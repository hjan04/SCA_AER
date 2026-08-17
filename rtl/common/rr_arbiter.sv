`timescale 1ns/1ps

module rr_arbiter #(
    parameter int N = 4,
    parameter int INDEX_W = (N <= 1) ? 1 : $clog2(N)
) (
    input  logic [N-1:0]         req_i,
    input  logic [INDEX_W-1:0]   base_i,

    output logic                 grant_valid_o,
    output logic [INDEX_W-1:0]   grant_index_o,
    output logic [N-1:0]         grant_onehot_o
);

    always_comb begin
        grant_valid_o = 1'b0;
        grant_index_o = '0;
        grant_onehot_o = '0;

        for (int offset = 0; offset < N; offset++) begin
            int index;

            index = base_i + offset;
            if (index >= N) begin
                index = index - N;
            end

            if (!grant_valid_o && req_i[index]) begin
                grant_valid_o = 1'b1;
                grant_index_o = INDEX_W'(index);
                grant_onehot_o[index] = 1'b1;
            end
        end
    end

endmodule
