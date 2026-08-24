`timescale 1ns/1ps

module aer_event_capture #(
    parameter int N_PIXELS = 256,
    parameter bit OVERFLOW_ENABLE = 1'b0,
    parameter int COUNT_W = (N_PIXELS <= 1) ? 1 : $clog2(N_PIXELS + 1)
) (
    input  logic                clk,
    input  logic                rst_n,

    input  logic [N_PIXELS-1:0] pixel_event_valid_i,
    input  logic [N_PIXELS-1:0] pixel_event_pol_i,
    input  logic [N_PIXELS-1:0] clear_i,
    input  logic [N_PIXELS-1:0] promote_hit_i,
    input  logic [N_PIXELS-1:0] promote_pol_i,

    output logic [N_PIXELS-1:0] pending_o,
    output logic [N_PIXELS-1:0] pending_pol_o,
    output logic [N_PIXELS-1:0] overflow_push_req_o,
    output logic [N_PIXELS-1:0] overflow_push_pol_o,
    output logic [COUNT_W-1:0] primary_unique_occupancy_o
);
    generate if (!OVERFLOW_ENABLE) begin
    // Exact legacy Model2 equations; promotion inputs are intentionally ignored.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_o <= '0;
            pending_pol_o <= '0;
        end else begin
            for (int i = 0; i < N_PIXELS; i++) begin
                if (pixel_event_valid_i[i] && (!pending_o[i] || clear_i[i])) begin
                    pending_pol_o[i] <= pixel_event_pol_i[i];
                end

                pending_o[i] <= (pending_o[i] && !clear_i[i]) || pixel_event_valid_i[i];
            end
        end
    end
    assign overflow_push_req_o = '0;
    assign overflow_push_pol_o = '0;
    end else begin
    always_comb begin
        overflow_push_req_o = '0;
        overflow_push_pol_o = pixel_event_pol_i;
        for (int i=0; i<N_PIXELS; i++)
            if (pixel_event_valid_i[i] && (promote_hit_i[i] || (pending_o[i] && !clear_i[i])))
                overflow_push_req_o[i] = 1'b1;
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin pending_o <= '0; pending_pol_o <= '0; end
        else for (int i=0; i<N_PIXELS; i++) begin
            if (promote_hit_i[i]) begin
                pending_o[i] <= 1'b1;
                pending_pol_o[i] <= promote_pol_i[i];
            end else begin
                if (pixel_event_valid_i[i] && (!pending_o[i] || clear_i[i])) pending_pol_o[i] <= pixel_event_pol_i[i];
                pending_o[i] <= (pending_o[i] && !clear_i[i]) || pixel_event_valid_i[i];
            end
        end
    end
    end endgenerate

    always_comb begin
        int n; n=0;
        for (int i=0;i<N_PIXELS;i++) if (pending_o[i]) n++;
        primary_unique_occupancy_o = COUNT_W'(n);
    end

endmodule
