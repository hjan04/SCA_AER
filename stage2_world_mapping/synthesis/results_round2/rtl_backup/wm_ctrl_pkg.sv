// Control-side definitions for the Stage 2 V1 world mapper (Claude-owned).
// Numeric contract constants come from the frozen wm_pkg (Codex-owned, read-only).
package wm_ctrl_pkg;
  import wm_pkg::*;

  localparam integer FRAME_ID_W = 8;
  localparam integer GROUP_W    = 7;          // y >> 3, valid 0..89
  localparam integer GRP_TAG_W  = 2;          // rolling native-group tag
  localparam integer LANE_LAT   = RAY2ANGLE_LATENCY; // 52 enabled edges

  // Packed tile word: cell c occupies bits [8c+7:8c] = {ON[3:0], OFF[3:0]}.
  // (Control-side bit order; wm_pkg fixes 16 cells x (4 ON + 4 OFF) = 128 bits.)
  localparam integer CELLS      = TILE_W * TILE_H;           // 16
  localparam integer CELL_BITS  = ON_COUNT_W + OFF_COUNT_W;  // 8
  localparam integer TILE_WORD_W = CELLS * CELL_BITS;        // 128
  localparam integer DELTA_W    = 4;          // <= 8 events per native group
  localparam integer BANK_WORDS = 1 << TILE_WORD_ADDR_W;     // 512

  // One native sensor word (core input transaction). Group B carries an
  // ABSOLUTE group index (the adapter adds the sensor's off field).
  typedef struct packed {
    logic [FRAME_ID_W-1:0] frame;
    logic [PIXEL_X_W-1:0]  x;
    logic                  ga_v;
    logic [GROUP_W-1:0]    ga_grp;
    logic [7:0]            ga_mask;
    logic                  ga_pol;
    logic                  gb_v;
    logic [GROUP_W-1:0]    gb_grp;
    logic [7:0]            gb_mask;
    logic                  gb_pol;
  } nword_t;                                  // 52 bits

  // Per-event metadata carried alongside the 52-cycle numeric lane.
  typedef struct packed {
    logic                  v;
    logic [PIXEL_X_W-1:0]  x;                 // debug/scoreboard
    logic [PIXEL_Y_W-1:0]  y;                 // debug/scoreboard
    logic                  pol;               // 1 = ON plane, 0 = OFF plane
    logic [GRP_TAG_W-1:0]  grp;
    logic [FRAME_ID_W-1:0] frame;
  } meta_t;                                   // 32 bits

  // Mapped event: lane output + aligned metadata + tile/bank address.
  typedef struct packed {
    logic                        v;
    logic [BANK_ID_W-1:0]        bank;
    logic [TILE_WORD_ADDR_W-1:0] waddr;
    logic [TILE_CELL_W-1:0]      cofs;
    logic                        pol;
    logic [GRP_TAG_W-1:0]        grp;
    logic [FRAME_ID_W-1:0]       frame;
    logic [WORLD_ADDR_W-1:0]     world_addr;  // debug/scoreboard
    logic [PIXEL_X_W-1:0]        x;           // debug/scoreboard
    logic [PIXEL_Y_W-1:0]        y;           // debug/scoreboard
  } mapped_t;

  // One read-modify-write request (merged or single event).
  typedef struct packed {
    logic                        v;
    logic [BANK_ID_W-1:0]        bank;
    logic [TILE_WORD_ADDR_W-1:0] waddr;
    logic [CELLS*DELTA_W-1:0]    d_on;        // cell c at [4c+3:4c]
    logic [CELLS*DELTA_W-1:0]    d_off;
    logic [4:0]                  n;           // events in this record
  } rec_t;

  // Frozen Exp05b tile/bank contract.
  function automatic logic [BANK_ID_W-1:0] bank_of(input logic [WORLD_X_W-1:0] wx,
                                                   input logic [WORLD_Y_W-1:0] wy);
    logic [TILE_X_W-1:0] tx;
    logic [TILE_Y_W-1:0] ty;
    begin
      tx = wx[7:2];
      ty = wy[6:2];
      bank_of = tx[1:0] ^ (2'b00 - ty[1:0]);  // tx[1:0] XOR ((-ty) mod 4)
    end
  endfunction

  function automatic logic [TILE_WORD_ADDR_W-1:0] waddr_of(input logic [WORLD_X_W-1:0] wx,
                                                           input logic [WORLD_Y_W-1:0] wy);
    waddr_of = {wy[6:2], wx[7:4]};            // {tile_y, tile_x[5:2]}
  endfunction

  function automatic logic [TILE_CELL_W-1:0] cell_of(input logic [WORLD_X_W-1:0] wx,
                                                     input logic [WORLD_Y_W-1:0] wy);
    cell_of = {wy[1:0], wx[1:0]};             // 4*cell_y + cell_x
  endfunction

  function automatic integer popcount8(input logic [7:0] m);
    integer k;
    begin
      popcount8 = 0;
      for (k = 0; k < 8; k = k + 1) popcount8 = popcount8 + m[k];
    end
  endfunction

  // Status / performance counters (32-bit, saturate never expected in tests).
  typedef struct packed {
    logic [31:0] cycles;            // cycles since init_done
    logic [31:0] words_accepted;    // native words loaded by the unpacker
    logic [31:0] events_accepted;   // valid events in loaded words
    logic [31:0] dropped_events;    // invalid-coordinate events removed
    logic [31:0] events_issued;     // events dispatched to lanes
    logic [31:0] issue_cycles;      // enabled cycles with >= 1 issued event
    logic [31:0] events_mapped;     // lane outputs captured
    logic [31:0] rmw_requests;      // records accepted by the router
    logic [31:0] merge_count;       // records with n >= 2
    logic [31:0] events_in_records; // sum of n over accepted records
    logic [31:0] bank_conflicts;    // accepted pairs to the same bank
    logic [31:0] same_word_pairs;   // accepted pairs to the same bank word
    logic [31:0] rmw_done;          // bank read-modify-writes performed
    logic [31:0] events_applied;    // sum of n over performed RMWs
    logic [31:0] bypass_count;      // RMWs that used forwarded data
    logic [31:0] sat_loss_on;       // ON contributions lost to saturation
    logic [31:0] sat_loss_off;      // OFF contributions lost to saturation
    logic [31:0] stall_cycles;      // cycles with mapper_ce = 0
    logic [31:0] grid_wait_cycles;  // head word waiting for its frame grid
    logic [31:0] node_reads;        // lane node fetches from the grid store (x4 nodes)
    logic [31:0] node_reuses;       // lane node sets served without a read
    logic [31:0] fifo_max_occ;
    logic [31:0] outbuf_max_occ;
    logic [31:0] bq_max_occ;        // max over banks
  } status_t;
endpackage
