`timescale 1ns/1ps

// Capture/buffer boundary test for one 4x4 block.  clear_i models the clear
// mask held by an accepted sparse/dense packet; keeping it zero models a
// serializer that is busy transmitting an already-snapshotted packet.
module tb_capture_overflow_integration_directed;
    localparam int N = 16;
    logic clk, rst_n;
    logic [N-1:0] ev, pol, clear;
    logic [N-1:0] pending, pending_pol, push_req, push_pol, promote_hit, promote_pol;
    logic [4:0] primary_count;
    logic [N-1:0] reject;
    logic [1:0] overflow_count;
    logic [7:0] overflow_loss;
    logic [N-1:0] legacy_pending, legacy_pol, disabled_pending, disabled_pol;
    logic [4:0] legacy_count, disabled_count;
    int errors;

    always #5 clk = ~clk;

    aer_event_capture #(.N_PIXELS(N), .OVERFLOW_ENABLE(1), .COUNT_W(5)) capture (
        .clk, .rst_n, .pixel_event_valid_i(ev), .pixel_event_pol_i(pol), .clear_i(clear),
        .promote_hit_i(promote_hit), .promote_pol_i(promote_pol),
        .pending_o(pending), .pending_pol_o(pending_pol), .overflow_push_req_o(push_req),
        .overflow_push_pol_o(push_pol), .primary_unique_occupancy_o(primary_count));
    aer_block_overflow_buffer #(.OVERFLOW_DEPTH(3), .BLOCK_PIXELS(N), .LOSS_COUNT_W(8)) buffer (
        .clk, .rst_n, .push_req_i(push_req), .push_polarity_i(push_pol), .push_reject_o(reject),
        .promote_mask_i(clear), .promote_hit_o(promote_hit), .promote_pol_o(promote_pol),
        .overflow_count_o(overflow_count), .overflow_loss_count_o(overflow_loss));

    // Test 5 reference pair: Model2 legacy capture versus depth-zero path.
    aer_event_capture #(.N_PIXELS(N), .OVERFLOW_ENABLE(0), .COUNT_W(5)) legacy (
        .clk, .rst_n, .pixel_event_valid_i(ev), .pixel_event_pol_i(pol), .clear_i(clear),
        .promote_hit_i('0), .promote_pol_i('0), .pending_o(legacy_pending), .pending_pol_o(legacy_pol),
        .overflow_push_req_o(), .overflow_push_pol_o(), .primary_unique_occupancy_o(legacy_count));
    aer_event_capture #(.N_PIXELS(N), .OVERFLOW_ENABLE(0), .COUNT_W(5)) depth_zero (
        .clk, .rst_n, .pixel_event_valid_i(ev), .pixel_event_pol_i(pol), .clear_i(clear),
        .promote_hit_i('1), .promote_pol_i('1), .pending_o(disabled_pending), .pending_pol_o(disabled_pol),
        .overflow_push_req_o(), .overflow_push_pol_o(), .primary_unique_occupancy_o(disabled_count));

    task automatic check(input logic ok, input string msg);
        if (!ok) begin errors++; $error("%s", msg); end
    endtask
    task automatic tick;
        @(posedge clk); #1;
        check({legacy_pending,legacy_pol,legacy_count} == {disabled_pending,disabled_pol,disabled_count},
              "depth-zero capture differs from Model2 legacy capture");
    endtask
    task automatic reset;
        ev='0; pol='0; clear='0; rst_n=0; repeat (2) tick(); rst_n=1; tick();
    endtask
    task automatic inject(input logic [N-1:0] v, input logic [N-1:0] p);
        ev=v; pol=p; clear='0; tick(); ev='0; tick();
    endtask

    initial begin
        clk=0; errors=0; reset();

        // 1. Dense clear promotes independent entries in the same cycle.
        inject(16'h1082, 16'h1002); inject(16'h1082, 16'h0080);
        clear=16'h1082; #1;
        check(promote_hit==16'h1082 && promote_pol==16'h0080, "dense simultaneous promotion mismatch");
        tick(); clear='0; tick();
        check(pending==16'h1082 && pending_pol==16'h0080 && overflow_count==0,
              "dense promotions were not installed in primary slots");

        // 2. Promotion owns primary; same-cycle input becomes the next entry.
        inject(16'h0002,16'h0002); // queue older polarity=1 for local index 1
        clear=16'h0002; ev=16'h0002; pol='0; #1;
        check(promote_hit[1] && promote_pol[1] && push_req[1], "promotion/new-input priority mismatch");
        tick(); clear='0; ev='0; tick();
        check(pending[1] && pending_pol[1] && overflow_count==1, "older event was not retained first");
        clear=16'h0002; #1; check(promote_hit[1] && !promote_pol[1], "FIFO polarity order mismatch");
        tick(); clear='0; tick();

        // 3. Multiple already-pending pixels re-fire in one cycle: multi-push.
        inject(16'h000d,16'h0000); ev=16'h000d; pol=16'h0005; clear='0; #1;
        check(push_req==16'h000d && reject==0, "multi-push request vector mismatch");
        tick(); ev='0; tick(); check(overflow_count==3, "multi-push entries not stored");

        // 4. Busy serializer: no clear means queued data cannot mutate snapshot.
        repeat (3) begin
            clear='0; tick();
            check(!promote_hit[0] && pending[0], "promotion occurred before packet clear/accept");
        end

        // 5 is checked by tick() throughout this sequence.
        if (errors==0) $display("CAPTURE OVERFLOW INTEGRATION DIRECTED TEST: PASS");
        else $fatal(1,"CAPTURE OVERFLOW INTEGRATION DIRECTED TEST: FAIL (%0d errors)",errors);
        $finish;
    end
endmodule
