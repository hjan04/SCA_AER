// System-level self-checking testbench (Claude-owned).
// Two complete DUTs run the same scenario: D2 (MERGE_EN=0) and E-lite
// (MERGE_EN=1). Each harness checks, against the Python golden files:
//   * every mapped event, in issue order: world_addr + carried (x, y)
//     (proves metadata alignment across the 52-enabled-edge lanes)
//   * counters: accepted / dropped / issued / mapped / RMW records / merges /
//     issue cycles / applied events
//   * final world memory (all 2048 tile words) and saturation accounting
//   * event conservation: sum(memory ON+OFF) + saturation loss == accepted
// The top then requires the two final memories to be BIT IDENTICAL.
// Plusargs: +DIR=<scenario dir> +STALL=0..3 +HOLD=0/1 +GAP=0/1 +CLEAR=0/1 +SEED=n
`ifndef FIFO_DEPTH
`define FIFO_DEPTH 128
`endif
`ifndef RD_LAT
`define RD_LAT 1
`endif
`ifndef BQ_DEPTH
`define BQ_DEPTH 4
`endif
`ifdef REUSE_OFF
`define REUSE_EN 1'b0
`else
`define REUSE_EN 1'b1
`endif

module sys_harness
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
#(
  parameter bit MERGE_EN = 1'b1,
  parameter string TAG = "E-lite"
) (
  input  logic clk,
  output logic done,
  output logic fail
);
  // ------------------------------------------------------------ DUT
  logic        rst;
  logic        in_valid, in_ready;
  nword_t      in_word;
  logic        gw_valid, gw_ready, gc_valid, gc_ready;
  logic [9:0]  gw_node_idx;
  ray3_t       gw_node;
  logic [7:0]  gc_epoch;
  logic        ext_stall, clear_req;
  logic [3:0]  bank_hold;
  logic        mapper_ce, init_done, banks_idle, grid_load_err;
  status_t     st;

  wm_world_mapper_top #(
    .MERGE_EN(MERGE_EN), .REUSE_EN(`REUSE_EN), .FIFO_DEPTH(`FIFO_DEPTH), .BQ_DEPTH(`BQ_DEPTH), .RD_LAT(`RD_LAT)
  ) dut (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_ready(in_ready), .in_word(in_word),
    .gw_valid(gw_valid), .gw_ready(gw_ready), .gw_node_idx(gw_node_idx), .gw_node(gw_node),
    .gc_valid(gc_valid), .gc_ready(gc_ready), .gc_epoch(gc_epoch),
    .ext_stall(ext_stall), .bank_hold(bank_hold), .clear_req(clear_req),
    .mapper_ce(mapper_ce), .init_done(init_done), .banks_idle(banks_idle),
    .grid_load_err(grid_load_err), .status(st)
  );

  // ------------------------------------------------------------ stimulus files
  string dir;
  integer stall_mode, hold_mode, gap_mode, clear_mode, seed;
  logic [51:0]  words  [0:65535];
  logic [47:0]  grids  [0:16383];
  logic [34:0]  expev  [0:131071];
  logic [127:0] expmem [0:2047];
  logic [127:0] final_mem [0:2047];   // DUT memory snapshot after drain (before clear)
  integer epoch_of [0:63];
  integer partial_of [0:63];
  integer n_frames;
  integer x_words, x_events, x_dropped, x_el_rec, x_el_merged, x_d2_rec, x_sat, x_issue, x_frames;

  function automatic logic [127:0] memword(input integer b, input integer w);
    case (b)
      0: memword = dut.g_bank[0].u_mem.mem[w];
      1: memword = dut.g_bank[1].u_mem.mem[w];
      2: memword = dut.g_bank[2].u_mem.mem[w];
      default: memword = dut.g_bank[3].u_mem.mem[w];
    endcase
  endfunction

  integer errors;
  task automatic err(input string s);
    begin
      errors = errors + 1;
      if (errors < 20) $display("[%s] ERROR: %s", TAG, s);
    end
  endtask

  initial begin
    integer fd, e, p, r;
    errors = 0; done = 0; fail = 0;
    if (!$value$plusargs("DIR=%s", dir)) $fatal(1, "missing +DIR");
    if (!$value$plusargs("STALL=%d", stall_mode)) stall_mode = 0;
    if (!$value$plusargs("HOLD=%d", hold_mode)) hold_mode = 0;
    if (!$value$plusargs("GAP=%d", gap_mode)) gap_mode = 0;
    if (!$value$plusargs("CLEAR=%d", clear_mode)) clear_mode = 0;
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
    $readmemh({dir, "/words.hex"}, words);
    $readmemh({dir, "/grids.hex"}, grids);
    $readmemh({dir, "/exp_events.hex"}, expev);
    $readmemh({dir, "/exp_mem.hex"}, expmem);
    fd = $fopen({dir, "/expect.txt"}, "r");
    r = $fscanf(fd, "words=%d\n", x_words);
    r = $fscanf(fd, "events=%d\n", x_events);
    r = $fscanf(fd, "dropped=%d\n", x_dropped);
    r = $fscanf(fd, "elite_records=%d\n", x_el_rec);
    r = $fscanf(fd, "elite_merged=%d\n", x_el_merged);
    r = $fscanf(fd, "d2_records=%d\n", x_d2_rec);
    r = $fscanf(fd, "sat_loss=%d\n", x_sat);
    r = $fscanf(fd, "issue_cycles=%d\n", x_issue);
    r = $fscanf(fd, "frames=%d\n", x_frames);
    $fclose(fd);
    fd = $fopen({dir, "/frames.txt"}, "r");
    n_frames = 0;
    while ($fscanf(fd, "%d %d\n", e, p) == 2) begin
      epoch_of[n_frames] = e; partial_of[n_frames] = p; n_frames = n_frames + 1;
    end
    $fclose(fd);
  end

  // ------------------------------------------------------------ reset, stall/hold patterns
  integer cyc;
  integer rnd;
  initial begin
    rst = 1; ext_stall = 0; bank_hold = 0; clear_req = 0; cyc = 0;
    repeat (5) @(posedge clk);
    @(negedge clk) rst = 0;
  end
  always @(negedge clk) begin
    cyc <= cyc + 1;
    rnd = $urandom;
    case (stall_mode)
      1: ext_stall <= ((cyc % 11) < 3);
      2: ext_stall <= (rnd % 100) < 40;
      3: ext_stall <= (rnd % 100) < 75;
      default: ext_stall <= 0;
    endcase
    if (hold_mode != 0) bank_hold <= {($urandom % 5) == 0, ($urandom % 5) == 0,
                                      ($urandom % 5) == 0, ($urandom % 5) == 0};
    else bank_hold <= 0;
  end

  // ------------------------------------------------------------ grid loader
  logic loader_done;
  integer pending_partial_epoch;     // -1 = none
  initial begin
    integer i, n;
    loader_done = 0; gw_valid = 0; gc_valid = 0; gw_node_idx = 0; gw_node = '0; gc_epoch = 0;
    pending_partial_epoch = -1;
    @(negedge rst);
    for (i = 0; i < n_frames; i = i + 1) begin
      if (partial_of[i] > 0) begin
        // partial load, then an attempted commit that must be refused
        pending_partial_epoch = epoch_of[i];
        for (n = 0; n < partial_of[i]; n = n + 1) begin
          @(negedge clk); gw_valid = 1; gw_node_idx = n; gw_node = grids[i*744 + n];
          @(posedge clk); while (!gw_ready) @(posedge clk);
        end
        @(negedge clk); gw_valid = 0; gc_valid = 1; gc_epoch = epoch_of[i];
        repeat (400) begin
          @(posedge clk);
          if (gc_ready) err($sformatf("partial grid (%0d nodes) accepted for commit", partial_of[i]));
        end
        @(negedge clk); gc_valid = 0;
        pending_partial_epoch = -1;
      end
      for (n = 0; n < 744; n = n + 1) begin
        @(negedge clk); gw_valid = 1; gw_node_idx = n; gw_node = grids[i*744 + n];
        @(posedge clk); while (!gw_ready) @(posedge clk);
      end
      @(negedge clk); gw_valid = 0; gc_valid = 1; gc_epoch = epoch_of[i];
      @(posedge clk); while (!gc_ready) @(posedge clk);
      @(negedge clk); gc_valid = 0;
    end
    loader_done = 1;
  end

  // events of a frame whose grid is only partially loaded must never issue
  always @(posedge clk) begin
    if (!rst && pending_partial_epoch >= 0) begin
      if (dut.e0.v && mapper_ce && dut.e0.frame == pending_partial_epoch[7:0])
        err("event issued against a partially loaded grid");
    end
  end

  // ------------------------------------------------------------ word feeder
  logic feeder_done;
  initial begin
    integer i;
    feeder_done = 0; in_valid = 0; in_word = '0;
    @(negedge rst);
    for (i = 0; i < x_words; i = i + 1) begin
      @(negedge clk);
      if (gap_mode != 0) while (($urandom % 4) == 0) begin in_valid = 0; @(negedge clk); end
      in_valid = 1; in_word = words[i];
      @(posedge clk); while (!in_ready) @(posedge clk);
    end
    @(negedge clk); in_valid = 0;
    feeder_done = 1;
  end

  // ------------------------------------------------------------ mapped-event checker
  integer k;
  initial k = 0;
  always @(posedge clk) begin
    if (!rst && dut.ob_push) begin
      if (dut.m0.v) begin
        if ({dut.m0.world_addr, dut.m0.x, dut.m0.y} !== expev[k])
          err($sformatf("event %0d lane0 got addr %0d (x%0d,y%0d) exp addr %0d (x%0d,y%0d)", k,
              dut.m0.world_addr, dut.m0.x, dut.m0.y, expev[k][34:20], expev[k][19:10], expev[k][9:0]));
        k = k + 1;
      end
      if (dut.m1.v) begin
        if ({dut.m1.world_addr, dut.m1.x, dut.m1.y} !== expev[k])
          err($sformatf("event %0d lane1 got addr %0d exp addr %0d", k,
              dut.m1.world_addr, expev[k][34:20]));
        k = k + 1;
      end
    end
  end

  // ------------------------------------------------------------ completion + checks
  initial begin
    integer b, w, c, timeout;
    longint sum_mem;
    logic [127:0] mw;
    @(negedge rst);
    timeout = 0;
    while (!(loader_done && feeder_done && st.events_applied == x_events &&
             banks_idle && dut.inflight == 0 && !dut.ob_valid && !dut.fifo_valid)) begin
      @(posedge clk);
      timeout = timeout + 1;
      if (timeout > 5_000_000) begin err("timeout waiting for drain"); break; end
    end
    repeat (20) @(posedge clk);

    if (k != x_events) err($sformatf("observed %0d mapped events, expected %0d", k, x_events));
    if (st.words_accepted  != x_words)   err("words_accepted mismatch");
    if (st.events_accepted != x_events)  err($sformatf("events_accepted %0d exp %0d", st.events_accepted, x_events));
    if (st.dropped_events  != x_dropped) err($sformatf("dropped %0d exp %0d", st.dropped_events, x_dropped));
    if (st.events_issued   != x_events)  err("events_issued mismatch");
    if (st.events_mapped   != x_events)  err("events_mapped mismatch");
    if (st.issue_cycles    != x_issue)   err($sformatf("issue_cycles %0d exp %0d", st.issue_cycles, x_issue));
    if (st.rmw_requests != (MERGE_EN ? x_el_rec : x_d2_rec))
      err($sformatf("rmw_requests %0d exp %0d", st.rmw_requests, MERGE_EN ? x_el_rec : x_d2_rec));
    if (st.merge_count != (MERGE_EN ? x_el_merged : 0))
      err($sformatf("merge_count %0d exp %0d", st.merge_count, MERGE_EN ? x_el_merged : 0));
    if (st.events_in_records != x_events) err("events_in_records mismatch");
    if (st.rmw_done != st.rmw_requests)   err("rmw_done != rmw_requests");
    if (st.events_applied != x_events)    err("events_applied mismatch");
    if (st.sat_loss_on + st.sat_loss_off != x_sat)
      err($sformatf("saturation loss %0d exp %0d", st.sat_loss_on + st.sat_loss_off, x_sat));
    if (grid_load_err) err("grid_load_err set");

    sum_mem = 0;
    for (b = 0; b < 4; b = b + 1)
      for (w = 0; w < 512; w = w + 1) begin
        mw = memword(b, w);
        final_mem[b*512 + w] = mw;
        if (mw !== expmem[b*512 + w])
          err($sformatf("memory bank %0d word %0d got %h exp %h", b, w, mw, expmem[b*512 + w]));
        for (c = 0; c < 16; c = c + 1) sum_mem = sum_mem + mw[8*c+4 +: 4] + mw[8*c +: 4];
      end
    // conservation: accepted = accumulated + saturated-away + dropped(0 valid) + pending(0)
    if (sum_mem + st.sat_loss_on + st.sat_loss_off != st.events_accepted)
      err($sformatf("conservation: mem %0d + sat %0d != accepted %0d",
          sum_mem, st.sat_loss_on + st.sat_loss_off, st.events_accepted));

    $display("[%s] %s: events=%0d words=%0d dropped=%0d | records=%0d merged=%0d (RMW/event %.3f) | cycles=%0d stall=%0d issue_cyc=%0d eff=%.3f | conflicts=%0d same_word=%0d bypass=%0d | fifo_max=%0d outbuf_max=%0d bq_max=%0d | node_reads=%0d reuse=%0d grid_wait=%0d | sat=%0d",
      TAG, dir, st.events_accepted, st.words_accepted, st.dropped_events,
      st.rmw_requests, st.merge_count, (x_events > 0) ? real'(st.rmw_requests) / x_events : 0.0,
      st.cycles, st.stall_cycles, st.issue_cycles,
      (st.issue_cycles > 0) ? real'(st.events_issued) / (2.0 * st.issue_cycles) : 0.0,
      st.bank_conflicts, st.same_word_pairs, st.bypass_count,
      st.fifo_max_occ, st.outbuf_max_occ, st.bq_max_occ,
      st.node_reads, st.node_reuses, st.grid_wait_cycles, st.sat_loss_on + st.sat_loss_off);

    if (clear_mode != 0) begin
      @(negedge clk) clear_req = 1;
      @(negedge clk) clear_req = 0;
      @(posedge clk);
      if (init_done) err("init_done did not drop after clear_req");
      timeout = 0;
      while (!init_done && timeout < 2000) begin @(posedge clk); timeout = timeout + 1; end
      if (timeout != 512) err($sformatf("clear sweep took %0d cycles (expected 512)", timeout));
      repeat (2) @(posedge clk);
      for (b = 0; b < 4; b = b + 1)
        for (w = 0; w < 512; w = w + 1)
          if (memword(b, w) !== '0) err($sformatf("memory not cleared at bank %0d word %0d", b, w));
      $display("[%s] clear sweep: %0d cycles, all 2048 words zero", TAG, timeout);
    end

    fail = (errors != 0);
    done = 1;
  end
endmodule

module tb_system;
  logic clk = 0;
  always #5 clk = ~clk;
  logic d2_done, d2_fail, el_done, el_fail;

  sys_harness #(.MERGE_EN(1'b0), .TAG("D2"))     h_d2 (.clk(clk), .done(d2_done), .fail(d2_fail));
  sys_harness #(.MERGE_EN(1'b1), .TAG("E-lite")) h_el (.clk(clk), .done(el_done), .fail(el_fail));

  initial begin
    integer b, w, diff;
    wait (d2_done && el_done);
    diff = 0;
    // final maps before any clear test (clear runs after the first compare)
    for (b = 0; b < 4; b = b + 1)
      for (w = 0; w < 512; w = w + 1)
        if (h_d2.final_mem[b*512+w] !== h_el.final_mem[b*512+w]) diff = diff + 1;
    if (d2_fail || el_fail || diff != 0) begin
      $display("TB_RESULT FAIL d2_fail=%0d el_fail=%0d d2_vs_elite_word_diffs=%0d", d2_fail, el_fail, diff);
      $finish;
    end
    $display("TB_RESULT PASS (D2 vs E-lite final maps: 2048/2048 tile words bit-identical; both equal golden)");
    $finish;
  end
endmodule
