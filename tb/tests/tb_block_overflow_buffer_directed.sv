`timescale 1ns/1ps

module tb_block_overflow_buffer_directed;
    localparam int BLOCK_PIXELS = 16;

    logic clk;
    logic rst_n;
    logic push_req;
    logic [3:0] push_local_idx;
    logic push_polarity;
    logic push_full_o;
    logic [BLOCK_PIXELS-1:0] promote_mask_i;
    logic [BLOCK_PIXELS-1:0] promote_hit_o;
    logic [BLOCK_PIXELS-1:0] promote_pol_o;
    logic [1:0] overflow_count_o;
    logic [7:0] overflow_loss_count_o;

    logic disabled_push_full_o;
    logic [BLOCK_PIXELS-1:0] disabled_promote_hit_o;
    logic [BLOCK_PIXELS-1:0] disabled_promote_pol_o;
    logic disabled_overflow_count_o;
    logic [7:0] disabled_overflow_loss_count_o;

    int errors;

    aer_block_overflow_buffer #(
        .OVERFLOW_DEPTH(3),
        .BLOCK_PIXELS(BLOCK_PIXELS),
        .LOSS_COUNT_W(8)
    ) dut (
        .clk,
        .rst_n,
        .push_req,
        .push_local_idx,
        .push_polarity,
        .push_full_o,
        .promote_mask_i,
        .promote_hit_o,
        .promote_pol_o,
        .overflow_count_o,
        .overflow_loss_count_o
    );

    aer_block_overflow_buffer #(
        .OVERFLOW_DEPTH(0),
        .BLOCK_PIXELS(BLOCK_PIXELS),
        .LOSS_COUNT_W(8)
    ) disabled_dut (
        .clk,
        .rst_n,
        .push_req,
        .push_local_idx,
        .push_polarity,
        .push_full_o(disabled_push_full_o),
        .promote_mask_i,
        .promote_hit_o(disabled_promote_hit_o),
        .promote_pol_o(disabled_promote_pol_o),
        .overflow_count_o(disabled_overflow_count_o),
        .overflow_loss_count_o(disabled_overflow_loss_count_o)
    );

    always #5 clk = ~clk;

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                errors++;
                $error("%s", message);
            end
        end
    endtask

    task automatic reset_duts;
        begin
            push_req = 1'b0;
            push_local_idx = '0;
            push_polarity = 1'b0;
            promote_mask_i = '0;
            rst_n = 1'b0;
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
            @(negedge clk);
        end
    endtask

    task automatic push(input logic [3:0] local_idx, input logic polarity);
        begin
            push_req = 1'b1;
            push_local_idx = local_idx;
            push_polarity = polarity;
            promote_mask_i = '0;
            @(posedge clk);
            #1;
            push_req = 1'b0;
            @(negedge clk);
        end
    endtask

    task automatic promote(input logic [BLOCK_PIXELS-1:0] mask);
        begin
            promote_mask_i = mask;
            #1;
            @(posedge clk);
            #1;
            promote_mask_i = '0;
            @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        errors = 0;
        reset_duts();

        // 1. A single stored event is promoted by its matching primary clear.
        push(4'd3, 1'b1);
        check(overflow_count_o == 1, "single push was not stored");
        promote_mask_i = 16'h0008;
        #1;
        check(promote_hit_o == 16'h0008, "single promote hit mismatch");
        check(promote_pol_o == 16'h0008, "single promote polarity mismatch");
        @(posedge clk);
        #1;
        check(overflow_count_o == 0, "single promoted entry was not removed");
        promote_mask_i = '0;
        @(negedge clk);

        // 2. Repeated events for one pixel must promote in insertion order.
        push(4'd5, 1'b0);
        push(4'd5, 1'b1);
        promote_mask_i = 16'h0020;
        #1;
        check(promote_hit_o[5] && !promote_pol_o[5], "FIFO first polarity mismatch");
        @(posedge clk);
        #1;
        promote_mask_i = '0;
        @(negedge clk);
        promote_mask_i = 16'h0020;
        #1;
        check(promote_hit_o[5] && promote_pol_o[5], "FIFO second polarity mismatch");
        @(posedge clk);
        #1;
        check(overflow_count_o == 0, "FIFO entries were not fully removed");
        promote_mask_i = '0;
        @(negedge clk);

        // 3. Dense clear: independent local indices promote in the same cycle.
        push(4'd1, 1'b1);
        push(4'd7, 1'b0);
        push(4'd12, 1'b1);
        promote_mask_i = 16'h1082;
        #1;
        check(promote_hit_o == 16'h1082, "simultaneous dense promote hit mismatch");
        check(promote_pol_o == 16'h1002, "simultaneous dense promote polarity mismatch");
        @(posedge clk);
        #1;
        check(overflow_count_o == 0, "dense promote did not remove all matches");
        promote_mask_i = '0;
        @(negedge clk);

        // 4. A rejected full push increments the saturating loss counter once.
        push(4'd0, 1'b0);
        push(4'd1, 1'b0);
        push(4'd2, 1'b0);
        push_req = 1'b1;
        push_local_idx = 4'd3;
        push_polarity = 1'b1;
        #1;
        check(push_full_o, "full buffer did not flag rejected push");
        @(posedge clk);
        #1;
        check(overflow_count_o == 3, "full buffer count changed after rejected push");
        check(overflow_loss_count_o == 1, "full buffer loss count mismatch");
        push_req = 1'b0;
        @(negedge clk);

        // 5. A simultaneous promotion makes capacity for the new push.
        promote_mask_i = 16'h0002;
        push_req = 1'b1;
        push_local_idx = 4'd9;
        push_polarity = 1'b1;
        #1;
        check(!push_full_o, "simultaneous promote/push incorrectly rejected push");
        check(promote_hit_o == 16'h0002, "simultaneous promote hit mismatch");
        @(posedge clk);
        #1;
        check(overflow_count_o == 3, "simultaneous promote/push count mismatch");
        promote_mask_i = 16'h0200;
        push_req = 1'b0;
        #1;
        check(promote_hit_o == 16'h0200 && promote_pol_o == 16'h0200,
              "new simultaneous push was not stored correctly");
        @(posedge clk);
        #1;
        promote_mask_i = '0;
        @(negedge clk);

        // 6. Depth zero is a permanent disable path with no stored entries.
        reset_duts();
        check(disabled_push_full_o, "depth-zero buffer must always report full");
        check(disabled_overflow_count_o == 0, "depth-zero buffer stored an entry");
        check(disabled_promote_hit_o == 0 && disabled_promote_pol_o == 0,
              "depth-zero buffer produced a promotion");
        push_req = 1'b1;
        push_local_idx = 4'd4;
        push_polarity = 1'b0;
        @(posedge clk);
        #1;
        check(disabled_overflow_loss_count_o == 1,
              "depth-zero rejected push did not count as loss");
        push_req = 1'b0;

        if (errors == 0) begin
            $display("BLOCK OVERFLOW BUFFER DIRECTED TEST: PASS");
        end else begin
            $fatal(1, "BLOCK OVERFLOW BUFFER DIRECTED TEST: FAIL (%0d errors)", errors);
        end
        $finish;
    end
endmodule
