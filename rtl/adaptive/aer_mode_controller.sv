`timescale 1ns/1ps

module aer_mode_controller #(
    parameter int PACKET_W = 37,
    parameter int CLEAR_W = 256
) (
    input  logic                  dense_valid_i,
    input  logic [PACKET_W-1:0]   dense_packet_i,
    input  logic [CLEAR_W-1:0]    dense_clear_mask_i,

    input  logic                  sparse_valid_i,
    input  logic [PACKET_W-1:0]   sparse_packet_i,
    input  logic [CLEAR_W-1:0]    sparse_clear_mask_i,

    output logic                  packet_valid_o,
    output logic [PACKET_W-1:0]   packet_payload_o,
    output logic [CLEAR_W-1:0]    packet_clear_mask_o,
    output logic                  packet_is_dense_o
);

    always_comb begin
        packet_valid_o = dense_valid_i || sparse_valid_i;
        packet_payload_o = '0;
        packet_clear_mask_o = '0;
        packet_is_dense_o = 1'b0;

        if (dense_valid_i) begin
            packet_payload_o = dense_packet_i;
            packet_clear_mask_o = dense_clear_mask_i;
            packet_is_dense_o = 1'b1;
        end else if (sparse_valid_i) begin
            packet_payload_o = sparse_packet_i;
            packet_clear_mask_o = sparse_clear_mask_i;
        end
    end

endmodule
