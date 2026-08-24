`timescale 1ns/1ps

// Shared, per-block overflow storage for events whose primary pending bit is
// already occupied.  Entries are selected associatively by local pixel index.
// For a given local index, the entry with the smallest sequence tag is
// promoted first, preserving FIFO order for repeated events from one pixel.
module aer_block_overflow_buffer #(
    parameter int OVERFLOW_DEPTH = 3,
    parameter int BLOCK_PIXELS = 16,
    parameter int LOSS_COUNT_W = 32,
    parameter int COUNT_W = (OVERFLOW_DEPTH <= 1) ? 1 : $clog2(OVERFLOW_DEPTH + 1),
    parameter int AGE_W = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [BLOCK_PIXELS-1:0] push_req_i,
    input  logic [BLOCK_PIXELS-1:0] push_polarity_i,
    output logic [BLOCK_PIXELS-1:0] push_reject_o,

    // A one bit means that the corresponding primary slot was transmitted in
    // this cycle.  Several bits can be set by a dense packet.
    input  logic [BLOCK_PIXELS-1:0] promote_mask_i,
    output logic [BLOCK_PIXELS-1:0] promote_hit_o,
    output logic [BLOCK_PIXELS-1:0] promote_pol_o,

    output logic [COUNT_W-1:0]      overflow_count_o,
    output logic [LOSS_COUNT_W-1:0] overflow_loss_count_o
);

    // A zero-depth instance is the explicit Model2-compatible disable mode.
    generate
        if (OVERFLOW_DEPTH == 0) begin : g_disabled
            assign push_reject_o = '1;
            assign promote_hit_o = '0;
            assign promote_pol_o = '0;
            assign overflow_count_o = '0;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    overflow_loss_count_o <= '0;
                end else if ((|push_req_i) && !(&overflow_loss_count_o)) begin
                    overflow_loss_count_o <= overflow_loss_count_o + $countones(push_req_i);
                end
            end
        end else begin : g_enabled
            logic [OVERFLOW_DEPTH-1:0] valid_q;
            logic [3:0]                local_idx_q [0:OVERFLOW_DEPTH-1];
            logic                      polarity_q [0:OVERFLOW_DEPTH-1];
            logic [AGE_W-1:0]          age_q [0:OVERFLOW_DEPTH-1];
            logic [AGE_W-1:0]          next_age_q;

            // Combinational processing is deliberately split into one-way
            // stages.  No stage writes a signal consumed by an earlier stage.
            logic [OVERFLOW_DEPTH-1:0] promote_remove_c;
            logic [OVERFLOW_DEPTH-1:0] empty_after_promote_c;
            logic [BLOCK_PIXELS-1:0] push_accept_c;
            integer push_slot_c [0:BLOCK_PIXELS-1];
            integer reject_count_c;

            // Stage 1: inspect registered slots only and select the oldest
            // matching entry for every promoted local pixel.
            always_comb begin
                int selected_slot;
                logic [AGE_W-1:0] selected_age;
                promote_hit_o = '0;
                promote_pol_o = '0;
                promote_remove_c = '0;
                for (int local_idx = 0; local_idx < BLOCK_PIXELS; local_idx++) begin
                    selected_slot = -1;
                    selected_age = '1;

                    if (promote_mask_i[local_idx]) begin
                        for (int slot = 0; slot < OVERFLOW_DEPTH; slot++) begin
                            if (valid_q[slot] &&
                                (local_idx_q[slot] == local_idx) &&
                                ((selected_slot == -1) || (age_q[slot] < selected_age))) begin
                                selected_slot = slot;
                                selected_age = age_q[slot];
                            end
                        end
                    end

                    if (selected_slot != -1) begin
                        promote_hit_o[local_idx] = 1'b1;
                        promote_pol_o[local_idx] = polarity_q[selected_slot];
                        promote_remove_c[selected_slot] = 1'b1;
                    end
                end
            end

            // Stage 2: the sole definition of capacity available to push.
            always_comb begin
                for (int slot = 0; slot < OVERFLOW_DEPTH; slot++) begin
                    empty_after_promote_c[slot] = !valid_q[slot] || promote_remove_c[slot];
                end
            end

            // Stage 3: allocate only from the finished stage-2 empty map.
            always_comb begin
                logic [OVERFLOW_DEPTH-1:0] available_slots;
                logic found_empty;
                available_slots = empty_after_promote_c;
                push_accept_c = '0;
                push_reject_o = '0;
                for (int local_idx = 0; local_idx < BLOCK_PIXELS; local_idx++) begin
                    found_empty = 1'b0;
                    push_slot_c[local_idx] = -1;
                    if (push_req_i[local_idx]) begin
                        for (int slot = 0; slot < OVERFLOW_DEPTH; slot++) begin
                            if (!found_empty && available_slots[slot]) begin
                                found_empty = 1'b1;
                                push_slot_c[local_idx] = slot;
                                available_slots[slot] = 1'b0;
                            end
                        end
                        if (found_empty) push_accept_c[local_idx] = 1'b1;
                        else push_reject_o[local_idx] = 1'b1;
                    end
                end
                reject_count_c = $countones(push_reject_o);
            end

            always_comb begin
                int count;
                count = 0;
                for (int slot = 0; slot < OVERFLOW_DEPTH; slot++) begin
                    if (valid_q[slot]) begin
                        count++;
                    end
                end
                overflow_count_o = COUNT_W'(count);
            end

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    valid_q <= '0;
                    next_age_q <= '0;
                    overflow_loss_count_o <= '0;
                    for (int slot = 0; slot < OVERFLOW_DEPTH; slot++) begin
                        local_idx_q[slot] <= '0;
                        polarity_q[slot] <= 1'b0;
                        age_q[slot] <= '0;
                    end
                end else begin
                    for (int slot = 0; slot < OVERFLOW_DEPTH; slot++) begin
                        if (promote_remove_c[slot]) begin
                            valid_q[slot] <= 1'b0;
                        end
                    end

                    for (int local_idx = 0; local_idx < BLOCK_PIXELS; local_idx++) begin
                        if (push_accept_c[local_idx]) begin
                            valid_q[push_slot_c[local_idx]] <= 1'b1;
                            local_idx_q[push_slot_c[local_idx]] <= local_idx;
                            polarity_q[push_slot_c[local_idx]] <= push_polarity_i[local_idx];
                            age_q[push_slot_c[local_idx]] <= next_age_q + local_idx;
                        end
                    end
                    if (|push_accept_c) begin
                        next_age_q <= next_age_q + $countones(push_accept_c);
                    end

                    if ((|push_reject_o) && !(&overflow_loss_count_o)) begin
                        if (overflow_loss_count_o > ({LOSS_COUNT_W{1'b1}} - reject_count_c))
                            overflow_loss_count_o <= '1;
                        else overflow_loss_count_o <= overflow_loss_count_o + reject_count_c;
                    end
                end
            end
        end
    endgenerate

`ifndef SYNTHESIS
    initial begin
        if (BLOCK_PIXELS < 1 || BLOCK_PIXELS > 16) begin
            $fatal(1, "BLOCK_PIXELS must be in the range 1..16");
        end
        if (LOSS_COUNT_W < 1 || AGE_W < 1) begin
            $fatal(1, "LOSS_COUNT_W and AGE_W must be positive");
        end
    end
`endif

endmodule
