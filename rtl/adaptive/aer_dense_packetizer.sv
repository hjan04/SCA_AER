`timescale 1ns/1ps

module aer_dense_packetizer #(
    parameter int X_SIZE = 16,
    parameter int Y_SIZE = 16,
    parameter int BLOCK_W = 4,
    parameter int BLOCK_H = 4,
    parameter int BLOCK_PIXELS = BLOCK_W * BLOCK_H,
    parameter int BLOCK_X_COUNT = (X_SIZE + BLOCK_W - 1) / BLOCK_W,
    parameter int BLOCK_Y_COUNT = (Y_SIZE + BLOCK_H - 1) / BLOCK_H,
    parameter int BLOCK_X_W = (BLOCK_X_COUNT <= 1) ? 1 : $clog2(BLOCK_X_COUNT),
    parameter int BLOCK_Y_W = (BLOCK_Y_COUNT <= 1) ? 1 : $clog2(BLOCK_Y_COUNT),
    parameter int N_PIXELS = X_SIZE * Y_SIZE,
    parameter int PACKET_W = 1 + BLOCK_X_W + BLOCK_Y_W + BLOCK_PIXELS + BLOCK_PIXELS
) (
    input  logic [N_PIXELS-1:0]       pending_i,
    input  logic [N_PIXELS-1:0]       pending_pol_i,
    input  logic [BLOCK_X_W-1:0]      block_x_i,
    input  logic [BLOCK_Y_W-1:0]      block_y_i,

    output logic [BLOCK_PIXELS-1:0]   valid_mask_o,
    output logic [BLOCK_PIXELS-1:0]   polarity_mask_o,
    output logic [N_PIXELS-1:0]       clear_mask_o,
    output logic [PACKET_W-1:0]       packet_o
);

    localparam int TYPE_BIT          = 0;
    localparam int DENSE_BLOCK_X_LSB = 1;
    localparam int DENSE_BLOCK_Y_LSB = DENSE_BLOCK_X_LSB + BLOCK_X_W;
    localparam int DENSE_VALID_LSB   = DENSE_BLOCK_Y_LSB + BLOCK_Y_W;
    localparam int DENSE_POL_LSB     = DENSE_VALID_LSB + BLOCK_PIXELS;

    always_comb begin
        valid_mask_o = '0;
        polarity_mask_o = '0;
        clear_mask_o = '0;

        for (int local_y = 0; local_y < BLOCK_H; local_y++) begin
            for (int local_x = 0; local_x < BLOCK_W; local_x++) begin
                int global_x;
                int global_y;
                int global_index;
                int local_index;

                global_x = (int'(block_x_i) * BLOCK_W) + local_x;
                global_y = (int'(block_y_i) * BLOCK_H) + local_y;
                local_index = (local_y * BLOCK_W) + local_x;

                if ((global_x < X_SIZE) && (global_y < Y_SIZE)) begin
                    global_index = (global_y * X_SIZE) + global_x;
                    valid_mask_o[local_index] = pending_i[global_index];
                    polarity_mask_o[local_index] = pending_pol_i[global_index] &
                                                   pending_i[global_index];
                    clear_mask_o[global_index] = pending_i[global_index];
                end
            end
        end

        packet_o = '0;
        packet_o[TYPE_BIT] = 1'b1;
        packet_o[DENSE_BLOCK_X_LSB +: BLOCK_X_W] = block_x_i;
        packet_o[DENSE_BLOCK_Y_LSB +: BLOCK_Y_W] = block_y_i;
        packet_o[DENSE_VALID_LSB +: BLOCK_PIXELS] = valid_mask_o;
        packet_o[DENSE_POL_LSB +: BLOCK_PIXELS] = polarity_mask_o;
    end

endmodule
