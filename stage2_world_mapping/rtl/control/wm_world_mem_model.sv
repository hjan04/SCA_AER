// Behavioural world-memory bank (SIMULATION MODEL, not for synthesis/PPA).
// 512 x 128-bit packed 4x4 tile words (16 cells x {ON[3:0],OFF[3:0]}).
// 1 read port + 1 write port. Read issued on an enabled cycle returns the
// word as of the start of that cycle after RD_LAT enabled cycles
// (read-before-write on the same address in the same cycle).
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
  logic [TILE_WORD_W-1:0] mem   [0:BANK_WORDS-1];
  logic [TILE_WORD_W-1:0] rpipe [0:RD_LAT-1];

  always_ff @(posedge clk) begin
    if (wr_en) mem[wr_addr] <= wr_data;
    if (en) begin
      rpipe[0] <= rd_en ? mem[rd_addr] : '0;
      for (int i = 1; i < RD_LAT; i++) rpipe[i] <= rpipe[i-1];
    end
  end
  assign rd_data = rpipe[RD_LAT-1];

  initial begin
    for (int i = 0; i < BANK_WORDS; i++) mem[i] = {TILE_WORD_W{1'bx}};
    for (int i = 0; i < RD_LAT; i++) rpipe[i] = '0;
  end
endmodule
