`timescale 1ns/1ps
`include "o2_defs.vh"
// O2 core top: front end + I$, rename/dispatch, three issue queues, PRF,
// pipe 0 (ALU + branch), pipe 1 (ALU + MUL/CLMUL), pipe M (LSU + D$), ROB.
//
// Issue-queue payload (39 bits):
//   [38:37] ps1 bank [36:35] ps2 bank (register-file bank codes, see o2_prf)
//   [34:31] op [30] src2_imm [29:24] ps1 [23:18] ps2 [17:12] pd
// Immediates live in a ROB-indexed table read in each pipe's RR stage.
//   [11] wr [10:8] brtag [7:5] sqidx [4] jalr [3:1] fu [0] -
module o2_core #(
    parameter [31:0] RESET_PC = 32'h80000000,
    parameter [31:0] RAM_BASE = 32'h80000000,
    parameter integer RAM_BYTES = 131072
) (
    input  logic        clk, rst,
    input  logic        irq_software, irq_timer, irq_external,
    // end-of-run D$ clean
    input  logic        ext_clean_req, output logic ext_clean_done,
    output logic        data_idle,
    // MMIO
    output logic        io_req_v, input logic io_req_rdy,
    output logic [31:0] io_addr, output logic io_write, output logic [3:0] io_be, output logic [31:0] io_wdata,
    input  logic        io_rsp_v, input logic [31:0] io_rdata, input logic io_rsp_err,
    // I$ burst master
    output logic        ic_cmd_valid, input logic ic_cmd_ready, output logic ic_cmd_write,
    output logic [31:0] ic_cmd_addr, output logic [7:0] ic_cmd_len,
    output logic        ic_w_valid, input logic ic_w_ready, output logic [31:0] ic_w_data,
    output logic [3:0]  ic_w_be, output logic ic_w_last,
    input  logic        ic_r_valid, output logic ic_r_ready, input logic [31:0] ic_r_data,
    input  logic        ic_r_error, ic_r_last,
    // D$ burst master
    output logic        dc_cmd_valid, input logic dc_cmd_ready, output logic dc_cmd_write,
    output logic [31:0] dc_cmd_addr, output logic [7:0] dc_cmd_len,
    output logic        dc_w_valid, input logic dc_w_ready, output logic [31:0] dc_w_data,
    output logic [3:0]  dc_w_be, output logic dc_w_last,
    input  logic        dc_r_valid, output logic dc_r_ready, input logic [31:0] dc_r_data,
    input  logic        dc_r_error, dc_r_last,
    // commit trace
    output logic [1:0]  tr_v,
    output logic [31:0] tr_pc0, tr_pc1, tr_insn0, tr_insn1,
    output logic        tr_wr0, tr_wr1,
    output logic [4:0]  tr_rd0, tr_rd1,
    output logic [5:0]  tr_pd0, tr_pd1,
    output logic        tr_trap, tr_irq,
    output logic [31:0] tr_cause, tr_epc, tr_csr_old,
    // PRF write ports (for the testbench shadow register file)
    output logic [3:0]  prf_we_o,
    output logic [23:0] prf_wa_o,
    output logic [127:0] prf_wd_o,
    output logic [63:0] minstret, mcycle,
    // performance events (registered): {be_stall, fe_stall, ld_miss, ld_access, ic_miss}
    output logic [4:0]  perf_ev,
    // imprecise bus errors (pulse): committed store discarded / D$ write-back failed
    output logic        bus_err_v, output logic bus_err_wb, output logic [31:0] bus_err_addr
);
    // ================================================================ wires
    logic flush; logic [31:0] flush_pc;
    logic br_kill, br_ok; logic [2:0] br_kill_tag, br_ok_tag;
    logic fetch_stop;

    // ================================================================ I$ + front end
    logic pf_ic, pf_lda, pf_ldm, pf_fe, pf_be;
    always_ff @(posedge clk) perf_ev <= {pf_be, pf_fe, pf_ldm, pf_lda, pf_ic};
    logic [31:0] ic_f1_pc, ic_f2_pc; logic ic_f2_hit, ic_f2_cacheable, ic_f2_fault, ic_refill_req, ic_busy, ic_inv;
    logic [127:0] ic_f2_block;
    o2_icache #(.SETS(256), .RAM_BASE(RAM_BASE), .RAM_BYTES(RAM_BYTES)) icache (
        .clk(clk), .rst(rst), .f1_pc(ic_f1_pc), .f1_hold(1'b0),
        .f2_pc(ic_f2_pc), .f2_hit(ic_f2_hit), .f2_cacheable(ic_f2_cacheable), .f2_fault(ic_f2_fault),
        .f2_block(ic_f2_block),
        .refill_req(ic_refill_req), .busy(ic_busy), .invalidate(ic_inv),
        .cmd_valid(ic_cmd_valid), .cmd_ready(ic_cmd_ready), .cmd_write(ic_cmd_write), .cmd_addr(ic_cmd_addr),
        .cmd_len(ic_cmd_len), .w_valid(ic_w_valid), .w_ready(ic_w_ready), .w_data(ic_w_data), .w_be(ic_w_be),
        .w_last(ic_w_last), .r_valid(ic_r_valid), .r_ready(ic_r_ready), .r_data(ic_r_data),
        .r_error(ic_r_error), .r_last(ic_r_last), .perf_fill(pf_ic));

    logic fq_v0, fq_v1, fq_fault0, fq_fault1; logic [31:0] fq_pc0, fq_pc1, fq_insn0, fq_insn1, fq_pred0, fq_pred1;
    logic [3:0] fq_biq0, fq_biq1; logic [1:0] fq_k0, fq_k1, fq_pop; logic fq_cmt0, fq_cmt1, fq_br0, fq_br1;
    logic mis_v; logic [31:0] mis_pc; logic [3:0] mis_biq; logic [1:0] mis_k; logic mis_cbr, mis_taken;
    logic cmt_br_valid, cmt_is_cbr, cmt_taken; logic [31:0] cmt_pc; logic [3:0] cmt_biq;
    logic ib_train; logic [31:0] ib_pc, ib_target;
    o2_frontend #(.RESET_PC(RESET_PC)) frontend (
        .clk(clk), .rst(rst),
        .be_flush(flush), .be_flush_pc(flush_pc),
        .be_mispredict(mis_v), .be_mis_pc(mis_pc), .be_mis_biq(mis_biq), .be_mis_k(mis_k),
        .be_mis_is_cbr(mis_cbr), .be_mis_taken(mis_taken), .fetch_stop(fetch_stop),
        .cmt_br_valid(cmt_br_valid), .cmt_is_cbr(cmt_is_cbr), .cmt_taken(cmt_taken), .cmt_pc(cmt_pc), .cmt_biq(cmt_biq),
        .ib_train(ib_train), .ib_pc(ib_pc), .ib_target(ib_target),
        .ic_f1_pc(ic_f1_pc), .ic_f2_pc(ic_f2_pc), .ic_f2_hit(ic_f2_hit), .ic_f2_cacheable(ic_f2_cacheable),
        .ic_f2_fault(ic_f2_fault), .ic_f2_block(ic_f2_block), .ic_refill_req(ic_refill_req), .ic_busy(ic_busy),
        .fq_v0(fq_v0), .fq_v1(fq_v1), .fq_pc0(fq_pc0), .fq_pc1(fq_pc1), .fq_insn0(fq_insn0), .fq_insn1(fq_insn1),
        .fq_pred0(fq_pred0), .fq_pred1(fq_pred1), .fq_fault0(fq_fault0), .fq_fault1(fq_fault1),
        .fq_biq0(fq_biq0), .fq_biq1(fq_biq1), .fq_k0(fq_k0), .fq_k1(fq_k1),
        .fq_cmt0(fq_cmt0), .fq_cmt1(fq_cmt1), .fq_br0(fq_br0), .fq_br1(fq_br1), .fq_pop(fq_pop));

    // ================================================================ rename / dispatch
    logic [1:0] cm_wr; logic [4:0] cm_rd0, cm_rd1; logic [5:0] cm_pdst0, cm_pdst1, cm_pold0, cm_pold1;
    logic rob_empty; logic replay_set; logic [31:0] replay_pc;
    logic [5:0] rob_tail, rob_count; logic [4:0] rob_head; logic [1:0] rob_room, sq_room;
    logic [3:0] iq0_free, iq1_free, iqm_free;
    logic [2:0] iq0_a0, iq0_a1, iq1_a0, iq1_a1, iqm_a0, iqm_a1;
    logic [23:0] wake;
    logic [3:0] sq_tail, sq_count; logic [7:0] sq_valid, sq_issued, sq_free; logic sq_empty;
    logic [1:0] iq0_dv, iq1_dv, iqm_dv;
    logic [38:0] s0_pay, s1_pay; logic [31:0] s0_imm, s1_imm; logic [23:0] s0_dep, s1_dep; logic [1:0] s0_lat, s1_lat;
    logic [7:0] s0_brm, s1_brm, s0_sqm, s1_sqm; logic s0_st, s1_st, s0_head, s1_head; logic [4:0] s0_rob, s1_rob;
    logic [1:0] rob_dv; logic [127:0] rob_e0, rob_e1; logic [1:0] sq_alloc;
    logic brt_we; logic [2:0] brt_tag; logic [107:0] brt_data; logic [3:0] ckpt_sq_tail;
    o2_rename rename (
        .clk(clk), .rst(rst),
        .fq_v0(fq_v0), .fq_v1(fq_v1), .fq_pc0(fq_pc0), .fq_pc1(fq_pc1), .fq_insn0(fq_insn0), .fq_insn1(fq_insn1),
        .fq_pred0(fq_pred0), .fq_pred1(fq_pred1), .fq_fault0(fq_fault0), .fq_fault1(fq_fault1),
        .fq_biq0(fq_biq0), .fq_biq1(fq_biq1), .fq_k0(fq_k0), .fq_k1(fq_k1),
        .fq_cmt0(fq_cmt0), .fq_cmt1(fq_cmt1), .fq_br0(fq_br0), .fq_br1(fq_br1), .fq_pop(fq_pop),
        .flush(flush), .br_kill(br_kill), .br_kill_tag(br_kill_tag), .br_ok(br_ok), .br_ok_tag(br_ok_tag),
        .cm_wr(cm_wr), .cm_rd0(cm_rd0), .cm_rd1(cm_rd1), .cm_pdst0(cm_pdst0), .cm_pdst1(cm_pdst1),
        .cm_pold0(cm_pold0), .cm_pold1(cm_pold1), .rob_empty(rob_empty),
        .replay_set(replay_set), .replay_pc(replay_pc), .md_set(md_set),
        .rob_tail(rob_tail), .rob_room(rob_room), .sq_room(sq_room),
        .iq0_free(iq0_free), .iq1_free(iq1_free), .iqm_free(iqm_free),
        .iq0_a0(iq0_a0), .iq0_a1(iq0_a1), .iq1_a0(iq1_a0), .iq1_a1(iq1_a1), .iqm_a0(iqm_a0), .iqm_a1(iqm_a1),
        .wake(wake), .sq_tail(sq_tail), .sq_count(sq_count), .sq_valid(sq_valid),
        .iq0_dv(iq0_dv), .iq1_dv(iq1_dv), .iqm_dv(iqm_dv),
        .s0_pay(s0_pay), .s1_pay(s1_pay), .s0_imm(s0_imm), .s1_imm(s1_imm), .s0_dep(s0_dep), .s1_dep(s1_dep), .s0_lat(s0_lat), .s1_lat(s1_lat),
        .s0_brm(s0_brm), .s1_brm(s1_brm), .s0_sqm(s0_sqm), .s1_sqm(s1_sqm), .s0_st(s0_st), .s1_st(s1_st),
        .s0_head(s0_head), .s1_head(s1_head), .s0_rob(s0_rob), .s1_rob(s1_rob),
        .rob_dv(rob_dv), .rob_e0(rob_e0), .rob_e1(rob_e1), .sq_alloc(sq_alloc),
        .brt_we(brt_we), .brt_tag(brt_tag), .brt_data(brt_data), .ckpt_sq_tail(ckpt_sq_tail),
        .perf_fe_stall(pf_fe), .perf_be_stall(pf_be));

    // branch table and per-branch SQ tail
    logic [107:0] brt [0:7];
    logic [3:0] ckpt_sq [0:7];
    always_ff @(posedge clk) if (brt_we) begin brt[brt_tag] <= brt_data; ckpt_sq[brt_tag] <= ckpt_sq_tail; end

    // immediate table, indexed by ROB entry: even / odd banks (the two
    // dispatch slots always have consecutive ROB indices), one copy per
    // reading pipe (RR stage of pipes 0, 1, M)
    logic [31:0] imm_rd [0:2];
    wire imm_s0e = !s0_rob[0];
    wire imm_we_e = rob_dv[0] && imm_s0e || rob_dv[1] && !imm_s0e;
    wire imm_we_o = rob_dv[0] && !imm_s0e || rob_dv[1] && imm_s0e;
    wire [3:0] imm_wa_e = imm_s0e ? s0_rob[4:1] : s1_rob[4:1];
    wire [3:0] imm_wa_o = imm_s0e ? s1_rob[4:1] : s0_rob[4:1];
    wire [31:0] imm_wd_e = imm_s0e ? s0_imm : s1_imm;
    wire [31:0] imm_wd_o = imm_s0e ? s1_imm : s0_imm;
    genvar gi;
    generate for (gi = 0; gi < 3; gi++) begin : g_imm
        (* syn_ramstyle = "lut_ram" *) logic [31:0] te [0:15];
        (* syn_ramstyle = "lut_ram" *) logic [31:0] to [0:15];
        always_ff @(posedge clk) begin
            if (imm_we_e) te[imm_wa_e] <= imm_wd_e;
            if (imm_we_o) to[imm_wa_o] <= imm_wd_o;
        end
        wire [4:0] ri = (gi == 0) ? rr0_rob : (gi == 1) ? rr1_rob : rrm_rob;
        assign imm_rd[gi] = ri[0] ? to[ri[4:1]] : te[ri[4:1]];
    end endgenerate

    // ================================================================ issue queues
    logic [7:0] wake0, wake1, wakem;
    assign wake = {wakem, wake1, wake0};
    logic iss0_v, iss1_v, issm_v; logic [2:0] iss0_slot, iss1_slot, issm_slot;
    logic [38:0] iss0_pay, iss1_pay, issm_pay; logic [7:0] iss0_brm, iss1_brm, issm_brm, issm_sqm, unused_sqm0, unused_sqm1;
    logic [4:0] iss0_rob, iss1_rob, issm_rob; logic [1:0] iss0_lat, iss1_lat, issm_lat;
    logic [7:0] ext_done; logic slow_busy, slow_pend; logic spec_ok; logic [31:0] md_viol; logic md_set;
    logic mi1, mi2;             // MUL issued 1 / 2 cycles ago in IQ1
    always_ff @(posedge clk) begin
        if (rst) begin mi1 <= 1'b0; mi2 <= 1'b0; end
        else begin mi1 <= iss1_v && iss1_lat == 2'd2; mi2 <= mi1; end
    end
`define IQ_PORTS \
        .d_pay0(s0_pay), .d_pay1(s1_pay), .d_dep0(s0_dep), .d_dep1(s1_dep), \
        .d_lat0(s0_lat), .d_lat1(s1_lat), .d_brm0(s0_brm), .d_brm1(s1_brm), \
        .d_sqm0(s0_sqm), .d_sqm1(s1_sqm), .d_store0(s0_st), .d_store1(s1_st), \
        .d_head0(s0_head), .d_head1(s1_head), .d_rob0(s0_rob), .d_rob1(s1_rob)
    o2_iq #(.N(8), .NC(24), .BASE(0), .PW(39), .MEM(0)) iq0 (
        .clk(clk), .rst(rst), .d_v(iq0_dv), `IQ_PORTS,
        .a_slot0(iq0_a0), .a_slot1(iq0_a1), .free_cnt(iq0_free), .wake_in(wake), .wake_out(wake0),
        .issue_en(1'b1), .blk_lat(1'b0), .blk_l0(1'b0), .iss_v(iss0_v), .iss_slot(iss0_slot), .iss_pay(iss0_pay), .iss_brm(iss0_brm),
        .iss_sqm(unused_sqm0), .iss_rob(iss0_rob), .iss_lat(iss0_lat), .ext_done(8'b0),
        .sq_issued(8'b0), .sq_free(8'b0), .rob_head(rob_head),
        .br_ok(br_ok), .br_ok_tag(br_ok_tag), .br_kill(br_kill), .br_kill_tag(br_kill_tag), .flush(flush));
    o2_iq #(.N(8), .NC(24), .BASE(8), .PW(39), .MEM(0)) iq1 (
        .clk(clk), .rst(rst), .d_v(iq1_dv), `IQ_PORTS,
        .a_slot0(iq1_a0), .a_slot1(iq1_a1), .free_cnt(iq1_free), .wake_in(wake), .wake_out(wake1),
        .issue_en(1'b1), .blk_lat(1'b0), .blk_l0(mi2), .iss_v(iss1_v), .iss_slot(iss1_slot), .iss_pay(iss1_pay), .iss_brm(iss1_brm),
        .iss_sqm(unused_sqm1), .iss_rob(iss1_rob), .iss_lat(iss1_lat), .ext_done(8'b0),
        .sq_issued(8'b0), .sq_free(8'b0), .rob_head(rob_head),
        .br_ok(br_ok), .br_ok_tag(br_ok_tag), .br_kill(br_kill), .br_kill_tag(br_kill_tag), .flush(flush));
    o2_iq #(.N(8), .NC(24), .BASE(16), .PW(39), .MEM(1)) iqm (
        .clk(clk), .rst(rst), .d_v(iqm_dv), `IQ_PORTS,
        .a_slot0(iqm_a0), .a_slot1(iqm_a1), .free_cnt(iqm_free), .wake_in(wake), .wake_out(wakem),
        .issue_en(!slow_pend), .blk_lat(1'b0), .blk_l0(1'b0), .iss_v(issm_v), .iss_slot(issm_slot), .iss_pay(issm_pay), .iss_brm(issm_brm),
        .iss_sqm(issm_sqm), .iss_rob(issm_rob), .iss_lat(issm_lat), .ext_done(ext_done),
        .sq_issued(sq_issued), .sq_free(sq_free), .spec_ok(spec_ok), .rob_head(rob_head),
        .br_ok(br_ok), .br_ok_tag(br_ok_tag), .br_kill(br_kill), .br_kill_tag(br_kill_tag), .flush(flush));
`undef IQ_PORTS

    // ================================================================ PRF
    logic [2:0] prf_we; logic [17:0] prf_wa; logic [95:0] prf_wd;
    logic [35:0] prf_ra; logic [191:0] prf_rd;
    // Read addresses are registered once per write bank so no copy drives
    // more than one bank.
    logic [35:0] prf_ra_n;                     // next-cycle read addresses
    logic [107:0] prf_ra_b;                    // bank copies, [(w*6 + r)*6 +: 6]
    genvar gw;
    generate for (gw = 0; gw < 3; gw++) begin : g_rac
        (* syn_preserve = 1 *) logic [35:0] c;
        always_ff @(posedge clk) c <= prf_ra_n;
        assign prf_ra_b[36*gw +: 36] = c;
    end endgenerate
    // bank codes of the read operands (registered with the RR payloads)
    // The CSR operand uses pipe M's rs1 port: a CSR op executes alone at the
    // ROB head with all issue queues empty, so that port is idle (its payload
    // is all zero) and the CSR fields can simply be ORed in.
    logic [11:0] prf_rsel;
    assign prf_rsel = {rrm_pay[36:35], rrm_pay[38:37] | (csr_rd_b ? csr_rs1_bank : 2'b0), rr1_pay[36:35], rr1_pay[38:37],
                       rr0_pay[36:35], rr0_pay[38:37]};
    o2_prf #(.NW(3), .NR(6)) prf (.clk(clk), .rst(rst), .we(prf_we), .waddr(prf_wa), .wdata(prf_wd),
        .raddr_b(prf_ra_b), .rsel(prf_rsel), .rdata(prf_rd));
    // result registers (one per write port), written to the PRF the next cycle
    //   0: pipe 0   1: pipe 1 (ALU or MUL/CLMUL)   2: loads / CSR
    logic wb_v [0:2]; logic [5:0] wb_pd [0:2]; logic [31:0] wb_d [0:2];
    always_comb begin
        for (int i = 0; i < 3; i++) begin
            prf_we[i] = wb_v[i]; prf_wa[6*i +: 6] = wb_pd[i]; prf_wd[32*i +: 32] = wb_d[i];
        end
    end
    assign prf_we_o = {1'b0, prf_we}; assign prf_wa_o = {6'b0, prf_wa}; assign prf_wd_o = {32'b0, prf_wd};

    function automatic logic killed(input [7:0] brm);
        killed = flush || (br_kill && brm[br_kill_tag]);
    endfunction
    function automatic [7:0] okclr(input [7:0] brm);
        okclr = br_ok ? (brm & ~(8'b1 << br_ok_tag)) : brm;
    endfunction
    // RR-stage operand: PRF value with bypass from the result registers (a
    // physical register is written by at most one port per cycle: one-hot)
    function automatic [31:0] rrval(input [5:0] p, input [31:0] prfv);
        logic [2:0] m; logic [31:0] bv;
        bv = 32'b0;
        for (int i = 0; i < 3; i++) begin
            m[i] = wb_v[i] && wb_pd[i] == p && p != 6'd0;
            bv = bv | ({32{m[i]}} & wb_d[i]);
        end
        rrval = (|m) ? bv : prfv;          // prfv is zero for x0 / never written
    endfunction

    // producers finishing this cycle (their results are in wb_* next cycle)
    logic ex0_prod, ex1_prod, ld_prod, mul_prod;
    logic [5:0] ex0_ppd, ex1_ppd, ld_ppd, mul_ppd;
    function automatic [1:0] latesel(input [5:0] p);
        logic m0, m1, m2;
        m0 = ex0_prod && ex0_ppd == p;
        m1 = (ex1_prod && ex1_ppd == p) || (mul_prod && mul_ppd == p);
        m2 = ld_prod && ld_ppd == p;
        latesel = (p == 6'd0) ? 2'd0 : {m1 | m2, m0 | m2};
    endfunction
    // EX-stage late bypass (4:1 by the 2-bit code)
    function automatic [31:0] exval(input [1:0] sel, input [31:0] v);
        case (sel)
            2'd0: exval = v;
            2'd1: exval = wb_d[0];
            2'd2: exval = wb_d[1];
            default: exval = wb_d[2];
        endcase
    endfunction
    // ALU op decoded in RR: one-hot result select + subtract flag
    //   [0] add/sub [1] slt [2] sltu [3] sll [4] srl [5] sra [6] xor [7] or [8] and [9] pass b
    function automatic [10:0] aludec(input [3:0] op);
        logic [9:0] oh;
        case (op)
            `ALU_ADD, `ALU_SUB: oh = 10'b0000000001;
            `ALU_SLT:  oh = 10'b0000000010;
            `ALU_SLTU: oh = 10'b0000000100;
            `ALU_SLL:  oh = 10'b0000001000;
            `ALU_SRL:  oh = 10'b0000010000;
            `ALU_SRA:  oh = 10'b0000100000;
            `ALU_XOR:  oh = 10'b0001000000;
            `ALU_OR:   oh = 10'b0010000000;
            `ALU_AND:  oh = 10'b0100000000;
            default:   oh = 10'b1000000000;
        endcase
        aludec = {op == `ALU_SUB || op == `ALU_SLT || op == `ALU_SLTU, oh};
    endfunction
    // one add/sub carry chain serves add, sub, slt and sltu
    function automatic [31:0] alu(input [10:0] d, input [31:0] a, input [31:0] b);
        logic [32:0] s; logic lts, ltu; logic [31:0] sr;
        s = {1'b0, a} + {1'b0, d[10] ? ~b : b} + {32'b0, d[10]};
        ltu = !s[32];
        lts = (a[31] ^ b[31]) ? a[31] : s[31];
        sr = d[5] ? $unsigned($signed(a) >>> b[4:0]) : (a >> b[4:0]);
        alu = ({32{d[0]}} & s[31:0]) | ({32{d[1]}} & {31'b0, lts}) | ({32{d[2]}} & {31'b0, ltu}) |
              ({32{d[3]}} & (a << b[4:0])) | ({32{d[4] | d[5]}} & sr) | ({32{d[6]}} & (a ^ b)) |
              ({32{d[7]}} & (a | b)) | ({32{d[8]}} & (a & b)) | ({32{d[9]}} & b);
    endfunction

    // ================================================================ pipe 0: RR
    logic rr0_v; logic [38:0] rr0_pay; logic [7:0] rr0_brm; logic [4:0] rr0_rob;
    always_ff @(posedge clk) begin
        if (rst) rr0_v <= 1'b0;
        else rr0_v <= iss0_v && !killed(iss0_brm);
        rr0_pay <= iss0_pay; rr0_brm <= okclr(iss0_brm); rr0_rob <= iss0_rob;
    end
    assign prf_ra[0 +: 6] = rr0_pay[29:24];
    assign prf_ra[6 +: 6] = rr0_pay[23:18];
    assign prf_ra_n[0 +: 6] = iss0_pay[29:24];
    assign prf_ra_n[6 +: 6] = iss0_pay[23:18];
    wire [107:0] rr0_brt = brt[rr0_pay[10:8]];
    // EX regs
    logic ex0_v; logic [38:0] ex0_pay; logic [7:0] ex0_brm; logic [4:0] ex0_rob;
    logic [31:0] ex0_a, ex0_b; logic [1:0] ex0_sa, ex0_sb; logic [107:0] ex0_brt; logic [31:0] ex0_pc4;
    logic [10:0] ex0_d; logic ex0_ne_seq, ex0_ne_tgt;
    wire [31:0] rr0_pc4 = rr0_brt[107:76] + 32'd4;
    always_ff @(posedge clk) begin
        if (rst) ex0_v <= 1'b0;
        else ex0_v <= rr0_v && !killed(rr0_brm);
        ex0_pay <= rr0_pay; ex0_brm <= okclr(rr0_brm); ex0_rob <= rr0_rob;
        ex0_a <= rrval(rr0_pay[29:24], prf_rd[0 +: 32]);
        ex0_b <= rr0_pay[30] ? imm_rd[0] : rrval(rr0_pay[23:18], prf_rd[32 +: 32]);
        ex0_sa <= latesel(rr0_pay[29:24]); ex0_sb <= rr0_pay[30] ? 2'b0 : latesel(rr0_pay[23:18]);
        ex0_d <= aludec(rr0_pay[34:31]);
        ex0_brt <= rr0_brt; ex0_pc4 <= rr0_pc4;
        // prediction checks for the two possible direct outcomes
        ex0_ne_seq <= rr0_brt[75:44] != rr0_pc4;
        ex0_ne_tgt <= rr0_brt[75:44] != rr0_brt[43:12];
    end
    // EX
    wire ex0_live = ex0_v && !killed(ex0_brm);
    wire [31:0] a0 = exval(ex0_sa, ex0_a);
    wire [31:0] b0 = exval(ex0_sb, ex0_b);       // rs2 or immediate (branches: rs2)
    wire ex0_isbr = ex0_pay[3:1] == `FU_BR;
    wire ex0_jalr = ex0_pay[4];
    wire [2:0] bf3 = ex0_pay[33:31];
    logic btaken;
    always_comb begin
        case (bf3)
            3'd0: btaken = a0 == b0;
            3'd1: btaken = a0 != b0;
            3'd4: btaken = $signed(a0) < $signed(b0);
            3'd5: btaken = $signed(a0) >= $signed(b0);
            3'd6: btaken = a0 < b0;
            default: btaken = a0 >= b0;
        endcase
    end
    wire [31:0] jtgt = (a0 + ex0_brt[43:12]) & ~32'd1;     // brt imm field = JALR offset
    wire [31:0] btgt = ex0_jalr ? jtgt : ex0_brt[43:12];
    wire br_taken = ex0_jalr || btaken;
    wire [31:0] br_next = br_taken ? btgt : ex0_pc4;
    wire br_mis_align = br_taken && btgt[1];
    wire br_mis = !br_mis_align && (ex0_jalr ? (jtgt != ex0_brt[75:44]) : btaken ? ex0_ne_tgt : ex0_ne_seq);
    wire [31:0] alu0 = alu(ex0_d, a0, b0);
    assign ex0_prod = ex0_live && ex0_pay[11];
    assign ex0_ppd = ex0_pay[17:12];
    // resolution (registered)
    logic res_v, res_mis, res_cbr, res_taken; logic [2:0] res_tag; logic [31:0] res_next, res_pc;
    logic [3:0] res_biq; logic [1:0] res_k; logic [4:0] res_rob; logic res_jalr, res_exc;
    always_ff @(posedge clk) begin
        if (rst) res_v <= 1'b0;
        else res_v <= ex0_live && ex0_isbr;
        res_mis <= br_mis; res_cbr <= !ex0_jalr; res_taken <= br_taken; res_tag <= ex0_pay[10:8];
        res_next <= br_next; res_pc <= ex0_brt[107:76]; res_biq <= ex0_brt[11:8]; res_k <= ex0_brt[7:6];
        res_rob <= ex0_brt[4:0]; res_jalr <= ex0_jalr; res_exc <= br_mis_align;
    end
    assign br_kill = res_v && res_mis && !flush;
    assign br_kill_tag = res_tag;
    assign br_ok = res_v && !res_mis && !flush;
    assign br_ok_tag = res_tag;
    assign mis_v = br_kill; assign mis_pc = res_next; assign mis_biq = res_biq; assign mis_k = res_k;
    assign mis_cbr = res_cbr; assign mis_taken = res_taken;
    assign ib_train = res_v && res_jalr && !flush; assign ib_pc = res_pc; assign ib_target = res_next;

    // ================================================================ pipe 1: RR / EX / MUL
    logic rr1_v; logic [38:0] rr1_pay; logic [7:0] rr1_brm; logic [4:0] rr1_rob;
    always_ff @(posedge clk) begin
        if (rst) rr1_v <= 1'b0;
        else rr1_v <= iss1_v && !killed(iss1_brm);
        rr1_pay <= iss1_pay; rr1_brm <= okclr(iss1_brm); rr1_rob <= iss1_rob;
    end
    assign prf_ra[12 +: 6] = rr1_pay[29:24];
    assign prf_ra[18 +: 6] = rr1_pay[23:18];
    assign prf_ra_n[12 +: 6] = iss1_pay[29:24];
    assign prf_ra_n[18 +: 6] = iss1_pay[23:18];
    logic ex1_v; logic [38:0] ex1_pay; logic [7:0] ex1_brm; logic [4:0] ex1_rob;
    logic [31:0] ex1_a, ex1_b; logic [1:0] ex1_sa, ex1_sb; logic [10:0] ex1_d;
    always_ff @(posedge clk) begin
        if (rst) ex1_v <= 1'b0;
        else ex1_v <= rr1_v && !killed(rr1_brm);
        ex1_pay <= rr1_pay; ex1_brm <= okclr(rr1_brm); ex1_rob <= rr1_rob;
        ex1_a <= rrval(rr1_pay[29:24], prf_rd[64 +: 32]);
        ex1_b <= rr1_pay[30] ? imm_rd[1] : rrval(rr1_pay[23:18], prf_rd[96 +: 32]);
        ex1_sa <= latesel(rr1_pay[29:24]); ex1_sb <= rr1_pay[30] ? 2'b0 : latesel(rr1_pay[23:18]);
        // zero unless a live ALU op: port 1 ORs the ALU and MUL results
        ex1_d <= (rr1_v && rr1_pay[3:1] != `FU_MUL) ? aludec(rr1_pay[34:31]) : 11'b0;
    end
    wire ex1_live = ex1_v && !killed(ex1_brm);
    wire [31:0] a1 = exval(ex1_sa, ex1_a);
    wire [31:0] b1 = exval(ex1_sb, ex1_b);        // rs2 or immediate (MUL: rs2)
    wire ex1_ismul = ex1_pay[3:1] == `FU_MUL;
    wire [31:0] alu1 = alu(ex1_d, a1, b1);
    assign ex1_prod = ex1_live && !ex1_ismul && ex1_pay[11];
    assign ex1_ppd = ex1_pay[17:12];
    // MUL / CLMUL (all latency class 2):
    //   M1 = EX: bypassed operands registered (multiplier input registers)
    //   M2: four 17x17 signed partial products (or carry-less 16x16 partials)
    //   M3: one carry-save + carry-propagate add; result to write port 3
    function automatic [31:0] poly16(input [15:0] x, input [15:0] y);
        logic [31:0] acc; acc = 32'b0;
        for (int i = 0; i < 16; i++) if (y[i]) acc = acc ^ ({16'b0, x} << i);
        poly16 = acc;
    endfunction
    wire mul_go = ex1_live && ex1_ismul;
    logic mo_v, mo_wr; logic [2:0] mo_op; logic [5:0] mo_pd; logic [4:0] mo_rob; logic [7:0] mo_brm;
    logic [31:0] mo_a, mo_b;
    always_ff @(posedge clk) begin
        if (rst) mo_v <= 1'b0;
        else mo_v <= mul_go;
        mo_op <= ex1_pay[33:31]; mo_pd <= ex1_pay[17:12]; mo_wr <= ex1_pay[11]; mo_rob <= ex1_rob;
        mo_brm <= okclr(ex1_brm); mo_a <= a1; mo_b <= b1;
    end
    wire mo_live = mo_v && !killed(mo_brm);
    wire mo_sa = mo_op == `MOP_MULH || mo_op == `MOP_MULHSU;
    wire mo_sb = mo_op == `MOP_MULH;
    wire signed [16:0] mah = {mo_sa & mo_a[31], mo_a[31:16]}, mbh = {mo_sb & mo_b[31], mo_b[31:16]};
    wire signed [16:0] mal = {1'b0, mo_a[15:0]}, mbl = {1'b0, mo_b[15:0]};
    logic m2_v, m2_wr, m2_cl, m2_hi; logic [2:0] m2_op; logic [5:0] m2_pd; logic [4:0] m2_rob; logic [7:0] m2_brm;
    logic signed [33:0] m2_ll, m2_lh, m2_hl, m2_hh;
    logic [31:0] m2_cll, m2_clh, m2_chl, m2_chh;
    always_ff @(posedge clk) begin
        if (rst) m2_v <= 1'b0;
        else m2_v <= mo_live;
        m2_op <= mo_op; m2_cl <= mo_op[2]; m2_hi <= !mo_op[2] && mo_op != `MOP_MUL;
        m2_pd <= mo_pd; m2_wr <= mo_wr; m2_rob <= mo_rob; m2_brm <= okclr(mo_brm);
        m2_ll <= mal * mbl; m2_lh <= mal * mbh; m2_hl <= mah * mbl; m2_hh <= mah * mbh;
        m2_cll <= poly16(mo_a[15:0], mo_b[15:0]); m2_clh <= poly16(mo_a[15:0], mo_b[31:16]);
        m2_chl <= poly16(mo_a[31:16], mo_b[15:0]); m2_chh <= poly16(mo_a[31:16], mo_b[31:16]);
    end
    wire m2_live = m2_v && !killed(m2_brm);
    wire [63:0] mx1 = {{14{m2_lh[33]}}, m2_lh, 16'b0};
    wire [63:0] mx2 = {{14{m2_hl[33]}}, m2_hl, 16'b0};
    wire [63:0] my = {m2_hh[31:0], m2_ll[31:0]};
    wire [63:0] mcs_s = my ^ mx1 ^ mx2;
    wire [63:0] mcs_c = ((my & mx1) | (my & mx2) | (mx1 & mx2)) << 1;
    wire [63:0] mprod = mcs_s + mcs_c;
    wire [63:0] clprod = {32'b0, m2_cll} ^ {16'b0, m2_clh, 16'b0} ^ {16'b0, m2_chl, 16'b0} ^ {m2_chh, 32'b0};
    wire [31:0] m2_res = m2_cl ? ((m2_op == `MOP_CLMUL) ? clprod[31:0] : (m2_op == `MOP_CLMULR) ? clprod[62:31] : clprod[63:32])
                               : (m2_hi ? mprod[63:32] : mprod[31:0]);
    assign mul_prod = m2_live && m2_wr;
    assign mul_ppd = m2_pd;

    // ================================================================ pipe M: RR / EX (LSU)
    logic rrm_v; logic [38:0] rrm_pay; logic [7:0] rrm_brm, rrm_sqm; logic [4:0] rrm_rob; logic [1:0] rrm_lat;
    logic [2:0] rrm_slot;
    always_ff @(posedge clk) begin
        if (rst) rrm_v <= 1'b0;
        else rrm_v <= issm_v && !killed(issm_brm);
        rrm_pay <= issm_pay; rrm_brm <= okclr(issm_brm); rrm_rob <= issm_rob; rrm_lat <= issm_lat;
        rrm_sqm <= issm_sqm & ~sq_free; rrm_slot <= issm_slot;
    end
    assign prf_ra[24 +: 6] = rrm_pay[29:24];
    assign prf_ra[30 +: 6] = rrm_pay[23:18];
    assign prf_ra_n[24 +: 6] = issm_pay[29:24] | (csr_rd_a ? csr_rs1_preg : 6'b0);
    assign prf_ra_n[30 +: 6] = issm_pay[23:18];
    logic exm_v; logic [38:0] exm_pay; logic [7:0] exm_brm, exm_sqm; logic [4:0] exm_rob; logic [1:0] exm_lat;
    logic [31:0] exm_a, exm_b; logic [1:0] exm_sa, exm_sb; logic [2:0] exm_slot; logic [11:0] exm_imm;
    always_ff @(posedge clk) begin
        if (rst) exm_v <= 1'b0;
        else exm_v <= rrm_v && !killed(rrm_brm);
        exm_pay <= rrm_pay; exm_brm <= okclr(rrm_brm); exm_rob <= rrm_rob; exm_lat <= rrm_lat;
        exm_sqm <= rrm_sqm & ~sq_free; exm_slot <= rrm_slot;
        exm_a <= rrval(rrm_pay[29:24], prf_rd[128 +: 32]);
        exm_b <= rrval(rrm_pay[23:18], prf_rd[160 +: 32]);
        exm_sa <= latesel(rrm_pay[29:24]); exm_sb <= latesel(rrm_pay[23:18]);
        exm_imm <= imm_rd[2][11:0];
    end
    wire [31:0] am = exval(exm_sa, exm_a);
    wire [31:0] bm = exval(exm_sb, exm_b);
    logic st_done_v, st_exc, st_rpl, ld_wb_v, ld_done_v, ld_exc, ld_replay, ld_replay_io, ld_m_v;
    // store completions reach the ROB one cycle later (off the address-adder path)
    logic st_v_q, st_exc_q, st_rpl_q; logic [4:0] st_rob_q; logic [3:0] st_cause_q; logic [31:0] st_tval_q;
    logic [4:0] st_done_rob, ld_done_rob; logic [3:0] st_cause, ld_cause; logic [31:0] st_tval, ld_tval, ld_wb_data;
    logic [5:0] ld_wb_pd, ld_m_pd; logic [1:0] sq_commit; logic dc_clean_req, dc_clean_done;
    logic lsu_clean_req, lsu_clean_done;
    o2_lsu #(.SETS(256), .RAM_BASE(RAM_BASE), .RAM_BYTES(RAM_BYTES)) lsu (
        .clk(clk), .rst(rst),
        .sq_alloc(sq_alloc), .sq_tail(sq_tail), .sq_count(sq_count), .sq_valid(sq_valid), .sq_issued(sq_issued),
        .sq_free(sq_free), .sq_empty(sq_empty), .sq_room(sq_room), .spec_ok(spec_ok), .md_viol(md_viol), .perf_ld_acc(pf_lda), .perf_ld_miss(pf_ldm),
        .ex_v(exm_v), .ex_store(exm_pay[3:1] == `FU_ST), .ex_op(exm_pay[33:31]), .ex_base(am), .ex_sdata(bm),
        .ex_imm(exm_imm), .ex_pd(exm_pay[17:12]), .ex_rob(exm_rob), .ex_sqidx(exm_pay[7:5]), .ex_sqm(exm_sqm),
        .ex_brm(exm_brm), .ex_head(exm_lat == 2'd3), .ex_slot(exm_slot),
        .st_done_v(st_done_v), .st_done_rob(st_done_rob), .st_exc(st_exc), .st_cause(st_cause), .st_tval(st_tval),
        .st_replay(st_rpl), .bus_err_v(bus_err_v), .bus_err_wb(bus_err_wb), .bus_err_addr(bus_err_addr),
        .ld_wb_v(ld_wb_v), .ld_wb_pd(ld_wb_pd), .ld_wb_data(ld_wb_data), .ld_done_v(ld_done_v), .ld_done_rob(ld_done_rob),
        .ld_exc(ld_exc), .ld_cause(ld_cause), .ld_tval(ld_tval), .ld_replay(ld_replay), .ld_replay_io(ld_replay_io), .ld_m_v(ld_m_v), .ld_m_pd(ld_m_pd),
        .ext_done(ext_done), .slow_busy(slow_busy), .sq_commit(sq_commit),
        .flush(flush), .br_kill(br_kill), .br_kill_tag(br_kill_tag), .br_kill_sqtail(ckpt_sq[br_kill_tag]),
        .br_ok(br_ok), .br_ok_tag(br_ok_tag),
        .clean_req(lsu_clean_req), .clean_done(lsu_clean_done),
        .io_req_v(io_req_v), .io_req_rdy(io_req_rdy), .io_addr(io_addr), .io_write(io_write), .io_be(io_be),
        .io_wdata(io_wdata), .io_rsp_v(io_rsp_v), .io_rdata(io_rdata), .io_rsp_err(io_rsp_err),
        .cmd_valid(dc_cmd_valid), .cmd_ready(dc_cmd_ready), .cmd_write(dc_cmd_write), .cmd_addr(dc_cmd_addr),
        .cmd_len(dc_cmd_len), .w_valid(dc_w_valid), .w_ready(dc_w_ready), .w_data(dc_w_data), .w_be(dc_w_be),
        .w_last(dc_w_last), .r_valid(dc_r_valid), .r_ready(dc_r_ready), .r_data(dc_r_data),
        .r_error(dc_r_error), .r_last(dc_r_last));
    assign lsu_clean_req = dc_clean_req || ext_clean_req;
    assign dc_clean_done = lsu_clean_done;
    assign ext_clean_done = lsu_clean_done;
    assign ld_prod = ld_m_v && ld_wb_v;
    always_ff @(posedge clk) begin
        if (rst) st_v_q <= 1'b0;
        else st_v_q <= st_done_v && !flush;
        st_rob_q <= st_done_rob; st_exc_q <= st_exc; st_rpl_q <= st_rpl; st_cause_q <= st_cause; st_tval_q <= st_tval;
    end
    assign ld_ppd = ld_m_pd;
    // A head-only op owns the slow path from its RR stage on: the LSU state
    // machine only leaves L_IDLE after EX. Until it completes, no other IQM op
    // may issue (the slow path borrows D$ port A) and no interrupt may be
    // taken (its MMIO access cannot be undone once started).
    assign slow_pend = slow_busy || (rrm_v && rrm_lat == 2'd3) || (exm_v && exm_lat == 2'd3);
    assign data_idle = sq_empty && !slow_busy;

    // ================================================================ result registers
    logic csr_wb_v; logic [5:0] csr_wb_pd; logic [31:0] csr_wb_data;
    always_ff @(posedge clk) begin
        if (rst) begin for (int i = 0; i < 3; i++) wb_v[i] <= 1'b0; end
        else begin
            wb_v[0] <= ex0_prod;
            // an ALU op never finishes in the cycle a MUL does (issue block)
            wb_v[1] <= ex1_prod || (mul_prod && !flush);
            wb_v[2] <= (ld_wb_v && !flush) || csr_wb_v;
        end
        wb_pd[0] <= ex0_ppd; wb_d[0] <= ex0_isbr ? ex0_pc4 : alu0;
        wb_pd[1] <= mul_prod ? mul_ppd : ex1_ppd; wb_d[1] <= alu1 | ({32{mul_prod}} & m2_res);
        wb_pd[2] <= csr_wb_v ? csr_wb_pd : ld_wb_pd; wb_d[2] <= csr_wb_v ? csr_wb_data : ld_wb_data;
    end

    // ================================================================ ROB
    // Commit side effects reach rename / LSU / front end one cycle later
    // (registered): free-list pushes, committed RAT, SQ commit marks and
    // predictor training are not latency critical.
    logic [1:0] cm_wr_r, sq_commit_r; logic [4:0] cm_rd0_r, cm_rd1_r; logic [5:0] cm_pdst0_r, cm_pdst1_r, cm_pold0_r, cm_pold1_r;
    logic cmt_br_valid_r, cmt_is_cbr_r, cmt_taken_r; logic [31:0] cmt_pc_r; logic [3:0] cmt_biq_r;
    always_ff @(posedge clk) begin
        if (rst) begin cm_wr <= 2'b0; sq_commit <= 2'b0; cmt_br_valid <= 1'b0; end
        else begin cm_wr <= cm_wr_r; sq_commit <= sq_commit_r; cmt_br_valid <= cmt_br_valid_r; end
        cm_rd0 <= cm_rd0_r; cm_rd1 <= cm_rd1_r; cm_pdst0 <= cm_pdst0_r; cm_pdst1 <= cm_pdst1_r;
        cm_pold0 <= cm_pold0_r; cm_pold1 <= cm_pold1_r;
        cmt_is_cbr <= cmt_is_cbr_r; cmt_taken <= cmt_taken_r; cmt_pc <= cmt_pc_r; cmt_biq <= cmt_biq_r;
    end
    logic [5:0] csr_rs1_preg, csr_rs1_preg_n; logic [1:0] csr_rs1_bank; logic csr_rd_a, csr_rd_b;
    o2_rob #(.RESET_PC(RESET_PC)) rob (
        .clk(clk), .rst(rst), .dv(rob_dv), .e0(rob_e0), .e1(rob_e1),
        .tail(rob_tail), .count(rob_count), .room(rob_room), .empty(rob_empty), .head_idx(rob_head),
        .c0_v(ex0_live && !ex0_isbr), .c0_rob(ex0_rob),
        .c5_v(res_v), .c5_rob(res_rob), .c5_exc(res_exc), .c5_tval(res_next), .c5_taken(res_taken),
        .c1_v(ex1_live && !ex1_ismul), .c1_rob(ex1_rob),
        .c2_v(m2_live), .c2_rob(m2_rob),
        .c3_v(st_v_q), .c3_rob(st_rob_q), .c3_exc(st_exc_q), .c3_cause(st_cause_q), .c3_tval(st_tval_q),
        .c3_replay(st_rpl_q),
        .c4_v(ld_done_v), .c4_rob(ld_done_rob), .c4_exc(ld_exc), .c4_cause(ld_cause), .c4_tval(ld_tval),
        .c4_replay(ld_replay), .c4_replay_io(ld_replay_io),
        .br_kill(br_kill), .br_kill_rob(res_rob),
        .cm_wr(cm_wr_r), .cm_rd0(cm_rd0_r), .cm_rd1(cm_rd1_r), .cm_pdst0(cm_pdst0_r), .cm_pdst1(cm_pdst1_r),
        .cm_pold0(cm_pold0_r), .cm_pold1(cm_pold1_r), .sq_commit(sq_commit_r),
        .cmt_br_valid(cmt_br_valid_r), .cmt_is_cbr(cmt_is_cbr_r), .cmt_taken(cmt_taken_r), .cmt_pc(cmt_pc_r), .cmt_biq(cmt_biq_r),
        .flush(flush), .flush_pc(flush_pc), .replay_set(replay_set), .replay_pc(replay_pc), .fetch_stop(fetch_stop),
        .md_set(md_set), .md_viol(md_viol),
        .csr_rs1_preg(csr_rs1_preg), .csr_rs1_preg_n(csr_rs1_preg_n), .csr_rs1_bank(csr_rs1_bank), .csr_rd_a(csr_rd_a), .csr_rd_b(csr_rd_b),
        .csr_rs1_value(prf_rd[128 +: 32]),
        .csr_wb_v(csr_wb_v), .csr_wb_pd(csr_wb_pd), .csr_wb_data(csr_wb_data),
        .irq_software(irq_software), .irq_timer(irq_timer), .irq_external(irq_external),
        .sq_empty(sq_empty), .slow_busy(slow_pend),
        .dc_clean_req(dc_clean_req), .dc_clean_done(dc_clean_done), .ic_inv(ic_inv), .ic_busy(ic_busy),
        .tr_v(tr_v), .tr_pc0(tr_pc0), .tr_pc1(tr_pc1), .tr_insn0(tr_insn0), .tr_insn1(tr_insn1),
        .tr_wr0(tr_wr0), .tr_wr1(tr_wr1), .tr_rd0(tr_rd0), .tr_rd1(tr_rd1), .tr_pd0(tr_pd0), .tr_pd1(tr_pd1),
        .tr_trap(tr_trap), .tr_irq(tr_irq), .tr_cause(tr_cause), .tr_epc(tr_epc), .tr_csr_old(tr_csr_old),
        .minstret_o(minstret), .mcycle_o(mcycle));

`ifndef SYNTHESIS
    // ---------------------------------------------------------------- statistics
    longint st_cycles = 0, st_mis = 0, st_ok = 0, st_flush = 0, st_replay = 0, st_fq_empty = 0;
    longint st_iss0 = 0, st_iss1 = 0, st_issm = 0, st_c0 = 0, st_c1 = 0, st_c2 = 0;
    longint st_ovr = 0, st_self = 0, st_f2miss = 0;
    longint st_ds_rob = 0, st_ds_iq0 = 0, st_ds_iq1 = 0, st_ds_iqm = 0, st_ds_sq = 0, st_ds_ser = 0, st_ds_fl = 0, st_ds_tag = 0;
    longint st_ds_empty = 0, st_rob_full = 0;
    always_ff @(posedge clk) if (!rst) begin
        st_cycles <= st_cycles + 1;
        if (br_kill) st_mis <= st_mis + 1;
        if (br_ok) st_ok <= st_ok + 1;
        if (flush) st_flush <= st_flush + 1;
        if (replay_set) st_replay <= st_replay + 1;
        if (!fq_v0) st_fq_empty <= st_fq_empty + 1;
        if (iss0_v) st_iss0 <= st_iss0 + 1;
        if (iss1_v) st_iss1 <= st_iss1 + 1;
        if (issm_v) st_issm <= st_issm + 1;
        case (tr_v) 2'b00: st_c0 <= st_c0 + 1; 2'b01: st_c1 <= st_c1 + 1; default: st_c2 <= st_c2 + 1; endcase
        if (frontend.f4_override) st_ovr <= st_ovr + 1;
        if (frontend.f4_self) st_self <= st_self + 1;
        if (frontend.f2_miss) st_f2miss <= st_f2miss + 1;
        if (!rename.d_v0) st_ds_empty <= st_ds_empty + 1;
        if (rename.dis_stall) begin
            if (!(rename.d_v1 ? rob_room[1] : rob_room[0])) st_ds_rob <= st_ds_rob + 1;
            else if ({2'b0, rename.nq0} > iq0_free) st_ds_iq0 <= st_ds_iq0 + 1;
            else if ({2'b0, rename.nq1} > iq1_free) st_ds_iq1 <= st_ds_iq1 + 1;
            else if ({2'b0, rename.nqm} > iqm_free) st_ds_iqm <= st_ds_iqm + 1;
            else if ((rename.nst == 2'd2 && !sq_room[1]) || (rename.nst == 2'd1 && !sq_room[0])) st_ds_sq <= st_ds_sq + 1;
            else st_ds_ser <= st_ds_ser + 1;
        end
        if (rename.r_v0 && !rename.dis_stall && rename.ren_stall) begin
            if (rename.br_in_grp && !rename.tag_avail) st_ds_tag <= st_ds_tag + 1; else st_ds_fl <= st_ds_fl + 1;
        end
    end
    final begin
        $display("O2_STATS cycles=%0d br_ok=%0d br_mis=%0d flush=%0d replay=%0d iss=%0d/%0d/%0d",
            st_cycles, st_ok, st_mis, st_flush, st_replay, st_iss0, st_iss1, st_issm);
        $display("O2_COMMIT c0=%0d c1=%0d c2=%0d", st_c0, st_c1, st_c2);
        $display("O2_FRONT fq_empty=%0d override=%0d noroom=%0d icmiss=%0d dis_empty=%0d",
            st_fq_empty, st_ovr, st_self, st_f2miss, st_ds_empty);
        $display("O2_DSTALL rob=%0d iq0=%0d iq1=%0d iqm=%0d sq=%0d serial=%0d | ren: tag=%0d freelist=%0d",
            st_ds_rob, st_ds_iq0, st_ds_iq1, st_ds_iqm, st_ds_sq, st_ds_ser, st_ds_tag, st_ds_fl);
    end
`endif
endmodule
