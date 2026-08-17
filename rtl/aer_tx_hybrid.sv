`timescale 1ns/1ps

module aer_tx_hybrid #(
    parameter int N_SOURCES        = 64,
    parameter int GROUP_SIZE       = 8,
    parameter int ADDR_W           = (N_SOURCES <= 1) ? 1 : $clog2(N_SOURCES),
    parameter int GROUP_COUNT      = (N_SOURCES + GROUP_SIZE - 1) / GROUP_SIZE,
    parameter int GROUP_W          = (GROUP_COUNT <= 1) ? 1 : $clog2(GROUP_COUNT),
    parameter int DENSE_THRESHOLD  = GROUP_SIZE,
    parameter int GROUP_DENSE_THRESHOLD = (GROUP_SIZE <= 1) ? 1 : 2,
    parameter int SPARSE_THRESHOLD = (GROUP_SIZE <= 1) ? 0 : (GROUP_SIZE / 2),
    parameter int MODE_EXIT_HOLD   = 2
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic [N_SOURCES-1:0]  event_i,

    output logic                  hyb_req_o,
    input  logic                  hyb_ack_i,
    output logic                  hyb_mode_o,
    output logic [ADDR_W-1:0]     hyb_addr_o,
    output logic [GROUP_W-1:0]    hyb_group_o,
    output logic [GROUP_SIZE-1:0] hyb_mask_o,

    output logic                  dense_mode_o,
    output logic                  busy_o,
    output logic [N_SOURCES-1:0]  pending_o
);

    typedef logic [ADDR_W-1:0]  addr_t;
    typedef logic [GROUP_W-1:0] group_t;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_REQ_HIGH,
        ST_REQ_LOW
    } state_e;

    localparam int EXIT_HOLD_W = (MODE_EXIT_HOLD <= 1) ? 1 : $clog2(MODE_EXIT_HOLD + 1);

    state_e state_q;
    state_e state_d;

    logic [N_SOURCES-1:0] pending_q;
    logic [N_SOURCES-1:0] pending_d;
    logic [N_SOURCES-1:0] pending_with_events;
    logic [N_SOURCES-1:0] pending_after_update;
    logic [N_SOURCES-1:0] clear_mask;
    logic [N_SOURCES-1:0] active_clear_mask_q;
    logic [N_SOURCES-1:0] active_clear_mask_d;

    addr_t  rr_src_q;
    addr_t  rr_src_d;
    group_t rr_group_q;
    group_t rr_group_d;

    logic dense_mode_q;
    logic dense_mode_d;
    logic [EXIT_HOLD_W-1:0] exit_hold_q;
    logic [EXIT_HOLD_W-1:0] exit_hold_d;

    logic active_mode_q;
    logic active_mode_d;

    logic                  hyb_req_d;
    logic                  hyb_mode_d;
    addr_t                 hyb_addr_d;
    group_t                hyb_group_d;
    logic [GROUP_SIZE-1:0] hyb_mask_d;

    logic                 sparse_valid;
    addr_t                sparse_addr;
    logic [N_SOURCES-1:0] sparse_clear_mask;

    logic                  dense_valid;
    group_t                dense_group;
    logic [GROUP_SIZE-1:0] dense_mask;
    logic [GROUP_SIZE-1:0] dense_candidate_mask;
    logic [N_SOURCES-1:0]  dense_clear_mask;

    logic                  packet_valid;
    logic                  packet_mode;
    addr_t                 packet_addr;
    group_t                packet_group;
    logic [GROUP_SIZE-1:0] packet_mask;
    logic [N_SOURCES-1:0]  packet_clear_mask;

    int pending_count_for_mode;
    int max_group_count_for_mode;
    logic enter_dense;
    logic exit_sparse_eligible;

    assign pending_with_events = pending_q | event_i;
    assign clear_mask = ((state_q == ST_REQ_HIGH) && hyb_ack_i) ? active_clear_mask_q : '0;
    assign pending_after_update = (pending_q & ~clear_mask) | event_i;

    assign pending_o = pending_q;
    assign dense_mode_o = dense_mode_q;
    assign busy_o = (state_q != ST_IDLE) || (|pending_q);

`ifndef SYNTHESIS
    initial begin
        if (N_SOURCES < 1) begin
            $fatal(1, "N_SOURCES must be greater than zero");
        end
        if (GROUP_SIZE < 1) begin
            $fatal(1, "GROUP_SIZE must be greater than zero");
        end
        if ((2 ** ADDR_W) < N_SOURCES) begin
            $fatal(1, "ADDR_W is too small for N_SOURCES");
        end
        if ((2 ** GROUP_W) < GROUP_COUNT) begin
            $fatal(1, "GROUP_W is too small for GROUP_COUNT");
        end
        if ((GROUP_COUNT * GROUP_SIZE) < N_SOURCES) begin
            $fatal(1, "GROUP_COUNT is too small for N_SOURCES and GROUP_SIZE");
        end
        if (DENSE_THRESHOLD < 1) begin
            $fatal(1, "DENSE_THRESHOLD must be greater than zero");
        end
        if (GROUP_DENSE_THRESHOLD < 1) begin
            $fatal(1, "GROUP_DENSE_THRESHOLD must be greater than zero");
        end
        if (GROUP_DENSE_THRESHOLD > GROUP_SIZE) begin
            $fatal(1, "GROUP_DENSE_THRESHOLD must be less than or equal to GROUP_SIZE");
        end
        if (MODE_EXIT_HOLD < 1) begin
            $fatal(1, "MODE_EXIT_HOLD must be greater than zero");
        end
    end
`endif

    function automatic int count_sources(input logic [N_SOURCES-1:0] value);
        int count;
        begin
            count = 0;
            for (int i = 0; i < N_SOURCES; i++) begin
                if (value[i]) begin
                    count++;
                end
            end
            return count;
        end
    endfunction

    function automatic logic [GROUP_SIZE-1:0] get_group_mask(
        input logic [N_SOURCES-1:0] value,
        input int group_index
    );
        logic [GROUP_SIZE-1:0] mask;
        int source_index;
        begin
            mask = '0;
            for (int i = 0; i < GROUP_SIZE; i++) begin
                source_index = (group_index * GROUP_SIZE) + i;
                if (source_index < N_SOURCES) begin
                    mask[i] = value[source_index];
                end
            end
            return mask;
        end
    endfunction

    function automatic int count_group_bits(input logic [GROUP_SIZE-1:0] mask);
        int count;
        begin
            count = 0;
            for (int i = 0; i < GROUP_SIZE; i++) begin
                if (mask[i]) begin
                    count++;
                end
            end
            return count;
        end
    endfunction

    function automatic int max_group_count(input logic [N_SOURCES-1:0] value);
        int maximum;
        logic [GROUP_SIZE-1:0] mask;
        int group_count;
        begin
            maximum = 0;
            for (int group_index = 0; group_index < GROUP_COUNT; group_index++) begin
                mask = get_group_mask(value, group_index);
                group_count = count_group_bits(mask);
                if (group_count > maximum) begin
                    maximum = group_count;
                end
            end
            return maximum;
        end
    endfunction

    function automatic logic [N_SOURCES-1:0] expand_group_mask(
        input int group_index,
        input logic [GROUP_SIZE-1:0] mask
    );
        logic [N_SOURCES-1:0] expanded;
        int source_index;
        begin
            expanded = '0;
            for (int i = 0; i < GROUP_SIZE; i++) begin
                source_index = (group_index * GROUP_SIZE) + i;
                if (source_index < N_SOURCES) begin
                    expanded[source_index] = mask[i];
                end
            end
            return expanded;
        end
    endfunction

    function automatic addr_t next_source(input addr_t source);
        int next_index;
        begin
            next_index = source + 1;
            if (next_index >= N_SOURCES) begin
                next_index = 0;
            end
            return addr_t'(next_index);
        end
    endfunction

    function automatic group_t next_group(input group_t group_index);
        int next_index;
        begin
            next_index = group_index + 1;
            if (next_index >= GROUP_COUNT) begin
                next_index = 0;
            end
            return group_t'(next_index);
        end
    endfunction

    function automatic addr_t source_after_group(input group_t group_index);
        int next_index;
        begin
            next_index = (group_index + 1) * GROUP_SIZE;
            if (next_index >= N_SOURCES) begin
                next_index = 0;
            end
            return addr_t'(next_index);
        end
    endfunction

    always_comb begin
        pending_count_for_mode = count_sources(pending_after_update);
        max_group_count_for_mode = max_group_count(pending_after_update);

        enter_dense = (pending_count_for_mode >= DENSE_THRESHOLD) ||
                      (max_group_count_for_mode >= GROUP_DENSE_THRESHOLD);
        exit_sparse_eligible = (pending_count_for_mode <= SPARSE_THRESHOLD);

        dense_mode_d = dense_mode_q;
        exit_hold_d  = exit_hold_q;

        if (enter_dense) begin
            dense_mode_d = 1'b1;
            exit_hold_d  = '0;
        end else if (dense_mode_q) begin
            if (exit_sparse_eligible) begin
                if (exit_hold_q >= (MODE_EXIT_HOLD - 1)) begin
                    dense_mode_d = 1'b0;
                    exit_hold_d  = '0;
                end else begin
                    exit_hold_d = exit_hold_q + 1'b1;
                end
            end else begin
                exit_hold_d = '0;
            end
        end else begin
            exit_hold_d = '0;
        end
    end

    always_comb begin
        sparse_valid = 1'b0;
        sparse_addr = '0;
        sparse_clear_mask = '0;

        for (int offset = 0; offset < N_SOURCES; offset++) begin
            int source_index;
            source_index = rr_src_q + offset;
            if (source_index >= N_SOURCES) begin
                source_index = source_index - N_SOURCES;
            end

            if (!sparse_valid && pending_with_events[source_index]) begin
                sparse_valid = 1'b1;
                sparse_addr = addr_t'(source_index);
                sparse_clear_mask = '0;
                sparse_clear_mask[source_index] = 1'b1;
            end
        end
    end

    always_comb begin
        dense_valid = 1'b0;
        dense_group = '0;
        dense_mask = '0;
        dense_candidate_mask = '0;
        dense_clear_mask = '0;

        for (int offset = 0; offset < GROUP_COUNT; offset++) begin
            int group_index;
            group_index = rr_group_q + offset;
            if (group_index >= GROUP_COUNT) begin
                group_index = group_index - GROUP_COUNT;
            end

            dense_candidate_mask = get_group_mask(pending_with_events, group_index);

            if (!dense_valid &&
                (count_group_bits(dense_candidate_mask) >= GROUP_DENSE_THRESHOLD)) begin
                dense_valid = 1'b1;
                dense_group = group_t'(group_index);
                dense_mask = dense_candidate_mask;
                dense_clear_mask = expand_group_mask(group_index, dense_candidate_mask);
            end
        end
    end

    always_comb begin
        packet_valid = 1'b0;
        packet_mode = 1'b0;
        packet_addr = '0;
        packet_group = '0;
        packet_mask = '0;
        packet_clear_mask = '0;

        if (dense_mode_d && dense_valid) begin
            packet_valid = 1'b1;
            packet_mode = 1'b1;
            packet_group = dense_group;
            packet_mask = dense_mask;
            packet_clear_mask = dense_clear_mask;
        end else if (sparse_valid) begin
            packet_valid = 1'b1;
            packet_mode = 1'b0;
            packet_addr = sparse_addr;
            packet_clear_mask = sparse_clear_mask;
        end
    end

    always_comb begin
        state_d = state_q;
        pending_d = pending_after_update;
        active_clear_mask_d = active_clear_mask_q;
        active_mode_d = active_mode_q;
        rr_src_d = rr_src_q;
        rr_group_d = rr_group_q;
        hyb_req_d = hyb_req_o;
        hyb_mode_d = hyb_mode_o;
        hyb_addr_d = hyb_addr_o;
        hyb_group_d = hyb_group_o;
        hyb_mask_d = hyb_mask_o;

        case (state_q)
            ST_IDLE: begin
                active_clear_mask_d = '0;
                active_mode_d = 1'b0;
                hyb_req_d = 1'b0;

                if (packet_valid && !hyb_ack_i) begin
                    state_d = ST_REQ_HIGH;
                    active_clear_mask_d = packet_clear_mask;
                    active_mode_d = packet_mode;
                    hyb_req_d = 1'b1;
                    hyb_mode_d = packet_mode;
                    hyb_addr_d = packet_addr;
                    hyb_group_d = packet_group;
                    hyb_mask_d = packet_mask;
                end
            end

            ST_REQ_HIGH: begin
                hyb_req_d = 1'b1;

                if (hyb_ack_i) begin
                    state_d = ST_REQ_LOW;
                    hyb_req_d = 1'b0;
                    active_clear_mask_d = '0;

                    if (active_mode_q) begin
                        rr_group_d = next_group(hyb_group_o);
                        rr_src_d = source_after_group(hyb_group_o);
                    end else begin
                        rr_src_d = next_source(hyb_addr_o);
                    end
                end
            end

            ST_REQ_LOW: begin
                hyb_req_d = 1'b0;

                if (!hyb_ack_i) begin
                    state_d = ST_IDLE;
                end
            end

            default: begin
                state_d = ST_IDLE;
                pending_d = event_i;
                active_clear_mask_d = '0;
                active_mode_d = 1'b0;
                rr_src_d = '0;
                rr_group_d = '0;
                hyb_req_d = 1'b0;
                hyb_mode_d = 1'b0;
                hyb_addr_d = '0;
                hyb_group_d = '0;
                hyb_mask_d = '0;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            pending_q <= '0;
            active_clear_mask_q <= '0;
            active_mode_q <= 1'b0;
            rr_src_q <= '0;
            rr_group_q <= '0;
            dense_mode_q <= 1'b0;
            exit_hold_q <= '0;
            hyb_req_o <= 1'b0;
            hyb_mode_o <= 1'b0;
            hyb_addr_o <= '0;
            hyb_group_o <= '0;
            hyb_mask_o <= '0;
        end else begin
            state_q <= state_d;
            pending_q <= pending_d;
            active_clear_mask_q <= active_clear_mask_d;
            active_mode_q <= active_mode_d;
            rr_src_q <= rr_src_d;
            rr_group_q <= rr_group_d;
            dense_mode_q <= dense_mode_d;
            exit_hold_q <= exit_hold_d;
            hyb_req_o <= hyb_req_d;
            hyb_mode_o <= hyb_mode_d;
            hyb_addr_o <= hyb_addr_d;
            hyb_group_o <= hyb_group_d;
            hyb_mask_o <= hyb_mask_d;
        end
    end

endmodule
