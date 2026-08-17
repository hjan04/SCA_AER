`timescale 1ns/1ps

module aer_baseline_top #(
    parameter int X_SIZE = 16,
    parameter int Y_SIZE = 16,
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE),
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE),
    parameter int N_PIXELS = X_SIZE * Y_SIZE,
    parameter int EVENT_W = 1 + Y_W + X_W
) (
    input  logic                clk,
    input  logic                rst_n,

    input  logic [N_PIXELS-1:0] pixel_event_valid_i,
    input  logic [N_PIXELS-1:0] pixel_event_pol_i,

    output logic                aer_req_o,
    input  logic                aer_ack_i,
    output logic [EVENT_W-1:0]  aer_event_o,

    output logic                busy_o
);

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
    logic                output_accept;
    logic                output_busy;
    x_t                  col_base_q;
    y_t                  row_base_q;

    function automatic x_t next_x(input x_t value);
        int next_value;
        begin
            next_value = value + 1;
            if (next_value >= X_SIZE) begin
                next_value = 0;
            end
            return x_t'(next_value);
        end
    endfunction

    function automatic y_t next_y(input y_t value);
        int next_value;
        begin
            next_value = value + 1;
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

    aer_output_handshake #(
        .PAYLOAD_W(EVENT_W),
        .CLEAR_W(N_PIXELS)
    ) u_output (
        .clk(clk),
        .rst_n(rst_n),
        .packet_valid_i(grant_valid),
        .packet_payload_i(grant_event),
        .packet_clear_mask_i(grant_onehot),
        .aer_req_o(aer_req_o),
        .aer_ack_i(aer_ack_i),
        .aer_event_o(aer_event_o),
        .accept_o(output_accept),
        .clear_mask_o(clear_mask),
        .busy_o(output_busy)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_base_q <= '0;
            col_base_q <= '0;
        end else if (output_accept) begin
            row_base_q <= next_y(aer_event_o[X_W + Y_W - 1:X_W]);
            col_base_q <= next_x(aer_event_o[X_W-1:0]);
        end
    end

    assign busy_o = output_busy || (|pending);

endmodule
