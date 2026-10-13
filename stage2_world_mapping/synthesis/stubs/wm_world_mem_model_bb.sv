// SYNTHESIS-ONLY black-box stub for wm_world_mem_model (MODE 1).
// Port-exact copy of rtl/control/wm_world_mem_model.sv with NO body: one
// 512 x 128-bit 1R1W bank per instance (4 instances = 256x128 cells x 8 b).
// World memory is reported separately (macro estimate), never as flops.
(* black_box *)
module wm_world_mem_model
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
#(
  parameter integer RD_LAT = 1
) (
  input  logic                        clk,
  input  logic                        en,
  input  logic                        rd_en,
  input  logic [TILE_WORD_ADDR_W-1:0] rd_addr,
  output logic [TILE_WORD_W-1:0]      rd_data,
  input  logic                        wr_en,
  input  logic [TILE_WORD_ADDR_W-1:0] wr_addr,
  input  logic [TILE_WORD_W-1:0]      wr_data
);
endmodule
