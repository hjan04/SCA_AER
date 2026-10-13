// Holds one native word and issues up to two events per enabled cycle,
// lowest set bit first: group A bits 0..7, then group B bits 0..7.
// A word with N valid events takes ceil(N/2) issue cycles; the next word is
// loaded in the same cycle the last events issue (no inter-word bubble).
// Invalid coordinates (x >= 960 or y >= 720) are removed at load and counted.
module wm_word_unpacker
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  // FIFO head
  input  logic        fifo_valid,
  input  nword_t      fifo_data,
  output logic        fifo_pop,
  // frame control: the head word may be loaded (its grid is active)
  input  logic        load_allow,
  // global advance (mapper_ce); issue happens only on enabled cycles
  input  logic        adv,
  // issued events (valid only when adv)
  output meta_t       e0,
  output meta_t       e1,
  output logic        held_valid,
  output logic [FRAME_ID_W-1:0] held_frame,
  // statistics strobes
  output logic        word_loaded,
  output logic [4:0]  events_loaded,
  output logic [4:0]  events_dropped,
  output logic [1:0]  events_issued
);
  logic [PIXEL_X_W-1:0]  hx;
  logic [FRAME_ID_W-1:0] hframe;
  logic [GROUP_W-1:0]    hga_grp, hgb_grp;
  logic                  hga_pol, hgb_pol;
  logic [15:0]           rem;
  logic                  hseq, last_seq, last_slot, have_last;
  logic [GRP_TAG_W-1:0]  uid;

  // ---- lowest and second-lowest set bits of rem
  logic        f0, f1;
  logic [3:0]  i0, i1;
  always_comb begin
    f0 = 1'b0; f1 = 1'b0; i0 = '0; i1 = '0;
    for (int k = 0; k < 16; k++) begin
      if (rem[k]) begin
        if (!f0)      begin f0 = 1'b1; i0 = 4'(k); end
        else if (!f1) begin f1 = 1'b1; i1 = 4'(k); end
      end
    end
  end

  logic        do_issue;
  logic [15:0] rem_next, rem_after;
  logic        s0, s1, new0, new1;
  logic [GRP_TAG_W-1:0] uid0, uid1;

  assign do_issue = adv && held_valid && f0;
  always_comb begin
    rem_next = rem;
    if (f0) rem_next[i0] = 1'b0;
    if (f1) rem_next[i1] = 1'b0;
  end
  assign rem_after = do_issue ? rem_next : rem;

  assign s0   = i0[3];
  assign s1   = i1[3];
  assign new0 = !(have_last && (last_seq == hseq) && (last_slot == s0));
  assign uid0 = new0 ? uid + 1'b1 : uid;
  assign new1 = (s1 != s0);
  assign uid1 = new1 ? uid0 + 1'b1 : uid0;

  function automatic logic [PIXEL_Y_W-1:0] y_of(input logic [3:0] idx,
                                                input logic [GROUP_W-1:0] ga,
                                                input logic [GROUP_W-1:0] gb);
    logic [GROUP_W-1:0] g;
    begin
      g = idx[3] ? gb : ga;
      y_of = {g, idx[2:0]};
    end
  endfunction

  always_comb begin
    e0 = '0;
    e1 = '0;
    if (do_issue) begin
      e0.v = 1'b1; e0.x = hx; e0.y = y_of(i0, hga_grp, hgb_grp);
      e0.pol = s0 ? hgb_pol : hga_pol; e0.grp = uid0; e0.frame = hframe;
      if (f1) begin
        e1.v = 1'b1; e1.x = hx; e1.y = y_of(i1, hga_grp, hgb_grp);
        e1.pol = s1 ? hgb_pol : hga_pol; e1.grp = uid1; e1.frame = hframe;
      end
    end
  end
  assign events_issued = do_issue ? (f1 ? 2'd2 : 2'd1) : 2'd0;

  // ---- load path with coordinate filtering
  function automatic logic [7:0] valid_mask(input logic gv, input logic [GROUP_W-1:0] grp,
                                            input logic [7:0] m, input logic xok);
    logic [7:0] r;
    begin
      for (int k = 0; k < 8; k++)
        r[k] = gv && xok && m[k] && (({grp, 3'(k)}) < 10'(SENSOR_H));
      valid_mask = r;
    end
  endfunction

  logic       xok;
  logic [7:0] ma, mb;
  integer     n_orig, n_keep;
  assign xok      = (fifo_data.x < 10'(SENSOR_W));
  assign ma       = valid_mask(fifo_data.ga_v, fifo_data.ga_grp, fifo_data.ga_mask, xok);
  assign mb       = valid_mask(fifo_data.gb_v, fifo_data.gb_grp, fifo_data.gb_mask, xok);
  always_comb begin
    n_orig = (fifo_data.ga_v ? popcount8(fifo_data.ga_mask) : 0) +
             (fifo_data.gb_v ? popcount8(fifo_data.gb_mask) : 0);
    n_keep = popcount8(ma) + popcount8(mb);
  end

  assign fifo_pop       = fifo_valid && load_allow && (!held_valid || (rem_after == '0));
  assign word_loaded    = fifo_pop;
  assign events_loaded  = fifo_pop ? 5'(n_keep) : 5'd0;
  assign events_dropped = fifo_pop ? 5'(n_orig - n_keep) : 5'd0;
  assign held_frame     = hframe;

  always_ff @(posedge clk) begin
    if (rst) begin
      held_valid <= 1'b0;
      rem        <= '0;
      hx         <= '0; hframe <= '0;
      hga_grp    <= '0; hgb_grp <= '0; hga_pol <= 1'b0; hgb_pol <= 1'b0;
      hseq       <= 1'b0; last_seq <= 1'b0; last_slot <= 1'b0; have_last <= 1'b0;
      uid        <= '0;
    end else begin
      if (do_issue) begin
        uid       <= f1 ? uid1 : uid0;
        last_slot <= f1 ? s1 : s0;
        last_seq  <= hseq;
        have_last <= 1'b1;
      end
      if (fifo_pop) begin
        held_valid <= 1'b1;
        rem        <= {mb, ma};
        hx         <= fifo_data.x;
        hframe     <= fifo_data.frame;
        hga_grp    <= fifo_data.ga_grp; hgb_grp <= fifo_data.gb_grp;
        hga_pol    <= fifo_data.ga_pol; hgb_pol <= fifo_data.gb_pol;
        hseq       <= ~hseq;
      end else begin
        rem <= rem_after;
        if (rem_after == '0) held_valid <= 1'b0;
      end
    end
  end
endmodule
