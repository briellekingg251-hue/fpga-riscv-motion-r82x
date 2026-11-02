`timescale 1ns/1ps
`include "o2_defs.vh"
// O2 decode / rename / dispatch (DEC -> REN -> DIS).
//   DEC: decode the two fetch-queue heads, pairing rules, -> REN register.
//   REN: RAT lookup, intra-pair bypass, free-list pops, branch checkpoint.
//   DIS: producer-table dependency vectors, IQ steering/allocation, ROB/SQ/BRT
//        allocation, writes.
// Recovery: branch kill restores RAT/free-list head from the checkpoint and
// discards DEC/REN/DIS; full flush restores the committed RAT and head.
module o2_rename (
    input  logic        clk, rst,
    // fetch queue
    input  logic        fq_v0, fq_v1,
    input  logic [31:0] fq_pc0, fq_pc1, fq_insn0, fq_insn1, fq_pred0, fq_pred1,
    input  logic        fq_fault0, fq_fault1,
    input  logic [3:0]  fq_biq0, fq_biq1,
    input  logic [1:0]  fq_k0, fq_k1,
    input  logic        fq_cmt0, fq_cmt1, fq_br0, fq_br1,   // predecoded pairing bits
    output logic [1:0]  fq_pop,
    // recovery
    input  logic        flush,
    input  logic        br_kill, input logic [2:0] br_kill_tag,
    input  logic        br_ok, input logic [2:0] br_ok_tag,
    // commit: rename-state retirement (up to 2 per cycle, slot 0 older)
    input  logic [1:0]  cm_wr,
    input  logic [4:0]  cm_rd0, cm_rd1,
    input  logic [5:0]  cm_pdst0, cm_pdst1, cm_pold0, cm_pold1,
    input  logic        rob_empty,
    // replay (head-only) PC registration
    input  logic        replay_set, input logic [31:0] replay_pc,
    input  logic        md_set,             // memory-order violation replay: train the wait table
    // ROB status
    input  logic [5:0]  rob_tail,        // {wrap, idx}
    input  logic [1:0]  rob_room,        // registered: [0] >= 1 free, [1] >= 2 free
    input  logic [1:0]  sq_room,         // registered: [0] >= 1 free, [1] >= 2 free
    // IQ status / allocation
    input  logic [3:0]  iq0_free, iq1_free, iqm_free,
    input  logic [2:0]  iq0_a0, iq0_a1, iq1_a0, iq1_a1, iqm_a0, iqm_a1,
    input  logic [23:0] wake,
    // SQ status
    input  logic [3:0]  sq_tail,         // {wrap, idx}
    input  logic [3:0]  sq_count,
    input  logic [7:0]  sq_valid,        // allocated entries (incl. committed)
    // dispatch outputs: per-slot fields; iqX_dv[k] = slot k goes to queue X
    output logic [1:0]  iq0_dv, iq1_dv, iqm_dv,
    output logic [38:0] s0_pay, s1_pay,
    output logic [31:0] s0_imm, s1_imm,      // immediates (kept in the core's ROB-indexed table)
    output logic [23:0] s0_dep, s1_dep,
    output logic [1:0]  s0_lat, s1_lat,
    output logic [7:0]  s0_brm, s1_brm,
    output logic [7:0]  s0_sqm, s1_sqm,
    output logic        s0_st, s1_st,
    output logic        s0_head, s1_head,
    output logic [4:0]  s0_rob, s1_rob,
    // dispatch outputs: ROB
    output logic [1:0]  rob_dv,
    output logic [127:0] rob_e0, rob_e1,
    // dispatch outputs: SQ allocation
    output logic [1:0]  sq_alloc,        // count of stores dispatched (0..2)
    // dispatch outputs: branch table (one per cycle)
    output logic        brt_we,
    output logic [2:0]  brt_tag,
    output logic [107:0] brt_data,
    output logic [3:0]  ckpt_sq_tail,    // SQ tail after the branch (for recovery)
    output logic        perf_fe_stall,   // nothing to dispatch (front end did not deliver)
    output logic        perf_be_stall    // a group waits for back-end resources
);
`include "o2_util.vh"
    // =================================================================== DEC
    logic [2:0] fu0, fu1; logic [3:0] op0, op1;
    logic [4:0] rs1_0, rs2_0, rd_0, rs1_1, rs2_1, rd_1;
    logic use1_0, use2_0, wr_0, use1_1, use2_1, wr_1, si_0, si_1, jalr_0, jalr_1, ex_0, ex_1;
    logic [31:0] imm_0, imm_1; logic [3:0] ca_0, ca_1;
    o2_decode dec0 (.pc(fq_pc0), .insn(fq_insn0), .fetch_fault(fq_fault0),
        .fu(fu0), .op(op0), .rs1(rs1_0), .rs2(rs2_0), .rd(rd_0), .use1(use1_0), .use2(use2_0), .wr(wr_0),
        .src2_imm(si_0), .imm(imm_0), .is_jalr(jalr_0), .exc(ex_0), .cause(ca_0));
    o2_decode dec1 (.pc(fq_pc1), .insn(fq_insn1), .fetch_fault(fq_fault1),
        .fu(fu1), .op(op1), .rs1(rs1_1), .rs2(rs2_1), .rd(rd_1), .use1(use1_1), .use2(use2_1), .wr(wr_1),
        .src2_imm(si_1), .imm(imm_1), .is_jalr(jalr_1), .exc(ex_1), .cause(ca_1));
    // pairing: one checkpointed branch per group; commit-executed ops alone
    wire take0 = fq_v0;
    wire take1 = fq_v1 && !fq_cmt0 && !fq_cmt1 && !(fq_br0 && fq_br1);

    // DEC -> REN register
    logic        r_v0, r_v1;
    logic [31:0] r_pc0, r_pc1, r_insn0, r_insn1, r_pred0, r_pred1, r_imm0, r_imm1;
    logic [2:0]  r_fu0, r_fu1; logic [3:0] r_op0, r_op1;
    logic [4:0]  r_rs1_0, r_rs2_0, r_rs1_1, r_rs2_1;
    (* syn_preserve = 1 *) logic [4:0] r_rd0, r_rd1;   // not merged with r_insn (placed near the RAT)
    logic        r_wr0, r_wr1, r_si0, r_si1, r_jalr0, r_jalr1;
    logic [3:0]  r_ca0, r_ca1, r_biq0, r_biq1; logic [1:0] r_k0, r_k1;
    logic        ren_stall;
    wire ren_take = !ren_stall;
    assign fq_pop = (ren_take && !flush && !br_kill) ? ({1'b0, take0} + {1'b0, take0 && take1}) : 2'd0;

    // =================================================================== REN
    logic [5:0] rat [0:31];
    logic [5:0] crat [0:31];
    logic [5:0] fl [0:31];
    logic [5:0] fl_head, fl_tail, fl_chead;        // 6-bit with wrap (32 entries)
    logic [7:0] tag_free;
    (* syn_ramstyle = "lut_ram" *) logic [191:0] ck_rat [0:7];
    logic [5:0] ck_head [0:7];
    logic [7:0] ck_young [0:7];

    wire [5:0] fl_count = fl_tail - fl_head;
    wire need_fl0 = r_v0 && r_wr0;
    wire need_fl1 = r_v1 && r_wr1;
    wire [1:0] need_fl = {1'b0, need_fl0} + {1'b0, need_fl1};
    wire [5:0] new0 = fl[fl_head[4:0]];
    wire [5:0] new1 = fl[need_fl0 ? fl_head[4:0] + 5'd1 : fl_head[4:0]];
    wire br_in_grp = (r_v0 && r_fu0 == `FU_BR) || (r_v1 && r_fu1 == `FU_BR);
    logic [2:0] new_tag; logic tag_avail;
    always_comb begin
        new_tag = pe_lo8(tag_free); tag_avail = |tag_free;
    end
    // renamed sources
    wire [5:0] ps1_0 = rat[r_rs1_0], ps2_0 = rat[r_rs2_0], po_0 = rat[r_rd0];
    wire s1_from0 = r_wr0 && r_rs1_1 == r_rd0 && r_rs1_1 != 5'd0;
    wire s2_from0 = r_wr0 && r_rs2_1 == r_rd0 && r_rs2_1 != 5'd0;
    wire [5:0] ps1_1 = s1_from0 ? new0 : rat[r_rs1_1];
    wire [5:0] ps2_1 = s2_from0 ? new0 : rat[r_rs2_1];
    wire [5:0] po_1 = (r_wr0 && r_rd1 == r_rd0) ? new0 : rat[r_rd1];
    wire [7:0] active_mask = ~tag_free;
    wire br0 = r_v0 && r_fu0 == `FU_BR;
    wire [7:0] brm_0 = active_mask;
    wire [7:0] brm_1 = active_mask | (br0 ? (8'b1 << new_tag) : 8'b0);

    // REN -> DIS register
    logic        d_v0, d_v1;
    logic [31:0] d_pc0, d_pc1, d_insn0, d_insn1, d_pred0, d_pred1, d_imm0, d_imm1;
    logic [2:0]  d_fu0, d_fu1; logic [3:0] d_op0, d_op1;
    logic [4:0]  d_rd0, d_rd1;
    logic        d_wr0, d_wr1, d_si0, d_si1, d_jalr0, d_jalr1;
    logic [3:0]  d_ca0, d_ca1, d_biq0, d_biq1; logic [1:0] d_k0, d_k1;
    logic [5:0]  d_ps1_0, d_ps2_0, d_pd0, d_po0, d_ps1_1, d_ps2_1, d_pd1, d_po1;
    logic        d_s1from0, d_s2from0;
    logic [7:0]  d_brm0, d_brm1;
    logic [2:0]  d_tag;
    logic [1:0]  d_q0, d_q1;
    logic [1:0]  fl_room;                          // registered: [0] >= 1 free, [1] >= 2 free
    logic        dis_stall;
    assign ren_stall = r_v0 && (dis_stall || (need_fl == 2'd2 && !fl_room[1]) || (need_fl == 2'd1 && !fl_room[0]) ||
                                (br_in_grp && !tag_avail));
    // steering for the REN group (balance by the registered IQ free counts)
    logic [1:0] rq0, rq1;
    always_comb begin
        case (r_fu0)
            `FU_BR: rq0 = 2'd0; `FU_MUL: rq0 = 2'd1; `FU_LD, `FU_ST: rq0 = 2'd2; `FU_CMT: rq0 = 2'd3;
            default: rq0 = (iq0_free >= iq1_free) ? 2'd0 : 2'd1;
        endcase
        case (r_fu1)
            `FU_BR: rq1 = 2'd0; `FU_MUL: rq1 = 2'd1; `FU_LD, `FU_ST: rq1 = 2'd2; `FU_CMT: rq1 = 2'd3;
            default: rq1 = (rq0 == 2'd0) ? 2'd1 : (rq0 == 2'd1) ? 2'd0 : (iq0_free >= iq1_free) ? 2'd0 : 2'd1;
        endcase
    end
    (* syn_maxfan = 24 *) wire ren_go = r_v0 && !ren_stall && !flush && !br_kill;
    // checkpoint RAT value (state after the branch; a slot-0 branch excludes slot 1)
    logic [191:0] ck_wd;
    always_comb begin
        for (int i = 0; i < 32; i++) begin
            logic [5:0] v;
            v = rat[i];
            if (need_fl0 && r_rd0 == 5'(i)) v = new0;
            if (!br0 && need_fl1 && r_rd1 == 5'(i)) v = new1;
            ck_wd[6*i +: 6] = v;
        end
    end
    wire ck_we = ren_go && br_in_grp && !flush && !br_kill;
    always_ff @(posedge clk) if (ck_we) ck_rat[new_tag] <= ck_wd;
    wire [191:0] ck_rd = ck_rat[br_kill_tag];

    // =================================================================== DIS
    // producer table: preg -> {valid, column}
    logic [63:0] pt_v;
    logic [4:0]  pt_col [0:63];
    function automatic [23:0] col1h(input [4:0] c);
        col1h = 24'b1 << c;
    endfunction
    // replay (head-only) PCs: loads and stores that went to MMIO (or to a
    // line with a failed refill) issue only at the ROB head next time
    // 14-bit PC tags: a false match only makes an access wait for the ROB head
    logic [13:0] hpc [0:3]; logic [3:0] hpc_v; logic [1:0] hpc_rr;
    wire mem0 = d_fu0 == `FU_LD || d_fu0 == `FU_ST, mem1 = d_fu1 == `FU_LD || d_fu1 == `FU_ST;
    wire hd0 = mem0 && ((hpc_v[0] && hpc[0] == d_pc0[15:2]) || (hpc_v[1] && hpc[1] == d_pc0[15:2]) ||
                        (hpc_v[2] && hpc[2] == d_pc0[15:2]) || (hpc_v[3] && hpc[3] == d_pc0[15:2]));
    wire hd1 = mem1 && ((hpc_v[0] && hpc[0] == d_pc1[15:2]) || (hpc_v[1] && hpc[1] == d_pc1[15:2]) ||
                        (hpc_v[2] && hpc[2] == d_pc1[15:2]) || (hpc_v[3] && hpc[3] == d_pc1[15:2]));
    // steering (decided in REN, registered): 0 = IQ0 (ALU/BR), 1 = IQ1
    // (ALU/MUL), 2 = IQM, 3 = none (commit)
    logic [1:0] q0, q1;
    assign q0 = d_q0; assign q1 = d_q1;
    wire [1:0] nq0 = {1'b0, d_v0 && q0 == 2'd0} + {1'b0, d_v1 && q1 == 2'd0};
    wire [1:0] nq1 = {1'b0, d_v0 && q0 == 2'd1} + {1'b0, d_v1 && q1 == 2'd1};
    wire [1:0] nqm = {1'b0, d_v0 && q0 == 2'd2} + {1'b0, d_v1 && q1 == 2'd2};
    wire st0 = d_v0 && d_fu0 == `FU_ST, st1 = d_v1 && d_fu1 == `FU_ST;
    wire [1:0] nst = {1'b0, st0} + {1'b0, st1};
    wire [1:0] nrob = {1'b0, d_v0} + {1'b0, d_v1};
    logic serial_pend;
    wire cmt_wait = d_v0 && d_fu0 == `FU_CMT && !rob_empty;
    assign dis_stall = d_v0 && (
        ({2'b0, nq0} > iq0_free) || ({2'b0, nq1} > iq1_free) || ({2'b0, nqm} > iqm_free) ||
        !(d_v1 ? rob_room[1] : rob_room[0]) || (nst == 2'd2 && !sq_room[1]) || (nst == 2'd1 && !sq_room[0]) ||
        cmt_wait || serial_pend);
    (* syn_maxfan = 24 *) wire dis_go = d_v0 && !dis_stall && !flush && !br_kill;
    assign perf_fe_stall = !d_v0;
    assign perf_be_stall = dis_stall;
    // allocation slots: first instruction to an IQ takes a0, second takes a1
    wire [2:0] sl0 = (q0 == 2'd0) ? iq0_a0 : (q0 == 2'd1) ? iq1_a0 : iqm_a0;
    wire same_q = d_v0 && q0 == q1;
    wire [2:0] sl1 = (q1 == 2'd0) ? (same_q ? iq0_a1 : iq0_a0) :
                     (q1 == 2'd1) ? (same_q ? iq1_a1 : iq1_a0) : (same_q ? iqm_a1 : iqm_a0);
    wire [4:0] col0 = (q0 == 2'd0 ? 5'd0 : q0 == 2'd1 ? 5'd8 : 5'd16) + {2'b0, sl0};
    wire [4:0] col1 = (q1 == 2'd0 ? 5'd0 : q1 == 2'd1 ? 5'd8 : 5'd16) + {2'b0, sl1};
    // dependency vectors from the producer table
    function automatic [23:0] depv(input [5:0] p);
        depv = (p != 6'd0 && pt_v[p]) ? col1h(pt_col[p]) : 24'b0;
    endfunction
    // register-file bank of an operand: the write port of its producer's pipe
    // (column / 8 = queue; 2'b11 = never written since reset)
    function automatic [1:0] pbank(input [5:0] p);
        logic [1:0] c;
        c = pt_col[p][4:3];
        pbank = (p == 6'd0 || c == 2'b11) ? 2'b00 : c + 2'b01;
    endfunction
    function automatic [1:0] qbank(input [1:0] q);     // producer steered to queue q (3: CSR -> port 2)
        qbank = (q == 2'd0) ? 2'b01 : (q == 2'd1) ? 2'b10 : 2'b11;
    endfunction
    wire [1:0] sb1_0 = pbank(d_ps1_0), sb2_0 = pbank(d_ps2_0);
    wire [1:0] sb1_1 = d_s1from0 ? qbank(q0) : pbank(d_ps1_1);
    wire [1:0] sb2_1 = d_s2from0 ? qbank(q0) : pbank(d_ps2_1);
    // The producer table is cleared by the registered wake (wake_q), so a
    // table entry may still be set for a column that fired last cycle:
    // table-derived bits are masked with wake_q as well. A slot-0 producer of
    // this group is never masked by wake_q (its column may have just fired for
    // the previous occupant).
    logic [23:0] wake_q;
    // (the current cycle's wake is applied by the issue queue on allocation)
    wire [23:0] dep0 = (depv(d_ps1_0) | depv(d_ps2_0)) & ~wake_q;
    wire [23:0] dep1 = (d_s1from0 ? col1h(col0) : (depv(d_ps1_1) & ~wake_q)) |
                       (d_s2from0 ? col1h(col0) : (depv(d_ps2_1) & ~wake_q));
    // wake latency class (3: head-only memory op, completes via the LSU slow path)
    function automatic [1:0] latc(input [2:0] fu, input [3:0] op, input hd);
        if (fu == `FU_LD) latc = hd ? 2'd3 : 2'd1;
        else if (fu == `FU_ST) latc = hd ? 2'd3 : 2'd0;
        else if (fu == `FU_MUL) latc = 2'd2;
        else latc = 2'd0;
    endfunction
    wire [5:0] rob_i0 = rob_tail;
    wire [5:0] rob_i1 = rob_tail + 6'd1;
    wire [3:0] sq_i0 = sq_tail;
    wire [3:0] sq_i1 = sq_tail + {3'b0, st0};
    // older-store mask for loads: allocated SQ entries plus a store in slot 0
    wire [7:0] sqm_0 = sq_valid;
    wire [7:0] sqm_1 = sq_valid | (st0 ? (8'b1 << sq_i0[2:0]) : 8'b0);
    // payload: {op4, si, imm32, ps1, ps2, pd, wr, brtag3, sqidx3, jalr, fu3, spare}
    function automatic [38:0] mkpay(input [1:0] b1, b2, input [3:0] op, input si,
                                    input [5:0] s1, s2, pd, input wr, input [2:0] tag, input [2:0] sqi,
                                    input jalr, input [2:0] fu, input wt);
        mkpay = {b1, b2, op, si, s1, s2, pd, wr, tag, sqi, jalr, fu, wt};
    endfunction
    // load-wait table: loads that caused a memory-order violation wait for
    // older store addresses (cleared every 64K cycles)
    logic [63:0] lwt; logic [15:0] lwt_age;
    wire wt0 = lwt[d_pc0[7:2]], wt1 = lwt[d_pc1[7:2]];
    wire [38:0] pay0 = mkpay(sb1_0, sb2_0, d_op0, d_si0, d_ps1_0, d_ps2_0, d_pd0, d_wr0, d_tag, sq_i0[2:0], d_jalr0, d_fu0, wt0);
    wire [38:0] pay1 = mkpay(sb1_1, sb2_1, d_op1, d_si1, d_ps1_1, d_ps2_1, d_pd1, d_wr1, d_tag, sq_i1[2:0], d_jalr1, d_fu1, wt1);
    assign s0_imm = d_imm0; assign s1_imm = d_imm1;
    always_comb begin
        logic a0, b0, a1, b1, am, bm;
        a0 = d_v0 && q0 == 2'd0; b0 = d_v1 && q1 == 2'd0;
        a1 = d_v0 && q0 == 2'd1; b1 = d_v1 && q1 == 2'd1;
        am = d_v0 && q0 == 2'd2; bm = d_v1 && q1 == 2'd2;
        iq0_dv = {dis_go && b0, dis_go && a0};
        iq1_dv = {dis_go && b1, dis_go && a1};
        iqm_dv = {dis_go && bm, dis_go && am};
        s0_pay = pay0; s1_pay = pay1;
        s0_dep = dep0; s1_dep = dep1;
        s0_lat = latc(d_fu0, d_op0, hd0); s1_lat = latc(d_fu1, d_op1, hd1);
        s0_brm = br_ok ? (d_brm0 & ~(8'b1 << br_ok_tag)) : d_brm0;
        s1_brm = br_ok ? (d_brm1 & ~(8'b1 << br_ok_tag)) : d_brm1;
        s0_rob = rob_i0[4:0]; s1_rob = rob_i1[4:0];
        s0_sqm = sqm_0; s1_sqm = sqm_1;
        s0_st = st0; s1_st = st1;
        s0_head = hd0; s1_head = hd1;
    end
    // ROB entry: {pc32, insn32, pred32? no: rd5, wr, pd6, po6, fu3, op4, exc, cause4, sqidx3,
    //             biq4, k2, brtag3, jalr, pad}
    function automatic [127:0] mkrob(input [31:0] pc, input [31:0] insn, input [4:0] rd, input wr,
        input [5:0] pd, input [5:0] po, input [2:0] fu, input [3:0] op, input [3:0] ca,
        input [2:0] sqi, input [3:0] biq, input [2:0] tag, input [5:0] ps1, input [1:0] sb1);
        mkrob = {pc, insn, rd, wr, pd, po, fu, op, ca, sqi, biq, tag, ps1, sb1, 17'b0};
    endfunction
    always_comb begin
        rob_dv = {dis_go && d_v1, dis_go};
        rob_e0 = mkrob(d_pc0, d_insn0, d_rd0, d_wr0, d_pd0, d_po0, d_fu0, d_op0, d_ca0, sq_i0[2:0], d_biq0, d_tag, d_ps1_0, sb1_0);
        rob_e1 = mkrob(d_pc1, d_insn1, d_rd1, d_wr1, d_pd1, d_po1, d_fu1, d_op1, d_ca1, sq_i1[2:0], d_biq1, d_tag, d_ps1_1, sb1_1);
        sq_alloc = dis_go ? nst : 2'd0;
        // branch table: {pc32, pred32, imm32, biq4, k2, jalr, rob5}
        brt_we = dis_go && ((d_fu0 == `FU_BR) || (d_v1 && d_fu1 == `FU_BR));
        brt_tag = d_tag;
        if (d_fu0 == `FU_BR)
            brt_data = {d_pc0, d_pred0, d_imm0, d_biq0, d_k0, d_jalr0, rob_i0[4:0]};
        else
            brt_data = {d_pc1, d_pred1, d_imm1, d_biq1, d_k1, d_jalr1, rob_i1[4:0]};
        // SQ tail after the stores older than the branch (a slot-1 store is younger
        // than a slot-0 branch and must be discarded on its mispredict)
        ckpt_sq_tail = sq_tail + ((d_fu0 == `FU_BR) ? 4'd0 : {3'b0, st0});
    end

    // =================================================================== sequential
    // DEC -> REN
    always_ff @(posedge clk) begin
        if (rst || flush || br_kill) begin
            r_v0 <= 1'b0; r_v1 <= 1'b0;
        end else if (ren_take) begin
            r_v0 <= take0; r_v1 <= take0 && take1;
            r_pc0 <= fq_pc0; r_pc1 <= fq_pc1; r_insn0 <= fq_insn0; r_insn1 <= fq_insn1;
            r_pred0 <= fq_pred0; r_pred1 <= fq_pred1; r_imm0 <= imm_0; r_imm1 <= imm_1;
            r_fu0 <= fu0; r_fu1 <= fu1; r_op0 <= op0; r_op1 <= op1;
            r_rs1_0 <= rs1_0; r_rs2_0 <= rs2_0; r_rd0 <= rd_0;
            r_rs1_1 <= rs1_1; r_rs2_1 <= rs2_1; r_rd1 <= rd_1;
            r_wr0 <= wr_0; r_wr1 <= wr_1; r_si0 <= si_0; r_si1 <= si_1;
            r_jalr0 <= jalr_0; r_jalr1 <= jalr_1; r_ca0 <= ca_0; r_ca1 <= ca_1;
            r_biq0 <= fq_biq0; r_biq1 <= fq_biq1; r_k0 <= fq_k0; r_k1 <= fq_k1;
        end
    end
    // REN state
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 32; i++) begin rat[i] <= 6'(i); crat[i] <= 6'(i); fl[i] <= 6'(32 + i); end
            fl_head <= 6'd0; fl_tail <= 6'd32; fl_chead <= 6'd0; fl_room <= 2'b11;
            tag_free <= 8'hff;
        end else begin
            // commit-side
            begin
                logic [5:0] nt, nch;
                nt = fl_tail; nch = fl_chead;
                if (cm_wr[0]) begin crat[cm_rd0] <= cm_pdst0; fl[nt[4:0]] <= cm_pold0; nt = nt + 6'd1; nch = nch + 6'd1; end
                if (cm_wr[1]) begin crat[cm_rd1] <= cm_pdst1; fl[nt[4:0]] <= cm_pold1; nt = nt + 6'd1; nch = nch + 6'd1; end
                if (cm_wr[0] && cm_wr[1] && cm_rd0 == cm_rd1) crat[cm_rd1] <= cm_pdst1;
                fl_tail <= nt; fl_chead <= nch;
                // pushes this cycle and recovery are seen one cycle late (conservative)
                begin
                    logic [5:0] fc;
                    fc = fl_tail - (fl_head + (ren_go ? {4'b0, need_fl} : 6'd0));
                    fl_room <= {fc >= 6'd2, fc >= 6'd1};
                end
                if (flush) begin
                    fl_head <= nch;
                    for (int i = 0; i < 32; i++) rat[i] <= crat[i];
                    if (cm_wr[0]) rat[cm_rd0] <= cm_pdst0;
                    if (cm_wr[1]) rat[cm_rd1] <= cm_pdst1;
                    tag_free <= 8'hff;
                end else if (br_kill) begin
                    fl_head <= ck_head[br_kill_tag];
                    for (int i = 0; i < 32; i++) rat[i] <= ck_rd[6*i +: 6];
                    tag_free <= tag_free | ck_young[br_kill_tag] | (8'b1 << br_kill_tag);
                end else begin
                    logic [7:0] tf;
                    tf = tag_free;
                    if (br_ok) tf[br_ok_tag] = 1'b1;
                    if (ren_go) begin
                        fl_head <= fl_head + {4'b0, need_fl};
                        if (need_fl0) rat[r_rd0] <= new0;
                        if (need_fl1) rat[r_rd1] <= new1;
                        if (br_in_grp) begin
                            tf[new_tag] = 1'b0;
                            // checkpoint: state after the branch (slot 0 branch excludes slot 1)

                            ck_head[new_tag] <= fl_head + {5'b0, need_fl0} + {5'b0, !br0 && need_fl1};
                            ck_young[new_tag] <= 8'b0;
                            for (int t = 0; t < 8; t++) if (!tag_free[t]) ck_young[t][new_tag] <= 1'b1;
                        end
                    end
                    tag_free <= tf;
                end
            end
        end
    end
    // REN -> DIS
    always_ff @(posedge clk) begin
        if (rst || flush || br_kill) begin
            d_v0 <= 1'b0; d_v1 <= 1'b0;
        end else if (!dis_stall) begin
            d_v0 <= ren_go; d_v1 <= ren_go && r_v1;
            d_pc0 <= r_pc0; d_pc1 <= r_pc1; d_insn0 <= r_insn0; d_insn1 <= r_insn1;
            d_pred0 <= r_pred0; d_pred1 <= r_pred1; d_imm0 <= r_imm0; d_imm1 <= r_imm1;
            d_fu0 <= r_fu0; d_fu1 <= r_fu1; d_op0 <= r_op0; d_op1 <= r_op1;
            d_rd0 <= r_rd0; d_rd1 <= r_rd1; d_wr0 <= r_wr0; d_wr1 <= r_wr1;
            d_si0 <= r_si0; d_si1 <= r_si1; d_jalr0 <= r_jalr0; d_jalr1 <= r_jalr1;
            d_ca0 <= r_ca0; d_ca1 <= r_ca1; d_biq0 <= r_biq0; d_biq1 <= r_biq1; d_k0 <= r_k0; d_k1 <= r_k1;
            d_ps1_0 <= ps1_0; d_ps2_0 <= ps2_0; d_pd0 <= need_fl0 ? new0 : 6'd0; d_po0 <= po_0;
            d_ps1_1 <= ps1_1; d_ps2_1 <= ps2_1; d_pd1 <= need_fl1 ? new1 : 6'd0; d_po1 <= po_1;
            d_s1from0 <= s1_from0; d_s2from0 <= s2_from0;
            d_brm0 <= br_ok ? (brm_0 & ~(8'b1 << br_ok_tag)) : brm_0;
            d_brm1 <= br_ok ? (brm_1 & ~(8'b1 << br_ok_tag)) : brm_1;
            d_tag <= new_tag; d_q0 <= rq0; d_q1 <= rq1;
        end else if (br_ok) begin
            d_brm0[br_ok_tag] <= 1'b0; d_brm1[br_ok_tag] <= 1'b0;
        end
    end
    // DIS state: producer table, serialization, head-only PCs
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            pt_v <= 64'b0; wake_q <= 24'b0;
            if (rst) for (int p = 0; p < 64; p++) pt_col[p] <= 5'b11000;
        end else begin
            logic [63:0] nv;
            wake_q <= wake;
            for (int p = 0; p < 64; p++) nv[p] = pt_v[p] && !wake_q[pt_col[p]];
            // Written for the group in DIS every cycle, also while it stalls
            // (no dis_go in the enable): a new destination register is not
            // visible to any other group before this group dispatches, and a
            // killed group's register is rewritten by its next producer.
            if (d_v0 && d_wr0) begin
                nv[d_pd0] = q0 != 2'd3;
                pt_col[d_pd0] <= (q0 == 2'd3) ? 5'b10000 : col0;   // CSR results use port 2
            end
            if (d_v1 && d_wr1) begin
                nv[d_pd1] = q1 != 2'd3;
                pt_col[d_pd1] <= (q1 == 2'd3) ? 5'b10000 : col1;
            end
            pt_v <= nv;
        end
    end
    always_ff @(posedge clk) begin
        if (rst) begin serial_pend <= 1'b0; hpc_v <= 4'b0; hpc_rr <= 2'd0; lwt <= 64'b0; lwt_age <= 16'b0; end
        else begin
            if (flush || rob_empty) serial_pend <= 1'b0;
            if (dis_go && d_fu0 == `FU_CMT) serial_pend <= 1'b1;
            lwt_age <= lwt_age + 16'd1;
            if (lwt_age == 16'hffff) lwt <= 64'b0;
            else if (md_set) lwt[replay_pc[7:2]] <= 1'b1;
            if (replay_set) begin
                hpc[hpc_rr] <= replay_pc[15:2]; hpc_v[hpc_rr] <= 1'b1; hpc_rr <= hpc_rr + 2'd1;
            end
        end
    end
`ifndef SYNTHESIS
    always_ff @(posedge clk) if (!rst) begin
        if (fq_v0) assert (fq_cmt0 == (fu0 == `FU_CMT) && fq_br0 == (fu0 == `FU_BR)) else $fatal(1, "FQ_PREDECODE0");
        if (fq_v1) assert (fq_cmt1 == (fu1 == `FU_CMT) && fq_br1 == (fu1 == `FU_BR)) else $fatal(1, "FQ_PREDECODE1");
    end
`endif
endmodule
