`timescale 1ns/1ps

module tb_output_sink (
    input  logic clk,
    input  logic rst_n,
    input  logic req_i,
    input  int   ack_delay_cycles_i,

    output logic ack_o
);

    typedef enum logic [1:0] {
        WAIT_REQ,
        WAIT_DELAY,
        ACK_HIGH
    } sink_state_e;

    sink_state_e state_q;
    int delay_count_q;

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= WAIT_REQ;
            delay_count_q <= 0;
            ack_o <= 1'b0;
        end else begin
            case (state_q)
                WAIT_REQ: begin
                    ack_o <= 1'b0;
                    delay_count_q <= 0;

                    if (req_i) begin
                        if (ack_delay_cycles_i <= 0) begin
                            ack_o <= 1'b1;
                            state_q <= ACK_HIGH;
                        end else begin
                            delay_count_q <= ack_delay_cycles_i;
                            state_q <= WAIT_DELAY;
                        end
                    end
                end

                WAIT_DELAY: begin
                    ack_o <= 1'b0;

                    if (!req_i) begin
                        delay_count_q <= 0;
                        state_q <= WAIT_REQ;
                    end else if (delay_count_q <= 1) begin
                        delay_count_q <= 0;
                        ack_o <= 1'b1;
                        state_q <= ACK_HIGH;
                    end else begin
                        delay_count_q <= delay_count_q - 1;
                    end
                end

                ACK_HIGH: begin
                    if (!req_i) begin
                        ack_o <= 1'b0;
                        state_q <= WAIT_REQ;
                    end else begin
                        ack_o <= 1'b1;
                    end
                end

                default: begin
                    state_q <= WAIT_REQ;
                    delay_count_q <= 0;
                    ack_o <= 1'b0;
                end
            endcase
        end
    end

endmodule
