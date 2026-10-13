// Exp05 signed Q1.15 nested difference interpolation, combinational.
module wm_lerp (
  input  logic signed [15:0] v00,
  input  logic signed [15:0] v10,
  input  logic signed [15:0] v01,
  input  logic signed [15:0] v11,
  input  logic        [4:0] x_offset,
  input  logic        [4:0] y_offset,
  output logic signed [15:0] value
);
  logic signed [16:0] dx_top, dx_bottom, dy;
  logic signed [21:0] p_top, p_bottom, p_y;
  logic signed [16:0] r_top, r_bottom, r_y;
  logic signed [17:0] top, bottom, out_wide;
  logic signed [17:0] dy_wide;

  function automatic logic signed [16:0] round_nearest_even_div32(
    input logic signed [21:0] product
  );
    logic [21:0] magnitude;
    logic [16:0] quotient;
    logic [4:0] remainder;
    logic signed [17:0] signed_quotient;
    begin
      magnitude = product[21] ? (~product + 22'd1) : product;
      quotient = magnitude[21:5];
      remainder = magnitude[4:0];
      if ((remainder > 5'd16) ||
          ((remainder == 5'd16) && quotient[0]))
        quotient = quotient + 17'd1;
      signed_quotient = {1'b0,quotient};
      if (product[21]) signed_quotient = -signed_quotient;
      round_nearest_even_div32 = signed_quotient[16:0];
    end
  endfunction

  always @* begin
    dx_top    = $signed({v10[15],v10}) - $signed({v00[15],v00});
    dx_bottom = $signed({v11[15],v11}) - $signed({v01[15],v01});
    p_top     = $signed({{5{dx_top[16]}},dx_top}) * $signed({17'b0,x_offset});
    p_bottom  = $signed({{5{dx_bottom[16]}},dx_bottom}) * $signed({17'b0,x_offset});
    r_top     = round_nearest_even_div32(p_top);
    r_bottom  = round_nearest_even_div32(p_bottom);
    top       = $signed({{2{v00[15]}},v00}) + $signed({r_top[16],r_top});
    bottom    = $signed({{2{v01[15]}},v01}) + $signed({r_bottom[16],r_bottom});

    dy_wide = bottom - top;
    // Convex interpolation of Q1.15 endpoints guarantees this exact
    // difference fits signed 17 bits; retain that frozen Exp05 width.
    dy = dy_wide[16:0];
    p_y = $signed({{5{dy[16]}},dy}) * $signed({17'b0,y_offset});
    r_y = round_nearest_even_div32(p_y);
    out_wide = top + $signed({r_y[16],r_y});

    if (out_wide > 18'sd32767)
      value = 16'sh7fff;
    else if (out_wide < -18'sd32768)
      value = 16'sh8000;
    else
      value = out_wide[15:0];
  end
endmodule
