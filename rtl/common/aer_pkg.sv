`timescale 1ns/1ps

package aer_pkg;

    localparam int AER_POLARITY_W = 1;

    typedef enum logic {
        AER_PACKET_SPARSE      = 1'b0,
        AER_PACKET_DENSE_BLOCK = 1'b1
    } aer_packet_type_e;

endpackage
