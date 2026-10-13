module tb_ray2angle;
  localparam integer N=33231;
  localparam integer LAT=52;
  logic clk=0,rst=1,ce=1,valid_in=0;
  always #5 clk=~clk;
  logic [126:0] vecs[0:N-1];
  logic signed [15:0] ray_x,ray_y,ray_z;
  logic valid_out;
  logic signed [31:0] azimuth_bam32,elevation_bam32;
  logic [7:0] world_x;
  logic [6:0] world_y;
  logic [14:0] world_addr;
  integer cycle,out_count,input_count,enabled_count;

  wm_ray2angle dut(.clk(clk),.rst(rst),.ce(ce),.valid_in(valid_in),
    .ray_x(ray_x),.ray_y(ray_y),.ray_z(ray_z),.valid_out(valid_out),
    .azimuth_bam32(azimuth_bam32),.elevation_bam32(elevation_bam32));
  wm_world_quant quant(.azimuth_bam32(azimuth_bam32),
    .elevation_bam32(elevation_bam32),.world_x(world_x),.world_y(world_y),
    .world_addr(world_addr));

  initial begin
    $readmemh("address_vectors.hex",vecs);
    ray_x=0;ray_y=0;ray_z=0;
    repeat(3) @(posedge clk);
    @(negedge clk);rst=0;out_count=0;input_count=0;enabled_count=0;cycle=0;
    while(enabled_count<N+LAT) begin
      ce=((cycle%17)!=8);
      if(ce && input_count<N) begin
        ray_x=vecs[input_count][47:32];
        ray_y=vecs[input_count][31:16];
        ray_z=vecs[input_count][15:0];
        valid_in=1;
      end else valid_in=0;
      @(posedge clk);#1;
      if(ce && valid_out) begin
        if(azimuth_bam32 !== vecs[out_count][79:48])
          $fatal(1,"az CORDIC mismatch vector %0d got %h expected %h",out_count,azimuth_bam32,vecs[out_count][79:48]);
        if(elevation_bam32 !== vecs[out_count][111:80])
          $fatal(1,"el CORDIC mismatch vector %0d got %h expected %h",out_count,elevation_bam32,vecs[out_count][111:80]);
        if(world_addr !== vecs[out_count][126:112])
          $fatal(1,"world quant mismatch vector %0d got %0d expected %0d",out_count,world_addr,vecs[out_count][126:112]);
        if(world_addr >= 32768 || world_x >= 256 || world_y >= 128)
          $fatal(1,"world output out of bounds vector %0d",out_count);
        out_count=out_count+1;
      end
      if(ce) begin
        if(valid_in) input_count=input_count+1;
        enabled_count=enabled_count+1;
      end
      @(negedge clk);
      cycle=cycle+1;
    end
    if(out_count!=N) $fatal(1,"ray2angle outputs %0d expected %0d",out_count,N);
    $display("PASS wm_ray2angle + wm_world_quant: %0d vectors, latency %0d",N,LAT);
    $finish;
  end
endmodule
