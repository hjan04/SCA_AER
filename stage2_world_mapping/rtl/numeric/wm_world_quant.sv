// Exact Exp05b signed BAM32 -> 256x128 equirectangular world quantization.
// Combinational; floor binning, horizontal wrap, and vertical endpoint clamp.
module wm_world_quant (
  input  logic signed [31:0] azimuth_bam32,
  input  logic signed [31:0] elevation_bam32,
  output logic [7:0] world_x,
  output logic [6:0] world_y,
  output logic [14:0] world_addr
);
  logic [31:0] az_shifted;
  logic signed [32:0] elevation_ext;
  logic signed [32:0] elevation_delta;

  always @* begin
    az_shifted = '0;
    elevation_ext = '0;
    elevation_delta = '0;
    world_x = '0;
    world_y = '0;
    world_addr = '0;
    // BAM32 signed range [-pi,+pi); adding pi as an unsigned modulo sum
    // implements floor((az+pi)/(2*pi)*256) with the +pi endpoint wrapped.
    az_shifted = $unsigned(azimuth_bam32) + 32'h80000000;
    world_x = az_shifted[31:24];

    elevation_ext = {elevation_bam32[31],elevation_bam32};
    if (elevation_bam32 >= 32'sh40000000) begin
      world_y = 7'd0;
    end else if (elevation_bam32 <= -32'sh40000000) begin
      world_y = 7'd127;
    end else begin
      elevation_delta = 33'sd1073741824 - elevation_ext;
      world_y = elevation_delta[30:24];
    end
    world_addr = {world_y,world_x};
  end
endmodule
