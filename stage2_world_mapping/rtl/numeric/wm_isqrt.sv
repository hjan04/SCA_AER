// Exact restoring integer square root, digit-by-digit (two input bits/stage).
// 56-bit unsigned radicand -> floor(sqrt(n)), 28-bit result.
// Latency: 28 enabled clock edges. Initiation interval: 1. ce stalls all stages.
module wm_isqrt (
  input  logic        clk,
  input  logic        rst,
  input  logic        ce,
  input  logic        valid_in,
  input  logic [55:0] radicand_in,
  output logic        valid_out,
  output logic [27:0] root_out
);
  logic [55:0] rad_pipe [0:27];
  logic [29:0] rem_pipe [0:27];
  logic [27:0] root_pipe [0:27];
  logic        valid_pipe [0:27];

  logic [29:0] rem_next [0:27];
  logic [27:0] root_next [0:27];
  logic [29:0] trial [0:27];
  logic [29:0] rem_shifted [0:27];
  logic [55:0] radicand_clean;

  assign radicand_clean = valid_in ? radicand_in : 56'd0;

  genvar i;
  generate
    for (i=0; i<28; i=i+1) begin: gen_sqrt_stage
      if (i == 0) begin: gen_first
        always @* begin
          rem_shifted[i] = {28'b0,radicand_clean[55:54]};
          trial[i] = 30'd1;
          if (rem_shifted[i] >= trial[i]) begin
            rem_next[i] = rem_shifted[i] - trial[i];
            root_next[i] = 28'd1;
          end else begin
            rem_next[i] = rem_shifted[i];
            root_next[i] = 28'd0;
          end
        end
        always_ff @(posedge clk) begin
          if (rst) begin
            rad_pipe[i] <= '0;
            rem_pipe[i] <= '0;
            root_pipe[i] <= '0;
            valid_pipe[i] <= 1'b0;
          end else if (ce) begin
            rad_pipe[i] <= {radicand_clean[53:0],2'b00};
            rem_pipe[i] <= rem_next[i];
            root_pipe[i] <= root_next[i];
            valid_pipe[i] <= valid_in;
          end
        end
      end else begin: gen_rest
        always @* begin
          rem_shifted[i] = (rem_pipe[i-1] << 2) | {28'b0,rad_pipe[i-1][55:54]};
          trial[i] = ({2'b0,root_pipe[i-1]} << 2) | 30'd1;
          if (rem_shifted[i] >= trial[i]) begin
            rem_next[i] = rem_shifted[i] - trial[i];
            root_next[i] = (root_pipe[i-1] << 1) | 28'd1;
          end else begin
            rem_next[i] = rem_shifted[i];
            root_next[i] = root_pipe[i-1] << 1;
          end
        end
        always_ff @(posedge clk) begin
          if (rst) begin
            rad_pipe[i] <= '0;
            rem_pipe[i] <= '0;
            root_pipe[i] <= '0;
            valid_pipe[i] <= 1'b0;
          end else if (ce) begin
            rad_pipe[i] <= {rad_pipe[i-1][53:0],2'b00};
            rem_pipe[i] <= rem_next[i];
            root_pipe[i] <= root_next[i];
            valid_pipe[i] <= valid_pipe[i-1];
          end
        end
      end
    end
  endgenerate

  assign root_out = root_pipe[27];
  assign valid_out = valid_pipe[27];
endmodule
