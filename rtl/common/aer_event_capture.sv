`timescale 1ns/1ps

module aer_event_capture #(
    parameter int N_PIXELS = 256,
    parameter bit ENABLE_COUNTER = 1'b0,
    parameter int COUNTER_W = 2
) (
    input  logic                clk,
    input  logic                rst_n,

    input  logic [N_PIXELS-1:0] pixel_event_valid_i,
    input  logic [N_PIXELS-1:0] pixel_event_pol_i,
    input  logic [N_PIXELS-1:0] clear_i,

    output logic [N_PIXELS-1:0] pending_o,
    output logic [N_PIXELS-1:0] pending_pol_o
);

    logic [COUNTER_W-1:0] repeat_count [N_PIXELS];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_o     <= '0;
            pending_pol_o <= '0;
            for (int i = 0; i < N_PIXELS; i++) begin
                repeat_count[i] <= '0;
            end
        end else begin
            for (int i = 0; i < N_PIXELS; i++) begin
                if (!ENABLE_COUNTER) begin
                    if (pixel_event_valid_i[i] && (!pending_o[i] || clear_i[i])) begin
                        pending_pol_o[i] <= pixel_event_pol_i[i];
                    end
                    pending_o[i] <= (pending_o[i] && !clear_i[i]) ||
                                    pixel_event_valid_i[i];
                    repeat_count[i] <= '0;
                end else if (clear_i[i]) begin
                    if (!pending_o[i] && pixel_event_valid_i[i]) begin
                        pending_o[i]     <= 1'b1;
                        pending_pol_o[i] <= pixel_event_pol_i[i];
                        repeat_count[i]  <= '0;
                    end else if (pending_o[i] && pixel_event_valid_i[i] &&
                                 (pixel_event_pol_i[i] == pending_pol_o[i])) begin
                        // One event is consumed and one equal-polarity event arrives.
                        pending_o[i] <= 1'b1;
                    end else if (pending_o[i] && pixel_event_valid_i[i]) begin
                        // On clear+new with opposite polarity, preserve the new event.
                        pending_o[i]     <= 1'b1;
                        pending_pol_o[i] <= pixel_event_pol_i[i];
                        repeat_count[i]  <= '0;
                    end else if (repeat_count[i] != '0) begin
                        // Re-issue one previously captured equal-polarity event.
                        pending_o[i]    <= 1'b1;
                        repeat_count[i] <= repeat_count[i] - 1'b1;
                    end else begin
                        pending_o[i] <= 1'b0;
                    end
                end else if (!pending_o[i] && pixel_event_valid_i[i]) begin
                    pending_o[i]     <= 1'b1;
                    pending_pol_o[i] <= pixel_event_pol_i[i];
                    repeat_count[i]  <= '0;
                end else if (pending_o[i] && pixel_event_valid_i[i] &&
                             (pixel_event_pol_i[i] == pending_pol_o[i]) &&
                             !(&repeat_count[i])) begin
                    repeat_count[i] <= repeat_count[i] + 1'b1;
                end
            end
        end
    end

endmodule`timescale 1ns/1ps

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
