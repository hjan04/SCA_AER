`timescale 1ns/1ps

module tb_aer_tx_hybrid;

    localparam int N_SOURCES = 10;
    localparam int GROUP_SIZE = 4;
    localparam int ADDR_W = $clog2(N_SOURCES);
    localparam int GROUP_COUNT = (N_SOURCES + GROUP_SIZE - 1) / GROUP_SIZE;
    localparam int GROUP_W = (GROUP_COUNT <= 1) ? 1 : $clog2(GROUP_COUNT);

    logic                  clk;
    logic                  rst_n;
    logic [N_SOURCES-1:0]  event_i;
    logic                  hyb_req_o;
    logic                  hyb_ack_i;
    logic                  hyb_mode_o;
    logic [ADDR_W-1:0]     hyb_addr_o;
    logic [GROUP_W-1:0]    hyb_group_o;
    logic [GROUP_SIZE-1:0] hyb_mask_o;
    logic                  dense_mode_o;
    logic                  busy_o;
    logic [N_SOURCES-1:0]  pending_o;

    int error_count;

    aer_tx_hybrid #(
        .N_SOURCES(N_SOURCES),
        .GROUP_SIZE(GROUP_SIZE),
        .ADDR_W(ADDR_W),
        .GROUP_COUNT(GROUP_COUNT),
        .GROUP_W(GROUP_W),
        .DENSE_THRESHOLD(4),
        .GROUP_DENSE_THRESHOLD(2),
        .SPARSE_THRESHOLD(1),
        .MODE_EXIT_HOLD(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .event_i(event_i),
        .hyb_req_o(hyb_req_o),
        .hyb_ack_i(hyb_ack_i),
        .hyb_mode_o(hyb_mode_o),
        .hyb_addr_o(hyb_addr_o),
        .hyb_group_o(hyb_group_o),
        .hyb_mask_o(hyb_mask_o),
        .dense_mode_o(dense_mode_o),
        .busy_o(busy_o),
        .pending_o(pending_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [N_SOURCES-1:0] source_mask(input int source);
        logic [N_SOURCES-1:0] mask;
        begin
            mask = '0;
            mask[source] = 1'b1;
            return mask;
        end
    endfunction

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
            hyb_ack_i = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
            check(hyb_req_o == 1'b0, "hyb_req_o must be low after reset");
            check(pending_o == '0, "pending_o must be clear after reset");
            check(dense_mode_o == 1'b0, "dense_mode_o must be low after reset");
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
            while (hyb_req_o !== 1'b1) begin
                @(posedge clk);
                cycles++;
                if (cycles > 64) begin
                    error_count++;
                    $fatal(1, "Timed out waiting for hyb_req_o");
                end
            end
        end
    endtask

    task automatic accept_one(
        output bit mode,
        output int addr,
        output int group_index,
        output logic [GROUP_SIZE-1:0] mask
    );
        bit sampled_mode;
        logic [ADDR_W-1:0] sampled_addr;
        logic [GROUP_W-1:0] sampled_group;
        logic [GROUP_SIZE-1:0] sampled_mask;
        begin
            wait_for_req();

            sampled_mode = hyb_mode_o;
            sampled_addr = hyb_addr_o;
            sampled_group = hyb_group_o;
            sampled_mask = hyb_mask_o;

            mode = sampled_mode;
            addr = sampled_addr;
            group_index = sampled_group;
            mask = sampled_mask;

            repeat (2) begin
                @(posedge clk);
                check(hyb_req_o == 1'b1, "hyb_req_o changed before ack");
                check(hyb_mode_o == sampled_mode, "hyb_mode_o changed before ack");
                check(hyb_addr_o == sampled_addr, "hyb_addr_o changed before ack");
                check(hyb_group_o == sampled_group, "hyb_group_o changed before ack");
                check(hyb_mask_o == sampled_mask, "hyb_mask_o changed before ack");
            end

            @(negedge clk);
            hyb_ack_i = 1'b1;
            @(posedge clk);
            #1;
            check(hyb_req_o == 1'b0, "hyb_req_o must drop after ack high");
            check(hyb_mode_o == sampled_mode, "hyb_mode_o should remain latched after req drop");
            check(hyb_addr_o == sampled_addr, "hyb_addr_o should remain latched after req drop");
            check(hyb_group_o == sampled_group, "hyb_group_o should remain latched after req drop");
            check(hyb_mask_o == sampled_mask, "hyb_mask_o should remain latched after req drop");

            @(negedge clk);
            hyb_ack_i = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic test_single_sparse_event;
        bit mode;
        int addr;
        int group_index;
        logic [GROUP_SIZE-1:0] mask;
        begin
            pulse_events(source_mask(5));
            accept_one(mode, addr, group_index, mask);
            check(mode == 1'b0, "single event must use sparse mode");
            check(addr == 5, "single event source 5 must transmit address 5");
        end
    endtask

    task automatic test_sparse_round_robin_order;
        bit mode;
        int addr;
        int group_index;
        logic [GROUP_SIZE-1:0] mask;
        begin
            pulse_events(source_mask(2) | source_mask(6));

            accept_one(mode, addr, group_index, mask);
            check(mode == 1'b0, "first round-robin packet must use sparse mode");
            check(addr == 6, "round-robin pointer should grant source 6 before source 2");

            accept_one(mode, addr, group_index, mask);
            check(mode == 1'b0, "second round-robin packet must use sparse mode");
            check(addr == 2, "round-robin wrap should grant source 2 second");
        end
    endtask

    task automatic test_dense_full_group;
        bit mode;
        int addr;
        int group_index;
        logic [GROUP_SIZE-1:0] mask;
        begin
            pulse_events(source_mask(4) | source_mask(5) | source_mask(6) | source_mask(7));
            accept_one(mode, addr, group_index, mask);
            check(mode == 1'b1, "four events in one group must use dense mode");
            check(group_index == 1, "dense full-group packet must select group 1");
            check(mask == 4'b1111, "dense full-group packet must carry mask 1111");
        end
    endtask

    task automatic test_dense_partial_last_group;
        bit mode;
        int addr;
        int group_index;
        logic [GROUP_SIZE-1:0] mask;
        begin
            pulse_events(source_mask(8) | source_mask(9));
            accept_one(mode, addr, group_index, mask);
            check(mode == 1'b1, "two events in one group must use dense mode");
            check(group_index == 2, "partial last-group packet must select group 2");
            check(mask == 4'b0011, "invalid bits in the partial last group must remain zero");
        end
    endtask

    task automatic test_dense_backpressure_stability;
        bit sampled_mode;
        logic [GROUP_W-1:0] sampled_group;
        logic [GROUP_SIZE-1:0] sampled_mask;
        begin
            pulse_events(source_mask(4) | source_mask(5));
            wait_for_req();

            sampled_mode = hyb_mode_o;
            sampled_group = hyb_group_o;
            sampled_mask = hyb_mask_o;

            check(sampled_mode == 1'b1, "backpressure packet must use dense mode");
            check(sampled_group == 1, "backpressure packet must select group 1");
            check(sampled_mask == 4'b0011, "backpressure packet must carry mask 0011");

            repeat (5) begin
                @(posedge clk);
                check(hyb_req_o == 1'b1, "hyb_req_o must stay high under backpressure");
                check(hyb_mode_o == sampled_mode, "hyb_mode_o must stay stable under backpressure");
                check(hyb_group_o == sampled_group, "hyb_group_o must stay stable under backpressure");
                check(hyb_mask_o == sampled_mask, "hyb_mask_o must stay stable under backpressure");
            end

            @(negedge clk);
            hyb_ack_i = 1'b1;
            @(posedge clk);
            #1;
            check(hyb_req_o == 1'b0, "hyb_req_o must drop after delayed ack");

            @(negedge clk);
            hyb_ack_i = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic test_dense_clear_set_same_cycle;
        bit mode;
        int addr;
        int group_index;
        logic [GROUP_SIZE-1:0] mask;
        begin
            pulse_events(source_mask(0) | source_mask(1));
            wait_for_req();
            check(hyb_mode_o == 1'b1, "clear/set test must start with dense mode");
            check(hyb_group_o == 0, "clear/set test must start with group 0");
            check(hyb_mask_o == 4'b0011, "clear/set test must start with mask 0011");

            @(negedge clk);
            hyb_ack_i = 1'b1;
            event_i = source_mask(0);
            @(posedge clk);
            #1;
            check(hyb_req_o == 1'b0, "hyb_req_o must drop after dense clear/set ack");

            @(negedge clk);
            hyb_ack_i = 1'b0;
            event_i = '0;
            @(posedge clk);
            #1;

            accept_one(mode, addr, group_index, mask);
            check(mode == 1'b0, "preserved clear/set event should return to sparse mode");
            check(addr == 0, "new source 0 event in dense clear cycle must be preserved");
        end
    endtask

    initial begin
        error_count = 0;

        reset_dut();
        test_single_sparse_event();
        test_sparse_round_robin_order();
        test_dense_full_group();
        test_dense_partial_last_group();
        test_dense_backpressure_stability();
        test_dense_clear_set_same_cycle();

        if (error_count == 0) begin
            $display("PASS: tb_aer_tx_hybrid");
        end else begin
            $fatal(1, "FAIL: tb_aer_tx_hybrid with %0d errors", error_count);
        end

        $finish;
    end

endmodule
