// D stage: registers the issued two-event bundle and binds every event to the
// grid buffer that is active at issue time (gsel). Lane 0 always receives the
// first event; lane 1 is valid only when a second event was issued.
// Both lanes advance together on adv (= mapper_ce); no lane stalls alone.
module wm_lane_dispatch
  import wm_ctrl_pkg::*;
(
  input  logic  clk,
  input  logic  rst,
  input  logic  adv,
  input  meta_t e0,
  input  meta_t e1,
  input  logic  active_gsel,
  output meta_t d0,
  output meta_t d1,
  output logic  d0_gsel,
  output logic  d1_gsel
);
  always_ff @(posedge clk) begin
    if (rst) begin
      d0 <= '0; d1 <= '0; d0_gsel <= 1'b0; d1_gsel <= 1'b0;
    end else if (adv) begin
      d0 <= e0; d1 <= e1;
      d0_gsel <= active_gsel;
      d1_gsel <= active_gsel;
    end
  end

`ifndef SYNTHESIS
  always @(posedge clk)
    if (!rst && adv && e1.v && !e0.v)
      $fatal(1, "wm_lane_dispatch: lane1 valid without lane0");
`endif
endmodule
