// Included by tb/tests/tb_benchmark_baseline.sv.

task automatic read_trace_file;
    int fd;
    int code;
    int event_id;
    int cycle;
    int x;
    int y;
    int polarity;
    int last_cycle;
    begin
        trace_count = 0;
        last_cycle = -1;

        fd = $fopen(trace_file, "r");
        if (fd == 0) begin
            $fatal(1, "Could not open trace file: %s", trace_file);
        end

        while (!$feof(fd)) begin
            code = $fscanf(fd, "%d,%d,%d,%d,%d\n", event_id, cycle, x, y, polarity);

            if (code == 5) begin
                if (trace_count >= MAX_TRACE_EVENTS) begin
                    $fatal(1, "Trace exceeds MAX_TRACE_EVENTS=%0d", MAX_TRACE_EVENTS);
                end
                if (cycle < last_cycle) begin
                    $fatal(1, "Trace cycles must be sorted in nondecreasing order");
                end
                if ((x < 0) || (x >= X_SIZE) || (y < 0) || (y >= Y_SIZE) ||
                    ((polarity != 0) && (polarity != 1))) begin
                    $fatal(1, "Invalid trace event id=%0d cycle=%0d x=%0d y=%0d polarity=%0d",
                           event_id, cycle, x, y, polarity);
                end

                trace_event_id[trace_count] = event_id;
                trace_cycle[trace_count] = cycle;
                trace_x[trace_count] = x;
                trace_y[trace_count] = y;
                trace_pol[trace_count] = polarity;
                trace_count++;
                last_cycle = cycle;
            end else if (code != -1) begin
                $fatal(1, "Malformed trace line near entry %0d in %s", trace_count, trace_file);
            end
        end

        $fclose(fd);
    end
endtask

task automatic prepare_drive_for_cycle(input int cycle);
    int idx;
    begin
        pixel_event_valid_i = '0;
        pixel_event_pol_i = '0;
        clear_drive_metadata();

        if (cycle < injection_cycles) begin
            while ((trace_read_index < trace_count) &&
                   (trace_cycle[trace_read_index] == cycle)) begin
                idx = pixel_index(trace_x[trace_read_index], trace_y[trace_read_index]);

                if (drive_valid[idx]) begin
                    capture_loss++;
                end

                drive_valid[idx] = 1'b1;
                drive_pol[idx] = trace_pol[trace_read_index][0];
                drive_event_id[idx] = trace_event_id[trace_read_index];
                drive_cycle[idx] = trace_cycle[trace_read_index];
                pixel_event_valid_i[idx] = 1'b1;
                pixel_event_pol_i[idx] = trace_pol[trace_read_index][0];

                trace_read_index++;
            end
        end
    end
endtask
