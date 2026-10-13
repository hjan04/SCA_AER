module tb_isqrt;
  localparam integer N=33231;
  logic clk=0,rst=1,ce=1,valid_in=0;
  always #5 clk=~clk;
  logic [83:0] vecs[0:N-1];
  logic [55:0] radicand_in;
  logic [27:0] root_out;
  logic valid_out;
  integer cycle,out_count,input_count,enabled_count;
  wm_isqrt dut(.clk(clk),.rst(rst),.ce(ce),.valid_in(valid_in),
    .radicand_in(radicand_in),.valid_out(valid_out),.root_out(root_out));
  initial begin
    $readmemh("isqrt_vectors.hex",vecs);radicand_in=0;
    repeat(3) @(posedge clk);
    @(negedge clk);rst=0;out_count=0;input_count=0;enabled_count=0;cycle=0;
    while(enabled_count<N+28) begin
      ce=((cycle%17)!=8);
      if(ce && input_count<N) begin radicand_in=vecs[input_count][55:0];valid_in=1;end
      else valid_in=0;
      @(posedge clk);#1;
      if(ce && valid_out) begin
        if(root_out !== vecs[out_count][83:56])
          $fatal(1,"isqrt mismatch vector %0d got %0d expected %0d",out_count,root_out,vecs[out_count][83:56]);
        out_count=out_count+1;
      end
      if(ce) begin
        if(valid_in) input_count=input_count+1;
        enabled_count=enabled_count+1;
      end
      @(negedge clk);
      cycle=cycle+1;
    end
    if(out_count!=N) $fatal(1,"isqrt outputs %0d expected %0d",out_count,N);
    $display("PASS wm_isqrt: %0d vectors, latency 28",N);$finish;
  end
endmodule
