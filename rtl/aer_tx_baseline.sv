`timescale 1ns/1ps

module aer_tx_baseline #(
    parameter int N_SOURCES = 64,
    parameter int ADDR_W    = (N_SOURCES <= 1) ? 1 : $clog2(N_SOURCES)
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic [N_SOURCES-1:0] event_i,

    output logic                 aer_req_o,
    input  logic                 aer_ack_i,
    output logic [ADDR_W-1:0]    aer_addr_o,

    output logic                 busy_o,
    output logic [N_SOURCES-1:0] pending_o
);

    typedef logic [ADDR_W-1:0] addr_t;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_REQ_HIGH,
        ST_REQ_LOW
    } state_e;

    state_e state_q;
    state_e state_d;

    logic [N_SOURCES-1:0] pending_q;
    logic [N_SOURCES-1:0] pending_d;
    logic [N_SOURCES-1:0] active_src_q;
    logic [N_SOURCES-1:0] active_src_d;
    logic [N_SOURCES-1:0] pending_with_events;
    logic [N_SOURCES-1:0] clear_mask;
    logic [N_SOURCES-1:0] grant_onehot;
    logic                 grant_valid;
    addr_t                grant_addr;
    logic                 aer_req_d;
    addr_t                aer_addr_d;

    assign pending_with_events = pending_q | event_i;
    assign clear_mask = ((state_q == ST_REQ_HIGH) && aer_ack_i) ? active_src_q : '0;

    assign pending_o = pending_q;
    assign busy_o = (state_q != ST_IDLE) || (|pending_q);

`ifndef SYNTHESIS
    initial begin
        if (N_SOURCES < 1) begin
            $fatal(1, "N_SOURCES must be greater than zero");
        end
        if ((2 ** ADDR_W) < N_SOURCES) begin
            $fatal(1, "ADDR_W is too small for N_SOURCES");
        end
    end
`endif

    always_comb begin
        grant_valid  = 1'b0;
        grant_onehot = '0;
        grant_addr   = '0;

        for (int i = 0; i < N_SOURCES; i++) begin
            if (!grant_valid && pending_with_events[i]) begin
                grant_valid      = 1'b1;
                grant_onehot     = '0;
                grant_onehot[i]  = 1'b1;
                grant_addr       = addr_t'(i);
            end
        end
    end

    always_comb begin
        state_d      = state_q;
        pending_d    = (pending_q & ~clear_mask) | event_i;
        active_src_d = active_src_q;
        aer_req_d    = aer_req_o;
        aer_addr_d   = aer_addr_o;

        case (state_q)
            ST_IDLE: begin
                active_src_d = '0;
                aer_req_d    = 1'b0;

                if (grant_valid && !aer_ack_i) begin
                    state_d      = ST_REQ_HIGH;
                    active_src_d = grant_onehot;
                    aer_addr_d   = grant_addr;
                    aer_req_d    = 1'b1;
                end
            end

            ST_REQ_HIGH: begin
                aer_req_d = 1'b1;

                if (aer_ack_i) begin
                    state_d      = ST_REQ_LOW;
                    active_src_d = '0;
                    aer_req_d    = 1'b0;
                end
            end

            ST_REQ_LOW: begin
                aer_req_d = 1'b0;

                if (!aer_ack_i) begin
                    state_d = ST_IDLE;
                end
            end

            default: begin
                state_d      = ST_IDLE;
                active_src_d = '0;
                aer_req_d    = 1'b0;
                aer_addr_d   = '0;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q      <= ST_IDLE;
            pending_q    <= '0;
            active_src_q <= '0;
            aer_req_o    <= 1'b0;
            aer_addr_o   <= '0;
        end else begin
            state_q      <= state_d;
            pending_q    <= pending_d;
            active_src_q <= active_src_d;
            aer_req_o    <= aer_req_d;
            aer_addr_o   <= aer_addr_d;
        end
    end

endmodule
