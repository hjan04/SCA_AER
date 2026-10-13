module tb_cordic;
  localparam integer N=66462;
  logic clk=0,rst=1,ce=1,valid_in=0;
  always #5 clk=~clk;
  logic [95:0] vecs[0:N-1];
  logic signed [31:0] x_in,y_in,angle_out;
  logic valid_out;
  integer cycle,out_count,input_count,enabled_count;
  wm_cordic_vectoring dut(.clk(clk),.rst(rst),.ce(ce),.valid_in(valid_in),
    .x_in(x_in),.y_in(y_in),.valid_out(valid_out),.angle_out(angle_out));
  initial begin
    $readmemh("cordic_vectors.hex",vecs);x_in=0;y_in=0;
    repeat(3) @(posedge clk);
    @(negedge clk);rst=0;out_count=0;input_count=0;enabled_count=0;cycle=0;
    while(enabled_count<N+24) begin
      ce=((cycle%17)!=8);
      if(ce && input_count<N) begin
        x_in=vecs[input_count][31:0];y_in=vecs[input_count][63:32];valid_in=1;
      end else valid_in=0;
      @(posedge clk);#1;
      if(ce && valid_out) begin
        if(angle_out !== vecs[out_count][95:64])
          $fatal(1,"CORDIC mismatch vector %0d got %h expected %h",out_count,angle_out,vecs[out_count][95:64]);
        out_count=out_count+1;
      end
      if(ce) begin
        if(valid_in) input_count=input_count+1;
        enabled_count=enabled_count+1;
      end
      @(negedge clk);
      cycle=cycle+1;
    end
    if(out_count!=N) $fatal(1,"CORDIC outputs %0d expected %0d",out_count,N);
    $display("PASS wm_cordic_vectoring: %0d vectors, latency 24",N);$finish;
  end
endmodule
