module tb_direct_bin;
 logic clk=0,rst=1,ce=1,valid_in=0;
 logic signed [15:0] ray_x,ray_y,ray_z;
 logic valid_out; logic [7:0] world_x; logic [6:0] world_y; logic [14:0] world_addr;
 logic [62:0] vecs[0:50000]; integer n=0, idx=0, accepted=0, errors=0;
 wm_direct_bin dut(.*);
 always #5 clk=~clk;
 initial begin $readmemh("direct_vectors.hex",vecs); while(vecs[n] !== 63'bx) n=n+1; end
 initial begin
  repeat(2) @(posedge clk); #1 rst=0;
  while(idx<n) begin
   @(negedge clk); ce=($urandom_range(0,3)!=0); valid_in=1;
   ray_x=vecs[idx][62:47]; ray_y=vecs[idx][46:31]; ray_z=vecs[idx][30:15];
   @(posedge clk);
   if(ce) begin
    accepted++; #1;
    if(accepted>=4 && (!valid_out || world_addr!==vecs[accepted-4][14:0])) begin
     $display("MISMATCH accepted=%0d source=%0d got=%0d expected=%0d valid=%b",accepted,accepted-4,world_addr,vecs[accepted-4][14:0],valid_out); errors++;
    end
    idx++;
   end
  end
  @(negedge clk); valid_in=0; ce=1;
  repeat(3) begin
   @(posedge clk); #1;
   if(accepted>=4) begin
    accepted++;
    if(!valid_out || world_addr!==vecs[accepted-4][14:0]) begin $display("DRAIN MISMATCH"); errors++; end
   end
  end
  if(errors==0) $display("DIRECT_BIN_PASS vectors=%0d randomized_CE_stall_test=PASS",n);
  else $display("DIRECT_BIN_FAIL errors=%0d vectors=%0d",errors,n);
  $finish;
 end
endmodule
