`timescale 1ns/1ps

module tb_benchmark_adaptive;

    parameter int X_SIZE = 16;
    parameter int Y_SIZE = 16;
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE);
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE);
    parameter int N_PIXELS = X_SIZE * Y_SIZE;

    parameter int BLOCK_W = 4;
    parameter int BLOCK_H = 4;
    parameter int BLOCK_PIXELS = BLOCK_W * BLOCK_H;
    parameter int BLOCK_X_COUNT = (X_SIZE + BLOCK_W - 1) / BLOCK_W;
    parameter int BLOCK_Y_COUNT = (Y_SIZE + BLOCK_H - 1) / BLOCK_H;
    parameter int BLOCK_X_W = (BLOCK_X_COUNT <= 1) ? 1 : $clog2(BLOCK_X_COUNT);
    parameter int BLOCK_Y_W = (BLOCK_Y_COUNT <= 1) ? 1 : $clog2(BLOCK_Y_COUNT);
    parameter int DENSE_ENTER_THRESHOLD = 5;

    parameter int SPARSE_PACKET_W = 1 + X_W + Y_W + 1;
    parameter int DENSE_PACKET_W = 1 + BLOCK_X_W + BLOCK_Y_W +
                                   BLOCK_PIXELS + BLOCK_PIXELS;
    parameter int PACKET_W = (DENSE_PACKET_W > SPARSE_PACKET_W) ?
                             DENSE_PACKET_W : SPARSE_PACKET_W;
    parameter int MAX_TRACE_EVENTS = 200000;
    parameter int MAX_LATENCY_BINS = 200000;

    localparam int TYPE_BIT          = 0;
    localparam int SPARSE_X_LSB      = 1;
    localparam int SPARSE_Y_LSB      = SPARSE_X_LSB + X_W;
    localparam int SPARSE_POL_BIT    = SPARSE_Y_LSB + Y_W;
    localparam int DENSE_BLOCK_X_LSB = 1;
    localparam int DENSE_BLOCK_Y_LSB = DENSE_BLOCK_X_LSB + BLOCK_X_W;
    localparam int DENSE_VALID_LSB   = DENSE_BLOCK_Y_LSB + BLOCK_Y_W;
    localparam int DENSE_POL_LSB     = DENSE_VALID_LSB + BLOCK_PIXELS;

    logic clk;
    logic rst_n;
    logic [N_PIXELS-1:0] pixel_event_valid_i;
    logic [N_PIXELS-1:0] pixel_event_pol_i;
    logic aer_req_o;
    logic aer_ack_i;
    logic [PACKET_W-1:0] aer_packet_o;
    logic busy_o;
    logic dense_eligible_o;

    string trace_file;
    string result_file;
    string traffic_type;
    string traffic_variant;
    int seed;
    int injection_cycles;
    int max_drain_cycles;
    int ack_delay_cycles;
    real offered_events_per_cycle;

    int trace_count;
    int trace_read_index;
    int trace_event_id [0:MAX_TRACE_EVENTS-1];
    int trace_cycle [0:MAX_TRACE_EVENTS-1];
    int trace_x [0:MAX_TRACE_EVENTS-1];
    int trace_y [0:MAX_TRACE_EVENTS-1];
    int trace_pol [0:MAX_TRACE_EVENTS-1];

    logic [N_PIXELS-1:0] drive_valid;
    logic [N_PIXELS-1:0] drive_pol;
    int drive_event_id [0:N_PIXELS-1];
    int drive_cycle [0:N_PIXELS-1];

    logic [N_PIXELS-1:0] model_pending;
    logic [N_PIXELS-1:0] model_pol;
    int model_event_id [0:N_PIXELS-1];
    int model_cycle [0:N_PIXELS-1];

    int current_cycle;
    int clock_cycles_total;
    int generated_events;
    int captured_events;
    int transmitted_events;
    int transmitted_during_injection;
    int capture_loss;
    int unexpected_output;
    int duplicate_output;
    int ack_without_req;
    int successful_handshakes;
    int output_req_high_cycles;
    int cycles_dense_eligible;
    int sparse_packets;
    int dense_packets;
    int events_in_sparse_packets;
    int events_in_dense_packets;
    int min_dense_packet_occupancy;
    int max_dense_packet_occupancy;
    longint latency_sum;
    int maximum_latency_cycles;
    int latency_hist [0:MAX_LATENCY_BINS-1];
    bit benchmark_active;

    aer_adaptive_top #(
        .X_SIZE(X_SIZE),
        .Y_SIZE(Y_SIZE),
        .X_W(X_W),
        .Y_W(Y_W),
        .N_PIXELS(N_PIXELS),
        .BLOCK_W(BLOCK_W),
        .BLOCK_H(BLOCK_H),
        .BLOCK_PIXELS(BLOCK_PIXELS),
        .BLOCK_X_COUNT(BLOCK_X_COUNT),
        .BLOCK_Y_COUNT(BLOCK_Y_COUNT),
        .BLOCK_X_W(BLOCK_X_W),
        .BLOCK_Y_W(BLOCK_Y_W),
        .DENSE_ENTER_THRESHOLD(DENSE_ENTER_THRESHOLD),
        .SPARSE_PACKET_W(SPARSE_PACKET_W),
        .DENSE_PACKET_W(DENSE_PACKET_W),
        .PACKET_W(PACKET_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_event_valid_i(pixel_event_valid_i),
        .pixel_event_pol_i(pixel_event_pol_i),
        .aer_req_o(aer_req_o),
        .aer_ack_i(aer_ack_i),
        .aer_packet_o(aer_packet_o),
        .busy_o(busy_o),
        .dense_eligible_o(dense_eligible_o)
    );

    tb_output_sink u_output_sink (
        .clk(clk),
        .rst_n(rst_n),
        .req_i(aer_req_o),
        .ack_delay_cycles_i(ack_delay_cycles),
        .ack_o(aer_ack_i)
    );

    `include "tb/traffic/tb_trace_driver.sv"

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        string wave_file;

        if (!$value$plusargs("TRACE_FILE=%s", trace_file)) begin
            trace_file = "traces/generated/stage2/uniform_rate0.10_rate0p100_seed1_ack0.trace";
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_file)) begin
            result_file = "results/csv/runs/stage3/adaptive_benchmark.csv";
        end
        if (!$value$plusargs("TRAFFIC_TYPE=%s", traffic_type)) begin
            traffic_type = "unknown";
        end
        if (!$value$plusargs("TRAFFIC_VARIANT=%s", traffic_variant)) begin
            traffic_variant = "unknown";
        end
        if (!$value$plusargs("SEED=%d", seed)) begin
            seed = 0;
        end
        if (!$value$plusargs("INJECTION_CYCLES=%d", injection_cycles)) begin
            injection_cycles = 5000;
        end
        if (!$value$plusargs("MAX_DRAIN_CYCLES=%d", max_drain_cycles)) begin
            max_drain_cycles = 5000;
        end
        if (!$value$plusargs("ACK_DELAY_CYCLES=%d", ack_delay_cycles)) begin
            ack_delay_cycles = 0;
        end
        if (!$value$plusargs("OFFERED_EVENTS_PER_CYCLE=%f", offered_events_per_cycle)) begin
            offered_events_per_cycle = 0.0;
        end
        if (!$value$plusargs("WAVE_FILE=%s", wave_file)) begin
            wave_file = "results/waves/stage3/adaptive_benchmark.vcd";
        end

        $dumpfile(wave_file);
        $dumpvars(0, tb_benchmark_adaptive);
    end

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

    function automatic int count_dense_bits(input logic [BLOCK_PIXELS-1:0] value);
        int count;
        begin
            count = 0;
            for (int i = 0; i < BLOCK_PIXELS; i++) begin
                if (value[i]) begin
                    count++;
                end
            end
            return count;
        end
    endfunction

    function automatic bit has_unknown_packet(input logic [PACKET_W-1:0] value);
        begin
            return (^value === 1'bx);
        end
    endfunction

    function automatic real safe_div_real(input real numerator, input real denominator);
        begin
            if (denominator == 0.0) begin
                return 0.0;
            end
            return numerator / denominator;
        end
    endfunction

    function automatic int percentile_latency(input int percentile);
        int target;
        int cumulative;
        begin
            if (transmitted_events <= 0) begin
                return -1;
            end

            target = (transmitted_events * percentile + 99) / 100;
            cumulative = 0;
            percentile_latency = MAX_LATENCY_BINS - 1;

            for (int i = 0; i < MAX_LATENCY_BINS; i++) begin
                cumulative += latency_hist[i];
                if (cumulative >= target) begin
                    percentile_latency = i;
                    return percentile_latency;
                end
            end
        end
    endfunction

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
            cycles_dense_eligible = 0;
            sparse_packets = 0;
            dense_packets = 0;
            events_in_sparse_packets = 0;
            events_in_dense_packets = 0;
            min_dense_packet_occupancy = BLOCK_PIXELS + 1;
            max_dense_packet_occupancy = 0;
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

    task automatic scoreboard_observe_event(
        input int x,
        input int y,
        input int polarity
    );
        int idx;
        int latency;
        begin
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
    endtask

    task automatic scoreboard_accept_output;
        int x;
        int y;
        int polarity;
        int block_x;
        int block_y;
        int local_x;
        int local_y;
        int dense_event_count;
        logic [BLOCK_PIXELS-1:0] valid_mask;
        logic [BLOCK_PIXELS-1:0] polarity_mask;
        begin
            successful_handshakes++;

            if (has_unknown_packet(aer_packet_o)) begin
                unexpected_output++;
            end else if (!aer_packet_o[TYPE_BIT]) begin
                sparse_packets++;
                events_in_sparse_packets++;
                x = aer_packet_o[SPARSE_X_LSB +: X_W];
                y = aer_packet_o[SPARSE_Y_LSB +: Y_W];
                polarity = aer_packet_o[SPARSE_POL_BIT];
                scoreboard_observe_event(x, y, polarity);
            end else begin
                dense_packets++;
                block_x = aer_packet_o[DENSE_BLOCK_X_LSB +: BLOCK_X_W];
                block_y = aer_packet_o[DENSE_BLOCK_Y_LSB +: BLOCK_Y_W];
                valid_mask = aer_packet_o[DENSE_VALID_LSB +: BLOCK_PIXELS];
                polarity_mask = aer_packet_o[DENSE_POL_LSB +: BLOCK_PIXELS];
                dense_event_count = count_dense_bits(valid_mask);

                if (dense_event_count == 0) begin
                    unexpected_output++;
                end
                events_in_dense_packets += dense_event_count;
                if (dense_event_count > max_dense_packet_occupancy) begin
                    max_dense_packet_occupancy = dense_event_count;
                end
                if (dense_event_count < min_dense_packet_occupancy) begin
                    min_dense_packet_occupancy = dense_event_count;
                end

                for (int local_index = 0; local_index < BLOCK_PIXELS; local_index++) begin
                    if (valid_mask[local_index]) begin
                        local_x = local_index % BLOCK_W;
                        local_y = local_index / BLOCK_W;
                        x = (block_x * BLOCK_W) + local_x;
                        y = (block_y * BLOCK_H) + local_y;
                        polarity = polarity_mask[local_index];
                        scoreboard_observe_event(x, y, polarity);
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

    always @(posedge clk) begin
        if (!rst_n || !benchmark_active) begin
            if (!rst_n) begin
                output_req_high_cycles <= 0;
                ack_without_req <= 0;
                cycles_dense_eligible <= 0;
            end
        end else begin
            if (aer_req_o) begin
                output_req_high_cycles++;
            end
            if (dense_eligible_o) begin
                cycles_dense_eligible++;
            end
            if (aer_ack_i && !aer_req_o) begin
                ack_without_req++;
            end

            if (aer_req_o && aer_ack_i) begin
                scoreboard_accept_output();
            end

            scoreboard_capture_inputs();
        end
    end

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            benchmark_active = 1'b0;

            repeat (6) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic write_result_csv;
        int fd;
        int total_loss;
        int undrained_at_end;
        int p95_latency;
        int logical_bits_transmitted;
        int total_logical_packets;
        real event_loss_rate;
        real throughput_injection_window;
        real throughput_full_run;
        real average_latency_cycles;
        real output_utilization;
        real cycles_per_handshake;
        real average_events_per_packet;
        real average_dense_packet_occupancy;
        real logical_bits_per_delivered_event;
        real fraction_events_sent_dense;
        begin
            undrained_at_end = count_model_pending();
            total_loss = generated_events - transmitted_events;
            p95_latency = percentile_latency(95);
            total_logical_packets = sparse_packets + dense_packets;
            logical_bits_transmitted =
                (sparse_packets * SPARSE_PACKET_W) + (dense_packets * DENSE_PACKET_W);

            event_loss_rate = safe_div_real(total_loss, generated_events);
            throughput_injection_window =
                safe_div_real(transmitted_during_injection, injection_cycles);
            throughput_full_run = safe_div_real(transmitted_events, clock_cycles_total);
            average_latency_cycles = safe_div_real(latency_sum, transmitted_events);
            output_utilization = safe_div_real(output_req_high_cycles, clock_cycles_total);
            cycles_per_handshake = safe_div_real(clock_cycles_total, successful_handshakes);
            average_events_per_packet =
                safe_div_real(transmitted_events, total_logical_packets);
            average_dense_packet_occupancy =
                safe_div_real(events_in_dense_packets, dense_packets);
            logical_bits_per_delivered_event =
                safe_div_real(logical_bits_transmitted, transmitted_events);
            fraction_events_sent_dense =
                safe_div_real(events_in_dense_packets, transmitted_events);

            if (dense_packets == 0) begin
                min_dense_packet_occupancy = 0;
            end

            fd = $fopen(result_file, "w");
            if (fd == 0) begin
                $fatal(1, "Could not open result file: %s", result_file);
            end

            $fwrite(fd, "architecture,traffic_type,traffic_variant,seed,x_size,y_size,");
            $fwrite(fd, "block_w,block_h,dense_enter_threshold,");
            $fwrite(fd, "clock_cycles_injection,clock_cycles_total,");
            $fwrite(fd, "offered_events_per_cycle,generated_events,captured_events,");
            $fwrite(fd, "transmitted_events,capture_loss,undrained_at_end,total_loss,");
            $fwrite(fd, "event_loss_rate,successful_handshakes,cycles_per_handshake,");
            $fwrite(fd, "throughput_injection_window,throughput_full_run,");
            $fwrite(fd, "average_latency_cycles,maximum_latency_cycles,p95_latency_cycles,");
            $fwrite(fd, "sparse_packets,dense_packets,total_logical_packets,");
            $fwrite(fd, "events_in_sparse_packets,events_in_dense_packets,");
            $fwrite(fd, "average_events_per_packet,average_dense_packet_occupancy,");
            $fwrite(fd, "minimum_dense_packet_occupancy,maximum_dense_packet_occupancy,");
            $fwrite(fd, "logical_bits_transmitted,logical_bits_per_delivered_event,");
            $fwrite(fd, "sparse_packet_bits,dense_packet_bits,");
            $fwrite(fd, "cycles_dense_eligible,fraction_events_sent_dense,");
            $fwrite(fd, "output_req_high_cycles,output_utilization,ack_delay_cycles,notes\n");

            $fwrite(fd, "adaptive,%s,%s,%0d,%0d,%0d,", traffic_type, traffic_variant,
                    seed, X_SIZE, Y_SIZE);
            $fwrite(fd, "%0d,%0d,%0d,", BLOCK_W, BLOCK_H, DENSE_ENTER_THRESHOLD);
            $fwrite(fd, "%0d,%0d,%0.6f,%0d,%0d,", injection_cycles, clock_cycles_total,
                    offered_events_per_cycle, generated_events, captured_events);
            $fwrite(fd, "%0d,%0d,%0d,%0d,%0.8f,", transmitted_events, capture_loss,
                    undrained_at_end, total_loss, event_loss_rate);
            $fwrite(fd, "%0d,%0.6f,%0.8f,%0.8f,", successful_handshakes,
                    cycles_per_handshake, throughput_injection_window,
                    throughput_full_run);
            $fwrite(fd, "%0.6f,%0d,%0d,", average_latency_cycles,
                    maximum_latency_cycles, p95_latency);
            $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,", sparse_packets, dense_packets,
                    total_logical_packets, events_in_sparse_packets,
                    events_in_dense_packets);
            $fwrite(fd, "%0.6f,%0.6f,%0d,%0d,", average_events_per_packet,
                    average_dense_packet_occupancy, min_dense_packet_occupancy,
                    max_dense_packet_occupancy);
            $fwrite(fd, "%0d,%0.6f,%0d,%0d,", logical_bits_transmitted,
                    logical_bits_per_delivered_event, SPARSE_PACKET_W,
                    DENSE_PACKET_W);
            $fwrite(fd, "%0d,%0.8f,%0d,%0.8f,%0d,", cycles_dense_eligible,
                    fraction_events_sent_dense, output_req_high_cycles,
                    output_utilization, ack_delay_cycles);
            $fwrite(fd, "unexpected_output=%0d;duplicate_output=%0d;ack_without_req=%0d;trace_events=%0d;packet_w=%0d\n",
                    unexpected_output, duplicate_output, ack_without_req, trace_count,
                    PACKET_W);
            $fclose(fd);
        end
    endtask

    initial begin
        int drain_cycles;

        read_trace_file();
        reset_scoreboard_model();
        reset_dut();

        trace_read_index = 0;
        current_cycle = 0;
        clock_cycles_total = 0;
        benchmark_active = 1'b1;

        for (current_cycle = 0; current_cycle < injection_cycles; current_cycle++) begin
            @(negedge clk);
            prepare_drive_for_cycle(current_cycle);
            @(posedge clk);
            #1;
            clock_cycles_total = current_cycle + 1;
        end

        @(negedge clk);
        pixel_event_valid_i = '0;
        pixel_event_pol_i = '0;
        clear_drive_metadata();

        drain_cycles = 0;
        while (((count_model_pending() != 0) || busy_o) &&
               (drain_cycles < max_drain_cycles)) begin
            current_cycle = injection_cycles + drain_cycles;
            @(posedge clk);
            #1;
            drain_cycles++;
            clock_cycles_total = injection_cycles + drain_cycles;
        end

        benchmark_active = 1'b0;
        @(negedge clk);
        pixel_event_valid_i = '0;
        pixel_event_pol_i = '0;

        if (trace_read_index != trace_count) begin
            $fatal(1, "Trace contains events beyond injection window: read %0d of %0d",
                   trace_read_index, trace_count);
        end
        if ((unexpected_output != 0) || (duplicate_output != 0) ||
            (ack_without_req != 0)) begin
            $fatal(1, "Benchmark scoreboard errors unexpected=%0d duplicate=%0d ack_without_req=%0d",
                   unexpected_output, duplicate_output, ack_without_req);
        end

        write_result_csv();

        $display("ADAPTIVE BENCHMARK: PASS");
        $display("trace=%s", trace_file);
        $display("result=%s", result_file);
        $display("threshold=%0d generated=%0d transmitted=%0d capture_loss=%0d sparse_packets=%0d dense_packets=%0d pending_at_end=%0d",
                 DENSE_ENTER_THRESHOLD, generated_events, transmitted_events,
                 capture_loss, sparse_packets, dense_packets, count_model_pending());

        $finish;
    end

endmodule
