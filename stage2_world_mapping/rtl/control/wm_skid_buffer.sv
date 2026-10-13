// Mapper output buffer. Captures one two-lane mapped bundle per enabled cycle.
// The numeric lanes have no backpressure; mapper_ce is derived from this
// buffer's occupancy register (ce = !full), so the stall path is a flop compare,
// not a combinational chain from the merger/banks.
module wm_skid_buffer #(
  parameter integer W     = 2,
  parameter integer DEPTH = 4
) (
  input  logic         clk,
  input  logic         rst,
  input  logic         push,          // = mapper_ce && (lane0.v || lane1.v)
  input  logic [W-1:0] push_data,
  output logic         full,
  output logic         out_valid,
  input  logic         out_ready,
  output logic [W-1:0] out_data,
  output logic [$clog2(DEPTH+1)-1:0] occupancy,
  output logic [$clog2(DEPTH+1)-1:0] max_occupancy
);
  logic in_ready_unused, empty_unused;

  wm_input_fifo #(.W(W), .DEPTH(DEPTH)) u_fifo (
    .clk(clk), .rst(rst),
    .in_valid(push), .in_ready(in_ready_unused), .in_data(push_data),
    .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
    .occupancy(occupancy), .max_occupancy(max_occupancy),
    .full(full), .empty(empty_unused)
  );

`ifndef SYNTHESIS
  always @(posedge clk)
    if (!rst && push && full)
      $fatal(1, "wm_skid_buffer overflow: mapper_ce must be 0 when full");
`endif
endmodule
