// Q1.15 direction ray -> azimuth/elevation BAM32, both per-event aligned.
// Radial path: 28-stage exact integer sqrt. Angle paths: two independent
// 24-stage CORDICs. Total latency 52 enabled edges; II=1; global ce stalls all.
module wm_ray2angle (
  input  logic clk,
  input  logic rst,
  input  logic ce,
  input  logic valid_in,
  input  logic signed [15:0] ray_x,
  input  logic signed [15:0] ray_y,
  input  logic signed [15:0] ray_z,
  output logic valid_out,
  output logic signed [31:0] azimuth_bam32,
  output logic signed [31:0] elevation_bam32
);
  logic [55:0] radial_radicand;
  logic [27:0] radial_q28;
  logic radial_valid;

  logic signed [31:0] ray_x_guard, ray_y_guard, ray_z_guard;
  logic signed [31:0] ray_x_ext, ray_z_ext;
  logic [31:0] ray_x_sq, ray_z_sq;
  logic [32:0] radial_sum;
  logic signed [31:0] ray_x_pipe [0:27];
  logic signed [31:0] ray_y_pipe [0:27];
  logic signed [31:0] ray_z_pipe [0:27];
  logic ray_valid_pipe [0:27];

  logic az_valid, el_valid;
  logic signed [31:0] az_code, el_code;
  integer i;

  // Scale all Q1.15 integers by 2^12 exactly, matching Exp05b.
  assign ray_x_guard = {{4{ray_x[15]}},ray_x,12'b0};
  assign ray_y_guard = {{4{ray_y[15]}},ray_y,12'b0};
  assign ray_z_guard = {{4{ray_z[15]}},ray_z,12'b0};
  assign ray_x_ext = {{16{ray_x[15]}},ray_x};
  assign ray_z_ext = {{16{ray_z[15]}},ray_z};
  assign ray_x_sq = ray_x_ext * ray_x_ext;
  assign ray_z_sq = ray_z_ext * ray_z_ext;
  assign radial_sum = {1'b0,ray_x_sq} + {1'b0,ray_z_sq};
  assign radial_radicand = {radial_sum[31:0],24'b0};

  wm_isqrt u_isqrt (
    .clk(clk),.rst(rst),.ce(ce),.valid_in(valid_in),
    .radicand_in(radial_radicand),.valid_out(radial_valid),.root_out(radial_q28)
  );

  // Align azimuth x/y inputs with the 28-stage square-root result.
  always_ff @(posedge clk) begin
    if (rst) begin
      for (i=0;i<28;i=i+1) begin
        ray_x_pipe[i] <= '0;
        ray_y_pipe[i] <= '0;
        ray_z_pipe[i] <= '0;
        ray_valid_pipe[i] <= 1'b0;
      end
    end else if (ce) begin
      ray_x_pipe[0] <= ray_x_guard;
      ray_y_pipe[0] <= ray_y_guard;
      ray_z_pipe[0] <= ray_z_guard;
      ray_valid_pipe[0] <= valid_in;
      for (i=1;i<28;i=i+1) begin
        ray_x_pipe[i] <= ray_x_pipe[i-1];
        ray_y_pipe[i] <= ray_y_pipe[i-1];
        ray_z_pipe[i] <= ray_z_pipe[i-1];
        ray_valid_pipe[i] <= ray_valid_pipe[i-1];
      end
    end
  end

  // Both units launch on the cycle after their aligned input valid is raised.
  // For azimuth, x=ray_z and y=ray_x. Elevation x=|ray_xz|, y=ray_y.
  wm_cordic_vectoring u_azimuth (
    .clk(clk),.rst(rst),.ce(ce),.valid_in(ray_valid_pipe[27]),
    .x_in(ray_z_pipe[27]),.y_in(ray_x_pipe[27]),
    .valid_out(az_valid),.angle_out(az_code)
  );

  wm_cordic_vectoring u_elevation (
    .clk(clk),.rst(rst),.ce(ce),.valid_in(radial_valid),
    .x_in({4'b0,radial_q28}),.y_in(ray_y_pipe[27]),
    .valid_out(el_valid),.angle_out(el_code)
  );

  // The independent valid paths are required to stay cycle-aligned.
  assign valid_out = az_valid & el_valid;
  assign azimuth_bam32 = az_code;
  assign elevation_bam32 = el_code;

`ifndef SYNTHESIS
  // The parallel azimuth/elevation pipelines must never drift out of phase.
  always @(posedge clk) begin
    if (!rst && ce && (az_valid !== el_valid))
      $fatal(1,"wm_ray2angle azimuth/elevation valid misalignment");
    if (!rst && ce && valid_in && (ray_x == 0) && (ray_y == 0) && (ray_z == 0))
      $fatal(1,"wm_ray2angle received zero direction ray");
  end
`endif
endmodule
