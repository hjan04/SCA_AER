`timescale 1ns/1ps

module aer_adaptive_link_top #(
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

    parameter int SPARSE_PACKET_W = 1 + X_W + Y_W + 1,
    parameter int DENSE_PACKET_W = 1 + BLOCK_X_W + BLOCK_Y_W +
                                   BLOCK_PIXELS + BLOCK_PIXELS,
    parameter int PACKET_W = (DENSE_PACKET_W > SPARSE_PACKET_W) ?
                             DENSE_PACKET_W : SPARSE_PACKET_W,

    parameter int LINK_WIDTH = 16,
    parameter int MAX_PACKET_W = PACKET_W,
    parameter int LINK_TYPE_W = 2,
    parameter int LINK_LEN_W = 6
) (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic [N_PIXELS-1:0]        pixel_event_valid_i,
    input  logic [N_PIXELS-1:0]        pixel_event_pol_i,

    output logic                       link_valid_o,
    input  logic                       link_ready_i,
    output logic [LINK_WIDTH-1:0]      link_data_o,

    output logic                       busy_o,
    output logic                       dense_eligible_o,

    output logic                       logical_packet_accept_o,
    output logic [LINK_TYPE_W-1:0]     logical_packet_type_o,
    output logic [LINK_LEN_W-1:0]      logical_packet_bits_o,
    output logic [MAX_PACKET_W-1:0]    logical_packet_data_o,
    output logic [N_PIXELS-1:0]        logical_packet_clear_mask_o
);

    localparam int TYPE_BIT = 0;
    localparam int SPARSE_X_LSB = 1;
    localparam int SPARSE_Y_LSB = SPARSE_X_LSB + X_W;

    localparam logic [LINK_TYPE_W-1:0] ADAPTIVE_SPARSE_TYPE = 2'd1;
    localparam logic [LINK_TYPE_W-1:0] ADAPTIVE_DENSE_TYPE  = 2'd2;

    typedef logic [X_W-1:0]           x_t;
    typedef logic [Y_W-1:0]           y_t;
    typedef logic [BLOCK_INDEX_W-1:0] block_index_t;

    logic [N_PIXELS-1:0]       pending;
    logic [N_PIXELS-1:0]       pending_pol;
    logic [N_PIXELS-1:0]       clear_mask;

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
    logic                      serializer_busy;

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

    aer_event_capture #(
        .N_PIXELS(N_PIXELS),
        .ENABLE_COUNTER(1),
        .COUNTER_W(2)
    ) u_capture (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_event_valid_i(pixel_event_valid_i),
        .pixel_event_pol_i(pixel_event_pol_i),
        .clear_i(clear_mask),
        .pending_o(pending),
        .pending_pol_o(pending_pol)
    );

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

    always_comb begin
        logical_packet_type_o =
            selected_packet_is_dense ? ADAPTIVE_DENSE_TYPE : ADAPTIVE_SPARSE_TYPE;
        logical_packet_bits_o =
            selected_packet_is_dense ? LINK_LEN_W'(DENSE_PACKET_W) :
                                       LINK_LEN_W'(SPARSE_PACKET_W);
        logical_packet_data_o = selected_packet;
        logical_packet_clear_mask_o =
            logical_packet_accept_o ? selected_clear_mask : '0;
    end

    aer_link_serializer #(
        .LINK_WIDTH(LINK_WIDTH),
        .MAX_PACKET_W(MAX_PACKET_W),
        .TYPE_W(LINK_TYPE_W),
        .LEN_W(LINK_LEN_W)
    ) u_serializer (
        .clk(clk),
        .rst_n(rst_n),
        .packet_valid_i(selected_packet_valid),
        .packet_ready_o(),
        .packet_type_i(logical_packet_type_o),
        .packet_bits_i(logical_packet_bits_o),
        .packet_data_i(logical_packet_data_o),
        .link_valid_o(link_valid_o),
        .link_ready_i(link_ready_i),
        .link_data_o(link_data_o),
        .packet_accept_o(logical_packet_accept_o),
        .busy_o(serializer_busy)
    );

    assign clear_mask = logical_packet_accept_o ? selected_clear_mask : '0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_base_q <= '0;
            col_base_q <= '0;
            block_base_q <= '0;
        end else if (logical_packet_accept_o) begin
            if (selected_packet_is_dense) begin
                block_base_q <= next_block(dense_grant_index);
            end else begin
                row_base_q <= next_y(selected_packet[SPARSE_Y_LSB +: Y_W]);
                col_base_q <= next_x(selected_packet[SPARSE_X_LSB +: X_W]);
            end
        end
    end

    assign dense_eligible_o = |dense_req;
    assign busy_o = serializer_busy || (|pending);

endmodule
