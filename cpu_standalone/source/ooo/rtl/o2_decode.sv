`timescale 1ns/1ps
`include "o2_defs.vh"
// Combinational RV32I + Zmmul + Zbc + Zicsr decoder. PC-relative values that
// only depend on the instruction are precomputed here (AUIPC, JAL link,
// conditional-branch target), so execution pipes see plain operands.
module o2_decode (
    input  logic [31:0] pc,
    input  logic [31:0] insn,
    input  logic        fetch_fault,
    output logic [2:0]  fu,
    output logic [3:0]  op,       // ALU op | branch funct3 | MOP | CMT kind | {unsigned,size,store}
    output logic [4:0]  rs1, rs2, rd,
    output logic        use1, use2, wr,
    output logic        src2_imm,
    output logic [31:0] imm,      // ALU imm/value, mem offset, branch target, JALR offset
    output logic        is_jalr,
    output logic        exc,      // decode-time exception (FU_CMT/CMT_FAULT)
    output logic [3:0]  cause
);
    logic [6:0] opc; logic [2:0] f3; logic [6:0] f7;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    always_comb begin
        opc = insn[6:0]; f3 = insn[14:12]; f7 = insn[31:25];
        imm_i = {{20{insn[31]}}, insn[31:20]};
        imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
        imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
        imm_u = {insn[31:12], 12'b0};
        imm_j = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
        rs1 = insn[19:15]; rs2 = insn[24:20]; rd = insn[11:7];
        fu = `FU_ALU; op = `ALU_ADD; use1 = 1'b0; use2 = 1'b0; wr = 1'b0;
        src2_imm = 1'b1; imm = 32'b0; is_jalr = 1'b0; exc = 1'b0; cause = `EXC_ILLEGAL;
        case (opc)
            7'h37: begin wr = 1'b1; op = `ALU_PASS; imm = imm_u; end
            7'h17: begin wr = 1'b1; op = `ALU_PASS; imm = pc + imm_u; end
            7'h6f: begin
                wr = 1'b1; op = `ALU_PASS; imm = pc + 32'd4;
                if (imm_j[1]) begin exc = 1'b1; cause = `EXC_IADDR_MIS; end
            end
            7'h67: begin
                if (f3 != 3'd0) exc = 1'b1;
                fu = `FU_BR; is_jalr = 1'b1; use1 = 1'b1; wr = 1'b1; imm = imm_i; op = 4'd2;
            end
            7'h63: begin
                fu = `FU_BR; use1 = 1'b1; use2 = 1'b1; imm = pc + imm_b; op = {1'b0, f3}; src2_imm = 1'b0;
                if (f3 == 3'd2 || f3 == 3'd3) exc = 1'b1;
            end
            7'h03: begin
                fu = `FU_LD; use1 = 1'b1; wr = 1'b1; imm = imm_i; op = {1'b0, f3};
                if (f3 == 3'd3 || f3 == 3'd6 || f3 == 3'd7) exc = 1'b1;
            end
            7'h23: begin
                fu = `FU_ST; use1 = 1'b1; use2 = 1'b1; imm = imm_s; op = {1'b1, f3};
                if (f3 > 3'd2) exc = 1'b1;
            end
            7'h13: begin
                use1 = 1'b1; wr = 1'b1; imm = imm_i;
                case (f3)
                    3'd0: op = `ALU_ADD;
                    3'd1: begin op = `ALU_SLL; if (f7 != 7'd0) exc = 1'b1; end
                    3'd2: op = `ALU_SLT;
                    3'd3: op = `ALU_SLTU;
                    3'd4: op = `ALU_XOR;
                    3'd5: begin
                        op = f7[5] ? `ALU_SRA : `ALU_SRL;
                        if (f7 != 7'd0 && f7 != 7'h20) exc = 1'b1;
                    end
                    3'd6: op = `ALU_OR;
                    default: op = `ALU_AND;
                endcase
            end
            7'h33: begin
                use1 = 1'b1; use2 = 1'b1; wr = 1'b1; src2_imm = 1'b0;
                if (f7 == 7'h01) begin
                    fu = `FU_MUL; op = {1'b0, f3};
                    if (f3[2]) exc = 1'b1;             // Zmmul: no divide
                end else if (f7 == 7'h05) begin
                    fu = `FU_MUL;
                    case (f3)
                        3'd1: op = {1'b0, `MOP_CLMUL};
                        3'd2: op = {1'b0, `MOP_CLMULR};
                        3'd3: op = {1'b0, `MOP_CLMULH};
                        default: exc = 1'b1;
                    endcase
                end else if (f7 == 7'h00 || (f7 == 7'h20 && (f3 == 3'd0 || f3 == 3'd5))) begin
                    case (f3)
                        3'd0: op = f7[5] ? `ALU_SUB : `ALU_ADD;
                        3'd1: op = `ALU_SLL;
                        3'd2: op = `ALU_SLT;
                        3'd3: op = `ALU_SLTU;
                        3'd4: op = `ALU_XOR;
                        3'd5: op = f7[5] ? `ALU_SRA : `ALU_SRL;
                        3'd6: op = `ALU_OR;
                        default: op = `ALU_AND;
                    endcase
                end else exc = 1'b1;
            end
            7'h0f: begin
                fu = `FU_CMT;
                if (f3 == 3'd0) op = {1'b0, `CMT_NOP};
                else if (f3 == 3'd1) op = {1'b0, `CMT_FENCEI};
                else exc = 1'b1;
            end
            7'h73: begin
                fu = `FU_CMT;
                if (f3 == 3'd0) begin
                    if (insn == 32'h00000073) op = {1'b0, `CMT_ECALL};
                    else if (insn == 32'h00100073) op = {1'b0, `CMT_EBREAK};
                    else if (insn == 32'h30200073) op = {1'b0, `CMT_MRET};
                    else if (insn == 32'h10500073) op = {1'b0, `CMT_NOP};
                    else exc = 1'b1;
                end else if (f3 == 3'd4) exc = 1'b1;
                else begin
                    op = {1'b0, `CMT_CSR};
                    use1 = !f3[2]; wr = 1'b1;
                end
            end
            default: exc = 1'b1;
        endcase
        if (fetch_fault) begin exc = 1'b1; cause = `EXC_IACCESS; end
        if (exc) begin
            fu = `FU_CMT; op = {1'b0, `CMT_FAULT}; use1 = 1'b0; use2 = 1'b0; wr = 1'b0;
        end
        if (rd == 5'd0) wr = 1'b0;
        if (!use1) rs1 = 5'd0;
        if (!use2) rs2 = 5'd0;
    end
endmodule
