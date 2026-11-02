`timescale 1ns/1ps
// Small distributed-RAM bit array: one synchronous write port, NR
// asynchronous read ports (one LUT-RAM copy per read port).
module o2_bitram #(
    parameter integer DEPTH = 256,
    parameter integer AW = 8,
    parameter integer NR = 2
) (
    input  logic          clk,
    input  logic          we,
    input  logic [AW-1:0] wa,
    input  logic          wd,
    input  logic [NR*AW-1:0] ra,
    output logic [NR-1:0] rd
);
    genvar r;
    generate for (r = 0; r < NR; r++) begin : c
        (* syn_ramstyle = "lut_ram" *) logic m [0:DEPTH-1];
        always_ff @(posedge clk) if (we) m[wa] <= wd;
        assign rd[r] = m[ra[AW*r +: AW]];
`ifndef SYNTHESIS
        initial for (int i = 0; i < DEPTH; i++) m[i] = 1'b0;
`endif
    end endgenerate
endmodule
