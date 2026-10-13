// Synchronous valid/ready FIFO. Used as the shared native-word input FIFO
// (W = $bits(nword_t), DEPTH = 128 default) and, via wm_skid_buffer, as the
// mapper output buffer. Never drops: in_ready = !full.
// Active-high synchronous reset (matches the Codex numeric RTL).
module wm_input_fifo #(
  parameter integer W     = 52,
  parameter integer DEPTH = 128,
  parameter integer CNT_W = $clog2(DEPTH + 1)
) (
  input  logic             clk,
  input  logic             rst,
  input  logic             in_valid,
  output logic             in_ready,
  input  logic [W-1:0]     in_data,
  output logic             out_valid,
  input  logic             out_ready,
  output logic [W-1:0]     out_data,
  output logic [CNT_W-1:0] occupancy,
  output logic [CNT_W-1:0] max_occupancy,
  output logic             full,
  output logic             empty
);
  localparam integer PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

  logic [W-1:0]     mem [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr, rd_ptr;
  logic [CNT_W-1:0] count;
  logic             push, pop;

  assign full      = (count == CNT_W'(DEPTH));
  assign empty     = (count == '0);
  assign in_ready  = !full;
  assign out_valid = !empty;
  assign out_data  = mem[rd_ptr];
  assign occupancy = count;
  assign push      = in_valid && in_ready;
  assign pop       = out_valid && out_ready;

  function automatic logic [PTR_W-1:0] incr(input logic [PTR_W-1:0] p);
    incr = (p == PTR_W'(DEPTH - 1)) ? '0 : p + 1'b1;
  endfunction

  always_ff @(posedge clk) begin
    if (rst) begin
      wr_ptr        <= '0;
      rd_ptr        <= '0;
      count         <= '0;
      max_occupancy <= '0;
    end else begin
      if (push) begin
        mem[wr_ptr] <= in_data;
        wr_ptr      <= incr(wr_ptr);
      end
      if (pop) rd_ptr <= incr(rd_ptr);
      case ({push, pop})
        2'b10:   count <= count + 1'b1;
        2'b01:   count <= count - 1'b1;
        default: count <= count;
      endcase
      if (count > max_occupancy) max_occupancy <= count;
    end
  end
endmodule
