// Frozen shared numeric contract for SCA AER Stage 2 V1.
// Do not edit without an explicit cross-workspace interface change.
package wm_pkg;
  // Sensor pixel domain. Coordinates are 10-bit unsigned; valid x<960,y<720.
  localparam integer SENSOR_W = 960;
  localparam integer SENSOR_H = 720;
  localparam integer PIXEL_X_W = 10;
  localparam integer PIXEL_Y_W = 10;

  // Equirectangular direction-memory dimensions and row-major address width.
  localparam integer WORLD_W = 256;
  localparam integer WORLD_H = 128;
  localparam integer WORLD_X_W = 8;
  localparam integer WORLD_Y_W = 7;
  localparam integer WORLD_ADDR_W = 15;

  // T32 pose-specific ray grid. Includes guard nodes at right/bottom edges.
  localparam integer GRID_STEP = 32;
  localparam integer GRID_COLS = 31;
  localparam integer GRID_ROWS = 24;
  localparam integer GRID_NODES = GRID_COLS * GRID_ROWS; // 744
  localparam integer GRID_NODE_IDX_W = 10;               // 0..743

  // Signed Q1.15 world-ray components and exact /32 offsets.
  localparam integer RAY_W = 16;
  localparam integer RAY_FRAC = 15;
  localparam integer INTERP_OFFSET_W = 5;
  localparam integer INTERP_DELTA_W = 17;
  localparam integer INTERP_PRODUCT_W = 22;

  // Externally provided four-bank, 4x4-cell packed world-memory organization.
  localparam integer TILE_W = 4;
  localparam integer TILE_H = 4;
  localparam integer TILE_X_W = 6;       // WORLD_W / TILE_W = 64
  localparam integer TILE_Y_W = 5;       // WORLD_H / TILE_H = 32
  localparam integer TILE_CELL_W = 4;    // 16 cells per tile
  localparam integer TILE_WORD_ADDR_W = 9; // {tile_y[4:0],tile_x[5:2]}
  localparam integer NUM_BANKS = 4;
  localparam integer BANK_ID_W = 2;

  // Packed ON/OFF accumulators. Counter width is an engineering default.
  localparam integer ON_COUNT_W = 4;
  localparam integer OFF_COUNT_W = 4;

  // Exp05b ray-to-angle pipeline contract.
  localparam integer CORDIC_ITERATIONS = 24;
  localparam integer CORDIC_XY_W = 32;
  localparam integer CORDIC_INPUT_GUARD = 12;
  localparam integer ANGLE_W = 32;       // signed BAM32; full turn = 2^32
  localparam integer SQRT_INPUT_W = 56;
  localparam integer SQRT_OUTPUT_W = 28;
  localparam integer SQRT_STAGES = 28;
  localparam integer RAY2ANGLE_LATENCY = SQRT_STAGES + CORDIC_ITERATIONS;

  // Shared signed signal and node types. Packed order is {x,y,z}; z is LSB.
  typedef logic signed [RAY_W-1:0] ray_component_t;
  typedef struct packed {
    ray_component_t x;
    ray_component_t y;
    ray_component_t z;
  } ray3_t;
  typedef logic signed [ANGLE_W-1:0] angle_bam32_t;
  typedef logic [WORLD_X_W-1:0] world_x_t;
  typedef logic [WORLD_Y_W-1:0] world_y_t;
  typedef logic [WORLD_ADDR_W-1:0] world_addr_t;
endpackage
