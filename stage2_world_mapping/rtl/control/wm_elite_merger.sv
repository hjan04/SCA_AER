// Consecutive-only, native-group-scoped E-lite merger (Exp05b semantics).
// One open record. An event folds into it iff MERGE_EN and it has the same
// frame, native (word, slot) group tag, bank and tile word. Otherwise the open
// record is emitted and a new one opened. The open record is also emitted when
// the whole upstream is empty (flush_ok: FIFO, unpacker, lanes, output buffer),
// so a ce stall can never split a group and RMW counts are stall-independent.
// At most two records are emitted per cycle.
// MERGE_EN = 0: every event is emitted as its own record (D2 baseline).
// ON (pol = 1) and OFF (pol = 0) deltas are kept separately per cell.
module wm_elite_merger
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
#(
  parameter bit MERGE_EN = 1'b1
) (
  input  logic    clk,
  input  logic    rst,
  input  logic    in_valid,
  output logic    in_ready,
  input  mapped_t e0,
  input  mapped_t e1,
  output rec_t    r0,
  output rec_t    r1,
  input  logic    rt_accept,          // router takes r0/r1 this cycle
  input  logic    flush_ok            // no event anywhere upstream (idle flush)
);
  rec_t                  open_r;
  logic [GRP_TAG_W-1:0]  open_grp;
  logic [FRAME_ID_W-1:0] open_frame;

  logic proceed;
  assign proceed  = !(r0.v || r1.v) || rt_accept;
  assign in_ready = proceed;

  function automatic rec_t new_rec(input mapped_t e);
    rec_t r;
    logic [CELLS*DELTA_W-1:0] on_v, off_v;
    begin
      on_v = '0; off_v = '0;
      if (e.pol) on_v[e.cofs*DELTA_W +: DELTA_W]  = 4'd1;
      else       off_v[e.cofs*DELTA_W +: DELTA_W] = 4'd1;
      r = '0;
      r.v = 1'b1; r.bank = e.bank; r.waddr = e.waddr; r.n = 5'd1;
      r.d_on = on_v; r.d_off = off_v;
      new_rec = r;
    end
  endfunction

  function automatic rec_t fold(input rec_t r, input mapped_t e);
    rec_t q;
    logic [CELLS*DELTA_W-1:0] on_v, off_v;
    begin
      on_v = r.d_on; off_v = r.d_off;
      if (e.pol) on_v[e.cofs*DELTA_W +: DELTA_W]  = on_v[e.cofs*DELTA_W +: DELTA_W] + 4'd1;
      else       off_v[e.cofs*DELTA_W +: DELTA_W] = off_v[e.cofs*DELTA_W +: DELTA_W] + 4'd1;
      q = r;
      q.d_on = on_v; q.d_off = off_v;
      q.n = r.n + 5'd1;
      fold = q;
    end
  endfunction

  rec_t                  o, em0, em1;
  logic [GRP_TAG_W-1:0]  og;
  logic [FRAME_ID_W-1:0] ofr;
  logic [1:0]            nemit;
  logic                  c0, c1;

  // Sequential fold/emit of e0 then e1 (written out explicitly; no tasks).
  always_comb begin
    o = open_r; og = open_grp; ofr = open_frame;
    em0 = '0; em1 = '0; nemit = 2'd0; c0 = 1'b0; c1 = 1'b0;
    if (proceed) begin
      if (in_valid) begin
        // ---- event 0
        if (e0.v) begin
          if (MERGE_EN) begin
            c0 = o.v && og == e0.grp && ofr == e0.frame &&
                 o.bank == e0.bank && o.waddr == e0.waddr;
            if (c0) o = fold(o, e0);
            else begin
              if (o.v) begin em0 = o; nemit = 2'd1; end
              o = new_rec(e0); og = e0.grp; ofr = e0.frame;
            end
          end else begin
            em0 = new_rec(e0); nemit = 2'd1;
          end
        end
        // ---- event 1
        if (e1.v) begin
          if (MERGE_EN) begin
            c1 = o.v && og == e1.grp && ofr == e1.frame &&
                 o.bank == e1.bank && o.waddr == e1.waddr;
            if (c1) o = fold(o, e1);
            else begin
              if (o.v) begin
                if (nemit == 2'd0) em0 = o; else em1 = o;
                nemit = nemit + 2'd1;
              end
              o = new_rec(e1); og = e1.grp; ofr = e1.frame;
            end
          end else begin
            if (nemit == 2'd0) em0 = new_rec(e1); else em1 = new_rec(e1);
            nemit = nemit + 2'd1;
          end
        end
      end else if (o.v && flush_ok) begin
        em0 = o; nemit = 2'd1;
        o = '0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      open_r <= '0; open_grp <= '0; open_frame <= '0;
      r0 <= '0; r1 <= '0;
    end else if (proceed) begin
      open_r <= o; open_grp <= og; open_frame <= ofr;
      r0 <= em0; r1 <= em1;
    end
  end

`ifndef SYNTHESIS
  always @(posedge clk)
    if (!rst && proceed && in_valid && e1.v && !e0.v)
      $fatal(1, "wm_elite_merger: lane1 event without lane0 event");
`endif
endmodule
