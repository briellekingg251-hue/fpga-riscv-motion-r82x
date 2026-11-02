`timescale 1ns/1ps
// Adapted from RVCoreP v0.5.3 proc.v, optimized DMEM output section.
// Copyright (c) 2020 Kise Laboratory, Tokyo Institute of Technology
// MIT License: see third_party/RVCoreP_LICENSE.txt.
// Changes: standalone RV32I interface; exact funct3 decoding; excluded ALU
// merge; invalid encodings produce zero (the core independently traps them).
// Source archive SHA256:
// de1d7c26b9b1874ae38e697f585736bc0c90035afd47a46df737f8ee0baeb016
module p1_load_align (
    input wire [31:0] data,
    input wire [1:0] offset,
    input wire [2:0] funct3,
    output wire [31:0] result
);
    wire [7:0] byte_value = data[{offset,3'b000} +: 8];
    wire [15:0] half_value = offset[1] ? data[31:16] : data[15:0];
    wire signed_load = !funct3[2];
    wire [31:0] byte_result = (funct3==0 || funct3==4) ?
        {{24{byte_value[7] & signed_load}},byte_value} : 32'b0;
    wire [31:0] half_result = (funct3==1 || funct3==5) ?
        {{16{half_value[15] & signed_load}},half_value} : 32'b0;
    wire [31:0] word_result = funct3==2 ? data : 32'b0;
    // Mutually exclusive terms: no priority chain between supported sizes.
    assign result = byte_result ^ half_result ^ word_result;
endmodule
