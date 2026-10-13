// L stage: node fetch with native-word reuse. The cache entries are the two
// lanes' input node registers themselves, tagged with key {gsel, gx, gy}.
// For each event the four T32 nodes come from (priority order):
//   HOLD  - this lane's registers already hold the same cell (no read)
//   OTHER - the other lane's registers hold the same cell (register copy)
//   SAME  - lane 1 only: lane 0 fetches the same cell in this bundle (copy)
//   READ  - grid store read (4 nodes)
// Reused: grid-cell identification, node addresses and node fetches.
// NOT reused (deferred, would need changes inside Codex's wm_lerp): the
// horizontal top/bottom interpolation. Lane inputs are held while adv = 0.
module wm_reuse_cache
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
(
  input  logic  clk,
  input  logic  rst,
  input  logic  adv,
  input  logic  reuse_en,                       // 0 = always READ (D2 ablation)
  // D stage
  input  meta_t d0, d1,
  input  logic  d0_gsel, d1_gsel,
  // grid store read ports (addresses driven from D stage)
  output logic        rsel0, rsel1,
  output logic [4:0]  rgx0, rgy0, rgx1, rgy1,
  input  ray3_t       g00_0, g10_0, g01_0, g11_0,
  input  ray3_t       g00_1, g10_1, g01_1, g11_1,
  // invalidation when a grid buffer is released for reload
  input  logic  inv_valid,
  input  logic  inv_sel,
  // lane inputs (L stage registers)
  output logic  l0_valid, l1_valid,
  output ray3_t l0_n00, l0_n10, l0_n01, l0_n11,
  output ray3_t l1_n00, l1_n10, l1_n01, l1_n11,
  output logic [4:0] l0_ox, l0_oy, l1_ox, l1_oy,
  output meta_t l0_meta, l1_meta,
  // statistics (valid on enabled cycles)
  output logic [1:0] reads,                     // lanes that read the grid
  output logic [1:0] reuses                     // lanes served without a read
);
  logic        kv0, kv1, ks0, ks1;
  logic [4:0]  kx0, ky0, kx1, ky1;

  logic [4:0]  nx0, ny0, nx1, ny1;
  assign nx0 = d0.x[9:5]; assign ny0 = d0.y[9:5];
  assign nx1 = d1.x[9:5]; assign ny1 = d1.y[9:5];

  assign rsel0 = d0_gsel; assign rgx0 = nx0; assign rgy0 = ny0;
  assign rsel1 = d1_gsel; assign rgx1 = nx1; assign rgy1 = ny1;

  logic own0, oth0, own1, oth1, same1;
  assign own0  = reuse_en && kv0 && ks0 == d0_gsel && kx0 == nx0 && ky0 == ny0;
  assign oth0  = reuse_en && kv1 && ks1 == d0_gsel && kx1 == nx0 && ky1 == ny0;
  assign own1  = reuse_en && kv1 && ks1 == d1_gsel && kx1 == nx1 && ky1 == ny1;
  assign oth1  = reuse_en && kv0 && ks0 == d1_gsel && kx0 == nx1 && ky0 == ny1;
  assign same1 = reuse_en && d0.v && d0_gsel == d1_gsel && nx0 == nx1 && ny0 == ny1;

  // next node values for lane 0 (needed by lane 1's SAME path)
  ray3_t a00, a10, a01, a11;
  always_comb begin
    if (own0)      begin a00 = l0_n00; a10 = l0_n10; a01 = l0_n01; a11 = l0_n11; end
    else if (oth0) begin a00 = l1_n00; a10 = l1_n10; a01 = l1_n01; a11 = l1_n11; end
    else           begin a00 = g00_0;  a10 = g10_0;  a01 = g01_0;  a11 = g11_0;  end
  end

  always_comb begin
    reads  = '0;
    reuses = '0;
    if (d0.v) begin
      if (own0 || oth0) reuses = reuses + 1'b1; else reads = reads + 1'b1;
    end
    if (d1.v) begin
      if (own1 || oth1 || same1) reuses = reuses + 1'b1; else reads = reads + 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      l0_valid <= 1'b0; l1_valid <= 1'b0;
      l0_n00 <= '0; l0_n10 <= '0; l0_n01 <= '0; l0_n11 <= '0;
      l1_n00 <= '0; l1_n10 <= '0; l1_n01 <= '0; l1_n11 <= '0;
      l0_ox <= '0; l0_oy <= '0; l1_ox <= '0; l1_oy <= '0;
      l0_meta <= '0; l1_meta <= '0;
      kv0 <= 1'b0; kv1 <= 1'b0; ks0 <= 1'b0; ks1 <= 1'b0;
      kx0 <= '0; ky0 <= '0; kx1 <= '0; ky1 <= '0;
    end else begin
      if (adv) begin
        l0_valid <= d0.v; l1_valid <= d1.v;
        l0_meta  <= d0;   l1_meta  <= d1;
        l0_ox <= d0.x[4:0]; l0_oy <= d0.y[4:0];
        l1_ox <= d1.x[4:0]; l1_oy <= d1.y[4:0];
        // lane 0
        if (d0.v) begin
          l0_n00 <= a00; l0_n10 <= a10; l0_n01 <= a01; l0_n11 <= a11;
          kv0 <= 1'b1; ks0 <= d0_gsel; kx0 <= nx0; ky0 <= ny0;
        end
        // lane 1 (uses lane 0's pre-edge registers for OTHER)
        if (d1.v) begin
          if (own1) begin
            // hold
          end else if (oth1) begin
            l1_n00 <= l0_n00; l1_n10 <= l0_n10; l1_n01 <= l0_n01; l1_n11 <= l0_n11;
          end else if (same1) begin
            l1_n00 <= a00; l1_n10 <= a10; l1_n01 <= a01; l1_n11 <= a11;
          end else begin
            l1_n00 <= g00_1; l1_n10 <= g10_1; l1_n01 <= g01_1; l1_n11 <= g11_1;
          end
          kv1 <= 1'b1; ks1 <= d1_gsel; kx1 <= nx1; ky1 <= ny1;
        end
      end
      // release of a grid buffer: drop cached keys that refer to it
      // (the frame controller guarantees no D-stage event references it).
      if (inv_valid) begin
        if (ks0 == inv_sel && !(adv && d0.v)) kv0 <= 1'b0;
        if (ks1 == inv_sel && !(adv && d1.v)) kv1 <= 1'b0;
      end
    end
  end
endmodule
