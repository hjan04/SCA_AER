// Exp05b direct ray-to-world classifier. Four CE-enabled edges, II=1.
// Threshold constants and special-case ordering follow ray_address.py.
module wm_direct_bin (
 input logic clk, rst, ce, valid_in,
 input logic signed [15:0] ray_x, ray_y, ray_z,
 output logic valid_out,
 output logic [7:0] world_x,
 output logic [6:0] world_y,
 output logic [14:0] world_addr
);
 function automatic [31:0] tan_q32(input integer n); begin case(n)
  0: tan_q32=32'd105435529;
  1: tan_q32=32'd210998213;
  2: tan_q32=32'd316815821;
  3: tan_q32=32'd423017356;
  4: tan_q32=32'd529733691;
  5: tan_q32=32'd637098215;
  6: tan_q32=32'd745247522;
  7: tan_q32=32'd854322113;
  8: tan_q32=32'd964467159;
  9: tan_q32=32'd1075833302;
  10: tan_q32=32'd1188577525;
  11: tan_q32=32'd1302864085;
  12: tan_q32=32'd1418865542;
  13: tan_q32=32'd1536763871;
  14: tan_q32=32'd1656751707;
  15: tan_q32=32'd1779033704;
  16: tan_q32=32'd1903828065;
  17: tan_q32=32'd2031368245;
  18: tan_q32=32'd2161904859;
  19: tan_q32=32'd2295707848;
  20: tan_q32=32'd2433068920;
  21: tan_q32=32'd2574304328;
  22: tan_q32=32'd2719758045;
  23: tan_q32=32'd2869805398;
  24: tan_q32=32'd3024857252;
  25: tan_q32=32'd3185364841;
  26: tan_q32=32'd3351825376;
  27: tan_q32=32'd3524788567;
  28: tan_q32=32'd3704864268;
  29: tan_q32=32'd3892731450;
  30: tan_q32=32'd4089148798;
  default: tan_q32=0; endcase end endfunction
 function automatic [31:0] tan2_q32(input integer n); begin case(n)
  0: tan2_q32=32'd2588297;
  1: tan2_q32=32'd10365678;
  2: tan2_q32=32'd23369739;
  3: tan2_q32=32'd41663573;
  4: tan2_q32=32'd65336419;
  5: tan2_q32=32'd94504593;
  6: tan2_q32=32'd129312712;
  7: tan2_q32=32'd169935234;
  8: tan2_q32=32'd216578343;
  9: tan2_q32=32'd269482214;
  10: tan2_q32=32'd328923700;
  11: tan2_q32=32'd395219500;
  12: tan2_q32=32'd468729861;
  13: tan2_q32=32'd549862905;
  14: tan2_q32=32'd639079655;
  15: tan2_q32=32'd736899888;
  16: tan2_q32=32'd843908941;
  17: tan2_q32=32'd960765627;
  18: tan2_q32=32'd1088211457;
  19: tan2_q32=32'd1227081410;
  20: tan2_q32=32'd1378316518;
  21: tan2_q32=32'd1542978635;
  22: tan2_q32=32'd1722267788;
  23: tan2_q32=32'd1917542662;
  24: tan2_q32=32'd2130344834;
  25: tan2_q32=32'd2362427575;
  26: tan2_q32=32'd2615790197;
  27: tan2_q32=32'd2892719219;
  28: tan2_q32=32'd3195837896;
  29: tan2_q32=32'd3528166129;
  30: tan2_q32=32'd3893193299;
  default: tan2_q32=0; endcase end endfunction

 logic [16:0] ax0, ay0, az0, lo0, hi0;
 logic sx0, sy0, sz0;
 logic [31:0] r20, y20;
 logic v0;
 logic [16:0] ax0_r,ay0_r,az0_r,lo0_r,hi0_r; logic sx0_r,sy0_r,sz0_r; logic [31:0] r20_r,y20_r;
 logic [30:0] hcmp1, vcmp1;
 logic [15:0] hcount1a,hcount1b,vcount1a,vcount1b;
 logic hvalid1, vvalid1;
 logic [15:0] hcount2,vcount2;
 logic [16:0] ax2,ay2,az2;
 logic sx2,sy2,sz2;
 logic [31:0] r22,y22;
 logic v2;
 logic [7:0] wx3, wy3; logic v3;
 logic [15:0] hcnt,vct;
 logic [15:0] hsml,hbig,vsml,vbig;
 logic [48:0] hleft,hright;
 logic [62:0] vleft,vright;
 logic [15:0] jh, jv, theta, alpha;
 logic hexact, vexact;
 integer i;

 always_comb begin
  ax0 = ray_x[15] ? $unsigned(-$signed({ray_x[15],ray_x})) : {1'b0,ray_x};
  ay0 = ray_y[15] ? $unsigned(-$signed({ray_y[15],ray_y})) : {1'b0,ray_y};
  az0 = ray_z[15] ? $unsigned(-$signed({ray_z[15],ray_z})) : {1'b0,ray_z};
  sx0=ray_x[15]; sy0=ray_y[15]; sz0=ray_z[15];
  lo0=(ax0<az0)?ax0:az0; hi0=(ax0<az0)?az0:ax0;
  r20=ax0*ax0+az0*az0; y20=ay0*ay0;
 end

 // Stage 0: capture signs, magnitudes, and shared squares.
 always_ff @(posedge clk) begin
  if(rst) v0<=0;
  else if(ce) begin
   v0<=valid_in; ax0_r<=ax0; ay0_r<=ay0; az0_r<=az0;
   sx0_r<=sx0; sy0_r<=sy0; sz0_r<=sz0; lo0_r<=lo0; hi0_r<=hi0;
   r20_r<=r20; y20_r<=y20;
  end
 end

 // Stage 1: all exact constant boundary predicates; split groups at stage 2.
 logic [16:0] ax1,ay1,az1; logic sx1,sy1,sz1; logic [31:0] r21,y21;
 logic [30:0] hcmp0,vcmp0;
 always_comb begin
  hcmp0='0; vcmp0='0;
  hsml=(y20_r<r20_r)?y20_r[15:0]:r20_r[15:0];
  hbig=(y20_r<r20_r)?r20_r[15:0]:y20_r[15:0];
  // h classifier uses lo/hi magnitudes; vertical values are full 31-bit squares.
  for(i=0;i<31;i=i+1) begin
   hleft={lo0_r,32'b0}; hright=hi0_r*tan_q32(i);
   hcmp0[i]=(hleft>=hright);
   if(y20_r<r20_r) begin vleft={y20_r,32'b0}; vright=r20_r*tan2_q32(i); end
   else begin vleft={r20_r,32'b0}; vright=y20_r*tan2_q32(i); end
   vcmp0[i]=(vleft>=vright);
  end
 end
 always_ff @(posedge clk) begin
  if(rst) hvalid1<=0;
  else if(ce) begin
   hvalid1<=v0; hcmp1<=hcmp0; vcmp1<=vcmp0;
   ax1<=ax0_r; ay1<=ay0_r; az1<=az0_r; sx1<=sx0_r; sy1<=sy0_r; sz1<=sz0_r;
   r21<=r20_r; y21<=y20_r;
  end
 end
 always_comb begin
  hcount1a=0; hcount1b=0; vcount1a=0; vcount1b=0;
  for(integer k=0;k<16;k=k+1) begin hcount1a=hcount1a+hcmp1[k]; vcount1a=vcount1a+vcmp1[k]; end
  for(integer k=16;k<31;k=k+1) begin hcount1b=hcount1b+hcmp1[k]; vcount1b=vcount1b+vcmp1[k]; end
 end
 always_ff @(posedge clk) begin
  if(rst) v2<=0; else if(ce) begin
   v2<=hvalid1; hcount2<=hcount1a+hcount1b; vcount2<=vcount1a+vcount1b;
   ax2<=ax1; ay2<=ay1; az2<=az1; sx2<=sx1; sy2<=sy1; sz2<=sz1; r22<=r21; y22<=y21;
  end
 end
 always_comb begin
  theta=0; alpha=0; hexact=0; vexact=0;
  if(ax2==0) begin theta=0; hexact=1; end
  else if(az2==0) begin theta=64; hexact=1; end
  else if(ax2==az2) begin theta=32; hexact=1; end
  else if(ax2<az2) theta=hcount2;
  else theta=63-hcount2;
  if(y22==0) begin alpha=0; vexact=1; end
  else if(r22==0) begin alpha=64; vexact=1; end
  else if(y22==r22) begin alpha=32; vexact=1; end
  else if(y22<r22) alpha=vcount2;
  else alpha=63-vcount2;
  if(ax2==0 && az2==0) wx3=128;
  else if(!sx2 && !sz2) wx3=128+theta;
  else if(!sx2 && sz2) wx3=256-(hexact?theta:(theta+1));
  else if(sx2 && sz2) wx3=theta;
  else wx3=128-(hexact?theta:(theta+1));
  if(!sy2) wy3=vexact?(64-alpha):(63-alpha);
  else wy3=64+alpha;
  if(wy3>127) wy3=127;
 end
 always_ff @(posedge clk) begin
  if(rst) begin v3<=0; world_x<=0; world_y<=0; end
  else if(ce) begin v3<=v2; world_x<=wx3; world_y<=wy3[6:0]; end
 end
 assign valid_out=v3; assign world_addr={world_y,world_x};
`ifndef SYNTHESIS
 always @(posedge clk) if(!rst && ce && valid_in && ray_x==0 && ray_y==0 && ray_z==0) $fatal(1,"zero ray invalid");
`endif
endmodule
