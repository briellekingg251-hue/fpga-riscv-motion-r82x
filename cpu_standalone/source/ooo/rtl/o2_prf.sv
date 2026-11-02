`timescale 1ns/1ps
// O2 physical register file: 64 x 32, NW write ports, NR read ports.
// One LUT-RAM bank per (write port, read port) pair. A physical register is
// only ever written through the write port of its producer's pipe, so the
// bank holding it is known at rename (from the producer table) and travels
// with the operand as a 2-bit code: 0 = reads as zero (x0 or never
// written), 1..3 = bank of write port 0..2. No live-value table is needed.
module o2_prf #(
    parameter integer NW = 3,
    parameter integer NR = 7
) (
    input  logic            clk, rst,
    input  logic [NW-1:0]   we,
    input  logic [NW*6-1:0] waddr,
    input  logic [NW*32-1:0] wdata,
    input  logic [NW*NR*6-1:0] raddr_b,     // bank (w, r) read address, [(w*NR + r)*6 +: 6]
    input  logic [NR*2-1:0] rsel,           // per read port bank code
    output logic [NR*32-1:0] rdata
);
    genvar w, r;
    wire [31:0] q_all [0:NW*NR-1];
    generate
        for (w = 0; w < NW; w++) begin : g_w
            for (r = 0; r < NR; r++) begin : g_r
                (* syn_ramstyle = "lut_ram" *) logic [31:0] bank [0:63];
                always_ff @(posedge clk) if (we[w]) bank[waddr[6*w +: 6]] <= wdata[32*w +: 32];
                assign q_all[w*NR + r] = bank[raddr_b[6*(w*NR + r) +: 6]];
`ifndef SYNTHESIS
                initial for (int i = 0; i < 64; i++) bank[i] = 32'b0;
`endif
            end
        end
        // NW == 3
        for (r = 0; r < NR; r++) begin : g_rd
            logic [31:0] v;
            always_comb begin
                case (rsel[2*r +: 2])
                    2'd1: v = q_all[0*NR + r];
                    2'd2: v = q_all[1*NR + r];
                    2'd3: v = q_all[2*NR + r];
                    default: v = 32'b0;
                endcase
            end
            assign rdata[32*r +: 32] = v;
        end
    endgenerate
endmodule
