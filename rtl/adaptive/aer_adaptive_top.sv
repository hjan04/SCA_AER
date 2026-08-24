`timescale 1ns/1ps

module aer_adaptive_top #(
    parameter int X_SIZE = 16,
    parameter int Y_SIZE = 16,
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE),
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE),
    parameter int N_PIXELS = X_SIZE * Y_SIZE,

    parameter int BLOCK_W = 4,
    parameter int BLOCK_H = 4,
    parameter int BLOCK_PIXELS = BLOCK_W * BLOCK_H,
    parameter int BLOCK_X_COUNT = (X_SIZE + BLOCK_W - 1) / BLOCK_W,
    parameter int BLOCK_Y_COUNT = (Y_SIZE + BLOCK_H - 1) / BLOCK_H,
    parameter int N_BLOCKS = BLOCK_X_COUNT * BLOCK_Y_COUNT,
    parameter int BLOCK_X_W = (BLOCK_X_COUNT <= 1) ? 1 : $clog2(BLOCK_X_COUNT),
    parameter int BLOCK_Y_W = (BLOCK_Y_COUNT <= 1) ? 1 : $clog2(BLOCK_Y_COUNT),
    parameter int BLOCK_INDEX_W = (N_BLOCKS <= 1) ? 1 : $clog2(N_BLOCKS),
    parameter int OCC_W = (BLOCK_PIXELS <= 1) ? 1 : $clog2(BLOCK_PIXELS + 1),
    parameter int DENSE_ENTER_THRESHOLD = 3,
    parameter int DENSE_EXIT_THRESHOLD = 1,
    parameter int HOLD_CYCLES = 4,
    parameter int OVERFLOW_DEPTH = 3,
    parameter int METRIC_COUNT_W = ((N_PIXELS + N_BLOCKS*OVERFLOW_DEPTH) <= 1) ? 1 : $clog2(N_PIXELS + N_BLOCKS*OVERFLOW_DEPTH + 1),

    parameter int SPARSE_PACKET_W = 1 + X_W + Y_W + 1,
    parameter int DENSE_PACKET_W = 1 + BLOCK_X_W + BLOCK_Y_W +
                                   BLOCK_PIXELS + BLOCK_PIXELS,
    parameter int PACKET_W = (DENSE_PACKET_W > SPARSE_PACKET_W) ?
                             DENSE_PACKET_W : SPARSE_PACKET_W
) (
    input  logic                clk,
    input  logic                rst_n,

    input  logic [N_PIXELS-1:0] pixel_event_valid_i,
    input  logic [N_PIXELS-1:0] pixel_event_pol_i,

    output logic                aer_req_o,
    input  logic                aer_ack_i,
    output logic [PACKET_W-1:0] aer_packet_o,

    output logic                busy_o,
    output logic                dense_eligible_o,
    output logic [METRIC_COUNT_W-1:0] primary_unique_occupancy_o,
    output logic [METRIC_COUNT_W-1:0] overflow_count_o,
    output logic [METRIC_COUNT_W-1:0] total_pending_count_o,
    output logic [METRIC_COUNT_W-1:0] overflow_promoted_count_o
);

    typedef logic [X_W-1:0]           x_t;
    typedef logic [Y_W-1:0]           y_t;
    typedef logic [BLOCK_INDEX_W-1:0] block_index_t;

    localparam int TYPE_BIT          = 0;
    localparam int SPARSE_X_LSB      = 1;
    localparam int SPARSE_Y_LSB      = SPARSE_X_LSB + X_W;
    localparam int DENSE_BLOCK_X_LSB = 1;
    localparam int DENSE_BLOCK_Y_LSB = DENSE_BLOCK_X_LSB + BLOCK_X_W;

    logic [N_PIXELS-1:0]       pending;
    logic [N_PIXELS-1:0]       pending_pol;
    logic [N_PIXELS-1:0]       clear_mask;
    logic [N_PIXELS-1:0]       promote_hit, promote_pol;
    logic [N_PIXELS-1:0]       overflow_push_req, overflow_push_pol;
    localparam int OVERFLOW_COUNT_W = (OVERFLOW_DEPTH <= 1) ? 1 : $clog2(OVERFLOW_DEPTH+1);
    logic [N_BLOCKS*OVERFLOW_COUNT_W-1:0] block_overflow_count;
    logic [N_BLOCKS*BLOCK_PIXELS-1:0] block_promote_hit, block_promote_pol;

    logic                      sparse_grant_valid;
    logic [X_W-1:0]            sparse_grant_x;
    logic [Y_W-1:0]            sparse_grant_y;
    logic [N_PIXELS-1:0]       sparse_grant_onehot;
    logic                      sparse_grant_polarity;
    logic [PACKET_W-1:0]       sparse_packet;
    x_t                        col_base_q;
    y_t                        row_base_q;

    logic [N_BLOCKS-1:0]       dense_req;
    logic [N_BLOCKS-1:0]       dense_active_req;
    logic [N_BLOCKS-1:0]       dense_hold_req;
    logic [N_BLOCKS-1:0]       dense_select_req;
    logic [N_BLOCKS*OCC_W-1:0] block_occupancy;
    logic                      dense_grant_valid;
    logic [BLOCK_INDEX_W-1:0]  dense_grant_index;
    logic [BLOCK_X_W-1:0]      dense_grant_x;
    logic [BLOCK_Y_W-1:0]      dense_grant_y;
    logic [N_BLOCKS-1:0]       dense_grant_onehot;
    logic [BLOCK_PIXELS-1:0]   dense_valid_mask;
    logic [BLOCK_PIXELS-1:0]   dense_polarity_mask;
    logic [N_PIXELS-1:0]       dense_clear_mask;
    logic [PACKET_W-1:0]       dense_packet;
    block_index_t              block_base_q;

    logic                      selected_packet_valid;
    logic [PACKET_W-1:0]       selected_packet;
    logic [N_PIXELS-1:0]       selected_clear_mask;
    logic                      selected_packet_is_dense;
    logic                      dense_mode;
    logic                      output_accept;
    logic                      output_busy;

    function automatic x_t next_x(input x_t value);
        int next_value;
        begin
            next_value = int'(value) + 1;
            if (next_value >= X_SIZE) begin
                next_value = 0;
            end
            return x_t'(next_value);
        end
    endfunction

    function automatic y_t next_y(input y_t value);
        int next_value;
        begin
            next_value = int'(value) + 1;
            if (next_value >= Y_SIZE) begin
                next_value = 0;
            end
            return y_t'(next_value);
        end
    endfunction

    function automatic block_index_t next_block(input block_index_t value);
        int next_value;
        begin
            next_value = int'(value) + 1;
            if (next_value >= N_BLOCKS) begin
                next_value = 0;
            end
            return block_index_t'(next_value);
        end
    endfunction

    function automatic block_index_t packet_block_index(input logic [PACKET_W-1:0] packet);
        int block_x;
        int block_y;
        int block_index;
        begin
            block_x = int'(packet[DENSE_BLOCK_X_LSB +: BLOCK_X_W]);
            block_y = int'(packet[DENSE_BLOCK_Y_LSB +: BLOCK_Y_W]);
            block_index = (block_y * BLOCK_X_COUNT) + block_x;
            return block_index_t'(block_index);
        end
    endfunction

    aer_event_capture #(
        .N_PIXELS(N_PIXELS), .OVERFLOW_ENABLE(OVERFLOW_DEPTH > 0), .COUNT_W(METRIC_COUNT_W)
    ) u_capture (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_event_valid_i(pixel_event_valid_i),
        .pixel_event_pol_i(pixel_event_pol_i),
        .clear_i(clear_mask),
        .promote_hit_i(promote_hit), .promote_pol_i(promote_pol),
        .pending_o(pending),
        .pending_pol_o(pending_pol),
        .overflow_push_req_o(overflow_push_req), .overflow_push_pol_o(overflow_push_pol),
        .primary_unique_occupancy_o(primary_unique_occupancy_o)
    );

    generate
        for (genvar b = 0; b < N_BLOCKS; b++) begin : g_overflow_block
            logic [BLOCK_PIXELS-1:0] push_req, push_pol, promote_mask, push_reject;
            logic [OVERFLOW_COUNT_W-1:0] count;
            for (genvar l = 0; l < BLOCK_PIXELS; l++) begin : g_map
                localparam int LX = l % BLOCK_W;
                localparam int LY = l / BLOCK_W;
                localparam int BX = b % BLOCK_X_COUNT;
                localparam int BY = b / BLOCK_X_COUNT;
                localparam int GX = BX*BLOCK_W + LX;
                localparam int GY = BY*BLOCK_H + LY;
                localparam int GI = GY*X_SIZE + GX;
                if ((GX < X_SIZE) && (GY < Y_SIZE)) begin : g_valid
                    assign push_req[l] = overflow_push_req[GI];
                    assign push_pol[l] = overflow_push_pol[GI];
                    assign promote_mask[l] = clear_mask[GI];
                    assign promote_hit[GI] = block_promote_hit[b*BLOCK_PIXELS+l];
                    assign promote_pol[GI] = block_promote_pol[b*BLOCK_PIXELS+l];
                end else begin : g_pad
                    assign push_req[l] = 1'b0; assign push_pol[l] = 1'b0; assign promote_mask[l] = 1'b0;
                end
            end
            aer_block_overflow_buffer #(.OVERFLOW_DEPTH(OVERFLOW_DEPTH), .BLOCK_PIXELS(BLOCK_PIXELS), .COUNT_W(OVERFLOW_COUNT_W)) u_buf (
                .clk(clk), .rst_n(rst_n), .push_req_i(push_req), .push_polarity_i(push_pol), .push_reject_o(push_reject),
                .promote_mask_i(promote_mask),
                .promote_hit_o(block_promote_hit[b*BLOCK_PIXELS +: BLOCK_PIXELS]),
                .promote_pol_o(block_promote_pol[b*BLOCK_PIXELS +: BLOCK_PIXELS]),
                .overflow_count_o(count), .overflow_loss_count_o()
            );
            assign block_overflow_count[b*OVERFLOW_COUNT_W +: OVERFLOW_COUNT_W] = count;
        end
    endgenerate
    always_comb begin
        int n; n=0;
        for (int b=0;b<N_BLOCKS;b++) n += block_overflow_count[b*OVERFLOW_COUNT_W +: OVERFLOW_COUNT_W];
        overflow_count_o = METRIC_COUNT_W'(n);
        total_pending_count_o = primary_unique_occupancy_o + METRIC_COUNT_W'(n);
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) overflow_promoted_count_o <= '0;
        else if (|promote_hit) overflow_promoted_count_o <= overflow_promoted_count_o + $countones(promote_hit);
    end

    aer_row_col_arbiter #(
        .X_SIZE(X_SIZE),
        .Y_SIZE(Y_SIZE),
        .X_W(X_W),
        .Y_W(Y_W),
        .N_PIXELS(N_PIXELS)
    ) u_sparse_arbiter (
        .pending_i(pending),
        .row_base_i(row_base_q),
        .col_base_i(col_base_q),
        .grant_valid_o(sparse_grant_valid),
        .grant_x_o(sparse_grant_x),
        .grant_y_o(sparse_grant_y),
        .grant_onehot_o(sparse_grant_onehot)
    );

    always_comb begin
        sparse_grant_polarity = 1'b0;

        for (int i = 0; i < N_PIXELS; i++) begin
            if (sparse_grant_onehot[i]) begin
                sparse_grant_polarity = pending_pol[i];
            end
        end
    end

    aer_sparse_packetizer #(
        .X_W(X_W),
        .Y_W(Y_W),
        .PACKET_W(PACKET_W)
    ) u_sparse_packetizer (
        .x_i(sparse_grant_x),
        .y_i(sparse_grant_y),
        .polarity_i(sparse_grant_polarity),
        .packet_o(sparse_packet)
    );

    aer_block_occupancy #(
        .X_SIZE(X_SIZE),
        .Y_SIZE(Y_SIZE),
        .BLOCK_W(BLOCK_W),
        .BLOCK_H(BLOCK_H),
        .BLOCK_PIXELS(BLOCK_PIXELS),
        .BLOCK_X_COUNT(BLOCK_X_COUNT),
        .BLOCK_Y_COUNT(BLOCK_Y_COUNT),
        .N_BLOCKS(N_BLOCKS),
        .N_PIXELS(N_PIXELS),
        .OCC_W(OCC_W),
        .DENSE_ENTER_THRESHOLD(DENSE_ENTER_THRESHOLD),
        .DENSE_EXIT_THRESHOLD(DENSE_EXIT_THRESHOLD)
    ) u_block_occupancy (
        .pending_i(pending),
        .dense_req_o(dense_req),
        .dense_active_req_o(dense_active_req),
        .dense_hold_req_o(dense_hold_req),
        .block_occupancy_o(block_occupancy)
    );

    // Once dense mode has been entered, retain dense packetization for any
    // non-empty block until the low-threshold debounce expires.
    assign dense_select_req = (dense_mode || (|dense_req)) ?
                              dense_active_req : dense_req;

    aer_dense_block_selector #(
        .BLOCK_X_COUNT(BLOCK_X_COUNT),
        .BLOCK_Y_COUNT(BLOCK_Y_COUNT),
        .N_BLOCKS(N_BLOCKS),
        .BLOCK_INDEX_W(BLOCK_INDEX_W),
        .BLOCK_X_W(BLOCK_X_W),
        .BLOCK_Y_W(BLOCK_Y_W)
    ) u_dense_selector (
        .dense_req_i(dense_select_req),
        .block_base_i(block_base_q),
        .grant_valid_o(dense_grant_valid),
        .grant_block_index_o(dense_grant_index),
        .grant_block_x_o(dense_grant_x),
        .grant_block_y_o(dense_grant_y),
        .grant_onehot_o(dense_grant_onehot)
    );

    aer_dense_packetizer #(
        .X_SIZE(X_SIZE),
        .Y_SIZE(Y_SIZE),
        .BLOCK_W(BLOCK_W),
        .BLOCK_H(BLOCK_H),
        .BLOCK_PIXELS(BLOCK_PIXELS),
        .BLOCK_X_COUNT(BLOCK_X_COUNT),
        .BLOCK_Y_COUNT(BLOCK_Y_COUNT),
        .BLOCK_X_W(BLOCK_X_W),
        .BLOCK_Y_W(BLOCK_Y_W),
        .N_PIXELS(N_PIXELS),
        .PACKET_W(PACKET_W)
    ) u_dense_packetizer (
        .pending_i(pending),
        .pending_pol_i(pending_pol),
        .block_x_i(dense_grant_x),
        .block_y_i(dense_grant_y),
        .valid_mask_o(dense_valid_mask),
        .polarity_mask_o(dense_polarity_mask),
        .clear_mask_o(dense_clear_mask),
        .packet_o(dense_packet)
    );

    aer_mode_controller #(
        .PACKET_W(PACKET_W),
        .CLEAR_W(N_PIXELS),
        .HOLD_CYCLES(HOLD_CYCLES)
    ) u_mode_controller (
        .clk(clk),
        .rst_n(rst_n),
        .dense_enter_i(|dense_req),
        .dense_hold_i(|dense_hold_req),
        .dense_valid_i(dense_grant_valid),
        .dense_packet_i(dense_packet),
        .dense_clear_mask_i(dense_clear_mask),
        .sparse_valid_i(sparse_grant_valid),
        .sparse_packet_i(sparse_packet),
        .sparse_clear_mask_i(sparse_grant_onehot),
        .packet_valid_o(selected_packet_valid),
        .packet_payload_o(selected_packet),
        .packet_clear_mask_o(selected_clear_mask),
        .packet_is_dense_o(selected_packet_is_dense),
        .dense_mode_o(dense_mode)
    );

    aer_output_handshake #(
        .PAYLOAD_W(PACKET_W),
        .CLEAR_W(N_PIXELS)
    ) u_output (
        .clk(clk),
        .rst_n(rst_n),
        .packet_valid_i(selected_packet_valid),
        .packet_payload_i(selected_packet),
        .packet_clear_mask_i(selected_clear_mask),
        .aer_req_o(aer_req_o),
        .aer_ack_i(aer_ack_i),
        .aer_event_o(aer_packet_o),
        .accept_o(output_accept),
        .clear_mask_o(clear_mask),
        .busy_o(output_busy)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_base_q <= '0;
            col_base_q <= '0;
            block_base_q <= '0;
        end else if (output_accept) begin
            if (aer_packet_o[TYPE_BIT]) begin
                block_base_q <= next_block(packet_block_index(aer_packet_o));
            end else begin
                row_base_q <= next_y(aer_packet_o[SPARSE_Y_LSB +: Y_W]);
                col_base_q <= next_x(aer_packet_o[SPARSE_X_LSB +: X_W]);
            end
        end
    end

    assign dense_eligible_o = |dense_req;
    assign busy_o = output_busy || (|pending);

endmodule
