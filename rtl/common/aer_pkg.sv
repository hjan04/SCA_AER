`timescale 1ns/1ps

package aer_pkg;

    localparam int AER_POLARITY_W = 1;
    localparam int AER_LINK_TYPE_W = 2;
    localparam int AER_LINK_LEN_W = 6;
    localparam int AER_LINK_HEADER_W = AER_LINK_TYPE_W + AER_LINK_LEN_W;

    typedef enum logic {
        AER_PACKET_SPARSE      = 1'b0,
        AER_PACKET_DENSE_BLOCK = 1'b1
    } aer_packet_type_e;

    typedef enum logic [AER_LINK_TYPE_W-1:0] {
        AER_LINK_BASELINE_SPARSE = 2'd0,
        AER_LINK_ADAPTIVE_SPARSE = 2'd1,
        AER_LINK_ADAPTIVE_DENSE  = 2'd2
    } aer_link_packet_type_e;

endpackage
