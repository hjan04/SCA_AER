// Included by tb/tests/tb_benchmark_baseline.sv.
// The scoreboard mirrors the approved one-event-per-pixel capture model.

function automatic int pixel_index(input int x, input int y);
    begin
        return (y * X_SIZE) + x;
    end
endfunction

function automatic int count_model_pending;
    int count;
    begin
        count = 0;
        for (int i = 0; i < N_PIXELS; i++) begin
            if (model_pending[i]) begin
                count++;
            end
        end
        return count;
    end
endfunction

function automatic bit has_unknown_event(input logic [EVENT_W-1:0] value);
    begin
        return (^value === 1'bx);
    end
endfunction

task automatic decode_event(
    input  logic [EVENT_W-1:0] payload,
    output int x,
    output int y,
    output int polarity
);
    begin
        x = payload[X_W-1:0];
        y = payload[X_W + Y_W - 1:X_W];
        polarity = payload[EVENT_W-1];
    end
endtask

task automatic clear_drive_metadata;
    begin
        drive_valid = '0;
        drive_pol = '0;
        for (int i = 0; i < N_PIXELS; i++) begin
            drive_event_id[i] = -1;
            drive_cycle[i] = -1;
        end
    end
endtask

task automatic reset_scoreboard_model;
    begin
        generated_events = trace_count;
        captured_events = 0;
        transmitted_events = 0;
        transmitted_during_injection = 0;
        capture_loss = 0;
        unexpected_output = 0;
        duplicate_output = 0;
        ack_without_req = 0;
        successful_handshakes = 0;
        output_req_high_cycles = 0;
        latency_sum = 0;
        maximum_latency_cycles = 0;

        model_pending = '0;
        model_pol = '0;
        for (int i = 0; i < N_PIXELS; i++) begin
            model_event_id[i] = -1;
            model_cycle[i] = -1;
        end

        for (int i = 0; i < MAX_LATENCY_BINS; i++) begin
            latency_hist[i] = 0;
        end

        clear_drive_metadata();
    end
endtask

task automatic scoreboard_accept_output;
    int x;
    int y;
    int polarity;
    int idx;
    int latency;
    begin
        successful_handshakes++;

        if (has_unknown_event(aer_event_o)) begin
            unexpected_output++;
        end else begin
            decode_event(aer_event_o, x, y, polarity);

            if ((x < 0) || (x >= X_SIZE) || (y < 0) || (y >= Y_SIZE) ||
                ((polarity != 0) && (polarity != 1))) begin
                unexpected_output++;
            end else begin
                idx = pixel_index(x, y);

                if (!model_pending[idx]) begin
                    duplicate_output++;
                end else if (model_pol[idx] != polarity[0]) begin
                    unexpected_output++;
                    model_pending[idx] = 1'b0;
                    model_event_id[idx] = -1;
                    model_cycle[idx] = -1;
                end else begin
                    transmitted_events++;
                    if (current_cycle < injection_cycles) begin
                        transmitted_during_injection++;
                    end

                    latency = current_cycle - model_cycle[idx];
                    if (latency < 0) begin
                        latency = 0;
                    end
                    latency_sum += latency;
                    if (latency > maximum_latency_cycles) begin
                        maximum_latency_cycles = latency;
                    end
                    if (latency < MAX_LATENCY_BINS) begin
                        latency_hist[latency]++;
                    end else begin
                        latency_hist[MAX_LATENCY_BINS-1]++;
                    end

                    model_pending[idx] = 1'b0;
                    model_event_id[idx] = -1;
                    model_cycle[idx] = -1;
                end
            end
        end
    end
endtask

task automatic scoreboard_capture_inputs;
    begin
        for (int idx = 0; idx < N_PIXELS; idx++) begin
            if (drive_valid[idx]) begin
                if (model_pending[idx]) begin
                    capture_loss++;
                end else begin
                    model_pending[idx] = 1'b1;
                    model_pol[idx] = drive_pol[idx];
                    model_event_id[idx] = drive_event_id[idx];
                    model_cycle[idx] = drive_cycle[idx];
                    captured_events++;
                end
            end
        end
    end
endtask
