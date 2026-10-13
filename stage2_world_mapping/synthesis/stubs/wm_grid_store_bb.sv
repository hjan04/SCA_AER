// SYNTHESIS-ONLY black-box stub for wm_grid_store (MODE 1 logic/control PPA).
// Port-exact copy of rtl/control/wm_grid_store.sv with NO body, so the grid
// storage (2 x 744 x 48 b, 4 parity sub-banks, 2 lane read ports each) is
// excluded from the logic PPA and reported/estimated separately.
// Genus must report this module as a black box (see genus_wm.tcl checks).
(* black_box *)
module wm_grid_store
  import wm_pkg::*;
(
  input  logic        clk,
  input  logic        we,
  input  logic        wsel,
  input  logic [4:0]  wgx,
  input  logic [4:0]  wgy,
  input  ray3_t       wnode,
  input  logic        rsel0,
  input  logic [4:0]  rgx0,
  input  logic [4:0]  rgy0,
  output ray3_t       n00_0, n10_0, n01_0, n11_0,
  input  logic        rsel1,
  input  logic [4:0]  rgx1,
  input  logic [4:0]  rgy1,
  output ray3_t       n00_1, n10_1, n01_1, n11_1
);
endmodule
