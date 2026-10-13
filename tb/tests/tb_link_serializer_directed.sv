`timescale 1ns/1ps

module tb_link_serializer_directed;

    parameter int LINK_WIDTH = 16;
    parameter int MAX_PACKET_W = 37;
    parameter int TYPE_W = 2;
    parameter int LEN_W = 6;

    logic clk;
    logic rst_n;

    logic packet_valid_i;
    logic packet_ready_o;
    logic [TYPE_W-1:0] packet_type_i;
    logic [LEN_W-1:0] packet_bits_i;
    logic [MAX_PACKET_W-1:0] packet_data_i;
    logic link_valid;
    logic link_ready;
    logic [LINK_WIDTH-1:0] link_data;
    logic packet_accept;
    logic serializer_busy;

    logic sink_ready;
    logic packet_valid_o;
    logic packet_ready_i;
    logic [TYPE_W-1:0] packet_type_o;
    logic [LEN_W-1:0] packet_bits_o;
    logic [MAX_PACKET_W-1:0] packet_data_o;
    logic deserializer_busy;

    string current_test;
    int test_errors;
    bit monitor_link_active;
    logic [LINK_WIDTH-1:0] monitor_link_data;

    aer_link_serializer #(
        .LINK_WIDTH(LINK_WIDTH),
        .MAX_PACKET_W(MAX_PACKET_W),
        .TYPE_W(TYPE_W),
        .LEN_W(LEN_W)
    ) u_serializer (
        .clk(clk),
        .rst_n(rst_n),
        .packet_valid_i(packet_valid_i),
        .packet_ready_o(packet_ready_o),
        .packet_type_i(packet_type_i),
        .packet_bits_i(packet_bits_i),
        .packet_data_i(packet_data_i),
        .link_valid_o(link_valid),
        .link_ready_i(link_ready),
        .link_data_o(link_data),
        .packet_accept_o(packet_accept),
        .busy_o(serializer_busy)
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
        .packet_valid_o(packet_valid_o),
        .packet_ready_i(packet_ready_i),
        .packet_type_o(packet_type_o),
        .packet_bits_o(packet_bits_o),
        .packet_data_o(packet_data_o),
        .busy_o(deserializer_busy)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [MAX_PACKET_W-1:0] mask_data(
        input logic [MAX_PACKET_W-1:0] data,
        input int bits
    );
        logic [MAX_PACKET_W-1:0] mask;
        begin
            mask = '0;
            for (int i = 0; i < MAX_PACKET_W; i++) begin
                if (i < bits) begin
                    mask[i] = 1'b1;
                end
            end
            return data & mask;
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

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            packet_valid_i = 1'b0;
            packet_type_i = '0;
            packet_bits_i = '0;
            packet_data_i = '0;
            sink_ready = 1'b1;
            packet_ready_i = 1'b1;
            monitor_link_active = 1'b0;
            monitor_link_data = '0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic begin_test(input string name);
        begin
            current_test = name;
            test_errors = 0;
            reset_dut();
        end
    endtask

    task automatic end_test;
        begin
            check_true(test_errors == 0, "test_errors is nonzero");
            $display("[TEST] %-28s PASS", current_test);
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            monitor_link_active <= 1'b0;
            monitor_link_data <= '0;
        end else begin
            if (link_valid && !link_ready) begin
                if (!monitor_link_active) begin
                    monitor_link_active <= 1'b1;
                    monitor_link_data <= link_data;
                end else if (link_data !== monitor_link_data) begin
                    fail_current("link_data changed while stalled");
                end
            end else begin
                monitor_link_active <= 1'b0;
                monitor_link_data <= '0;
            end
        end
    end

    task automatic drive_packet(
        input logic [TYPE_W-1:0] packet_type,
        input int bits,
        input logic [MAX_PACKET_W-1:0] data
    );
        int wait_cycles;
        begin
            wait_cycles = 0;
            @(negedge clk);
            packet_type_i = packet_type;
            packet_bits_i = LEN_W'(bits);
            packet_data_i = data;
            packet_valid_i = 1'b1;

            while (!packet_ready_o && (wait_cycles < 100)) begin
                @(posedge clk);
                #1;
                wait_cycles++;
            end
            check_true(packet_ready_o, "timed out waiting for packet_ready");

            @(posedge clk);
            #1;
            @(negedge clk);
            packet_valid_i = 1'b0;
            packet_type_i = '0;
            packet_bits_i = '0;
            packet_data_i = '0;
        end
    endtask

    task automatic expect_packet(
        input logic [TYPE_W-1:0] packet_type,
        input int bits,
        input logic [MAX_PACKET_W-1:0] data
    );
        int wait_cycles;
        begin
            wait_cycles = 0;
            while (!packet_valid_o && (wait_cycles < 100)) begin
                @(posedge clk);
                #1;
                wait_cycles++;
            end

            check_true(packet_valid_o, "timed out waiting for reconstructed packet");
            check_true(packet_type_o == packet_type, "packet type mismatch");
            check_true(packet_bits_o == LEN_W'(bits), "packet bit length mismatch");
            check_true(mask_data(packet_data_o, bits) == mask_data(data, bits),
                       "packet payload mismatch");
            @(posedge clk);
            #1;
        end
    endtask

    task automatic send_and_expect(
        input logic [TYPE_W-1:0] packet_type,
        input int bits,
        input logic [MAX_PACKET_W-1:0] data
    );
        fork
            drive_packet(packet_type, bits, data);
            expect_packet(packet_type, bits, data);
        join
    endtask

    task automatic test_one_beat;
        begin
            begin_test("one_beat_packet");
            send_and_expect(2'd1, 4, 37'ha);
            end_test();
        end
    endtask

    task automatic test_two_beat;
        begin
            begin_test("two_beat_packet");
            send_and_expect(2'd0, 9, 37'h123);
            end_test();
        end
    endtask

    task automatic test_three_beat;
        begin
            begin_test("three_beat_packet");
            send_and_expect(2'd2, 37, 37'h155aa5c33);
            end_test();
        end
    endtask

    task automatic test_non_multiple_width;
        begin
            begin_test("non_multiple_width");
            send_and_expect(2'd2, 33, 37'h6a123455a);
            end_test();
        end
    endtask

    task automatic test_middle_backpressure;
        logic [MAX_PACKET_W-1:0] data;
        int accepted_beats;
        int wait_cycles;
        begin
            begin_test("middle_backpressure");
            data = 37'h15500ff12;
            accepted_beats = 0;

            wait_cycles = 0;
            drive_packet(2'd2, 37, data);
            while ((accepted_beats < 1) && (wait_cycles < 100)) begin
                @(posedge clk);
                #1;
                if (link_valid && link_ready) begin
                    accepted_beats++;
                end
                wait_cycles++;
            end
            check_true(accepted_beats == 1, "timed out waiting for first accepted beat");

            @(negedge clk);
            sink_ready = 1'b0;
            repeat (3) begin
                @(posedge clk);
                #1;
                check_true(link_valid, "link_valid dropped during middle backpressure");
            end
            @(negedge clk);
            sink_ready = 1'b1;
            expect_packet(2'd2, 37, data);
            end_test();
        end
    endtask

    task automatic test_final_backpressure;
        logic [MAX_PACKET_W-1:0] data;
        int accepted_beats;
        int wait_cycles;
        begin
            begin_test("final_backpressure");
            data = 37'h1a5;
            accepted_beats = 0;

            wait_cycles = 0;
            drive_packet(2'd0, 9, data);
            while ((accepted_beats < 1) && (wait_cycles < 100)) begin
                @(posedge clk);
                #1;
                if (link_valid && link_ready) begin
                    accepted_beats++;
                end
                wait_cycles++;
            end
            check_true(accepted_beats == 1, "timed out waiting for first accepted beat");

            @(negedge clk);
            sink_ready = 1'b0;
            repeat (2) begin
                @(posedge clk);
                #1;
                check_true(link_valid, "link_valid dropped during final backpressure");
            end
            @(negedge clk);
            sink_ready = 1'b1;
            expect_packet(2'd0, 9, data);
            end_test();
        end
    endtask

    task automatic test_back_to_back;
        logic [MAX_PACKET_W-1:0] data0;
        logic [MAX_PACKET_W-1:0] data1;
        begin
            begin_test("back_to_back_packets");
            data0 = 37'h42;
            data1 = 37'h1550f0f0f;

            fork
                begin
                    drive_packet(2'd1, 10, data0);
                    drive_packet(2'd2, 37, data1);
                end
                begin
                    expect_packet(2'd1, 10, data0);
                    expect_packet(2'd2, 37, data1);
                end
            join
            end_test();
        end
    endtask

    task automatic test_different_lengths;
        begin
            begin_test("different_lengths");
            send_and_expect(2'd1, 10, 37'h2aa);
            send_and_expect(2'd2, 21, 37'ha5a5a);
            send_and_expect(2'd0, 9, 37'h155);
            end_test();
        end
    endtask

    task automatic test_reset_idle;
        begin
            begin_test("reset_idle");
            repeat (4) @(posedge clk);
            check_true(!link_valid, "link_valid asserted after idle reset");
            check_true(packet_ready_o, "packet_ready not high after idle reset");
            end_test();
        end
    endtask

    initial begin
        test_one_beat();
        test_two_beat();
        test_three_beat();
        test_non_multiple_width();
        test_middle_backpressure();
        test_final_backpressure();
        test_back_to_back();
        test_different_lengths();
        test_reset_idle();

        $display("");
        $display("LINK SERIALIZER DIRECTED TESTS: PASS");
        $finish;
    end

endmodule
