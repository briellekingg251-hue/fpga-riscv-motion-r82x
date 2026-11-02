// O2 out-of-order core: shared constants.
`ifndef O2_DEFS_VH
`define O2_DEFS_VH

// Functional unit classes
`define FU_ALU    3'd0
`define FU_BR     3'd1   // conditional branch or JALR (pipe 0, checkpointed)
`define FU_LD     3'd2
`define FU_ST     3'd3
`define FU_MUL    3'd4   // MUL/MULH*/CLMUL* (pipe 1, long latency)
`define FU_CMT    3'd5   // executed at commit: CSR, ECALL, EBREAK, MRET, WFI, FENCE, FENCE.I, faults

// ALU operations
`define ALU_ADD   4'd0
`define ALU_SUB   4'd1
`define ALU_SLL   4'd2
`define ALU_SLT   4'd3
`define ALU_SLTU  4'd4
`define ALU_XOR   4'd5
`define ALU_SRL   4'd6
`define ALU_SRA   4'd7
`define ALU_OR    4'd8
`define ALU_AND   4'd9
`define ALU_PASS  4'd10  // result = operand B (LUI, AUIPC, JAL link precomputed)

// Long-latency ops (FU_MUL): funct3 of MUL group, or CLMUL kinds
`define MOP_MUL    3'd0
`define MOP_MULH   3'd1
`define MOP_MULHSU 3'd2
`define MOP_MULHU  3'd3
`define MOP_CLMUL  3'd4
`define MOP_CLMULR 3'd5
`define MOP_CLMULH 3'd6

// Commit-executed op kinds (FU_CMT)
`define CMT_CSR    3'd0
`define CMT_ECALL  3'd1
`define CMT_EBREAK 3'd2
`define CMT_MRET   3'd3
`define CMT_NOP    3'd4   // WFI, FENCE
`define CMT_FENCEI 3'd5
`define CMT_FAULT  3'd6   // decode-time exception (illegal / fetch fault)

// Exception causes
`define EXC_IADDR_MIS  4'd0
`define EXC_IACCESS    4'd1
`define EXC_ILLEGAL    4'd2
`define EXC_BREAK      4'd3
`define EXC_LADDR_MIS  4'd4
`define EXC_LACCESS    4'd5
`define EXC_SADDR_MIS  4'd6
`define EXC_SACCESS    4'd7
`define EXC_ECALL_M    4'd11

`endif
