`timescale 1ns/1ps

module tb_adaptive_directed;

    parameter int X_SIZE = 8;
    parameter int Y_SIZE = 8;
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE);
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE);
    parameter int N_PIXELS = X_SIZE * Y_SIZE;

    parameter int BLOCK_W = 4;
    parameter int BLOCK_H = 4;
    parameter int BLOCK_PIXELS = BLOCK_W * BLOCK_H;
    parameter int BLOCK_X_COUNT = (X_SIZE + BLOCK_W - 1) / BLOCK_W;
    parameter int BLOCK_Y_COUNT = (Y_SIZE + BLOCK_H - 1) / BLOCK_H;
    parameter int BLOCK_X_W = (BLOCK_X_COUNT <= 1) ? 1 : $clog2(BLOCK_X_COUNT);
    parameter int BLOCK_Y_W = (BLOCK_Y_COUNT <= 1) ? 1 : $clog2(BLOCK_Y_COUNT);
    parameter int DENSE_ENTER_THRESHOLD = 5;

    parameter int SPARSE_PACKET_W = 1 + X_W + Y_W + 1;
    parameter int DENSE_PACKET_W = 1 + BLOCK_X_W + BLOCK_Y_W +
                                   BLOCK_PIXELS + BLOCK_PIXELS;
    parameter int PACKET_W = (DENSE_PACKET_W > SPARSE_PACKET_W) ?
                             DENSE_PACKET_W : SPARSE_PACKET_W;
    parameter int MAX_EXPECTED = 256;

    localparam int TYPE_BIT          = 0;
    localparam int SPARSE_X_LSB      = 1;
    localparam int SPARSE_Y_LSB      = SPARSE_X_LSB + X_W;
    localparam int SPARSE_POL_BIT    = SPARSE_Y_LSB + Y_W;
    localparam int DENSE_BLOCK_X_LSB = 1;
    localparam int DENSE_BLOCK_Y_LSB = DENSE_BLOCK_X_LSB + BLOCK_X_W;
    localparam int DENSE_VALID_LSB   = DENSE_BLOCK_Y_LSB + BLOCK_Y_W;
    localparam int DENSE_POL_LSB     = DENSE_VALID_LSB + BLOCK_PIXELS;

    logic clk;
    logic rst_n;
    logic [N_PIXELS-1:0] pixel_event_valid_i;
    logic [N_PIXELS-1:0] pixel_event_pol_i;
    logic aer_req_o;
    logic aer_ack_i;
    logic [PACKET_W-1:0] aer_packet_o;
    logic busy_o;
    logic dense_eligible_o;

    string current_test;
    int test_errors;
    int expected_count;
    int matched_count;
    int expected_x [0:MAX_EXPECTED-1];
    int expected_y [0:MAX_EXPECTED-1];
    int expected_pol [0:MAX_EXPECTED-1];
    bit expected_seen [0:MAX_EXPECTED-1];

    int sparse_packets;
    int dense_packets;
    int events_in_sparse_packets;
    int events_in_dense_packets;
    int max_dense_occupancy;
    int min_dense_occupancy;

    bit monitor_req_active;
    logic [PACKET_W-1:0] monitor_payload;

    bit last_packet_is_dense;
    int last_packet_event_count;
    int last_block_x;
    int last_block_y;
    logic [BLOCK_PIXELS-1:0] last_valid_mask;
    logic [BLOCK_PIXELS-1:0] last_polarity_mask;

    aer_adaptive_top #(
        .X_SIZE(X_SIZE),
        .Y_SIZE(Y_SIZE),
        .X_W(X_W),
        .Y_W(Y_W),
        .N_PIXELS(N_PIXELS),
        .BLOCK_W(BLOCK_W),
        .BLOCK_H(BLOCK_H),
        .BLOCK_PIXELS(BLOCK_PIXELS),
        .BLOCK_X_COUNT(BLOCK_X_COUNT),
        .BLOCK_Y_COUNT(BLOCK_Y_COUNT),
        .BLOCK_X_W(BLOCK_X_W),
        .BLOCK_Y_W(BLOCK_Y_W),
        .DENSE_ENTER_THRESHOLD(DENSE_ENTER_THRESHOLD),
        .SPARSE_PACKET_W(SPARSE_PACKET_W),
        .DENSE_PACKET_W(DENSE_PACKET_W),
        .PACKET_W(PACKET_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_event_valid_i(pixel_event_valid_i),
        .pixel_event_pol_i(pixel_event_pol_i),
        .aer_req_o(aer_req_o),
        .aer_ack_i(aer_ack_i),
        .aer_packet_o(aer_packet_o),
        .busy_o(busy_o),
        .dense_eligible_o(dense_eligible_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("results/waves/adaptive_directed.vcd");
        $dumpvars(0, tb_adaptive_directed);
    end

    function automatic int pixel_index(input int x, input int y);
        begin
            return (y * X_SIZE) + x;
        end
    endfunction

    function automatic int count_bits(input logic [BLOCK_PIXELS-1:0] value);
        int count;
        begin
            count = 0;
            for (int i = 0; i < BLOCK_PIXELS; i++) begin
                if (value[i]) begin
                    count++;
                end
            end
            return count;
        end
    endfunction

    task automatic fail_current(input string message);
        begin
            test_errors++;
            $display("[FAIL] %s: %s", current_test, message);
            $fatal(1);
        end
    endtask

    task automatic check_true(input bit condition, input string message);
        begin
            if (!condition) begin
                fail_current(message);
            end
        end
    endtask

    task automatic reset_scoreboard;
        begin
            expected_count = 0;
            matched_count = 0;
            sparse_packets = 0;
            dense_packets = 0;
            events_in_sparse_packets = 0;
            events_in_dense_packets = 0;
            max_dense_occupancy = 0;
            min_dense_occupancy = BLOCK_PIXELS + 1;
            last_packet_is_dense = 1'b0;
            last_packet_event_count = 0;
            last_block_x = 0;
            last_block_y = 0;
            last_valid_mask = '0;
            last_polarity_mask = '0;
            monitor_req_active = 1'b0;
            monitor_payload = '0;

            for (int i = 0; i < MAX_EXPECTED; i++) begin
                expected_x[i] = -1;
                expected_y[i] = -1;
                expected_pol[i] = -1;
                expected_seen[i] = 1'b0;
            end
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            aer_ack_i = 1'b0;
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            repeat (6) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic begin_test(input string name);
        begin
            current_test = name;
            test_errors = 0;
            reset_scoreboard();
            reset_dut();
        end
    endtask

    task automatic end_test;
        begin
            check_true(test_errors == 0, "test_errors is nonzero");
            $display("[TEST] %-27s PASS", current_test);
        end
    endtask

    task automatic add_expected(input int x, input int y, input int polarity);
        begin
            check_true(expected_count < MAX_EXPECTED, "expected-event storage overflow");
            check_true((x >= 0) && (x < X_SIZE), "expected x outside array");
            check_true((y >= 0) && (y < Y_SIZE), "expected y outside array");
            check_true((polarity == 0) || (polarity == 1), "expected polarity invalid");
            expected_x[expected_count] = x;
            expected_y[expected_count] = y;
            expected_pol[expected_count] = polarity;
            expected_seen[expected_count] = 1'b0;
            expected_count++;
        end
    endtask

    task automatic observe_event(input int x, input int y, input int polarity);
        bit matched;
        begin
            matched = 1'b0;
            if ((x < 0) || (x >= X_SIZE) || (y < 0) || (y >= Y_SIZE) ||
                ((polarity != 0) && (polarity != 1))) begin
                fail_current("decoded output event outside legal range");
            end

            for (int i = 0; i < MAX_EXPECTED; i++) begin
                if (!matched && (i < expected_count) && !expected_seen[i] &&
                    (expected_x[i] == x) && (expected_y[i] == y) &&
                    (expected_pol[i] == polarity)) begin
                    expected_seen[i] = 1'b1;
                    matched_count++;
                    matched = 1'b1;
                end
            end

            if (!matched) begin
                $display("Unexpected event x=%0d y=%0d polarity=%0d", x, y, polarity);
                fail_current("unexpected or duplicate output event");
            end
        end
    endtask

    task automatic decode_and_score_packet(input logic [PACKET_W-1:0] packet);
        int x;
        int y;
        int polarity;
        int block_x;
        int block_y;
        int local_x;
        int local_y;
        int event_count;
        logic [BLOCK_PIXELS-1:0] valid_mask;
        logic [BLOCK_PIXELS-1:0] polarity_mask;
        begin
            check_true((^packet !== 1'bx), "accepted packet contains X/Z");

            last_packet_is_dense = packet[TYPE_BIT];
            last_packet_event_count = 0;
            last_valid_mask = '0;
            last_polarity_mask = '0;
            last_block_x = 0;
            last_block_y = 0;

            if (!packet[TYPE_BIT]) begin
                x = packet[SPARSE_X_LSB +: X_W];
                y = packet[SPARSE_Y_LSB +: Y_W];
                polarity = packet[SPARSE_POL_BIT];
                sparse_packets++;
                events_in_sparse_packets++;
                last_packet_event_count = 1;
                observe_event(x, y, polarity);
            end else begin
                dense_packets++;
                block_x = packet[DENSE_BLOCK_X_LSB +: BLOCK_X_W];
                block_y = packet[DENSE_BLOCK_Y_LSB +: BLOCK_Y_W];
                valid_mask = packet[DENSE_VALID_LSB +: BLOCK_PIXELS];
                polarity_mask = packet[DENSE_POL_LSB +: BLOCK_PIXELS];
                event_count = count_bits(valid_mask);

                check_true(event_count > 0, "dense packet has empty valid mask");
                last_block_x = block_x;
                last_block_y = block_y;
                last_valid_mask = valid_mask;
                last_polarity_mask = polarity_mask;
                last_packet_event_count = event_count;
                events_in_dense_packets += event_count;

                if (event_count > max_dense_occupancy) begin
                    max_dense_occupancy = event_count;
                end
                if (event_count < min_dense_occupancy) begin
                    min_dense_occupancy = event_count;
                end

                for (int local_index = 0; local_index < BLOCK_PIXELS; local_index++) begin
                    if (valid_mask[local_index]) begin
                        local_x = local_index % BLOCK_W;
                        local_y = local_index / BLOCK_W;
                        x = (block_x * BLOCK_W) + local_x;
                        y = (block_y * BLOCK_H) + local_y;
                        polarity = polarity_mask[local_index];
                        observe_event(x, y, polarity);
                    end
                end
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            monitor_req_active <= 1'b0;
            monitor_payload <= '0;
        end else begin
            if (aer_ack_i && !aer_req_o) begin
                fail_current("ACK asserted without REQ");
            end

            if (aer_req_o) begin
                if (!monitor_req_active) begin
                    monitor_req_active <= 1'b1;
                    monitor_payload <= aer_packet_o;
                end else if (aer_packet_o !== monitor_payload) begin
                    fail_current("packet changed while REQ was high");
                end
            end else begin
                monitor_req_active <= 1'b0;
                monitor_payload <= '0;
            end

            if (aer_req_o && aer_ack_i) begin
                decode_and_score_packet(aer_packet_o);
            end
        end
    end

    task automatic pulse_vectors(
        input logic [N_PIXELS-1:0] valid,
        input logic [N_PIXELS-1:0] polarity
    );
        begin
            @(negedge clk);
            pixel_event_valid_i = valid;
            pixel_event_pol_i = polarity;
            @(posedge clk);
            #1;
            @(negedge clk);
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
        end
    endtask

    task automatic pulse_event(input int x, input int y, input int polarity);
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            valid = '0;
            pol = '0;
            valid[pixel_index(x, y)] = 1'b1;
            pol[pixel_index(x, y)] = polarity[0];
            pulse_vectors(valid, pol);
        end
    endtask

    task automatic wait_for_req;
        int wait_cycles;
        begin
            wait_cycles = 0;
            while (!aer_req_o && (wait_cycles < 200)) begin
                @(posedge clk);
                #1;
                wait_cycles++;
            end
            check_true(aer_req_o, "timed out waiting for REQ");
        end
    endtask

    task automatic accept_next_packet(input int ack_delay_cycles,
                                      output logic [PACKET_W-1:0] sampled_packet);
        begin
            wait_for_req();
            sampled_packet = aer_packet_o;

            for (int i = 0; i < ack_delay_cycles; i++) begin
                @(posedge clk);
                #1;
                check_true(aer_req_o, "REQ dropped before ACK");
                check_true(aer_packet_o === sampled_packet,
                           "packet changed during delayed ACK wait");
            end

            @(negedge clk);
            aer_ack_i = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            aer_ack_i = 1'b0;
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic accept_next_packet_with_event(
        input int event_x,
        input int event_y,
        input int event_polarity,
        output logic [PACKET_W-1:0] sampled_packet
    );
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            wait_for_req();
            sampled_packet = aer_packet_o;
            valid = '0;
            pol = '0;
            valid[pixel_index(event_x, event_y)] = 1'b1;
            pol[pixel_index(event_x, event_y)] = event_polarity[0];

            @(negedge clk);
            pixel_event_valid_i = valid;
            pixel_event_pol_i = pol;
            aer_ack_i = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            aer_ack_i = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic drain_expected(input int max_packets);
        logic [PACKET_W-1:0] sampled_packet;
        int packet_count;
        begin
            packet_count = 0;
            while ((matched_count < expected_count) && (packet_count < max_packets)) begin
                accept_next_packet(0, sampled_packet);
                packet_count++;
            end

            check_true(matched_count == expected_count, "not all expected events were observed");

            repeat (8) begin
                @(posedge clk);
                #1;
                check_true(!aer_req_o, "unexpected extra packet after expected drain");
            end
        end
    endtask

    task automatic set_vec_event(
        inout logic [N_PIXELS-1:0] valid,
        inout logic [N_PIXELS-1:0] pol,
        input int x,
        input int y,
        input int polarity
    );
        begin
            valid[pixel_index(x, y)] = 1'b1;
            pol[pixel_index(x, y)] = polarity[0];
        end
    endtask

    task automatic test_sparse_single;
        logic [PACKET_W-1:0] sampled_packet;
        begin
            begin_test("sparse_single");
            add_expected(2, 1, 1);
            pulse_event(2, 1, 1);
            accept_next_packet(0, sampled_packet);
            check_true(!last_packet_is_dense, "single event should use sparse packet");
            check_true(sparse_packets == 1, "single event sparse packet count mismatch");
            check_true(dense_packets == 0, "single event produced dense packet");
            drain_expected(4);
            end_test();
        end
    endtask

    task automatic test_sparse_below_threshold;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            begin_test("sparse_below_threshold");
            valid = '0;
            pol = '0;
            for (int i = 0; i < 4; i++) begin
                set_vec_event(valid, pol, i, 0, i[0]);
                add_expected(i, 0, i[0]);
            end
            pulse_vectors(valid, pol);
            drain_expected(8);
            check_true(dense_packets == 0, "below-threshold block used dense mode");
            check_true(sparse_packets == 4, "below-threshold sparse packet count mismatch");
            end_test();
        end
    endtask

    task automatic test_dense_threshold;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        logic [PACKET_W-1:0] sampled_packet;
        begin
            begin_test("dense_threshold");
            valid = '0;
            pol = '0;
            for (int i = 0; i < DENSE_ENTER_THRESHOLD; i++) begin
                set_vec_event(valid, pol, i % BLOCK_W, i / BLOCK_W, i[0]);
                add_expected(i % BLOCK_W, i / BLOCK_W, i[0]);
            end
            pulse_vectors(valid, pol);
            accept_next_packet(0, sampled_packet);
            check_true(last_packet_is_dense, "threshold occupancy should use dense packet");
            check_true(last_packet_event_count == DENSE_ENTER_THRESHOLD,
                       "threshold dense packet event count mismatch");
            check_true(last_valid_mask[4:0] == 5'b1_1111,
                       "threshold dense valid mask mismatch");
            drain_expected(4);
            end_test();
        end
    endtask

    task automatic test_dense_above_threshold;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        logic [PACKET_W-1:0] sampled_packet;
        begin
            begin_test("dense_above_threshold");
            valid = '0;
            pol = '0;
            for (int i = 0; i < 12; i++) begin
                set_vec_event(valid, pol, i % BLOCK_W, i / BLOCK_W, i[0]);
                add_expected(i % BLOCK_W, i / BLOCK_W, i[0]);
            end
            pulse_vectors(valid, pol);
            accept_next_packet(0, sampled_packet);
            check_true(last_packet_is_dense, "above-threshold block should use dense packet");
            check_true(last_packet_event_count == 12, "dense above-threshold count mismatch");
            drain_expected(4);
            end_test();
        end
    endtask

    task automatic test_spatial_distribution;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            begin_test("spatial_distribution");
            valid = '0;
            pol = '0;
            for (int by = 0; by < BLOCK_Y_COUNT; by++) begin
                for (int bx = 0; bx < BLOCK_X_COUNT; bx++) begin
                    int base_x;
                    int base_y;
                    base_x = bx * BLOCK_W;
                    base_y = by * BLOCK_H;
                    set_vec_event(valid, pol, base_x, base_y, 0);
                    set_vec_event(valid, pol, base_x + 1, base_y, 1);
                    add_expected(base_x, base_y, 0);
                    add_expected(base_x + 1, base_y, 1);
                end
            end
            pulse_vectors(valid, pol);
            drain_expected(12);
            check_true(dense_packets == 0, "distributed traffic should not use dense mode");
            check_true(sparse_packets == 8, "distributed sparse packet count mismatch");
            end_test();
        end
    endtask

    task automatic test_multiple_dense_blocks;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        logic [PACKET_W-1:0] sampled_packet;
        begin
            begin_test("multiple_dense_blocks");
            valid = '0;
            pol = '0;

            for (int i = 0; i < 5; i++) begin
                set_vec_event(valid, pol, i % BLOCK_W, i / BLOCK_W, i[0]);
                add_expected(i % BLOCK_W, i / BLOCK_W, i[0]);
                set_vec_event(valid, pol, BLOCK_W + (i % BLOCK_W), i / BLOCK_W, 1 - i[0]);
                add_expected(BLOCK_W + (i % BLOCK_W), i / BLOCK_W, 1 - i[0]);
            end

            pulse_vectors(valid, pol);
            accept_next_packet(0, sampled_packet);
            check_true(last_packet_is_dense, "first dense block not selected");
            check_true((last_block_x == 0) && (last_block_y == 0),
                       "first dense block should be block 0 after reset");
            accept_next_packet(0, sampled_packet);
            check_true(last_packet_is_dense, "second dense block not selected");
            check_true((last_block_x == 1) && (last_block_y == 0),
                       "second dense block should advance round-robin");
            drain_expected(4);
            check_true(dense_packets == 2, "multiple dense block packet count mismatch");
            end_test();
        end
    endtask

    task automatic test_dense_delayed_ack;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        logic [PACKET_W-1:0] sampled_packet;
        begin
            begin_test("dense_delayed_ack");
            valid = '0;
            pol = '0;
            for (int i = 0; i < 5; i++) begin
                set_vec_event(valid, pol, i % BLOCK_W, 1 + (i / BLOCK_W), i[0]);
                add_expected(i % BLOCK_W, 1 + (i / BLOCK_W), i[0]);
            end
            pulse_vectors(valid, pol);
            accept_next_packet(6, sampled_packet);
            check_true(last_packet_is_dense, "delayed ACK case should use dense packet");
            check_true(last_packet_event_count == 5, "delayed ACK dense count mismatch");
            drain_expected(4);
            end_test();
        end
    endtask

    task automatic test_dense_new_same_block;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        logic [PACKET_W-1:0] sampled_packet;
        begin
            begin_test("dense_new_same_block");
            valid = '0;
            pol = '0;
            for (int i = 0; i < 5; i++) begin
                set_vec_event(valid, pol, i % BLOCK_W, i / BLOCK_W, i[0]);
                add_expected(i % BLOCK_W, i / BLOCK_W, i[0]);
            end
            add_expected(3, 3, 1);
            pulse_vectors(valid, pol);
            accept_next_packet_with_event(3, 3, 1, sampled_packet);
            check_true(last_packet_is_dense, "same-block ACK case should accept dense packet first");
            check_true(!last_valid_mask[15], "same-block new pixel was incorrectly in snapshot");
            drain_expected(8);
            end_test();
        end
    endtask

    task automatic test_dense_clear_and_new;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        logic [PACKET_W-1:0] sampled_packet;
        begin
            begin_test("dense_clear_and_new");
            valid = '0;
            pol = '0;
            for (int i = 0; i < 5; i++) begin
                set_vec_event(valid, pol, i % BLOCK_W, i / BLOCK_W, 0);
                add_expected(i % BLOCK_W, i / BLOCK_W, 0);
            end
            add_expected(2, 0, 1);
            pulse_vectors(valid, pol);
            accept_next_packet_with_event(2, 0, 1, sampled_packet);
            check_true(last_packet_is_dense, "same-pixel clear/new should accept dense packet first");
            drain_expected(8);
            end_test();
        end
    endtask

    task automatic test_mixed_sparse_dense;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            begin_test("mixed_sparse_dense");
            valid = '0;
            pol = '0;
            for (int i = 0; i < 5; i++) begin
                set_vec_event(valid, pol, i % BLOCK_W, i / BLOCK_W, i[0]);
                add_expected(i % BLOCK_W, i / BLOCK_W, i[0]);
            end
            set_vec_event(valid, pol, 7, 7, 1);
            set_vec_event(valid, pol, 6, 5, 0);
            set_vec_event(valid, pol, 0, 6, 1);
            add_expected(7, 7, 1);
            add_expected(6, 5, 0);
            add_expected(0, 6, 1);
            pulse_vectors(valid, pol);
            drain_expected(12);
            check_true(dense_packets == 1, "mixed traffic should contain one dense packet");
            check_true(sparse_packets == 3, "mixed traffic sparse packet count mismatch");
            end_test();
        end
    endtask

    task automatic test_polarity_mask;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        logic [PACKET_W-1:0] sampled_packet;
        logic [BLOCK_PIXELS-1:0] expected_pol_mask;
        begin
            begin_test("polarity_mask");
            valid = '0;
            pol = '0;
            expected_pol_mask = '0;
            for (int i = 0; i < 9; i++) begin
                int px;
                int py;
                int event_pol;
                int local_index;

                px = i % BLOCK_W;
                py = i / BLOCK_W;
                event_pol = ((i * 3) + 1) & 1;
                local_index = (py * BLOCK_W) + px;
                set_vec_event(valid, pol, px, py, event_pol);
                expected_pol_mask[local_index] = event_pol[0];
                add_expected(px, py, event_pol);
            end
            pulse_vectors(valid, pol);
            accept_next_packet(0, sampled_packet);
            check_true(last_packet_is_dense, "polarity-mask case should use dense packet");
            check_true((last_polarity_mask & last_valid_mask) ==
                       (expected_pol_mask & last_valid_mask),
                       "dense polarity mask mismatch");
            drain_expected(4);
            end_test();
        end
    endtask

    task automatic test_full_block;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        logic [PACKET_W-1:0] sampled_packet;
        begin
            begin_test("full_block");
            valid = '0;
            pol = '0;
            for (int y = 0; y < BLOCK_H; y++) begin
                for (int x = 0; x < BLOCK_W; x++) begin
                    int p;
                    p = (x + y) & 1;
                    set_vec_event(valid, pol, x, y, p);
                    add_expected(x, y, p);
                end
            end
            pulse_vectors(valid, pol);
            accept_next_packet(0, sampled_packet);
            check_true(last_packet_is_dense, "full block should use dense packet");
            check_true(last_valid_mask == {BLOCK_PIXELS{1'b1}},
                       "full block valid mask is not all ones");
            check_true(last_packet_event_count == BLOCK_PIXELS,
                       "full block dense event count mismatch");
            drain_expected(4);
            end_test();
        end
    endtask

    initial begin
        test_sparse_single();
        test_sparse_below_threshold();
        test_dense_threshold();
        test_dense_above_threshold();
        test_spatial_distribution();
        test_multiple_dense_blocks();
        test_dense_delayed_ack();
        test_dense_new_same_block();
        test_dense_clear_and_new();
        test_mixed_sparse_dense();
        test_polarity_mask();
        test_full_block();

        $display("");
        $display("ADAPTIVE DIRECTED TESTS: PASS");
        $finish;
    end

endmodule
