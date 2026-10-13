`timescale 1ns/1ps

module aer_link_serializer #(
    parameter int LINK_WIDTH = 16,
    parameter int MAX_PACKET_W = 37,
    parameter int TYPE_W = 2,
    parameter int LEN_W = 6,
    parameter int HEADER_W = TYPE_W + LEN_W,
    parameter int FRAME_W = HEADER_W + MAX_PACKET_W,
    parameter int MAX_BEATS = (FRAME_W + LINK_WIDTH - 1) / LINK_WIDTH,
    parameter int BEAT_COUNT_W = (MAX_BEATS <= 1) ? 1 : $clog2(MAX_BEATS + 1)
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    packet_valid_i,
    output logic                    packet_ready_o,
    input  logic [TYPE_W-1:0]       packet_type_i,
    input  logic [LEN_W-1:0]        packet_bits_i,
    input  logic [MAX_PACKET_W-1:0] packet_data_i,

    output logic                    link_valid_o,
    input  logic                    link_ready_i,
    output logic [LINK_WIDTH-1:0]   link_data_o,

    output logic                    packet_accept_o,
    output logic                    busy_o
);

    logic [FRAME_W-1:0] frame_shift_q;
    logic [BEAT_COUNT_W-1:0] beats_remaining_q;

    assign busy_o = link_valid_o;
    assign link_data_o = frame_shift_q[LINK_WIDTH-1:0];

    assign packet_ready_o =
        !link_valid_o ||
        (link_valid_o && link_ready_i && (beats_remaining_q == BEAT_COUNT_W'(1)));

    assign packet_accept_o = packet_valid_i && packet_ready_o;

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

    function automatic [FRAME_W-1:0] build_frame(
        input logic [TYPE_W-1:0]       packet_type,
        input logic [LEN_W-1:0]        packet_bits,
        input logic [MAX_PACKET_W-1:0] packet_data
    );
        logic [FRAME_W-1:0] frame;
        begin
            frame = '0;
            frame[0 +: TYPE_W] = packet_type;
            frame[TYPE_W +: LEN_W] = packet_bits;
            frame[HEADER_W +: MAX_PACKET_W] = packet_data;
            return frame;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_shift_q <= '0;
            beats_remaining_q <= '0;
            link_valid_o <= 1'b0;
        end else begin
            if (!link_valid_o) begin
                if (packet_accept_o) begin
                    frame_shift_q <= build_frame(packet_type_i, packet_bits_i, packet_data_i);
                    beats_remaining_q <= beat_count(packet_bits_i);
                    link_valid_o <= 1'b1;
                end
            end else if (link_ready_i) begin
                if (beats_remaining_q == BEAT_COUNT_W'(1)) begin
                    if (packet_accept_o) begin
                        frame_shift_q <= build_frame(packet_type_i, packet_bits_i, packet_data_i);
                        beats_remaining_q <= beat_count(packet_bits_i);
                        link_valid_o <= 1'b1;
                    end else begin
                        frame_shift_q <= '0;
                        beats_remaining_q <= '0;
                        link_valid_o <= 1'b0;
                    end
                end else begin
                    frame_shift_q <= frame_shift_q >> LINK_WIDTH;
                    beats_remaining_q <= beats_remaining_q - BEAT_COUNT_W'(1);
                    link_valid_o <= 1'b1;
                end
            end
        end
    end

endmodule
