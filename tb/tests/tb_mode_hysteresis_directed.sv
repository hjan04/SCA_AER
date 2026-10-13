`timescale 1ns/1ps

module tb_mode_hysteresis_directed;

    localparam int PACKET_W = 8;
    localparam int CLEAR_W = 4;
    localparam int HOLD_CYCLES = 4;

    logic clk;
    logic rst_n;
    logic dense_enter_i;
    logic dense_hold_i;
    logic dense_valid_i;
    logic [PACKET_W-1:0] dense_packet_i;
    logic [CLEAR_W-1:0] dense_clear_mask_i;
    logic sparse_valid_i;
    logic [PACKET_W-1:0] sparse_packet_i;
    logic [CLEAR_W-1:0] sparse_clear_mask_i;
    logic packet_valid_o;
    logic [PACKET_W-1:0] packet_payload_o;
    logic [CLEAR_W-1:0] packet_clear_mask_o;
    logic packet_is_dense_o;
    logic dense_mode_o;
    int errors;

    aer_mode_controller #(
        .PACKET_W(PACKET_W),
        .CLEAR_W(CLEAR_W),
        .HOLD_CYCLES(HOLD_CYCLES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .dense_enter_i(dense_enter_i),
        .dense_hold_i(dense_hold_i),
        .dense_valid_i(dense_valid_i),
        .dense_packet_i(dense_packet_i),
        .dense_clear_mask_i(dense_clear_mask_i),
        .sparse_valid_i(sparse_valid_i),
        .sparse_packet_i(sparse_packet_i),
        .sparse_clear_mask_i(sparse_clear_mask_i),
        .packet_valid_o(packet_valid_o),
        .packet_payload_o(packet_payload_o),
        .packet_clear_mask_o(packet_clear_mask_o),
        .packet_is_dense_o(packet_is_dense_o),
        .dense_mode_o(dense_mode_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                errors++;
                $error("%s", message);
            end
        end
    endtask

    task automatic tick_and_check_dense(input logic expected_dense_mode,
                                        input logic expected_packet_dense,
                                        input string phase);
        begin
            @(posedge clk);
            #1;
            check(dense_mode_o == expected_dense_mode,
                  {phase, ": dense mode state mismatch"});
            check(packet_valid_o, {phase, ": no packet selected"});
            check(packet_is_dense_o == expected_packet_dense,
                  {phase, ": sparse/dense packet selection mismatch"});
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        dense_enter_i = 1'b0;
        dense_hold_i = 1'b0;
        dense_valid_i = 1'b1;
        dense_packet_i = 8'hd3;
        dense_clear_mask_i = 4'hf;
        sparse_valid_i = 1'b1;
        sparse_packet_i = 8'h5a;
        sparse_clear_mask_i = 4'h1;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // Occupancy reaches 3: enter dense mode immediately.
        @(negedge clk);
        dense_enter_i = 1'b1;
        dense_hold_i = 1'b1;
        #1;
        check(packet_is_dense_o, "entry threshold should immediately select dense");
        tick_and_check_dense(1'b1, 1'b1, "entry");

        // Occupancy falls to the exit boundary (<= 1) for three cycles.
        // Dense selection must remain stable; it must not flap to sparse.
        @(negedge clk);
        dense_enter_i = 1'b0;
        dense_hold_i = 1'b0;
        tick_and_check_dense(1'b1, 1'b1, "exit debounce cycle 1");
        tick_and_check_dense(1'b1, 1'b1, "exit debounce cycle 2");
        tick_and_check_dense(1'b1, 1'b1, "exit debounce cycle 3");

        // A transient recovery to occupancy 2 (> exit threshold) resets the
        // counter, proving that boundary oscillation cannot accumulate a false
        // sparse transition.
        @(negedge clk);
        dense_hold_i = 1'b1;
        tick_and_check_dense(1'b1, 1'b1, "boundary recovery");

        @(negedge clk);
        dense_hold_i = 1'b0;
        tick_and_check_dense(1'b1, 1'b1, "second debounce cycle 1");
        tick_and_check_dense(1'b1, 1'b1, "second debounce cycle 2");
        tick_and_check_dense(1'b1, 1'b1, "second debounce cycle 3");
        tick_and_check_dense(1'b0, 1'b0, "second debounce cycle 4");

        if (errors == 0) begin
            $display("MODE HYSTERESIS DIRECTED TEST: PASS");
        end else begin
            $fatal(1, "MODE HYSTERESIS DIRECTED TEST: FAIL (%0d errors)", errors);
        end
        $finish;
    end

endmodule
