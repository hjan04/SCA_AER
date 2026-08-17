`timescale 1ns/1ps

module tb_benchmark_baseline;

    parameter int X_SIZE = 16;
    parameter int Y_SIZE = 16;
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE);
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE);
    parameter int N_PIXELS = X_SIZE * Y_SIZE;
    parameter int EVENT_W = 1 + Y_W + X_W;
    parameter int MAX_TRACE_EVENTS = 200000;
    parameter int MAX_LATENCY_BINS = 200000;

    logic clk;
    logic rst_n;
    logic [N_PIXELS-1:0] pixel_event_valid_i;
    logic [N_PIXELS-1:0] pixel_event_pol_i;
    logic aer_req_o;
    logic aer_ack_i;
    logic [EVENT_W-1:0] aer_event_o;
    logic busy_o;

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
    longint latency_sum;
    int maximum_latency_cycles;
    int latency_hist [0:MAX_LATENCY_BINS-1];
    bit benchmark_active;

    aer_baseline_top #(
        .X_SIZE(X_SIZE),
        .Y_SIZE(Y_SIZE),
        .X_W(X_W),
        .Y_W(Y_W),
        .N_PIXELS(N_PIXELS),
        .EVENT_W(EVENT_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_event_valid_i(pixel_event_valid_i),
        .pixel_event_pol_i(pixel_event_pol_i),
        .aer_req_o(aer_req_o),
        .aer_ack_i(aer_ack_i),
        .aer_event_o(aer_event_o),
        .busy_o(busy_o)
    );

    tb_output_sink u_output_sink (
        .clk(clk),
        .rst_n(rst_n),
        .req_i(aer_req_o),
        .ack_delay_cycles_i(ack_delay_cycles),
        .ack_o(aer_ack_i)
    );

    `include "tb/common/tb_scoreboard.sv"
    `include "tb/common/tb_metrics.sv"
    `include "tb/traffic/tb_trace_driver.sv"

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        string wave_file;

        if (!$value$plusargs("TRACE_FILE=%s", trace_file)) begin
            trace_file = "traces/generated/baseline_smoke.trace";
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_file)) begin
            result_file = "results/csv/baseline_benchmark.csv";
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
            wave_file = "results/waves/baseline_benchmark.vcd";
        end

        $dumpfile(wave_file);
        $dumpvars(0, tb_benchmark_baseline);
    end

    always @(posedge clk) begin
        if (!rst_n || !benchmark_active) begin
            if (!rst_n) begin
                output_req_high_cycles <= 0;
                ack_without_req <= 0;
            end
        end else begin
            if (aer_req_o) begin
                output_req_high_cycles++;
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

        write_result_csv();

        $display("BASELINE BENCHMARK: PASS");
        $display("trace=%s", trace_file);
        $display("result=%s", result_file);
        $display("generated=%0d transmitted=%0d capture_loss=%0d pending_at_end=%0d",
                 generated_events, transmitted_events, capture_loss, count_model_pending());

        $finish;
    end

endmodule
