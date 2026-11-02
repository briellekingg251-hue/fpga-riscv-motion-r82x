`timescale 1ns/1ps
`include "o2_defs.vh"
// O2 reorder buffer, commit, machine-mode CSRs and traps.
// 32 entries; dispatch writes tail/tail+1 (one even, one odd bank), commit
// reads head/head+1. Up to two instructions commit per cycle; at most one
// branch. CSR, trap-class work and FENCE.I only at the head.
//
// Dispatch entry layout (128 bits, built by o2_rename):
//   [127:96] pc   [95:64] insn  [63:59] rd  [58] wr  [57:52] pdst  [51:46] pold
//   [45:43] fu    [42:39] op    [38:35] cause  [34:32] sqidx  [31:28] biq
//   [27:25] brtag [24:19] psrc1 (CSR operand)
module o2_rob #(
    parameter [31:0] RESET_PC = 32'h80000000
) (
    input  logic        clk, rst,
    // dispatch
    input  logic [1:0]  dv,
    input  logic [127:0] e0, e1,
    output logic [5:0]  tail,           // {wrap, idx}
    output logic [5:0]  count,
    output logic [1:0]  room,           // registered: [0] >= 1 free, [1] >= 2 free (conservative)
    output logic        empty,
    output logic [4:0]  head_idx,
    // completions
    input  logic        c0_v, input logic [4:0] c0_rob,            // pipe 0 ALU
    input  logic        c5_v, input logic [4:0] c5_rob, input logic c5_exc, input logic [31:0] c5_tval,
    input  logic        c5_taken,                                   // pipe 0 branch (resolution stage)
    input  logic        c1_v, input logic [4:0] c1_rob,
    input  logic        c2_v, input logic [4:0] c2_rob,
    input  logic        c3_v, input logic [4:0] c3_rob, input logic c3_exc, input logic [3:0] c3_cause,
    input  logic [31:0] c3_tval, input logic c3_replay,                // store (replay: MMIO, re-run head-only)
    input  logic        c4_v, input logic [4:0] c4_rob, input logic c4_exc, input logic [3:0] c4_cause,
    input  logic [31:0] c4_tval, input logic c4_replay, input logic c4_replay_io,
    // branch kill: tail <- branch rob + 1
    input  logic        br_kill, input logic [4:0] br_kill_rob,
    // commit outputs to rename
    output logic [1:0]  cm_wr,
    output logic [4:0]  cm_rd0, cm_rd1,
    output logic [5:0]  cm_pdst0, cm_pdst1, cm_pold0, cm_pold1,
    output logic [1:0]  sq_commit,
    // commit outputs to front end
    output logic        cmt_br_valid, cmt_is_cbr, cmt_taken,
    output logic [31:0] cmt_pc,
    output logic [3:0]  cmt_biq,
    // flush / redirect
    output logic        flush,
    output logic [31:0] flush_pc,
    output logic        replay_set, output logic [31:0] replay_pc,
    output logic        md_set,             // the replay was a memory-order violation
    input  logic [31:0] md_viol,            // ROB entries of loads that read stale data (replay)
    output logic        fetch_stop,
    // CSR operand read and result write (via the load write port)
    output logic [5:0]  csr_rs1_preg,
    output logic [5:0]  csr_rs1_preg_n,     // value csr_rs1_preg takes next cycle
    output logic [1:0]  csr_rs1_bank,       // register-file bank code of the operand
    output logic        csr_rd_a,           // csr_rs1_preg is loaded into the read-address registers
    output logic        csr_rd_b,           // the read port returns the CSR operand
    input  logic [31:0] csr_rs1_value,
    output logic        csr_wb_v, output logic [5:0] csr_wb_pd, output logic [31:0] csr_wb_data,
    // interrupts / system
    input  logic        irq_software, irq_timer, irq_external,
    input  logic        sq_empty, slow_busy,
    output logic        dc_clean_req, input logic dc_clean_done,
    output logic        ic_inv, input logic ic_busy,
    // trace (registered one cycle after commit)
    output logic [1:0]  tr_v,
    output logic [31:0] tr_pc0, tr_pc1, tr_insn0, tr_insn1,
    output logic        tr_wr0, tr_wr1,
    output logic [4:0]  tr_rd0, tr_rd1,
    output logic [5:0]  tr_pd0, tr_pd1,
    output logic        tr_trap, tr_irq,
    output logic [31:0] tr_cause, tr_epc,
    output logic [31:0] tr_csr_old,
    output logic [63:0] minstret_o, mcycle_o
);
    // ---------------------------------------------------------- storage
    (* syn_ramstyle = "lut_ram" *) logic [61:0] pa0 [0:15];  // {pc[31:2], insn}
    (* syn_ramstyle = "lut_ram" *) logic [61:0] pa1 [0:15];
    (* syn_ramstyle = "lut_ram" *) logic [46:0] pb0 [0:15];  // e[63:17]
    (* syn_ramstyle = "lut_ram" *) logic [46:0] pb1 [0:15];
    logic [31:0] done, exc, rpl, rpl_io, rpl_md, tkn;
    // the oldest reported exception (cause/tval); exc[] marks the entries
    logic        xv; logic [4:0] xrob; logic [3:0] xcause; logic [31:0] xtval;
    logic        e0_v, e3_v, e3_exc, e4_v, e4_exc, e4_rio; logic [4:0] e0_rob, e3_rob, e4_rob;
    logic [3:0]  e3_cause, e4_cause; logic [31:0] e0_tval, e3_tval, e4_tval;
    logic [5:0]  head;

    wire [5:0] t0 = tail, t1 = tail + 6'd1;
    function automatic [61:0] fa(input [127:0] e); fa = {e[127:98], e[95:64]}; endfunction
    function automatic [46:0] fb(input [127:0] e); fb = e[63:17]; endfunction
    // exactly one of t0/t1 is even: each bank has a single write port
    wire w0_e = !t0[0];                                   // slot 0 goes to the even bank
    wire we_even = (dv[0] && w0_e) || (dv[1] && !w0_e);
    wire we_odd  = (dv[0] && !w0_e) || (dv[1] && w0_e);
    wire [3:0] wa_even = w0_e ? t0[4:1] : t1[4:1];
    wire [3:0] wa_odd  = w0_e ? t1[4:1] : t0[4:1];
    wire [127:0] wd_even = w0_e ? e0 : e1;
    wire [127:0] wd_odd  = w0_e ? e1 : e0;
    always_ff @(posedge clk) begin
        if (we_even) begin pa0[wa_even] <= fa(wd_even); pb0[wa_even] <= fb(wd_even); end
        if (we_odd)  begin pa1[wa_odd] <= fa(wd_odd);   pb1[wa_odd] <= fb(wd_odd); end
    end
    wire [5:0] h0 = head, h1 = head + 6'd1;
    wire [61:0] ra0 = h0[0] ? pa1[h0[4:1]] : pa0[h0[4:1]];
    wire [46:0] rb0 = h0[0] ? pb1[h0[4:1]] : pb0[h0[4:1]];
    wire [61:0] ra1 = h1[0] ? pa1[h1[4:1]] : pa0[h1[4:1]];
    wire [46:0] rb1 = h1[0] ? pb1[h1[4:1]] : pb0[h1[4:1]];
    // rb layout (e[63:17] shifted down by 17): rd[46:42] wr[41] pd[40:35] po[34:29]
    // fu[28:26] op[25:22] ca[21:18] sqi[17:15] biq[14:11] tag[10:8] ps1[7:2] ps1 bank[1:0]
    wire [31:0] pc0 = {ra0[61:32], 2'b00}, insn0 = ra0[31:0];
    wire [31:0] pc1 = {ra1[61:32], 2'b00}, insn1 = ra1[31:0];
    wire [4:0] rd0 = rb0[46:42], rd1 = rb1[46:42];
    wire wr0 = rb0[41], wr1 = rb1[41];
    wire [5:0] pd0 = rb0[40:35], po0 = rb0[34:29], pd1 = rb1[40:35], po1 = rb1[34:29];
    wire [2:0] fu0 = rb0[28:26], fu1 = rb1[28:26];
    wire [3:0] op0 = rb0[25:22];
    wire [3:0] dca0 = rb0[21:18];
    wire [3:0] biq0 = rb0[14:11], biq1 = rb1[14:11];
    wire st0 = fu0 == `FU_ST, st1 = fu1 == `FU_ST;
    wire br0 = fu0 == `FU_BR, br1 = fu1 == `FU_BR;
    wire cbr0 = br0 && insn0[6:0] == 7'h63, cbr1 = br1 && insn1[6:0] == 7'h63;
    logic [5:0] csr_preg_q; logic [1:0] csr_bank_q;
    assign csr_rs1_preg = csr_preg_q;
    assign csr_rs1_preg_n = rb0[7:2];
    assign csr_rs1_bank = csr_bank_q2;
    assign csr_rd_a = csr_arm1;
    assign csr_rd_b = csr_arm2;

    function automatic [4:0] age(input [4:0] r); age = r - head[4:0]; endfunction
    // a strictly older than b (both in the window): same side of head -> lower index
    function automatic logic older(input [4:0] a, input [4:0] b);
        logic ah, bh;
        ah = a >= head[4:0]; bh = b >= head[4:0];
        older = (ah == bh) ? (a < b) : ah;
    endfunction
    assign count = tail - head;
    // commits during this cycle are seen one cycle late (conservative)
    wire [5:0] cnt_n = tail + {5'b0, dv[0]} + {5'b0, dv[1]} - head;
    always_ff @(posedge clk) begin
        if (rst) room <= 2'b11;
        else room <= {cnt_n <= 6'd30, cnt_n <= 6'd31};
    end
    // registered; dispatches this cycle count, commits are seen a cycle late
    always_ff @(posedge clk) begin
        if (rst) empty <= 1'b1;
        else empty <= cnt_n == 6'd0 && !flush_q;
    end
    assign head_idx = head[4:0];

    // ---------------------------------------------------------- CSRs
    logic [31:0] mstatus, mie, mtvec, mscratch, mepc, mcause, mtval;
    logic [63:0] mcycle, minstret;
    wire [31:0] mip = {20'b0, irq_external, 3'b0, irq_timer, 3'b0, irq_software, 3'b0};
    assign minstret_o = minstret; assign mcycle_o = mcycle;
    function automatic logic csr_known(input [11:0] a);
        case (a)
            12'h300, 12'h301, 12'h304, 12'h305, 12'h340, 12'h341, 12'h342, 12'h343, 12'h344,
            12'hb00, 12'hb80, 12'hb02, 12'hb82, 12'hc00, 12'hc80, 12'hc02, 12'hc82,
            12'hf11, 12'hf12, 12'hf13, 12'hf14: csr_known = 1'b1;
            default: csr_known = 1'b0;
        endcase
    endfunction
    logic [31:0] csr_old;
    always_comb begin
        case (insn0[31:20])
            12'h300: csr_old = mstatus;
            12'h301: csr_old = 32'h40000100; // RV32I; Zmmul does not implement full M.
            12'h304: csr_old = mie;
            12'h305: csr_old = mtvec;
            12'h340: csr_old = mscratch;
            12'h341: csr_old = mepc;
            12'h342: csr_old = mcause;
            12'h343: csr_old = mtval;
            12'h344: csr_old = mip;
            12'hb00, 12'hc00: csr_old = mcycle[31:0];
            12'hb80, 12'hc80: csr_old = mcycle[63:32];
            12'hb02, 12'hc02: csr_old = minstret[31:0];
            12'hb82, 12'hc82: csr_old = minstret[63:32];
            default: csr_old = 32'b0;
        endcase
    end
    wire [2:0] cf3 = insn0[14:12];
    // The rs1 operand read is two registered steps: the physical register
    // number (csr_arm1), then the PRF value (csr_arm); the CSR op executes
    // when both have been taken for the op at the head.
    logic [31:0] csr_rs1_q; logic csr_arm1, csr_arm2, csr_arm; logic [1:0] csr_bank_q2;
    wire csr_wr_en = (cf3[1:0] == 2'b01) || insn0[19:15] != 5'd0;
    wire csr_illegal = !csr_known(insn0[31:20]) || (csr_wr_en && insn0[31:30] == 2'b11);
    // A CSR op waits at the head while its operand is read (csr_arm), and no
    // CSR changes meanwhile (an interrupt would preempt it), so its old value,
    // address decode and legality are taken from registers (counters may be a
    // cycle or two old).
    logic [31:0] csr_old_q; logic csr_ill_q, csr_wen_q; logic [2:0] csr_f3_q; logic [4:0] csr_zimm_q;
    logic [6:0] csr_wsel_q;     // mstatus, mie, mtvec, mscratch, mepc, mcause, mtval
    logic [3:0] csr_counter_wsel_q; // mcycle, mcycleh, minstret, minstreth
    logic minstret_write_q;
    always_ff @(posedge clk) begin
        csr_old_q <= csr_old; csr_ill_q <= csr_illegal; csr_wen_q <= csr_wr_en;
        csr_f3_q <= cf3; csr_zimm_q <= insn0[19:15];
        csr_wsel_q <= {insn0[31:20] == 12'h343, insn0[31:20] == 12'h342, insn0[31:20] == 12'h341,
                       insn0[31:20] == 12'h340, insn0[31:20] == 12'h305, insn0[31:20] == 12'h304,
                       insn0[31:20] == 12'h300};
        csr_counter_wsel_q <= {insn0[31:20] == 12'hb82, insn0[31:20] == 12'hb02,
                               insn0[31:20] == 12'hb80, insn0[31:20] == 12'hb00};
    end
    wire [31:0] csr_src = csr_f3_q[2] ? {27'b0, csr_zimm_q} : csr_rs1_q;
    wire [31:0] csr_new = (csr_f3_q[1:0] == 2'b01) ? csr_src :
                          (csr_f3_q[1:0] == 2'b10) ? (csr_old_q | csr_src) : (csr_old_q & ~csr_src);

    // ---------------------------------------------------------- commit decision
    localparam [2:0] F_IDLE = 3'd0, F_SQ = 3'd1, F_DC = 3'd2, F_IW0 = 3'd3, F_IP = 3'd4, F_IW1 = 3'd5;
    logic [2:0] fstate;
    logic flush_q; logic [31:0] flush_pc_q;
    // redirects (trap, interrupt, mret, replay) take effect one cycle after
    // the commit decision; commit is held meanwhile
    logic rd_pend, rd_trap, rd_irq, rd_mret, rd_rpl, rd_rset, rd_md;
    logic [31:0] rd_pc, rd_insn, rd_icause, fi_pc; logic [3:0] rd_dca; logic [2:0] rd_tk;
    logic [31:0] rd_cause, rd_tval;
    wire v0 = count >= 6'd1, v1 = count >= 6'd2;
    wire irq_pend = mstatus[3] && |(mie & mip & 32'h888);
    logic [31:0] irq_cause;
    always_comb begin
        if (mie[11] && mip[11]) irq_cause = 32'h8000000b;
        else if (mie[3] && mip[3]) irq_cause = 32'h80000003;
        else irq_cause = 32'h80000007;
    end
    wire h0_done = done[h0[4:0]], h0_exc = exc[h0[4:0]], h0_rpl = rpl[h0[4:0]];
    // A finished load/store at the head commits (or traps) before an interrupt
    // is taken: an MMIO access has already happened and must not be repeated.
    // A slow-path fault reaches done/exc one cycle after its completion
    // (e4_v), so that cycle is covered too. Replays have not accessed anything.
    wire h0_mem_done = h0_done && !h0_rpl && (st0 || fu0 == `FU_LD);
    wire irq_ok = !slow_busy && !h0_mem_done && !e4_v;
    wire csr_at_head = !flush_q && !br_kill && v0 && fstate == F_IDLE && !rd_pend && h0_done && !h0_exc &&
                       !h0_rpl && fu0 == `FU_CMT && op0[2:0] == `CMT_CSR;
    logic do_c0, do_c1, do_trap, do_irq, do_replay, do_mret, do_csr, start_fencei;
    // cause / tval are formed in redirect phase 2 from the kind recorded here
    logic [2:0] trap_kind;      // 0 reported exception, 1 illegal CSR, 2 ecall, 3 ebreak, 4 decode fault
    always_comb begin
        do_c0 = 1'b0; do_c1 = 1'b0; do_trap = 1'b0; do_irq = 1'b0; do_replay = 1'b0;
        do_mret = 1'b0; do_csr = 1'b0; start_fencei = 1'b0;
        trap_kind = h0_exc ? 3'd0 : (op0[2:0] == `CMT_CSR) ? 3'd1 : (op0[2:0] == `CMT_ECALL) ? 3'd2 :
                    (op0[2:0] == `CMT_EBREAK) ? 3'd3 : 3'd4;
        if (!flush_q && !br_kill && v0 && fstate == F_IDLE && !rd_pend) begin
            if (irq_pend && irq_ok) begin
                do_irq = 1'b1;
            end else if (h0_done) begin
                if (h0_exc) begin
                    do_trap = 1'b1;
                end else if (h0_rpl) begin
                    do_replay = 1'b1;
                end else if (fu0 == `FU_CMT) begin
                    case (op0[2:0])
                        `CMT_CSR: if (csr_arm) begin
                            if (csr_ill_q) do_trap = 1'b1;
                            else begin do_csr = 1'b1; do_c0 = 1'b1; end
                        end
                        `CMT_ECALL, `CMT_EBREAK: do_trap = 1'b1;
                        `CMT_MRET: begin do_mret = 1'b1; do_c0 = 1'b1; end
                        `CMT_NOP: do_c0 = 1'b1;
                        `CMT_FENCEI: start_fencei = 1'b1;
                        default: do_trap = 1'b1;           // decode-time fault
                    endcase
                end else begin
                    do_c0 = 1'b1;
                    if (v1 && done[h1[4:0]] && !exc[h1[4:0]] && !rpl[h1[4:0]] && fu1 != `FU_CMT && !(br0 && br1))
                        do_c1 = 1'b1;
                end
            end
        end
        if (fstate == F_IW1 && !ic_busy) do_c0 = 1'b1;
    end
    always_comb begin
        cm_wr = {do_c1 && wr1, do_c0 && wr0};
        cm_rd0 = rd0; cm_rd1 = rd1; cm_pdst0 = pd0; cm_pdst1 = pd1; cm_pold0 = po0; cm_pold1 = po1;
        sq_commit = {1'b0, do_c0 && st0} + {1'b0, do_c1 && st1};
        cmt_br_valid = (do_c0 && br0) || (do_c1 && br1);
        cmt_is_cbr = (do_c0 && br0) ? cbr0 : cbr1;
        cmt_taken = (do_c0 && br0) ? tkn[h0[4:0]] : tkn[h1[4:0]];
        cmt_pc = (do_c0 && br0) ? pc0 : pc1;
        cmt_biq = (do_c0 && br0) ? biq0 : biq1;
    end
    assign flush = flush_q;
    assign flush_pc = flush_pc_q;
    assign fetch_stop = fstate != F_IDLE;
    assign dc_clean_req = fstate == F_DC;
    assign ic_inv = fstate == F_IP;
    // branch-kill tail: branch index + 1, with the wrap bit relative to head
    wire [4:0] kill_off = br_kill_rob - head[4:0];
    wire [5:0] kill_tail = head + {1'b0, kill_off} + 6'd1;

    // ---------------------------------------------------------- sequential
    always_ff @(posedge clk) begin
        if (rst) begin
            head <= 6'd0; tail <= 6'd0; done <= 32'b0; exc <= 32'b0; rpl <= 32'b0; tkn <= 32'b0; xv <= 1'b0;
            flush_q <= 1'b0; flush_pc_q <= RESET_PC; fstate <= F_IDLE;
            mstatus <= 32'h1800; mie <= 32'b0; mtvec <= 32'b0; mscratch <= 32'b0; mepc <= 32'b0;
            mcause <= 32'b0; mtval <= 32'b0; mcycle <= 64'b0; minstret <= 64'b0;
            minstret_write_q <= 1'b0;
            replay_set <= 1'b0; md_set <= 1'b0; csr_wb_v <= 1'b0; replay_pc <= 32'b0; csr_arm <= 1'b0; csr_arm1 <= 1'b0; csr_arm2 <= 1'b0;
            rd_pend <= 1'b0; e0_v <= 1'b0; e3_v <= 1'b0; e4_v <= 1'b0;
            tr_v <= 2'b0; tr_trap <= 1'b0; tr_irq <= 1'b0;
        end else begin
            mcycle <= mcycle + 64'd1;
            csr_preg_q <= rb0[7:2]; csr_bank_q <= rb0[1:0]; csr_bank_q2 <= csr_bank_q;
            csr_rs1_q <= csr_rs1_value;
            // armed while the same CSR op stays at the head
            csr_arm1 <= csr_at_head && !do_c0 && !do_trap && !do_irq;
            csr_arm2 <= csr_arm1 && csr_at_head && !do_c0 && !do_trap && !do_irq;
            csr_arm <= csr_arm2 && csr_at_head && !do_c0 && !do_trap && !do_irq;
            flush_q <= 1'b0; replay_set <= 1'b0; md_set <= 1'b0; csr_wb_v <= 1'b0;
            tr_v <= 2'b0; tr_trap <= 1'b0; tr_irq <= 1'b0;
            // completions
            // completions without exception/replay mark done now
            if (c0_v) done[c0_rob] <= 1'b1;
            if (c5_v) tkn[c5_rob] <= c5_taken;
            if (c5_v && !c5_exc) done[c5_rob] <= 1'b1;
            if (c1_v) done[c1_rob] <= 1'b1;
            if (c2_v) done[c2_rob] <= 1'b1;
            if (c3_v && !c3_exc && !c3_replay) done[c3_rob] <= 1'b1;
            if (c4_v && !c4_exc && !c4_replay) done[c4_rob] <= 1'b1;
            // exception / replay completions: registered record, applied
            // (done + exc/rpl + oldest-exception update) one cycle later
            e0_v <= c5_v && c5_exc && !flush_q; e0_rob <= c5_rob; e0_tval <= c5_tval;
            e3_v <= c3_v && (c3_exc || c3_replay) && !flush_q; e3_rob <= c3_rob; e3_exc <= c3_exc;
            e3_cause <= c3_cause; e3_tval <= c3_tval;
            e4_v <= c4_v && (c4_exc || c4_replay) && !flush_q; e4_rob <= c4_rob; e4_exc <= c4_exc;
            e4_cause <= c4_cause; e4_tval <= c4_tval; e4_rio <= c4_replay_io;
            begin
                logic a0, a3, a4;
                a0 = e0_v && !flush_q && !(br_kill && older(br_kill_rob, e0_rob));
                a3 = e3_v && !flush_q && !(br_kill && older(br_kill_rob, e3_rob));
                a4 = e4_v && !flush_q && !(br_kill && older(br_kill_rob, e4_rob));
                if (a0) begin done[e0_rob] <= 1'b1; exc[e0_rob] <= 1'b1; end
                if (a3) begin done[e3_rob] <= 1'b1;
                    if (e3_exc) exc[e3_rob] <= 1'b1;
                    else begin rpl[e3_rob] <= 1'b1; rpl_io[e3_rob] <= 1'b1; end end
                if (a4) begin done[e4_rob] <= 1'b1;
                    if (e4_exc) exc[e4_rob] <= 1'b1;
                    else begin rpl[e4_rob] <= 1'b1; rpl_io[e4_rob] <= e4_rio; end end
                // oldest exception record: pairwise order of the candidates
                if (flush_q) xv <= 1'b0;
                else begin
                    logic xk, a3x, a4x, w0, w3, w4, o0x, o3x, o4x, o03, o04, o34;
                    xk = xv && !(br_kill && older(br_kill_rob, xrob));
                    a3x = a3 && e3_exc;
                    a4x = a4 && e4_exc;
                    o0x = older(e0_rob, xrob); o3x = older(e3_rob, xrob); o4x = older(e4_rob, xrob);
                    o03 = older(e0_rob, e3_rob); o04 = older(e0_rob, e4_rob); o34 = older(e3_rob, e4_rob);
                    w0 = a0 && (!xk || o0x) && (!a3x || o03) && (!a4x || o04);
                    w3 = a3x && (!xk || o3x) && (!a0 || !o03) && (!a4x || o34);
                    w4 = a4x && (!xk || o4x) && (!a0 || !o04) && (!a3x || !o34);
                    xv <= xk || a0 || a3x || a4x;
                    if (w0) begin xrob <= e0_rob; xcause <= 4'd0; xtval <= e0_tval; end
                    else if (w3) begin xrob <= e3_rob; xcause <= e3_cause; xtval <= e3_tval; end
                    else if (w4) begin xrob <= e4_rob; xcause <= e4_cause; xtval <= e4_tval; end
                end
            end
            // dispatch: commit-executed ops (and decode faults) are complete at dispatch
            // memory-order violations (registered by the LSU): replay
            for (int i = 0; i < 32; i++) if (md_viol[i]) begin rpl[i] <= 1'b1; rpl_md[i] <= 1'b1; rpl_io[i] <= 1'b0; end
            if (dv[0]) begin done[t0[4:0]] <= e0[45:43] == `FU_CMT; exc[t0[4:0]] <= 1'b0; rpl[t0[4:0]] <= 1'b0; rpl_md[t0[4:0]] <= 1'b0; end
            if (dv[1]) begin done[t1[4:0]] <= e1[45:43] == `FU_CMT; exc[t1[4:0]] <= 1'b0; rpl[t1[4:0]] <= 1'b0; rpl_md[t1[4:0]] <= 1'b0; end
            // tail
            if (br_kill) tail <= kill_tail;
            else tail <= tail + {5'b0, dv[0]} + {5'b0, dv[1]};
            // commit
            head <= head + {5'b0, do_c0} + {5'b0, do_c1};
            // counted from the registered commit vector (one cycle behind)
            // Explicit counter writes override the writing instruction's
            // implicit increment, which arrives through tr_v one cycle later.
            minstret <= minstret + (minstret_write_q ? 64'd0 :
                                    ({63'b0, tr_v[0]} + {63'b0, tr_v[1]}));
            minstret_write_q <= do_csr && csr_wen_q && |csr_counter_wsel_q[3:2];
            tr_v <= {do_c1, do_c0};
            tr_pc0 <= pc0; tr_pc1 <= pc1; tr_insn0 <= insn0; tr_insn1 <= insn1;
            tr_wr0 <= wr0; tr_wr1 <= wr1; tr_rd0 <= rd0; tr_rd1 <= rd1; tr_pd0 <= pd0; tr_pd1 <= pd1;
            tr_csr_old <= csr_old_q;
            // CSR execution
            if (do_csr) begin
                csr_wb_v <= wr0; csr_wb_pd <= pd0; csr_wb_data <= csr_old_q;
                if (csr_wen_q) begin
                    if (csr_wsel_q[0]) mstatus <= (csr_new & 32'h88) | 32'h1800; // M-only: MPP is WARL 3.
                    if (csr_wsel_q[1]) mie <= csr_new & 32'h888;
                    if (csr_wsel_q[2]) mtvec <= {csr_new[31:2], 2'b00};
                    if (csr_wsel_q[3]) mscratch <= csr_new;
                    if (csr_wsel_q[4]) mepc <= {csr_new[31:2], 2'b00};
                    if (csr_wsel_q[5]) mcause <= csr_new;
                    if (csr_wsel_q[6]) mtval <= csr_new;
                    // RV32 accesses replace one half and preserve the other.
                    // These assignments take precedence over natural counting.
                    if (csr_counter_wsel_q[0]) mcycle <= {mcycle[63:32], csr_new};
                    if (csr_counter_wsel_q[1]) mcycle <= {csr_new, mcycle[31:0]};
                    if (csr_counter_wsel_q[2]) minstret <= {minstret[63:32], csr_new};
                    if (csr_counter_wsel_q[3]) minstret <= {csr_new, minstret[31:0]};
                end
            end
            // redirect, phase 1: record (commit is held while rd_pend); the
            // head fields are captured every cycle, cause / tval formed later
            if (!rd_pend) begin
                rd_pend <= do_trap || do_irq || do_mret || do_replay;
                rd_trap <= do_trap || do_irq; rd_irq <= do_irq; rd_mret <= do_mret; rd_rpl <= do_replay;
                rd_rset <= (fu0 == `FU_LD || st0) && rpl_io[h0[4:0]];   // MMIO / failed line: re-run head-only
                rd_md <= rpl_md[h0[4:0]];
                rd_pc <= pc0; rd_insn <= insn0; rd_dca <= dca0; rd_icause <= irq_cause; rd_tk <= trap_kind;
            end
            // redirect, phase 2: CSR side effects and flush
            if (rd_pend) begin
                logic [31:0] cz, tz;
                case (rd_tk)
                    3'd0: begin cz = {28'b0, xcause}; tz = xtval; end
                    3'd1: begin cz = 32'd2; tz = rd_insn; end
                    3'd2: begin cz = 32'd11; tz = 32'b0; end
                    3'd3: begin cz = 32'd3; tz = rd_pc; end
                    default: begin
                        cz = {28'b0, rd_dca};
                        tz = (rd_dca == `EXC_IACCESS) ? rd_pc :
                             (rd_dca == `EXC_IADDR_MIS) ? rd_pc + {{11{rd_insn[31]}}, rd_insn[31], rd_insn[19:12], rd_insn[20], rd_insn[30:21], 1'b0} :
                             rd_insn;
                    end
                endcase
                if (rd_irq) begin cz = rd_icause; tz = 32'b0; end
                rd_cause <= cz; rd_tval <= tz;
                rd_pend <= 1'b0;
                flush_q <= 1'b1;
                if (rd_trap) begin
                    mepc <= rd_pc; mcause <= cz; mtval <= tz;
                    mstatus <= (mstatus & ~32'h88) | {24'b0, mstatus[3], 7'b0} | 32'h1800;
                    flush_pc_q <= mtvec;
                    tr_trap <= 1'b1; tr_irq <= rd_irq; tr_cause <= cz; tr_epc <= rd_pc;
                end
                if (rd_mret) begin
                    mstatus <= (mstatus & ~32'h8) | {28'b0, mstatus[7], 3'b0} | 32'h1880;
                    flush_pc_q <= mepc;
                end
                if (rd_rpl) begin
                    flush_pc_q <= rd_pc;
                    replay_set <= rd_rset; md_set <= rd_md; replay_pc <= rd_pc;
                end
            end
            case (fstate)
                F_IDLE: if (start_fencei) begin fstate <= F_SQ; fi_pc <= pc0 + 32'd4; end
                F_SQ: if (sq_empty) fstate <= F_DC;
                F_DC: if (dc_clean_done) fstate <= F_IW0;
                F_IW0: if (!ic_busy) fstate <= F_IP;
                F_IP: fstate <= F_IW1;
                F_IW1: if (!ic_busy) begin fstate <= F_IDLE; flush_q <= 1'b1; flush_pc_q <= fi_pc; end
                default: fstate <= F_IDLE;
            endcase
            if (flush_q) tail <= head;
        end
    end
`ifndef SYNTHESIS
    longint st_c1 = 0, st_bb = 0, st_h1nd = 0, st_h1v = 0, st_cmt = 0;
    always_ff @(posedge clk) if (!rst && do_c0 && !do_c1 && fstate == F_IDLE) begin
        st_c1 <= st_c1 + 1;
        if (!v1) st_h1v <= st_h1v + 1;
        else if (!done[h1[4:0]]) st_h1nd <= st_h1nd + 1;
        else if (br0 && br1) st_bb <= st_bb + 1;
        else if (fu1 == `FU_CMT || fu0 == `FU_CMT) st_cmt <= st_cmt + 1;
    end
    final $display("O2_C1 single=%0d h1_empty=%0d h1_notdone=%0d two_branches=%0d cmt=%0d", st_c1, st_h1v, st_h1nd, st_bb, st_cmt);
`endif
endmodule
