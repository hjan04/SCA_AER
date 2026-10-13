`timescale 1ns/1ps

module aer_mode_controller #(
    parameter int PACKET_W = 37,
    parameter int CLEAR_W = 256,
    parameter int HOLD_CYCLES = 4
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Enter dense mode at the configured high threshold.  While already in
    // dense mode, dense_hold_i remains high whenever occupancy is above the
    // lower exit threshold.
    input  logic                  dense_enter_i,
    input  logic                  dense_hold_i,
    input  logic                  dense_valid_i,
    input  logic [PACKET_W-1:0]   dense_packet_i,
    input  logic [CLEAR_W-1:0]    dense_clear_mask_i,

    input  logic                  sparse_valid_i,
    input  logic [PACKET_W-1:0]   sparse_packet_i,
    input  logic [CLEAR_W-1:0]    sparse_clear_mask_i,

    output logic                  packet_valid_o,
    output logic [PACKET_W-1:0]   packet_payload_o,
    output logic [CLEAR_W-1:0]    packet_clear_mask_o,
    output logic                  packet_is_dense_o,
    output logic                  dense_mode_o
);

    localparam int HOLD_COUNT_W =
        (HOLD_CYCLES <= 1) ? 1 : $clog2(HOLD_CYCLES + 1);

    logic dense_mode_q;
    logic [HOLD_COUNT_W-1:0] exit_hold_count_q;
    logic dense_mode_active;

    assign dense_mode_o = dense_mode_q;
    // Permit the packet that crosses the entry threshold to be dense without
    // waiting an extra cycle for dense_mode_q to update.
    assign dense_mode_active = dense_mode_q || dense_enter_i;

`ifndef SYNTHESIS
    initial begin
        if (HOLD_CYCLES < 1) begin
            $fatal(1, "HOLD_CYCLES must be at least one");
        end
    end
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dense_mode_q <= 1'b0;
            exit_hold_count_q <= '0;
        end else if (!dense_mode_q) begin
            exit_hold_count_q <= '0;
            if (dense_enter_i) begin
                dense_mode_q <= 1'b1;
            end
        end else if (dense_hold_i) begin
            // Occupancy recovered above the exit threshold: cancel a pending
            // sparse transition and remain in dense mode.
            dense_mode_q <= 1'b1;
            exit_hold_count_q <= '0;
        end else if (exit_hold_count_q == HOLD_CYCLES - 1) begin
            dense_mode_q <= 1'b0;
            exit_hold_count_q <= '0;
        end else begin
            dense_mode_q <= 1'b1;
            exit_hold_count_q <= exit_hold_count_q + 1'b1;
        end
    end

    always_comb begin
        packet_valid_o = (dense_mode_active && dense_valid_i) || sparse_valid_i;
        packet_payload_o = '0;
        packet_clear_mask_o = '0;
        packet_is_dense_o = 1'b0;

        if (dense_mode_active && dense_valid_i) begin
            packet_payload_o = dense_packet_i;
            packet_clear_mask_o = dense_clear_mask_i;
            packet_is_dense_o = 1'b1;
        end else if (sparse_valid_i) begin
            packet_payload_o = sparse_packet_i;
            packet_clear_mask_o = sparse_clear_mask_i;
        end
    end

endmodule
