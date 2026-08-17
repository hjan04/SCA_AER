`timescale 1ns/1ps

module aer_baseline_packetizer #(
    parameter int X_W = 4,
    parameter int Y_W = 4,
    parameter int EVENT_W = 1 + Y_W + X_W
) (
    input  logic [X_W-1:0]     x_i,
    input  logic [Y_W-1:0]     y_i,
    input  logic               polarity_i,

    output logic [EVENT_W-1:0] event_o
);

    assign event_o = {polarity_i, y_i, x_i};

endmodule
