// One world-memory bank controller: request queue (two enqueue ports, one
// dequeue port) + in-order read-modify-write pipeline + RAW bypass.
//
// Memory model contract (wm_world_mem_model): a read issued on an enabled
// cycle returns the word as of the start of that cycle, RD_LAT enabled cycles
// later; a write is visible to reads issued on a later cycle.
// RAW: a record's read can miss at most the writes performed between its read
// issue and its own modify stage, i.e. the last RD_LAT writes. A history of the
// last RD_LAT writes (youngest wins) therefore always yields the newest value.
// Saturation: per-cell ON/OFF counters saturate independently at 2^CNT-1.
// Init: after reset (or clear_req) every word is written to zero, one word per
// cycle (512 cycles for 512 words); no requests are served until init_done.
module wm_bank_update_ctrl
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
#(
  parameter integer BQ_DEPTH = 4,
  parameter integer RD_LAT   = 1,
  parameter integer CW       = $clog2(BQ_DEPTH + 1)
) (
  input  logic                         clk,
  input  logic                         rst,
  input  logic                         hold,        // memory not ready (test hook)
  input  logic                         clear_req,
  // enqueue
  input  rec_t                         r0,
  input  rec_t                         r1,
  input  logic                         enq0,
  input  logic                         enq1,
  output logic [CW-1:0]                free,
  // memory port
  output logic                         mem_en,
  output logic                         rd_en,
  output logic [TILE_WORD_ADDR_W-1:0]  rd_addr,
  input  logic [TILE_WORD_W-1:0]       rd_data,
  output logic                         wr_en,
  output logic [TILE_WORD_ADDR_W-1:0]  wr_addr,
  output logic [TILE_WORD_W-1:0]       wr_data,
  // status
  output logic                         init_done,
  output logic                         busy,
  output logic                         rmw,         // a modify/write happened
  output logic [4:0]                   rmw_events,  // events applied by it
  output logic                         bypass,      // it used forwarded data
  output logic [7:0]                   sat_on,      // contributions lost to ON saturation
  output logic [7:0]                   sat_off,
  output logic [CW-1:0]                occ,
  output logic [CW-1:0]                max_occ
);
  localparam integer PW  = (BQ_DEPTH <= 1) ? 1 : $clog2(BQ_DEPTH);
  localparam integer MAXC = (1 << ON_COUNT_W) - 1;

  // ---------------- queue
  rec_t          q [0:BQ_DEPTH-1];
  logic [PW-1:0] wp, rp, w1;
  logic [CW-1:0] cnt;
  logic          pop;

  function automatic logic [PW-1:0] inc(input logic [PW-1:0] p);
    inc = (p == PW'(BQ_DEPTH - 1)) ? '0 : p + 1'b1;
  endfunction

  assign free = CW'(BQ_DEPTH) - cnt;
  assign occ  = cnt;
  assign w1   = enq0 ? inc(wp) : wp;

  // ---------------- RMW pipeline
  logic                        pv   [0:RD_LAT-1];
  rec_t                        prec [0:RD_LAT-1];
  logic                        hv   [0:RD_LAT-1];
  logic [TILE_WORD_ADDR_W-1:0] ha   [0:RD_LAT-1];
  logic [TILE_WORD_W-1:0]      hd   [0:RD_LAT-1];
  logic [TILE_WORD_ADDR_W:0]   init_cnt;
  logic                        en;

  assign init_done = init_cnt[TILE_WORD_ADDR_W];
  assign en        = !hold;
  assign mem_en    = en;
  assign pop       = en && init_done && (cnt != '0);
  assign rd_en     = pop;
  rec_t qh;                                   // queue head (Icarus: no member
  assign qh        = q[rp];                   // select on array-of-struct elements)
  assign rd_addr   = qh.waddr;

  rec_t                   m;
  logic                   mv;
  logic [TILE_WORD_W-1:0] base, nw;
  logic                   fwd;
  integer                 lost_on, lost_off, on_s, off_s;
  logic [CELLS*DELTA_W-1:0] mdon, mdoff;      // plain copies (Icarus part-select)

  always_comb begin
    m   = prec[RD_LAT-1];
    mv  = pv[RD_LAT-1] && en;
    base = rd_data;
    fwd  = 1'b0;
    // oldest .. youngest so the youngest match wins
    for (int h = RD_LAT - 1; h >= 0; h--) begin
      if (hv[h] && ha[h] == m.waddr) begin
        base = hd[h];
        fwd  = 1'b1;
      end
    end
    nw = base;
    mdon  = m.d_on;
    mdoff = m.d_off;
    lost_on = 0; lost_off = 0;
    for (int c = 0; c < CELLS; c++) begin
      on_s  = 32'(base[c*CELL_BITS + OFF_COUNT_W +: ON_COUNT_W]) + 32'(mdon[c*DELTA_W +: DELTA_W]);
      off_s = 32'(base[c*CELL_BITS +: OFF_COUNT_W]) + 32'(mdoff[c*DELTA_W +: DELTA_W]);
      if (on_s > MAXC)  begin lost_on  = lost_on  + on_s  - MAXC; on_s  = MAXC; end
      if (off_s > MAXC) begin lost_off = lost_off + off_s - MAXC; off_s = MAXC; end
      nw[c*CELL_BITS + OFF_COUNT_W +: ON_COUNT_W] = ON_COUNT_W'(on_s);
      nw[c*CELL_BITS +: OFF_COUNT_W]              = OFF_COUNT_W'(off_s);
    end
  end

  assign wr_en      = !init_done || mv;
  assign wr_addr    = !init_done ? init_cnt[TILE_WORD_ADDR_W-1:0] : m.waddr;
  assign wr_data    = !init_done ? '0 : nw;
  assign rmw        = init_done && mv;
  assign rmw_events = rmw ? m.n : 5'd0;
  assign bypass     = rmw && fwd;
  assign sat_on     = rmw ? 8'(lost_on)  : 8'd0;
  assign sat_off    = rmw ? 8'(lost_off) : 8'd0;

  logic pipe_busy;
  always_comb begin
    pipe_busy = 1'b0;
    for (int i = 0; i < RD_LAT; i++) pipe_busy = pipe_busy | pv[i];
  end
  assign busy = pipe_busy || (cnt != '0) || !init_done;

  always_ff @(posedge clk) begin
    if (rst) begin
      wp <= '0; rp <= '0; cnt <= '0; max_occ <= '0;
      init_cnt <= '0;
      for (int i = 0; i < RD_LAT; i++) begin
        pv[i] <= 1'b0; prec[i] <= '0; hv[i] <= 1'b0; ha[i] <= '0; hd[i] <= '0;
      end
    end else begin
      // queue
      if (enq0) q[wp] <= r0;
      if (enq1) q[w1] <= r1;
      wp  <= enq1 ? inc(w1) : w1;
      if (pop) rp <= inc(rp);
      cnt <= cnt + CW'(enq0) + CW'(enq1) - CW'(pop);
      if (cnt > max_occ) max_occ <= cnt;
      // init / clear sweep
      if (clear_req && !pipe_busy && cnt == '0)
        init_cnt <= '0;
      else if (!init_done)
        init_cnt <= init_cnt + 1'b1;
      // RMW pipeline and write history advance on enabled cycles
      if (en) begin
        pv[0]   <= pop;
        prec[0] <= qh;
        for (int i = 1; i < RD_LAT; i++) begin
          pv[i] <= pv[i-1]; prec[i] <= prec[i-1];
        end
        if (mv) begin
          hv[0] <= 1'b1; ha[0] <= m.waddr; hd[0] <= nw;
          for (int i = 1; i < RD_LAT; i++) begin
            hv[i] <= hv[i-1]; ha[i] <= ha[i-1]; hd[i] <= hd[i-1];
          end
        end
      end
      if (!init_done) begin
        for (int i = 0; i < RD_LAT; i++) hv[i] <= 1'b0;
      end
    end
  end

`ifndef SYNTHESIS
  always @(posedge clk)
    if (!rst && (CW'(enq0) + CW'(enq1)) > free)
      $fatal(1, "wm_bank_update_ctrl: queue overflow");
`endif
endmodule
