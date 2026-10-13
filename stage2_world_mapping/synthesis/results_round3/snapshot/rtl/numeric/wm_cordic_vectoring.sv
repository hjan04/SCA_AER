// 24-stage, fully pipelined fixed-point vectoring atan2(y,x).
// Signed 32-bit Cartesian state and signed BAM32 result (full turn = 2^32).
// Latency 24 enabled edges; initiation interval 1. ce stalls all stages.
module wm_cordic_vectoring (
  input  logic clk,
  input  logic rst,
  input  logic ce,
  input  logic valid_in,
  input  logic signed [31:0] x_in,
  input  logic signed [31:0] y_in,
  output logic valid_out,
  output logic signed [31:0] angle_out
);
  function automatic logic signed [31:0] atan_bam32(input integer idx);
    begin
      case (idx)
         0: atan_bam32 = 32'sd536870912;
         1: atan_bam32 = 32'sd316933406;
         2: atan_bam32 = 32'sd167458907;
         3: atan_bam32 = 32'sd85004756;
         4: atan_bam32 = 32'sd42667331;
         5: atan_bam32 = 32'sd21354465;
         6: atan_bam32 = 32'sd10679838;
         7: atan_bam32 = 32'sd5340245;
         8: atan_bam32 = 32'sd2670163;
         9: atan_bam32 = 32'sd1335087;
        10: atan_bam32 = 32'sd667544;
        11: atan_bam32 = 32'sd333772;
        12: atan_bam32 = 32'sd166886;
        13: atan_bam32 = 32'sd83443;
        14: atan_bam32 = 32'sd41722;
        15: atan_bam32 = 32'sd20861;
        16: atan_bam32 = 32'sd10430;
        17: atan_bam32 = 32'sd5215;
        18: atan_bam32 = 32'sd2608;
        19: atan_bam32 = 32'sd1304;
        20: atan_bam32 = 32'sd652;
        21: atan_bam32 = 32'sd326;
        22: atan_bam32 = 32'sd163;
        23: atan_bam32 = 32'sd81;
        default: atan_bam32 = 32'sd0;
      endcase
    end
  endfunction

  logic signed [31:0] x_pipe [0:23];
  logic signed [31:0] y_pipe [0:23];
  logic signed [31:0] z_pipe [0:23];
  logic               axis_pipe [0:23];
  logic signed [31:0] x_next [0:23];
  logic signed [31:0] y_next [0:23];
  logic signed [31:0] z_next [0:23];
  logic               axis_next [0:23];
  logic               valid_pipe [0:23];
  logic signed [31:0] x_clean, y_clean;

  // Invalid-cycle data is forced to zero so it cannot spread X values.
  assign x_clean = valid_in ? x_in : 32'sd0;
  assign y_clean = valid_in ? y_in : 32'sd0;

  genvar g;
  generate
    for (g=0; g<24; g=g+1) begin: gen_cordic_stage
      if (g == 0) begin: gen_first
        logic signed [31:0] bx, by, bz;
        logic axis;
        always @* begin
          bx = x_clean;
          by = y_clean;
          bz = 32'sd0;
          axis = 1'b0;
          if (x_clean == 0) begin
            bx = 32'sd0; by = 32'sd0; axis = 1'b1;
            if (y_clean > 0) bz = 32'sd1073741824;
            else if (y_clean < 0) bz = -32'sd1073741824;
            else bz = 32'sd0;
          end else if (y_clean == 0) begin
            bx = 32'sd0; by = 32'sd0; axis = 1'b1;
            if (x_clean > 0) bz = 32'sd0;
            else bz = 32'sh80000000;
          end else if (x_clean < 0) begin
            // Exp05b half-turn pre-rotation, with signed 32-bit wrap.
            // +pi and -pi share the same signed BAM32 code (0x80000000).
            bz = 32'sh80000000;
            bx = -x_in;
            by = -y_in;
          end

          if (axis) begin
            x_next[g] = 32'sd0;
            y_next[g] = 32'sd0;
            z_next[g] = bz;
            axis_next[g] = 1'b1;
          end else if (by > 0) begin
            x_next[g] = bx + (by >>> 0);
            y_next[g] = by - (bx >>> 0);
            z_next[g] = bz + atan_bam32(0);
            axis_next[g] = 1'b0;
          end else if (by < 0) begin
            x_next[g] = bx - (by >>> 0);
            y_next[g] = by + (bx >>> 0);
            z_next[g] = bz - atan_bam32(0);
            axis_next[g] = 1'b0;
          end else begin
            x_next[g]=bx; y_next[g]=by; z_next[g]=bz; axis_next[g]=1'b0;
          end
        end
        always_ff @(posedge clk) begin
          if (rst) begin
            x_pipe[g] <= '0; y_pipe[g] <= '0; z_pipe[g] <= '0;
            axis_pipe[g] <= 1'b0; valid_pipe[g] <= 1'b0;
          end else if (ce) begin
            x_pipe[g] <= x_next[g]; y_pipe[g] <= y_next[g]; z_pipe[g] <= z_next[g];
            axis_pipe[g] <= axis_next[g]; valid_pipe[g] <= valid_in;
          end
        end
      end else begin: gen_later
        always @* begin
          axis_next[g] = axis_pipe[g-1];
          if (axis_pipe[g-1]) begin
            x_next[g]=x_pipe[g-1]; y_next[g]=y_pipe[g-1]; z_next[g]=z_pipe[g-1];
          end else if (y_pipe[g-1] > 0) begin
            x_next[g] = x_pipe[g-1] + (y_pipe[g-1] >>> g);
            y_next[g] = y_pipe[g-1] - (x_pipe[g-1] >>> g);
            z_next[g] = z_pipe[g-1] + atan_bam32(g);
          end else if (y_pipe[g-1] < 0) begin
            x_next[g] = x_pipe[g-1] - (y_pipe[g-1] >>> g);
            y_next[g] = y_pipe[g-1] + (x_pipe[g-1] >>> g);
            z_next[g] = z_pipe[g-1] - atan_bam32(g);
          end else begin
            x_next[g]=x_pipe[g-1]; y_next[g]=y_pipe[g-1]; z_next[g]=z_pipe[g-1];
          end
        end
        always_ff @(posedge clk) begin
          if (rst) begin
            x_pipe[g] <= '0; y_pipe[g] <= '0; z_pipe[g] <= '0;
            axis_pipe[g] <= 1'b0; valid_pipe[g] <= 1'b0;
          end else if (ce) begin
            x_pipe[g] <= x_next[g]; y_pipe[g] <= y_next[g]; z_pipe[g] <= z_next[g];
            axis_pipe[g] <= axis_next[g]; valid_pipe[g] <= valid_pipe[g-1];
          end
        end
      end
    end
  endgenerate

  assign angle_out = z_pipe[23];
  assign valid_out = valid_pipe[23];
endmodule
