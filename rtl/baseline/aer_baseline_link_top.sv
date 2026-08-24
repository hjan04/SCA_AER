`timescale 1ns/1ps

module aer_baseline_link_top #(
    parameter int X_SIZE = 16,
    parameter int Y_SIZE = 16,
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE),
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE),
    parameter int N_PIXELS = X_SIZE * Y_SIZE,
    parameter int EVENT_W = 1 + Y_W + X_W,

    parameter int LINK_WIDTH = 16,
    parameter int MAX_PACKET_W = 37,
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

    output logic                       logical_packet_accept_o,
    output logic [LINK_TYPE_W-1:0]     logical_packet_type_o,
    output logic [LINK_LEN_W-1:0]      logical_packet_bits_o,
    output logic [MAX_PACKET_W-1:0]    logical_packet_data_o,
    output logic [N_PIXELS-1:0]        logical_packet_clear_mask_o
);

    localparam logic [LINK_TYPE_W-1:0] BASELINE_SPARSE_TYPE = 2'd0;

    typedef logic [X_W-1:0] x_t;
    typedef logic [Y_W-1:0] y_t;

    logic [N_PIXELS-1:0] pending;
    logic [N_PIXELS-1:0] pending_pol;
    logic [N_PIXELS-1:0] clear_mask;
    logic [N_PIXELS-1:0] grant_onehot;
    logic                grant_valid;
    x_t                  grant_x;
    y_t                  grant_y;
    logic                grant_polarity;
    logic [EVENT_W-1:0]  grant_event;
    logic                serializer_ready;
    logic                serializer_busy;
    x_t                  col_base_q;
    y_t                  row_base_q;

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

    aer_event_capture #(
        .N_PIXELS(N_PIXELS)
    ) u_capture (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_event_valid_i(pixel_event_valid_i),
        .pixel_event_pol_i(pixel_event_pol_i),
        .clear_i(clear_mask),
        .promote_hit_i('0),
        .promote_pol_i('0),
        .pending_o(pending),
        .pending_pol_o(pending_pol)
    );

    aer_row_col_arbiter #(
        .X_SIZE(X_SIZE),
        .Y_SIZE(Y_SIZE),
        .X_W(X_W),
        .Y_W(Y_W),
        .N_PIXELS(N_PIXELS)
    ) u_arbiter (
        .pending_i(pending),
        .row_base_i(row_base_q),
        .col_base_i(col_base_q),
        .grant_valid_o(grant_valid),
        .grant_x_o(grant_x),
        .grant_y_o(grant_y),
        .grant_onehot_o(grant_onehot)
    );

    always_comb begin
        grant_polarity = 1'b0;

        for (int i = 0; i < N_PIXELS; i++) begin
            if (grant_onehot[i]) begin
                grant_polarity = pending_pol[i];
            end
        end
    end

    aer_baseline_packetizer #(
        .X_W(X_W),
        .Y_W(Y_W),
        .EVENT_W(EVENT_W)
    ) u_packetizer (
        .x_i(grant_x),
        .y_i(grant_y),
        .polarity_i(grant_polarity),
        .event_o(grant_event)
    );

    always_comb begin
        logical_packet_type_o = BASELINE_SPARSE_TYPE;
        logical_packet_bits_o = LINK_LEN_W'(EVENT_W);
        logical_packet_data_o = '0;
        logical_packet_data_o[EVENT_W-1:0] = grant_event;
        logical_packet_clear_mask_o = logical_packet_accept_o ? grant_onehot : '0;
    end

    aer_link_serializer #(
        .LINK_WIDTH(LINK_WIDTH),
        .MAX_PACKET_W(MAX_PACKET_W),
        .TYPE_W(LINK_TYPE_W),
        .LEN_W(LINK_LEN_W)
    ) u_serializer (
        .clk(clk),
        .rst_n(rst_n),
        .packet_valid_i(grant_valid),
        .packet_ready_o(serializer_ready),
        .packet_type_i(logical_packet_type_o),
        .packet_bits_i(logical_packet_bits_o),
        .packet_data_i(logical_packet_data_o),
        .link_valid_o(link_valid_o),
        .link_ready_i(link_ready_i),
        .link_data_o(link_data_o),
        .packet_accept_o(logical_packet_accept_o),
        .busy_o(serializer_busy)
    );

    assign clear_mask = logical_packet_accept_o ? grant_onehot : '0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_base_q <= '0;
            col_base_q <= '0;
        end else if (logical_packet_accept_o) begin
            row_base_q <= next_y(grant_y);
            col_base_q <= next_x(grant_x);
        end
    end

    assign busy_o = serializer_busy || (|pending);

endmodule
