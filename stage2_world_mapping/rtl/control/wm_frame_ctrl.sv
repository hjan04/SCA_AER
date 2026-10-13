// Frame / grid-epoch controller (STRICT policy).
//
// Buffer life cycle: FREE -> LOADING -> READY(epoch) -> ACTIVE -> DRAINING -> FREE
//  * Loader writes the 744 nodes of a grid into the FREE/LOADING buffer in
//    increasing node_idx (gy-major, Exp05b). Out-of-order/duplicate/missing
//    indices set a sticky error; writing node_idx 0 restarts the load.
//  * Commit is accepted only with all 744 nodes and no error -> READY(epoch).
//    A partially loaded grid can never become READY or ACTIVE.
//  * The unpacker may load the FIFO head word only if its frame id equals the
//    ACTIVE epoch. A new frame waits until the held word is finished, then the
//    READY buffer with that epoch becomes ACTIVE (atomic swap). No READY grid
//    for that frame -> the frame stalls (grid_wait), stale pose is never used.
//  * Safe reload point: an event needs grid memory only in the D stage (its
//    four nodes are captured into the lane-input registers on the D->L edge;
//    the numeric lane receives node VALUES, not addresses). The old buffer is
//    released (DRAINING -> FREE) on the first cycle in which no D-stage event
//    carries its gsel, and cached node keys for it are invalidated. It does NOT
//    wait for the 52-cycle numeric pipeline.
module wm_frame_ctrl
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
(
  input  logic                  clk,
  input  logic                  rst,
  // grid load / commit port
  input  logic                  gw_valid,
  output logic                  gw_ready,
  input  logic [GRID_NODE_IDX_W-1:0] gw_node_idx,
  input  ray3_t                 gw_node,
  input  logic                  gc_valid,
  output logic                  gc_ready,
  input  logic [FRAME_ID_W-1:0] gc_epoch,
  // grid store write port
  output logic                  st_we,
  output logic                  st_wsel,
  output logic [4:0]            st_wgx,
  output logic [4:0]            st_wgy,
  output ray3_t                 st_wnode,
  // unpacker interface
  input  logic                  head_valid,
  input  logic [FRAME_ID_W-1:0] head_frame,
  input  logic                  held_valid,
  output logic                  load_allow,
  output logic                  active_gsel,
  // D-stage references (drain tracking)
  input  logic                  d0_v, d0_gsel,
  input  logic                  d1_v, d1_gsel,
  output logic                  inv_valid,
  output logic                  inv_sel,
  // status
  output logic                  grid_wait,
  output logic                  grid_load_err,
  output logic [31:0]           swaps,
  output logic [31:0]           commits
);
  typedef enum logic [2:0] {FREE, LOADING, READY, ACTIVE, DRAINING} bst_t;
  bst_t                  st   [0:1];
  logic [FRAME_ID_W-1:0] ep   [0:1];
  logic [9:0]            cnt;
  logic [4:0]            lgx, lgy;
  logic                  err;

  // buffer used by the loader: a LOADING one, else a FREE one (lowest index)
  logic lb_ok, lb;
  always_comb begin
    lb_ok = 1'b1;
    if      (st[0] == LOADING) lb = 1'b0;
    else if (st[1] == LOADING) lb = 1'b1;
    else if (st[0] == FREE)    lb = 1'b0;
    else if (st[1] == FREE)    lb = 1'b1;
    else begin lb = 1'b0; lb_ok = 1'b0; end
  end

  logic act_ok, act;
  always_comb begin
    act_ok = 1'b1;
    if      (st[0] == ACTIVE) act = 1'b0;
    else if (st[1] == ACTIVE) act = 1'b1;
    else begin act = 1'b0; act_ok = 1'b0; end
  end
  assign active_gsel = act;

  logic gw_fire, gc_fire;
  assign gw_ready = lb_ok && (cnt < 10'(GRID_NODES) || gw_node_idx == '0);
  assign gw_fire  = gw_valid && gw_ready;
  assign gc_ready = lb_ok && (st[lb] == LOADING) && (cnt == 10'(GRID_NODES)) && !err;
  assign gc_fire  = gc_valid && gc_ready;

  assign st_we    = gw_fire;
  assign st_wsel  = lb;
  assign st_wgx   = (gw_node_idx == '0) ? 5'd0 : lgx;
  assign st_wgy   = (gw_node_idx == '0) ? 5'd0 : lgy;
  assign st_wnode = gw_node;

  // frame binding for the FIFO head word
  logic other_ready_match, sw;
  assign other_ready_match = (st[~act] == READY) && (ep[~act] == head_frame);
  // first frame: no ACTIVE buffer yet -> look for any READY match
  logic init_match, init_sel;
  always_comb begin
    init_match = 1'b0; init_sel = 1'b0;
    if (!act_ok) begin
      if (st[0] == READY && ep[0] == head_frame)      begin init_match = 1'b1; init_sel = 1'b0; end
      else if (st[1] == READY && ep[1] == head_frame) begin init_match = 1'b1; init_sel = 1'b1; end
    end
  end
  assign load_allow = act_ok && (ep[act] == head_frame);
  assign sw = head_valid && !held_valid && !load_allow &&
              ((act_ok && other_ready_match && st[~act] == READY) || init_match);
  assign grid_wait = head_valid && !load_allow && !sw && !held_valid;

  // drain: release the DRAINING buffer once no D-stage event references it
  logic drn_ok, drn;
  always_comb begin
    drn_ok = 1'b1;
    if      (st[0] == DRAINING) drn = 1'b0;
    else if (st[1] == DRAINING) drn = 1'b1;
    else begin drn = 1'b0; drn_ok = 1'b0; end
  end
  assign inv_valid = drn_ok && !(d0_v && d0_gsel == drn) && !(d1_v && d1_gsel == drn);
  assign inv_sel   = drn;
  assign grid_load_err = err;

  always_ff @(posedge clk) begin
    if (rst) begin
      st[0] <= FREE; st[1] <= FREE; ep[0] <= '0; ep[1] <= '0;
      cnt <= '0; lgx <= '0; lgy <= '0; err <= 1'b0;
      swaps <= '0; commits <= '0;
    end else begin
      // loader
      if (gw_fire) begin
        if (gw_node_idx == '0) begin
          err <= 1'b0; cnt <= 10'd1; lgx <= 5'd1; lgy <= 5'd0;
        end else begin
          if (gw_node_idx != cnt) err <= 1'b1;
          cnt <= cnt + 1'b1;
          if (lgx == 5'(GRID_COLS - 1)) begin lgx <= '0; lgy <= lgy + 1'b1; end
          else lgx <= lgx + 1'b1;
        end
        if (st[lb] == FREE) st[lb] <= LOADING;
      end
      if (gc_fire) begin
        st[lb] <= READY; ep[lb] <= gc_epoch;
        cnt <= '0; lgx <= '0; lgy <= '0;
        commits <= commits + 1'b1;
      end
      // atomic swap at a frame boundary
      if (sw) begin
        if (act_ok) begin
          st[act]  <= DRAINING;
          st[~act] <= ACTIVE;
        end else begin
          st[init_sel] <= ACTIVE;
        end
        swaps <= swaps + 1'b1;
      end
      // release
      if (inv_valid) st[drn] <= FREE;
    end
  end

`ifndef SYNTHESIS
  always @(posedge clk) begin
    if (!rst && st[0] == ACTIVE && st[1] == ACTIVE)
      $fatal(1, "wm_frame_ctrl: two ACTIVE grid buffers");
    if (!rst && gw_fire && (st[lb] == ACTIVE || st[lb] == DRAINING || st[lb] == READY))
      $fatal(1, "wm_frame_ctrl: write into a non-loadable grid buffer");
  end
`endif
endmodule
