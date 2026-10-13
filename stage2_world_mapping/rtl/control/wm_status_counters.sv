// Verification / report counters. Pure accumulation of strobes from the
// datapath; no influence on behaviour.
module wm_status_counters
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  input  logic        init_done,
  input  logic        mapper_ce,
  // unpacker / dispatch
  input  logic        word_loaded,
  input  logic [4:0]  events_loaded,
  input  logic [4:0]  events_dropped,
  input  logic [1:0]  events_issued,
  input  logic        grid_wait,
  input  logic [1:0]  node_reads,
  input  logic [1:0]  node_reuses,
  // mapper output
  input  logic [1:0]  events_mapped,
  // router
  input  logic        rt_accept,
  input  rec_t        r0,
  input  rec_t        r1,
  input  logic        conflict,
  input  logic        same_word,
  // banks
  input  logic [NUM_BANKS-1:0] rmw,
  input  logic [NUM_BANKS*5-1:0] rmw_events,
  input  logic [NUM_BANKS-1:0] bypass,
  input  logic [NUM_BANKS*8-1:0] sat_on,
  input  logic [NUM_BANKS*8-1:0] sat_off,
  // high-water marks (already maxima)
  input  logic [31:0] fifo_max_occ,
  input  logic [31:0] outbuf_max_occ,
  input  logic [31:0] bq_max_occ,
  output status_t     st
);
  logic [31:0] n_rec, n_merged, n_ev_rec, n_rmw, n_app, n_byp, n_son, n_soff;
  always_comb begin
    n_rec = 0; n_merged = 0; n_ev_rec = 0;
    if (rt_accept) begin
      if (r0.v) begin n_rec += 1; n_ev_rec += 32'(r0.n); if (r0.n >= 5'd2) n_merged += 1; end
      if (r1.v) begin n_rec += 1; n_ev_rec += 32'(r1.n); if (r1.n >= 5'd2) n_merged += 1; end
    end
    n_rmw = 0; n_app = 0; n_byp = 0; n_son = 0; n_soff = 0;
    for (int b = 0; b < NUM_BANKS; b++) begin
      n_rmw  += 32'(rmw[b]);
      n_app  += 32'(rmw_events[b*5 +: 5]);
      n_byp  += 32'(bypass[b]);
      n_son  += 32'(sat_on[b*8 +: 8]);
      n_soff += 32'(sat_off[b*8 +: 8]);
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      st <= '0;
    end else begin
      if (init_done) st.cycles <= st.cycles + 1;
      if (word_loaded) st.words_accepted <= st.words_accepted + 1;
      st.events_accepted   <= st.events_accepted + 32'(events_loaded);
      st.dropped_events    <= st.dropped_events + 32'(events_dropped);
      if (mapper_ce) begin
        st.events_issued <= st.events_issued + 32'(events_issued);
        if (events_issued != 2'd0) st.issue_cycles <= st.issue_cycles + 1;
        st.node_reads    <= st.node_reads + 32'(node_reads);
        st.node_reuses   <= st.node_reuses + 32'(node_reuses);
        st.events_mapped <= st.events_mapped + 32'(events_mapped);
      end else begin
        st.stall_cycles <= st.stall_cycles + 1;
      end
      if (grid_wait) st.grid_wait_cycles <= st.grid_wait_cycles + 1;
      st.rmw_requests      <= st.rmw_requests + n_rec;
      st.merge_count       <= st.merge_count + n_merged;
      st.events_in_records <= st.events_in_records + n_ev_rec;
      if (conflict)  st.bank_conflicts  <= st.bank_conflicts + 1;
      if (same_word) st.same_word_pairs <= st.same_word_pairs + 1;
      st.rmw_done       <= st.rmw_done + n_rmw;
      st.events_applied <= st.events_applied + n_app;
      st.bypass_count   <= st.bypass_count + n_byp;
      st.sat_loss_on    <= st.sat_loss_on + n_son;
      st.sat_loss_off   <= st.sat_loss_off + n_soff;
      st.fifo_max_occ   <= fifo_max_occ;
      st.outbuf_max_occ <= outbuf_max_occ;
      st.bq_max_occ     <= bq_max_occ;
    end
  end
endmodule
