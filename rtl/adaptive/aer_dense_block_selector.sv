`timescale 1ns/1ps

module aer_dense_block_selector #(
    parameter int BLOCK_X_COUNT = 4,
    parameter int BLOCK_Y_COUNT = 4,
    parameter int N_BLOCKS = BLOCK_X_COUNT * BLOCK_Y_COUNT,
    parameter int BLOCK_INDEX_W = (N_BLOCKS <= 1) ? 1 : $clog2(N_BLOCKS),
    parameter int BLOCK_X_W = (BLOCK_X_COUNT <= 1) ? 1 : $clog2(BLOCK_X_COUNT),
    parameter int BLOCK_Y_W = (BLOCK_Y_COUNT <= 1) ? 1 : $clog2(BLOCK_Y_COUNT)
) (
    input  logic [N_BLOCKS-1:0]       dense_req_i,
    input  logic [BLOCK_INDEX_W-1:0]  block_base_i,

    output logic                      grant_valid_o,
    output logic [BLOCK_INDEX_W-1:0]  grant_block_index_o,
    output logic [BLOCK_X_W-1:0]      grant_block_x_o,
    output logic [BLOCK_Y_W-1:0]      grant_block_y_o,
    output logic [N_BLOCKS-1:0]       grant_onehot_o
);

    rr_arbiter #(
        .N(N_BLOCKS),
        .INDEX_W(BLOCK_INDEX_W)
    ) u_block_rr (
        .req_i(dense_req_i),
        .base_i(block_base_i),
        .grant_valid_o(grant_valid_o),
        .grant_index_o(grant_block_index_o),
        .grant_onehot_o(grant_onehot_o)
    );

    always_comb begin
        int block_index;

        block_index = int'(grant_block_index_o);
        grant_block_x_o = BLOCK_X_W'(block_index % BLOCK_X_COUNT);
        grant_block_y_o = BLOCK_Y_W'(block_index / BLOCK_X_COUNT);
    end

endmodule
