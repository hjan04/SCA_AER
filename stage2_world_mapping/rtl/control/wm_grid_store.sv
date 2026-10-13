// Double-buffered T32 grid store: 2 buffers x 744 nodes x {x,y,z} Q1.15.
// Organised as 4 parity sub-banks per buffer, sub-bank = {ny[0], nx[0]},
// local index = {ny[4:1], nx[4:1]}. Any 2x2 node neighbourhood hits each
// sub-bank exactly once, so one lane needs one read per sub-bank and two lanes
// need TWO READ PORTS PER SUB-BANK (logical bandwidth: 8 node reads/cycle peak).
// Functional model: asynchronous-read behavioural array, kept in its own module
// so synthesis/PPA can report it separately or replace it with a macro.
module wm_grid_store
  import wm_pkg::*;
(
  input  logic        clk,
  // write port (one node per cycle) into buffer wsel
  input  logic        we,
  input  logic        wsel,
  input  logic [4:0]  wgx,          // 0..30
  input  logic [4:0]  wgy,          // 0..23
  input  ray3_t       wnode,
  // lane 0 read port: cell (gx, gy) of buffer rsel -> four nodes
  input  logic        rsel0,
  input  logic [4:0]  rgx0,
  input  logic [4:0]  rgy0,
  output ray3_t       n00_0, n10_0, n01_0, n11_0,
  // lane 1 read port
  input  logic        rsel1,
  input  logic [4:0]  rgx1,
  input  logic [4:0]  rgy1,
  output ray3_t       n00_1, n10_1, n01_1, n11_1
);
  // flat index = {buf, ny[0], nx[0], ny[4:1], nx[4:1]} -> 11 bits
  ray3_t mem [0:2047];

  function automatic logic [10:0] fidx(input logic b, input logic [4:0] nx,
                                       input logic [4:0] ny);
    fidx = {b, ny[0], nx[0], ny[4:1], nx[4:1]};
  endfunction

  always_ff @(posedge clk)
    if (we) mem[fidx(wsel, wgx, wgy)] <= wnode;

  assign n00_0 = mem[fidx(rsel0, rgx0,        rgy0)];
  assign n10_0 = mem[fidx(rsel0, rgx0 + 5'd1, rgy0)];
  assign n01_0 = mem[fidx(rsel0, rgx0,        rgy0 + 5'd1)];
  assign n11_0 = mem[fidx(rsel0, rgx0 + 5'd1, rgy0 + 5'd1)];
  assign n00_1 = mem[fidx(rsel1, rgx1,        rgy1)];
  assign n10_1 = mem[fidx(rsel1, rgx1 + 5'd1, rgy1)];
  assign n01_1 = mem[fidx(rsel1, rgx1,        rgy1 + 5'd1)];
  assign n11_1 = mem[fidx(rsel1, rgx1 + 5'd1, rgy1 + 5'd1)];

`ifndef SYNTHESIS
  initial for (int i = 0; i < 2048; i++) mem[i] = '0;
`endif
endmodule
