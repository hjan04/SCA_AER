`timescale 1ns/1ps

module aer_row_col_arbiter #(
    parameter int X_SIZE = 16,
    parameter int Y_SIZE = 16,
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE),
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE),
    parameter int N_PIXELS = X_SIZE * Y_SIZE
) (
    input  logic [N_PIXELS-1:0] pending_i,
    input  logic [Y_W-1:0]      row_base_i,
    input  logic [X_W-1:0]      col_base_i,

    output logic                grant_valid_o,
    output logic [X_W-1:0]      grant_x_o,
    output logic [Y_W-1:0]      grant_y_o,
    output logic [N_PIXELS-1:0] grant_onehot_o
);

    logic [Y_SIZE-1:0] row_req;
    logic [X_SIZE-1:0] col_req;
    logic              row_grant_valid;
    logic [Y_W-1:0]    row_grant_index;
    logic [Y_SIZE-1:0] row_grant_onehot;
    logic              col_grant_valid;
    logic [X_W-1:0]    col_grant_index;
    logic [X_SIZE-1:0] col_grant_onehot;

    rr_arbiter #(
        .N(Y_SIZE),
        .INDEX_W(Y_W)
    ) u_row_rr (
        .req_i(row_req),
        .base_i(row_base_i),
        .grant_valid_o(row_grant_valid),
        .grant_index_o(row_grant_index),
        .grant_onehot_o(row_grant_onehot)
    );

    rr_arbiter #(
        .N(X_SIZE),
        .INDEX_W(X_W)
    ) u_col_rr (
        .req_i(col_req),
        .base_i(col_base_i),
        .grant_valid_o(col_grant_valid),
        .grant_index_o(col_grant_index),
        .grant_onehot_o(col_grant_onehot)
    );

    always_comb begin
        row_req = '0;

        for (int y = 0; y < Y_SIZE; y++) begin
            for (int x = 0; x < X_SIZE; x++) begin
                row_req[y] = row_req[y] | pending_i[(y * X_SIZE) + x];
            end
        end
    end

    always_comb begin
        col_req = '0;

        if (row_grant_valid) begin
            for (int x = 0; x < X_SIZE; x++) begin
                col_req[x] = pending_i[(row_grant_index * X_SIZE) + x];
            end
        end
    end

    always_comb begin
        grant_valid_o = row_grant_valid && col_grant_valid;
        grant_x_o = col_grant_index;
        grant_y_o = row_grant_index;
        grant_onehot_o = '0;

        if (grant_valid_o) begin
            grant_onehot_o[(row_grant_index * X_SIZE) + col_grant_index] = 1'b1;
        end
    end

endmodule
