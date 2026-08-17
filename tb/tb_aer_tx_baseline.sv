`timescale 1ns/1ps

module tb_aer_tx_baseline;

    localparam int N_SOURCES = 8;
    localparam int ADDR_W = $clog2(N_SOURCES);

    logic                 clk;
    logic                 rst_n;
    logic [N_SOURCES-1:0] event_i;
    logic                 aer_req_o;
    logic                 aer_ack_i;
    logic [ADDR_W-1:0]    aer_addr_o;
    logic                 busy_o;
    logic [N_SOURCES-1:0] pending_o;

    int error_count;

    aer_tx_baseline #(
        .N_SOURCES(N_SOURCES),
        .ADDR_W(ADDR_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .event_i(event_i),
        .aer_req_o(aer_req_o),
        .aer_ack_i(aer_ack_i),
        .aer_addr_o(aer_addr_o),
        .busy_o(busy_o),
        .pending_o(pending_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check(input bit condition, input string message);
        begin
            if (!condition) begin
                error_count++;
                $error("%s", message);
            end
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            event_i = '0;
            aer_ack_i = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
            check(aer_req_o == 1'b0, "aer_req_o must be low after reset");
            check(pending_o == '0, "pending_o must be clear after reset");
        end
    endtask

    task automatic pulse_events(input logic [N_SOURCES-1:0] mask);
        begin
            @(negedge clk);
            event_i = mask;
            @(negedge clk);
            event_i = '0;
        end
    endtask

    task automatic wait_for_req;
        int cycles;
        begin
            cycles = 0;
            while (aer_req_o !== 1'b1) begin
                @(posedge clk);
                cycles++;
                if (cycles > 32) begin
                    error_count++;
                    $fatal(1, "Timed out waiting for aer_req_o");
                end
            end
        end
    endtask

    task automatic accept_one(output int addr);
        begin
            wait_for_req();
            addr = aer_addr_o;

            repeat (2) begin
                @(posedge clk);
                check(aer_req_o == 1'b1, "aer_req_o changed before ack");
                check(aer_addr_o == addr[ADDR_W-1:0], "aer_addr_o changed before ack");
            end

            @(negedge clk);
            aer_ack_i = 1'b1;
            @(posedge clk);
            #1;
            check(aer_req_o == 1'b0, "aer_req_o must drop after ack high");
            check(aer_addr_o == addr[ADDR_W-1:0], "aer_addr_o should remain latched after req drop");

            @(negedge clk);
            aer_ack_i = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic test_single_event;
        int addr;
        begin
            pulse_events(8'b0000_1000);
            accept_one(addr);
            check(addr == 3, "single event source 3 must transmit address 3");
        end
    endtask

    task automatic test_fixed_priority_order;
        int addr;
        begin
            pulse_events(8'b1011_0010);

            accept_one(addr);
            check(addr == 1, "first grant must be source 1");

            accept_one(addr);
            check(addr == 4, "second grant must be source 4");

            accept_one(addr);
            check(addr == 5, "third grant must be source 5");

            accept_one(addr);
            check(addr == 7, "fourth grant must be source 7");
        end
    endtask

    task automatic test_backpressure_stability;
        int addr;
        begin
            pulse_events(8'b0100_0000);
            wait_for_req();
            addr = aer_addr_o;
            check(addr == 6, "backpressure test must start with source 6");

            repeat (5) begin
                @(posedge clk);
                check(aer_req_o == 1'b1, "aer_req_o must stay high under backpressure");
                check(aer_addr_o == addr[ADDR_W-1:0], "aer_addr_o must stay stable under backpressure");
            end

            @(negedge clk);
            aer_ack_i = 1'b1;
            @(posedge clk);
            #1;
            check(aer_req_o == 1'b0, "aer_req_o must drop after delayed ack");

            @(negedge clk);
            aer_ack_i = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic test_clear_set_same_cycle;
        int addr;
        begin
            pulse_events(8'b0000_0100);
            wait_for_req();
            check(aer_addr_o == 2, "clear/set test must start with source 2");

            @(negedge clk);
            aer_ack_i = 1'b1;
            event_i = 8'b0000_0100;
            @(posedge clk);
            #1;
            check(aer_req_o == 1'b0, "aer_req_o must drop after ack in clear/set test");

            @(negedge clk);
            aer_ack_i = 1'b0;
            event_i = '0;
            @(posedge clk);
            #1;

            accept_one(addr);
            check(addr == 2, "new event in clear cycle must be preserved");
        end
    endtask

    initial begin
        error_count = 0;

        reset_dut();
        test_single_event();
        test_fixed_priority_order();
        test_backpressure_stability();
        test_clear_set_same_cycle();

        if (error_count == 0) begin
            $display("PASS: tb_aer_tx_baseline");
        end else begin
            $fatal(1, "FAIL: tb_aer_tx_baseline with %0d errors", error_count);
        end

        $finish;
    end

endmodule
