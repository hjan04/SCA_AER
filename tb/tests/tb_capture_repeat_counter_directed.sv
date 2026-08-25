`timescale 1ns/1ps

module tb_capture_repeat_counter_directed;
    localparam int N_PIXELS = 4;

    logic clk = 1'b0;
    logic rst_n;
    logic [N_PIXELS-1:0] valid, pol, clear;
    logic [N_PIXELS-1:0] pending, pending_pol;

    always #5 clk = ~clk;

    aer_event_capture #(
        .N_PIXELS(N_PIXELS),
        .ENABLE_COUNTER(1),
        .COUNTER_W(2)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .pixel_event_valid_i(valid),
        .pixel_event_pol_i(pol),
        .clear_i(clear),
        .pending_o(pending),
        .pending_pol_o(pending_pol)
    );

    task automatic inject_same_polarity;
        begin
            @(negedge clk);
            valid[0] = 1'b1;
            pol[0]   = 1'b1;
            @(negedge clk);
            valid[0] = 1'b0;
        end
    endtask

    task automatic clear_and_expect(input bit expected_pending);
        begin
            @(negedge clk);
            clear[0] = 1'b1;
            @(posedge clk);
            #1;
            if (pending[0] !== expected_pending)
                $fatal(1, "pending mismatch: expected %0b, got %0b",
                       expected_pending, pending[0]);
            @(negedge clk);
            clear[0] = 1'b0;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        valid = '0;
        pol   = '0;
        clear = '0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        inject_same_polarity();  // pending event
        inject_same_polarity();  // repeat count 1
        inject_same_polarity();  // repeat count 2
        inject_same_polarity();  // repeat count 3

        clear_and_expect(1'b1);
        clear_and_expect(1'b1);
        clear_and_expect(1'b1);
        clear_and_expect(1'b0);

        $display("REPEAT COUNTER DIRECTED TEST: PASS");
        $finish;
    end
endmodule
