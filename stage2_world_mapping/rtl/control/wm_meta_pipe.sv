// Metadata delay line aligned with the Codex numeric lane: LAT stages, shifting
// only on enabled edges (ce), exactly like the lane's internal valid pipeline.
// The metadata captured with lane valid_in on enabled edge k appears at meta_out
// together with the lane's valid_out after LAT enabled edges.
module wm_meta_pipe #(
  parameter integer W   = 32,
  parameter integer LAT = 52
) (
  input  logic         clk,
  input  logic         rst,
  input  logic         ce,
  input  logic [W-1:0] meta_in,
  output logic [W-1:0] meta_out
);
  logic [W-1:0] pipe [0:LAT-1];

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < LAT; i++) pipe[i] <= '0;
    end else if (ce) begin
      pipe[0] <= meta_in;
      for (int i = 1; i < LAT; i++) pipe[i] <= pipe[i-1];
    end
  end

  assign meta_out = pipe[LAT-1];
endmodule
