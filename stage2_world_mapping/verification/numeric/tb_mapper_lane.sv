module tb_mapper_lane;
  import wm_pkg::*;
  localparam integer N = 8064;
  localparam integer LAT = RAY2ANGLE_LATENCY + 1;
  logic clk=0, rst=1, ce=1, valid_in=0;
  always #5 clk=~clk;

  logic [264:0] vecs [0:N-1];
  ray3_t node00,node10,node01,node11;
  logic [4:0] x_offset,y_offset;
  logic valid_out;
  logic [7:0] world_x;
  logic [6:0] world_y;
  logic [14:0] world_addr;
  logic signed [15:0] lerp_x,lerp_y,lerp_z;
  integer cycle,out_count,input_count,enabled_count;
  logic [LAT-1:0] valid_ref;

  always @(posedge clk) begin
    if (rst) valid_ref <= '0;
    else if (ce) valid_ref <= {valid_ref[LAT-2:0], valid_in};
  end

  wm_lerp lx(.v00(node00.x),.v10(node10.x),.v01(node01.x),.v11(node11.x),
             .x_offset(x_offset),.y_offset(y_offset),.value(lerp_x));
  wm_lerp ly(.v00(node00.y),.v10(node10.y),.v01(node01.y),.v11(node11.y),
             .x_offset(x_offset),.y_offset(y_offset),.value(lerp_y));
  wm_lerp lz(.v00(node00.z),.v10(node10.z),.v01(node01.z),.v11(node11.z),
             .x_offset(x_offset),.y_offset(y_offset),.value(lerp_z));

  wm_mapper_lane dut(.clk(clk),.rst(rst),.ce(ce),.valid_in(valid_in),
    .node00(node00),.node10(node10),.node01(node01),.node11(node11),
    .x_offset(x_offset),.y_offset(y_offset),.valid_out(valid_out),
    .world_x(world_x),.world_y(world_y),.world_addr(world_addr));

  initial begin
    $readmemh("lane_vectors.hex",vecs);
    node00='0; node10='0; node01='0; node11='0;
    x_offset='0; y_offset='0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst=0;
    out_count=0; input_count=0; enabled_count=0; cycle=0;
    while (enabled_count<N+LAT) begin
      ce = ((cycle % 17) != 8);
      if (ce && input_count<N) begin
        node00=vecs[input_count][57:10];
        node10=vecs[input_count][105:58];
        node01=vecs[input_count][153:106];
        node11=vecs[input_count][201:154];
        y_offset=vecs[input_count][4:0];
        x_offset=vecs[input_count][9:5];
        valid_in=1'b1;
        #1;
        if ({lerp_x,lerp_y,lerp_z} !== vecs[input_count][249:202])
          $fatal(1,"lerp mismatch vector %0d got %h expected %h",input_count,
                 {lerp_x,lerp_y,lerp_z},vecs[input_count][249:202]);
      end else begin
        valid_in=1'b0;
      end
      @(posedge clk); #1;
      if (valid_out !== valid_ref[LAT-1])
        $fatal(1,"lane valid latency/CE mismatch at cycle %0d",cycle);
      if (ce && valid_out) begin
        if (out_count>=N) $fatal(1,"unexpected lane output");
        if (world_addr !== vecs[out_count][264:250])
          $fatal(1,"lane address mismatch vector %0d got %0d expected %0d",
                 out_count,world_addr,vecs[out_count][264:250]);
        if (world_x !== vecs[out_count][257:250] || world_y !== vecs[out_count][264:258])
          $fatal(1,"lane coordinate mismatch vector %0d",out_count);
        out_count=out_count+1;
      end
      if (ce) begin
        if (valid_in) input_count=input_count+1;
        enabled_count=enabled_count+1;
      end
      @(negedge clk);
      cycle=cycle+1;
    end
    if (out_count != N) $fatal(1,"lane outputs %0d expected %0d",out_count,N);
    $display("PASS wm_lerp + wm_mapper_lane: %0d vectors, latency %0d",N,LAT);
    $finish;
  end
endmodule
