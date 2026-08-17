`timescale 1ns/1ps

module aer_link_deserializer #(
    parameter int LINK_WIDTH = 16,
    parameter int MAX_PACKET_W = 37,
    parameter int TYPE_W = 2,
    parameter int LEN_W = 6,
    parameter int HEADER_W = TYPE_W + LEN_W,
    parameter int FRAME_W = HEADER_W + MAX_PACKET_W,
    parameter int MAX_BEATS = (FRAME_W + LINK_WIDTH - 1) / LINK_WIDTH,
    parameter int BEAT_COUNT_W = (MAX_BEATS <= 1) ? 1 : $clog2(MAX_BEATS + 1),
    parameter int COUNT_W = (FRAME_W <= 1) ? 1 : $clog2(FRAME_W + LINK_WIDTH + 1)
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    link_valid_i,
    output logic                    link_ready_o,
    input  logic [LINK_WIDTH-1:0]   link_data_i,
    input  logic                    sink_ready_i,

    output logic                    packet_valid_o,
    input  logic                    packet_ready_i,
    output logic [TYPE_W-1:0]       packet_type_o,
    output logic [LEN_W-1:0]        packet_bits_o,
    output logic [MAX_PACKET_W-1:0] packet_data_o,

    output logic                    busy_o
);

    logic [FRAME_W-1:0] frame_accum_q;
    logic [COUNT_W-1:0] bits_collected_q;
    logic [BEAT_COUNT_W-1:0] beats_remaining_q;
    logic [TYPE_W-1:0] active_packet_type_q;
    logic [LEN_W-1:0] active_packet_bits_q;
    logic receiving_q;

    assign link_ready_o = sink_ready_i && (!packet_valid_o || packet_ready_i);
    assign busy_o = receiving_q || packet_valid_o;

    function automatic [BEAT_COUNT_W-1:0] beat_count(input logic [LEN_W-1:0] payload_bits);
        int total_bits;
        int beats;
        begin
            total_bits = HEADER_W + int'(payload_bits);
            beats = (total_bits + LINK_WIDTH - 1) / LINK_WIDTH;
            if (beats < 1) begin
                beats = 1;
            end
            return BEAT_COUNT_W'(beats);
        end
    endfunction

    function automatic [FRAME_W-1:0] append_beat(
        input logic [FRAME_W-1:0]       frame,
        input logic [COUNT_W-1:0]       bit_offset,
        input logic [LINK_WIDTH-1:0]    beat_data
    );
        logic [FRAME_W+LINK_WIDTH-1:0] extended_frame;
        logic [FRAME_W+LINK_WIDTH-1:0] extended_beat;
        begin
            extended_frame = '0;
            extended_beat = '0;
            extended_frame[FRAME_W-1:0] = frame;
            extended_beat[LINK_WIDTH-1:0] = beat_data;
            extended_frame = extended_frame | (extended_beat << bit_offset);
            return extended_frame[FRAME_W-1:0];
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_accum_q <= '0;
            bits_collected_q <= '0;
            beats_remaining_q <= '0;
            active_packet_type_q <= '0;
            active_packet_bits_q <= '0;
            receiving_q <= 1'b0;
            packet_valid_o <= 1'b0;
            packet_type_o <= '0;
            packet_bits_o <= '0;
            packet_data_o <= '0;
        end else begin
            logic beat_accept;
            logic [FRAME_W-1:0] frame_next;
            logic [TYPE_W-1:0] first_type;
            logic [LEN_W-1:0] first_bits;
            logic [BEAT_COUNT_W-1:0] first_beats;

            beat_accept = link_valid_i && link_ready_o;
            frame_next = frame_accum_q;
            first_type = link_data_i[0 +: TYPE_W];
            first_bits = link_data_i[TYPE_W +: LEN_W];
            first_beats = beat_count(first_bits);

            if (packet_valid_o && packet_ready_i) begin
                packet_valid_o <= 1'b0;
            end

            if (beat_accept) begin
                if (!receiving_q) begin
                    frame_next = append_beat('0, '0, link_data_i);

                    if (first_beats == BEAT_COUNT_W'(1)) begin
                        packet_valid_o <= 1'b1;
                        packet_type_o <= first_type;
                        packet_bits_o <= first_bits;
                        packet_data_o <= frame_next[HEADER_W +: MAX_PACKET_W];
                        frame_accum_q <= '0;
                        bits_collected_q <= '0;
                        beats_remaining_q <= '0;
                        active_packet_type_q <= '0;
                        active_packet_bits_q <= '0;
                        receiving_q <= 1'b0;
                    end else begin
                        frame_accum_q <= frame_next;
                        bits_collected_q <= COUNT_W'(LINK_WIDTH);
                        beats_remaining_q <= first_beats - BEAT_COUNT_W'(1);
                        active_packet_type_q <= first_type;
                        active_packet_bits_q <= first_bits;
                        receiving_q <= 1'b1;
                    end
                end else begin
                    frame_next = append_beat(frame_accum_q, bits_collected_q, link_data_i);

                    if (beats_remaining_q == BEAT_COUNT_W'(1)) begin
                        packet_valid_o <= 1'b1;
                        packet_type_o <= active_packet_type_q;
                        packet_bits_o <= active_packet_bits_q;
                        packet_data_o <= frame_next[HEADER_W +: MAX_PACKET_W];
                        frame_accum_q <= '0;
                        bits_collected_q <= '0;
                        beats_remaining_q <= '0;
                        active_packet_type_q <= '0;
                        active_packet_bits_q <= '0;
                        receiving_q <= 1'b0;
                    end else begin
                        frame_accum_q <= frame_next;
                        bits_collected_q <= bits_collected_q + COUNT_W'(LINK_WIDTH);
                        beats_remaining_q <= beats_remaining_q - BEAT_COUNT_W'(1);
                    end
                end
            end
        end
    end

endmodule
