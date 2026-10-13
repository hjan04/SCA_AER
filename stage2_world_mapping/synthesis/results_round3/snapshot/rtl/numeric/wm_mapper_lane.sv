// One V1 numerical event lane: four externally fetched T32 nodes -> world cell.
// Grid memory, scheduling, native word parsing, merge, banks, and memory are
// intentionally outside this module. Latency 53 enabled edges; II=1.
module wm_mapper_lane (
  input  logic clk,
  input  logic rst,
  input  logic ce,
  input  logic valid_in,
  input  wm_pkg::ray3_t node00,
  input  wm_pkg::ray3_t node10,
  input  wm_pkg::ray3_t node01,
  input  wm_pkg::ray3_t node11,
  input  logic [4:0] x_offset,
  input  logic [4:0] y_offset,
  output logic valid_out,
  output logic [7:0] world_x,
  output logic [6:0] world_y,
  output logic [14:0] world_addr
);
  logic signed [15:0] lerp_x, lerp_y, lerp_z;
  logic signed [15:0] ray_x, ray_y, ray_z;
  logic ray_valid_in;
  logic ray_valid;
  logic signed [31:0] azimuth_bam32, elevation_bam32;

  wm_lerp u_lerp_x (
    .v00(node00.x),.v10(node10.x),.v01(node01.x),.v11(node11.x),
    .x_offset(x_offset),.y_offset(y_offset),.value(lerp_x)
  );
  wm_lerp u_lerp_y (
    .v00(node00.y),.v10(node10.y),.v01(node01.y),.v11(node11.y),
    .x_offset(x_offset),.y_offset(y_offset),.value(lerp_y)
  );
  wm_lerp u_lerp_z (
    .v00(node00.z),.v10(node10.z),.v01(node01.z),.v11(node11.z),
    .x_offset(x_offset),.y_offset(y_offset),.value(lerp_z)
  );

  // Break the interpolation-to-radial-preparation path. Data and valid advance
  // together only when the shared numeric-pipeline enable is asserted.
  always_ff @(posedge clk) begin
    if (rst) begin
      ray_x <= '0;
      ray_y <= '0;
      ray_z <= '0;
      ray_valid_in <= 1'b0;
    end else if (ce) begin
      ray_x <= lerp_x;
      ray_y <= lerp_y;
      ray_z <= lerp_z;
      ray_valid_in <= valid_in;
    end
  end

  wm_ray2angle u_ray2angle (
    .clk(clk),.rst(rst),.ce(ce),.valid_in(ray_valid_in),
    .ray_x(ray_x),.ray_y(ray_y),.ray_z(ray_z),.valid_out(ray_valid),
    .azimuth_bam32(azimuth_bam32),.elevation_bam32(elevation_bam32)
  );

  wm_world_quant u_world_quant (
    .azimuth_bam32(azimuth_bam32),.elevation_bam32(elevation_bam32),
    .world_x(world_x),.world_y(world_y),.world_addr(world_addr)
  );

  assign valid_out = ray_valid;

`ifndef SYNTHESIS
  // Every 5-bit local offset is a valid numerator in the exact /32 grid.
  // Guard X values and externally supplied nodes at the module boundary.
  always @(posedge clk) begin
    if (!rst && ce && valid_in) begin
      if ((^x_offset) === 1'bx || (^y_offset) === 1'bx)
        $fatal(1,"wm_mapper_lane received unknown interpolation offset");
      if ((^node00) === 1'bx || (^node10) === 1'bx ||
          (^node01) === 1'bx || (^node11) === 1'bx)
        $fatal(1,"wm_mapper_lane received unknown grid node");
    end
  end
`endif
endmodule
