// Four-bank router (steering + atomic acceptance). The per-bank request queues
// live in wm_bank_update_ctrl (two enqueue ports, one dequeue port each).
// Up to two records per cycle (r0 before r1 in stream order). The pair is
// accepted ATOMICALLY iff every target queue has room for all of its records;
// otherwise nothing is accepted and backpressure propagates to the merger, the
// mapper output buffer and finally mapper_ce. Never drops.
//   different banks        -> parallel enqueue
//   same bank, any words   -> both enqueued (r0 first), served back-to-back;
//                             same-word pairs use the bank's RAW bypass
module wm_bank_router
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
#(
  parameter integer CW = 3                       // width of each free count
) (
  input  rec_t                     r0,
  input  rec_t                     r1,
  input  logic [NUM_BANKS*CW-1:0]  bq_free,      // {free[3],..,free[0]}
  output logic                     accept,
  output logic [NUM_BANKS-1:0]     enq0,         // r0 -> bank b
  output logic [NUM_BANKS-1:0]     enq1,         // r1 -> bank b
  output logic                     conflict,     // accepted pair, same bank
  output logic                     same_word     // accepted pair, same bank+word
);
  logic fits;
  always_comb begin
    fits = 1'b1;
    for (int b = 0; b < NUM_BANKS; b++) begin
      if (CW'((r0.v && r0.bank == BANK_ID_W'(b)) ? 1 : 0) +
          CW'((r1.v && r1.bank == BANK_ID_W'(b)) ? 1 : 0) > bq_free[b*CW +: CW])
        fits = 1'b0;
    end
  end
  assign accept = (r0.v || r1.v) && fits;

  always_comb begin
    for (int b = 0; b < NUM_BANKS; b++) begin
      enq0[b] = accept && r0.v && (r0.bank == BANK_ID_W'(b));
      enq1[b] = accept && r1.v && (r1.bank == BANK_ID_W'(b));
    end
  end
  assign conflict  = accept && r0.v && r1.v && (r0.bank == r1.bank);
  assign same_word = conflict && (r0.waddr == r1.waddr);
endmodule
