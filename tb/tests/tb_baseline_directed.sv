`timescale 1ns/1ps

module tb_baseline_directed;

    localparam int X_SIZE = 4;
    localparam int Y_SIZE = 4;
    localparam int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE);
    localparam int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE);
    localparam int N_PIXELS = X_SIZE * Y_SIZE;
    localparam int EVENT_W = 1 + Y_W + X_W;
    localparam int MAX_EXPECTED = 512;

    logic                clk;
    logic                rst_n;
    logic [N_PIXELS-1:0] pixel_event_valid_i;
    logic [N_PIXELS-1:0] pixel_event_pol_i;
    logic                aer_req_o;
    logic                aer_ack_i;
    logic [EVENT_W-1:0]  aer_event_o;
    logic                busy_o;

    int error_count;
    int expected_count;
    int accepted_count;
    int test_start_errors;
    int exp_x [0:MAX_EXPECTED-1];
    int exp_y [0:MAX_EXPECTED-1];
    int exp_pol [0:MAX_EXPECTED-1];
    bit exp_seen [0:MAX_EXPECTED-1];
    string active_test;

    bit payload_tracking;
    logic [EVENT_W-1:0] tracked_payload;

    aer_baseline_top #(
        .X_SIZE(X_SIZE),
        .Y_SIZE(Y_SIZE),
        .X_W(X_W),
        .Y_W(Y_W),
        .N_PIXELS(N_PIXELS),
        .EVENT_W(EVENT_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_event_valid_i(pixel_event_valid_i),
        .pixel_event_pol_i(pixel_event_pol_i),
        .aer_req_o(aer_req_o),
        .aer_ack_i(aer_ack_i),
        .aer_event_o(aer_event_o),
        .busy_o(busy_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("results/waves/baseline_directed.vcd");
        $dumpvars(0, tb_baseline_directed);
    end

    function automatic int pixel_index(input int x, input int y);
        begin
            return (y * X_SIZE) + x;
        end
    endfunction

    function automatic bit has_unknown_event(input logic [EVENT_W-1:0] value);
        begin
            return (^value === 1'bx);
        end
    endfunction

    function automatic int find_expected(input int x, input int y, input int pol);
        begin
            find_expected = -1;
            for (int i = 0; i < expected_count; i++) begin
                if ((find_expected < 0) &&
                    !exp_seen[i] &&
                    (exp_x[i] == x) &&
                    (exp_y[i] == y) &&
                    (exp_pol[i] == pol)) begin
                    find_expected = i;
                end
            end
        end
    endfunction

    task automatic decode_event(
        input  logic [EVENT_W-1:0] event_payload,
        output int x,
        output int y,
        output int pol
    );
        begin
            x = event_payload[X_W-1:0];
            y = event_payload[X_W + Y_W - 1:X_W];
            pol = event_payload[EVENT_W-1];
        end
    endtask

    task automatic check(input bit condition, input string message);
        begin
            if (!condition) begin
                error_count++;
                $error("[%s] %s", active_test, message);
            end
        end
    endtask

    task automatic reset_scoreboard;
        begin
            expected_count = 0;
            accepted_count = 0;
            for (int i = 0; i < MAX_EXPECTED; i++) begin
                exp_x[i] = 0;
                exp_y[i] = 0;
                exp_pol[i] = 0;
                exp_seen[i] = 1'b0;
            end
        end
    endtask

    task automatic add_expected(input int x, input int y, input int pol);
        begin
            check((x >= 0) && (x < X_SIZE), "expected x coordinate outside array");
            check((y >= 0) && (y < Y_SIZE), "expected y coordinate outside array");
            check((pol == 0) || (pol == 1), "expected polarity must be 0 or 1");
            check(expected_count < MAX_EXPECTED, "expected-event scoreboard overflow");

            exp_x[expected_count] = x;
            exp_y[expected_count] = y;
            exp_pol[expected_count] = pol;
            exp_seen[expected_count] = 1'b0;
            expected_count++;
        end
    endtask

    task automatic check_scoreboard_complete;
        begin
            for (int i = 0; i < expected_count; i++) begin
                if (!exp_seen[i]) begin
                    error_count++;
                    $error("[%s] missing expected event x=%0d y=%0d pol=%0d",
                           active_test, exp_x[i], exp_y[i], exp_pol[i]);
                end
            end

            check(accepted_count == expected_count,
                  "accepted event count does not match expected event count");
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            aer_ack_i = 1'b0;
            payload_tracking = 1'b0;
            tracked_payload = '0;

            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
            #1;

            check(aer_req_o == 1'b0, "aer_req_o must be low after reset");
            check(busy_o == 1'b0, "busy_o must be low after reset");
            check(dut.u_capture.pending_o == '0, "pending bitmap must be clear after reset");
        end
    endtask

    task automatic begin_test(input string name);
        begin
            active_test = name;
            reset_scoreboard();
            test_start_errors = error_count;
            reset_dut();
        end
    endtask

    task automatic finish_test;
        begin
            check_scoreboard_complete();

            if (error_count == test_start_errors) begin
                $display("[TEST] %-20s PASS", active_test);
            end else begin
                $display("[TEST] %-20s FAIL", active_test);
            end

            active_test = "";
        end
    endtask

    task automatic drive_events_one_cycle(
        input logic [N_PIXELS-1:0] valid_mask,
        input logic [N_PIXELS-1:0] polarity_mask
    );
        begin
            @(negedge clk);
            pixel_event_valid_i = valid_mask;
            pixel_event_pol_i = polarity_mask;
            @(negedge clk);
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
        end
    endtask

    task automatic sample_current_request(
        output logic [EVENT_W-1:0] payload,
        output int x,
        output int y,
        output int pol
    );
        int cycles;
        begin
            cycles = 0;
            while (aer_req_o !== 1'b1) begin
                @(posedge clk);
                #1;
                cycles++;
                if (cycles > 128) begin
                    error_count++;
                    $fatal(1, "[%s] timed out waiting for aer_req_o", active_test);
                end
            end

            payload = aer_event_o;
            check(!has_unknown_event(payload), "request payload contains X/Z");
            decode_event(payload, x, y, pol);
            check((x >= 0) && (x < X_SIZE), "request x coordinate outside array");
            check((y >= 0) && (y < Y_SIZE), "request y coordinate outside array");
            check((pol == 0) || (pol == 1), "request polarity outside valid range");
        end
    endtask

    task automatic acknowledge_current(input logic [EVENT_W-1:0] payload);
        begin
            @(negedge clk);
            aer_ack_i = 1'b1;
            @(posedge clk);
            #1;

            check(aer_req_o == 1'b0, "aer_req_o must drop after ACK is sampled high");
            check(aer_event_o === payload, "payload should remain latched after REQ drops");

            @(negedge clk);
            aer_ack_i = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic accept_one(
        input int ack_delay_cycles,
        output int x,
        output int y,
        output int pol
    );
        logic [EVENT_W-1:0] payload;
        begin
            sample_current_request(payload, x, y, pol);

            repeat (ack_delay_cycles) begin
                @(posedge clk);
                #1;
                check(aer_req_o == 1'b1, "aer_req_o changed before delayed ACK");
                check(aer_event_o === payload, "payload changed before delayed ACK");
            end

            acknowledge_current(payload);
        end
    endtask

    task automatic expect_no_req_cycles(input int cycles);
        begin
            repeat (cycles) begin
                @(posedge clk);
                #1;
                check(aer_req_o == 1'b0, "unexpected extra request observed");
            end
        end
    endtask

    always @(posedge clk) begin
        int x;
        int y;
        int pol;
        int match_index;

        if (!rst_n) begin
            payload_tracking = 1'b0;
            tracked_payload = '0;
        end else begin
            if (aer_req_o) begin
                if (!payload_tracking) begin
                    payload_tracking = 1'b1;
                    tracked_payload = aer_event_o;
                end else begin
                    check(aer_event_o === tracked_payload,
                          "aer_event_o changed while aer_req_o was high");
                end
            end else begin
                payload_tracking = 1'b0;
            end

            if (aer_req_o && aer_ack_i) begin
                check(payload_tracking, "accepted event was not tracked under REQ");
                check(aer_event_o === tracked_payload,
                      "accepted payload changed at ACK edge");
                check(!has_unknown_event(aer_event_o),
                      "accepted event contains X/Z");

                decode_event(aer_event_o, x, y, pol);
                check((x >= 0) && (x < X_SIZE), "accepted x coordinate outside array");
                check((y >= 0) && (y < Y_SIZE), "accepted y coordinate outside array");
                check((pol == 0) || (pol == 1), "accepted polarity outside valid range");

                match_index = find_expected(x, y, pol);
                if (match_index < 0) begin
                    error_count++;
                    $error("[%s] unexpected or duplicate event x=%0d y=%0d pol=%0d",
                           active_test, x, y, pol);
                end else begin
                    exp_seen[match_index] = 1'b1;
                end

                accepted_count++;
                payload_tracking = 1'b0;
            end
        end
    end

    task automatic test_single_event;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol_mask;
        int x;
        int y;
        int pol;
        begin
            begin_test("single_event");

            valid = '0;
            pol_mask = '0;
            valid[pixel_index(2, 1)] = 1'b1;
            pol_mask[pixel_index(2, 1)] = 1'b1;
            add_expected(2, 1, 1);

            drive_events_one_cycle(valid, pol_mask);
            accept_one(1, x, y, pol);
            check((x == 2) && (y == 1) && (pol == 1),
                  "single event decoded to wrong x/y/polarity");
            expect_no_req_cycles(3);

            finish_test();
        end
    endtask

    task automatic test_simultaneous_events;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol_mask;
        int x;
        int y;
        int pol;
        begin
            begin_test("simultaneous");

            valid = '0;
            pol_mask = '0;

            valid[pixel_index(0, 0)] = 1'b1;
            pol_mask[pixel_index(0, 0)] = 1'b0;
            add_expected(0, 0, 0);

            valid[pixel_index(3, 0)] = 1'b1;
            pol_mask[pixel_index(3, 0)] = 1'b1;
            add_expected(3, 0, 1);

            valid[pixel_index(1, 2)] = 1'b1;
            pol_mask[pixel_index(1, 2)] = 1'b1;
            add_expected(1, 2, 1);

            valid[pixel_index(2, 3)] = 1'b1;
            pol_mask[pixel_index(2, 3)] = 1'b0;
            add_expected(2, 3, 0);

            drive_events_one_cycle(valid, pol_mask);

            repeat (4) begin
                accept_one(0, x, y, pol);
            end

            expect_no_req_cycles(3);
            finish_test();
        end
    endtask

    task automatic test_round_robin_fairness;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol_mask;
        int x;
        int y;
        int pol;
        begin
            begin_test("round_robin");

            valid = '0;
            pol_mask = '0;

            valid[pixel_index(0, 0)] = 1'b1;
            pol_mask[pixel_index(0, 0)] = 1'b0;
            add_expected(0, 0, 0);

            valid[pixel_index(1, 0)] = 1'b1;
            pol_mask[pixel_index(1, 0)] = 1'b1;
            add_expected(1, 0, 1);

            valid[pixel_index(0, 1)] = 1'b1;
            pol_mask[pixel_index(0, 1)] = 1'b1;
            add_expected(0, 1, 1);

            valid[pixel_index(1, 1)] = 1'b1;
            pol_mask[pixel_index(1, 1)] = 1'b0;
            add_expected(1, 1, 0);

            drive_events_one_cycle(valid, pol_mask);

            accept_one(0, x, y, pol);
            check((x == 0) && (y == 0),
                  "round-robin first grant should start at row 0 column 0");

            accept_one(0, x, y, pol);
            check((x == 1) && (y == 1),
                  "round-robin priority should advance after first accepted event");

            accept_one(0, x, y, pol);
            check((x == 1) && (y == 0),
                  "round-robin row priority should wrap without starving row 0");

            accept_one(0, x, y, pol);
            check((x == 0) && (y == 1),
                  "round-robin should eventually service the remaining requester");

            expect_no_req_cycles(3);
            finish_test();
        end
    endtask

    task automatic test_delayed_ack;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol_mask;
        logic [EVENT_W-1:0] payload;
        int x;
        int y;
        int pol;
        int idx;
        begin
            begin_test("delayed_ack");

            idx = pixel_index(3, 2);
            valid = '0;
            pol_mask = '0;
            valid[idx] = 1'b1;
            pol_mask[idx] = 1'b1;
            add_expected(3, 2, 1);

            drive_events_one_cycle(valid, pol_mask);
            sample_current_request(payload, x, y, pol);
            check((x == 3) && (y == 2) && (pol == 1),
                  "delayed ACK request decoded to wrong event");

            repeat (5) begin
                @(posedge clk);
                #1;
                check(aer_req_o == 1'b1, "REQ must remain high while ACK is delayed");
                check(aer_event_o === payload, "payload must remain stable while ACK is delayed");
                check(dut.u_capture.pending_o[idx] == 1'b1,
                      "pending bit cleared before ACK acceptance");
            end

            acknowledge_current(payload);
            expect_no_req_cycles(3);
            finish_test();
        end
    endtask

    task automatic test_back_to_back_traffic;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol_mask;
        int x;
        int y;
        int pol;
        begin
            begin_test("back_to_back");

            add_expected(0, 0, 0);
            add_expected(1, 0, 1);
            add_expected(2, 0, 0);
            add_expected(0, 1, 1);
            add_expected(3, 3, 1);

            @(negedge clk);
            valid = '0;
            pol_mask = '0;
            valid[pixel_index(0, 0)] = 1'b1;
            pol_mask[pixel_index(0, 0)] = 1'b0;
            pixel_event_valid_i = valid;
            pixel_event_pol_i = pol_mask;

            @(negedge clk);
            valid = '0;
            pol_mask = '0;
            valid[pixel_index(1, 0)] = 1'b1;
            pol_mask[pixel_index(1, 0)] = 1'b1;
            pixel_event_valid_i = valid;
            pixel_event_pol_i = pol_mask;

            @(negedge clk);
            valid = '0;
            pol_mask = '0;
            valid[pixel_index(2, 0)] = 1'b1;
            pol_mask[pixel_index(2, 0)] = 1'b0;
            pixel_event_valid_i = valid;
            pixel_event_pol_i = pol_mask;

            @(negedge clk);
            valid = '0;
            pol_mask = '0;
            valid[pixel_index(0, 1)] = 1'b1;
            pol_mask[pixel_index(0, 1)] = 1'b1;
            pixel_event_valid_i = valid;
            pixel_event_pol_i = pol_mask;

            @(negedge clk);
            valid = '0;
            pol_mask = '0;
            valid[pixel_index(3, 3)] = 1'b1;
            pol_mask[pixel_index(3, 3)] = 1'b1;
            pixel_event_valid_i = valid;
            pixel_event_pol_i = pol_mask;

            @(negedge clk);
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;

            repeat (5) begin
                accept_one(0, x, y, pol);
            end

            expect_no_req_cycles(3);
            finish_test();
        end
    endtask

    task automatic test_repeated_pixel_pending;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol_mask;
        logic [EVENT_W-1:0] payload;
        int x;
        int y;
        int pol;
        int idx;
        begin
            begin_test("repeated_pixel");

            idx = pixel_index(2, 2);
            valid = '0;
            pol_mask = '0;
            valid[idx] = 1'b1;
            pol_mask[idx] = 1'b0;
            add_expected(2, 2, 0);

            drive_events_one_cycle(valid, pol_mask);
            sample_current_request(payload, x, y, pol);

            valid = '0;
            pol_mask = '0;
            valid[idx] = 1'b1;
            pol_mask[idx] = 1'b1;
            drive_events_one_cycle(valid, pol_mask);

            check(dut.u_capture.pending_o[idx] == 1'b1,
                  "same-pixel repeated event should leave one pending event");
            check(dut.u_capture.pending_pol_o[idx] == 1'b0,
                  "same-pixel repeated event must not overwrite pending polarity");

            accept_one(0, x, y, pol);
            check((x == 2) && (y == 2) && (pol == 0),
                  "repeated pending pixel should transmit the original stored event");

            expect_no_req_cycles(5);
            $display("[INFO] repeated_pixel expected one-event-per-pixel capture behavior observed");
            finish_test();
        end
    endtask

    task automatic test_clear_and_new_same_cycle;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol_mask;
        logic [EVENT_W-1:0] payload;
        int x;
        int y;
        int pol;
        int idx;
        begin
            begin_test("clear_and_new");

            idx = pixel_index(1, 1);
            valid = '0;
            pol_mask = '0;
            valid[idx] = 1'b1;
            pol_mask[idx] = 1'b0;
            add_expected(1, 1, 0);

            drive_events_one_cycle(valid, pol_mask);
            sample_current_request(payload, x, y, pol);
            check((x == 1) && (y == 1) && (pol == 0),
                  "clear/new test must first request the old event");

            add_expected(1, 1, 1);

            @(negedge clk);
            valid = '0;
            pol_mask = '0;
            valid[idx] = 1'b1;
            pol_mask[idx] = 1'b1;
            pixel_event_valid_i = valid;
            pixel_event_pol_i = pol_mask;
            aer_ack_i = 1'b1;

            @(posedge clk);
            #1;
            check(aer_req_o == 1'b0, "REQ must drop after accepting old event");
            check(dut.u_capture.pending_o[idx] == 1'b1,
                  "new event must remain pending after same-cycle clear/new");
            check(dut.u_capture.pending_pol_o[idx] == 1'b1,
                  "new event polarity must be captured during same-cycle clear/new");

            @(negedge clk);
            aer_ack_i = 1'b0;
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            @(posedge clk);
            #1;

            accept_one(0, x, y, pol);
            check((x == 1) && (y == 1) && (pol == 1),
                  "same-cycle clear/new should later transmit the new event");

            expect_no_req_cycles(3);
            finish_test();
        end
    endtask

    task automatic test_heavy_simultaneous_traffic;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol_mask;
        int x;
        int y;
        int pol;
        begin
            begin_test("heavy_traffic");

            valid = '0;
            pol_mask = '0;

            for (int yy = 0; yy < Y_SIZE; yy++) begin
                for (int xx = 0; xx < X_SIZE; xx++) begin
                    int idx;
                    int event_pol;

                    idx = pixel_index(xx, yy);
                    event_pol = (xx + yy) & 1;
                    valid[idx] = 1'b1;
                    pol_mask[idx] = event_pol[0];
                    add_expected(xx, yy, event_pol);
                end
            end

            drive_events_one_cycle(valid, pol_mask);

            repeat (N_PIXELS) begin
                accept_one(0, x, y, pol);
            end

            expect_no_req_cycles(4);
            finish_test();
        end
    endtask

    initial begin
        error_count = 0;
        active_test = "";
        reset_scoreboard();

        test_single_event();
        test_simultaneous_events();
        test_round_robin_fairness();
        test_delayed_ack();
        test_back_to_back_traffic();
        test_repeated_pixel_pending();
        test_clear_and_new_same_cycle();
        test_heavy_simultaneous_traffic();

        if (error_count == 0) begin
            $display("");
            $display("BASELINE DIRECTED TESTS: PASS");
        end else begin
            $display("");
            $display("BASELINE DIRECTED TESTS: FAIL (%0d errors)", error_count);
            $fatal(1, "baseline directed tests failed");
        end

        $finish;
    end

endmodule
