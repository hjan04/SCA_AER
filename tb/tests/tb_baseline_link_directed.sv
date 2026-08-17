`timescale 1ns/1ps

module tb_baseline_link_directed;

    parameter int X_SIZE = 4;
    parameter int Y_SIZE = 4;
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE);
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE);
    parameter int N_PIXELS = X_SIZE * Y_SIZE;
    parameter int EVENT_W = 1 + X_W + Y_W;
    parameter int LINK_WIDTH = 16;
    parameter int MAX_PACKET_W = 37;
    parameter int TYPE_W = 2;
    parameter int LEN_W = 6;
    parameter int MAX_EXPECTED = 64;

    localparam int BASELINE_SPARSE_TYPE = 0;

    logic clk;
    logic rst_n;
    logic [N_PIXELS-1:0] pixel_event_valid_i;
    logic [N_PIXELS-1:0] pixel_event_pol_i;
    logic link_valid;
    logic link_ready;
    logic [LINK_WIDTH-1:0] link_data;
    logic sink_ready;
    logic busy_o;
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
    bit link_stall_active;
    logic [LINK_WIDTH-1:0] stalled_link_data;

    aer_baseline_link_top #(
        .X_SIZE(X_SIZE),
        .Y_SIZE(Y_SIZE),
        .X_W(X_W),
        .Y_W(Y_W),
        .N_PIXELS(N_PIXELS),
        .EVENT_W(EVENT_W),
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
            $display("[TEST] %-24s PASS", current_test);
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
        begin
            check_true(packet_type == BASELINE_SPARSE_TYPE[TYPE_W-1:0],
                       "baseline link packet type mismatch");
            check_true(packet_bits == LEN_W'(EVENT_W),
                       "baseline link payload length mismatch");
            x = packet_data[X_W-1:0];
            y = packet_data[X_W + Y_W - 1:X_W];
            polarity = packet_data[EVENT_W-1];
            observe_event(x, y, polarity);
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
            while (!packet_valid && (wait_cycles < 200)) begin
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

    task automatic test_single_event;
        begin
            begin_test("single_event");
            add_expected(2, 1, 1);
            pulse_event(2, 1, 1);
            drain_expected(4);
            end_test();
        end
    endtask

    task automatic test_simultaneous;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        begin
            begin_test("simultaneous");
            valid = '0;
            pol = '0;
            set_vec_event(valid, pol, 0, 0, 0);
            set_vec_event(valid, pol, 1, 0, 1);
            set_vec_event(valid, pol, 2, 2, 0);
            set_vec_event(valid, pol, 3, 3, 1);
            add_expected(0, 0, 0);
            add_expected(1, 0, 1);
            add_expected(2, 2, 0);
            add_expected(3, 3, 1);
            pulse_vectors(valid, pol);
            drain_expected(8);
            end_test();
        end
    endtask

    task automatic test_link_backpressure;
        begin
            begin_test("link_backpressure");
            add_expected(1, 2, 1);
            pulse_event(1, 2, 1);
            @(posedge clk);
            @(negedge clk);
            sink_ready = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            sink_ready = 1'b1;
            drain_expected(4);
            end_test();
        end
    endtask

    task automatic test_clear_and_new;
        logic [N_PIXELS-1:0] valid;
        logic [N_PIXELS-1:0] pol;
        int wait_cycles;
        begin
            begin_test("clear_and_new");
            add_expected(2, 2, 0);
            add_expected(2, 2, 1);
            pulse_event(2, 2, 0);

            wait_cycles = 0;
            while (!logical_packet_accept && (wait_cycles < 50)) begin
                @(negedge clk);
                wait_cycles++;
            end
            check_true(logical_packet_accept, "timed out waiting for logical accept");

            valid = '0;
            pol = '0;
            valid[pixel_index(2, 2)] = 1'b1;
            pol[pixel_index(2, 2)] = 1'b1;
            pixel_event_valid_i = valid;
            pixel_event_pol_i = pol;
            @(posedge clk);
            #1;
            @(negedge clk);
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;

            drain_expected(4);
            end_test();
        end
    endtask

    initial begin
        test_single_event();
        test_simultaneous();
        test_link_backpressure();
        test_clear_and_new();

        $display("");
        $display("BASELINE LINK DIRECTED TESTS: PASS");
        $finish;
    end

endmodule
