`timescale 1ns/1ps

module aer_sparse_packetizer #(
    parameter int X_W = 4,
    parameter int Y_W = 4,
    parameter int PACKET_W = 37
) (
    input  logic [X_W-1:0]      x_i,
    input  logic [Y_W-1:0]      y_i,
    input  logic                polarity_i,

    output logic [PACKET_W-1:0] packet_o
);

    localparam int TYPE_BIT       = 0;
    localparam int SPARSE_X_LSB   = 1;
    localparam int SPARSE_Y_LSB   = SPARSE_X_LSB + X_W;
    localparam int SPARSE_POL_BIT = SPARSE_Y_LSB + Y_W;

    always_comb begin
        packet_o = '0;
        packet_o[TYPE_BIT] = 1'b0;
        packet_o[SPARSE_X_LSB +: X_W] = x_i;
        packet_o[SPARSE_Y_LSB +: Y_W] = y_i;
        packet_o[SPARSE_POL_BIT] = polarity_i;
    end

endmodule
