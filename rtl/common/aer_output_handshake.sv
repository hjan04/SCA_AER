`timescale 1ns/1ps

module aer_output_handshake #(
    parameter int PAYLOAD_W = 9,
    parameter int CLEAR_W   = 256
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic                 packet_valid_i,
    input  logic [PAYLOAD_W-1:0] packet_payload_i,
    input  logic [CLEAR_W-1:0]   packet_clear_mask_i,

    output logic                 aer_req_o,
    input  logic                 aer_ack_i,
    output logic [PAYLOAD_W-1:0] aer_event_o,

    output logic                 accept_o,
    output logic [CLEAR_W-1:0]   clear_mask_o,
    output logic                 busy_o
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_REQ_HIGH,
        ST_REQ_LOW
    } state_e;

    state_e state_q;
    state_e state_d;

    logic                 aer_req_d;
    logic [PAYLOAD_W-1:0] aer_event_d;
    logic [CLEAR_W-1:0]   active_clear_mask_q;
    logic [CLEAR_W-1:0]   active_clear_mask_d;

    assign accept_o = (state_q == ST_REQ_HIGH) && aer_ack_i;
    assign clear_mask_o = accept_o ? active_clear_mask_q : '0;
    assign busy_o = (state_q != ST_IDLE);

    always_comb begin
        state_d = state_q;
        aer_req_d = aer_req_o;
        aer_event_d = aer_event_o;
        active_clear_mask_d = active_clear_mask_q;

        case (state_q)
            ST_IDLE: begin
                aer_req_d = 1'b0;
                active_clear_mask_d = '0;

                if (packet_valid_i && !aer_ack_i) begin
                    state_d = ST_REQ_HIGH;
                    aer_req_d = 1'b1;
                    aer_event_d = packet_payload_i;
                    active_clear_mask_d = packet_clear_mask_i;
                end
            end

            ST_REQ_HIGH: begin
                aer_req_d = 1'b1;

                if (aer_ack_i) begin
                    state_d = ST_REQ_LOW;
                    aer_req_d = 1'b0;
                    active_clear_mask_d = '0;
                end
            end

            ST_REQ_LOW: begin
                aer_req_d = 1'b0;

                if (!aer_ack_i) begin
                    state_d = ST_IDLE;
                end
            end

            default: begin
                state_d = ST_IDLE;
                aer_req_d = 1'b0;
                aer_event_d = '0;
                active_clear_mask_d = '0;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            aer_req_o <= 1'b0;
            aer_event_o <= '0;
            active_clear_mask_q <= '0;
        end else begin
            state_q <= state_d;
            aer_req_o <= aer_req_d;
            aer_event_o <= aer_event_d;
            active_clear_mask_q <= active_clear_mask_d;
        end
    end

endmodule
