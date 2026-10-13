`timescale 1ns/1ps

module tb_stage4_compare;

    parameter int ARCH = 0; // 0 = baseline, 1 = adaptive
    parameter int X_SIZE = 16;
    parameter int Y_SIZE = 16;
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE);
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE);
    parameter int N_PIXELS = X_SIZE * Y_SIZE;
    parameter int EVENT_W = 1 + Y_W + X_W;

    parameter int BLOCK_W = 4;
    parameter int BLOCK_H = 4;
    parameter int BLOCK_PIXELS = BLOCK_W * BLOCK_H;
    parameter int BLOCK_X_COUNT = (X_SIZE + BLOCK_W - 1) / BLOCK_W;
    parameter int BLOCK_Y_COUNT = (Y_SIZE + BLOCK_H - 1) / BLOCK_H;
    parameter int BLOCK_X_W = (BLOCK_X_COUNT <= 1) ? 1 : $clog2(BLOCK_X_COUNT);
    parameter int BLOCK_Y_W = (BLOCK_Y_COUNT <= 1) ? 1 : $clog2(BLOCK_Y_COUNT);
    parameter int DENSE_ENTER_THRESHOLD = 5;

    parameter int ADAPTIVE_SPARSE_PACKET_W = 1 + X_W + Y_W + 1;
    parameter int DENSE_PACKET_W = 1 + BLOCK_X_W + BLOCK_Y_W +
                                   BLOCK_PIXELS + BLOCK_PIXELS;
    parameter int PACKET_W = (DENSE_PACKET_W > ADAPTIVE_SPARSE_PACKET_W) ?
                             DENSE_PACKET_W : ADAPTIVE_SPARSE_PACKET_W;

    parameter int LINK_WIDTH = 16;
    parameter int LINK_TYPE_W = 2;
    parameter int LINK_LEN_W = 6;
    parameter int LINK_HEADER_W = LINK_TYPE_W + LINK_LEN_W;
    parameter int MAX_PACKET_W = PACKET_W;
    parameter int MAX_TRACE_EVENTS = 200000;
    parameter int MAX_LATENCY_BINS = 200000;
    parameter int MAX_INFLIGHT_EVENTS = 200000;

    localparam int BASELINE_SPARSE_TYPE = 0;
    localparam int ADAPTIVE_SPARSE_TYPE = 1;
    localparam int ADAPTIVE_DENSE_TYPE = 2;

    localparam int ADAPTIVE_TYPE_BIT = 0;
    localparam int ADAPTIVE_SPARSE_X_LSB = 1;
    localparam int ADAPTIVE_SPARSE_Y_LSB = ADAPTIVE_SPARSE_X_LSB + X_W;
    localparam int ADAPTIVE_SPARSE_POL_BIT = ADAPTIVE_SPARSE_Y_LSB + Y_W;
    localparam int DENSE_BLOCK_X_LSB = 1;
    localparam int DENSE_BLOCK_Y_LSB = DENSE_BLOCK_X_LSB + BLOCK_X_W;
    localparam int DENSE_VALID_LSB = DENSE_BLOCK_Y_LSB + BLOCK_Y_W;
    localparam int DENSE_POL_LSB = DENSE_VALID_LSB + BLOCK_PIXELS;

    logic clk;
    logic rst_n;

    logic [N_PIXELS-1:0] pixel_event_valid_i;
    logic [N_PIXELS-1:0] pixel_event_pol_i;

    logic link_valid;
    logic link_ready;
    logic [LINK_WIDTH-1:0] link_data;
    logic sink_ready;

    logic busy_o;
    logic dense_eligible_o;
    logic logical_packet_accept;
    logic [LINK_TYPE_W-1:0] logical_packet_type;
    logic [LINK_LEN_W-1:0] logical_packet_bits;
    logic [MAX_PACKET_W-1:0] logical_packet_data;
    logic [N_PIXELS-1:0] logical_packet_clear_mask;

    logic packet_valid;
    logic packet_ready;
    logic [LINK_TYPE_W-1:0] packet_type;
    logic [LINK_LEN_W-1:0] packet_bits;
    logic [MAX_PACKET_W-1:0] packet_data;
    logic deserializer_busy;

    string architecture_name;
    string trace_file;
    string result_file;
    string traffic_type;
    string traffic_variant;
    string link_ready_policy;
    int seed;
    int ready_seed;
    int stall_period;
    int stall_cycles;
    int random_stall_percent;
    int injection_cycles;
    int max_drain_cycles;
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

    bit inflight_valid [0:MAX_INFLIGHT_EVENTS-1];
    int inflight_x [0:MAX_INFLIGHT_EVENTS-1];
    int inflight_y [0:MAX_INFLIGHT_EVENTS-1];
    int inflight_pol [0:MAX_INFLIGHT_EVENTS-1];
    int inflight_cycle [0:MAX_INFLIGHT_EVENTS-1];
    int inflight_count;
    int inflight_write_index;

    int current_cycle;
    int clock_cycles_total;
    int ready_cycle_count;
    logic [31:0] ready_lfsr;
    int generated_events;
    int captured_events;
    int delivered_events;
    int delivered_during_injection;
    int capture_loss;
    int transport_loss;
    int unexpected_output;
    int duplicate_output;
    int logical_model_errors;
    int logical_packets;
    int sparse_packets;
    int dense_packets;
    int events_in_sparse_packets;
    int events_in_dense_packets;
    int min_dense_packet_occupancy;
    int max_dense_packet_occupancy;
    int dense_occupancy_hist [0:BLOCK_PIXELS];
    int cycles_dense_eligible;
    int physical_link_beats;
    int physical_bits_transmitted;
    int link_active_cycles;
    int link_stall_cycles;
    longint logical_bits_transmitted;
    longint latency_sum;
    int maximum_latency_cycles;
    int latency_hist [0:MAX_LATENCY_BINS-1];
    bit benchmark_active;

    generate
        if (ARCH == 0) begin : gen_baseline
            aer_baseline_link_top #(
                .X_SIZE(X_SIZE),
                .Y_SIZE(Y_SIZE),
                .X_W(X_W),
                .Y_W(Y_W),
                .N_PIXELS(N_PIXELS),
                .EVENT_W(EVENT_W),
                .LINK_WIDTH(LINK_WIDTH),
                .MAX_PACKET_W(MAX_PACKET_W),
                .LINK_TYPE_W(LINK_TYPE_W),
                .LINK_LEN_W(LINK_LEN_W)
            ) dut (
                .clk(clk),
                .rst_n(rst_n),
                .pixel_event_valid_i(pixel_event_valid_i),
                .pixel_event_pol_i(pixel_event_pol_i),
                .link_valid_o(link_valid),
                .link_ready_i(link_ready),
                .link_data_o(link_data),
                .busy_o(busy_o),
                .logical_packet_accept_o(logical_packet_accept),
                .logical_packet_type_o(logical_packet_type),
                .logical_packet_bits_o(logical_packet_bits),
                .logical_packet_data_o(logical_packet_data),
                .logical_packet_clear_mask_o(logical_packet_clear_mask)
            );
            assign dense_eligible_o = 1'b0;
        end else begin : gen_adaptive
            aer_adaptive_link_top #(
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
                .SPARSE_PACKET_W(ADAPTIVE_SPARSE_PACKET_W),
                .DENSE_PACKET_W(DENSE_PACKET_W),
                .PACKET_W(PACKET_W),
                .LINK_WIDTH(LINK_WIDTH),
                .MAX_PACKET_W(MAX_PACKET_W),
                .LINK_TYPE_W(LINK_TYPE_W),
                .LINK_LEN_W(LINK_LEN_W)
            ) dut (
                .clk(clk),
                .rst_n(rst_n),
                .pixel_event_valid_i(pixel_event_valid_i),
                .pixel_event_pol_i(pixel_event_pol_i),
                .link_valid_o(link_valid),
                .link_ready_i(link_ready),
                .link_data_o(link_data),
                .busy_o(busy_o),
                .dense_eligible_o(dense_eligible_o),
                .logical_packet_accept_o(logical_packet_accept),
                .logical_packet_type_o(logical_packet_type),
                .logical_packet_bits_o(logical_packet_bits),
                .logical_packet_data_o(logical_packet_data),
                .logical_packet_clear_mask_o(logical_packet_clear_mask)
            );
        end
    endgenerate

    aer_link_deserializer #(
        .LINK_WIDTH(LINK_WIDTH),
        .MAX_PACKET_W(MAX_PACKET_W),
        .TYPE_W(LINK_TYPE_W),
        .LEN_W(LINK_LEN_W)
    ) u_deserializer (
        .clk(clk),
        .rst_n(rst_n),
        .link_valid_i(link_valid),
        .link_ready_o(link_ready),
        .link_data_i(link_data),
        .sink_ready_i(sink_ready),
        .packet_valid_o(packet_valid),
        .packet_ready_i(packet_ready),
        .packet_type_o(packet_type),
        .packet_bits_o(packet_bits),
        .packet_data_o(packet_data),
        .busy_o(deserializer_busy)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
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

    function automatic int count_bits(input logic [BLOCK_PIXELS-1:0] value);
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

    function automatic int beat_count(input int payload_bits);
        int total_bits;
        begin
            total_bits = LINK_HEADER_W + payload_bits;
            beat_count = (total_bits + LINK_WIDTH - 1) / LINK_WIDTH;
            if (beat_count < 1) begin
                beat_count = 1;
            end
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
            if (delivered_events <= 0) begin
                return -1;
            end

            target = (delivered_events * percentile + 99) / 100;
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

    function automatic bit has_unknown_packet(input logic [MAX_PACKET_W-1:0] value);
        begin
            return (^value === 1'bx);
        end
    endfunction

    function automatic bit next_ready_value;
        logic feedback;
        begin
            if (link_ready_policy == "always") begin
                return 1'b1;
            end else if (link_ready_policy == "periodic") begin
                if (stall_period <= 0) begin
                    return 1'b1;
                end
                return ((ready_cycle_count % stall_period) >= stall_cycles);
            end else if (link_ready_policy == "random") begin
                return ((ready_lfsr % 100) >= random_stall_percent);
            end else begin
                return 1'b1;
            end
        end
    endfunction

    task automatic update_ready_lfsr;
        logic feedback;
        begin
            feedback = ready_lfsr[31] ^ ready_lfsr[21] ^ ready_lfsr[1] ^ ready_lfsr[0];
            ready_lfsr <= {ready_lfsr[30:0], feedback};
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

    `include "tb/traffic/tb_trace_driver.sv"

    task automatic reset_scoreboard_model;
        begin
            generated_events = trace_count;
            captured_events = 0;
            delivered_events = 0;
            delivered_during_injection = 0;
            capture_loss = 0;
            transport_loss = 0;
            unexpected_output = 0;
            duplicate_output = 0;
            logical_model_errors = 0;
            logical_packets = 0;
            sparse_packets = 0;
            dense_packets = 0;
            events_in_sparse_packets = 0;
            events_in_dense_packets = 0;
            min_dense_packet_occupancy = BLOCK_PIXELS + 1;
            max_dense_packet_occupancy = 0;
            cycles_dense_eligible = 0;
            physical_link_beats = 0;
            physical_bits_transmitted = 0;
            link_active_cycles = 0;
            link_stall_cycles = 0;
            logical_bits_transmitted = 0;
            latency_sum = 0;
            maximum_latency_cycles = 0;
            inflight_count = 0;
            inflight_write_index = 0;

            model_pending = '0;
            model_pol = '0;
            for (int i = 0; i < N_PIXELS; i++) begin
                model_event_id[i] = -1;
                model_cycle[i] = -1;
            end

            for (int i = 0; i < MAX_LATENCY_BINS; i++) begin
                latency_hist[i] = 0;
            end

            for (int i = 0; i <= BLOCK_PIXELS; i++) begin
                dense_occupancy_hist[i] = 0;
            end

            clear_drive_metadata();
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            pixel_event_valid_i = '0;
            pixel_event_pol_i = '0;
            benchmark_active = 1'b0;
            packet_ready = 1'b1;
            sink_ready = 1'b1;
            ready_cycle_count = 0;
            ready_lfsr = ready_seed[31:0];

            repeat (6) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic inflight_add(
        input int x,
        input int y,
        input int polarity,
        input int input_cycle
    );
        begin
            if (inflight_write_index >= MAX_INFLIGHT_EVENTS) begin
                $fatal(1, "Exceeded MAX_INFLIGHT_EVENTS=%0d", MAX_INFLIGHT_EVENTS);
            end
            inflight_valid[inflight_write_index] = 1'b1;
            inflight_x[inflight_write_index] = x;
            inflight_y[inflight_write_index] = y;
            inflight_pol[inflight_write_index] = polarity;
            inflight_cycle[inflight_write_index] = input_cycle;
            inflight_write_index++;
            inflight_count++;
        end
    endtask

    task automatic service_model_event(input int x, input int y, input int polarity);
        int idx;
        begin
            if ((x < 0) || (x >= X_SIZE) || (y < 0) || (y >= Y_SIZE) ||
                ((polarity != 0) && (polarity != 1))) begin
                logical_model_errors++;
            end else begin
                idx = pixel_index(x, y);
                if (!model_pending[idx]) begin
                    logical_model_errors++;
                end else if (model_pol[idx] != polarity[0]) begin
                    logical_model_errors++;
                    model_pending[idx] = 1'b0;
                    model_event_id[idx] = -1;
                    model_cycle[idx] = -1;
                end else begin
                    if (!logical_packet_clear_mask[idx]) begin
                        logical_model_errors++;
                    end
                    inflight_add(x, y, polarity, model_cycle[idx]);
                    model_pending[idx] = 1'b0;
                    model_event_id[idx] = -1;
                    model_cycle[idx] = -1;
                end
            end
        end
    endtask

    task automatic decode_logical_accept;
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
            logical_packets++;
            logical_bits_transmitted += LINK_HEADER_W + int'(logical_packet_bits);

            if (ARCH == 0) begin
                if ((logical_packet_type != LINK_TYPE_W'(BASELINE_SPARSE_TYPE)) ||
                    (logical_packet_bits != LINK_LEN_W'(EVENT_W))) begin
                    logical_model_errors++;
                end
                sparse_packets++;
                events_in_sparse_packets++;
                x = logical_packet_data[0 +: X_W];
                y = logical_packet_data[X_W +: Y_W];
                polarity = logical_packet_data[EVENT_W-1];
                service_model_event(x, y, polarity);
            end else if (logical_packet_type == LINK_TYPE_W'(ADAPTIVE_SPARSE_TYPE)) begin
                if ((logical_packet_bits != LINK_LEN_W'(ADAPTIVE_SPARSE_PACKET_W)) ||
                    (logical_packet_data[ADAPTIVE_TYPE_BIT] != 1'b0)) begin
                    logical_model_errors++;
                end
                sparse_packets++;
                events_in_sparse_packets++;
                x = logical_packet_data[ADAPTIVE_SPARSE_X_LSB +: X_W];
                y = logical_packet_data[ADAPTIVE_SPARSE_Y_LSB +: Y_W];
                polarity = logical_packet_data[ADAPTIVE_SPARSE_POL_BIT];
                service_model_event(x, y, polarity);
            end else if (logical_packet_type == LINK_TYPE_W'(ADAPTIVE_DENSE_TYPE)) begin
                if ((logical_packet_bits != LINK_LEN_W'(DENSE_PACKET_W)) ||
                    (logical_packet_data[ADAPTIVE_TYPE_BIT] != 1'b1)) begin
                    logical_model_errors++;
                end
                dense_packets++;
                block_x = logical_packet_data[DENSE_BLOCK_X_LSB +: BLOCK_X_W];
                block_y = logical_packet_data[DENSE_BLOCK_Y_LSB +: BLOCK_Y_W];
                valid_mask = logical_packet_data[DENSE_VALID_LSB +: BLOCK_PIXELS];
                polarity_mask = logical_packet_data[DENSE_POL_LSB +: BLOCK_PIXELS];
                dense_event_count = count_bits(valid_mask);
                events_in_dense_packets += dense_event_count;
                if (dense_event_count > max_dense_packet_occupancy) begin
                    max_dense_packet_occupancy = dense_event_count;
                end
                if (dense_event_count < min_dense_packet_occupancy) begin
                    min_dense_packet_occupancy = dense_event_count;
                end
                if ((dense_event_count >= 0) && (dense_event_count <= BLOCK_PIXELS)) begin
                    dense_occupancy_hist[dense_event_count]++;
                end

                for (int local_index = 0; local_index < BLOCK_PIXELS; local_index++) begin
                    if (valid_mask[local_index]) begin
                        local_x = local_index % BLOCK_W;
                        local_y = local_index / BLOCK_W;
                        x = (block_x * BLOCK_W) + local_x;
                        y = (block_y * BLOCK_H) + local_y;
                        polarity = polarity_mask[local_index];
                        service_model_event(x, y, polarity);
                    end
                end
            end else begin
                logical_model_errors++;
            end
        end
    endtask

    task automatic receiver_observe_event(input int x, input int y, input int polarity);
        bit matched;
        int latency;
        begin
            matched = 1'b0;
            if ((x < 0) || (x >= X_SIZE) || (y < 0) || (y >= Y_SIZE) ||
                ((polarity != 0) && (polarity != 1))) begin
                unexpected_output++;
            end else begin
                for (int i = 0; i < inflight_write_index; i++) begin
                    if (!matched && inflight_valid[i] &&
                        (inflight_x[i] == x) && (inflight_y[i] == y) &&
                        (inflight_pol[i] == polarity)) begin
                        inflight_valid[i] = 1'b0;
                        inflight_count--;
                        delivered_events++;
                        if (current_cycle < injection_cycles) begin
                            delivered_during_injection++;
                        end

                        latency = current_cycle - inflight_cycle[i];
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
                        matched = 1'b1;
                    end
                end
                if (!matched) begin
                    duplicate_output++;
                    transport_loss++;
                end
            end
        end
    endtask

    task automatic decode_receiver_packet;
        int x;
        int y;
        int polarity;
        int block_x;
        int block_y;
        int local_x;
        int local_y;
        logic [BLOCK_PIXELS-1:0] valid_mask;
        logic [BLOCK_PIXELS-1:0] polarity_mask;
        begin
            if (has_unknown_packet(packet_data)) begin
                unexpected_output++;
            end else if (packet_type == LINK_TYPE_W'(BASELINE_SPARSE_TYPE)) begin
                if (packet_bits != LINK_LEN_W'(EVENT_W)) begin
                    unexpected_output++;
                end
                x = packet_data[0 +: X_W];
                y = packet_data[X_W +: Y_W];
                polarity = packet_data[EVENT_W-1];
                receiver_observe_event(x, y, polarity);
            end else if (packet_type == LINK_TYPE_W'(ADAPTIVE_SPARSE_TYPE)) begin
                if ((packet_bits != LINK_LEN_W'(ADAPTIVE_SPARSE_PACKET_W)) ||
                    (packet_data[ADAPTIVE_TYPE_BIT] != 1'b0)) begin
                    unexpected_output++;
                end
                x = packet_data[ADAPTIVE_SPARSE_X_LSB +: X_W];
                y = packet_data[ADAPTIVE_SPARSE_Y_LSB +: Y_W];
                polarity = packet_data[ADAPTIVE_SPARSE_POL_BIT];
                receiver_observe_event(x, y, polarity);
            end else if (packet_type == LINK_TYPE_W'(ADAPTIVE_DENSE_TYPE)) begin
                if ((packet_bits != LINK_LEN_W'(DENSE_PACKET_W)) ||
                    (packet_data[ADAPTIVE_TYPE_BIT] != 1'b1)) begin
                    unexpected_output++;
                end
                block_x = packet_data[DENSE_BLOCK_X_LSB +: BLOCK_X_W];
                block_y = packet_data[DENSE_BLOCK_Y_LSB +: BLOCK_Y_W];
                valid_mask = packet_data[DENSE_VALID_LSB +: BLOCK_PIXELS];
                polarity_mask = packet_data[DENSE_POL_LSB +: BLOCK_PIXELS];

                for (int local_index = 0; local_index < BLOCK_PIXELS; local_index++) begin
                    if (valid_mask[local_index]) begin
                        local_x = local_index % BLOCK_W;
                        local_y = local_index / BLOCK_W;
                        x = (block_x * BLOCK_W) + local_x;
                        y = (block_y * BLOCK_H) + local_y;
                        polarity = polarity_mask[local_index];
                        receiver_observe_event(x, y, polarity);
                    end
                end
            end else begin
                unexpected_output++;
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sink_ready <= 1'b1;
            ready_cycle_count <= 0;
            ready_lfsr <= ready_seed[31:0];
        end else if (benchmark_active) begin
            sink_ready <= next_ready_value();
            ready_cycle_count <= ready_cycle_count + 1;
            update_ready_lfsr();
        end else begin
            sink_ready <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst_n && benchmark_active) begin
            if (link_valid) begin
                link_active_cycles++;
            end
            if (link_valid && link_ready) begin
                physical_link_beats++;
            end
            if (link_valid && !link_ready) begin
                link_stall_cycles++;
            end
            if (dense_eligible_o) begin
                cycles_dense_eligible++;
            end

            if (logical_packet_accept) begin
                decode_logical_accept();
            end

            if (packet_valid) begin
                decode_receiver_packet();
            end

            scoreboard_capture_inputs();
        end
    end

    task automatic write_result_csv;
        int fd;
        int total_loss;
        int undrained_events;
        int p50_latency;
        int p95_latency;
        int p99_latency;
        real event_loss_rate;
        real throughput_events_per_cycle;
        real average_latency;
        real logical_bits_per_event;
        real physical_bits_per_event;
        real events_per_physical_beat;
        real events_per_physical_bit;
        real link_utilization;
        real average_dense_occupancy;
        begin
            if (dense_packets == 0) begin
                min_dense_packet_occupancy = 0;
            end

            physical_bits_transmitted = physical_link_beats * LINK_WIDTH;
            undrained_events = count_model_pending() + inflight_count;
            total_loss = generated_events - delivered_events;
            p50_latency = percentile_latency(50);
            p95_latency = percentile_latency(95);
            p99_latency = percentile_latency(99);

            event_loss_rate = safe_div_real(total_loss, generated_events);
            throughput_events_per_cycle = safe_div_real(delivered_events, clock_cycles_total);
            average_latency = safe_div_real(latency_sum, delivered_events);
            logical_bits_per_event = safe_div_real(logical_bits_transmitted, delivered_events);
            physical_bits_per_event = safe_div_real(physical_bits_transmitted, delivered_events);
            events_per_physical_beat = safe_div_real(delivered_events, physical_link_beats);
            events_per_physical_bit = safe_div_real(delivered_events, physical_bits_transmitted);
            link_utilization = safe_div_real(physical_link_beats, clock_cycles_total);
            average_dense_occupancy = safe_div_real(events_in_dense_packets, dense_packets);

            fd = $fopen(result_file, "w");
            if (fd == 0) begin
                $fatal(1, "Could not open result file: %s", result_file);
            end

            $fwrite(fd, "architecture,traffic_type,traffic_variant,trace_file,seed,");
            $fwrite(fd, "x_size,y_size,block_w,block_h,dense_threshold,");
            $fwrite(fd, "link_width,link_ready_policy,injection_cycles,total_cycles,");
            $fwrite(fd, "offered_events_per_cycle,generated_events,delivered_events,");
            $fwrite(fd, "capture_loss,transport_loss,undrained_events,total_loss,event_loss_rate,");
            $fwrite(fd, "logical_packets,sparse_packets,dense_packets,");
            $fwrite(fd, "events_in_sparse_packets,events_in_dense_packets,");
            $fwrite(fd, "logical_bits,physical_link_beats,physical_bits,");
            $fwrite(fd, "logical_bits_per_event,physical_bits_per_event,");
            $fwrite(fd, "events_per_physical_beat,events_per_physical_bit,");
            $fwrite(fd, "throughput_events_per_cycle,delivered_during_injection,");
            $fwrite(fd, "average_latency,maximum_latency,p50_latency,p95_latency,p99_latency,");
            $fwrite(fd, "link_active_cycles,link_stall_cycles,link_utilization,");
            $fwrite(fd, "cycles_dense_eligible,average_dense_occupancy,");
            $fwrite(fd, "minimum_dense_occupancy,maximum_dense_occupancy,");
            $fwrite(fd, "dense_occ_0,dense_occ_1,dense_occ_2,dense_occ_3,");
            $fwrite(fd, "dense_occ_4,dense_occ_5,dense_occ_6,dense_occ_7,");
            $fwrite(fd, "dense_occ_8,dense_occ_9,dense_occ_10,dense_occ_11,");
            $fwrite(fd, "dense_occ_12,dense_occ_13,dense_occ_14,dense_occ_15,dense_occ_16,");
            $fwrite(fd, "baseline_payload_bits,adaptive_sparse_payload_bits,dense_payload_bits,");
            $fwrite(fd, "baseline_frame_bits,adaptive_sparse_frame_bits,dense_frame_bits,");
            $fwrite(fd, "baseline_physical_bits_per_packet,adaptive_sparse_physical_bits_per_packet,");
            $fwrite(fd, "dense_physical_bits_per_packet,notes\n");

            $fwrite(fd, "%s,%s,%s,%s,%0d,", architecture_name, traffic_type,
                    traffic_variant, trace_file, seed);
            $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,", X_SIZE, Y_SIZE, BLOCK_W,
                    BLOCK_H, DENSE_ENTER_THRESHOLD);
            $fwrite(fd, "%0d,%s,%0d,%0d,", LINK_WIDTH, link_ready_policy,
                    injection_cycles, clock_cycles_total);
            $fwrite(fd, "%0.8f,%0d,%0d,", offered_events_per_cycle,
                    generated_events, delivered_events);
            $fwrite(fd, "%0d,%0d,%0d,%0d,%0.8f,", capture_loss,
                    transport_loss, undrained_events, total_loss,
                    event_loss_rate);
            $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,", logical_packets, sparse_packets,
                    dense_packets, events_in_sparse_packets,
                    events_in_dense_packets);
            $fwrite(fd, "%0d,%0d,%0d,", logical_bits_transmitted,
                    physical_link_beats, physical_bits_transmitted);
            $fwrite(fd, "%0.6f,%0.6f,%0.8f,%0.10f,",
                    logical_bits_per_event, physical_bits_per_event,
                    events_per_physical_beat, events_per_physical_bit);
            $fwrite(fd, "%0.8f,%0d,", throughput_events_per_cycle,
                    delivered_during_injection);
            $fwrite(fd, "%0.6f,%0d,%0d,%0d,%0d,", average_latency,
                    maximum_latency_cycles, p50_latency, p95_latency,
                    p99_latency);
            $fwrite(fd, "%0d,%0d,%0.8f,%0d,%0.6f,%0d,%0d,",
                    link_active_cycles, link_stall_cycles, link_utilization,
                    cycles_dense_eligible, average_dense_occupancy,
                    min_dense_packet_occupancy, max_dense_packet_occupancy);
            for (int i = 0; i <= BLOCK_PIXELS; i++) begin
                $fwrite(fd, "%0d,", dense_occupancy_hist[i]);
            end
            $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",
                    EVENT_W, ADAPTIVE_SPARSE_PACKET_W, DENSE_PACKET_W,
                    LINK_HEADER_W + EVENT_W,
                    LINK_HEADER_W + ADAPTIVE_SPARSE_PACKET_W,
                    LINK_HEADER_W + DENSE_PACKET_W,
                    beat_count(EVENT_W) * LINK_WIDTH,
                    beat_count(ADAPTIVE_SPARSE_PACKET_W) * LINK_WIDTH,
                    beat_count(DENSE_PACKET_W) * LINK_WIDTH);
            $fwrite(fd, "captured_events=%0d;logical_model_errors=%0d;unexpected_output=%0d;duplicate_output=%0d;trace_events=%0d;stall_period=%0d;stall_cycles=%0d;random_stall_percent=%0d\n",
                    captured_events, logical_model_errors, unexpected_output,
                    duplicate_output, trace_count, stall_period, stall_cycles,
                    random_stall_percent);
            $fclose(fd);
        end
    endtask

    initial begin
        string wave_file;
        int drain_cycles;
        int dump_waves;

        if (ARCH == 0) begin
            architecture_name = "baseline_link";
        end else begin
            architecture_name = "adaptive_link";
        end

        if (!$value$plusargs("TRACE_FILE=%s", trace_file)) begin
            trace_file = "traces/generated/stage2/uniform_rate0.10_rate0p100_seed1_ack0.trace";
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_file)) begin
            result_file = "results/csv/runs/stage4/stage4_compare.csv";
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
        if (!$value$plusargs("READY_SEED=%d", ready_seed)) begin
            ready_seed = 32'h13579bdf;
        end
        if (!$value$plusargs("INJECTION_CYCLES=%d", injection_cycles)) begin
            injection_cycles = 5000;
        end
        if (!$value$plusargs("MAX_DRAIN_CYCLES=%d", max_drain_cycles)) begin
            max_drain_cycles = 5000;
        end
        if (!$value$plusargs("OFFERED_EVENTS_PER_CYCLE=%f", offered_events_per_cycle)) begin
            offered_events_per_cycle = 0.0;
        end
        if (!$value$plusargs("LINK_READY_POLICY=%s", link_ready_policy)) begin
            link_ready_policy = "always";
        end
        if (!$value$plusargs("STALL_PERIOD=%d", stall_period)) begin
            stall_period = 5;
        end
        if (!$value$plusargs("STALL_CYCLES=%d", stall_cycles)) begin
            stall_cycles = 1;
        end
        if (!$value$plusargs("RANDOM_STALL_PERCENT=%d", random_stall_percent)) begin
            random_stall_percent = 20;
        end
        if (!$value$plusargs("WAVE_FILE=%s", wave_file)) begin
            wave_file = "results/waves/stage4/stage4_compare.vcd";
        end
        if (!$value$plusargs("DUMP_WAVES=%d", dump_waves)) begin
            dump_waves = 0;
        end

        if (ready_seed == 0) begin
            ready_seed = 32'h1acebeef;
        end

        if (dump_waves != 0) begin
            $dumpfile(wave_file);
            $dumpvars(0, tb_stage4_compare);
        end

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
        while (((count_model_pending() != 0) || (inflight_count != 0) ||
                busy_o || deserializer_busy || packet_valid) &&
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

        write_result_csv();

        $display("STAGE4 BENCHMARK: PASS");
        $display("architecture=%s trace=%s", architecture_name, trace_file);
        $display("result=%s", result_file);
        $display("generated=%0d delivered=%0d capture_loss=%0d transport_loss=%0d pending=%0d inflight=%0d logical_packets=%0d dense_packets=%0d physical_beats=%0d",
                 generated_events, delivered_events, capture_loss, transport_loss,
                 count_model_pending(), inflight_count, logical_packets,
                 dense_packets, physical_link_beats);

        if ((transport_loss != 0) || (unexpected_output != 0) ||
            (duplicate_output != 0) || (logical_model_errors != 0)) begin
            $fatal(1, "Stage4 scoreboard errors transport=%0d unexpected=%0d duplicate=%0d logical_model=%0d",
                   transport_loss, unexpected_output, duplicate_output,
                   logical_model_errors);
        end

        $finish;
    end

endmodule
