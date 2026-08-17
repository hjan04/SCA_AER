`timescale 1ns/1ps

module aer_event_capture #(
    parameter int N_PIXELS = 256
) (
    input  logic                clk,
    input  logic                rst_n,

    input  logic [N_PIXELS-1:0] pixel_event_valid_i,
    input  logic [N_PIXELS-1:0] pixel_event_pol_i,
    input  logic [N_PIXELS-1:0] clear_i,

    output logic [N_PIXELS-1:0] pending_o,
    output logic [N_PIXELS-1:0] pending_pol_o
);

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

endmodule
