`timescale 1ns/1ps

module aer_block_occupancy #(
    parameter int X_SIZE = 16,
    parameter int Y_SIZE = 16,
    parameter int BLOCK_W = 4,
    parameter int BLOCK_H = 4,
    parameter int BLOCK_PIXELS = BLOCK_W * BLOCK_H,
    parameter int BLOCK_X_COUNT = (X_SIZE + BLOCK_W - 1) / BLOCK_W,
    parameter int BLOCK_Y_COUNT = (Y_SIZE + BLOCK_H - 1) / BLOCK_H,
    parameter int N_BLOCKS = BLOCK_X_COUNT * BLOCK_Y_COUNT,
    parameter int N_PIXELS = X_SIZE * Y_SIZE,
    parameter int OCC_W = (BLOCK_PIXELS <= 1) ? 1 : $clog2(BLOCK_PIXELS + 1),
    parameter int DENSE_ENTER_THRESHOLD = 5
) (
    input  logic [N_PIXELS-1:0]       pending_i,

    output logic [N_BLOCKS-1:0]       dense_req_o,
    output logic [N_BLOCKS*OCC_W-1:0] block_occupancy_o
);

    always_comb begin
        dense_req_o = '0;
        block_occupancy_o = '0;

        for (int block_y = 0; block_y < BLOCK_Y_COUNT; block_y++) begin
            for (int block_x = 0; block_x < BLOCK_X_COUNT; block_x++) begin
                int occupancy;
                int block_index;

                occupancy = 0;
                block_index = (block_y * BLOCK_X_COUNT) + block_x;

                for (int local_y = 0; local_y < BLOCK_H; local_y++) begin
                    for (int local_x = 0; local_x < BLOCK_W; local_x++) begin
                        int global_x;
                        int global_y;
                        int pixel_index;

                        global_x = (block_x * BLOCK_W) + local_x;
                        global_y = (block_y * BLOCK_H) + local_y;

                        if ((global_x < X_SIZE) && (global_y < Y_SIZE)) begin
                            pixel_index = (global_y * X_SIZE) + global_x;
                            if (pending_i[pixel_index]) begin
                                occupancy++;
                            end
                        end
                    end
                end

                block_occupancy_o[(block_index * OCC_W) +: OCC_W] =
                    OCC_W'(occupancy);
                dense_req_o[block_index] =
                    (occupancy >= DENSE_ENTER_THRESHOLD);
            end
        end
    end

endmodule
