module wm_ray_path_direct_top (
 input logic clk,rst,ce,valid_in,
 input logic signed [15:0] ray_x,ray_y,ray_z,
 output logic valid_out, output logic [7:0] world_x,
 output logic [6:0] world_y, output logic [14:0] world_addr
);
 wm_direct_bin u_path(.clk(clk),.rst(rst),.ce(ce),.valid_in(valid_in),
  .ray_x(ray_x),.ray_y(ray_y),.ray_z(ray_z),.valid_out(valid_out),
  .world_x(world_x),.world_y(world_y),.world_addr(world_addr));
endmodule
