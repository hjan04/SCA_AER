// Included by tb/tests/tb_benchmark_baseline.sv.

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

task automatic write_result_csv;
    int fd;
    int total_loss;
    int undrained_at_end;
    int bits_transmitted;
    int p95_latency;
    real event_loss_rate;
    real throughput_injection_window;
    real throughput_full_run;
    real average_latency_cycles;
    real bits_per_event;
    real output_utilization;
    real cycles_per_handshake;
    begin
        undrained_at_end = count_model_pending();
        total_loss = generated_events - transmitted_events;
        bits_transmitted = transmitted_events * EVENT_W;
        p95_latency = percentile_latency(95);

        event_loss_rate = safe_div_real(total_loss, generated_events);
        throughput_injection_window =
            safe_div_real(transmitted_during_injection, injection_cycles);
        throughput_full_run = safe_div_real(transmitted_events, clock_cycles_total);
        average_latency_cycles = safe_div_real(latency_sum, transmitted_events);
        bits_per_event = safe_div_real(bits_transmitted, transmitted_events);
        output_utilization = safe_div_real(output_req_high_cycles, clock_cycles_total);
        cycles_per_handshake = safe_div_real(clock_cycles_total, successful_handshakes);

        fd = $fopen(result_file, "w");
        if (fd == 0) begin
            $fatal(1, "Could not open result file: %s", result_file);
        end

        $fwrite(fd, "architecture,traffic_type,traffic_variant,seed,x_size,y_size,");
        $fwrite(fd, "clock_cycles_injection,clock_cycles_total,");
        $fwrite(fd, "offered_events_per_cycle,generated_events,captured_events,");
        $fwrite(fd, "transmitted_events,capture_loss,undrained_at_end,total_loss,");
        $fwrite(fd, "event_loss_rate,successful_handshakes,cycles_per_handshake,");
        $fwrite(fd, "throughput_injection_window,throughput_full_run,");
        $fwrite(fd, "average_latency_cycles,maximum_latency_cycles,p95_latency_cycles,");
        $fwrite(fd, "bits_transmitted,bits_per_event,output_req_high_cycles,");
        $fwrite(fd, "output_utilization,ack_delay_cycles,notes\n");

        $fwrite(fd, "baseline,%s,%s,%0d,%0d,%0d,", traffic_type, traffic_variant,
                seed, X_SIZE, Y_SIZE);
        $fwrite(fd, "%0d,%0d,%0.6f,%0d,%0d,", injection_cycles, clock_cycles_total,
                offered_events_per_cycle, generated_events, captured_events);
        $fwrite(fd, "%0d,%0d,%0d,%0d,%0.8f,", transmitted_events, capture_loss,
                undrained_at_end, total_loss, event_loss_rate);
        $fwrite(fd, "%0d,%0.6f,%0.8f,%0.8f,", successful_handshakes,
                cycles_per_handshake, throughput_injection_window,
                throughput_full_run);
        $fwrite(fd, "%0.6f,%0d,%0d,", average_latency_cycles,
                maximum_latency_cycles, p95_latency);
        $fwrite(fd, "%0d,%0.6f,%0d,%0.8f,%0d,", bits_transmitted, bits_per_event,
                output_req_high_cycles, output_utilization, ack_delay_cycles);
        $fwrite(fd, "unexpected_output=%0d;duplicate_output=%0d;ack_without_req=%0d;trace_events=%0d\n",
                unexpected_output, duplicate_output, ack_without_req, trace_count);
        $fclose(fd);
    end
endtask
