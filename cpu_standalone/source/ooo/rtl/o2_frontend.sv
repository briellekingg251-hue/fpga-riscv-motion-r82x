`timescale 1ns/1ps
`include "o2_defs.vh"
// O2 front end.
//   F1  pc1: next-line predictor (NLP, tagless) selects the next fetch PC;
//       I$ lookup and TAGE table reads use pc1 and the speculative GHR.
//   F2  I$ hit/data, TAGE entries; base counters and indirect BTB read.
//       Miss -> refill, refetch pc2.
//   F3  predecode the 16B block, per-slot direction, per-slot targets.
//   F4  final next PC (TAGE/JAL/RAS/iBTB), override F1 if the NLP was wrong,
//       enqueue the group (up to the first predicted-taken control transfer),
//       update GHR, NLP, RAS, and allocate a branch-info (BIQ) entry.
// A group holds at most 4 instructions of one aligned 16B block.
module o2_frontend #(
    parameter [31:0] RESET_PC = 32'h80000000
) (
    input  logic        clk, rst,
    // backend redirects (registered by the backend)
    input  logic        be_flush,            // full flush (commit-time)
    input  logic [31:0] be_flush_pc,
    input  logic        be_mispredict,
    input  logic [31:0] be_mis_pc,
    input  logic [3:0]  be_mis_biq,
    input  logic [1:0]  be_mis_k,
    input  logic        be_mis_is_cbr,
    input  logic        be_mis_taken,
    input  logic        fetch_stop,          // e.g. FENCE.I in progress
    // commit-side training
    input  logic        cmt_br_valid,
    input  logic        cmt_is_cbr,
    input  logic        cmt_taken,
    input  logic [31:0] cmt_pc,
    input  logic [3:0]  cmt_biq,
    // indirect target training (pipe 0 resolution)
    input  logic        ib_train,
    input  logic [31:0] ib_pc, ib_target,
    // I$ interface
    output logic [31:0] ic_f1_pc,
    input  logic [31:0] ic_f2_pc,
    input  logic        ic_f2_hit,
    input  logic        ic_f2_cacheable,
    input  logic        ic_f2_fault,         // the line's refill had a bus error
    input  logic [127:0] ic_f2_block,
    output logic        ic_refill_req,
    input  logic        ic_busy,
    // fetch queue output (2 per cycle)
    output logic        fq_v0, fq_v1,
    output logic [31:0] fq_pc0, fq_pc1, fq_insn0, fq_insn1, fq_pred0, fq_pred1,
    output logic        fq_fault0, fq_fault1,
    output logic [3:0]  fq_biq0, fq_biq1,
    output logic [1:0]  fq_k0, fq_k1,
    output logic        fq_cmt0, fq_cmt1,      // predecoded: executes at commit (or faults)
    output logic        fq_br0, fq_br1,        // predecoded: checkpointed branch
    input  logic [1:0]  fq_pop
);
    // ------------------------------------------------------------ parameters
    localparam integer NLPW = 13;
    localparam integer NTB = 15;            // NLP stores target[NTB+1:2] (128 KB code window)
    localparam integer TI = 10, TT = 11;    // TAGE index / tag bits
    localparam integer TW = TT + 2 + 12;    // tag, u, 4x3 counters
    localparam integer H0 = 4, H1 = 10, H2 = 25, H3 = 64;
    localparam integer FQN = 32;            // fetch queue entries (4 banks of FQN/4)
    localparam integer RASN = 8;

    function automatic [TI-1:0] fold9(input [63:0] g, input integer len);
        integer k; logic [TI-1:0] f;
        begin f = '0; for (k = 0; k < 64; k++) if (k < len) f[k % TI] = f[k % TI] ^ g[k]; fold9 = f; end
    endfunction
    function automatic [TT-1:0] foldt(input [63:0] g, input integer len);   // history folded to TT bits
        integer k; logic [TT-1:0] f;
        begin f = '0; for (k = 0; k < 64; k++) if (k < len) f[k % TT] = f[k % TT] ^ g[k]; foldt = f; end
    endfunction
    function automatic [TT-2:0] fold8(input [63:0] g, input integer len);
        integer k; logic [TT-2:0] f;
        begin f = '0; for (k = 0; k < 64; k++) if (k < len) f[k % (TT-1)] = f[k % (TT-1)] ^ g[k]; fold8 = f; end
    endfunction
    function automatic [TI-1:0] tidx(input [31:0] pc, input [63:0] g, input integer len);
        logic [27:0] bp;
        begin bp = pc[31:4]; tidx = bp[TI-1:0] ^ bp[2*TI-1:TI] ^ fold9(g, len); end
    endfunction
    function automatic [TT-1:0] ttag(input [31:0] pc, input [63:0] g, input integer len);
        logic [27:0] bp;
        begin bp = pc[31:4]; ttag = bp[TT-1:0] ^ foldt(g, len) ^ {fold8(g, len), 1'b0}; end
    endfunction
    function automatic [1:0] sat2(input [1:0] c, input t);
        sat2 = t ? ((c == 2'd3) ? 2'd3 : c + 2'd1) : ((c == 2'd0) ? 2'd0 : c - 2'd1);
    endfunction

    // ------------------------------------------------------------ state
    logic [31:0] pc1;
    logic        v1;
    logic [63:0] ghr_spec, ghr_commit;
    logic        refetch_wait;          // waiting for I$ refill
    logic [TI:0]   tinit;               // table reset walk
    // NLP contents only steer prediction (F4 corrects any entry), so there is
    // no reset walk: the RAM powers up zeroed and stale entries are harmless.
    wire nlp_ready = 1'b1;
    wire tinit_busy = !tinit[TI];

    logic kill_f4;                      // F4 redirected F1 (override or no room)
    logic [31:0] f4_redirect_pc;
    logic f2_miss;
    wire be_any = be_flush || be_mispredict;

    // ------------------------------------------------------------ NLP (F1)
    // entry {conf, valid, target[NTB+1:2]}; upper target bits come from pc1.
    // A confident entry survives one disagreement (hysteresis).
    // One block RAM read with the *next* fetch PC, so the entry for pc1 is at
    // its output while pc1 is in F1 (the F1 loop is RAM output -> next-PC mux
    // -> RAM address).
    logic [NTB+1:0] nlp [0:(1<<NLPW)-1];
    logic [NTB+1:0] nlp_q;
    wire [31:0] pc1_next;
    always_ff @(posedge clk) nlp_q <= nlp[rst ? RESET_PC[NLPW+1:2] : pc1_next[NLPW+1:2]];
    wire [31:0] seq_next1 = {pc1[31:4] + 28'd1, 4'b0};
    wire [31:0] nlp_next = nlp_q[NTB] ? {pc1[31:NTB+2], nlp_q[NTB-1:0], 2'b00} : seq_next1;
    wire nlp_c1 = nlp_q[NTB+1];
    logic nlp_we; logic [NLPW-1:0] nlp_widx; logic [NTB+1:0] nlp_wdata;
    always_ff @(posedge clk) if (nlp_we) nlp[nlp_widx] <= nlp_wdata;
`ifndef SYNTHESIS
    initial for (int i = 0; i < (1 << NLPW); i++) nlp[i] = '0;
`endif

    // ------------------------------------------------------------ TAGE tables
    // Prediction copy (read in F1) and update copy (read by the update unit);
    // both receive identical writes.
    logic [TW-1:0] tp0 [0:(1<<TI)-1]; logic [TW-1:0] tp1 [0:(1<<TI)-1];
    logic [TW-1:0] tp2 [0:(1<<TI)-1]; logic [TW-1:0] tp3 [0:(1<<TI)-1];
    logic [TW-1:0] tu0 [0:(1<<TI)-1]; logic [TW-1:0] tu1 [0:(1<<TI)-1];
    logic [TW-1:0] tu2 [0:(1<<TI)-1]; logic [TW-1:0] tu3 [0:(1<<TI)-1];
    logic [TI-1:0] f1_idx0, f1_idx1, f1_idx2, f1_idx3;
    logic [TT-1:0] f1_tag0, f1_tag1, f1_tag2, f1_tag3;
    always_comb begin
        f1_idx0 = tidx(pc1, ghr_spec, H0); f1_tag0 = ttag(pc1, ghr_spec, H0);
        f1_idx1 = tidx(pc1, ghr_spec, H1); f1_tag1 = ttag(pc1, ghr_spec, H1);
        f1_idx2 = tidx(pc1, ghr_spec, H2); f1_tag2 = ttag(pc1, ghr_spec, H2);
        f1_idx3 = tidx(pc1, ghr_spec, H3); f1_tag3 = ttag(pc1, ghr_spec, H3);
    end
    logic [TW-1:0] te2_0, te2_1, te2_2, te2_3;
    logic [3:0]    tw_en;
    logic [TI-1:0] tw_idx0, tw_idx1, tw_idx2, tw_idx3;
    logic [TW-1:0] tw_d0, tw_d1, tw_d2, tw_d3;
    logic [TI-1:0] tr_idx0, tr_idx1, tr_idx2, tr_idx3;
    logic [TW-1:0] tue0, tue1, tue2, tue3;
    always_ff @(posedge clk) begin
        te2_0 <= tp0[f1_idx0]; te2_1 <= tp1[f1_idx1]; te2_2 <= tp2[f1_idx2]; te2_3 <= tp3[f1_idx3];
        tue0 <= tu0[tr_idx0]; tue1 <= tu1[tr_idx1]; tue2 <= tu2[tr_idx2]; tue3 <= tu3[tr_idx3];
        if (tinit_busy) begin
            tp0[tinit[TI-1:0]] <= '0; tp1[tinit[TI-1:0]] <= '0; tp2[tinit[TI-1:0]] <= '0; tp3[tinit[TI-1:0]] <= '0;
            tu0[tinit[TI-1:0]] <= '0; tu1[tinit[TI-1:0]] <= '0; tu2[tinit[TI-1:0]] <= '0; tu3[tinit[TI-1:0]] <= '0;
        end else begin
            if (tw_en[0]) begin tp0[tw_idx0] <= tw_d0; tu0[tw_idx0] <= tw_d0; end
            if (tw_en[1]) begin tp1[tw_idx1] <= tw_d1; tu1[tw_idx1] <= tw_d1; end
            if (tw_en[2]) begin tp2[tw_idx2] <= tw_d2; tu2[tw_idx2] <= tw_d2; end
            if (tw_en[3]) begin tp3[tw_idx3] <= tw_d3; tu3[tw_idx3] <= tw_d3; end
        end
    end
    // base bimodal: 4 slot banks x 512, read in F2 and by the update unit
    (* syn_ramstyle = "lut_ram" *) logic [1:0] bs0 [0:511];
    (* syn_ramstyle = "lut_ram" *) logic [1:0] bs1 [0:511];
    (* syn_ramstyle = "lut_ram" *) logic [1:0] bs2 [0:511];
    (* syn_ramstyle = "lut_ram" *) logic [1:0] bs3 [0:511];
    logic bw_en; logic [10:0] bw_idx; logic [1:0] bw_data;
    always_ff @(posedge clk) begin
        if (tinit_busy) begin
            bs0[tinit[8:0]] <= 2'b01; bs1[tinit[8:0]] <= 2'b01; bs2[tinit[8:0]] <= 2'b01; bs3[tinit[8:0]] <= 2'b01;
        end else if (bw_en) begin
            case (bw_idx[1:0])
                2'd0: bs0[bw_idx[10:2]] <= bw_data; 2'd1: bs1[bw_idx[10:2]] <= bw_data;
                2'd2: bs2[bw_idx[10:2]] <= bw_data; default: bs3[bw_idx[10:2]] <= bw_data;
            endcase
        end
    end
    // indirect BTB: 4 slot banks x 16 entries {valid, tag8, target30}
    (* syn_ramstyle = "lut_ram" *) logic [38:0] ib0 [0:15];
    (* syn_ramstyle = "lut_ram" *) logic [38:0] ib1 [0:15];
    (* syn_ramstyle = "lut_ram" *) logic [38:0] ib2 [0:15];
    (* syn_ramstyle = "lut_ram" *) logic [38:0] ib3 [0:15];
    wire [38:0] ib_wdata = {1'b1, ib_pc[15:8], ib_target[31:2]};
    always_ff @(posedge clk) begin
        if (tinit_busy) begin
            ib0[tinit[3:0]] <= '0; ib1[tinit[3:0]] <= '0; ib2[tinit[3:0]] <= '0; ib3[tinit[3:0]] <= '0;
        end else if (ib_train) begin
            case (ib_pc[3:2])
                2'd0: ib0[ib_pc[7:4]] <= ib_wdata; 2'd1: ib1[ib_pc[7:4]] <= ib_wdata;
                2'd2: ib2[ib_pc[7:4]] <= ib_wdata; default: ib3[ib_pc[7:4]] <= ib_wdata;
            endcase
        end
    end

    // ------------------------------------------------------------ F2
    logic        v2;
    logic [31:0] nlp2;                 // successor PC fetched after this group
    logic        nlpc2, nlpc3, nlpc3b, nlpc4;   // NLP entry confidence
    logic [TT-1:0] tag2_0, tag2_1, tag2_2, tag2_3;
    logic [TI-1:0] idx2_0, idx2_1, idx2_2, idx2_3;
    always_ff @(posedge clk) begin
        if (rst) v2 <= 1'b0;
        else v2 <= v1 && !be_any && !kill_f4 && !f2_miss;
        nlp2 <= nlp_next; nlpc2 <= nlp_c1;
        tag2_0 <= f1_tag0; tag2_1 <= f1_tag1; tag2_2 <= f1_tag2; tag2_3 <= f1_tag3;
        idx2_0 <= f1_idx0; idx2_1 <= f1_idx1; idx2_2 <= f1_idx2; idx2_3 <= f1_idx3;
    end
    assign f2_miss = v2 && ic_f2_cacheable && !ic_f2_hit && !be_any && !kill_f4;
    assign ic_refill_req = f2_miss && !ic_busy;
    wire f2_good = v2 && !f2_miss && !be_any && !kill_f4;
    wire [1:0] base2_0 = bs0[ic_f2_pc[12:4]], base2_1 = bs1[ic_f2_pc[12:4]];
    wire [1:0] base2_2 = bs2[ic_f2_pc[12:4]], base2_3 = bs3[ic_f2_pc[12:4]];
    wire [38:0] ibe2_0 = ib0[ic_f2_pc[7:4]], ibe2_1 = ib1[ic_f2_pc[7:4]];
    wire [38:0] ibe2_2 = ib2[ic_f2_pc[7:4]], ibe2_3 = ib3[ic_f2_pc[7:4]];

    // ------------------------------------------------------------ F3
    logic        v3, fault3;
    logic [31:0] pc3, nlp3;
    logic [127:0] blk3;
    logic [4*TW-1:0] te3;
    logic [4*TT-1:0] tag3;
    logic [4*TI-1:0] idx3;
    logic [7:0]  base3;
    logic [4*39-1:0] ibe3;
    logic [3:0]  hit3;          // tag hits, compared at the F2 table outputs
    always_ff @(posedge clk) begin
        if (rst) v3 <= 1'b0;
        else v3 <= f2_good;
        pc3 <= ic_f2_pc; nlp3 <= nlp2; nlpc3 <= nlpc2;
        fault3 <= !ic_f2_cacheable || ic_f2_fault;     // instruction access fault
        blk3 <= ic_f2_block;
        te3 <= {te2_3, te2_2, te2_1, te2_0};
        hit3 <= {te2_3[TW-1 -: TT] == tag2_3, te2_2[TW-1 -: TT] == tag2_2,
                 te2_1[TW-1 -: TT] == tag2_1, te2_0[TW-1 -: TT] == tag2_0};
        tag3 <= {tag2_3, tag2_2, tag2_1, tag2_0};
        idx3 <= {idx2_3, idx2_2, idx2_1, idx2_0};
        base3 <= {base2_3, base2_2, base2_1, base2_0};
        ibe3 <= {ibe2_3, ibe2_2, ibe2_1, ibe2_0};
    end
    wire f3_live = v3 && !be_any && !kill_f4;

    // provider / alternate component (highest / second highest tag match)
    logic prov_v, alt_v; logic [1:0] prov_i, alt_i;
    always_comb begin
        prov_v = |hit3;
        prov_i = hit3[3] ? 2'd3 : hit3[2] ? 2'd2 : hit3[1] ? 2'd1 : 2'd0;
        alt_v = 1'b0; alt_i = 2'd0;
        case (prov_i)
            2'd3: begin alt_v = |hit3[2:0]; alt_i = hit3[2] ? 2'd2 : hit3[1] ? 2'd1 : 2'd0; end
            2'd2: begin alt_v = |hit3[1:0]; alt_i = hit3[1] ? 2'd1 : 2'd0; end
            2'd1: begin alt_v = hit3[0]; alt_i = 2'd0; end
            default: begin alt_v = 1'b0; alt_i = 2'd0; end
        endcase
    end
    wire [TW-1:0] prov_e = te3[TW*prov_i +: TW];
    wire [TW-1:0] alt_e = te3[TW*alt_i +: TW];
    wire prov_u0 = prov_e[13:12] == 2'd0;

    logic [3:0] s_valid, s_cbr, s_jal, s_jalr, s_call, s_ret, s_pred, s_taken;
    logic [31:0] s_target [0:3];
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            logic [31:0] ins; logic [6:0] o; logic [4:0] rd, rs1; logic rdl, rs1l;
            logic [31:0] spc, imm;
            logic [2:0] cp, ca; logic pp, ap, bp, wk;
            ins = blk3[32*i +: 32];
            o = ins[6:0]; rd = ins[11:7]; rs1 = ins[19:15];
            rdl = rd == 5'd1 || rd == 5'd5; rs1l = rs1 == 5'd1 || rs1 == 5'd5;
            s_valid[i] = (2'(i) >= pc3[3:2]) && !fault3;
            s_cbr[i] = o == 7'h63;
            s_jal[i] = o == 7'h6f;
            s_jalr[i] = o == 7'h67;
            s_call[i] = (s_jal[i] || s_jalr[i]) && rdl;
            s_ret[i] = s_jalr[i] && rs1l && (!rdl || rd != rs1);
            spc = {pc3[31:4], 2'(i), 2'b00};
            imm = s_jal[i] ? {{11{ins[31]}}, ins[31], ins[19:12], ins[20], ins[30:21], 1'b0}
                           : {{19{ins[31]}}, ins[31], ins[7], ins[30:25], ins[11:8], 1'b0};
            s_target[i] = spc + imm;
            bp = base3[2*i + 1];
            cp = prov_e[3*i +: 3];
            ca = alt_e[3*i +: 3];
            pp = prov_v ? !cp[2] : bp;
            ap = alt_v ? !ca[2] : bp;
            wk = prov_v && (cp == 3'd0 || cp == 3'b111) && prov_u0;
            s_pred[i] = prov_v ? (wk ? ap : pp) : bp;
            s_taken[i] = s_valid[i] && ((s_cbr[i] && s_pred[i]) || s_jal[i] || s_jalr[i]);
        end
    end
    // ------------------------------------------------------------ F3b
    // registered per-slot predictions/targets; pick the first taken slot
    logic v3b, fault3b; logic [31:0] pc3b, nlp3b; logic [127:0] blk3b;
    logic [3:0] tks3b, valid3b, cbr3b, jalr3b, call3b, ret3b;
    logic [31:0] tgt3b [0:3]; logic [4*39-1:0] ibe3b; logic [4*TI-1:0] idx3b; logic [4*TT-1:0] tag3b;
    always_ff @(posedge clk) begin
        if (rst) v3b <= 1'b0; else v3b <= f3_live;
        pc3b <= pc3; nlp3b <= nlp3; nlpc3b <= nlpc3; fault3b <= fault3; blk3b <= blk3;
        tks3b <= s_taken; valid3b <= s_valid; cbr3b <= s_cbr; jalr3b <= s_jalr; call3b <= s_call; ret3b <= s_ret;
        for (int i = 0; i < 4; i++) tgt3b[i] <= s_target[i];
        ibe3b <= ibe3; idx3b <= idx3; tag3b <= tag3;
    end
    wire f3b_live = v3b && !be_any && !kill_f4;
    // one-hot first taken slot (arithmetic isolation; no priority muxes)
    wire [3:0] toh = tks3b & (~tks3b + 4'd1);
    wire tk3 = |tks3b;
    wire [1:0] end3 = tk3 ? {toh[2] | toh[3], toh[1] | toh[3]} : 2'd3;
    wire [3:0] s_upto = tk3 ? ((toh - 4'd1) | toh) : 4'b1111;
    logic [31:0] tgt_sel; logic [38:0] ib_sel;
    always_comb begin
        tgt_sel = 32'b0; ib_sel = 39'b0;
        for (int i = 0; i < 4; i++) begin
            tgt_sel = tgt_sel | ({32{toh[i]}} & tgt3b[i]);
            ib_sel = ib_sel | ({39{toh[i]}} & ibe3b[39*i +: 39]);
        end
    end

    // F4 next-PC candidates, one-hot selects and NLP comparisons are prepared
    // here so F4 only does an AND-OR select (ret is a jalr subset).
    wire [31:0] seq3b = {pc3b[31:4] + 28'd1, 4'b0};
    wire [31:0] jpc3b = (end3 == 2'd3) ? seq3b : {pc3b[31:4], end3 + 2'd1, 2'b00};   // end slot + 4
    wire e_ret3 = |(toh & ret3b), e_jalr3 = |(toh & jalr3b);
    wire e_call3 = |(toh & call3b), e_cbr3 = |(toh & cbr3b);
    wire ibh3 = ib_sel[38] && ib_sel[37:30] == pc3b[15:8];

    // ------------------------------------------------------------ F4
    logic        v4, fault4, tk4;
    logic [31:0] pc4, nlp4;
    logic [127:0] blk4;
    logic [1:0]  end4;
    logic [3:0]  valid4, cbr4, jalr4;
    logic [31:0] tgt4, seq4, jpc4;
    logic [29:0] ib_tgt4;
    logic        s4_seq, s4_ret, s4_ib, s4_jpc, s4_tgt;     // next-PC source (one-hot)
    logic        eq4_seq, eq4_ib, eq4_jpc, eq4_tgt;          // candidate == nlp4
    logic        end_ret, end_call, last_cbr_taken;
    logic [4*TI-1:0] idx4; logic [4*TT-1:0] tag4;
    always_ff @(posedge clk) begin
        if (rst) v4 <= 1'b0;
        else v4 <= f3b_live;
        pc4 <= pc3b; nlp4 <= nlp3b; nlpc4 <= nlpc3b; fault4 <= fault3b; tk4 <= tk3; end4 <= end3;
        blk4 <= blk3b;
        valid4 <= valid3b & s_upto;
        idx4 <= idx3b; tag4 <= tag3b;
        cbr4 <= cbr3b; jalr4 <= jalr3b;
        tgt4 <= tgt_sel; seq4 <= seq3b; jpc4 <= jpc3b;
        ib_tgt4 <= ib_sel[29:0];
        s4_seq <= !tk3;
        s4_ret <= e_ret3;
        s4_ib <= e_jalr3 && !e_ret3 && ibh3;
        s4_jpc <= e_jalr3 && !e_ret3 && !ibh3;
        s4_tgt <= tk3 && !e_jalr3;
        eq4_seq <= seq3b == nlp3b;
        eq4_ib <= ib_sel[29:0] == nlp3b[31:2] && nlp3b[1:0] == 2'b00;
        eq4_jpc <= jpc3b == nlp3b;
        eq4_tgt <= tgt_sel == nlp3b;
        end_ret <= e_ret3; end_call <= e_call3; last_cbr_taken <= e_cbr3;
    end

    // RAS (ras_top mirrors ras[ras_ptr] as a register)
    logic [31:0] ras [0:RASN-1];
    logic [2:0]  ras_ptr;
    logic [31:0] ras_top;

    wire [31:0] next4 = ({32{s4_seq}} & seq4) | ({32{s4_ret}} & ras_top) |
                        ({32{s4_ib}} & {ib_tgt4, 2'b00}) | ({32{s4_jpc}} & jpc4) | ({32{s4_tgt}} & tgt4);
    wire nlp_eq4 = (s4_seq && eq4_seq) || (s4_ret && ras_top == nlp4) || (s4_ib && eq4_ib) ||
                   (s4_jpc && eq4_jpc) || (s4_tgt && eq4_tgt);
    logic [5:0] fq_count;
    wire fq_space = fq_count <= 6'(FQN - 4);
    logic [4:0] biq_head, biq_tail;    // 16 entries, wrap bit in [4]
    wire [4:0] biq_count = biq_tail - biq_head;
    wire grp_has_br = !fault4 && |(valid4 & (cbr4 | jalr4));
    wire biq_space = biq_count < 5'd15;
    wire f4_live = v4 && !be_any;
    wire f4_accept = f4_live && fq_space && (!grp_has_br || biq_space);
    wire f4_self = f4_live && !f4_accept;
    wire f4_override = f4_accept && !fault4 && !nlp_eq4;
    assign kill_f4 = f4_override || f4_self;
    assign f4_redirect_pc = f4_self ? pc4 : next4;

    // conditional branches before each slot of the (contiguous) group
    wire [3:0] cbv = valid4 & cbr4;
    logic [1:0] kcnt [0:3];
    wire [2:0] ncbr = {2'b0, cbv[0]} + {2'b0, cbv[1]} + {2'b0, cbv[2]} + {2'b0, cbv[3]};
    always_comb begin
        kcnt[0] = 2'd0;
        kcnt[1] = {1'b0, cbv[0]};
        kcnt[2] = {1'b0, cbv[0]} + {1'b0, cbv[1]};
        kcnt[3] = {1'b0, cbv[0]} + {1'b0, cbv[1]} + {1'b0, cbv[2]};
    end

    // ------------------------------------------------------------ BIQ
    (* syn_ramstyle = "lut_ram" *) logic [63:0] biq_ghr [0:15];
    (* syn_ramstyle = "lut_ram" *) logic [4*TI-1:0] biq_idx [0:15];
    (* syn_ramstyle = "lut_ram" *) logic [4*TT-1:0] biq_tag [0:15];
    (* syn_ramstyle = "lut_ram" *) logic [2:0]  biq_ras [0:15];
    (* syn_ramstyle = "lut_ram" *) logic [1:0]  biq_rasop [0:15];   // bit0 pop, bit1 push (end slot)
    wire [3:0] biq_wptr = biq_tail[3:0];
    always_ff @(posedge clk) begin
        if (f4_accept && grp_has_br) begin
            biq_ghr[biq_wptr] <= ghr_spec;
            biq_idx[biq_wptr] <= idx4;
            biq_tag[biq_wptr] <= tag4;
            biq_ras[biq_wptr] <= ras_ptr;
            biq_rasop[biq_wptr] <= {end_call, end_ret};
        end
    end
    wire [63:0] mis_ghr = biq_ghr[be_mis_biq];
    wire [2:0] mis_rp = be_mis_is_cbr ? biq_ras[be_mis_biq] :
                        biq_ras[be_mis_biq] - {2'b0, biq_rasop[be_mis_biq][0]} + {2'b0, biq_rasop[be_mis_biq][1]};

    // ------------------------------------------------------------ F1 control, GHR, RAS
    assign pc1_next = be_flush ? be_flush_pc : be_mispredict ? be_mis_pc : kill_f4 ? f4_redirect_pc :
                           f2_miss ? ic_f2_pc : v1 ? nlp_next : pc1;
    wire refetch_next = (be_any || kill_f4) ? 1'b0 : f2_miss ? 1'b1 :
                        (refetch_wait && !ic_busy) ? 1'b0 : refetch_wait;
    always_ff @(posedge clk) begin
        if (rst) begin
            pc1 <= RESET_PC; v1 <= 1'b0; ghr_spec <= 64'b0; ghr_commit <= 64'b0;
            ras_ptr <= 3'd0; ras_top <= 32'b0; refetch_wait <= 1'b0; tinit <= '0;
            biq_head <= 5'd0; biq_tail <= 5'd0;
            for (int i = 0; i < RASN; i++) ras[i] <= 32'b0;
        end else begin
            if (tinit_busy) tinit <= tinit + 1'b1;
            if (cmt_br_valid && cmt_is_cbr) ghr_commit <= {ghr_commit[62:0], cmt_taken};
            // next fetch PC
            pc1 <= pc1_next;
            refetch_wait <= refetch_next;
            v1 <= !(fetch_stop || !nlp_ready || tinit_busy || refetch_next);
            // speculative GHR / RAS
            if (be_flush) begin
                ghr_spec <= ghr_commit;
            end else if (be_mispredict) begin
                ghr_spec <= be_mis_is_cbr ? ((mis_ghr << be_mis_k) << 1) | {63'b0, be_mis_taken}
                                          : (mis_ghr << be_mis_k);
                ras_ptr <= mis_rp; ras_top <= ras[mis_rp];
            end else if (f4_accept) begin
                ghr_spec <= (ghr_spec << ncbr) | {63'b0, last_cbr_taken};
                if (end_ret && end_call) begin ras[ras_ptr] <= jpc4; ras_top <= jpc4; end
                else if (end_ret) begin ras_ptr <= ras_ptr - 3'd1; ras_top <= ras[ras_ptr - 3'd1]; end
                else if (end_call) begin ras_ptr <= ras_ptr + 3'd1; ras[ras_ptr + 3'd1] <= jpc4; ras_top <= jpc4; end
            end
            // BIQ pointers (5-bit with wrap)
            begin
                logic [4:0] nt, nh;
                nt = biq_tail; nh = biq_head;
                if (cmt_br_valid) nh = biq_head + {1'b0, cmt_biq - biq_head[3:0]};
                if (be_flush) nt = nh;
                else if (be_mispredict) nt = biq_head + {1'b0, be_mis_biq - biq_head[3:0]} + 5'd1;
                else if (f4_accept && grp_has_br) nt = biq_tail + 5'd1;
                biq_tail <= nt; biq_head <= nh;
            end
        end
    end
    assign ic_f1_pc = pc1;

    always_comb begin
        nlp_we = f4_accept && !fault4;
        nlp_widx = pc4[NLPW+1:2];
        // hit: confident; miss: a confident entry only loses its confidence
        nlp_wdata = {nlp_eq4, 1'b1, (nlpc4 && !nlp_eq4) ? nlp4[NTB+1:2] : next4[NTB+1:2]};
    end

    // ------------------------------------------------------------ fetch queue
    // FQ storage: 4 banks (entry index mod 4), FQN/4 entries each. A group writes
    // consecutive entries, so each bank sees at most one write per cycle; the
    // two heads are consecutive entries in different banks.
    localparam integer QW = 32 + 32 + 32 + 1 + 4 + 2 + 2;
    (* syn_ramstyle = "lut_ram" *) logic [QW-1:0] qb0 [0:FQN/4-1];
    (* syn_ramstyle = "lut_ram" *) logic [QW-1:0] qb1 [0:FQN/4-1];
    (* syn_ramstyle = "lut_ram" *) logic [QW-1:0] qb2 [0:FQN/4-1];
    (* syn_ramstyle = "lut_ram" *) logic [QW-1:0] qb3 [0:FQN/4-1];
    logic [4:0] fq_head, fq_tail, fq_h1;     // fq_h1 = fq_head + 1
    // the group is the contiguous slot range [pc4[3:2], end4] (one slot on a fault)
    wire [1:0] gs0 = pc4[3:2];
    wire [2:0] gcount = fault4 ? 3'd1 : ({1'b0, end4} - {1'b0, gs0} + 3'd1);
    wire [1:0] gslot0 = gs0, gslot1 = gs0 + 2'd1, gslot2 = gs0 + 2'd2, gslot3 = gs0 + 2'd3;
    wire do_enq = f4_accept;
    // predecode per block slot (only the fu output of the decoder is used:
    // pairing in rename needs "executes at commit" and "checkpointed branch")
    logic [2:0] pfu [0:3];
    genvar gp;
    generate for (gp = 0; gp < 4; gp++) begin : g_pd
        o2_decode pdec (.pc(32'b0), .insn(blk4[32*gp +: 32]), .fetch_fault(fault4),
            .fu(pfu[gp]), .op(), .rs1(), .rs2(), .rd(), .use1(), .use2(), .wr(),
            .src2_imm(), .imm(), .is_jalr(), .exc(), .cause());
    end endgenerate
    // per-group slot data, j = position in the group
    logic [QW-1:0] gdat [0:3];
    always_comb begin
        for (int j = 0; j < 4; j++) begin
            logic [1:0] sl; logic [31:0] spc, snext;
            sl = gs0 + 2'(j);
            spc = {pc4[31:4], sl, 2'b00};
            snext = (sl == 2'd3) ? seq4 : {pc4[31:4], sl + 2'd1, 2'b00};
            gdat[j] = {spc, blk4[32*sl +: 32], (sl == end4) ? next4 : snext, fault4, biq_wptr, kcnt[sl],
                       pfu[sl] == `FU_CMT, pfu[sl] == `FU_BR};
        end
    end
    // bank b receives group position j = (b - tail) mod 4 when j < gcount
    logic [3:0] bwe; logic [2:0] bwa [0:3]; logic [QW-1:0] bwd [0:3];
    always_comb begin
        for (int b = 0; b < 4; b++) begin
            logic [1:0] j; logic [4:0] idx;
            j = 2'(b) - fq_tail[1:0];
            idx = fq_tail + {3'b0, j};
            bwe[b] = do_enq && ({1'b0, j} < gcount);
            bwa[b] = idx[4:2];
            bwd[b] = gdat[j];
        end
    end
    always_ff @(posedge clk) begin
        if (bwe[0]) qb0[bwa[0]] <= bwd[0];
        if (bwe[1]) qb1[bwa[1]] <= bwd[1];
        if (bwe[2]) qb2[bwa[2]] <= bwd[2];
        if (bwe[3]) qb3[bwa[3]] <= bwd[3];
    end
    always_ff @(posedge clk) begin
        if (rst || be_any) begin fq_head <= 5'd0; fq_h1 <= 5'd1; fq_tail <= 5'd0; fq_count <= 6'd0; end
        else begin
            fq_head <= fq_head + {3'b0, fq_pop};
            fq_h1 <= fq_h1 + {3'b0, fq_pop};
            fq_tail <= fq_tail + (do_enq ? {2'b0, gcount} : 5'd0);
            fq_count <= fq_count + (do_enq ? {3'b0, gcount} : 6'd0) - {4'b0, fq_pop};
        end
    end
    wire [4:0] fh1 = fq_h1;
    // read: each bank addressed by whichever head maps to it
    logic [QW-1:0] brd [0:3];
    always_comb begin
        for (int b = 0; b < 4; b++) begin
            logic [2:0] ra;
            ra = (fq_head[1:0] == 2'(b)) ? fq_head[4:2] : fh1[4:2];
            case (b)
                0: brd[b] = qb0[ra]; 1: brd[b] = qb1[ra]; 2: brd[b] = qb2[ra]; default: brd[b] = qb3[ra];
            endcase
        end
    end
    wire [QW-1:0] h0d = brd[fq_head[1:0]], h1d = brd[fh1[1:0]];
    assign fq_v0 = fq_count >= 6'd1;
    assign fq_v1 = fq_count >= 6'd2;
    assign {fq_pc0, fq_insn0, fq_pred0, fq_fault0, fq_biq0, fq_k0, fq_cmt0, fq_br0} = h0d;
    assign {fq_pc1, fq_insn1, fq_pred1, fq_fault1, fq_biq1, fq_k1, fq_cmt1, fq_br1} = h1d;

    // ------------------------------------------------------------ TAGE update unit
    // U0 (commit cycle): read BIQ, address the update copies, read the base.
    // U1: forward the previous write, tag hits, provider / alternate.
    // U2: re-evaluate the prediction, modify and write the entries.
    // An update in U1 while the previous one is in U2 takes that write
    // straight into its U2 entry registers (tags change only on allocation,
    // so the U1 hit / provider decisions stay valid otherwise).
    logic u1_v, u1_taken;
    logic [31:0] u1_pc;
    logic [4*TI-1:0] u1_idx; logic [4*TT-1:0] u1_tag;
    logic [1:0] u1_base;
    logic [3:0] p_en; logic [4*TI-1:0] p_idx; logic [4*TW-1:0] p_data;
    wire [4*TI-1:0] cmt_idx = biq_idx[cmt_biq];
    always_comb begin
        tr_idx0 = cmt_idx[0 +: TI]; tr_idx1 = cmt_idx[TI +: TI];
        tr_idx2 = cmt_idx[2*TI +: TI]; tr_idx3 = cmt_idx[3*TI +: TI];
    end
    always_ff @(posedge clk) begin
        if (rst) u1_v <= 1'b0;
        else u1_v <= cmt_br_valid && cmt_is_cbr && !tinit_busy;
        u1_taken <= cmt_taken; u1_pc <= cmt_pc;
        u1_idx <= cmt_idx; u1_tag <= biq_tag[cmt_biq];
        case (cmt_pc[3:2])
            2'd0: u1_base <= bs0[cmt_pc[12:4]]; 2'd1: u1_base <= bs1[cmt_pc[12:4]];
            2'd2: u1_base <= bs2[cmt_pc[12:4]]; default: u1_base <= bs3[cmt_pc[12:4]];
        endcase
    end
    // ---- U1
    logic u2_v, u2_taken, u2_pv_v, u2_al_v; logic [1:0] u2_pv, u2_al, u2_base;
    logic [31:0] u2_pc; logic [4*TI-1:0] u2_idx; logic [4*TT-1:0] u2_tag;
    logic [4*TW-1:0] u2_e;
    logic [4*TW-1:0] u1_e; logic [3:0] u1_h; logic u1_pv_v, u1_al_v; logic [1:0] u1_pv, u1_al;
    logic p_ben; logic [10:0] p_bidx; logic [1:0] p_bdata;
    // base counter written by last cycle's U2 (read in U0 before that write)
    wire [1:0] u1_basef = (p_ben && p_bidx == u1_pc[12:2]) ? p_bdata : u1_base;
    always_comb begin
        logic [TW-1:0] tu [0:3];
        tu[0] = tue0; tu[1] = tue1; tu[2] = tue2; tu[3] = tue3;
        for (int i = 0; i < 4; i++) begin
            u1_e[TW*i +: TW] = (p_en[i] && p_idx[TI*i +: TI] == u1_idx[TI*i +: TI]) ? p_data[TW*i +: TW] : tu[i];
            u1_h[i] = u1_e[TW*i + TW-1 -: TT] == u1_tag[TT*i +: TT];
        end
        u1_pv_v = |u1_h; u1_pv = u1_h[3] ? 2'd3 : u1_h[2] ? 2'd2 : u1_h[1] ? 2'd1 : 2'd0;
        u1_al_v = 1'b0; u1_al = 2'd0;
        case (u1_pv)
            2'd3: begin u1_al_v = |u1_h[2:0]; u1_al = u1_h[2] ? 2'd2 : u1_h[1] ? 2'd1 : 2'd0; end
            2'd2: begin u1_al_v = |u1_h[1:0]; u1_al = u1_h[1] ? 2'd1 : 2'd0; end
            2'd1: begin u1_al_v = u1_h[0]; u1_al = 2'd0; end
            default: begin u1_al_v = 1'b0; u1_al = 2'd0; end
        endcase
    end
    always_ff @(posedge clk) begin
        if (rst) u2_v <= 1'b0;
        else u2_v <= u1_v;
        u2_taken <= u1_taken; u2_pc <= u1_pc; u2_idx <= u1_idx; u2_tag <= u1_tag;
        u2_base <= (bw_en && bw_idx == u1_pc[12:2]) ? bw_data : u1_basef;
        for (int i = 0; i < 4; i++)
            u2_e[TW*i +: TW] <= (tw_en[i] && u2_idx[TI*i +: TI] == u1_idx[TI*i +: TI]) ? uw[TW*i +: TW] : u1_e[TW*i +: TW];
        u2_pv_v <= u1_pv_v; u2_pv <= u1_pv; u2_al_v <= u1_al_v; u2_al <= u1_al;
        p_en <= u2_v ? tw_en : 4'b0;
        p_idx <= {tw_idx3, tw_idx2, tw_idx1, tw_idx0};
        p_data <= {tw_d3, tw_d2, tw_d1, tw_d0};
        p_ben <= bw_en && !tinit_busy; p_bidx <= bw_idx; p_bdata <= bw_data;
    end
    // ---- U2
    logic [4*TW-1:0] uw;          // write data
    always_comb begin
        logic [TW-1:0] e [0:3];
        logic [1:0] pv, al, sl;
        logic pv_v, al_v;
        logic [2:0] pc_, ac_;
        logic ppred, apred, bpred, wkp, fpred, mis, done_a;
        logic [TW-1:0] ne;
        logic [2:0] c;
        for (int i = 0; i < 4; i++) e[i] = u2_e[TW*i +: TW];
        pv = u2_pv; al = u2_al; pv_v = u2_pv_v; al_v = u2_al_v;
        sl = u2_pc[3:2];
        bpred = u2_base[1];
        pc_ = e[pv][3*sl +: 3];
        ac_ = e[al][3*sl +: 3];
        ppred = pv_v ? !pc_[2] : bpred;
        apred = al_v ? !ac_[2] : bpred;
        wkp = pv_v && (pc_ == 3'd0 || pc_ == 3'b111) && e[pv][13:12] == 2'd0;
        fpred = pv_v ? (wkp ? apred : ppred) : bpred;
        mis = fpred != u2_taken;
        for (int i = 0; i < 4; i++) uw[TW*i +: TW] = e[i];
        tw_en = 4'b0;
        bw_en = 1'b0; bw_idx = u2_pc[12:2]; bw_data = sat2(u2_base, u2_taken);
        ne = e[pv];
        if (ppred != apred) ne[13:12] = sat2(ne[13:12], ppred == u2_taken);
        c = pc_;
        if (u2_taken) c = (c == 3'd3) ? 3'd3 : c + 3'd1;
        else c = (c == 3'b100) ? 3'b100 : c - 3'd1;
        ne[3*sl +: 3] = c;
        done_a = 1'b0;
        if (u2_v) begin
            if (pv_v) begin
                tw_en[pv] = 1'b1; uw[TW*pv +: TW] = ne;
                if (!al_v && ne[13:12] == 2'd0) bw_en = 1'b1;
            end else bw_en = 1'b1;
            if (mis && !(pv_v && pv == 2'd3)) begin
                for (int i = 0; i < 4; i++) begin
                    if ((!pv_v || 2'(i) > pv) && !done_a && e[i][13:12] == 2'd0) begin
                        logic [TW-1:0] na;
                        na = '0;
                        na[TW-1 -: TT] = u2_tag[TT*i +: TT];
                        na[3*sl +: 3] = u2_taken ? 3'd0 : 3'b111;
                        tw_en[i] = 1'b1; uw[TW*i +: TW] = na; done_a = 1'b1;
                    end
                end
                if (!done_a) begin
                    for (int i = 0; i < 4; i++) begin
                        if ((!pv_v || 2'(i) > pv) && e[i][13:12] != 2'd0) begin
                            logic [TW-1:0] nd;
                            nd = e[i]; nd[13:12] = nd[13:12] - 2'd1;
                            tw_en[i] = 1'b1; uw[TW*i +: TW] = nd;
                        end
                    end
                end
            end
        end
        tw_idx0 = u2_idx[0 +: TI]; tw_idx1 = u2_idx[TI +: TI];
        tw_idx2 = u2_idx[2*TI +: TI]; tw_idx3 = u2_idx[3*TI +: TI];
        tw_d0 = uw[0 +: TW]; tw_d1 = uw[TW +: TW]; tw_d2 = uw[2*TW +: TW]; tw_d3 = uw[3*TW +: TW];
    end
`ifndef SYNTHESIS
    longint st_nr_fq = 0, st_nr_biq = 0;
    always_ff @(posedge clk) if (!rst && f4_self) begin
        if (!fq_space) st_nr_fq <= st_nr_fq + 1; else st_nr_biq <= st_nr_biq + 1;
    end
    final $display("O2_NOROOM fq=%0d biq=%0d", st_nr_fq, st_nr_biq);
`endif
endmodule
