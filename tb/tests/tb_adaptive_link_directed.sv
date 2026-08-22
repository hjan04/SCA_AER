`timescale 1ns/1ps

module tb_adaptive_link_directed;

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

    parameter int LINK_WIDTH = 16;
    parameter int MAX_PACKET_W = PACKET_W;
    parameter int TYPE_W = 2;
    parameter int LEN_W = 6;
    parameter int MAX_EXPECTED = 128;

    localparam int ADAPTIVE_SPARSE_TYPE = 1;
    localparam int ADAPTIVE_DENSE_TYPE = 2;
    localparam int AER_TYPE_BIT = 0;
    localparam int SPARSE_X_LSB = 1;
    localparam int SPARSE_Y_LSB = SPARSE_X_LSB + X_W;
    localparam int SPARSE_POL_BIT = SPARSE_Y_LSB + Y_W;
    localparam int DENSE_BLOCK_X_LSB = 1;
    localparam int DENSE_BLOCK_Y_LSB = DENSE_BLOCK_X_LSB + BLOCK_X_W;
    localparam int DENSE_VALID_LSB = DENSE_BLOCK_Y_LSB + BLOCK_Y_W;
    localparam int DENSE_POL_LSB = DENSE_VALID_LSB + BLOCK_PIXELS;

    logic clk;
    logic rst_n;
    logic [N_PIXELS-1:0] pixel_event_valid_i;
    logic [N_PIXELS-1:0] pixel_event_pol_i;
    logic link_valid;
    logic link_ready;
    logic [LINK_WIDTH-1:0] link_data;
    logic sink_ready;
    logic busy_o;
    logic dense_eligible_o;
    logic logical_packet_accept;
    logic [TYPE_W-1:0] logical_packet_type;
    logic [LEN_W-1:0] logical_packet_bits;
    logic [MAX_PACKET_W-1:0] logical_packet_data;
    logic [N_PIXELS-1:0] logical_packet_clear_mask;

    logic packet_valid;
    logic packet_ready;
    logic [TYPE_W-1:0] packet_type;
    logic [LEN_W-1:0] packet_bits;
    logic [MAX_PACKET_W-1:0] packet_data;
    logic deser_busy;

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
    int last_packet_event_count;
    bit last_packet_dense;
    logic [BLOCK_PIXELS-1:0] last_valid_mask;
    logic [BLOCK_PIXELS-1:0] last_polarity_mask;
    bit link_stall_active;
    logic [LINK_WIDTH-1:0] stalled_link_data;

    aer_adaptive_link_top #(
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
        .PACKET_W(PACKET_W),
        .LINK_WIDTH(LINK_WIDTH),
        .MAX_PACKET_W(MAX_PACKET_W),
        .LINK_TYPE_W(TYPE_W),
        .LINK_LEN_W(LEN_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_event_valid_i(pixel_event_valid_i),
        .pixel_event_pol_i(pixel_event_pol_i),
        .link_valid_o(link_valid),
        .link_ready_i(link_ready),
        .link_data_o(link_data),
        .busy_o(busy_o),
        .dense_eligible_o(dense_eligible_o),
        .logical_packet_accept_o(logical_packet_accept),
        .logical_packet_type_o(logical_packet_type),
        .logical_packet_bits_o(logical_packet_bits),
        .logical_packet_data_o(logical_packet_data),
        .logical_packet_clear_mask_o(logical_packet_clear_mask)
    );

    aer_link_deserializer #(
        .LINK_WIDTH(LINK_WIDTH),
        .MAX_PACKET_W(MAX_PACKET_W),
        .TYPE_W(TYPE_W),
        .LEN_W(LEN_W)
    ) u_deserializer (
        .clk(clk),
        .rst_n(rst_n),
        .link_valid_i(link_valid),
        .link_ready_o(link_ready),
        .link_data_i(link_data),
        .sink_ready_i(sink_ready),
        .packet_valid_o(packet_valid),
        .packet_ready_i(packet_ready),
        .packet_type_o(packet_type),
        .packet_bits_o(packet_bits),
        .packet_data_o(packet_data),
        .busy_o(deser_busy)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
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
            last_packet_event_count = 0;
            last_packet_dense = 1'b0;
            last_valid_mask = '0;
            last_polarity_mask = '0;
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
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            sink_ready = 1'b1;
            packet_ready = 1'b1;
            link_stall_active = 1'b0;
            stalled_link_data = '0;
            repeat (5) @(posedge clk);
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
            check_true(matched_count == expected_count, "not all expected events observed");
            $display("[TEST] %-30s PASS", current_test);
        end
    endtask

    task automatic add_expected(input int x, input int y, input int polarity);
        begin
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
                fail_current("unexpected or duplicate reconstructed event");
            end
        end
    endtask

    task automatic decode_packet;
        int x;
        int y;
        int polarity;
        int block_x;
        int block_y;
        int local_x;
        int local_y;
        logic [BLOCK_PIXELS-1:0] valid_mask;
        logic [BLOCK_PIXELS-1:0] polarity_mask;
        begin
            last_packet_dense = 1'b0;
            last_packet_event_count = 0;
            last_valid_mask = '0;
            last_polarity_mask = '0;

            if (packet_type == TYPE_W'(ADAPTIVE_SPARSE_TYPE)) begin
                check_true(packet_bits == LEN_W'(SPARSE_PACKET_W),
                           "adaptive sparse payload length mismatch");
                check_true(packet_data[AER_TYPE_BIT] == 1'b0,
                           "adaptive sparse payload type bit mismatch");
                x = packet_data[SPARSE_X_LSB +: X_W];
                y = packet_data[SPARSE_Y_LSB +: Y_W];
                polarity = packet_data[SPARSE_POL_BIT];
                sparse_packets++;
                last_packet_event_count = 1;
                observe_event(x, y, polarity);
            end else if (packet_type == TYPE_W'(ADAPTIVE_DENSE_TYPE)) begin
                check_true(packet_bits == LEN_W'(DENSE_PACKET_W),
                           "adaptive dense payload length mismatch");
                check_true(packet_data[AER_TYPE_BIT] == 1'b1,
                           "adaptive dense payload type bit mismatch");
                block_x = packet_data[DENSE_BLOCK_X_LSB +: BLOCK_X_W];
                block_y = packet_data[DENSE_BLOCK_Y_LSB +: BLOCK_Y_W];
                valid_mask = packet_data[DENSE_VALID_LSB +: BLOCK_PIXELS];
                polarity_mask = packet_data[DENSE_POL_LSB +: BLOCK_PIXELS];
                dense_packets++;
                last_packet_dense = 1'b1;
                last_valid_mask = valid_mask;
                last_polarity_mask = polarity_mask;
                last_packet_event_count = count_bits(valid_mask);
                check_true(last_packet_event_count > 0, "dense packet valid mask is empty");

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
            end else begin
                fail_current("unexpected transport packet type");
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            link_stall_active <= 1'b0;
            stalled_link_data <= '0;
        end else begin
            if (link_valid && !link_ready) begin
                if (!link_stall_active) begin
                    link_stall_active <= 1'b1;
                    stalled_link_data <= link_data;
                end else if (link_data !== stalled_link_data) begin
                    fail_current("link_data changed while link was stalled");
                end
            end else begin
                link_stall_active <= 1'b0;
                stalled_link_data <= '0;
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

    task automatic wait_and_decode_packet;
        int wait_cycles;
        begin
            wait_cycles = 0;
            while (!packet_valid && (wait_cycles < 300)) begin
                @(posedge clk);
                #1;
                wait_cycles++;
            end
            check_true(packet_valid, "timed out waiting for reconstructed packet");
            decode_packet();
            @(posedge clk);
            #1;
        end
    endtask

    task automatic drain_expected(input int max_packets);
        int packet_count;
        begin
            packet_count = 0;
            while ((matched_count < expected_count) && (packet_count < max_packets)) begin
                wait_and_decode_packet();
                packet_count++;
            end
            check_true(matched_count == expected_count, "drain did not deliver expected events");
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

    task automatic make_dense_block(
        output logic [N_PIXELS-1:0] valid,
        output logic [N_PIXELS-1:0] pol,
        input int count,
        input int polarity_base
    );
        begin
            valid = '0;
            pol = '0;
            for (int i = 0; i < count; i++) begin
                set_vec_event(valid, pol, i % BLOCK_W, i / BLOCK_W,
                              (polarity_base + i) & 1);
                add_expected(i % BLOCK_W, i / BLOCK_W,
                             (polarity_base + i) & 1);
            end
        end
    endtask

    task automatic wait_for_logical_accept;
        int wait_cycles;
        begin
            wait_cycles = 0;
            while (!logical_packet_accept && (wait_cycles < 100)) begin
                @(negedge clk);
                wait_cycles++;
            end
            check_true(logical_packet_accept, "timed out waiting for logical packet accept");
        end
    endtask

    task automatic test_sparse_single;
        begin
            begin_test("sparse_single");
            add_expected(2, 1, 1);
            pulse_event(2, 1, 1);
            wait_and_decode_packet();
            check_true(!last_packet_dense, "single event should reconstruct as sparse");
            end_test();
        end
    endtask

    task automatic test_dense_threshold;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            begin_test("dense_threshold");
            make_dense_block(valid, pol, 5, 0);
            pulse_vectors(valid, pol);
            wait_and_decode_packet();
            check_true(last_packet_dense, "threshold case should reconstruct dense");
            check_true(last_packet_event_count == 5, "dense threshold event count mismatch");
            end_test();
        end
    endtask

    task automatic test_dense_link_backpressure;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            begin_test("dense_link_backpressure");
            make_dense_block(valid, pol, 8, 1);
            pulse_vectors(valid, pol);
            wait_for_logical_accept();
            @(negedge clk);
            sink_ready = 1'b0;
            repeat (5) @(posedge clk);
            @(negedge clk);
            sink_ready = 1'b1;
            drain_expected(4);
            check_true(dense_packets == 1, "backpressured dense packet count mismatch");
            end_test();
        end
    endtask

    task automatic test_dense_new_same_block_during_multibeat;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            begin_test("dense_new_same_block");
            make_dense_block(valid, pol, 5, 0);
            add_expected(3, 3, 1);
            pulse_vectors(valid, pol);
            wait_for_logical_accept();
            @(negedge clk);
            sink_ready = 1'b0;
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            pixel_event_valid_i[pixel_index(3, 3)] = 1'b1;
            pixel_event_pol_i[pixel_index(3, 3)] = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            sink_ready = 1'b1;
            drain_expected(8);
            check_true(dense_packets >= 1,
                       "new same-block case should preserve the initial dense snapshot");
            end_test();
        end
    endtask

    task automatic test_dense_clear_and_new_same_pixel;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
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
            wait_for_logical_accept();

            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            pixel_event_valid_i[pixel_index(2, 0)] = 1'b1;
            pixel_event_pol_i[pixel_index(2, 0)] = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;

            drain_expected(8);
            check_true(dense_packets >= 1,
                       "same-pixel clear/new should preserve the initial dense snapshot");
            end_test();
        end
    endtask

    task automatic test_full_block;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            begin_test("full_block");
            make_dense_block(valid, pol, BLOCK_PIXELS, 0);
            pulse_vectors(valid, pol);
            wait_and_decode_packet();
            check_true(last_packet_dense, "full block should reconstruct dense");
            check_true(last_valid_mask == {BLOCK_PIXELS{1'b1}},
                       "full block dense valid mask mismatch");
            check_true(last_packet_event_count == BLOCK_PIXELS,
                       "full block event count mismatch");
            end_test();
        end
    endtask

    initial begin
        test_sparse_single();
        test_dense_threshold();
        test_dense_link_backpressure();
        test_dense_new_same_block_during_multibeat();
        test_dense_clear_and_new_same_pixel();
        test_full_block();

        $display("");
        $display("ADAPTIVE LINK DIRECTED TESTS: PASS");
        $finish;
    end

endmodule
