// Stage 2 V1 world mapper top (Claude control + Codex numeric lanes).
//
// native word -> FIFO -> unpacker (<=2 events/cycle) -> D stage (grid bind)
//   -> L stage (node fetch + reuse) -> 2 x wm_mapper_lane (52 enabled edges)
//      + aligned metadata pipes -> mapper output buffer -> E-lite merger
//   -> 4-bank router -> 4 x bank RMW controller -> 4 x world memory model
//
// One global enable, mapper_ce, advances the unpacker issue, the D and L
// stages, both numeric lanes and both metadata pipes together. It drops when
// the mapper output buffer is full (or ext_stall, a test hook). The numeric
// lanes have no ready/valid network and are never stalled individually.
// Reset: active-high synchronous (same as the Codex numeric RTL).
module wm_world_mapper_top
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
#(
  parameter bit     MERGE_EN     = 1'b1,
  parameter bit     REUSE_EN     = 1'b1,
  parameter integer FIFO_DEPTH   = 128,
  parameter integer OUTBUF_DEPTH = 4,
  parameter integer BQ_DEPTH     = 4,
  parameter integer RD_LAT       = 1
) (
  input  logic                        clk,
  input  logic                        rst,
  // native-word input
  input  logic                        in_valid,
  output logic                        in_ready,
  input  nword_t                      in_word,
  // grid load / commit
  input  logic                        gw_valid,
  output logic                        gw_ready,
  input  logic [GRID_NODE_IDX_W-1:0]  gw_node_idx,
  input  ray3_t                       gw_node,
  input  logic                        gc_valid,
  output logic                        gc_ready,
  input  logic [FRAME_ID_W-1:0]       gc_epoch,
  // test hooks / control
  input  logic                        ext_stall,
  input  logic [NUM_BANKS-1:0]        bank_hold,
  input  logic                        clear_req,
  // status
  output logic                        mapper_ce,
  output logic                        init_done,
  output logic                        banks_idle,
  output logic                        grid_load_err,
  output status_t                     status
);
  localparam integer BQ_CW = $clog2(BQ_DEPTH + 1);
  localparam integer FCW   = $clog2(FIFO_DEPTH + 1);
  localparam integer OCW   = $clog2(OUTBUF_DEPTH + 1);

  // ---------------------------------------------------------------- FIFO
  nword_t           fifo_q;
  logic             fifo_valid, fifo_pop, fifo_full, fifo_empty;
  logic [FCW-1:0]   fifo_occ, fifo_max;

  wm_input_fifo #(.W($bits(nword_t)), .DEPTH(FIFO_DEPTH)) u_fifo (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_ready(in_ready), .in_data(in_word),
    .out_valid(fifo_valid), .out_ready(fifo_pop), .out_data(fifo_q),
    .occupancy(fifo_occ), .max_occupancy(fifo_max),
    .full(fifo_full), .empty(fifo_empty)
  );

  // ---------------------------------------------------------------- frame ctrl
  logic load_allow, active_gsel, held_valid, inv_valid, inv_sel, grid_wait;
  logic st_we, st_wsel;
  logic [4:0] st_wgx, st_wgy;
  ray3_t st_wnode;
  logic [FRAME_ID_W-1:0] held_frame;
  logic [31:0] swaps, commits;
  meta_t d0, d1;
  logic  d0_gsel, d1_gsel;

  wm_frame_ctrl u_frame (
    .clk(clk), .rst(rst),
    .gw_valid(gw_valid), .gw_ready(gw_ready), .gw_node_idx(gw_node_idx), .gw_node(gw_node),
    .gc_valid(gc_valid), .gc_ready(gc_ready), .gc_epoch(gc_epoch),
    .st_we(st_we), .st_wsel(st_wsel), .st_wgx(st_wgx), .st_wgy(st_wgy), .st_wnode(st_wnode),
    .head_valid(fifo_valid), .head_frame(fifo_q.frame), .held_valid(held_valid),
    .load_allow(load_allow), .active_gsel(active_gsel),
    .d0_v(d0.v), .d0_gsel(d0_gsel), .d1_v(d1.v), .d1_gsel(d1_gsel),
    .inv_valid(inv_valid), .inv_sel(inv_sel),
    .grid_wait(grid_wait), .grid_load_err(grid_load_err),
    .swaps(swaps), .commits(commits)
  );

  // ---------------------------------------------------------------- unpack + dispatch
  logic        outbuf_full;
  meta_t       e0, e1;
  logic        word_loaded;
  logic [4:0]  events_loaded, events_dropped;
  logic [1:0]  events_issued;

  assign mapper_ce = !outbuf_full && !ext_stall;

  wm_word_unpacker u_unpack (
    .clk(clk), .rst(rst),
    .fifo_valid(fifo_valid), .fifo_data(fifo_q), .fifo_pop(fifo_pop),
    .load_allow(load_allow), .adv(mapper_ce),
    .e0(e0), .e1(e1), .held_valid(held_valid), .held_frame(held_frame),
    .word_loaded(word_loaded), .events_loaded(events_loaded),
    .events_dropped(events_dropped), .events_issued(events_issued)
  );

  wm_lane_dispatch u_dispatch (
    .clk(clk), .rst(rst), .adv(mapper_ce), .e0(e0), .e1(e1),
    .active_gsel(active_gsel), .d0(d0), .d1(d1), .d0_gsel(d0_gsel), .d1_gsel(d1_gsel)
  );

  // ---------------------------------------------------------------- grid + reuse (L stage)
  logic        rsel0, rsel1;
  logic [4:0]  rgx0, rgy0, rgx1, rgy1;
  ray3_t       g00_0, g10_0, g01_0, g11_0, g00_1, g10_1, g01_1, g11_1;
  logic        l0_valid, l1_valid;
  ray3_t       l0_n00, l0_n10, l0_n01, l0_n11, l1_n00, l1_n10, l1_n01, l1_n11;
  logic [4:0]  l0_ox, l0_oy, l1_ox, l1_oy;
  meta_t       l0_meta, l1_meta;
  logic [1:0]  node_reads, node_reuses;

  wm_grid_store u_grid (
    .clk(clk),
    .we(st_we), .wsel(st_wsel), .wgx(st_wgx), .wgy(st_wgy), .wnode(st_wnode),
    .rsel0(rsel0), .rgx0(rgx0), .rgy0(rgy0),
    .n00_0(g00_0), .n10_0(g10_0), .n01_0(g01_0), .n11_0(g11_0),
    .rsel1(rsel1), .rgx1(rgx1), .rgy1(rgy1),
    .n00_1(g00_1), .n10_1(g10_1), .n01_1(g01_1), .n11_1(g11_1)
  );

  wm_reuse_cache u_reuse (
    .clk(clk), .rst(rst), .adv(mapper_ce), .reuse_en(REUSE_EN),
    .d0(d0), .d1(d1), .d0_gsel(d0_gsel), .d1_gsel(d1_gsel),
    .rsel0(rsel0), .rsel1(rsel1), .rgx0(rgx0), .rgy0(rgy0), .rgx1(rgx1), .rgy1(rgy1),
    .g00_0(g00_0), .g10_0(g10_0), .g01_0(g01_0), .g11_0(g11_0),
    .g00_1(g00_1), .g10_1(g10_1), .g01_1(g01_1), .g11_1(g11_1),
    .inv_valid(inv_valid), .inv_sel(inv_sel),
    .l0_valid(l0_valid), .l1_valid(l1_valid),
    .l0_n00(l0_n00), .l0_n10(l0_n10), .l0_n01(l0_n01), .l0_n11(l0_n11),
    .l1_n00(l1_n00), .l1_n10(l1_n10), .l1_n01(l1_n01), .l1_n11(l1_n11),
    .l0_ox(l0_ox), .l0_oy(l0_oy), .l1_ox(l1_ox), .l1_oy(l1_oy),
    .l0_meta(l0_meta), .l1_meta(l1_meta),
    .reads(node_reads), .reuses(node_reuses)
  );

  // ---------------------------------------------------------------- numeric lanes (Codex, read-only)
  logic              v_out0, v_out1;
  logic [7:0]        wx0, wx1;
  logic [6:0]        wy0, wy1;
  logic [14:0]       wa0, wa1;
  meta_t             mo0, mo1;

  wm_mapper_lane u_lane0 (
    .clk(clk), .rst(rst), .ce(mapper_ce), .valid_in(l0_valid),
    .node00(l0_n00), .node10(l0_n10), .node01(l0_n01), .node11(l0_n11),
    .x_offset(l0_ox), .y_offset(l0_oy),
    .valid_out(v_out0), .world_x(wx0), .world_y(wy0), .world_addr(wa0)
  );
  wm_mapper_lane u_lane1 (
    .clk(clk), .rst(rst), .ce(mapper_ce), .valid_in(l1_valid),
    .node00(l1_n00), .node10(l1_n10), .node01(l1_n01), .node11(l1_n11),
    .x_offset(l1_ox), .y_offset(l1_oy),
    .valid_out(v_out1), .world_x(wx1), .world_y(wy1), .world_addr(wa1)
  );

  wm_meta_pipe #(.W($bits(meta_t)), .LAT(LANE_LAT)) u_meta0 (
    .clk(clk), .rst(rst), .ce(mapper_ce), .meta_in(l0_meta), .meta_out(mo0));
  wm_meta_pipe #(.W($bits(meta_t)), .LAT(LANE_LAT)) u_meta1 (
    .clk(clk), .rst(rst), .ce(mapper_ce), .meta_in(l1_meta), .meta_out(mo1));

  // ---------------------------------------------------------------- mapped bundle
  mapped_t m0, m1;
  always_comb begin
    m0 = '0; m1 = '0;
    m0.v = v_out0; m0.bank = bank_of(wx0, wy0); m0.waddr = waddr_of(wx0, wy0);
    m0.cofs = cell_of(wx0, wy0); m0.pol = mo0.pol; m0.grp = mo0.grp; m0.frame = mo0.frame;
    m0.world_addr = wa0; m0.x = mo0.x; m0.y = mo0.y;
    m1.v = v_out1; m1.bank = bank_of(wx1, wy1); m1.waddr = waddr_of(wx1, wy1);
    m1.cofs = cell_of(wx1, wy1); m1.pol = mo1.pol; m1.grp = mo1.grp; m1.frame = mo1.frame;
    m1.world_addr = wa1; m1.x = mo1.x; m1.y = mo1.y;
  end

  logic                         ob_push, ob_valid, ob_pop;
  logic [2*$bits(mapped_t)-1:0] ob_q;
  logic [OCW-1:0]               ob_occ, ob_max;
  mapped_t                      b0, b1;

  assign ob_push = mapper_ce && (v_out0 || v_out1);
  wm_skid_buffer #(.W(2*$bits(mapped_t)), .DEPTH(OUTBUF_DEPTH)) u_outbuf (
    .clk(clk), .rst(rst), .push(ob_push), .push_data({m1, m0}), .full(outbuf_full),
    .out_valid(ob_valid), .out_ready(ob_pop), .out_data(ob_q),
    .occupancy(ob_occ), .max_occupancy(ob_max)
  );
  assign {b1, b0} = ob_q;

  // ---------------------------------------------------------------- merger + router
  rec_t r0, r1;
  logic merger_ready, rt_accept, conflict, same_word;
  logic [NUM_BANKS-1:0]        enq0, enq1;
  logic [NUM_BANKS*BQ_CW-1:0]  bq_free;

  // events between issue and output-buffer capture (<= 2 x (2 + 52))
  logic [7:0] inflight;
  always_ff @(posedge clk) begin
    if (rst) inflight <= '0;
    else if (mapper_ce)
      inflight <= inflight + 8'(events_issued) - 8'({1'b0, v_out0} + {1'b0, v_out1});
  end
  logic flush_ok;
  assign flush_ok = !ob_valid && (inflight == '0) && !held_valid && !fifo_valid;

  wm_elite_merger #(.MERGE_EN(MERGE_EN)) u_merge (
    .clk(clk), .rst(rst), .in_valid(ob_valid), .in_ready(merger_ready),
    .e0(b0), .e1(b1), .r0(r0), .r1(r1), .rt_accept(rt_accept), .flush_ok(flush_ok)
  );
  assign ob_pop = ob_valid && merger_ready;

  wm_bank_router #(.CW(BQ_CW)) u_router (
    .r0(r0), .r1(r1), .bq_free(bq_free), .accept(rt_accept),
    .enq0(enq0), .enq1(enq1), .conflict(conflict), .same_word(same_word)
  );

  // ---------------------------------------------------------------- banks
  logic [NUM_BANKS-1:0]   b_init_done, b_busy, b_rmw, b_bypass;
  logic [NUM_BANKS*5-1:0] b_rmw_ev;
  logic [NUM_BANKS*8-1:0] b_sat_on, b_sat_off;
  logic [BQ_CW-1:0]       b_maxocc [0:NUM_BANKS-1];

  genvar gb;
  generate
    for (gb = 0; gb < NUM_BANKS; gb++) begin : g_bank
      logic                        mem_en, rd_en, wr_en;
      logic [TILE_WORD_ADDR_W-1:0] rd_addr, wr_addr;
      logic [TILE_WORD_W-1:0]      rd_data, wr_data;
      logic [BQ_CW-1:0]            occ;

      wm_bank_update_ctrl #(.BQ_DEPTH(BQ_DEPTH), .RD_LAT(RD_LAT), .CW(BQ_CW)) u_ctrl (
        .clk(clk), .rst(rst), .hold(bank_hold[gb]), .clear_req(clear_req),
        .r0(r0), .r1(r1), .enq0(enq0[gb]), .enq1(enq1[gb]),
        .free(bq_free[gb*BQ_CW +: BQ_CW]),
        .mem_en(mem_en), .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .init_done(b_init_done[gb]), .busy(b_busy[gb]),
        .rmw(b_rmw[gb]), .rmw_events(b_rmw_ev[gb*5 +: 5]), .bypass(b_bypass[gb]),
        .sat_on(b_sat_on[gb*8 +: 8]), .sat_off(b_sat_off[gb*8 +: 8]),
        .occ(occ), .max_occ(b_maxocc[gb])
      );

      wm_world_mem_model #(.RD_LAT(RD_LAT)) u_mem (
        .clk(clk), .en(mem_en), .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data)
      );
    end
  endgenerate

  assign init_done  = &b_init_done;
  assign banks_idle = ~|b_busy;

  logic [BQ_CW-1:0] bq_max;
  always_comb begin
    bq_max = '0;
    for (int b = 0; b < NUM_BANKS; b++) if (b_maxocc[b] > bq_max) bq_max = b_maxocc[b];
  end

  // ---------------------------------------------------------------- counters
  wm_status_counters u_status (
    .clk(clk), .rst(rst), .init_done(init_done), .mapper_ce(mapper_ce),
    .word_loaded(word_loaded), .events_loaded(events_loaded),
    .events_dropped(events_dropped), .events_issued(events_issued),
    .grid_wait(grid_wait), .node_reads(node_reads), .node_reuses(node_reuses),
    .events_mapped({1'b0, v_out0} + {1'b0, v_out1}),
    .rt_accept(rt_accept), .r0(r0), .r1(r1), .conflict(conflict), .same_word(same_word),
    .rmw(b_rmw), .rmw_events(b_rmw_ev), .bypass(b_bypass),
    .sat_on(b_sat_on), .sat_off(b_sat_off),
    .fifo_max_occ(32'(fifo_max)), .outbuf_max_occ(32'(ob_max)), .bq_max_occ(32'(bq_max)),
    .st(status)
  );

`ifndef SYNTHESIS
  // Metadata must stay exactly aligned with the 52-enabled-edge numeric lanes.
  always @(posedge clk) begin
    if (!rst) begin
      if (v_out0 !== mo0.v) $fatal(1, "metadata misalignment lane0 (lane %b meta %b)", v_out0, mo0.v);
      if (v_out1 !== mo1.v) $fatal(1, "metadata misalignment lane1 (lane %b meta %b)", v_out1, mo1.v);
      if (v_out1 && !v_out0) $fatal(1, "lane1 output without lane0 output");
    end
  end
`endif
endmodule
