`timescale 1ns/1ps
// P2 incremental core, retaining the P1 execution pipeline. See docs/{architecture,interface}_contract.md.
module p2_core #(
    parameter [31:0] RESET_PC = 32'h80000000,
    parameter MACHINE_MODE=1, BP_ENABLED=1, FIFO_DEPTH=2,RESPONSE_BYPASS=0,BTB_ENTRIES=64,BHT_ENTRIES=256,RAS_DEPTH=0,EARLY_LSU=0,HW_MUL=0,IFETCH_DUAL_WORDS=1,IFETCH_LINE_BYTES=32,IFETCH_PREDECODE=0
) (
    input wire clk, rst,
    input wire [319:0] perf_cache_flat,
    output wire i_req_valid, input wire i_req_ready, output wire [31:0] i_req_addr,
    input wire i_rsp_valid, output wire i_rsp_ready,
    input wire [31:0] i_rsp_data, input wire i_rsp_error,
    input wire [31:0] i_rsp_data_hi, input wire i_rsp_hi_valid,
    input wire [6:0] i_rsp_predecode,i_rsp_predecode_hi,
    output wire d_req_valid, input wire d_req_ready,
    output wire [31:0] d_req_addr, output wire d_req_write,
    output wire [3:0] d_req_be, output wire [31:0] d_req_wdata,
    input wire d_rsp_valid, output wire d_rsp_ready,
    input wire [31:0] d_rsp_data, input wire d_rsp_error,
    input wire d_rsp_terminal,
    input wire irq_software,irq_timer,irq_external,fatal_error,run_stop,
    output wire data_idle,
    output wire [63:0] machine_cycle,machine_retired,
    output wire fence_i_valid,input wire fence_i_ready,fence_i_done,fence_i_error,
    output reg trace_irq_valid,output reg [31:0] trace_irq_pc,trace_irq_cause,
    output reg trace_csr_valid,trace_csr_read,trace_csr_write,
    output reg [11:0] trace_csr_addr,output reg [31:0] trace_csr_rdata,trace_csr_wdata,
    output reg trace_valid, trace_trap,
    output reg trace_valid1,
    output reg [31:0] trace_pc1, trace_insn1,
    output reg [4:0] trace_rd1,
    output reg [31:0] trace_wdata1,
    output reg [31:0] trace_pc, trace_insn,
    output reg [4:0] trace_rd, output reg [31:0] trace_wdata,
    output reg [31:0] trace_cause, trace_tval,
    output reg trace_mem_valid, trace_mem_write,
    output reg [31:0] trace_mem_addr, trace_mem_wdata, trace_mem_rdata,
    output reg [3:0] trace_mem_be,
    output reg halted,
    output reg [63:0] count_cycle, count_retired, count_if_wait, count_data_wait,
    output reg [63:0] count_load_use, count_redirect, count_reads, count_writes
);
    // Pango ADS Synthesis User Guide section 5.16: lut_ram selects native
    // distributed RAM. Each bank has one synchronous write port and four
    // asynchronous logical read ports; synthesis can replicate read copies.
    // Standard attributes survive sv2v; synthesis comments do not.
    // Data have no reset. Small valid/last-writer maps preserve reset-to-zero
    // architecture, with slot1 winning a same-address double write.
    (* syn_ramstyle = "lut_ram" *) reg [31:0] rf_bank0[0:31];
    (* syn_ramstyle = "lut_ram" *) reg [31:0] rf_bank1[0:31];
    reg [31:0] rf_valid_q,rf_owner_q;
    reg rf_wb0_valid_q,rf_wb1_valid_q;
    reg [4:0] rf_wb0_rd_q,rf_wb1_rd_q;
    reg [31:0] rf_wb0_data_q,rf_wb1_data_q;
`ifndef SYNTHESIS
    // Observation only: keep 32 debug reads out of the synthesized memories.
    wire [31:0] regs[0:31];
    reg [31:0] rf_immediate_model[0:31];
    genvar rf_view;
    generate for(rf_view=0;rf_view<32;rf_view=rf_view+1) begin: architectural_rf_view
        assign regs[rf_view]=(rf_view==0 || !rf_valid_q[rf_view]) ? 32'b0 :
            (rf_wb1_valid_q&&rf_wb1_rd_q==rf_view)?rf_wb1_data_q:
            (rf_wb0_valid_q&&rf_wb0_rd_q==rf_view)?rf_wb0_data_q:
            rf_owner_q[rf_view] ? rf_bank1[rf_view] : rf_bank0[rf_view];
    end endgenerate
`endif
    reg fetch_stop;
    reg terminal_stopped;
    wire dv,de,dv1,de1;
    reg ev,mv,ev1,mv1_raw_q;
    // Slot 1 of a predicted-fallthrough branch is architecturally live only
    // when the resolved next PC equals that prediction. A taken branch whose
    // target is PC+4 legitimately keeps slot 1; target PC+8 must annul it.
    wire mv1;
    // Slot-1 PC relation of a slot-0 branch, registered in E: target==pc1 and
    // fall-through==pc1. M selects by the resolved outcome only.
    reg m_tgt_eq1_q,m_ft_eq1_q;
    // Slot-1 aligned conditional branches. rd is forced
    // to x0; the condition is registered as byte equalities at the E/M edge.
    reg m1_branch_q,m1_bne_q;
    // Slot-1 branch prediction: captured with the E payload, compared in E.
    reg [31:0] epred1,m1_fall_q;
    reg m1_wrong_taken_q,m1_wrong_nt_q;
    reg [3:0] mbranch1_eq8;
    reg [31:0] mtarget1;
    reg e_lui_pair_q;
    wire e_lui_pair=ev1&&e_lui_pair_q;
    // Narrow bit operations only. Both instructions keep their architectural
    // retirement slots; slot1 is evaluated directly from slot0's operands.
    function automatic [2:0] bitfusion_kind;
        input [31:0] head,tail;
        begin
            bitfusion_kind=0;
            if(head[11:7]!=0&&tail[19:15]==head[11:7]&&tail[6:0]==7'h13) begin
                if(head[6:0]==7'h33&&head[14:12]==4&&head[31:25]==0) begin
                    if(tail[14:12]==7&&tail[31:20]==12'h001) bitfusion_kind=1;
                    if(tail[14:12]==1&&tail[31:20]==12'h010) bitfusion_kind=2;
                end
                if(head[6:0]==7'h13&&head[14:12]==1&&head[31:20]==12'h010&&tail[14:12]==5) begin
                    if(tail[31:20]==12'h010) bitfusion_kind=3;
                    if(tail[31:20]==12'h410) bitfusion_kind=4;
                end
            end
        end
    endfunction
    reg [2:0] e_bitfusion_q;
    reg [3:0] e_fusion_sel_q;
    reg e_late1_enable_q;
    reg e_alu_imm0_q,e_alu_sub0_q,e_alu_left0_q,e_alu_arith0_q;
    reg e_alu_imm1_q,e_alu_sub1_q,e_alu_left1_q,e_alu_arith1_q;
    wire e_bitfusion=ev1&&(e_bitfusion_q!=0);
    wire [2:0] d_bitfusion=bitfusion_kind(di,di1);
    function automatic [31:0] bitfusion_result;
        input [2:0] kind;
        input [31:0] lhs,rhs;
        begin
            case(kind)
                1:bitfusion_result={31'b0,lhs[0]^rhs[0]};
                2:bitfusion_result={lhs[15:0]^rhs[15:0],16'b0};
                3:bitfusion_result={16'b0,lhs[15:0]};
                4:bitfusion_result={{16{lhs[15]}},lhs[15:0]};
                default:bitfusion_result=0;
            endcase
        end
    endfunction
    // Architectural annul is distinct from disposable execute preselection.
    // Mode 0 retains its terminal-edge fault/operand observation unchanged.
    wire mv1_exec=(MACHINE_MODE==0)?mv1:mv1_raw_q;
    wire [31:0] dp,di,dp1,di1,front_prediction,front_prediction1;
    wire front_sequential,front_sequential1,front_pair_link;
    wire [6:0] front_pre0,front_pre1;
    reg [31:0] ep,ei,mp,mi,ep1,ei1,mp1,mi1;
    reg ee,ee1;
    reg [11:0] e_lsu_imm12_q;
    reg e_store_q;
    wire [31:0] e_lsu_imm={{20{e_lsu_imm12_q[11]}},e_lsu_imm12_q};
    reg [4:0] mr;
    // Mirrors mr!=0 at the existing M packet boundary; no new stage.
    reg mr_nonzero_q;
    reg [31:0] mresult, maddr, mwdata, mcause, mtval,mresult1_payload;
    reg [31:0] mlate_b1;
    reg mlate0,mlate1;
    // Decode late ALU controls before the existing E/M edge. The late
    // shifter sees a registered amount, without an M opcode-to-RHS mux.
    reg mlate_sub0,mlate_left0,mlate_arith0;
    reg mlate_sub1,mlate_left1,mlate_arith1;
    reg [4:0] mr1;
    // Destination/source equality registered on the edges that load mr/mr1
    // and the E sources, so the bypass select does not start with a compare.
    // hit0 uses the raw field ei[11:7]; it is exact under mr_nonzero_q since
    // a nonzero decoded rd always equals ei[11:7]. hit1 is always exact.
    reg hit0_rs1_q,hit0_rs2_q,hit0_rs1_1_q,hit0_rs2_1_q;
    reg hit1_rs1_q,hit1_rs2_q,hit1_rs1_1_q,hit1_rs2_1_q;
    reg mr1_nonzero_q;
    // Registered youngest-M-writer classes per E source {rs2_1,rs1_1,rs2,rs1}.
    reg mmul_pipe_q;
    // Slot-1 low MUL whose product is still only in the DSP output registers.
    reg mmul1_live_q;
    wire [31:0] mul_result;
    reg [1:0] slowL_q,ld_q;reg late_q;reg [3:0] any_q;
    function automatic hit_next;
        input fire,capture;
        input [4:0] e_dest,m_dest,d_src,e_src;
        begin
            hit_next=fire?(capture?e_dest==d_src:e_dest==e_src):
                          (capture?m_dest==d_src:m_dest==e_src);
        end
    endfunction
    // Compare original register names in parallel. Literal qualification is
    // a one-bit result selection, not a five-bit mux before every compare.
    // Preserve the original raw hit when a selected destination is x0 too;
    // consumers still apply their existing nonzero-writer qualifications.
    function automatic literal_hit_next;
        input fire,capture;
        input [4:0] e_dest,m_dest,d_src,e_src;
        input d_literal,e_literal;
        reg normal_hit,literal_selected,zero_destination;
        begin
            normal_hit=hit_next(fire,capture,e_dest,m_dest,d_src,e_src);
            literal_selected=capture?d_literal:e_literal;
            zero_destination=fire?(e_dest==0):(m_dest==0);
            literal_hit_next=literal_selected?zero_destination:normal_hit;
        end
    endfunction
    reg [3:0] mbe;
    reg [2:0] mfunct3;
    reg mmem, mwrite, mfault, msent;
    reg mcsr,mmret,mfencei,mfence_sent;
    reg mcontrol,mconditional;
    reg [31:0] epred,mtarget_base,commit_next_pc;
    // Fast redirect metadata registered at the E/M edge.
    reg m_wrong_taken_q,m_wrong_nt_q;
    reg [31:0] m_fall_q,m_fall4_q,m_fall8_q,m_tgt4_q,m_tgt8_q,m1_tgt4_q,m1_tgt8_q,m1_fall4_q,m1_fall8_q;
    // Resolve control flow from registered operands in M. epred must travel
    // with the exact instruction; consulting the live predictor would lose
    // the prediction made before intervening training/alias updates.
    reg [31:0] mbranch_a,mbranch_b,mpred;
    // Same E/M edge as the operands. Four independent byte comparisons
    // replace the M-stage 32-bit carry chain without a new pipeline stage.
    // The original operands remain shared by late ALU and CSR operations.
    reg [3:0] mbranch_eq8,mbranch_lt8;
    reg mbranch_signed_top_lt;
    wire mbranch_eq_all=&mbranch_eq8;
    wire mbranch_lo_lt=mbranch_lt8[1]||(mbranch_eq8[1]&&mbranch_lt8[0]);
    wire mbranch_hi_eq=mbranch_eq8[3]&&mbranch_eq8[2];
    wire mbranch_hi_lt=mbranch_lt8[3]||(mbranch_eq8[3]&&mbranch_lt8[2]);
    wire mbranch_hi_signed_lt=mbranch_signed_top_lt||(mbranch_eq8[3]&&mbranch_lt8[2]);
    wire mbranch_unsigned_lt=mbranch_hi_lt||(mbranch_hi_eq&&mbranch_lo_lt);
    wire mbranch_signed_lt=mbranch_hi_signed_lt||(mbranch_hi_eq&&mbranch_lo_lt);

    wire [4:0] rs1 = ei[19:15], rs2 = ei[24:20];
    wire [6:0] op = ei[6:0], f7 = ei[31:25];
    wire [2:0] f3 = ei[14:12];
    wire [31:0] imm_i = {{20{ei[31]}},ei[31:20]};
    wire [31:0] imm_s = {{20{ei[31]}},ei[31:25],ei[11:7]};
    wire [31:0] imm_b = {{19{ei[31]}},ei[31],ei[7],ei[30:25],ei[11:8],1'b0};
    wire [31:0] imm_j = {{11{ei[31]}},ei[31],ei[19:12],ei[20],ei[30:21],1'b0};
    wire [31:0] imm_u = {ei[31:12],12'b0};

    wire m_response = mv && mmem && !mfault && msent && d_rsp_valid;
    wire m_done = mv && (mfault || (mfencei ? (mfence_sent&&fence_i_done&&!fence_i_error) : (!mmem || m_response)));
    wire [31:0] csr_rdata,csr_modify_rdata,csr_wdata,handler_pc,return_pc,irq_cause;
    wire csr_error,irq_eligible;
    function automatic csr_permission_illegal;
        input [31:0] instruction;
        reg [11:0] address;
        reg standard_known,zero_known,performance_known,write_access;
        begin
            address=instruction[31:20];
            standard_known=(address==12'h300)||(address==12'h301)||(address==12'h304)||(address==12'h305)||(address==12'h320)||(address==12'h340)||(address==12'h341)||(address==12'h342)||(address==12'h343)||(address==12'h344)||(address==12'hb00)||(address==12'hb80)||(address==12'hb02)||(address==12'hb82)||(address==12'hf11)||(address==12'hf12)||(address==12'hf13)||(address==12'hf14)||(address==12'hf15);
            zero_known=(address==12'h310)||
        (address>=12'hb03&&address<=12'hb1f)||
        (address>=12'hb83&&address<=12'hb9f)||
        (address>=12'h323&&address<=12'h33f);
            performance_known=address >= 12'hfc0 && address <= 12'hfef;
            write_access=(instruction[13:12]==2'b01)||(instruction[19:15]!=0);
            csr_permission_illegal=!(standard_known||zero_known||performance_known)||
                (write_access&&address[11:10]==2'b11);
        end
    endfunction
    reg mcsr_illegal_q;
    // The permission predicate is static in the instruction. Its packet flag
    // is qualified by the original CSR ownership and validity at every use.
    wire csr_error_reference;
    assign csr_error=mv&&mcsr&&mcsr_illegal_q;
`ifndef SYNTHESIS
    integer csr_permission_legal_checks=0,csr_permission_error_checks=0;
    always @(posedge clk) if(!rst&&mv&&mcsr) begin
        assert(csr_error===csr_error_reference) else $fatal(1,"CSR_PERMISSION_PACKET_IDENTITY");
        if(csr_error) csr_permission_error_checks<=csr_permission_error_checks+1;
        else csr_permission_legal_checks<=csr_permission_legal_checks+1;
    end
    final $display("CSR_PERMISSION_COVER legal=%0d illegal=%0d",
        csr_permission_legal_checks,csr_permission_error_checks);
`endif
    wire csr_read=(mi[13:12]!=2'b01)||mr_nonzero_q;
    wire csr_write=(mi[13:12]==2'b01)||(mi[19:15]!=0);
    // CSR source shares the already captured branch operand, not the ALU
    // result bus. Keeping CSR pass-through out of er prevents synthesis from
    // merging live load forwarding into PC/result carry logic.
    wire [31:0] mcsr_operand=mi[14]?{27'b0,mi[19:15]}:mbranch_a;
    assign csr_wdata=(mi[13:12]==2'b01)?mcsr_operand:(mi[13:12]==2'b10)?(csr_modify_rdata|mcsr_operand):(csr_modify_rdata&~mcsr_operand);
    wire mbranch_taken;
    reg mbranch_low_lt_direction_q,mbranch_low_ge_direction_q;
    reg mbranch_eq_taken_q;
    reg mbranch_order_hi_lt_q,mbranch_order_hi_eq_q,mbranch_order_lo_lt_q;
    wire mbranch_order_lt=mbranch_order_hi_lt_q||
        (mbranch_order_hi_eq_q&&mbranch_order_lo_lt_q);
    reg m1_decision_q;
    reg m1_order_low_lt_q,m1_order_low_ge_q,m1_order_lower_lt_q;
    wire m1_order_direction=m1_order_lower_lt_q?m1_order_low_lt_q:m1_order_low_ge_q;
    // A registered lower-half predicate selects precomputed directions.
    // Equality and invalid branch kinds give identical outcomes in both arms.
    assign mbranch_taken=mbranch_order_lo_lt_q?
        mbranch_low_lt_direction_q:mbranch_low_ge_direction_q;
    // Parallel small comparisons avoid a full-width equality carry chain.
    function automatic branch_half_direction;
        input [2:0] kind;
        input [31:0] lhs,rhs;
        input lower_lt;
        reg [10:0] equal3;
        reg [3:0] high_lt4,high_eq4;
        reg all_equal,high_unsigned_lt,high_signed_lt,high_equal,high_lt,ordered;
        integer j;
        begin
            for(j=0;j<10;j=j+1) equal3[j]=(lhs[j*3+:3]==rhs[j*3+:3]);
            equal3[10]=(lhs[31:30]==rhs[31:30]);
            all_equal=&equal3;
            for(j=0;j<4;j=j+1) begin
                high_lt4[j]=(lhs[16+j*4+:4]<rhs[16+j*4+:4]);
                high_eq4[j]=(lhs[16+j*4+:4]==rhs[16+j*4+:4]);
            end
            high_unsigned_lt=high_lt4[3]||(high_eq4[3]&&high_lt4[2])||
                (high_eq4[3]&&high_eq4[2]&&high_lt4[1])||
                (high_eq4[3]&&high_eq4[2]&&high_eq4[1]&&high_lt4[0]);
            high_signed_lt=(lhs[31]!=rhs[31])?lhs[31]:high_unsigned_lt;
            high_equal=&high_eq4;
            high_lt=kind[1]?high_unsigned_lt:high_signed_lt;
            ordered=high_lt||(high_equal&&lower_lt);
            branch_half_direction=((kind==0)&&all_equal)||((kind==1)&&!all_equal)||
                (kind[2]&&(ordered^kind[0]));
        end
    endfunction
`ifndef SYNTHESIS
    reg mbranch_decision_oracle;
    always @* begin
        case(mi[14:12])
            3'd0:mbranch_decision_oracle=mbranch_eq_all;
            3'd1:mbranch_decision_oracle=!mbranch_eq_all;
            3'd4:mbranch_decision_oracle=mbranch_signed_lt;
            3'd5:mbranch_decision_oracle=!mbranch_signed_lt;
            3'd6:mbranch_decision_oracle=mbranch_unsigned_lt;
            3'd7:mbranch_decision_oracle=!mbranch_unsigned_lt;
            default:mbranch_decision_oracle=1'b0;
        endcase
    end
    always @(posedge clk) if(!rst&&mv) begin
        if(mcontrol&&mconditional) assert(mbranch_taken===mbranch_decision_oracle)
            else $fatal(1,"BRANCH_REGISTERED_DECISION_IDENTITY");
        if(mv1_raw_q&&m1_branch_q) assert(m1_decision_q===(m1_bne_q?!(&mbranch1_eq8):(&mbranch1_eq8)))
            else $fatal(1,"BRANCH1_REGISTERED_DECISION_IDENTITY");
    end
`endif
    wire mtaken=mcontrol&&(!mconditional||mbranch_taken);
    // E computes JALR using the isolated AGU. M retains precise alignment,
    // retirement and redirect decisions but starts from a registered target.
    wire [31:0] mtarget=mtarget_base;
    wire [31:0] mnext=mtaken?mtarget:m_fall_q;
    wire mpred_wrong=!mfault&&(mtaken?m_wrong_taken_q:m_wrong_nt_q);
    // Raw control pairs predict PC+4. A taken branch preserves slot1 only
    // when its static displacement is +4; do not feed PC carry/compare into
    // the slot1 validity or execute operand selection cones.
    assign mv1=mv1_raw_q && (!mcontrol || (mbranch_taken ? m_tgt_eq1_q : m_ft_eq1_q));
    wire mcontrol_misaligned=mv&&mcontrol&&mtaken&&(|mtarget[1:0]);
    wire m_bad = mfault || mcontrol_misaligned || (m_response && d_rsp_error) || (mcsr&&csr_error);
    // Control packets cannot be memory, CSR, or FENCE.I packets: their kind
    // bits are decoded exclusively and captured together at the E/M boundary.
    // Remove unrelated response/error cones from predictor/event commits.
    wire control_commit=mv&&mcontrol&&!mfault&&!mcontrol_misaligned;

    wire [31:0] m_final_cause = mfault ? mcause : mcontrol_misaligned?32'd0:
        (mcsr&&csr_error)?32'd2:(mwrite ? 32'd7 : 32'd5);
    wire [31:0] m_final_tval = mfault ? mtval : mcontrol_misaligned?mtarget:(mcsr&&csr_error)?mi:maddr;
    wire irq_wait=(MACHINE_MODE!=0)&&irq_eligible;
    wire terminal_commit=m_done&&!m_bad&&mmem&&mwrite&&d_rsp_terminal;
    wire m1_taken=m1_branch_q&&(mi1[14]?m1_order_direction:m1_decision_q);
    // The slot-1 prediction may be sequential or taken. E registered its match
    // against both outcomes; M selects by the resolved direction only.
    wire m1_mispredict=m1_taken?m1_wrong_taken_q:m1_wrong_nt_q;
    // Registered selector: a slot-1 branch never shares a packet with slot-0
    // control, so mv1==mv1_raw_q here; keep mbranch_taken off this cone.
    wire slot1_branch_sel=mv1_raw_q&&m1_branch_q;
    // A paired slot1 branch excludes slot0 CSR/control/MRET/FENCE.I.
    // Memory packets still require their exact response, error and terminal
    // checks. Keep unrelated CSR decoding out of predictor/event commits.
    wire slot1_branch_commit=mv&&slot1_branch_sel&&!mfault&&
        (!mmem||(m_response&&!d_rsp_error&&(!mwrite||!d_rsp_terminal)));
    wire m1_redirect_raw=slot1_branch_sel&&m1_mispredict;
    wire m_redirect0=m_done&&!m_bad&&mpred_wrong;
    wire m_redirect1=m_done&&!m_bad&&!terminal_commit&&m1_redirect_raw;
    wire m_redirect=m_redirect0||m_redirect1;
    // FAST redirect: ordinary control mispredict, or slot-1 branch mispredict behind a
    // non-memory slot 0. Neither can coincide with exception, IRQ, MRET, FENCE.I or
    // terminal commit; those keep the registered recovery path.
    wire fast_ctl=mv&&mcontrol&&!mcontrol_misaligned&&mpred_wrong;
    reg m_fast_s1_nonmem_q;
    wire fast_s1=mv&&mv1_raw_q&&m_fast_s1_nonmem_q&&m1_mispredict;
    wire fast_redirect=(MACHINE_MODE!=0)&&(fast_ctl||fast_s1);
`ifndef SYNTHESIS
    wire fast_s1_original=mv&&slot1_branch_sel&&!mmem&&m1_mispredict;
    integer fast_s1_class_checks=0,fast_s1_class_eligible=0,fast_s1_class_memory=0,fast_s1_class_redirects=0;
    always @(posedge clk) if(!rst) begin
        assert(m_fast_s1_nonmem_q===(m1_branch_q&&!mmem))
            else $fatal(1,"FAST_S1_CLASS_BOUNDARY_IDENTITY");
        assert(fast_s1===fast_s1_original)
            else $fatal(1,"FAST_S1_ORIGINAL_PREDICATE");
        fast_s1_class_checks<=fast_s1_class_checks+1;
        if(mv&&slot1_branch_sel) begin
            if(mmem) fast_s1_class_memory<=fast_s1_class_memory+1;
            else fast_s1_class_eligible<=fast_s1_class_eligible+1;
        end
        if(fast_s1) fast_s1_class_redirects<=fast_s1_class_redirects+1;
    end
    final $display("FAST_S1_CLASS_COVER checks=%0d eligible=%0d memory=%0d redirects=%0d",
        fast_s1_class_checks,fast_s1_class_eligible,fast_s1_class_memory,fast_s1_class_redirects);
`endif

    // A slot-1 mispredict may be predicted-taken/resolved-not-taken: select the
    // registered target or fall-through set by the resolved slot-1 direction.
    // Only fast_redirect consumers observe these targets. A valid slot-1
    // branch excludes slot-0 control, so packet class selects the same
    // target on active redirects without the late mispredict predicate.
    (* syn_keep=1 *) wire fast_target_s1=mv1_raw_q&&m_fast_s1_nonmem_q;
    wire [31:0] fast_pc=fast_target_s1?(m1_taken?mtarget1:m1_fall_q):(mtaken?mtarget_base:m_fall_q);
    wire [31:0] fast_pc4=fast_target_s1?(m1_taken?m1_tgt4_q:m1_fall4_q):(mtaken?m_tgt4_q:m_fall4_q);
    wire [31:0] fast_pc8=fast_target_s1?(m1_taken?m1_tgt8_q:m1_fall8_q):(mtaken?m_tgt8_q:m_fall8_q);

`ifndef SYNTHESIS
    wire [31:0] fast_pc_original=fast_s1?(m1_taken?mtarget1:m1_fall_q):(mtaken?mtarget_base:m_fall_q);
    wire [31:0] fast_pc4_original=fast_s1?(m1_taken?m1_tgt4_q:m1_fall4_q):(mtaken?m_tgt4_q:m_fall4_q);
    wire [31:0] fast_pc8_original=fast_s1?(m1_taken?m1_tgt8_q:m1_fall8_q):(mtaken?m_tgt8_q:m_fall8_q);
    integer fast_target_slot0_checks=0,fast_target_slot1_checks=0,fast_target_inactive_difference=0;
    always @(posedge clk) if(!rst) begin
        // Both premises also have their original packet-shape/class assertions.
        if(fast_target_s1) assert(slot1_branch_sel&&!mmem&&!mcontrol)
            else $fatal(1,"FAST_TARGET_PACKET_SHAPE");
        if(fast_redirect) begin
            assert(fast_target_s1===fast_s1&&
                {fast_pc,fast_pc4,fast_pc8}==={fast_pc_original,fast_pc4_original,fast_pc8_original})
                else $fatal(1,"FAST_TARGET_ACTIVE_IDENTITY");
            if(fast_target_s1) fast_target_slot1_checks<=fast_target_slot1_checks+1;
            else fast_target_slot0_checks<=fast_target_slot0_checks+1;
        end else if({fast_pc,fast_pc4,fast_pc8}!=={fast_pc_original,fast_pc4_original,fast_pc8_original})
            fast_target_inactive_difference<=fast_target_inactive_difference+1;
    end
    final $display("FAST_TARGET_COVER slot0=%0d slot1=%0d inactive_difference=%0d",
        fast_target_slot0_checks,fast_target_slot1_checks,fast_target_inactive_difference);
`endif
    // E/kill control: terminal_commit already kills and blocks e_fire, so the
    // terminal qualifier is redundant there and stays off this cone.
    wire m_redirect_ctl=m_done&&!m_bad&&(mpred_wrong||m1_redirect_raw);
    wire irq_take=irq_wait&&!mv&&!halted&&!fatal_error&&!terminal_stopped&&!run_stop;
    wire mret_commit=m_done&&!m_bad&&mmret;
    wire exception_enter=m_done&&m_bad&&(MACHINE_MODE!=0);
    wire perf_known;
    wire [31:0] perf_rdata;
    p2_csr csrs(
        .clk(clk),.rst(rst),.access_valid(mv&&mcsr),.access_addr(mi[31:20]),
        .access_write(csr_write),.access_wdata(csr_wdata),.access_commit(m_done&&!m_bad),
        .perf_known(perf_known),.perf_rdata(perf_rdata),
        .access_rdata(csr_rdata),.access_modify_rdata(csr_modify_rdata),.access_error(csr_error_reference),.retire(m_done&&!m_bad),
        .retire_second(m_done&&!m_bad&&mv1&&!terminal_commit),
        .trap_enter(exception_enter||irq_take),.trap_pc(irq_take?commit_next_pc:mp),
        .trap_cause(irq_take?irq_cause:m_final_cause),.trap_tval(irq_take?32'b0:m_final_tval),
        .mret_commit(mret_commit),.irq_software(irq_software),.irq_timer(irq_timer),
        .irq_external(irq_external),.irq_eligible(irq_eligible),.irq_cause(irq_cause),
        .handler_pc(handler_pc),.return_pc(return_pc),.machine_cycle(machine_cycle),.machine_retired(machine_retired));
    function automatic [12:0] load_format_decode(input [1:0] off,input [2:0] kind);
        reg byte_kind,half_kind,word_kind;
        integer lane;
        begin
            byte_kind=(kind==3'd0)||(kind==3'd4);
            half_kind=(kind==3'd1)||(kind==3'd5);
            word_kind=(kind==3'd2);
            load_format_decode=13'b0;
            for(lane=0;lane<4;lane=lane+1) begin
                load_format_decode[lane]=byte_kind&&(off==lane);
                load_format_decode[7+lane]=(kind==3'd0)&&(off==lane);
            end
            load_format_decode[0]=load_format_decode[0]||(half_kind&&!off[1])||word_kind;
            load_format_decode[2]=load_format_decode[2]||(half_kind&&off[1]);
            load_format_decode[4]=(half_kind&&!off[1])||word_kind;
            load_format_decode[5]=half_kind&&off[1];
            load_format_decode[6]=word_kind;
            load_format_decode[11]=(kind==3'd1)&&!off[1];
            load_format_decode[12]=(kind==3'd1)&&off[1];
        end
    endfunction
    reg [12:0] mload_format_q;
    wire [31:0] load_value;
    p2_load_format_predecoded load_align_predecoded(.data(d_rsp_data),
        .selectors(mload_format_q),.result(load_value));
`ifndef SYNTHESIS
    wire [31:0] load_value_reference;
    p1_load_align load_align_reference(.data(d_rsp_data),.offset(maddr[1:0]),
        .funct3(mfunct3),.result(load_value_reference));
    integer load_format_checks=0,load_format_reads=0;
    reg [7:0] load_format_kinds=0;
    reg [3:0] load_format_offsets=0;
    always @(posedge clk) if(!rst) begin
        assert(mload_format_q===load_format_decode(maddr[1:0],mfunct3))
            else $fatal(1,"LOAD_FORMAT_SELECTOR_COHORT");
        assert(load_value===load_value_reference)
            else $fatal(1,"LOAD_FORMAT_VALUE_IDENTITY");
        load_format_checks=load_format_checks+1;
        if(mv&&mmem&&!mwrite&&m_response) begin
            load_format_reads=load_format_reads+1;
            load_format_kinds[mfunct3]=1'b1;
            load_format_offsets[maddr[1:0]]=1'b1;
        end
    end
    final $display("LOAD_FORMAT_COVER checks=%0d reads=%0d kinds=%02h offsets=%01h",
        load_format_checks,load_format_reads,load_format_kinds,load_format_offsets);
`endif
    // Integer ALU eligibility is exact; immediate rs2-shaped bits are unused.
    function automatic integer_alu_encoding;
        input [31:0] insn;
        begin
            integer_alu_encoding=(insn[6:0]==7'h13 &&
                ((insn[14:12]!=1&&insn[14:12]!=5)||
                 (insn[14:12]==1&&insn[31:25]==0)||
                 (insn[14:12]==5&&(insn[31:25]==0||insn[31:25]==7'h20))))||
                (insn[6:0]==7'h33 && (insn[31:25]==0||
                 (insn[31:25]==7'h20&&(insn[14:12]==0||insn[14:12]==5))));
        end
    endfunction
    // One right barrel per ALU implements left/logical/arithmetic shifts.
    // Each call is a separate physical early or late execution lane.
    function automatic [31:0] integer_alu;
        input [31:0] insn,lhs,rhs;
        reg [31:0] right_value,shift_in,shift_out,shift_result;
        reg signed [32:0] signed_shift;
        reg [4:0] amount;
        reg is_sub,left_shift,arith_shift;
        integer k;
        begin
            right_value=(insn[6:0]==7'h13)?{{20{insn[31]}},insn[31:20]}:rhs;
            is_sub=(insn[6:0]==7'h33)&&insn[30];
            amount=right_value[4:0];left_shift=(insn[14:12]==1);
            arith_shift=(insn[14:12]==5)&&insn[30];
            for(k=0;k<32;k=k+1) shift_in[k]=left_shift?lhs[31-k]:lhs[k];
            signed_shift={arith_shift&&shift_in[31],shift_in};
            shift_out=signed_shift>>>amount;
            for(k=0;k<32;k=k+1) shift_result[k]=left_shift?shift_out[31-k]:shift_out[k];
            case(insn[14:12])
                0:integer_alu=lhs+(is_sub?~right_value:right_value)+is_sub;
                1,5:integer_alu=shift_result;
                2:integer_alu={31'b0,$signed(lhs)<$signed(right_value)};
                3:integer_alu={31'b0,lhs<right_value};
                4:integer_alu=lhs^right_value;
                6:integer_alu=lhs|right_value;
                7:integer_alu=lhs&right_value;
                default:integer_alu=0;
            endcase
        end
    endfunction
    function automatic [31:0] late_integer_alu;
        input [2:0] operation;
        input [31:0] lhs,right_value;
        input is_sub,left_shift,arith_shift;
        reg [31:0] shift_in,shift_out,shift_result;
        reg signed [32:0] signed_shift;
        integer k;
        begin
            for(k=0;k<32;k=k+1) shift_in[k]=left_shift?lhs[31-k]:lhs[k];
            signed_shift={arith_shift&&shift_in[31],shift_in};
            shift_out=signed_shift>>>right_value[4:0];
            for(k=0;k<32;k=k+1) shift_result[k]=left_shift?shift_out[31-k]:shift_out[k];
            case(operation)
                0:late_integer_alu=lhs+(is_sub?~right_value:right_value)+is_sub;
                1,5:late_integer_alu=shift_result;
                2:late_integer_alu={31'b0,$signed(lhs)<$signed(right_value)};
                3:late_integer_alu={31'b0,lhs<right_value};
                4:late_integer_alu=lhs^right_value;
                6:late_integer_alu=lhs|right_value;
                7:late_integer_alu=lhs&right_value;
                default:late_integer_alu=0;
            endcase
        end
    endfunction
    function automatic [31:0] selected_integer_alu;
        input [2:0] operation;
        input [31:0] lhs,right_value;
        input [31:0] arithmetic_result;
        input is_sub,left_shift,arith_shift;
        reg [31:0] shift_in,shift_out,shift_result;
        reg signed [32:0] signed_shift;
        integer k;
        begin
            for(k=0;k<32;k=k+1) shift_in[k]=left_shift?lhs[31-k]:lhs[k];
            signed_shift={arith_shift&&shift_in[31],shift_in};
            shift_out=signed_shift>>>right_value[4:0];
            for(k=0;k<32;k=k+1) shift_result[k]=left_shift?shift_out[31-k]:shift_out[k];
            case(operation)
                0:selected_integer_alu=arithmetic_result;
                1,5:selected_integer_alu=shift_result;
                2:selected_integer_alu={31'b0,$signed(lhs)<$signed(right_value)};
                3:selected_integer_alu={31'b0,lhs<right_value};
                4:selected_integer_alu=lhs^right_value;
                6:selected_integer_alu=lhs|right_value;
                7:selected_integer_alu=lhs&right_value;
                default:selected_integer_alu=0;
            endcase
        end
    endfunction
    // Separate left/right barrels eliminate data reversal selectors.
    // Masked parallel operation selection keeps wide results off serial muxes.
    // No register boundary, decode eligibility, or instruction timing changes.
    function automatic [31:0] parallel_integer_alu;
        input [2:0] operation;
        input [31:0] lhs,right_value;
        input [31:0] arithmetic_result;
        input is_sub,left_shift,arith_shift;
        reg [31:0] reverse_lhs,left_out,right_out,left_result;
        reg signed [32:0] signed_left,signed_right;
        reg choose_shift,choose_left,choose_right;
        integer k;
        begin
            for(k=0;k<32;k=k+1) reverse_lhs[k]=lhs[31-k];
            signed_left={arith_shift&&lhs[0],reverse_lhs};
            signed_right={arith_shift&&lhs[31],lhs};
            left_out=signed_left>>>right_value[4:0];
            right_out=signed_right>>>right_value[4:0];
            for(k=0;k<32;k=k+1) left_result[k]=left_out[31-k];
            choose_shift=(operation==1)||(operation==5);
            choose_left=choose_shift&&left_shift;
            choose_right=choose_shift&&!left_shift;
            parallel_integer_alu=
                ({32{operation==0}}&arithmetic_result)|
                ({32{choose_left}}&left_result)|
                ({32{choose_right}}&right_out)|
                ({32{operation==2}}&{31'b0,$signed(lhs)<$signed(right_value)})|
                ({32{operation==3}}&{31'b0,lhs<right_value})|
                ({32{operation==4}}&(lhs^right_value))|
                ({32{operation==6}}&(lhs|right_value))|
                ({32{operation==7}}&(lhs&right_value));
        end
    endfunction
    // Preserve arithmetic outputs before the operation mux. This prevents
    // comparison-result selection from being folded into carry propagation.
    (* syn_keep = 1 *) wire [31:0] late_arithmetic0=
        mbranch_a+(mlate_sub0?~mbranch_b:mbranch_b)+mlate_sub0;
    (* syn_keep = 1 *) wire [31:0] late_arithmetic1=
        mresult1_payload+(mlate_sub1?~mlate_b1:mlate_b1)+mlate_sub1;
    wire [31:0] m_alu_nonmul=mlate0?selected_integer_alu(mi[14:12],mbranch_a,mbranch_b,
        late_arithmetic0,mlate_sub0,mlate_left0,mlate_arith0):mresult;
    wire [31:0] m_alu_value=mmul_pipe_q?mul_result:m_alu_nonmul;
    wire [31:0] mresult1_nonmul=mlate1?selected_integer_alu(mi1[14:12],mresult1_payload,mlate_b1,
        late_arithmetic1,mlate_sub1,mlate_left1,mlate_arith1):mresult1_payload;
    wire [31:0] mresult1=mmul1_live_q?mul_result:mresult1_nonmul;

    wire [31:0] m_value = mcsr ? (csr_read?csr_rdata:32'b0) : (mmem && !mwrite) ? load_value : m_alu_value;
    // CSR operations serialize E. Their result is committed to the RF before
    // E can execute again; it is never required on the execution bypass.
    // Keep the full m_value for writeback/trace, but omit the wide CSR read
    // mux from the load/ALU-to-execute forwarding datapath.
    wire [31:0] m_execute_value=(mmem && !mwrite) ? load_value : m_alu_value;
    // A decoded constant operand has no dependency on older RF writers.
    // Its value is captured in the existing local RF payload, not muxed in E.
    reg e_const_a1_q,e_const_b1_q;
    wire [4:0] rs1_1=e_const_a1_q?5'b0:ei1[19:15];
    wire [4:0] rs2_1=e_const_b1_q?5'b0:ei1[24:20];
    wire m0_rs1=mr_nonzero_q&&hit0_rs1_q,m0_rs2=mr_nonzero_q&&hit0_rs2_q;
    wire m0_rs1_1=mr_nonzero_q&&hit0_rs1_1_q,m0_rs2_1=mr_nonzero_q&&hit0_rs2_1_q;
    wire m1_rs1=mr1_nonzero_q&&hit1_rs1_q,m1_rs2=mr1_nonzero_q&&hit1_rs2_q;
    wire m1_rs1_1=mr1_nonzero_q&&hit1_rs1_1_q,m1_rs2_1=mr1_nonzero_q&&hit1_rs2_1_q;
    // Move the four raw RF reads onto the existing D->E boundary. These
    // registers track the architectural RF value, before the M->E bypass.
    // RF source selection has moved across the existing capture edge.
    // Each lane stores the original rf_*_next masked value, including current
    // M commit forwarding. Held repair and constant/youngest-write priority
    // remain unchanged; E now uses the local FF output directly.
    reg [31:0] rf_a_local_q,rf_b_local_q,rf_a1_local_q,rf_b1_local_q;
    (* syn_maxfan=8 *) reg [2:0] rf_a_source_q,rf_b_source_q,rf_a1_source_q,rf_b1_source_q;
    wire [31:0] rf_a_q=rf_a_local_q;
    wire [31:0] rf_b_q=rf_b_local_q;
    wire [31:0] rf_a1_q=rf_a1_local_q;
    wire [31:0] rf_b1_q=rf_b1_local_q;
    wire rf_write0=m_done&&!m_bad&&mr_nonzero_q;
    wire rf_write1=m_done&&!m_bad&&mv1&&!terminal_commit&&mr1_nonzero_q;
    function automatic [31:0] read_decode_rf;
        input [4:0] index;
        begin
            read_decode_rf=(index==0 || !rf_valid_q[index]) ? 32'b0 :
                (rf_wb1_valid_q&&rf_wb1_rd_q==index)?rf_wb1_data_q:
                (rf_wb0_valid_q&&rf_wb0_rd_q==index)?rf_wb0_data_q:
                rf_owner_q[index] ? rf_bank1[index] : rf_bank0[index];
        end
    endfunction
    // Architectural commit remains at M. The pending write registers are
    // part of the visible RF and forward ahead of physical bank storage.
    // Payloads are disposable unless their original commit enable was true.
    always @(posedge clk) begin
        if(rst) begin
            rf_wb0_valid_q<=0;rf_wb1_valid_q<=0;
            rf_wb0_rd_q<=0;rf_wb1_rd_q<=0;rf_wb0_data_q<=0;rf_wb1_data_q<=0;
        end else begin
            rf_wb0_valid_q<=rf_write0;rf_wb1_valid_q<=rf_write1;
            rf_wb0_rd_q<=mr;rf_wb1_rd_q<=mr1;
            rf_wb0_data_q<=m_value;rf_wb1_data_q<=mresult1;
        end
    end
    always @(posedge clk) begin
        if(!rst && rf_wb0_valid_q) rf_bank0[rf_wb0_rd_q]<=rf_wb0_data_q;
    end
    always @(posedge clk) begin
        if(!rst && rf_wb1_valid_q) rf_bank1[rf_wb1_rd_q]<=rf_wb1_data_q;
    end
    always @(posedge clk) begin
        if(rst) begin rf_valid_q<=0;rf_owner_q<=0;end
        else begin
            if(rf_write0) begin rf_valid_q[mr]<=1;rf_owner_q[mr]<=0;end
            if(rf_write1) begin rf_valid_q[mr1]<=1;rf_owner_q[mr1]<=1;end
        end
    end
    // Preselect from the resident M packet while E is stalled. E can consume
    // these values only on e_fire; with mv high, e_fire implies m_done,
    // !m_bad, !serial_m and !terminal_commit. Architectural RF writes keep
    // their completed-commit qualifiers. Priority is unchanged: RF, older
    // M0, younger M1 (terminal guard constant true in machine mode), then
    // the LUI-pair constant for a1. Every non-load source is selected first;
    // a matching live M0 load enters only at the final 2:1 select, whose
    // registered-state select excludes an overriding M1 match and LUI pair.
    wire operand_m1_forward=mv&&mv1_exec&&((MACHINE_MODE!=0)||!terminal_commit);
    wire operand_m0_load=mv&&mmem&&!mwrite;
    wire a_live_load=operand_m0_load&&m0_rs1&&!(operand_m1_forward&&m1_rs1);
    wire b_live_load=operand_m0_load&&m0_rs2&&!(operand_m1_forward&&m1_rs2);
    wire a1_live_load=operand_m0_load&&m0_rs1_1&&!(operand_m1_forward&&m1_rs1_1)&&!e_lui_pair;
    wire b1_live_load=operand_m0_load&&m0_rs2_1&&!(operand_m1_forward&&m1_rs2_1);
    // Separate nets keep the load arm last instead of re-merging the chain.
    (* syn_keep = 1 *) wire [31:0] a_nonload=(operand_m1_forward&&m1_rs1)?mresult1:
        (mv&&m0_rs1)?m_alu_value:rf_a_q;
    (* syn_keep = 1 *) wire [31:0] b_nonload=(operand_m1_forward&&m1_rs2)?mresult1:
        (mv&&m0_rs2)?m_alu_value:rf_b_q;
    (* syn_keep = 1 *) wire [31:0] a1_nonload=e_lui_pair?imm_u:(operand_m1_forward&&m1_rs1_1)?mresult1:
        (mv&&m0_rs1_1)?m_alu_value:rf_a1_q;
    (* syn_keep = 1 *) wire [31:0] b1_nonload=(operand_m1_forward&&m1_rs2_1)?mresult1:
        (mv&&m0_rs2_1)?m_alu_value:rf_b1_q;
    reg [31:0] a, b,a1,b1;
    always @* begin
        a = a_live_load ? load_value : a_nonload;
        b = b_live_load ? load_value : b_nonload;
        a1 = a1_live_load ? load_value : a1_nonload;
        b1 = b1_live_load ? load_value : b1_nonload;
    end
`ifndef SYNTHESIS
    // Former m_execute_value priority chain, kept verbatim as a reference.
    reg [31:0] a_chain,b_chain,a1_chain,b1_chain;
    always @* begin
        a_chain = rf_a_q;
        b_chain = rf_b_q;
        a1_chain = rf_a1_q;
        b1_chain = rf_b1_q;
        if (mv) begin
            if (m0_rs1) a_chain = m_execute_value;
            if (m0_rs2) b_chain = m_execute_value;
            if (m0_rs1_1) a1_chain = m_execute_value;
            if (m0_rs2_1) b1_chain = m_execute_value;
        end
        if (mv && mv1_exec && ((MACHINE_MODE!=0)||!terminal_commit)) begin
            if (m1_rs1) a_chain = mresult1;
            if (m1_rs2) b_chain = mresult1;
            if (m1_rs1_1) a1_chain = mresult1;
            if (m1_rs2_1) b1_chain = mresult1;
        end
        if(e_lui_pair) a1_chain=imm_u;
    end
    integer operand_cut_checks=0,operand_cut_load=0,operand_cut_m1_override=0,operand_cut_lui=0;
    always @(posedge clk) if(!rst) begin
        assert({a,b,a1,b1}==={a_chain,b_chain,a1_chain,b1_chain})
            else $fatal(1,"OPERAND_LOAD_CUT_IDENTITY");
        operand_cut_checks=operand_cut_checks+1;
        if(a_live_load||b_live_load||a1_live_load||b1_live_load) operand_cut_load=operand_cut_load+1;
        if(operand_m0_load&&operand_m1_forward&&((m0_rs1&&m1_rs1)||(m0_rs2&&m1_rs2)||
           (m0_rs1_1&&m1_rs1_1)||(m0_rs2_1&&m1_rs2_1)))
            operand_cut_m1_override=operand_cut_m1_override+1;
        if(e_lui_pair&&operand_m0_load&&m0_rs1_1) operand_cut_lui=operand_cut_lui+1;
    end
    final $display("OPERAND_LOAD_CUT_COVER checks=%0d load=%0d m1_override=%0d lui=%0d",
        operand_cut_checks,operand_cut_load,operand_cut_m1_override,operand_cut_lui);
`endif

    // Late sources are identified after youngest-writer selection. A newer
    // early slot1 must override an older load/late slot0 classification.
    // Every changing dependency is explicit: do not hide resident-M state
    // inside a function called from a continuous assignment.
    function automatic source_is_slow;
        input valid0,valid1,hit0,hit1;
        input dep0,dep1,terminal;
        begin
            source_is_slow=0;
            if(valid0) begin
                if(valid1&&hit1&&((MACHINE_MODE!=0)||!terminal))
                    source_is_slow=dep1;
                else if(hit0) source_is_slow=dep0;
            end
        end
    endfunction
    wire e_integer0=integer_alu_encoding(ei),e_integer1=integer_alu_encoding(ei1);
    wire e_late0_ref=ev&&!ee&&e_integer0&&
        (source_is_slow(mv,mv1_exec,m0_rs1,m1_rs1,((mmem&&!mwrite)||mlate0),mlate1,terminal_commit)||((op==7'h33)&&source_is_slow(mv,mv1_exec,m0_rs2,m1_rs2,((mmem&&!mwrite)||mlate0),mlate1,terminal_commit)));
    wire e_late1_ref=e_late1_enable_q&&
        // Any M-forwarded source makes slot 1 late: its early ALU sees RF operands only.
        (source_is_slow(mv,mv1_exec,m0_rs1_1,m1_rs1_1,1'b1,1'b1,terminal_commit)||((ei1[6:0]==7'h33)&&source_is_slow(mv,mv1_exec,m0_rs2_1,m1_rs2_1,1'b1,1'b1,terminal_commit)));
    wire e_late0=(MACHINE_MODE!=0)?(ev&&!ee&&e_integer0&&mv&&(slowL_q[0]||((op==7'h33)&&slowL_q[1]))):e_late0_ref;
    wire e_late1=(MACHINE_MODE!=0)?(e_late1_enable_q&&mv&&(any_q[2]||((ei1[6:0]==7'h33)&&any_q[3]))):e_late1_ref;
    reg [1:0] early_fwd0_q,early_fwd1_q;
    wire early_fwd0_a=(MACHINE_MODE!=0)?early_fwd0_q[0]:
        ((!mmem||mwrite)&&!mlate0&&m0_rs1);
    wire early_fwd0_b=(MACHINE_MODE!=0)?early_fwd0_q[1]:
        ((!mmem||mwrite)&&!mlate0&&m0_rs2);
    wire early_fwd1_a=(MACHINE_MODE!=0)?early_fwd1_q[0]:
        (mv1_exec&&!mlate1&&!terminal_commit&&m1_rs1);
    wire early_fwd1_b=(MACHINE_MODE!=0)?early_fwd1_q[1]:
        (mv1_exec&&!mlate1&&!terminal_commit&&m1_rs2);
    reg [31:0] early_a,early_b,early_a1,early_b1;
    always @* begin
        early_a=rf_a_q;early_b=rf_b_q;early_a1=rf_a1_q;early_b1=rf_b1_q;
        if(mv) begin
            if(early_fwd0_a) early_a=mresult;
            if(early_fwd0_b) early_b=mresult;
            if(early_fwd1_a) early_a=mresult1_payload;
            if(early_fwd1_b) early_b=mresult1_payload;
        end
        if(e_lui_pair) early_a1=imm_u;
    end
    wire [31:0] early_right0=e_alu_imm0_q?{{20{ei[31]}},ei[31:20]}:early_b;
    wire [31:0] early_right1=e_alu_imm1_q?{{20{ei1[31]}},ei1[31:20]}:early_b1;
    (* syn_keep = 1 *) wire [31:0] early_arithmetic0=
        early_a+(e_alu_sub0_q?~early_right0:early_right0)+e_alu_sub0_q;
    (* syn_keep = 1 *) wire [31:0] early_arithmetic1=
        early_a1+(e_alu_sub1_q?~early_right1:early_right1)+e_alu_sub1_q;
    wire [31:0] early_alu0=parallel_integer_alu(ei[14:12],early_a,early_right0,
        early_arithmetic0,e_alu_sub0_q,e_alu_left0_q,e_alu_arith0_q);
    wire [31:0] early_alu1_raw=parallel_integer_alu(ei1[14:12],early_a1,early_right1,
        early_arithmetic1,e_alu_sub1_q,e_alu_left1_q,e_alu_arith1_q);
    wire [31:0] early_alu1=e_bitfusion?bitfusion_result(e_bitfusion_q,early_a,early_b):early_alu1_raw;

    // Zmmul multiply encodings are implemented; divide encodings and an
    // instruction-fetch fault do not acquire an operand interlock.
    wire e_is_mul=(HW_MUL!=0)&&(op==7'h33)&&(f7==7'h01)&&!f3[2];
    // HW_MUL enables the full Zmmul+Zbc integer-product hardware option.
    // Zbc stays out of ordinary integer ALU and normal multiply ownership.
    wire e_is_zbc=(HW_MUL!=0)&&(op==7'h33)&&(f7==7'h05)&&
        ((f3==3'd1)||(f3==3'd2)||(f3==3'd3));
    wire mul_raw_primary_dependency=mv&&(m0_rs1||m0_rs2);
    wire mul_raw_slot1_dependency=mv&&mv1_exec&&(m1_rs1||m1_rs2);
    wire mul_raw_dependency_ref=ev&&!ee&&e_is_mul&&
        (mul_raw_primary_dependency||mul_raw_slot1_dependency);
    wire mul_raw_dependency=(MACHINE_MODE!=0)?(ev&&!ee&&e_is_mul&&mv&&(any_q[0]||any_q[1])):mul_raw_dependency_ref;
    // No live M data or destination-select mux reaches the DSP input. On a
    // dependent completion edge M commits while E waits; existing held RF
    // repair captures both retiring slots with slot1 priority for next cycle.
    // Dedicated DSP operand registers (see mul_a_q). A MUL waits in E only
    // while an operand captured load/CSR data and is not yet refreshed.
    reg [31:0] mul_a_decode_q,mul_b_decode_q,mul_a_held_q,mul_b_held_q;
    reg mul_payload_q;
    reg mul_a_decode_stale_q,mul_b_decode_stale_q;
    reg mul_a_held_stale_q,mul_b_held_stale_q;
    wire [31:0] mul_a_q=mul_payload_q?mul_a_decode_q:mul_a_held_q;
    wire [31:0] mul_b_q=mul_payload_q?mul_b_decode_q:mul_b_held_q;
    wire mul_a_stale_q=mul_payload_q?mul_a_decode_stale_q:mul_a_held_stale_q;
    wire mul_b_stale_q=mul_payload_q?mul_b_decode_stale_q:mul_b_held_stale_q;
    wire mul_stale_hold=ev&&!ee&&e_is_mul&&(mul_a_stale_q||mul_b_stale_q);
    wire [31:0] mul_a=mul_a_q,mul_b=mul_b_q;
    wire zbc_raw_dependency=ev&&!ee&&e_is_zbc&&
        ((MACHINE_MODE!=0)?(mv&&(any_q[0]||any_q[1])):
         (mul_raw_primary_dependency||mul_raw_slot1_dependency));
    wire zbc_stale_hold=ev&&!ee&&e_is_zbc&&(mul_a_stale_q||mul_b_stale_q);
    wire zbc_ready;
    wire [31:0] zbc_result;
    wire zbc_take=ev&&!ee&&e_is_zbc&&!zbc_raw_dependency&&!zbc_stale_hold;
    wire zbc_hold=ev&&!ee&&e_is_zbc&&(!zbc_ready||zbc_raw_dependency||zbc_stale_hold);
    p2_clmul_pipeline clmul_pipe(.clk(clk),.rst(rst),.cancel(kill||!ev),
        .take(zbc_take),.consume(e_fire),.kind(f3),.a(mul_a),.b(mul_b),
        .ready(zbc_ready),.result(zbc_result));
    wire e_mul_high=e_is_mul&&(f3[1:0]!=0);
    wire e_mul_pipe=(MACHINE_MODE!=0)&&e_is_mul&&!e_mul_high;
    reg mul_low_ready;
    wire mul_low_hold=(MACHINE_MODE==0)&&ev&&!ee&&e_is_mul&&!e_mul_high&&!mul_low_ready;
    reg [2:0] mulh_state;
    reg [4:0] mulh_step;
    reg [31:0] mulh_hi,mulh_lo,mulh_a,mulh_b;
    reg mulh_signed_a,mulh_signed_b;
    wire mul_high_hold=ev&&!ee&&e_mul_high&&(mulh_state!=3'd4);
    wire [32:0] mulh_sum={1'b0,mulh_hi}+
        (mulh_lo[0]?{1'b0,mulh_a}:33'b0);

    // Isolate only memory address/store-data calculations from live load
    // returns. Ordinary ALU, slot1 ALU and M-stage branch operands keep their
    // original forwarding; a registered branch resolves in the following M.
    wire e_lsu_encoding=((op==7'h03)&&((f3==0)||(f3==1)||(f3==2)||(f3==4)||(f3==5)))||
                        ((op==7'h23)&&((f3==0)||(f3==1)||(f3==2)));
    wire agu_base_load_dependency_ref=mv&&((mmem&&!mwrite)||mmul_pipe_q)&&m0_rs1&&
        !(mv1_exec&&m1_rs1)||
        (mv&&mv1_exec&&m1_rs1&&mmul1_live_q);
    wire agu_store_load_dependency_ref=mv&&((mmem&&!mwrite)||mmul_pipe_q)&&m0_rs2&&
        !(mv1_exec&&m1_rs2)||
        (mv&&mv1_exec&&m1_rs2&&mmul1_live_q);
    wire agu_base_load_dependency=(MACHINE_MODE!=0)?(mv&&ld_q[0]):agu_base_load_dependency_ref;
    wire agu_store_load_dependency=(MACHINE_MODE!=0)?(mv&&ld_q[1]):agu_store_load_dependency_ref;
    wire jalr_load_dependency=ev&&!ee&&(op==7'h67)&&(f3==0)&&agu_base_load_dependency;
    wire agu_load_dependency=ev&&!ee&&e_lsu_encoding&&
        (agu_base_load_dependency||((op==7'h23)&&agu_store_load_dependency));
    wire agu_late_dependency_ref=ev&&!ee&&(e_lsu_encoding||((op==7'h67)&&(f3==0)))&&source_is_slow(mv,mv1_exec,m0_rs1,m1_rs1,mlate0,mlate1,terminal_commit);
    wire agu_late_dependency=(MACHINE_MODE!=0)?(ev&&!ee&&(e_lsu_encoding||((op==7'h67)&&(f3==0)))&&mv&&late_q):agu_late_dependency_ref;
    reg [31:0] agu_a,agu_b;
    always @* begin
        agu_a=rf_a_q;agu_b=rf_b_q;
        if(mv&&(!mmem||mwrite)) begin
            if(!mlate0&&m0_rs1) agu_a=mresult;
            if(m0_rs2) agu_b=m_alu_value;
        end
        if(mv&&mv1_exec&&((MACHINE_MODE!=0)||!terminal_commit)) begin
            if(!mlate1&&m1_rs1) agu_a=mresult1_payload;
            if(m1_rs2) agu_b=mresult1;
        end
    end

    // The early store bus excludes late ALU results. Such a store still
    // advances into M normally, where mwdata holds the completed result.
    wire store_data_late=source_is_slow(mv,mv1_exec,m0_rs2,m1_rs2,
        mlate0,mlate1,terminal_commit);
    reg [31:0] early_store_b;
    always @* begin
        early_store_b=rf_b_q;
        if(mv&&(!mmem||mwrite)&&!mlate0&&m0_rs2)
            early_store_b=mresult;
        if(mv&&mv1_exec&&!mlate1&&m1_rs2&&((MACHINE_MODE!=0)||!terminal_commit))
            early_store_b=mresult1_payload;
    end
    // RV32 MUL keeps only the low 32 bits. Three parallel 16x16 products
    // suffice; a carry-save reduction avoids a cascade of wide DSP products.
    wire e_is_mul1=(HW_MUL!=0)&&ev1&&!ee1&&
        (ei1[6:0]==7'h33)&&(ei1[31:25]==7'h01)&&(ei1[14:12]==0);
    wire mul1_raw_dependency=e_is_mul1&&
        (source_is_slow(mv,mv1_exec,m0_rs1_1,m1_rs1_1,1'b1,1'b1,terminal_commit)||
         source_is_slow(mv,mv1_exec,m0_rs2_1,m1_rs2_1,1'b1,1'b1,terminal_commit));
    reg mul1_ready;
    // Machine mode issues at the DSP sampling edge; M owns the product.
    wire e_mul1_pipe=(MACHINE_MODE!=0)&&e_is_mul1;
    wire mul1_hold=e_is_mul1&&(((MACHINE_MODE==0)&&!mul1_ready)||mul1_raw_dependency);
    // The held slot-1 RF is repaired at the older writer's commit edge.
    // Read it only for this unit's payload; issue remains ordered.
    wire [31:0] mul_shared_a=e_is_mul1?rf_a1_q:mul_a;
    wire [31:0] mul_shared_b=e_is_mul1?rf_b1_q:mul_b;
    wire [31:0] mul_ll=mul_shared_a[15:0]*mul_shared_b[15:0];
    wire [15:0] mul_lh=mul_shared_a[15:0]*mul_shared_b[31:16];
    wire [15:0] mul_hl=mul_shared_a[31:16]*mul_shared_b[15:0];
    reg [31:0] mul_ll_q;
    reg [15:0] mul_lh_q,mul_hl_q;
    // Free-running DSP output registers. Readiness protects their first
    // sample and any operand changes while an older producer retires.
    always @(posedge clk) begin
        mul_ll_q<=mul_ll;mul_lh_q<=mul_lh;mul_hl_q<=mul_hl;
    end
    wire [15:0] mul_hi_xor=mul_ll_q[31:16]^mul_lh_q^mul_hl_q;
    wire [15:0] mul_hi_carry=((mul_ll_q[31:16]&mul_lh_q)|
                             (mul_ll_q[31:16]&mul_hl_q)|(mul_lh_q&mul_hl_q))<<1;
    wire [15:0] mul_hi=mul_hi_xor+mul_hi_carry;
    assign mul_result={mul_hi,mul_ll_q[15:0]};

    // Exact sext12 address sum: only low12 uses native arithmetic.
    // Upper increment/decrement propagation is explicit prefix logic. Its
    // qualifiers depend only on base bits, never on the late low12 carry.
    function automatic [31:0] agu_add_signed12(
        input [31:0] base_value, input [31:0] signed_imm);
        reg [12:0] low_sum;
        reg inc,dec;
        reg [19:0] prefix_ones,prefix_zeros,upper_result;
        integer bitno;
        begin
            low_sum={1'b0,base_value[11:0]}+{1'b0,signed_imm[11:0]};
            inc=!signed_imm[31]&&low_sum[12];
            dec=signed_imm[31]&&!low_sum[12];
            prefix_ones[0]=1'b1;
            prefix_zeros[0]=1'b1;
            for(bitno=1;bitno<20;bitno=bitno+1) begin
                prefix_ones[bitno]=prefix_ones[bitno-1]&base_value[bitno+11];
                prefix_zeros[bitno]=prefix_zeros[bitno-1]&~base_value[bitno+11];
            end
            for(bitno=0;bitno<20;bitno=bitno+1)
                upper_result[bitno]=base_value[bitno+12]^
                    ((inc&prefix_ones[bitno])|(dec&prefix_zeros[bitno]));
            agu_add_signed12={upper_result,low_sum[11:0]};
        end
    endfunction

`ifndef SYNTHESIS
    // Independent old ordinary-case target equations; no new metadata/sum.
    reg [31:0] target_old_reference,target_old_imm;
    reg [1:0] target_old_kind;
    always @* begin
        target_old_reference=0;target_old_imm=0;target_old_kind=0;
        case(ei[6:0])
            7'h6f:begin
                target_old_reference=ep+{{11{ei[31]}},ei[31],ei[19:12],ei[20],ei[30:21],1'b0};
                target_old_imm={{11{ei[31]}},ei[31],ei[19:12],ei[20],ei[30:21],1'b0};
                target_old_kind=1;
            end
            7'h63:begin
                target_old_reference=ep+{{19{ei[31]}},ei[31],ei[7],ei[30:25],ei[11:8],1'b0};
                target_old_imm={{19{ei[31]}},ei[31],ei[7],ei[30:25],ei[11:8],1'b0};
                target_old_kind=1;
            end
            7'h67:begin
                target_old_reference=(agu_a+{{20{ei[31]}},ei[31:20]})&32'hfffffffe;
                target_old_kind=2;
            end
            default:begin end
        endcase
    end
    wire [31:0] target_old4,target_old8;
    assign target_old4[1:0]=target_old_reference[1:0];
    assign target_old4[2]=~target_old_reference[2];
    assign target_old8[2:0]=target_old_reference[2:0];
    assign target_old8[3]=~target_old_reference[3];
    generate for(genvar tr4=3;tr4<32;tr4=tr4+1) begin: target_old4_prefix
        assign target_old4[tr4]=target_old_reference[tr4]^(&target_old_reference[tr4-1:2]);
    end
    for(genvar tr8=4;tr8<32;tr8=tr8+1) begin: target_old8_prefix
        assign target_old8[tr8]=target_old_reference[tr8]^(&target_old_reference[tr8-1:3]);
    end endgenerate
    integer target_metadata_checks=0;
    always @(posedge clk) if(!rst) begin
        assert(e_target_kind_q===target_old_kind&&e_pc_target_imm_q===target_old_imm)
            else $fatal(1,"TARGET_METADATA_OWNER");
        assert(target===target_old_reference&&target_plus4===target_old4&&target_plus8===target_old8)
            else $fatal(1,"TARGET_OLD_CASE_IDENTITY");
        target_metadata_checks=target_metadata_checks+1;
    end
    final $display("TARGET_METADATA_COVER checks=%0d",target_metadata_checks);
`endif

    // Do not merge unrelated execute results into the AUIPC carry chain.
    (* syn_keep = 1 *) wire [31:0] auipc_value0=ep+imm_u;
    // Disjoint result masks eliminate the second wide opcode priority mux.
    (* syn_keep=1 *) wire [31:0] link_value0=ep+32'd4;
    wire er0_mul=(op==7'h33)&&e_is_mul;
    wire er0_integer=(op==7'h13)||((op==7'h33)&&!e_is_mul&&!e_is_zbc);
    wire [31:0] er=({32{op==7'h37}}&imm_u)|
        ({32{op==7'h17}}&auipc_value0)|
        ({32{(op==7'h6f)||(op==7'h67)}}&link_value0)|
        ({32{er0_integer}}&early_alu0)|
        ({32{er0_mul&&!e_mul_high}}&mul_result)|
        ({32{er0_mul&&e_mul_high}}&mulh_hi)|
        ({32{e_is_zbc}}&zbc_result);
    // TARGET_METADATA_BEGIN
    reg [1:0] d_target_kind,e_target_kind_q;
    reg [31:0] d_pc_target_imm,e_pc_target_imm_q;
    always @* begin
        d_target_kind=0;d_pc_target_imm=0;
        case(di[6:0])
            7'h6f: begin
                d_target_kind=1;
                d_pc_target_imm={{11{di[31]}},di[31],di[19:12],di[20],di[30:21],1'b0};
            end
            7'h63: begin
                d_target_kind=1;
                d_pc_target_imm={{19{di[31]}},di[31],di[7],di[30:25],di[11:8],1'b0};
            end
            7'h67: d_target_kind=2;
            default: begin end
        endcase
    end
    (* syn_keep=1 *) wire [31:0] pc_target_sum=ep+e_pc_target_imm_q;
    reg [31:0] target;
    always @* begin
        target=0;
        case(e_target_kind_q)
            1:target=pc_target_sum;
            2:target=(agu_a+imm_i)&32'hfffffffe;
            default:begin end
        endcase
    end
    // TARGET_METADATA_END
    reg [31:0] ea, ew, ecause, etval;
    reg [4:0] rd;
    reg [3:0] be;
    reg mem, wr, fault, legal, use1, use2,csr,mret,fencei;
    reg control,conditional;
    always @* begin
        ea=0; ew=0; ecause=2; etval=ei;
        rd=ei[11:7]; be=0; mem=0; wr=0; fault=0;
        legal=1; use1=0; use2=0;
        csr=0;mret=0;fencei=0;control=0;conditional=0;
        case (op)
            7'h37: begin end
            7'h17: begin end
            7'h6f: begin end
            7'h67: begin
                use1=1;
                if (f3!=0) legal=0;
            end
            7'h63: begin
                use1=1; use2=1; rd=0;
                case(f3)
                    0,1,4,5,6,7: legal=1;
                    default: legal=0;
                endcase
            end
            7'h03,7'h23: begin
                use1=1; use2=(op==7'h23); mem=1; wr=(op==7'h23);
                ea=agu_add_signed12(agu_a,e_lsu_imm); ew=agu_b << {ea[1:0],3'b000};
                if(wr) rd=0;
                case(f3)
                    0: be=4'b0001 << ea[1:0];
                    1: be=4'b0011 << ea[1:0];
                    2: be=4'b1111;
                    4: begin be=4'b0001 << ea[1:0]; if(wr) legal=0; end
                    5: begin be=4'b0011 << ea[1:0]; if(wr) legal=0; end
                    default: legal=0;
                endcase
                if (((f3==1 || f3==5) && ea[0]) || (f3==2 && |ea[1:0])) begin
                    fault=1; ecause=wr ? 6 : 4; etval=ea;
                end
            end
            7'h13: begin
                use1=1;
                if(!integer_alu_encoding(ei)) legal=0;
            end
            7'h33: begin
                use1=1;use2=1;
                if(!e_is_mul&&!e_is_zbc&&!integer_alu_encoding(ei)) legal=0;
            end
            // M serializes all accesses, so older device writes are acknowledged
            // before FENCE advances and no younger access can be issued yet.
            7'h0f: begin
                rd=0;
                if(f3==1&&MACHINE_MODE!=0) fencei=1;
                else if(f3!=0) legal=0;
            end
            7'h73: begin
                if(MACHINE_MODE!=0&&(f3==1||f3==2||f3==3||f3==5||f3==6||f3==7)) begin
                    csr=1;use1=!f3[2];
                end else begin
                    rd=0;etval=0;
                    if(ei==32'h00000073) begin fault=1;ecause=11;end
                    else if(ei==32'h00100073) begin fault=1;ecause=3;end
                    else if(ei==32'h30200073&&MACHINE_MODE!=0) mret=1;
                    else if(ei!=32'h10500073||MACHINE_MODE==0) legal=0;
                end
            end
            default: legal=0;
        endcase
        if(!legal) begin fault=1; ecause=2; etval=ei; mem=0; end
        if(ee) begin fault=1; ecause=1; etval=ep; mem=0; end
        control=(op==7'h63)||(op==7'h6f)||(op==7'h67);
        conditional=(op==7'h63);
        if(fault) begin rd=0;csr=0;mret=0;fencei=0;control=0;end
    end

    // Independent carry predicates avoid a second ripple adder after
    // the selected branch/JAL/JALR target. The existing M metadata identity
    // assertion compares both registered outputs against target+4/+8.
    wire [31:0] target_plus4,target_plus8;
    assign target_plus4[1:0]=target[1:0];
    assign target_plus4[2]=~target[2];
    assign target_plus8[2:0]=target[2:0];
    assign target_plus8[3]=~target[3];
    generate for(genvar bit4=3;bit4<32;bit4=bit4+1) begin: target4_prefix
        assign target_plus4[bit4]=target[bit4]^(&target[bit4-1:2]);
    end
    for(genvar bit8=4;bit8<32;bit8=bit8+1) begin: target8_prefix
        assign target_plus8[bit8]=target[bit8]^(&target[bit8-1:3]);
    end endgenerate

    // A deliberately narrow second pipe: integer ALU only, no side effects
    // before the older slot commits. Illegal encodings are never paired.
    wire [6:0] op1=ei1[6:0],f7_1=ei1[31:25];
    wire [2:0] f3_1=ei1[14:12];
    wire [31:0] imm_i1={{20{ei1[31]}},ei1[31:20]};
    wire [31:0] imm_u1={ei1[31:12],12'b0};
    (* syn_keep = 1 *) wire [31:0] auipc_value1=ep1+imm_u1;
    // One disjoint result selection includes fusion and opcode alternatives.
    // Keep the existing execute/late payload boundary and mode-0 MUL priority.
    wire er1_mul_sel=e_is_mul1&&(MACHINE_MODE==0);
    wire er1_integer_sel=!er1_mul_sel&&((op1==7'h13)||(op1==7'h33));
    wire [31:0] er1=({32{er1_mul_sel}}&mul_result)|
        ({32{!er1_mul_sel&&(op1==7'h37)}}&imm_u1)|
        ({32{!er1_mul_sel&&(op1==7'h17)}}&auipc_value1)|
        ({32{er1_integer_sel&&!(|e_fusion_sel_q)}}&early_alu1_raw)|
        ({32{er1_integer_sel&&e_fusion_sel_q[0]}}&{31'b0,early_a[0]^early_b[0]})|
        ({32{er1_integer_sel&&e_fusion_sel_q[1]}}&{early_a[15:0]^early_b[15:0],16'b0})|
        ({32{er1_integer_sel&&e_fusion_sel_q[2]}}&{16'b0,early_a[15:0]})|
        ({32{er1_integer_sel&&e_fusion_sel_q[3]}}&{{16{early_a[15]}},early_a[15:0]});
    wire [6:0] d0op=di[6:0],d1op=di1[6:0];
    wire [2:0] d1f3=di1[14:12];
    wire [6:0] d1f7=di1[31:25];
    // Pairing classes come from the frontend's registered predecode bits.
    wire d0_pairable=front_pre0[1];
    wire d1_simple=front_pre1[0];
    wire d1_mul=(MACHINE_MODE!=0)&&(HW_MUL!=0)&&(d1op==7'h33)&&
        (d1f7==7'h01)&&(d1f3==0)&&!(d0op==7'h33&&di[31:25]==7'h01)&&
        !(d0op==7'h33&&di[31:25]==7'h05&&
          ((di[14:12]==1)||(di[14:12]==2)||(di[14:12]==3)));
    wire d1_use1=front_pre1[3];
    wire d1_use2=front_pre1[4];
    // Six legal branches, 4-byte-aligned offset, no slot-0 branch.
    wire d1_branch=(MACHINE_MODE!=0)&&front_pre1[5]&&!front_pre0[6];
    wire d0_writes=front_pre0[2];
    // ADDI rd,x0,imm12 is a nontrapping literal producer. Only a legal,
    // aligned slot-1 branch can consume it within this packet. Both
    // original instructions still retire; no instruction is rewritten.
    wire d_const_branch=d1_branch&&(d0op==7'h13)&&(di[14:12]==0)&&
        (di[19:15]==0)&&(di[11:7]!=0);
    wire d_const_a1=d_const_branch&&(di1[19:15]==di[11:7]);
    wire d_const_b1=d_const_branch&&(di1[24:20]==di[11:7]);
    wire [4:0] d_src_a1=d_const_a1?5'b0:di1[19:15];
    wire [4:0] d_src_b1=d_const_b1?5'b0:di1[24:20];
    wire [31:0] d_const_value={{20{di[31]}},di[31:20]};
    // Only a literal LUI constant can satisfy this intra-packet RAW. No
    // ALU result feeds another ALU in the same execute stage.
    wire d_lui_pair=(d0op==7'h37)&&(di[11:7]!=0)&&
        (d1op==7'h13)&&(d1f3==0)&&(di1[19:15]==di[11:7]);
    // Predicted-taken conditional branch + its predicted target (simple slot 1).
    wire d_taken_pair=(MACHINE_MODE!=0)&&(d0op==7'h63)&&!front_sequential&&(d1_simple||d1_mul);
    wire pair_d=dv1&&!de&&!de1&&d0_pairable&&(d1_simple||d1_branch||d1_mul)&&
        (front_sequential||d_taken_pair)&&(front_sequential1||d1_branch)&&front_pair_link&&
        (d_lui_pair||d_const_branch||(d_bitfusion!=0)||!(d0_writes&&((d1_use1&&di1[19:15]==di[11:7])||
                       (d1_use2&&di1[24:20]==di[11:7])||
                       (!front_pre1[6]&&(di1[11:7]==di[11:7])))));

    wire branch_bitwise0=(mi[14:12]==4)||(mi[14:12]==6)||(mi[14:12]==7);
    wire branch_bitwise1=(mi1[14:12]==4)||(mi1[14:12]==6)||(mi1[14:12]==7);
    wire branch_word_load=mmem&&!mwrite&&(mfunct3==3'd2);
    wire branch_subword_load=mmem&&!mwrite&&(mfunct3!=3'd2);
    wire branch_slow0=(mmem&&!mwrite&&!branch_word_load)||(mlate0&&!branch_bitwise0);
    wire branch_slow1=mlate1&&!branch_bitwise1;
    function automatic [31:0] branch_bitwise_value;
        input [2:0] kind;
        input [31:0] lhs,rhs;
        begin
            case(kind)
                4:branch_bitwise_value=lhs^rhs;
                6:branch_bitwise_value=lhs|rhs;
                7:branch_bitwise_value=lhs&rhs;
                default:branch_bitwise_value=0;
            endcase
        end
    endfunction
    wire [31:0] branch_m0_value=branch_word_load?d_rsp_data:mlate0?branch_bitwise_value(mi[14:12],mbranch_a,mbranch_b):mresult;
    wire [31:0] branch_m1_value=mlate1?branch_bitwise_value(mi1[14:12],mresult1_payload,mlate_b1):mresult1_payload;
    wire branch0_slow_hold=ev&&!ee&&(op==7'h63)&&
        (source_is_slow(mv,mv1_exec,m0_rs1,m1_rs1,(branch_slow0&&!(!f3[2]&&branch_subword_load)),branch_slow1,terminal_commit)||
         source_is_slow(mv,mv1_exec,m0_rs2,m1_rs2,(branch_slow0&&!(!f3[2]&&branch_subword_load)),branch_slow1,terminal_commit));
    wire branch1_slow_hold=ev1&&!ee1&&(op1==7'h63)&&
        (source_is_slow(mv,mv1_exec,m0_rs1_1,m1_rs1_1,(branch_slow0&&!(!f3_1[2]&&branch_subword_load)),branch_slow1,terminal_commit)||
         source_is_slow(mv,mv1_exec,m0_rs2_1,m1_rs2_1,(branch_slow0&&!(!f3_1[2]&&branch_subword_load)),branch_slow1,terminal_commit));
    reg [31:0] branch0_a,branch0_b,branch1_a,branch1_b;
    reg [31:0] branch0_a_other,branch0_b_other,branch1_a_other,branch1_b_other;
    reg [3:0] branch_take0,branch_take1;
    wire [31:0] branch_m0_nonword=mlate0?
        branch_bitwise_value(mi[14:12],mbranch_a,mbranch_b):mresult;
    wire [3:0] branch_word_take=branch_take0&~branch_take1&{4{branch_word_load}};
    always @* begin
        branch_take0=0;branch_take1=0;
        branch0_a_other=rf_a_q;branch0_b_other=rf_b_q;
        branch1_a_other=rf_a1_q;branch1_b_other=rf_b1_q;
        if(mv&&!branch_slow0) begin
            if(m0_rs1) begin branch_take0[0]=1;branch0_a_other=branch_m0_nonword;end
            if(m0_rs2) begin branch_take0[1]=1;branch0_b_other=branch_m0_nonword;end
            if(m0_rs1_1) begin branch_take0[2]=1;branch1_a_other=branch_m0_nonword;end
            if(m0_rs2_1) begin branch_take0[3]=1;branch1_b_other=branch_m0_nonword;end
        end
        if(mv&&mv1_exec&&!branch_slow1&&((MACHINE_MODE!=0)||!terminal_commit)) begin
            if(m1_rs1) begin branch_take1[0]=1;branch0_a_other=branch_m1_value;end
            if(m1_rs2) begin branch_take1[1]=1;branch0_b_other=branch_m1_value;end
            if(m1_rs1_1) begin branch_take1[2]=1;branch1_a_other=branch_m1_value;end
            if(m1_rs2_1) begin branch_take1[3]=1;branch1_b_other=branch_m1_value;end
        end
        branch0_a=branch_word_take[0]?d_rsp_data:branch0_a_other;
        branch0_b=branch_word_take[1]?d_rsp_data:branch0_b_other;
        branch1_a=branch_word_take[2]?d_rsp_data:branch1_a_other;
        branch1_b=branch_word_take[3]?d_rsp_data:branch1_b_other;
    end
    // These equality-only leaves never feed the ordered comparator.
    // A newer M slot-1 writer wins even when slot 0 is a subword load.
    wire [3:0] branch_eq_load_take;
    assign branch_eq_load_take[0]=source_is_slow(mv,mv1_exec,m0_rs1,m1_rs1,branch_subword_load,1'b0,terminal_commit);
    assign branch_eq_load_take[1]=source_is_slow(mv,mv1_exec,m0_rs2,m1_rs2,branch_subword_load,1'b0,terminal_commit);
    assign branch_eq_load_take[2]=source_is_slow(mv,mv1_exec,m0_rs1_1,m1_rs1_1,branch_subword_load,1'b0,terminal_commit);
    assign branch_eq_load_take[3]=source_is_slow(mv,mv1_exec,m0_rs2_1,m1_rs2_1,branch_subword_load,1'b0,terminal_commit);
    wire word_equal0,word_high_lt0,word_high_eq0,word_lower_lt0,word_dir_lt0,word_dir_ge0;
    wire word_equal1,word_high_lt1,word_high_eq1,word_lower_lt1,word_dir_lt1,word_dir_ge1;
    p2_branch_predicate word_predicate0(branch0_a_other,branch0_b_other,d_rsp_data,
        branch_word_take[0],branch_word_take[1],f3,
        word_equal0,word_high_lt0,word_high_eq0,word_lower_lt0,word_dir_lt0,word_dir_ge0);
    p2_branch_predicate word_predicate1(branch1_a_other,branch1_b_other,d_rsp_data,
        branch_word_take[2],branch_word_take[3],f3_1,
        word_equal1,word_high_lt1,word_high_eq1,word_lower_lt1,word_dir_lt1,word_dir_ge1);
    wire load_eq_b0,load_eq_a0,load_eq_b1,load_eq_a1;
    p2_subword_eq eq_b0(d_rsp_data,branch0_b_other,maddr[1:0],mfunct3,load_eq_b0);
    p2_subword_eq eq_a0(d_rsp_data,branch0_a_other,maddr[1:0],mfunct3,load_eq_a0);
    p2_subword_eq eq_b1(d_rsp_data,branch1_b_other,maddr[1:0],mfunct3,load_eq_b1);
    p2_subword_eq eq_a1(d_rsp_data,branch1_a_other,maddr[1:0],mfunct3,load_eq_a1);
    wire branch0_equal=(&branch_eq_load_take[1:0])?1'b1:
        branch_eq_load_take[0]?load_eq_b0:
        branch_eq_load_take[1]?load_eq_a0:word_equal0;
    wire branch1_equal=(&branch_eq_load_take[3:2])?1'b1:
        branch_eq_load_take[2]?load_eq_b1:
        branch_eq_load_take[3]?load_eq_a1:word_equal1;
    wire serial_m=mv&&(mcsr||mmret||mfencei);
    // A load/late operand retires and repairs held RF before this pair can
    // execute. No slow result is routed through the specialized datapath.
    wire bitfusion_slow_hold=e_bitfusion&&e_late0;
    // Under the unchanged M-space and M-error guards, e_fire can
    // observe a valid M packet only on successful completion. The terminal
    // predicate can therefore use the registered packet fields directly.
    wire m_terminal_pending=mv&&mmem&&mwrite&&d_rsp_terminal;
    wire e_fire = ev && !zbc_hold && !mul1_hold && !branch0_slow_hold && !branch1_slow_hold && !mul_low_hold && !mul_high_hold && !bitfusion_slow_hold && !mul_raw_dependency && !mul_stale_hold && !agu_load_dependency && !jalr_load_dependency && !agu_late_dependency && (!mv || m_done) && !(m_done && m_bad) && !m_redirect_ctl && !halted &&
        !serial_m&&!irq_wait&&!fatal_error&&!run_stop&&!m_terminal_pending&&!terminal_stopped;
`ifndef SYNTHESIS
    wire original_terminal_e_fire = ev && !zbc_hold && !mul1_hold && !branch0_slow_hold && !branch1_slow_hold && !mul_low_hold && !mul_high_hold && !bitfusion_slow_hold && !mul_raw_dependency && !mul_stale_hold && !agu_load_dependency && !jalr_load_dependency && !agu_late_dependency && (!mv || m_done) && !(m_done && m_bad) && !m_redirect_ctl && !halted &&
        !serial_m&&!irq_wait&&!fatal_error&&!run_stop&&!terminal_commit&&!terminal_stopped;
    integer terminal_guard_checks=0,terminal_guard_pending=0;
    always @(posedge clk) if(!rst) begin
        assert(e_fire===original_terminal_e_fire) else $fatal(1,"EARLY_TERMINAL_E_FIRE_IDENTITY");
        terminal_guard_checks<=terminal_guard_checks+1;
        if(m_terminal_pending) terminal_guard_pending<=terminal_guard_pending+1;
    end
    final $display("TERMINAL_GUARD_COVER checks=%0d pending=%0d",terminal_guard_checks,terminal_guard_pending);
`endif
`ifndef SYNTHESIS
    reg [31:0] branch0_a_original,branch0_b_original,branch1_a_original,branch1_b_original;
    always @* begin
        branch0_a_original=rf_a_q;branch0_b_original=rf_b_q;
        branch1_a_original=rf_a1_q;branch1_b_original=rf_b1_q;
        if(mv&&!branch_slow0) begin
            if(m0_rs1) branch0_a_original=branch_m0_value;
            if(m0_rs2) branch0_b_original=branch_m0_value;
            if(m0_rs1_1) branch1_a_original=branch_m0_value;
            if(m0_rs2_1) branch1_b_original=branch_m0_value;
        end
        if(mv&&mv1_exec&&!branch_slow1&&((MACHINE_MODE!=0)||!terminal_commit)) begin
            if(m1_rs1) branch0_a_original=branch_m1_value;
            if(m1_rs2) branch0_b_original=branch_m1_value;
            if(m1_rs1_1) branch1_a_original=branch_m1_value;
            if(m1_rs2_1) branch1_b_original=branch_m1_value;
        end
    end
    integer branch_word_mux_checks=0,branch_word_mux_slot0=0,branch_word_mux_slot1=0;
    always @(posedge clk) if(!rst) begin
        assert({branch0_a,branch0_b,branch1_a,branch1_b}===
            {branch0_a_original,branch0_b_original,branch1_a_original,branch1_b_original})
            else $fatal(1,"BRANCH_WORD_LAST_MUX_IDENTITY");
        branch_word_mux_checks<=branch_word_mux_checks+1;
        if(e_fire&&!ee&&(op==7'h63)&&(|branch_word_take[1:0]))
            branch_word_mux_slot0<=branch_word_mux_slot0+1;
        if(e_fire&&ev1&&!ee1&&(op1==7'h63)&&(|branch_word_take[3:2]))
            branch_word_mux_slot1<=branch_word_mux_slot1+1;
    end
    final $display("BRANCH_WORD_LAST_MUX_COVER checks=%0d slot0=%0d slot1=%0d",
        branch_word_mux_checks,branch_word_mux_slot0,branch_word_mux_slot1);
`endif
    always @(posedge clk) begin
        if(rst) mcsr_illegal_q<=0;
        else if(e_fire) mcsr_illegal_q<=csr_permission_illegal(ei);
    end
    wire m_kill = m_done && m_bad;
    wire e_kill = e_fire && fault && MACHINE_MODE==0;
    wire maintenance_commit=m_done&&!m_bad&&mfencei;
    wire kill = m_kill || m_redirect_ctl || e_kill || irq_take || mret_commit || maintenance_commit || terminal_commit;
    always @(posedge clk) begin
        if(rst||kill||e_fire||!ev1) mul1_ready<=0;
        else if(e_is_mul1&&!mul1_raw_dependency) mul1_ready<=1;
    end
    always @(posedge clk) begin
        if(rst||kill||e_fire||!ev) mul_low_ready<=0;
        else if(!ee&&e_is_mul&&!e_mul_high&&!mul_raw_dependency&&!mul_stale_hold)
            mul_low_ready<=1;
    end
`ifndef SYNTHESIS
    integer mul_product_waits=0,mul_product_commits=0;
    always @(posedge clk) if(!rst) begin
        if(mul_low_hold) begin
            mul_product_waits=mul_product_waits+1;
            assert(!e_fire) else $fatal(1,"MUL_PRODUCT_PIPE_HOLD");
        end
        if(MACHINE_MODE==0&&e_fire&&!fault&&e_is_mul&&!e_mul_high) begin
            mul_product_commits=mul_product_commits+1;
            assert(mul_low_ready&&mul_result===(a*b))
                else $fatal(1,"MUL_PRODUCT_PIPE_RESULT");
        end
    end
    final $display("MUL_PRODUCT_PIPE_COVER waits=%0d commits=%0d",mul_product_waits,mul_product_commits);
`endif
    wire [31:0] redirect_pc=(exception_enter||irq_take)?handler_pc:mret_commit?return_pc:
        maintenance_commit?mp+32'd4:m_redirect1?(m1_taken?mtarget1:m1_fall_q):mnext;
    wire d_fire = dv && (!ev || e_fire) && !kill && !halted && !terminal_stopped;
    wire d_fire1=d_fire&&pair_d;
`ifndef SYNTHESIS
    reg [31:0] mul_pipe_expected_q;
    integer mul_pipe_capture=0,mul_pipe_retire=0,mul_pipe_dual=0;
    always @(posedge clk) begin
        if(rst) mul_pipe_expected_q<=0;
        else begin
            if(e_fire&&!fault&&e_mul_pipe) begin
                assert(!e_is_mul1&&mul_a===a&&mul_b===b&&!mem&&!control&&!csr)
                    else $fatal(1,"MUL_PIPE_INPUT_OWNERSHIP");
                mul_pipe_expected_q<=a*b;mul_pipe_capture<=mul_pipe_capture+1;
            end
            if(mv&&mmul_pipe_q) begin
                assert(m_done&&!m_bad&&!mmem&&!mcsr&&!mcontrol&&!mfencei&&
                       m_alu_value===mul_pipe_expected_q)
                    else $fatal(1,"MUL_PIPE_M_RESULT");
                mul_pipe_retire<=mul_pipe_retire+1;
                if(mv1) mul_pipe_dual<=mul_pipe_dual+1;
            end
        end
    end
    final $display("MUL_PIPE_COVER capture=%0d retire=%0d dual=%0d",
        mul_pipe_capture,mul_pipe_retire,mul_pipe_dual);
`endif

`ifndef SYNTHESIS
    integer subword_eq_slot0=0,subword_eq_slot1=0,subword_eq_both=0;
    reg [7:0] subword_eq_kinds=0;
    always @(posedge clk) if(!rst&&e_fire) begin
        if(!fault&&(op==7'h63)&&!f3[2]&&(|branch_eq_load_take[1:0])) begin
            assert(m_response&&!d_rsp_error&&branch0_equal===(a==b))
                else $fatal(1,"SUBWORD_EQ0_RESPONSE");
            subword_eq_slot0<=subword_eq_slot0+1;
            subword_eq_kinds[mfunct3]<=1'b1;
            if(&branch_eq_load_take[1:0]) subword_eq_both<=subword_eq_both+1;
        end
        if(ev1&&!fault&&(op1==7'h63)&&!f3_1[2]&&(|branch_eq_load_take[3:2])) begin
            assert(m_response&&!d_rsp_error&&branch1_equal===(a1==b1))
                else $fatal(1,"SUBWORD_EQ1_RESPONSE");
            subword_eq_slot1<=subword_eq_slot1+1;
            subword_eq_kinds[mfunct3]<=1'b1;
        end
    end
    final $display("SUBWORD_EQ_COVER slot0=%0d slot1=%0d both=%0d kinds=%0d",
        subword_eq_slot0,subword_eq_slot1,subword_eq_both,subword_eq_kinds);
`endif

`ifndef SYNTHESIS
    integer slot1mul_issued=0,slot1mul_executed=0,slot1mul_retired=0;
    integer slot1mul_raw=0,slot1mul_wait=0,slot1mul_annul=0,slot1mul_killed=0;
    integer slot1mul_memory_pair=0,slot1mul_control_pair=0;
    wire m_is_mul1=mv1_raw_q&&(mi1[6:0]==7'h33)&&
        (mi1[31:25]==7'h01)&&(mi1[14:12]==0);
    always @(posedge clk) if(!rst) begin
        if(d_fire1&&d1_mul) slot1mul_issued<=slot1mul_issued+1;
        if(mul1_raw_dependency) slot1mul_raw<=slot1mul_raw+1;
        if(mul1_hold) begin
            assert(!e_fire&&!d_fire) else $fatal(1,"SLOT1_MUL_INTERLOCK");
            slot1mul_wait<=slot1mul_wait+1;
        end
        if(ev&&e_is_mul1) begin
            assert(!e_is_mul) else $fatal(1,"SLOT1_MUL_RESOURCE_COLLISION");
            if(kill) slot1mul_killed<=slot1mul_killed+1;
        end
        if(e_fire&&e_is_mul1&&!fault) begin
            assert(!mul1_raw_dependency&&((MACHINE_MODE!=0)?
                   (mul_shared_a===a1&&mul_shared_b===b1):(mul1_ready&&mul_result===(a1*b1))))
                else $fatal(1,"SLOT1_MUL_PRODUCT");
            assert(rf_a1_q===a1&&rf_b1_q===b1)
                else $fatal(1,"SLOT1_MUL_REPAIRED_RF");
            slot1mul_executed<=slot1mul_executed+1;
        end
        if(m_done&&m_is_mul1) begin
            if(!m_bad&&mv1&&!terminal_commit) begin
                slot1mul_retired<=slot1mul_retired+1;
                if(mmem) slot1mul_memory_pair<=slot1mul_memory_pair+1;
                if(mcontrol) slot1mul_control_pair<=slot1mul_control_pair+1;
            end else begin
                assert(!rf_write1) else $fatal(1,"SLOT1_MUL_ANNUL_WRITE");
                slot1mul_annul<=slot1mul_annul+1;
            end
        end
    end
    reg [31:0] mul1_pipe_expected_q;
    reg mul1_pipe_resident_q;
    integer mul1_pipe_capture=0,mul1_pipe_first_done=0,mul1_pipe_saved=0,mul1_pipe_wait=0;
    integer mul1_pipe_newer_e_mul=0,mul1_pipe_memory=0,mul1_pipe_retire=0,mul1_pipe_annul=0;
    always @(posedge clk) begin
        if(rst) begin mul1_pipe_expected_q<=0;mul1_pipe_resident_q<=0;end
        else begin
            if(mv&&mul1_pipe_resident_q) begin
                assert(mresult1===mul1_pipe_expected_q&&!mmul_pipe_q)
                    else $fatal(1,"MUL1_PIPE_M_RESULT");
                if(mmul1_live_q) begin
                    if(m_done) mul1_pipe_first_done<=mul1_pipe_first_done+1;
                    else mul1_pipe_saved<=mul1_pipe_saved+1;
                end
                if(!m_done) begin
                    mul1_pipe_wait<=mul1_pipe_wait+1;
                    if(ev&&(e_is_mul||e_is_mul1)) mul1_pipe_newer_e_mul<=mul1_pipe_newer_e_mul+1;
                end
                if(m_done) begin
                    if(!m_bad&&mv1&&!terminal_commit) begin
                        mul1_pipe_retire<=mul1_pipe_retire+1;
                        if(mmem) mul1_pipe_memory<=mul1_pipe_memory+1;
                    end else mul1_pipe_annul<=mul1_pipe_annul+1;
                end
            end
            if(mv&&mmul1_live_q) assert(mul1_pipe_resident_q) else $fatal(1,"MUL1_PIPE_LIVE_OWNER");
            if(m_done) mul1_pipe_resident_q<=0;
            if(e_fire) begin
                mul1_pipe_resident_q<=e_mul1_pipe&&!fault;
                if(e_mul1_pipe&&!fault) begin
                    assert(!e_is_mul&&rf_a1_q===a1&&rf_b1_q===b1)
                        else $fatal(1,"MUL1_PIPE_INPUT_OWNERSHIP");
                    mul1_pipe_expected_q<=a1*b1;mul1_pipe_capture<=mul1_pipe_capture+1;
                end
            end
        end
    end
    final $display("MUL1_PIPE_COVER capture=%0d first_done=%0d saved=%0d wait=%0d newer_e_mul=%0d memory=%0d retire=%0d annul=%0d",
        mul1_pipe_capture,mul1_pipe_first_done,mul1_pipe_saved,mul1_pipe_wait,
        mul1_pipe_newer_e_mul,mul1_pipe_memory,mul1_pipe_retire,mul1_pipe_annul);
    final $display("SLOT1_MUL_COVER issued=%0d executed=%0d retired=%0d raw=%0d wait=%0d annul=%0d killed=%0d memory=%0d control=%0d",
        slot1mul_issued,slot1mul_executed,slot1mul_retired,slot1mul_raw,slot1mul_wait,
        slot1mul_annul,slot1mul_killed,slot1mul_memory_pair,slot1mul_control_pair);
`endif

`ifndef SYNTHESIS
    // Independent full-width polynomial oracle, deliberately not poly16.
    function automatic [63:0] zbc_polynomial_reference;
        input [31:0] lhs,rhs;
        reg [63:0] accum;
        integer bitno;
        begin
            accum=0;
            for(bitno=0;bitno<32;bitno=bitno+1)
                if(rhs[bitno]) accum=accum^({32'b0,lhs}<<bitno);
            zbc_polynomial_reference=accum;
        end
    endfunction
    wire [63:0] zbc_expected=zbc_polynomial_reference(a,b);
    wire [31:0] zbc_expected_result=(f3==1)?zbc_expected[31:0]:
        (f3==2)?zbc_expected[62:31]:zbc_expected[63:32];
    wire zbc_raw_reference=ev&&!ee&&e_is_zbc&&mv&&
        (((mr!=0)&&((mr==ei[19:15])||(mr==ei[24:20])))||
         (mv1_exec&&(mr1!=0)&&((mr1==ei[19:15])||(mr1==ei[24:20]))));
    integer zbc_c1=0,zbc_c2=0,zbc_c3=0,zbc_waits=0,zbc_cancels=0;
    always @(posedge clk) if(!rst) begin
        assert(zbc_raw_dependency===zbc_raw_reference) else $fatal(1,"ZBC_RAW_IDENTITY");
        if(zbc_take&&!zbc_ready&&!kill) begin
            assert(mul_a===a&&mul_b===b) else $fatal(1,"ZBC_SAMPLE_OPERANDS");
        end
        if(zbc_hold) begin
            zbc_waits=zbc_waits+1;
            assert(!e_fire) else $fatal(1,"ZBC_E_HOLD");
        end
        if(kill&&zbc_ready) zbc_cancels=zbc_cancels+1;
        if(e_fire&&!fault&&e_is_zbc) begin
            assert(zbc_ready&&!zbc_raw_dependency&&!zbc_stale_hold&&
                !e_late0&&!e_mul_pipe&&!e_is_mul1&&er===zbc_expected_result)
                else $fatal(1,"ZBC_RESULT_OWNER");
            case(f3)
                1:zbc_c1=zbc_c1+1;
                2:zbc_c2=zbc_c2+1;
                3:zbc_c3=zbc_c3+1;
            endcase
        end
    end
    final $display("ZBC_COVER clmul=%0d clmulr=%0d clmulh=%0d wait=%0d cancel=%0d",
        zbc_c1,zbc_c2,zbc_c3,zbc_waits,zbc_cancels);
`endif

    // Operands are accepted only after the existing RAW/stale interlocks.
    // A killed operation cannot publish a result into a replacement E slot.
    always @(posedge clk) begin
        if(rst||kill||e_fire||!ev) begin
            mulh_state<=0;mulh_step<=0;mulh_hi<=0;mulh_lo<=0;
            mulh_a<=0;mulh_b<=0;mulh_signed_a<=0;mulh_signed_b<=0;
        end else case(mulh_state)
            0: if(!ee&&e_mul_high&&!mul_raw_dependency&&!mul_stale_hold) begin
                mulh_a<=mul_a;mulh_b<=mul_b;mulh_hi<=0;mulh_lo<=mul_b;
                mulh_signed_a<=mul_a[31]&&(f3!=3);
                mulh_signed_b<=mul_b[31]&&(f3==1);
                mulh_step<=0;mulh_state<=1;
            end
            1: begin
                {mulh_hi,mulh_lo}<={mulh_sum,mulh_lo[31:1]};
                if(mulh_step==31) mulh_state<=2;
                else mulh_step<=mulh_step+1'b1;
            end
            2: begin
                if(mulh_signed_a) mulh_hi<=mulh_hi-mulh_b;
                mulh_state<=3;
            end
            3: begin
                if(mulh_signed_b) mulh_hi<=mulh_hi-mulh_a;
                mulh_state<=4;
            end
            default: begin end
        endcase
    end
`ifndef SYNTHESIS
    wire signed [32:0] mulh_ref_a={((f3!=3)&&a[31]),a};
    wire signed [32:0] mulh_ref_b={((f3==1)&&b[31]),b};
    wire signed [65:0] mulh_ref_product=mulh_ref_a*mulh_ref_b;
    integer zmmul_low_count=0,zmmul_h_count=0,zmmul_hsu_count=0,zmmul_hu_count=0;
    integer zmmul_cancel_count=0,zmmul_wait_count=0;
    always @(posedge clk) if(!rst) begin
        if(mul_high_hold) begin
            zmmul_wait_count=zmmul_wait_count+1;
            assert(!e_fire) else $fatal(1,"ZMMUL_E_HOLD");
        end
        if(kill&&mulh_state!=0) zmmul_cancel_count=zmmul_cancel_count+1;
        if(e_fire&&!fault&&e_is_mul) begin
            case(f3)
                0: zmmul_low_count=zmmul_low_count+1;
                1: zmmul_h_count=zmmul_h_count+1;
                2: zmmul_hsu_count=zmmul_hsu_count+1;
                3: zmmul_hu_count=zmmul_hu_count+1;
            endcase
            if(e_mul_high) assert(mulh_state==4&&mulh_hi===mulh_ref_product[63:32])
                else $fatal(1,"ZMMUL_HIGH_RESULT");
        end
    end
    final $display("ZMMUL_COVER low=%0d h=%0d hsu=%0d hu=%0d cancel=%0d wait=%0d",
        zmmul_low_count,zmmul_h_count,zmmul_hsu_count,zmmul_hu_count,zmmul_cancel_count,zmmul_wait_count);
`endif

`ifndef SYNTHESIS
    always @(posedge clk) if(!rst&&dv&&dv1)
        assert((front_sequential&&front_sequential1&&dp1==front_prediction) ===
          (dp1==dp+32'd4&&front_prediction==dp+32'd4&&front_prediction1==dp1+32'd4))
            else $fatal(1,"FRONTSEQ_PAIR_EQUIVALENCE");
`endif
    // The payload may be captured when E is empty or would advance before
    // late M exception/redirect/terminal qualification. Those late outcomes
    // discard E at this edge, so an unused speculative payload is harmless.
    // Dependencies, serial M, IRQ and run-stop retain the original held-E
    // repair path. Mode 0 preserves its terminal-edge fault observation.
    wire rf_capture_early=!zbc_hold&&!mul1_hold&&!branch0_slow_hold&&!branch1_slow_hold&&!mul_low_hold&&!mul_high_hold&&!bitfusion_slow_hold&&!mul_raw_dependency&&!mul_stale_hold&&!agu_load_dependency&&
        !jalr_load_dependency&&!agu_late_dependency&&(!mv||m_done)&&
        !halted&&!serial_m&&!irq_wait&&!fatal_error&&!run_stop&&!terminal_stopped;
    wire rf_payload_capture=(MACHINE_MODE==0)?d_fire:(!ev||rf_capture_early);
    // Match decode and held addresses in parallel. Keep all architectural
    // write qualifiers unchanged and select the youngest writer first.
    // Data uses three mutually exclusive terms; no extra cycle or index mux.
    wire rf_operand_write0=(MACHINE_MODE!=0)?(m_done&&mr_nonzero_q):rf_write0;
    wire rf_operand_write1=(MACHINE_MODE!=0)?(m_done&&mv1_exec&&mr1_nonzero_q):rf_write1;
    wire rf_a_m1=rf_operand_write1&&((rf_payload_capture&&mr1==di[19:15])||(!rf_payload_capture&&hit1_rs1_q));
    wire rf_a_m0=rf_operand_write0&&!rf_a_m1&&((rf_payload_capture&&mr==di[19:15])||(!rf_payload_capture&&hit0_rs1_q));
    wire rf_a_raw=rf_payload_capture&&!rf_a_m0&&!rf_a_m1;
    wire rf_a_enable=rf_payload_capture||rf_a_m0||rf_a_m1;
    wire [31:0] rf_a_next=({32{rf_a_m1}}&mresult1)|
        ({32{rf_a_m0}}&m_value)|({32{rf_a_raw}}&read_decode_rf(di[19:15]));
    wire rf_b_m1=rf_operand_write1&&((rf_payload_capture&&mr1==di[24:20])||(!rf_payload_capture&&hit1_rs2_q));
    wire rf_b_m0=rf_operand_write0&&!rf_b_m1&&((rf_payload_capture&&mr==di[24:20])||(!rf_payload_capture&&hit0_rs2_q));
    wire rf_b_raw=rf_payload_capture&&!rf_b_m0&&!rf_b_m1;
    wire rf_b_enable=rf_payload_capture||rf_b_m0||rf_b_m1;
    wire [31:0] rf_b_next=({32{rf_b_m1}}&mresult1)|
        ({32{rf_b_m0}}&m_value)|({32{rf_b_raw}}&read_decode_rf(di[24:20]));
    wire rf_a1_m1=rf_operand_write1&&((rf_payload_capture&&!d_const_a1&&mr1==di1[19:15])||(!rf_payload_capture&&hit1_rs1_1_q));
    wire rf_a1_m0=rf_operand_write0&&!rf_a1_m1&&((rf_payload_capture&&!d_const_a1&&mr==di1[19:15])||(!rf_payload_capture&&hit0_rs1_1_q));
    wire rf_a1_raw=rf_payload_capture&&!rf_a1_m0&&!rf_a1_m1;
    wire rf_a1_enable=rf_payload_capture||rf_a1_m0||rf_a1_m1;
    wire [31:0] rf_a1_next=({32{rf_a1_m1}}&mresult1)|
        ({32{rf_a1_m0}}&m_value)|({32{rf_a1_raw}}&(d_const_a1?d_const_value:read_decode_rf(di1[19:15])));
    wire rf_b1_m1=rf_operand_write1&&((rf_payload_capture&&!d_const_b1&&mr1==di1[24:20])||(!rf_payload_capture&&hit1_rs2_1_q));
    wire rf_b1_m0=rf_operand_write0&&!rf_b1_m1&&((rf_payload_capture&&!d_const_b1&&mr==di1[24:20])||(!rf_payload_capture&&hit0_rs2_1_q));
    wire rf_b1_raw=rf_payload_capture&&!rf_b1_m0&&!rf_b1_m1;
    wire rf_b1_enable=rf_payload_capture||rf_b1_m0||rf_b1_m1;
    wire [31:0] rf_b1_next=({32{rf_b1_m1}}&mresult1)|
        ({32{rf_b1_m0}}&m_value)|({32{rf_b1_raw}}&(d_const_b1?d_const_value:read_decode_rf(di1[24:20])));
    // WB payloads capture the exact original M data at this same edge.
    // On a held operand, copy its visible value locally before WB changes.
    // Bit masks preserve the original four-state AND/OR selection semantics.
    always @(posedge clk) begin
        if(rst) begin
            rf_a_local_q<=0;rf_b_local_q<=0;rf_a1_local_q<=0;rf_b1_local_q<=0;
            rf_a_source_q<=3'b001;rf_b_source_q<=3'b001;
            rf_a1_source_q<=3'b001;rf_b1_source_q<=3'b001;
        end else begin
            rf_a_local_q<=rf_a_q;rf_a_source_q<=3'b001;
            if(rf_a_enable) begin
                rf_a_local_q<=rf_a_next;
                rf_a_source_q<={rf_a_m1,rf_a_m0,rf_a_raw};
            end
            rf_b_local_q<=rf_b_q;rf_b_source_q<=3'b001;
            if(rf_b_enable) begin
                rf_b_local_q<=rf_b_next;
                rf_b_source_q<={rf_b_m1,rf_b_m0,rf_b_raw};
            end
            rf_a1_local_q<=rf_a1_q;rf_a1_source_q<=3'b001;
            if(rf_a1_enable) begin
                rf_a1_local_q<=rf_a1_next;
                rf_a1_source_q<={rf_a1_m1,rf_a1_m0,rf_a1_raw};
            end
            rf_b1_local_q<=rf_b1_q;rf_b1_source_q<=3'b001;
            if(rf_b1_enable) begin
                rf_b1_local_q<=rf_b1_next;
                rf_b1_source_q<={rf_b1_m1,rf_b1_m0,rf_b1_raw};
            end
        end
    end
`ifndef SYNTHESIS
    reg [31:0] rf_capture_original_a,rf_capture_original_b;
    reg [31:0] rf_capture_original_a1,rf_capture_original_b1;
    always @(posedge clk) begin
        if(rst) begin
            rf_capture_original_a<=0;rf_capture_original_b<=0;rf_capture_original_a1<=0;rf_capture_original_b1<=0;
        end else begin
            if(rf_a_enable) rf_capture_original_a<=rf_a_next;
            if(rf_b_enable) rf_capture_original_b<=rf_b_next;
            if(rf_a1_enable) rf_capture_original_a1<=rf_a1_next;
            if(rf_b1_enable) rf_capture_original_b1<=rf_b1_next;
        end
    end
    integer rf_capture_bank_checks=0,rf_capture_bank_m0=0,rf_capture_bank_m1=0;
    always @(posedge clk) if(!rst) begin
        assert({rf_a_q,rf_b_q,rf_a1_q,rf_b1_q}===
               {rf_capture_original_a,rf_capture_original_b,rf_capture_original_a1,rf_capture_original_b1})
            else $fatal(1,"RF_OPERAND_CAPTURE_BANK_IDENTITY");
        rf_capture_bank_checks<=rf_capture_bank_checks+1;
        if(rf_a_source_q[1]||rf_b_source_q[1]||rf_a1_source_q[1]||rf_b1_source_q[1])
            rf_capture_bank_m0<=rf_capture_bank_m0+1;
        if(rf_a_source_q[2]||rf_b_source_q[2]||rf_a1_source_q[2]||rf_b1_source_q[2])
            rf_capture_bank_m1<=rf_capture_bank_m1+1;
    end
    final $display("RF_OPERAND_CAPTURE_COVER checks=%0d m0=%0d m1=%0d",
        rf_capture_bank_checks,rf_capture_bank_m0,rf_capture_bank_m1);
`endif
    // Capture both possible operand payloads before the selector arrives.
    // irq_wait stays on the original RF/control cone; only its registered
    // payload selector reaches the multiplier's operand choice.
    wire mul_m0_slow=mcsr||(mmem&&!mwrite)||mmul_pipe_q;
    wire mul_da1=rf_operand_write1&&(mr1==di[19:15]);
    wire mul_da0=rf_operand_write0&&!mul_da1&&(mr==di[19:15]);
    wire mul_db1=rf_operand_write1&&(mr1==di[24:20]);
    wire mul_db0=rf_operand_write0&&!mul_db1&&(mr==di[24:20]);
    wire mul_ha1=rf_operand_write1&&hit1_rs1_q;
    wire mul_ha0=rf_operand_write0&&!mul_ha1&&hit0_rs1_q;
    wire mul_hb1=rf_operand_write1&&hit1_rs2_q;
    wire mul_hb0=rf_operand_write0&&!mul_hb1&&hit0_rs2_q;
    wire [31:0] mul_a_decode_next=({32{mul_da1}}&mresult1_nonmul)|
        ({32{mul_da0}}&m_alu_nonmul)|({32{!mul_da1&&!mul_da0}}&read_decode_rf(di[19:15]));
    wire [31:0] mul_b_decode_next=({32{mul_db1}}&mresult1_nonmul)|
        ({32{mul_db0}}&m_alu_nonmul)|({32{!mul_db1&&!mul_db0}}&read_decode_rf(di[24:20]));
    wire [31:0] mul_a_held_next=({32{mul_ha1}}&mresult1_nonmul)|
        ({32{mul_ha0}}&m_alu_nonmul)|({32{!mul_ha1&&!mul_ha0}}&rf_a_q);
    wire [31:0] mul_b_held_next=({32{mul_hb1}}&mresult1_nonmul)|
        ({32{mul_hb0}}&m_alu_nonmul)|({32{!mul_hb1&&!mul_hb0}}&rf_b_q);
    always @(posedge clk) begin
        if(rst) begin
            mul_a_decode_q<=0;mul_b_decode_q<=0;mul_a_held_q<=0;mul_b_held_q<=0;
            mul_payload_q<=0;
            mul_a_decode_stale_q<=0;mul_b_decode_stale_q<=0;
            mul_a_held_stale_q<=0;mul_b_held_stale_q<=0;
        end else begin
            mul_a_decode_q<=mul_a_decode_next;mul_b_decode_q<=mul_b_decode_next;
            mul_a_held_q<=mul_a_held_next;mul_b_held_q<=mul_b_held_next;
            mul_payload_q<=rf_payload_capture;
            mul_a_decode_stale_q<=(mul_da0&&mul_m0_slow)||(mul_da1&&mmul1_live_q);
            mul_b_decode_stale_q<=(mul_db0&&mul_m0_slow)||(mul_db1&&mmul1_live_q);
            mul_a_held_stale_q<=(mul_ha0&&mul_m0_slow)||(mul_ha1&&mmul1_live_q);
            mul_b_held_stale_q<=(mul_hb0&&mul_m0_slow)||(mul_hb1&&mmul1_live_q);
        end
    end
`ifndef SYNTHESIS
    reg [31:0] original_mul_a_q,original_mul_b_q;
    reg original_mul_a_stale_q,original_mul_b_stale_q;
    // MUL operand registers: same selects as rf_a/rf_b, but slot-0 M data is
    // the ALU value only. A load/CSR (slow) capture marks the operand stale;
    // any cycle without a capture copies the settled rf_a_q/rf_b_q.
    // Invariant: !mul_x_stale_q -> mul_x_q==rf_x_q.
    wire [31:0] mul_a_next=({32{rf_a_m1}}&mresult1_nonmul)|({32{rf_a_m0}}&m_alu_nonmul)|
        ({32{rf_a_raw}}&read_decode_rf(di[19:15]))|({32{!rf_a_enable}}&rf_a_q);
    wire [31:0] mul_b_next=({32{rf_b_m1}}&mresult1_nonmul)|({32{rf_b_m0}}&m_alu_nonmul)|
        ({32{rf_b_raw}}&read_decode_rf(di[24:20]))|({32{!rf_b_enable}}&rf_b_q);
    always @(posedge clk) begin
        if(rst) begin
            original_mul_a_q<=0;original_mul_b_q<=0;original_mul_a_stale_q<=0;original_mul_b_stale_q<=0;
        end else begin
            original_mul_a_q<=mul_a_next;original_mul_b_q<=mul_b_next;
            original_mul_a_stale_q<=(rf_a_m0&&mul_m0_slow)||(rf_a_m1&&mmul1_live_q);
            original_mul_b_stale_q<=(rf_b_m0&&mul_m0_slow)||(rf_b_m1&&mmul1_live_q);
        end
    end
    integer mul_operand_bank_checks=0,mul_operand_bank_irq=0,mul_operand_bank_slow=0;
    always @(posedge clk) if(!rst) begin
        assert({mul_a_q,mul_b_q,mul_a_stale_q,mul_b_stale_q}===
               {original_mul_a_q,original_mul_b_q,original_mul_a_stale_q,original_mul_b_stale_q})
            else $fatal(1,"MUL_OPERAND_BANK_IDENTITY");
        mul_operand_bank_checks<=mul_operand_bank_checks+1;
        if(irq_wait) mul_operand_bank_irq<=mul_operand_bank_irq+1;
        if(mul_a_stale_q||mul_b_stale_q) mul_operand_bank_slow<=mul_operand_bank_slow+1;
    end
    final $display("MUL_OPERAND_BANK_COVER checks=%0d irq=%0d slow=%0d",
        mul_operand_bank_checks,mul_operand_bank_irq,mul_operand_bank_slow);
`endif
`ifndef SYNTHESIS
    integer branch1_slow_waits=0,branch1_early_compares=0;
    always @(posedge clk) if(!rst) begin
        if(branch1_slow_hold) begin
            branch1_slow_waits=branch1_slow_waits+1;
            assert(!e_fire&&!d_fire) else $fatal(1,"BRANCH1_SLOW_INTERLOCK");
        end
        if(e_fire&&ev1&&!ee1&&(op1==7'h63)) begin
            branch1_early_compares=branch1_early_compares+1;
            assert(f3_1[2]?(branch1_a===a1&&branch1_b===b1):(branch1_equal===(a1==b1)))
                else $fatal(1,"BRANCH1_EARLY_OPERAND_IDENTITY");
        end
    end
    final $display("BRANCH1_BOUNDARY_COVER waits=%0d compares=%0d",branch1_slow_waits,branch1_early_compares);
`endif
`ifndef SYNTHESIS
    integer branch0_slow_waits=0,branch0_early_compares=0;
    always @(posedge clk) if(!rst) begin
        if(branch0_slow_hold) begin
            branch0_slow_waits=branch0_slow_waits+1;
            assert(!e_fire&&!d_fire) else $fatal(1,"BRANCH0_SLOW_INTERLOCK");
        end
        if(e_fire&&!ee&&(op==7'h63)) begin
            branch0_early_compares=branch0_early_compares+1;
            assert(f3[2]?(branch0_a===a&&branch0_b===b):(branch0_equal===(a==b)))
                else $fatal(1,"BRANCH0_EARLY_OPERAND_IDENTITY");
        end
    end
    final $display("BRANCH0_BOUNDARY_COVER waits=%0d compares=%0d",branch0_slow_waits,branch0_early_compares);
`endif
`ifndef SYNTHESIS
    integer branch_bitwise_used0=0,branch_bitwise_used1=0;
    always @(posedge clk) if(!rst&&e_fire) begin
        if(!ee&&(op==7'h63)&&
           (source_is_slow(mv,mv1_exec,m0_rs1,m1_rs1,mlate0&&branch_bitwise0,mlate1&&branch_bitwise1,terminal_commit)||
            source_is_slow(mv,mv1_exec,m0_rs2,m1_rs2,mlate0&&branch_bitwise0,mlate1&&branch_bitwise1,terminal_commit)))
            branch_bitwise_used0=branch_bitwise_used0+1;
        if(ev1&&!ee1&&(op1==7'h63)&&
           (source_is_slow(mv,mv1_exec,m0_rs1_1,m1_rs1_1,mlate0&&branch_bitwise0,mlate1&&branch_bitwise1,terminal_commit)||
            source_is_slow(mv,mv1_exec,m0_rs2_1,m1_rs2_1,mlate0&&branch_bitwise0,mlate1&&branch_bitwise1,terminal_commit)))
            branch_bitwise_used1=branch_bitwise_used1+1;
    end
    final $display("BRANCH_BITWISE_COVER slot0=%0d slot1=%0d",branch_bitwise_used0,branch_bitwise_used1);
`endif
`ifndef SYNTHESIS
    integer branch_word_used0=0,branch_word_used1=0;
    always @(posedge clk) if(!rst&&e_fire) begin
        if(!ee&&(op==7'h63)&&
           (source_is_slow(mv,mv1_exec,m0_rs1,m1_rs1,branch_word_load,1'b0,terminal_commit)||
            source_is_slow(mv,mv1_exec,m0_rs2,m1_rs2,branch_word_load,1'b0,terminal_commit)))
            branch_word_used0=branch_word_used0+1;
        if(ev1&&!ee1&&(op1==7'h63)&&
           (source_is_slow(mv,mv1_exec,m0_rs1_1,m1_rs1_1,branch_word_load,1'b0,terminal_commit)||
            source_is_slow(mv,mv1_exec,m0_rs2_1,m1_rs2_1,branch_word_load,1'b0,terminal_commit)))
            branch_word_used1=branch_word_used1+1;
    end
    final $display("BRANCH_WORD_COVER slot0=%0d slot1=%0d",branch_word_used0,branch_word_used1);
`endif
    wire [31:0] predict_pc,predicted_next,predicted_next1;
    wire predicted_sequential;
    wire [31:0] response_predict_pc,response_predicted_next,response_predicted_next1;
    wire response_predicted_seq,response_predicted_seq1;
    wire predict_accept,predict_accept_second;
    wire response_sample_fast_select;
    p2_predictor #(.ENABLED(BP_ENABLED),.BTB_ENTRIES(BTB_ENTRIES),.BHT_ENTRIES(BHT_ENTRIES),.RAS_DEPTH(RAS_DEPTH)) predictor(
        .clk(clk),.rst(rst),.lookup_pc(predict_pc),.prediction(predicted_next),
        .prediction_is_sequential(predicted_sequential),
        .response_sample_pc(i_req_addr),.response_sample_accept(i_req_valid&&i_req_ready),
        .response_sample_fast_pc(fast_pc),.response_sample_fast_select(response_sample_fast_select),
        .response_lookup_pc(response_predict_pc),.response_prediction(response_predicted_next),
        .response_prediction1(response_predicted_next1),.response_sequential(response_predicted_seq),
        .response_sequential1(response_predicted_seq1),
        .lookup_pc1(predict_pc+32'd4),.prediction1(predicted_next1),
        .lookup_accept(predict_accept),.lookup_second_valid(predict_accept_second),
        .fetch_flush(kill),
        .train_valid(control_commit||slot1_branch_commit),
        .train_pc(slot1_branch_sel?mp1:mp),.train_target(slot1_branch_sel?mtarget1:mtarget),
        .train_conditional(slot1_branch_sel||mconditional),.train_taken(slot1_branch_sel?m1_taken:mtaken),
        .train_insn(slot1_branch_sel?mi1:mi),.ras_flush(m_kill||irq_take||mret_commit||maintenance_commit||terminal_commit),
        .ras_call_valid(control_commit&&((mi[6:0]==7'h6f)||(mi[6:0]==7'h67))&&
            ((mi[11:7]==5'd1)||(mi[11:7]==5'd5))),.ras_call_return(mp+32'd4));
    p2_frontend_dual #(.RESET_PC(RESET_PC),.FIFO_DEPTH(FIFO_DEPTH),.RESPONSE_BYPASS(RESPONSE_BYPASS),.DUAL_WORDS(IFETCH_DUAL_WORDS),.LINE_BYTES(IFETCH_LINE_BYTES),.RESPONSE_PREDECODE(IFETCH_PREDECODE)) frontend(
        // A pending IRQ may disappear before entry. Preserve queued fetches
        // while E drains; only the actual irq_take redirects/discards them.
        .clk(clk),.rst(rst),.stop(halted||fetch_stop||(mv&&mfencei)||fatal_error||run_stop||terminal_stopped),
        .redirect_valid(kill),.redirect_pc(redirect_pc),
        .fast_redirect(fast_redirect),.fast_pc(fast_pc),.fast_pc4(fast_pc4),.fast_pc8(fast_pc8),
        .predict_pc(predict_pc),.predict_next(predicted_next),.predict_next1(predicted_next1),
        .predict_sequential(predicted_sequential),
        .response_predict_pc(response_predict_pc),.response_predict_next(response_predicted_next),
        .response_predict_next1(response_predicted_next1),.response_predict_sequential(response_predicted_seq),
        .response_predict_sequential1(response_predicted_seq1),
        .predict_accept(predict_accept),.predict_accept_second(predict_accept_second),
        .response_sample_fast_select(response_sample_fast_select),
        .req_valid(i_req_valid),.req_ready(i_req_ready),.req_addr(i_req_addr),
        .rsp_valid(i_rsp_valid),.rsp_ready(i_rsp_ready),.rsp_data(i_rsp_data),.rsp_error(i_rsp_error),
        .rsp_data_hi(i_rsp_data_hi),.rsp_hi_valid(i_rsp_hi_valid),
        .rsp_predecode(i_rsp_predecode),.rsp_predecode_hi(i_rsp_predecode_hi),
        .out_valid(dv),.out_ready(d_fire),.out_pc(dp),.out_insn(di),
        .out_prediction(front_prediction),.out_error(de),
        .out_sequential(front_sequential),.out1_sequential(front_sequential1),
        .out_pair_link(front_pair_link),.out_predecode(front_pre0),.out1_predecode(front_pre1),
        .out1_valid(dv1),.out1_ready(d_fire1),.out1_pc(dp1),.out1_insn(di1),
        .out1_prediction(front_prediction1),.out1_error(de1));
    wire [1:0] lsu_align_low=agu_a[1:0]+e_lsu_imm[1:0];
    wire lsu_align_bad=((f3==1||f3==5)&&lsu_align_low[0])||((f3==2)&&(|lsu_align_low));
    wire lsu_encoding_legal=(op==7'h03||op==7'h23)&&
        ((f3==0)||(f3==1)||(f3==2)||((op==7'h03)&&((f3==4)||(f3==5))));
    wire lsu_payload_legal=lsu_encoding_legal&&!lsu_align_bad&&!ee;
    wire late_data_request=mv && mmem && !mfault && !msent;
    // e_fire transfers this legal memory operation into M at the same edge.
    // If the offer stalls, M captures this exact payload and keeps offering it
    // through late_data_request. No ready-dependent withdrawal is permitted.
    // A completing older response may share the edge with this new request.
    wire address_base_forwarded=mv&&(m0_rs1||(mv1_exec&&m1_rs1));
    // The machine-mode early mux and its selects end at FFs. It never
    // consumes same-cycle load, late-ALU, CSR or live multiplier data.
    // Youngest-selected AGU hazards still block E-to-M ownership transfer.
    wire registered_base_ready=(MACHINE_MODE!=0)&&mv&&!ld_q[0]&&!late_q;
    wire [31:0] early_address_base=(MACHINE_MODE!=0)?early_a:rf_a_q;
    wire [31:0] early_address=agu_add_signed12(early_address_base,e_lsu_imm);
    wire [3:0] early_be=(f3[1:0]==0)?(4'b0001<<early_address[1:0]):
        (f3[1:0]==1)?(4'b0011<<early_address[1:0]):4'b1111;
    wire early_data_request=(EARLY_LSU!=0) && e_fire && lsu_payload_legal &&
        (!address_base_forwarded||registered_base_ready)&&(!e_store_q||!store_data_late);
    wire [31:0] early_write_data=e_store_q ? (early_store_b << {early_address[1:0],3'b000}) : 32'b0;
    assign d_req_valid=late_data_request || early_data_request;
    // Late request qualification uses only registered M packet state.
    // With valid high, late and early requests are mutually exclusive; selecting
    // by late removes e_fire/terminal response from the wide payload mux control.
    assign d_req_addr=late_data_request ? {maddr[31:2],2'b0} : {early_address[31:2],2'b0};
    assign d_req_write=late_data_request ? mwrite : e_store_q;
    assign d_req_be=late_data_request ? mbe : early_be;
    assign d_req_wdata=late_data_request ? mwdata : early_write_data;
    assign d_rsp_ready=mv && mmem && !mfault && msent;
    assign fence_i_valid=mv&&mfencei&&!mfence_sent&&!halted;
    assign data_idle=!mv;

`ifndef SYNTHESIS
    integer lsu_predecode_inactive=0,lsu_predecode_checked=0;
    always @(posedge clk) if(!rst) begin
        assert(e_store_q===(op==7'h23))
            else $fatal(1,"LSU_PREDECODE_INSTRUCTION_IDENTITY");
        if(!ev&&e_store_q!==wr) begin
            if(lsu_predecode_inactive==0)
                $display("LSU_PREDECODE_INACTIVE ei=%h ev=%b store=%b wr=%b",ei,ev,e_store_q,wr);
            lsu_predecode_inactive=lsu_predecode_inactive+1;
        end
        if(ev) begin
            lsu_predecode_checked=lsu_predecode_checked+1;
            assert(e_store_q===wr)
                else $fatal(1,"LSU_PREDECODE_STORE_IDENTITY ei=%h ev=%b store=%b wr=%b",ei,ev,e_store_q,wr);
        end
        if((op==7'h03)||(op==7'h23))
            assert(e_lsu_imm===(wr?imm_s:imm_i))
                else $fatal(1,"LSU_PREDECODE_IMMEDIATE_IDENTITY");
    end
    final $display("LSU_PREDECODE_COVER active=%0d inactive_x=%0d",lsu_predecode_checked,lsu_predecode_inactive);
    integer address_forward_seen=0,address_forward_early=0;
    integer address_forward_deferred=0,address_rf_early=0;
    reg address_capture_check=0,address_capture_sent=0;
    reg [31:0] address_capture_pc,address_capture_addr,address_capture_data;
    reg [3:0] address_capture_be;
    reg address_capture_write;
    always @(posedge clk) begin
        if(rst) address_capture_check<=0;
        else begin
            if(address_capture_check) begin
                assert(mv&&mmem&&!mfault&&mp===address_capture_pc&&
                    maddr===address_capture_addr&&mbe===address_capture_be&&
                    mwrite===address_capture_write&&mwdata===address_capture_data&&
                    msent===address_capture_sent)
                    else $fatal(1,"ADDR_EARLY_CAPTURE_CONTINUITY");
            end
            address_capture_check<=early_data_request;
            if(early_data_request) begin
                address_capture_pc<=ep;address_capture_addr<=ea;
                address_capture_be<=be;address_capture_write<=wr;
                address_capture_data<=wr?ew:32'b0;
                address_capture_sent<=d_req_ready;
            end
            if((MACHINE_MODE!=0)&&e_fire&&e_lsu_encoding&&!ee) begin
                assert(early_a===agu_a&&agu_a===a&&early_address===ea)
                    else $fatal(1,"ADDR_REGISTERED_EARLY_BASE_IDENTITY");
            end
            if(e_fire&&mem&&!fault&&address_base_forwarded) begin
                address_forward_seen=address_forward_seen+1;
                if(early_data_request) address_forward_early=address_forward_early+1;
                else address_forward_deferred=address_forward_deferred+1;
                if(!registered_base_ready)
                    assert(!early_data_request) else $fatal(1,"ADDR_UNREADY_FORWARD_OFFER");
            end
            if(early_data_request) begin
                assert(e_fire&&lsu_payload_legal&&early_address===ea&&early_be===be)
                    else $fatal(1,"ADDR_EARLY_PAYLOAD_IDENTITY");
                if(address_base_forwarded)
                    assert(registered_base_ready&&!agu_base_load_dependency&&!agu_late_dependency&&
                           early_a===a) else $fatal(1,"ADDR_FORWARDED_SOURCE_NOT_READY");
                else begin
                    address_rf_early=address_rf_early+1;
                    assert(early_address_base===rf_a_q) else $fatal(1,"ADDR_RF_EARLY_BASE_IDENTITY");
                end
                if(MACHINE_MODE==0)
                    assert(!address_base_forwarded&&early_address_base===rf_a_q)
                        else $fatal(1,"ADDR_LEGACY_EARLY_IDENTITY");
            end
        end
    end
    final $display("ADDR_REGISTERED_BASE_COVER forwarded=%0d forwarded_early=%0d deferred=%0d rf_early=%0d",
        address_forward_seen,address_forward_early,address_forward_deferred,address_rf_early);
    integer store_late_defers=0,store_early_offers=0;
    always @(posedge clk) if(!rst) begin
        if(e_fire&&mem&&wr&&!fault&&store_data_late) begin
            store_late_defers=store_late_defers+1;
            assert(!early_data_request) else $fatal(1,"STORE_LATE_EARLY_OFFER");
        end
        if(early_data_request&&wr) begin
            store_early_offers=store_early_offers+1;
            assert(!store_data_late&&early_store_b===agu_b&&early_write_data===ew)
                else $fatal(1,"STORE_EARLY_DATA_IDENTITY");
        end
        if(d_req_valid&&!d_req_write)
            assert(d_req_wdata===32'b0) else $fatal(1,"LOAD_WRITE_DATA_ZERO");
    end
    final $display("STORE_BOUNDARY_COVER deferred=%0d early=%0d",store_late_defers,store_early_offers);
`endif

    wire perf_active=!halted&&!terminal_stopped&&!run_stop;
    wire retired_control=control_commit||slot1_branch_commit;
    wire retired_taken=slot1_branch_sel?m1_taken:mtaken;
    wire retired_wrong=slot1_branch_sel?m1_mispredict:mpred_wrong;
    // Observation only (benchmark B-record probe); unused by synthesis.
    wire [31:0] retired_pc=slot1_branch_sel?mp1:mp;
    wire [31:0] retired_insn=slot1_branch_sel?mi1:mi;
    wire load_use_event=ev&&mv&&mmem&&!mwrite&&!m_done&&
        ((use1&&m0_rs1)||(use2&&m0_rs2));
    wire [23:0] perf_events;
    assign perf_events[0]=(!ev||e_fire)&&!dv&&!kill;
    assign perf_events[1]=!dv;
    assign perf_events[2]=kill;
    assign perf_events[3]=dv&&!d_fire&&!kill;
    assign perf_events[4]=load_use_event;
    assign perf_events[5]=mv&&mmem&&!m_done;
    assign perf_events[6]=retired_control;
    assign perf_events[7]=retired_control&&retired_taken;
    assign perf_events[8]=retired_control&&retired_wrong;
    assign perf_events[9]=m_redirect;
    assign perf_events[10]=retired_control;
    assign perf_events[11]=retired_control&&!retired_wrong;
    assign perf_events[12]=i_req_valid&&!i_req_ready;
    assign perf_events[13]=i_req_valid&&i_req_ready;
    assign perf_events[14]=i_rsp_valid&&i_rsp_ready;
    assign perf_events[15]=d_req_valid&&d_req_ready;
    assign perf_events[16]=d_req_valid&&!d_req_ready;
    assign perf_events[17]=m_done&&!m_bad&&!mcontrol&&mpred_wrong;
    assign perf_events[18]=d_fire;
    assign perf_events[23:19]=0;
    wire [1535:0] unused_perf_values;
    p3_perf_counters #(.DUAL_ISSUE(1)) perf(
        .clk(clk),.rst(rst),.enable(perf_active),.event_pulses(perf_events),
        .issue_second(d_fire1),
        .csr_addr(mi[31:20]),.csr_rdata(perf_rdata),.csr_known(perf_known),
        .i_hit(perf_cache_flat[0+:64]),.i_miss(perf_cache_flat[64+:64]),
        .d_hit(perf_cache_flat[128+:64]),.d_miss(perf_cache_flat[192+:64]),
        .d_writeback(perf_cache_flat[256+:64]),.values_flat(unused_perf_values));

    // Next M packet attributes: from E on e_fire, else the resident packet.
    wire fl_v1n=e_fire?(ev1&&!fault):mv1_raw_q;
    wire fl_nz1n=e_fire?((op1!=7'h63)&&(ei1[11:7]!=0)):mr1_nonzero_q;
    wire fl_nz0n=e_fire?(rd!=0):mr_nonzero_q;
    wire fl_ld0n=e_fire?((mem&&!wr)||e_mul_pipe):((mmem&&!mwrite)||mmul_pipe_q);
    wire fl_late0n=e_fire?((e_late0||e_mul_pipe)&&!fault):mlate0;
    wire fl_late1n=e_fire?((e_late1||e_mul1_pipe)&&!fault):(mlate1&&!mmul1_live_q);
    wire fl_mul1n=e_fire&&e_mul1_pipe&&!fault;
    wire fl_h0n_0=hit_next(e_fire,rf_payload_capture,ei[11:7],mr,di[19:15],rs1);
    wire fl_h1n_0=hit_next(e_fire,rf_payload_capture,ei1[11:7],mr1,di[19:15],rs1);
    wire fl_sel1_0=fl_v1n&&fl_nz1n&&fl_h1n_0;
    wire fl_sel0_0=fl_nz0n&&fl_h0n_0;
    wire fl_h0n_1=hit_next(e_fire,rf_payload_capture,ei[11:7],mr,di[24:20],rs2);
    wire fl_h1n_1=hit_next(e_fire,rf_payload_capture,ei1[11:7],mr1,di[24:20],rs2);
    wire fl_sel1_1=fl_v1n&&fl_nz1n&&fl_h1n_1;
    wire fl_sel0_1=fl_nz0n&&fl_h0n_1;
    wire fl_h0n_2=literal_hit_next(e_fire,rf_payload_capture,ei[11:7],mr,di1[19:15],ei1[19:15],d_const_a1,e_const_a1_q);
    wire fl_h1n_2=literal_hit_next(e_fire,rf_payload_capture,ei1[11:7],mr1,di1[19:15],ei1[19:15],d_const_a1,e_const_a1_q);
    wire fl_sel1_2=fl_v1n&&fl_nz1n&&fl_h1n_2;
    wire fl_sel0_2=fl_nz0n&&fl_h0n_2;
    wire fl_h0n_3=literal_hit_next(e_fire,rf_payload_capture,ei[11:7],mr,di1[24:20],ei1[24:20],d_const_b1,e_const_b1_q);
    wire fl_h1n_3=literal_hit_next(e_fire,rf_payload_capture,ei1[11:7],mr1,di1[24:20],ei1[24:20],d_const_b1,e_const_b1_q);
    wire fl_sel1_3=fl_v1n&&fl_nz1n&&fl_h1n_3;
    wire fl_sel0_3=fl_nz0n&&fl_h0n_3;
    // Matches ev1 capture/consume/kill priorities in the original packet FF.
    always @(posedge clk) begin
        if(rst||kill) begin e_fusion_sel_q<=0;e_late1_enable_q<=0;end
        else if(rf_payload_capture) begin
            e_fusion_sel_q<={d_fire1&&(d_bitfusion==4),d_fire1&&(d_bitfusion==3),
                d_fire1&&(d_bitfusion==2),d_fire1&&(d_bitfusion==1)};
            e_late1_enable_q<=d_fire1&&!de1&&!d_lui_pair&&(d_bitfusion==0)&&integer_alu_encoding(di1);
        end else if(e_fire) begin e_fusion_sel_q<=0;e_late1_enable_q<=0;end
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst) begin
        assert(e_fusion_sel_q==={ev1&&(e_bitfusion_q==4),ev1&&(e_bitfusion_q==3),
            ev1&&(e_bitfusion_q==2),ev1&&(e_bitfusion_q==1)}) else $fatal(1,"SLOT1_FUSION_CONTROL_IDENTITY");
        assert(e_late1_enable_q===(ev1&&!ee1&&!e_lui_pair_q&&!e_bitfusion&&e_integer1))
            else $fatal(1,"SLOT1_LATE_CONTROL_IDENTITY");
    end
`endif
    // Only branch payloads speculate. Valid, MMIO, exceptions and
    // instruction metadata retain their original e_fire enables. A resident
    // M packet holds its payload until retirement; invalid payloads are free.
    wire branch_payload_capture=!mv||m_done;
    always @(posedge clk) begin
        if(rst) begin
            mtarget_base<=0;
            mtarget1<=0;
            mpred<=0;
            mbranch_a<=0;
            mbranch_b<=0;
            mbranch_eq8<=4'b1111;
            mbranch_lt8<=0;
            mbranch_signed_top_lt<=0;
            mbranch_eq_taken_q<=1;
            mbranch_low_lt_direction_q<=1;
            mbranch_low_ge_direction_q<=1;
            mbranch_order_hi_lt_q<=0;
            mbranch_order_hi_eq_q<=1;
            mbranch_order_lo_lt_q<=0;
            m1_decision_q<=1;
            m1_order_low_lt_q<=0;
            m1_order_low_ge_q<=0;
            m1_order_lower_lt_q<=0;
            m_tgt_eq1_q<=0;
            m_ft_eq1_q<=1;
            mbranch1_eq8<=4'b1111;
            m_wrong_taken_q<=0;
            m_wrong_nt_q<=1;
            m_fall_q<=4;
            m_fall4_q<=8;
            m_fall8_q<=12;
            m_tgt4_q<=4;
            m_tgt8_q<=8;
            m1_tgt4_q<=4;
            m1_tgt8_q<=8;
            m1_fall4_q<=8;
            m1_fall8_q<=12;
            m1_wrong_taken_q<=0;
            m1_wrong_nt_q<=0;
            m1_fall_q<=4;
        end else if(branch_payload_capture) begin
            mtarget_base<=target;
            mtarget1<=ep1+{{19{ei1[31]}},ei1[31],ei1[7],ei1[30:25],ei1[11:8],1'b0};
            mpred<=epred;
            mbranch_a<=a;
            mbranch_b<=(e_late0&&(op==7'h13))?imm_i:b;
            mbranch_eq8<={a[31:24]==b[31:24],a[23:16]==b[23:16],a[15:8]==b[15:8],a[7:0]==b[7:0]};
            mbranch_lt8<={branch0_a[31:24]<branch0_b[31:24],branch0_a[23:16]<branch0_b[23:16],branch0_a[15:8]<branch0_b[15:8],branch0_a[7:0]<branch0_b[7:0]};
            mbranch_signed_top_lt<=($signed(branch0_a[31:24])<$signed(branch0_b[31:24]));
            mbranch_eq_taken_q<=f3[0]?!branch0_equal:branch0_equal;
            mbranch_low_lt_direction_q<=(f3[2]?word_dir_lt0:(f3[0]?!branch0_equal:branch0_equal));
            mbranch_low_ge_direction_q<=(f3[2]?word_dir_ge0:(f3[0]?!branch0_equal:branch0_equal));
            mbranch_order_hi_lt_q<=word_high_lt0;
            mbranch_order_hi_eq_q<=word_high_eq0;
            mbranch_order_lo_lt_q<=word_lower_lt0;
            m1_decision_q<=ei1[12]?!branch1_equal:branch1_equal;
            m1_order_low_lt_q<=word_dir_lt1;
            m1_order_low_ge_q<=word_dir_ge1;
            m1_order_lower_lt_q<=word_lower_lt1;
            m_tgt_eq1_q<=(target==ep1);
            m_ft_eq1_q<=((ep+32'd4)==ep1);
            mbranch1_eq8<={a1[31:24]==b1[31:24],a1[23:16]==b1[23:16],a1[15:8]==b1[15:8],a1[7:0]==b1[7:0]};
            m_wrong_taken_q<=(target!=epred);
            m_wrong_nt_q<=((ep+32'd4)!=epred);
            m_fall_q<=ep+32'd4;
            m_fall4_q<=ep+32'd8;
            m_fall8_q<=ep+32'd12;
            m_tgt4_q<=target_plus4;
            m_tgt8_q<=target_plus8;
            m1_tgt4_q<=ep1+{{19{ei1[31]}},ei1[31],ei1[7],ei1[30:25],ei1[11:8],1'b0}+32'd4;
            m1_tgt8_q<=ep1+{{19{ei1[31]}},ei1[31],ei1[7],ei1[30:25],ei1[11:8],1'b0}+32'd8;
            m1_fall4_q<=ep1+32'd8;
            m1_fall8_q<=ep1+32'd12;
            m1_wrong_taken_q<=((ep1+{{19{ei1[31]}},ei1[31],ei1[7],ei1[30:25],ei1[11:8],1'b0})!=epred1);
            m1_wrong_nt_q<=((ep1+32'd4)!=epred1);
            m1_fall_q<=ep1+32'd4;
        end
    end
`ifndef SYNTHESIS
    reg [31:0] branch_old_mtarget_base;
    reg [31:0] branch_old_mtarget1;
    reg [31:0] branch_old_mpred;
    reg [31:0] branch_old_mbranch_a;
    reg [31:0] branch_old_mbranch_b;
    reg [3:0] branch_old_mbranch_eq8;
    reg [3:0] branch_old_mbranch_lt8;
    reg  branch_old_mbranch_signed_top_lt;
    reg  branch_old_mbranch_eq_taken_q;
    reg  branch_old_mbranch_low_lt_direction_q;
    reg  branch_old_mbranch_low_ge_direction_q;
    reg  branch_old_mbranch_order_hi_lt_q;
    reg  branch_old_mbranch_order_hi_eq_q;
    reg  branch_old_mbranch_order_lo_lt_q;
    reg  branch_old_m1_decision_q;
    reg  branch_old_m1_order_low_lt_q;
    reg  branch_old_m1_order_low_ge_q;
    reg  branch_old_m1_order_lower_lt_q;
    reg  branch_old_m_tgt_eq1_q;
    reg  branch_old_m_ft_eq1_q;
    reg [3:0] branch_old_mbranch1_eq8;
    reg  branch_old_m_wrong_taken_q;
    reg  branch_old_m_wrong_nt_q;
    reg [31:0] branch_old_m_fall_q;
    reg [31:0] branch_old_m_fall4_q;
    reg [31:0] branch_old_m_fall8_q;
    reg [31:0] branch_old_m_tgt4_q;
    reg [31:0] branch_old_m_tgt8_q;
    reg [31:0] branch_old_m1_tgt4_q;
    reg [31:0] branch_old_m1_tgt8_q;
    reg [31:0] branch_old_m1_fall4_q;
    reg [31:0] branch_old_m1_fall8_q;
    reg  branch_old_m1_wrong_taken_q;
    reg  branch_old_m1_wrong_nt_q;
    reg [31:0] branch_old_m1_fall_q;
    always @(posedge clk) begin
        if(rst) begin
            branch_old_mtarget_base<=0;
            branch_old_mtarget1<=0;
            branch_old_mpred<=0;
            branch_old_mbranch_a<=0;
            branch_old_mbranch_b<=0;
            branch_old_mbranch_eq8<=4'b1111;
            branch_old_mbranch_lt8<=0;
            branch_old_mbranch_signed_top_lt<=0;
            branch_old_mbranch_eq_taken_q<=1;
            branch_old_mbranch_low_lt_direction_q<=1;
            branch_old_mbranch_low_ge_direction_q<=1;
            branch_old_mbranch_order_hi_lt_q<=0;
            branch_old_mbranch_order_hi_eq_q<=1;
            branch_old_mbranch_order_lo_lt_q<=0;
            branch_old_m1_decision_q<=1;
            branch_old_m1_order_low_lt_q<=0;
            branch_old_m1_order_low_ge_q<=0;
            branch_old_m1_order_lower_lt_q<=0;
            branch_old_m_tgt_eq1_q<=0;
            branch_old_m_ft_eq1_q<=1;
            branch_old_mbranch1_eq8<=4'b1111;
            branch_old_m_wrong_taken_q<=0;
            branch_old_m_wrong_nt_q<=1;
            branch_old_m_fall_q<=4;
            branch_old_m_fall4_q<=8;
            branch_old_m_fall8_q<=12;
            branch_old_m_tgt4_q<=4;
            branch_old_m_tgt8_q<=8;
            branch_old_m1_tgt4_q<=4;
            branch_old_m1_tgt8_q<=8;
            branch_old_m1_fall4_q<=8;
            branch_old_m1_fall8_q<=12;
            branch_old_m1_wrong_taken_q<=0;
            branch_old_m1_wrong_nt_q<=0;
            branch_old_m1_fall_q<=4;
        end else if(e_fire) begin
            branch_old_mtarget_base<=target;
            branch_old_mtarget1<=ep1+{{19{ei1[31]}},ei1[31],ei1[7],ei1[30:25],ei1[11:8],1'b0};
            branch_old_mpred<=epred;
            branch_old_mbranch_a<=a;
            branch_old_mbranch_b<=(e_late0&&(op==7'h13))?imm_i:b;
            branch_old_mbranch_eq8<={a[31:24]==b[31:24],a[23:16]==b[23:16],a[15:8]==b[15:8],a[7:0]==b[7:0]};
            branch_old_mbranch_lt8<={branch0_a[31:24]<branch0_b[31:24],branch0_a[23:16]<branch0_b[23:16],branch0_a[15:8]<branch0_b[15:8],branch0_a[7:0]<branch0_b[7:0]};
            branch_old_mbranch_signed_top_lt<=($signed(branch0_a[31:24])<$signed(branch0_b[31:24]));
            branch_old_mbranch_eq_taken_q<=f3[0]?!branch0_equal:branch0_equal;
            branch_old_mbranch_low_lt_direction_q<=(f3[2]?word_dir_lt0:(f3[0]?!branch0_equal:branch0_equal));
            branch_old_mbranch_low_ge_direction_q<=(f3[2]?word_dir_ge0:(f3[0]?!branch0_equal:branch0_equal));
            branch_old_mbranch_order_hi_lt_q<=word_high_lt0;
            branch_old_mbranch_order_hi_eq_q<=word_high_eq0;
            branch_old_mbranch_order_lo_lt_q<=word_lower_lt0;
            branch_old_m1_decision_q<=ei1[12]?!branch1_equal:branch1_equal;
            branch_old_m1_order_low_lt_q<=word_dir_lt1;
            branch_old_m1_order_low_ge_q<=word_dir_ge1;
            branch_old_m1_order_lower_lt_q<=word_lower_lt1;
            branch_old_m_tgt_eq1_q<=(target==ep1);
            branch_old_m_ft_eq1_q<=((ep+32'd4)==ep1);
            branch_old_mbranch1_eq8<={a1[31:24]==b1[31:24],a1[23:16]==b1[23:16],a1[15:8]==b1[15:8],a1[7:0]==b1[7:0]};
            branch_old_m_wrong_taken_q<=(target!=epred);
            branch_old_m_wrong_nt_q<=((ep+32'd4)!=epred);
            branch_old_m_fall_q<=ep+32'd4;
            branch_old_m_fall4_q<=ep+32'd8;
            branch_old_m_fall8_q<=ep+32'd12;
            branch_old_m_tgt4_q<=target_plus4;
            branch_old_m_tgt8_q<=target_plus8;
            branch_old_m1_tgt4_q<=ep1+{{19{ei1[31]}},ei1[31],ei1[7],ei1[30:25],ei1[11:8],1'b0}+32'd4;
            branch_old_m1_tgt8_q<=ep1+{{19{ei1[31]}},ei1[31],ei1[7],ei1[30:25],ei1[11:8],1'b0}+32'd8;
            branch_old_m1_fall4_q<=ep1+32'd8;
            branch_old_m1_fall8_q<=ep1+32'd12;
            branch_old_m1_wrong_taken_q<=((ep1+{{19{ei1[31]}},ei1[31],ei1[7],ei1[30:25],ei1[11:8],1'b0})!=epred1);
            branch_old_m1_wrong_nt_q<=((ep1+32'd4)!=epred1);
            branch_old_m1_fall_q<=ep1+32'd4;
        end
    end
    integer branch_payload_live_checks=0,branch_payload_spec_checks=0;
    always @(posedge clk) if(!rst) begin
        assert(!e_fire||branch_payload_capture) else $fatal(1,"BRANCH_PAYLOAD_CAPTURE_GATE");
        if(mv) begin
            assert({mtarget_base,mtarget1,mpred,mbranch_a,mbranch_b,mbranch_eq8,mbranch_lt8,mbranch_signed_top_lt,mbranch_eq_taken_q,mbranch_low_lt_direction_q,mbranch_low_ge_direction_q,mbranch_order_hi_lt_q,mbranch_order_hi_eq_q,mbranch_order_lo_lt_q,m1_decision_q,m1_order_low_lt_q,m1_order_low_ge_q,m1_order_lower_lt_q,m_tgt_eq1_q,m_ft_eq1_q,mbranch1_eq8,m_wrong_taken_q,m_wrong_nt_q,m_fall_q,m_fall4_q,m_fall8_q,m_tgt4_q,m_tgt8_q,m1_tgt4_q,m1_tgt8_q,m1_fall4_q,m1_fall8_q,m1_wrong_taken_q,m1_wrong_nt_q,m1_fall_q}==={branch_old_mtarget_base,branch_old_mtarget1,branch_old_mpred,branch_old_mbranch_a,branch_old_mbranch_b,branch_old_mbranch_eq8,branch_old_mbranch_lt8,branch_old_mbranch_signed_top_lt,branch_old_mbranch_eq_taken_q,branch_old_mbranch_low_lt_direction_q,branch_old_mbranch_low_ge_direction_q,branch_old_mbranch_order_hi_lt_q,branch_old_mbranch_order_hi_eq_q,branch_old_mbranch_order_lo_lt_q,branch_old_m1_decision_q,branch_old_m1_order_low_lt_q,branch_old_m1_order_low_ge_q,branch_old_m1_order_lower_lt_q,branch_old_m_tgt_eq1_q,branch_old_m_ft_eq1_q,branch_old_mbranch1_eq8,branch_old_m_wrong_taken_q,branch_old_m_wrong_nt_q,branch_old_m_fall_q,branch_old_m_fall4_q,branch_old_m_fall8_q,branch_old_m_tgt4_q,branch_old_m_tgt8_q,branch_old_m1_tgt4_q,branch_old_m1_tgt8_q,branch_old_m1_fall4_q,branch_old_m1_fall8_q,branch_old_m1_wrong_taken_q,branch_old_m1_wrong_nt_q,branch_old_m1_fall_q}) else $fatal(1,"BRANCH_PAYLOAD_LIVE_IDENTITY");
            branch_payload_live_checks<=branch_payload_live_checks+1;
        end
        if(branch_payload_capture&&!e_fire) branch_payload_spec_checks<=branch_payload_spec_checks+1;
    end
    final $display("BRANCH_PAYLOAD_COVER live=%0d speculative=%0d",branch_payload_live_checks,branch_payload_spec_checks);
`endif
    always @(posedge clk) begin
        if(rst) begin
            fetch_stop<=0;
            terminal_stopped<=0;
            ev<=0;mv<=0;ep<=0;ei<=0;mp<=0;mi<=0;ee<=0;
            e_target_kind_q<=0;e_pc_target_imm_q<=0; // TARGET_RESET
            e_lsu_imm12_q<=0;e_store_q<=0;
            e_alu_imm0_q<=0;e_alu_sub0_q<=0;e_alu_left0_q<=0;e_alu_arith0_q<=0;
            e_alu_imm1_q<=0;e_alu_sub1_q<=0;e_alu_left1_q<=0;e_alu_arith1_q<=0;
            ev1<=0;mv1_raw_q<=0;ep1<=0;ei1<=0;mp1<=0;mi1<=0;ee1<=0;e_lui_pair_q<=0;e_bitfusion_q<=0;e_const_a1_q<=0;e_const_b1_q<=0;
            mresult1_payload<=0;mlate_b1<=0;mlate0<=0;mmul_pipe_q<=0;mlate1<=0;mmul1_live_q<=0;mr1<=0;
            mlate_sub0<=0;mlate_left0<=0;mlate_arith0<=0;
            mlate_sub1<=0;mlate_left1<=0;mlate_arith1<=0;
            hit0_rs1_q<=1;hit0_rs2_q<=1;hit0_rs1_1_q<=1;hit0_rs2_1_q<=1;
            hit1_rs1_q<=1;hit1_rs2_q<=1;hit1_rs1_1_q<=1;hit1_rs2_1_q<=1;mr1_nonzero_q<=0;
            slowL_q<=0;ld_q<=0;late_q<=0;any_q<=0;early_fwd0_q<=0;early_fwd1_q<=0;
            mr<=0; mr_nonzero_q<=0; mresult<=0; maddr<=0; mload_format_q<=load_format_decode(2'b00,3'b000); mwdata<=0; mcause<=0; mtval<=0; mbe<=0; mfunct3<=0;
            mmem<=0; mwrite<=0; mfault<=0; msent<=0; halted<=0;
            mcsr<=0;mmret<=0;mfencei<=0;mfence_sent<=0;mcontrol<=0;mconditional<=0;
            epred<=0;commit_next_pc<=RESET_PC;
            
            
            
            
            m1_branch_q<=0;m_fast_s1_nonmem_q<=0;m1_bne_q<=0;
            epred1<=4;
            trace_irq_valid<=0;trace_irq_pc<=0;trace_irq_cause<=0;
            trace_csr_valid<=0;trace_csr_read<=0;trace_csr_write<=0;
            trace_csr_addr<=0;trace_csr_rdata<=0;trace_csr_wdata<=0;
            trace_valid<=0; trace_trap<=0; trace_pc<=0; trace_insn<=0; trace_rd<=0; trace_wdata<=0;
            trace_valid1<=0;trace_pc1<=0;trace_insn1<=0;trace_rd1<=0;trace_wdata1<=0;
            trace_cause<=0; trace_tval<=0; trace_mem_valid<=0; trace_mem_write<=0;
            trace_mem_addr<=0; trace_mem_wdata<=0; trace_mem_rdata<=0; trace_mem_be<=0;
            count_cycle<=0; count_retired<=0; count_if_wait<=0; count_data_wait<=0;
            count_load_use<=0; count_redirect<=0; count_reads<=0; count_writes<=0;
        end else begin
            trace_valid<=0;trace_valid1<=0;
            trace_irq_valid<=0;trace_csr_valid<=0;
            early_fwd0_q[0]<=fl_sel0_0&&!fl_ld0n&&!fl_late0n;
            early_fwd0_q[1]<=fl_sel0_1&&!fl_ld0n&&!fl_late0n;
            early_fwd1_q[0]<=fl_sel1_0&&!fl_late1n;
            early_fwd1_q[1]<=fl_sel1_1&&!fl_late1n;
            slowL_q[0]<=fl_sel1_0?fl_late1n:fl_sel0_0?(fl_ld0n||fl_late0n):1'b0;
            ld_q[0]<=fl_sel1_0?fl_mul1n:fl_sel0_0&&fl_ld0n;
            slowL_q[1]<=fl_sel1_1?fl_late1n:fl_sel0_1?(fl_ld0n||fl_late0n):1'b0;
            ld_q[1]<=fl_sel1_1?fl_mul1n:fl_sel0_1&&fl_ld0n;
            late_q<=fl_sel1_0?fl_late1n:fl_sel0_0&&fl_late0n;
            any_q[0]<=fl_sel1_0||fl_sel0_0;
            any_q[1]<=fl_sel1_1||fl_sel0_1;
            any_q[2]<=fl_sel1_2||fl_sel0_2;
            any_q[3]<=fl_sel1_3||fl_sel0_3;
            hit0_rs1_q<=hit_next(e_fire,rf_payload_capture,ei[11:7],mr,di[19:15],rs1);
            hit0_rs2_q<=hit_next(e_fire,rf_payload_capture,ei[11:7],mr,di[24:20],rs2);
            hit0_rs1_1_q<=literal_hit_next(e_fire,rf_payload_capture,ei[11:7],mr,di1[19:15],ei1[19:15],d_const_a1,e_const_a1_q);
            hit0_rs2_1_q<=literal_hit_next(e_fire,rf_payload_capture,ei[11:7],mr,di1[24:20],ei1[24:20],d_const_b1,e_const_b1_q);
            hit1_rs1_q<=hit_next(e_fire,rf_payload_capture,ei1[11:7],mr1,di[19:15],rs1);
            hit1_rs2_q<=hit_next(e_fire,rf_payload_capture,ei1[11:7],mr1,di[24:20],rs2);
            hit1_rs1_1_q<=literal_hit_next(e_fire,rf_payload_capture,ei1[11:7],mr1,di1[19:15],ei1[19:15],d_const_a1,e_const_a1_q);
            hit1_rs2_1_q<=literal_hit_next(e_fire,rf_payload_capture,ei1[11:7],mr1,di1[24:20],ei1[24:20],d_const_b1,e_const_b1_q);
            if(e_fire) mr1_nonzero_q<=(op1!=7'h63)&&(ei1[11:7]!=0);
            if(terminal_commit) terminal_stopped<=1;
            if(terminal_stopped) assert(!mv&&!e_fire&&!d_req_valid&&!irq_take);
            if(fatal_error||(mfence_sent&&fence_i_done&&fence_i_error)) halted<=1;
            if(fence_i_valid&&fence_i_ready) mfence_sent<=1;
            if(!halted) begin
                count_cycle<=count_cycle+1;
                if(!dv) count_if_wait<=count_if_wait+1;
                if(mv && mmem && !m_done) count_data_wait<=count_data_wait+1;
                if(load_use_event) count_load_use<=count_load_use+1;
            end
            if(d_req_valid && d_req_ready) begin
                msent<=1;
                if(d_req_write) count_writes<=count_writes+1; else count_reads<=count_reads+1;
            end
            // W: architectural state and trace are committed together.
            if(m_done) begin
                mv<=0; trace_valid<=1; trace_trap<=m_bad;
                mv1_raw_q<=0;
                if(mv1&&!m_bad&&!terminal_commit) begin
                    trace_valid1<=1;trace_pc1<=mp1;trace_insn1<=mi1;
                    trace_rd1<=mr1;trace_wdata1<=mr1==0?32'b0:mresult1;
                end
                trace_pc<=mp; trace_insn<=mi;
                trace_rd<=m_bad ? 5'b0 : mr;
                trace_wdata<=(m_bad || mr==0) ? 32'b0 : m_value;
                trace_cause<=m_bad ? m_final_cause : 32'b0;
                trace_tval<=m_bad ? m_final_tval : 32'b0;
                trace_mem_valid<=mmem; trace_mem_write<=mmem && mwrite;
                trace_mem_addr<=mmem ? {maddr[31:2],2'b0} : 32'b0;
                trace_mem_be<=mmem ? mbe : 4'b0;
                trace_mem_wdata<=(mmem && mwrite) ? mwdata : 32'b0;
                trace_mem_rdata<=(mmem && !mwrite && !m_bad) ? d_rsp_data : 32'b0;
                trace_csr_valid<=mcsr&&!m_bad;
                trace_csr_addr<=mi[31:20];trace_csr_read<=csr_read;trace_csr_write<=csr_write;
                trace_csr_rdata<=csr_read?csr_rdata:32'b0;
                trace_csr_wdata<=csr_write?csr_wdata:32'b0;
                if(m_bad) begin
                    if(MACHINE_MODE==0) halted<=1;
                    else commit_next_pc<=handler_pc;
                end
                else begin
                    count_retired<=count_retired+(mv1&&!terminal_commit?64'd2:64'd1);
                    commit_next_pc<=mmret?return_pc:(mv1&&!terminal_commit?(m1_taken?mtarget1:mp1+32'd4):mnext);
                end
            end
            // DSP registers sample E operands every edge. A resident slot-1
            // product moves to its own payload now; e_fire below overrides.
            if(mmul1_live_q) begin
                mresult1_payload<=mul_result;mlate1<=0;mmul1_live_q<=0;
            end
            if(e_fire) begin
                ev<=0; mv<=1; mp<=ep; mi<=ei; mr<=rd; mr_nonzero_q<=(rd!=0); mresult<=er;
                ev1<=0;mv1_raw_q<=ev1&&!fault;
                mp1<=ep1;mi1<=ei1;mr1<=(op1==7'h63)?5'd0:ei1[11:7];
                m1_branch_q<=(op1==7'h63);
                m_fast_s1_nonmem_q<=(op1==7'h63)&&!mem;
                m1_bne_q<=f3_1[0];
                
                
                mresult1_payload<=e_late1?a1:er1;
                mlate_b1<=(ei1[6:0]==7'h13)?{{20{ei1[31]}},ei1[31:20]}:b1;
                mlate0<=(e_late0||e_mul_pipe)&&!fault;mmul_pipe_q<=e_mul_pipe&&!fault;mlate1<=(e_late1||e_mul1_pipe)&&!fault;mmul1_live_q<=e_mul1_pipe&&!fault;
                mlate_sub0<=(op==7'h33)&&ei[30];
                mlate_left0<=f3==3'd1;mlate_arith0<=(f3==3'd5)&&ei[30];
                mlate_sub1<=(ei1[6:0]==7'h33)&&ei1[30];
                mlate_left1<=ei1[14:12]==3'd1;mlate_arith1<=(ei1[14:12]==3'd5)&&ei1[30];
                maddr<=ea; mload_format_q<=load_format_decode(ea[1:0],f3); mwdata<=wr?ew:32'b0; mbe<=be; mfunct3<=f3;
                mmem<=mem; mwrite<=wr; mfault<=fault; mcause<=ecause; mtval<=etval;
                msent<=early_data_request&&d_req_ready;
                mcsr<=csr;mmret<=mret;mfencei<=fencei;mfence_sent<=0;
                mcontrol<=control;mconditional<=conditional;
                
                
                
                
                
                
                
                
                
                
                
                
                
                
                
                // Branch operands retain the original value; only a late
                // immediate ALU stores its effective RHS in this shared FF.
                
                
                
                
                
                
            end
            if(d_fire) begin
                ev<=1;
                ev1<=d_fire1;
            end
            // The payload is disposable whenever E is empty or its old
            // instruction advances/is killed. Keep the exact valid/kill
            // controls above; only payload FF enables use the earlier gate.
            // MACHINE_MODE=0 keeps d_fire through rf_payload_capture.
            if(rf_payload_capture) begin
                e_lui_pair_q<=d_lui_pair;e_bitfusion_q<=d_bitfusion;
                e_const_a1_q<=d_const_a1;e_const_b1_q<=d_const_b1;
                epred<=front_prediction;epred1<=front_prediction1;
                ep<=dp;ei<=di;ee<=de;
                e_target_kind_q<=d_target_kind;e_pc_target_imm_q<=d_pc_target_imm; // TARGET_CAPTURE
                e_store_q<=(di[6:0]==7'h23);
                e_alu_imm0_q<=di[6:0]==7'h13;
                e_alu_sub0_q<=(di[6:0]==7'h33)&&di[30];
                e_alu_left0_q<=di[14:12]==3'd1;
                e_alu_arith0_q<=(di[14:12]==3'd5)&&di[30];
                e_alu_imm1_q<=di1[6:0]==7'h13;
                e_alu_sub1_q<=(di1[6:0]==7'h33)&&di1[30];
                e_alu_left1_q<=di1[14:12]==3'd1;
                e_alu_arith1_q<=(di1[14:12]==3'd5)&&di1[30];
                e_lsu_imm12_q<=di[5]?{di[31:25],di[11:7]}:di[31:20];
                ep1<=dp1;ei1<=di1;ee1<=de1;
            end
            if(kill) begin
                ev<=0;ev1<=0;
                // An M redirect discards the younger E instruction. Its fault
                // must not stop mode0 fetch. Preserve the prior terminal-edge
                // fault observation while terminal_stopped drains held fetch.
                if(MACHINE_MODE==0&&(m_kill||(fault&&(!m_redirect||terminal_commit)))) fetch_stop<=1;
                else count_redirect<=count_redirect+1;
            end
            if(irq_take) begin
                trace_irq_valid<=1;trace_irq_pc<=commit_next_pc;trace_irq_cause<=irq_cause;
                commit_next_pc<=handler_pc;
            end
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst) begin
        assert({m0_rs1,m0_rs2,m0_rs1_1,m0_rs2_1}==={mr!=0&&mr==rs1,mr!=0&&mr==rs2,mr!=0&&mr==rs1_1,mr!=0&&mr==rs2_1})
            else $fatal(1,"BYPASSHIT_SLOT0");
        assert({m1_rs1,m1_rs2,m1_rs1_1,m1_rs2_1}==={mr1!=0&&mr1==rs1,mr1!=0&&mr1==rs2,mr1!=0&&mr1==rs1_1,mr1!=0&&mr1==rs2_1})
            else $fatal(1,"BYPASSHIT_SLOT1");
        assert(mr_nonzero_q===(mr!=0)&&mr1_nonzero_q===(mr1!=0)) else $fatal(1,"BYPASSHIT_NONZERO");
        if(mr1_nonzero_q) assert({hit1_rs1_q,hit1_rs2_q,hit1_rs1_1_q,hit1_rs2_1_q}==={mr1==rs1,mr1==rs2,mr1==rs1_1,mr1==rs2_1})
            else $fatal(1,"BYPASSHIT_SLOT1_RAW");
    end
`endif
`ifndef SYNTHESIS
    // Independent full-width ISA predicate; unlike the split implementation.
    function automatic slot1_condition_reference;
        input [2:0] kind;
        input [31:0] lhs,rhs;
        begin
            case(kind)
                0:slot1_condition_reference=lhs==rhs;
                1:slot1_condition_reference=lhs!=rhs;
                4:slot1_condition_reference=$signed(lhs)<$signed(rhs);
                5:slot1_condition_reference=$signed(lhs)>=$signed(rhs);
                6:slot1_condition_reference=lhs<rhs;
                7:slot1_condition_reference=lhs>=rhs;
                default:slot1_condition_reference=0;
            endcase
        end
    endfunction
    reg [7:0] slot1_order_taken=0,slot1_order_nt=0;
    integer slot1_order_retired=0,slot1_order_redirect=0;
    always @(posedge clk) if(!rst&&slot1_branch_commit) begin
        if(m1_taken) slot1_order_taken[mi1[14:12]]<=1'b1;
        else slot1_order_nt[mi1[14:12]]<=1'b1;
        if(mi1[14]) begin
            slot1_order_retired<=slot1_order_retired+1;
            if(m_redirect1) slot1_order_redirect<=slot1_order_redirect+1;
        end
    end
    final $display("SLOT1_ORDER_COVER taken=%0d nt=%0d retired=%0d redirect=%0d",
        slot1_order_taken,slot1_order_nt,slot1_order_retired,slot1_order_redirect);
    reg [31:0] slot1br_a_q,slot1br_b_q,slot1br_pred_q,front_prediction1_e;
    integer s1pt_taken_ok=0,s1pt_wrong_nt=0,s1pt_nt_wrong_taken=0,s1pt_wrong_target=0,s1pt_nt_ok=0;
    always @(posedge clk) if(d_fire1) front_prediction1_e<=front_prediction1;
    integer slot1br_retired=0,slot1br_taken=0,slot1br_redirect=0,slot1br_annul=0;
    always @(posedge clk) begin
        if(e_fire) begin slot1br_a_q<=a1;slot1br_b_q<=b1;slot1br_pred_q<=front_prediction1_e;end
        if(!rst) begin
            if(slot1_branch_sel) begin
                assert(mv&&!mcontrol&&mi1[6:0]==7'h63&&(mi1[14]||mi1[14:13]==2'b00)&&!mi1[8]&&mr1==0)
                    else $fatal(1,"SLOT1BR_SHAPE");
                assert(mtarget1===mp1+{{19{mi1[31]}},mi1[31],mi1[7],mi1[30:25],mi1[11:8],1'b0}&&mtarget1[1:0]==0)
                    else $fatal(1,"SLOT1BR_TARGET");
                assert(m1_taken===slot1_condition_reference(mi1[14:12],slot1br_a_q,slot1br_b_q))
                    else $fatal(1,"SLOT1BR_CONDITION");
                assert(!control_commit) else $fatal(1,"SLOT1BR_TRAIN_EXCLUSIVE");
                assert(m1_mispredict===((m1_taken?mtarget1:mp1+32'd4)!=slot1br_pred_q))
                    else $fatal(1,"S1PT_MISPREDICT_REFERENCE");
                assert(mp1===mp+32'd4&&mpred===mp1) else $fatal(1,"S1PT_SLOT0_LINK");
                if(m_redirect1&&!exception_enter&&!irq_take&&!mret_commit&&!maintenance_commit)
                    assert(redirect_pc===(m1_taken?mtarget1:mp1+32'd4)) else $fatal(1,"S1PT_REDIRECT_PC");
                if(slot1_branch_commit) begin
                    if(slot1br_pred_q!=mp1+32'd4) begin
                        if(!m1_taken) s1pt_wrong_nt=s1pt_wrong_nt+1;
                        else if(m1_mispredict) s1pt_wrong_target=s1pt_wrong_target+1;
                        else s1pt_taken_ok=s1pt_taken_ok+1;
                    end else if(m1_taken) s1pt_nt_wrong_taken=s1pt_nt_wrong_taken+1;
                    else s1pt_nt_ok=s1pt_nt_ok+1;
                end
            end
            assert(!(m_redirect0&&m_redirect1)) else $fatal(1,"SLOT1BR_REDIRECT_EXCLUSIVE");
            if(slot1_branch_sel) assert(mv1===mv1_raw_q) else $fatal(1,"SLOT1BR_MV1_RAW");
            assert((m_redirect_ctl||terminal_commit)===(m_redirect||terminal_commit))
                else $fatal(1,"SLOT1BR_CTL_REDIRECT_EQUIV");
            if(slot1_branch_commit) begin
                slot1br_retired=slot1br_retired+1;
                if(m1_taken) slot1br_taken=slot1br_taken+1;
                if(m_redirect1) slot1br_redirect=slot1br_redirect+1;
            end
            if(m_done&&!m_bad&&slot1_branch_sel&&!(mv1&&!terminal_commit)) slot1br_annul=slot1br_annul+1;
        end
    end
    final $display("SLOT1BR_COVER retired=%0d taken=%0d redirect=%0d annul=%0d",
        slot1br_retired,slot1br_taken,slot1br_redirect,slot1br_annul);
    final $display("S1PT_COVER taken_ok=%0d wrong_nt=%0d nt_wrong_taken=%0d wrong_target=%0d nt_ok=%0d",
        s1pt_taken_ok,s1pt_wrong_nt,s1pt_nt_wrong_taken,s1pt_wrong_target,s1pt_nt_ok);
`endif
`ifndef SYNTHESIS
    integer fastredirect_fast=0,fastredirect_slow=0;
    always @(posedge clk) if(!rst) begin
        if(mv) assert(m_fall_q===mp+32'd4&&m_fall4_q===mp+32'd8&&m_fall8_q===mp+32'd12&&
                      m_tgt4_q===mtarget+32'd4&&m_tgt8_q===mtarget+32'd8&&
                      mpred_wrong===(!mfault&&(mtaken?(mtarget!=mpred):((mp+32'd4)!=mpred))))
            else $fatal(1,"FASTREDIRECT_M_METADATA");
        if(slot1_branch_sel) assert(m1_tgt4_q===mtarget1+32'd4&&m1_tgt8_q===mtarget1+32'd8&&
                                    m1_fall_q===mp1+32'd4&&m1_fall4_q===mp1+32'd8&&m1_fall8_q===mp1+32'd12)
            else $fatal(1,"FASTREDIRECT_S1_METADATA");
        if(fast_redirect) begin
            assert(kill&&m_redirect&&redirect_pc===fast_pc&&!exception_enter&&!irq_take&&!mret_commit&&
                   !maintenance_commit&&!terminal_commit&&fast_pc4===fast_pc+32'd4&&fast_pc8===fast_pc+32'd8)
                else $fatal(1,"FASTREDIRECT_PRIORITY");
            fastredirect_fast=fastredirect_fast+1;
        end else if(m_redirect) fastredirect_slow=fastredirect_slow+1;
    end
    final $display("FASTREDIRECT_COVER fast=%0d slow=%0d",fastredirect_fast,fastredirect_slow);
`endif
`ifndef SYNTHESIS
    integer takenpair_taken_pair=0,takenpair_taken_annul=0,takenpair_not_taken_annul=0,takenpair_seq_live=0;
    always @(posedge clk) if(!rst) begin
        // Independent reference: slot 1 is live iff the resolved next PC is its PC.
        if(mv&&mv1_raw_q&&mcontrol) assert(mv1===(mnext==mp1)) else $fatal(1,"TAKENPAIR_LIVE_REFERENCE");
        if(m_done&&!m_bad&&mv1_raw_q&&mcontrol) begin
            if(mp1!=mp+32'd4) begin
                if(mv1) takenpair_taken_pair=takenpair_taken_pair+1;
                else takenpair_taken_annul=takenpair_taken_annul+1;
            end else begin
                if(mv1) takenpair_seq_live=takenpair_seq_live+1;
                else takenpair_not_taken_annul=takenpair_not_taken_annul+1;
            end
        end
    end
    final $display("TAKENPAIR_COVER taken_pair=%0d taken_annul=%0d not_taken_annul=%0d seq_live=%0d",
        takenpair_taken_pair,takenpair_taken_annul,takenpair_not_taken_annul,takenpair_seq_live);
`endif
`ifndef SYNTHESIS
    integer slot1late_forced=0;
    always @(posedge clk) if(!rst&&e_fire&&ev1&&e_integer1&&!e_lui_pair_q&&!e_bitfusion) begin
        if(!e_late1) assert(early_a1===a1&&(ei1[6:0]!=7'h33||early_b1===b1))
            else $fatal(1,"SLOT1LATE_EARLY_OPERAND");
        else slot1late_forced=slot1late_forced+1;
    end
    final $display("SLOT1LATE_COVER late=%0d",slot1late_forced);
`endif
`ifndef SYNTHESIS
    // Registered classes must reproduce the original combinational decisions.
    always @(posedge clk) if(!rst&&MACHINE_MODE!=0) begin
        assert({e_late0,e_late1,mul_raw_dependency,agu_base_load_dependency,agu_store_load_dependency,agu_late_dependency}===
               {e_late0_ref,e_late1_ref,mul_raw_dependency_ref,agu_base_load_dependency_ref,agu_store_load_dependency_ref,agu_late_dependency_ref})
            else $fatal(1,"LSUCTL_CLASS_EQUIVALENCE");
    end
`endif
`ifndef SYNTHESIS
    // A fresh MUL operand register equals its RF payload register.
    integer mulsplit_stale_count=0,mulsplit_hold_count=0;
    always @(posedge clk) if(!rst) begin
        if(!mul_a_stale_q) assert(mul_a_q===rf_a_q) else $fatal(1,"MULSPLIT_A_INCOHERENT");
        if(!mul_b_stale_q) assert(mul_b_q===rf_b_q) else $fatal(1,"MULSPLIT_B_INCOHERENT");
        if(mul_stale_hold) assert(!e_fire) else $fatal(1,"MULSPLIT_HOLD_BYPASSED");
        if(mul_a_stale_q||mul_b_stale_q) mulsplit_stale_count=mulsplit_stale_count+1;
        if(mul_stale_hold) mulsplit_hold_count=mulsplit_hold_count+1;
    end
    final $display("MULSPLIT_COVER stale=%0d hold=%0d",mulsplit_stale_count,mulsplit_hold_count);
`endif
`ifndef SYNTHESIS
    // The registered predecode/link must equal the original combinational decode.
    wire [6:0] ref_d0op=di[6:0],ref_d1op=di1[6:0];
    wire ref_d0_pairable=(ref_d0op==7'h37||ref_d0op==7'h17||ref_d0op==7'h13||
        ref_d0op==7'h33||ref_d0op==7'h03||ref_d0op==7'h23||ref_d0op==7'h63);
    wire ref_d1_simple=(ref_d1op==7'h37||ref_d1op==7'h17||
        (ref_d1op==7'h13&&((di1[14:12]!=3'b001&&di1[14:12]!=3'b101)||(di1[14:12]==3'b001&&di1[31:25]==0)||
         (di1[14:12]==3'b101&&(di1[31:25]==0||di1[31:25]==7'h20))))||
        (ref_d1op==7'h33&&(di1[31:25]==0||(di1[31:25]==7'h20&&(di1[14:12]==0||di1[14:12]==5)))));
    always @(posedge clk) if(!rst&&dv) begin
        assert(d0_pairable===ref_d0_pairable&&d0_writes===(ref_d0op!=7'h23&&ref_d0op!=7'h63&&di[11:7]!=0))
            else $fatal(1,"FIXEDHEAD_PREDECODE0");
        if(dv1) begin
            assert(d1_simple===ref_d1_simple&&d1_use1===(ref_d1op==7'h13||ref_d1op==7'h33||ref_d1op==7'h63)&&
                d1_use2===(ref_d1op==7'h33||ref_d1op==7'h63)&&
                d1_branch===((MACHINE_MODE!=0)&&(ref_d1op==7'h63)&&(di1[14]||(di1[14:13]==2'b00))&&!di1[8]&&(ref_d0op!=7'h63))&&
                front_pair_link===(dp1==front_prediction))
                else $fatal(1,"FIXEDHEAD_PREDECODE1_LINK");
        end
    end
`endif
`ifndef SYNTHESIS
    integer early_fwd0_checks=0,early_fwd1_checks=0;
    always @(posedge clk) if(!rst&&mv&&(MACHINE_MODE!=0)) begin
        assert(early_fwd0_q==={(!mmem||mwrite)&&!mlate0&&m0_rs2,
                              (!mmem||mwrite)&&!mlate0&&m0_rs1})
            else $fatal(1,"EARLY_FWD0_SELECTOR_IDENTITY");
        assert(early_fwd1_q==={mv1_exec&&!mlate1&&m1_rs2,
                              mv1_exec&&!mlate1&&m1_rs1})
            else $fatal(1,"EARLY_FWD1_SELECTOR_IDENTITY");
        if(|early_fwd0_q) early_fwd0_checks<=early_fwd0_checks+1;
        if(|early_fwd1_q) early_fwd1_checks<=early_fwd1_checks+1;
    end
    final $display("EARLY_FORWARD_SELECT_COVER m0=%0d m1=%0d",early_fwd0_checks,early_fwd1_checks);
`endif
`ifndef SYNTHESIS
    if (1) begin : v3_live_oracle
        wire mv1=mv1_raw_q && (!mcontrol || !mpred_wrong);
    reg [31:0] a, b,a1,b1;
    always @* begin
        a = rf_a_q;
        b = rf_b_q;
        a1 = rf_a1_q;
        b1 = rf_b1_q;
        // Preselect from the resident M packet while E is stalled. E can
        // consume these values only on e_fire; with mv high, e_fire implies
        // m_done, !m_bad, !serial_m and !terminal_commit. Keep architectural
        // RF writes and D-stage write-through
        // qualified by their original completed-commit conditions.
        // The youngest older instruction takes priority over the register file.
        if (mv && mr != 0) begin
            if (mr == rs1) a = m_execute_value;
            if (mr == rs2) b = m_execute_value;
            if (mr == rs1_1) a1 = m_execute_value;
            if (mr == rs2_1) b1 = m_execute_value;
        end
        // Slot 1 is younger than slot 0 in the retiring packet.
        // In non-machine mode, fault is also observed by the terminal kill
        // counter/fetch-stop branch. Preserve that parameter's terminal
        // operand value; this guard is constant true in machine mode.
        if (mv && mv1 && mr1 != 0 && ((MACHINE_MODE!=0)||!terminal_commit)) begin
            if (mr1 == rs1) a = mresult1;
            if (mr1 == rs2) b = mresult1;
            if (mr1 == rs1_1) a1 = mresult1;
            if (mr1 == rs2_1) b1 = mresult1;
        end
        if(e_lui_pair) a1=imm_u;
    end

    // Late sources are identified after youngest-writer selection. A newer
    // early slot1 must override an older load/late slot0 classification.
    // Every changing dependency is explicit: do not hide resident-M state
    // inside a function called from a continuous assignment.
    function automatic source_is_slow;
        input [4:0] index;
        input valid0,valid1;
        input [4:0] dest0,dest1;
        input dep0,dep1,terminal;
        begin
            source_is_slow=0;
            if(valid0&&index!=0) begin
                if(valid1&&dest1!=0&&dest1==index&&((MACHINE_MODE!=0)||!terminal))
                    source_is_slow=dep1;
                else if(dest0!=0&&dest0==index) source_is_slow=dep0;
            end
        end
    endfunction
    // Every changing dependency is explicit: do not hide resident-M state
    // inside a function called from a continuous assignment.
    function automatic source_is_late;
        input [4:0] index;
        input valid0,valid1;
        input [4:0] dest0,dest1;
        input dep0,dep1,terminal;
        begin
            source_is_late=0;
            if(valid0&&index!=0) begin
                if(valid1&&dest1!=0&&dest1==index&&((MACHINE_MODE!=0)||!terminal))
                    source_is_late=dep1;
                else if(dest0!=0&&dest0==index) source_is_late=dep0;
            end
        end
    endfunction
    wire e_integer0=integer_alu_encoding(ei),e_integer1=integer_alu_encoding(ei1);
    wire e_late0=ev&&!ee&&e_integer0&&
        (source_is_slow(rs1,mv,mv1,mr,mr1,((mmem&&!mwrite)||mlate0),mlate1,terminal_commit)||((op==7'h33)&&source_is_slow(rs2,mv,mv1,mr,mr1,((mmem&&!mwrite)||mlate0),mlate1,terminal_commit)));
    wire e_late1=ev1&&!ee1&&!e_lui_pair_q&&!e_bitfusion&&e_integer1&&
        (source_is_slow(rs1_1,mv,mv1,mr,mr1,1'b1,1'b1,terminal_commit)||((ei1[6:0]==7'h33)&&source_is_slow(rs2_1,mv,mv1,mr,mr1,1'b1,1'b1,terminal_commit)));
    reg [31:0] early_a,early_b,early_a1,early_b1;
    always @* begin
        early_a=rf_a_q;early_b=rf_b_q;early_a1=rf_a1_q;early_b1=rf_b1_q;
        if(mv&&(!mmem||mwrite)&&!mlate0&&mr_nonzero_q) begin
            if(mr==rs1) early_a=mresult;
            if(mr==rs2) early_b=mresult;
        end
        if(mv&&mv1&&!mlate1&&mr1!=0&&((MACHINE_MODE!=0)||!terminal_commit)) begin
            if(mr1==rs1) early_a=mresult1_payload;
            if(mr1==rs2) early_b=mresult1_payload;
        end
        if(e_lui_pair) early_a1=imm_u;
    end
    wire [31:0] early_alu0=integer_alu(ei,early_a,early_b);
    wire [31:0] early_alu1=e_bitfusion?bitfusion_result(e_bitfusion_q,early_a,early_b):integer_alu(ei1,early_a1,early_b1);

    // Zmmul multiply encodings are implemented; divide encodings and an
    // instruction-fetch fault do not acquire an operand interlock.
    wire e_is_mul=(HW_MUL!=0)&&(op==7'h33)&&(f7==7'h01)&&!f3[2];
    wire mul_raw_primary_dependency=mv&&(mr!=0)&&((mr==rs1)||(mr==rs2));
    wire mul_raw_slot1_dependency=mv&&mv1&&(mr1!=0)&&((mr1==rs1)||(mr1==rs2));
    wire mul_raw_dependency=ev&&!ee&&e_is_mul&&
        (mul_raw_primary_dependency||mul_raw_slot1_dependency);
    // No live M data or destination-select mux reaches the DSP input. On a
    // dependent completion edge M commits while E waits; existing held RF
    // repair captures both retiring slots with slot1 priority for next cycle.
    wire [31:0] mul_a=rf_a_q,mul_b=rf_b_q;

    // Isolate only memory address/store-data calculations from live load
    // returns. Ordinary ALU, slot1 ALU and M-stage branch operands keep their
    // original forwarding; a registered branch resolves in the following M.
    wire e_lsu_encoding=((op==7'h03)&&((f3==0)||(f3==1)||(f3==2)||(f3==4)||(f3==5)))||
                        ((op==7'h23)&&((f3==0)||(f3==1)||(f3==2)));
    wire agu_base_load_dependency=mv&&((mmem&&!mwrite)||mmul_pipe_q)&&(mr!=0)&&(mr==rs1)&&
        !(mv1&&(mr1!=0)&&(mr1==rs1))||(mv&&mv1&&(mr1!=0)&&(mr1==rs1)&&mmul1_live_q);
    wire agu_store_load_dependency=mv&&((mmem&&!mwrite)||mmul_pipe_q)&&(mr!=0)&&(mr==rs2)&&
        !(mv1&&(mr1!=0)&&(mr1==rs2))||(mv&&mv1&&(mr1!=0)&&(mr1==rs2)&&mmul1_live_q);
    wire jalr_load_dependency=ev&&!ee&&(op==7'h67)&&(f3==0)&&agu_base_load_dependency;
    wire agu_load_dependency=ev&&!ee&&e_lsu_encoding&&
        (agu_base_load_dependency||((op==7'h23)&&agu_store_load_dependency));
    wire agu_late_dependency=ev&&!ee&&(e_lsu_encoding||((op==7'h67)&&(f3==0)))&&source_is_late(rs1,mv,mv1,mr,mr1,mlate0,mlate1,terminal_commit);
    reg [31:0] agu_a,agu_b;
    always @* begin
        agu_a=rf_a_q;agu_b=rf_b_q;
        if(mv&&(!mmem||mwrite)&&mr_nonzero_q) begin
            if(!mlate0&&mr==rs1) agu_a=mresult;
            if(mr==rs2) agu_b=m_alu_value;
        end
        if(mv&&mv1&&(mr1!=0)&&((MACHINE_MODE!=0)||!terminal_commit)) begin
            if(!mlate1&&mr1==rs1) agu_a=mresult1_payload;
            if(mr1==rs2) agu_b=mresult1;
        end
    end

    end
    integer v3_consumptions=0,v3_annul_discard=0,v3_live_checks=0;
    always @(posedge clk) if(!rst) begin
        if(mv) begin
            assert(mv1===(mv1_raw_q&&(!mcontrol||!mpred_wrong)))
                else $fatal(1,"V3_LIVE_ANNUL_EQUIVALENCE");
            if(mcontrol&&mconditional)
                assert(m_tgt_eq1_q===(mp+{{19{mi[31]}},mi[31],mi[7],mi[30:25],mi[11:8],1'b0}==mp1)&&
                       m_ft_eq1_q===(mp+32'd4==mp1))
                    else $fatal(1,"V3_STATIC_TARGET_NEXT");
            v3_live_checks=v3_live_checks+1;
        end
        if(MACHINE_MODE==0) assert(mv1_exec===mv1)
            else $fatal(1,"V3_MODE0_EXEC_VALID");
        if(mv&&mv1_raw_q&&!mv1) begin
            assert((m_redirect||m_kill)&&!e_fire&&!early_data_request&&!late_data_request)
                else $fatal(1,"V3_ANNUL_EXECUTION_BARRIER");
            v3_annul_discard=v3_annul_discard+1;
        end
        if(e_fire) begin
            assert(!mv||(mv1_exec===mv1)) else $fatal(1,"V3_CONSUME_VALID");
            assert({a,b,a1,b1,early_a,early_b,early_a1,early_b1,agu_a,agu_b}===
                {v3_live_oracle.a,v3_live_oracle.b,v3_live_oracle.a1,v3_live_oracle.b1,
                 v3_live_oracle.early_a,v3_live_oracle.early_b,v3_live_oracle.early_a1,v3_live_oracle.early_b1,
                 v3_live_oracle.agu_a,v3_live_oracle.agu_b})
                else $fatal(1,"V3_CONSUME_OPERANDS");
            assert({e_late0,e_late1,mul_raw_slot1_dependency,mul_raw_dependency,
                    agu_base_load_dependency,agu_store_load_dependency,jalr_load_dependency,
                    agu_load_dependency,agu_late_dependency}===
                {v3_live_oracle.e_late0,v3_live_oracle.e_late1,v3_live_oracle.mul_raw_slot1_dependency,
                 v3_live_oracle.mul_raw_dependency,v3_live_oracle.agu_base_load_dependency,
                 v3_live_oracle.agu_store_load_dependency,v3_live_oracle.jalr_load_dependency,
                 v3_live_oracle.agu_load_dependency,v3_live_oracle.agu_late_dependency})
                else $fatal(1,"V3_CONSUME_DEPENDENCIES");
            v3_consumptions=v3_consumptions+1;
        end
    end
    final $display("V3_COVER consume=%0d annul_discard=%0d live_checks=%0d",v3_consumptions,v3_annul_discard,v3_live_checks);
`endif
`ifndef SYNTHESIS
    function automatic [31:0] old_read_decode_rf;
        input [4:0] index;
        begin
            old_read_decode_rf=rf_immediate_model[index];
            if(rf_write0&&mr==index) old_read_decode_rf=m_value;
            if(rf_write1&&mr1==index) old_read_decode_rf=mresult1;
        end
    endfunction
    reg [31:0] rf_old_a_q,rf_old_b_q,rf_old_a1_q,rf_old_b1_q;
    always @(posedge clk) begin
        if(rst) begin
            rf_old_a_q<=0;rf_old_b_q<=0;rf_old_a1_q<=0;rf_old_b1_q<=0;
        end else if(rf_payload_capture) begin
            rf_old_a_q<=old_read_decode_rf(di[19:15]);
            rf_old_b_q<=old_read_decode_rf(di[24:20]);
            rf_old_a1_q<=(d_const_a1?d_const_value:old_read_decode_rf(di1[19:15]));
            rf_old_b1_q<=(d_const_b1?d_const_value:old_read_decode_rf(di1[24:20]));
        end else begin
            // E can remain held after M retires (IRQ/serial/run-stop). Keep
            // its raw operands coherent after the transient M bypass leaves.
            if(rf_write0) begin
                if(mr==rs1) rf_old_a_q<=m_value;
                if(mr==rs2) rf_old_b_q<=m_value;
                if(mr==rs1_1) rf_old_a1_q<=m_value;
                if(mr==rs2_1) rf_old_b1_q<=m_value;
            end
            if(rf_write1) begin
                if(mr1==rs1) rf_old_a_q<=mresult1;
                if(mr1==rs2) rf_old_b_q<=mresult1;
                if(mr1==rs1_1) rf_old_a1_q<=mresult1;
                if(mr1==rs2_1) rf_old_b1_q<=mresult1;
            end
        end
    end
    integer rfnext_miter_checked=0,rfnext_capture=0,rfnext_held_repair=0,rfnext_double_match=0;
    always @(posedge clk) if(!rst) begin
        if(ev||(MACHINE_MODE==0))
            assert({rf_a_q,rf_b_q,rf_a1_q,rf_b1_q}==={rf_old_a_q,rf_old_b_q,rf_old_a1_q,rf_old_b1_q})
                else $fatal(1,"RFNEXT_ORIGINAL_LIVE_STATE_MITER");
        if((rf_operand_write0&&!rf_write0)||(rf_operand_write1&&!rf_write1))
            assert(kill&&!e_fire&&!d_fire)
                else $fatal(1,"RF_OPERAND_SPECULATION_KILL_BARRIER");
        rfnext_miter_checked=rfnext_miter_checked+1;
        if(rf_payload_capture)rfnext_capture=rfnext_capture+1;
        if(!rf_payload_capture&&(rf_a_enable||rf_b_enable||rf_a1_enable||rf_b1_enable))rfnext_held_repair=rfnext_held_repair+1;
        if(rf_write0&&rf_write1&&mr==mr1)rfnext_double_match=rfnext_double_match+1;
    end
    final $display("RFNEXT_MITER_PASS checked=%0d capture=%0d held_repair=%0d double_match=%0d",rfnext_miter_checked,rfnext_capture,rfnext_held_repair,rfnext_double_match);
`endif
`ifndef SYNTHESIS
    integer bitfusion_decode=0,bitfusion_consume=0,bitfusion_waw=0,bitfusion_held=0,bitfusion_slow=0,bitfusion_killed=0;
    integer bitfusion_kind1=0,bitfusion_kind2=0,bitfusion_kind3=0,bitfusion_kind4=0;
    always @(posedge clk) if(!rst) begin
        if(d_fire1&&d_bitfusion!=0) bitfusion_decode=bitfusion_decode+1;
        if(ev1) assert(e_bitfusion_q===bitfusion_kind(ei,ei1)) else $fatal(1,"BITFUSION_PAYLOAD_COHERENCE");
        if(bitfusion_slow_hold) begin
            assert(!e_fire&&!early_data_request) else $fatal(1,"BITFUSION_SLOW_INTERLOCK");
            bitfusion_slow=bitfusion_slow+1;
        end
        if(e_bitfusion) begin
            assert(!ee&&!ee1&&!e_late1&&!e_lui_pair) else $fatal(1,"BITFUSION_QUALIFIER");
            if(!e_fire&&!kill) bitfusion_held=bitfusion_held+1;
            if(kill) bitfusion_killed=bitfusion_killed+1;
            if(e_fire) begin
                assert(!e_late0&&early_a===a&&((e_bitfusion_q>=3)||(early_b===b))) else $fatal(1,"BITFUSION_EARLY_OPERANDS");
                assert(er1===alu_oracle(ei1,alu_oracle(ei,a,b),b1)) else $fatal(1,"BITFUSION_COMPOSITION");
                bitfusion_consume=bitfusion_consume+1;
                if(ei1[11:7]==ei[11:7]) bitfusion_waw=bitfusion_waw+1;
                case(e_bitfusion_q)
                    1:bitfusion_kind1=bitfusion_kind1+1;
                    2:bitfusion_kind2=bitfusion_kind2+1;
                    3:bitfusion_kind3=bitfusion_kind3+1;
                    4:bitfusion_kind4=bitfusion_kind4+1;
                endcase
            end
        end
    end
    final $display("BITFUSION_COVER decode=%0d consume=%0d waw=%0d held=%0d slow=%0d killed=%0d kinds=%0d,%0d,%0d,%0d",bitfusion_decode,bitfusion_consume,bitfusion_waw,bitfusion_held,bitfusion_slow,bitfusion_killed,bitfusion_kind1,bitfusion_kind2,bitfusion_kind3,bitfusion_kind4);
`endif
`ifndef SYNTHESIS
    integer lui_pair_decode=0,lui_pair_consume=0,lui_pair_waw=0,lui_pair_oldslow=0,lui_pair_held=0,lui_pair_killed=0;
    always @(posedge clk) if(!rst) begin
        if(d_fire1&&d_lui_pair) lui_pair_decode=lui_pair_decode+1;
        if(ev1) assert(e_lui_pair_q===((ei[6:0]==7'h37)&&(ei[11:7]!=0)&&
            (ei1[6:0]==7'h13)&&(ei1[14:12]==0)&&(ei1[19:15]==ei[11:7])))
            else $fatal(1,"LUI_PAIR_PAYLOAD_COHERENCE");
        if(e_lui_pair) begin
            assert(!ee&&!ee1&&a1==={ei[31:12],12'b0}&&early_a1==={ei[31:12],12'b0}&&!e_late1)
                else $fatal(1,"LUI_PAIR_CONSTANT_OPERAND");
            if(!e_fire&&!kill) lui_pair_held=lui_pair_held+1;
            if(kill) lui_pair_killed=lui_pair_killed+1;
            if(e_fire) begin
                assert(er1===({ei[31:12],12'b0}+{{20{ei1[31]}},ei1[31:20]}))
                    else $fatal(1,"LUI_PAIR_SUM");
                lui_pair_consume=lui_pair_consume+1;
                if(ei1[11:7]==ei[11:7]) lui_pair_waw=lui_pair_waw+1;
                if(v3_live_oracle.source_is_slow(rs1_1,mv,mv1_exec,mr,mr1,((mmem&&!mwrite)||mlate0),mlate1,terminal_commit))
                    lui_pair_oldslow=lui_pair_oldslow+1;
            end
        end
        if(mv&&mv1&&mr!=0&&mr==mr1)
            assert(((mi[6:0]==7'h37&&mi1[6:0]==7'h13&&mi1[14:12]==0&&mi1[19:15]==mr)||(bitfusion_kind(mi,mi1)!=0))&&!mlate1)
                else $fatal(1,"LUI_PAIR_ONLY_WAW_EXCEPTION");
    end
    reg lui_waw_check_q;
    reg [4:0] lui_waw_rd_q;
    reg [31:0] lui_waw_result_q;
    always @(posedge clk) begin
        if(rst) begin lui_waw_check_q<=0;lui_waw_rd_q<=0;lui_waw_result_q<=0;end
        else begin
            if(lui_waw_check_q)
                assert(regs[lui_waw_rd_q]===lui_waw_result_q&&rf_owner_q[lui_waw_rd_q])
                    else $fatal(1,"LUI_PAIR_YOUNGEST_RF_WRITE");
            lui_waw_check_q<=rf_write0&&rf_write1&&(mr==mr1);
            lui_waw_rd_q<=mr1;lui_waw_result_q<=mresult1;
        end
    end
    final $display("LUI_PAIR_COVER decode=%0d consume=%0d waw=%0d oldslow=%0d held=%0d killed=%0d",lui_pair_decode,lui_pair_consume,lui_pair_waw,lui_pair_oldslow,lui_pair_held,lui_pair_killed);
`endif
`ifndef SYNTHESIS
    integer branchparts_capture=0,branchparts_consume=0;
    reg branchparts_oracle;
    always @* begin
        case(mi[14:12])
            0:branchparts_oracle=(mbranch_a==mbranch_b);
            1:branchparts_oracle=(mbranch_a!=mbranch_b);
            4:branchparts_oracle=($signed(mbranch_a)<$signed(mbranch_b));
            5:branchparts_oracle=($signed(mbranch_a)>=$signed(mbranch_b));
            6:branchparts_oracle=(mbranch_a<mbranch_b);
            7:branchparts_oracle=(mbranch_a>=mbranch_b);
            default:branchparts_oracle=1'b0;
        endcase
    end
    always @(posedge clk) if(!rst) begin
        if(e_fire&&control&&conditional&&!fault) branchparts_capture=branchparts_capture+1;
        if(mv&&mcontrol&&mconditional&&!mfault) begin
            assert((^{mbranch_a,mbranch_b})!==1'bx)
                else $fatal(1,"BRANCHPARTS_ACTIVE_OPERANDS_UNKNOWN");
            assert(mbranch_taken===branchparts_oracle)
                else $fatal(1,"BRANCHPARTS_CONSUMPTION_MISMATCH");
            branchparts_consume=branchparts_consume+1;
        end
    end
    final $display("BRANCHPARTS_COVER capture=%0d consume=%0d",branchparts_capture,branchparts_consume);
    integer rf_spec_empty=0,rf_spec_discard=0,rf_spec_consume=0,rf_spec_held=0;
    always @(posedge clk) if(!rst) begin
        assert(!d_fire||rf_payload_capture) else $fatal(1,"RFCAPTURE_MISSED_DECODE");
        assert(!(ev&&!e_fire&&!kill&&rf_payload_capture))
            else $fatal(1,"RFCAPTURE_OVERWROTE_HELD_E");
        if(MACHINE_MODE==0) assert(rf_payload_capture===d_fire)
            else $fatal(1,"RFCAPTURE_MODE0_CHANGED");
        if(rf_payload_capture&&!d_fire) begin
            if(!ev) rf_spec_empty=rf_spec_empty+1;
            else if(kill) rf_spec_discard=rf_spec_discard+1;
            else if(e_fire) rf_spec_consume=rf_spec_consume+1;
            else $fatal(1,"RFCAPTURE_UNPROVEN_OVERWRITE");
        end
        if(ev&&!e_fire&&!kill) rf_spec_held=rf_spec_held+1;
    end
    final $display("RFCAPTURE_COVER empty=%0d discard=%0d consume=%0d held=%0d",
        rf_spec_empty,rf_spec_discard,rf_spec_consume,rf_spec_held);
    // Independent simulation oracle uses direct left/right operators rather
    // than the implementation's single-barrel/reversal function.
    function automatic [31:0] alu_oracle;
        input [31:0] insn,lhs,rhs;
        reg [31:0] r;
        begin
            r=(insn[6:0]==7'h13)?{{20{insn[31]}},insn[31:20]}:rhs;
            case(insn[14:12])
                0:alu_oracle=(insn[6:0]==7'h33&&insn[30])?lhs-r:lhs+r;
                1:alu_oracle=lhs<<r[4:0];
                2:alu_oracle={31'b0,$signed(lhs)<$signed(r)};
                3:alu_oracle={31'b0,lhs<r};
                4:alu_oracle=lhs^r;
                5:alu_oracle=insn[30]?$unsigned($signed(lhs)>>>r[4:0]):lhs>>r[4:0];
                6:alu_oracle=lhs|r;
                7:alu_oracle=lhs&r;
                default:alu_oracle=0;
            endcase
        end
    endfunction
    reg [31:0] late_expected0,late_expected1;
    reg late_expected_valid0,late_expected_valid1;
    integer late_alu_e0=0,late_alu_e1=0,late_alu_m0=0,late_alu_m1=0;
    integer late_alu_early0=0,late_alu_early1=0,late_alu_addr_hold=0,late_alu_store_forward=0;
    always @(posedge clk) begin
        if(rst) begin
            late_expected0<=0;late_expected1<=0;late_expected_valid0<=0;late_expected_valid1<=0;
        end else begin
            if(m_done) begin late_expected_valid0<=0;late_expected_valid1<=0;end
            if(mv&&mlate0&&!mmul_pipe_q) begin
                assert(late_expected_valid0&&m_alu_value===late_expected0) else $fatal(1,"LATE_ALU_M0_RESULT");
                if(m_done&&!m_bad) late_alu_m0=late_alu_m0+1;
            end
            if(mv&&mv1&&mlate1&&!mmul1_live_q) begin
                assert(late_expected_valid1&&mresult1===late_expected1) else $fatal(1,"LATE_ALU_M1_RESULT");
                if(m_done&&!m_bad&&!terminal_commit) late_alu_m1=late_alu_m1+1;
            end
            if(e_fire) begin
                late_expected0<=alu_oracle(ei,a,b);late_expected1<=alu_oracle(ei1,a1,b1);
                late_expected_valid0<=e_late0&&!fault;late_expected_valid1<=e_late1&&!fault;
                if(!fault&&e_integer0) begin
                    if(e_late0) late_alu_e0=late_alu_e0+1;
                    else begin
                        assert(early_a===a&&((op!=7'h33)||(early_b===b))) else $fatal(1,"EARLY_ALU0_OPERANDS");
                        assert(early_alu0===alu_oracle(ei,a,b)) else $fatal(1,"EARLY_ALU0_RESULT");
                        late_alu_early0=late_alu_early0+1;
                    end
                end
                if(!fault&&ev1&&e_integer1) begin
                    if(e_late1) late_alu_e1=late_alu_e1+1;
                    else begin
                        assert(e_bitfusion||(early_a1===a1&&((op1!=7'h33)||(early_b1===b1)))) else $fatal(1,"EARLY_ALU1_OPERANDS");
                        assert(early_alu1===alu_oracle(ei1,e_bitfusion?alu_oracle(ei,a,b):a1,b1)) else $fatal(1,"EARLY_ALU1_RESULT");
                        late_alu_early1=late_alu_early1+1;
                    end
                end
                if(op==7'h23&&v3_live_oracle.source_is_late(rs2,mv,mv1,mr,mr1,mlate0,mlate1,terminal_commit)&&!fault) late_alu_store_forward=late_alu_store_forward+1;
            end
            if(agu_late_dependency) begin
                assert(!e_fire&&!early_data_request) else $fatal(1,"LATE_ALU_AGU_INTERLOCK");
                if(m_done&&!m_bad&&!m_redirect&&!irq_wait&&!run_stop&&!terminal_commit&&!serial_m)
                    late_alu_addr_hold=late_alu_addr_hold+1;
            end
        end
    end
    final $display("LATE_ALU_COVER e0=%0d e1=%0d m0=%0d m1=%0d early0=%0d early1=%0d addr_hold=%0d store_forward=%0d",
        late_alu_e0,late_alu_e1,late_alu_m0,late_alu_m1,late_alu_early0,late_alu_early1,late_alu_addr_hold,late_alu_store_forward);
    // Consumption equivalence to the original completion-qualified bypass.
    function automatic [31:0] completed_execute_operand;
        input [4:0] index;
        input [31:0] raw_value;
        begin
            completed_execute_operand=raw_value;
            if(m_done && !m_bad && !mcsr && mr!=0 && mr==index)
                completed_execute_operand=m_execute_value;
            if(m_done && !m_bad && mv1 && mr1!=0 && !terminal_commit && mr1==index)
                completed_execute_operand=mresult1;
        end
    endfunction
    integer mul_raw_hold_count=0,mul_raw_execute_count=0;
    always @(posedge clk) if(!rst) begin
        if(mul_raw_dependency) begin
            assert(!e_fire&&!early_data_request) else $fatal(1,"MUL_RAW_INTERLOCK_BYPASSED");
            if(m_done&&!m_bad&&!m_redirect&&!irq_wait&&!run_stop&&!terminal_commit&&!serial_m)
                mul_raw_hold_count=mul_raw_hold_count+1;
        end
        if(e_fire&&e_is_mul&&!fault) begin
            assert({mul_a,mul_b}==={a,b}) else $fatal(1,"MUL_RAW_OPERAND_MISMATCH");
            mul_raw_execute_count=mul_raw_execute_count+1;
        end
    end
    final $display("MUL_RAW_COVER held=%0d executed=%0d",mul_raw_hold_count,mul_raw_execute_count);
    integer jalr_load_hold_count=0,jalr_consume_count=0;
    always @(posedge clk) if(!rst) begin
        if(jalr_load_dependency) begin
            assert(!e_fire&&!early_data_request) else $fatal(1,"JALR_LOAD_INTERLOCK_BYPASSED");
            if(m_done&&!m_bad&&!m_redirect&&!irq_wait&&!run_stop&&!terminal_commit&&!serial_m)
                jalr_load_hold_count=jalr_load_hold_count+1;
        end
        if(e_fire&&!ee&&(op==7'h67)&&(f3==0)) begin
            assert(agu_a===a) else $fatal(1,"JALR_AGU_OPERAND_MISMATCH");
            assert(target===((a+imm_i)&32'hfffffffe)) else $fatal(1,"JALR_TARGET_MISMATCH");
            jalr_consume_count=jalr_consume_count+1;
        end
        if(mv) assert(mpred_wrong===(!mfault&&(mnext!=mpred)))
            else $fatal(1,"PARALLEL_PREDICTION_MISMATCH");
    end
    final $display("JALR_AGU_COVER held=%0d consumed=%0d",jalr_load_hold_count,jalr_consume_count);
    integer agu_load_hold_count=0,agu_consume_count=0;
    always @(posedge clk) if(!rst) begin
        if(agu_load_dependency) begin
            assert(!e_fire&&!early_data_request) else $fatal(1,"AGU_LOAD_INTERLOCK_BYPASSED");
            if(m_done&&!m_bad&&!m_redirect&&!irq_wait&&!run_stop&&!terminal_commit&&!serial_m)
                agu_load_hold_count=agu_load_hold_count+1;
        end
        if(e_fire&&e_lsu_encoding&&!ee) begin
            assert(agu_a===a) else $fatal(1,"AGU_BASE_OPERAND_MISMATCH");
            if(op==7'h23) assert(agu_b===b) else $fatal(1,"AGU_STORE_OPERAND_MISMATCH");
            agu_consume_count=agu_consume_count+1;
        end
    end
    final $display("AGU_LOAD_COVER held=%0d consumed=%0d",agu_load_hold_count,agu_consume_count);
    integer prefwd_consume_count=0;
    always @(posedge clk) if(!rst && e_fire) begin
        assert({a,b,a1,b1} === {
            completed_execute_operand(rs1,rf_a_q),
            completed_execute_operand(rs2,rf_b_q),
            e_lui_pair?{ei[31:12],12'b0}:completed_execute_operand(rs1_1,rf_a1_q),
            completed_execute_operand(rs2_1,rf_b1_q)})
            else $fatal(1,"PREFWD_CONSUMPTION_MISMATCH");
        prefwd_consume_count=prefwd_consume_count+1;
    end
    final $display("PREFWD_ASSERT_COVER consumed=%0d",prefwd_consume_count);
`endif
`ifndef SYNTHESIS
    integer rf_capture_count=0,rf_capture_write0=0,rf_capture_write1=0;
    integer rf_held_write0=0,rf_held_write1=0;
    always @(posedge clk) if(!rst) begin
        if(ev) begin
            assert(rf_a_q===(rs1==0?32'b0:regs[rs1])) else $fatal(1,"RFREAD_A_INCOHERENT");
            assert(rf_b_q===(rs2==0?32'b0:regs[rs2])) else $fatal(1,"RFREAD_B_INCOHERENT");
            assert(rf_a1_q===(e_const_a1_q?{{20{ei[31]}},ei[31:20]}:(rs1_1==0?32'b0:regs[rs1_1]))) else $fatal(1,"RFREAD_A1_INCOHERENT");
            assert(rf_b1_q===(e_const_b1_q?{{20{ei[31]}},ei[31:20]}:(rs2_1==0?32'b0:regs[rs2_1]))) else $fatal(1,"RFREAD_B1_INCOHERENT");
        end
        if(d_fire) begin
            rf_capture_count=rf_capture_count+1;
            if(rf_write0&&((mr==di[19:15])||(mr==di[24:20])||(mr==d_src_a1)||(mr==d_src_b1)))
                rf_capture_write0=rf_capture_write0+1;
            if(rf_write1&&((mr1==di[19:15])||(mr1==di[24:20])||(mr1==d_src_a1)||(mr1==d_src_b1)))
                rf_capture_write1=rf_capture_write1+1;
        end else if(ev) begin
            if(rf_write0&&((mr==rs1)||(mr==rs2)||(mr==rs1_1)||(mr==rs2_1))) rf_held_write0=rf_held_write0+1;
            if(rf_write1&&((mr1==rs1)||(mr1==rs2)||(mr1==rs1_1)||(mr1==rs2_1))) rf_held_write1=rf_held_write1+1;
        end
    end
    final $display("RFREAD_ASSERT_COVER captures=%0d capture_write0=%0d capture_write1=%0d held_write0=%0d held_write1=%0d",
        rf_capture_count,rf_capture_write0,rf_capture_write1,rf_held_write0,rf_held_write1);
    always @(posedge clk) if(!rst) begin
        assert(!(late_data_request&&early_data_request));
        // Every live second slot follows a correctly predicted sequential PC.
        // Conditional branch slot 0 is allowed only under that same contract.
        if(mv&&mv1) assert(!mpred_wrong&&(!mcontrol||mconditional));
        if(mv&&mv1_raw_q&&mcontrol) begin
            // Slot 1 is the predicted next PC (sequential or predicted-taken target).
            assert(mconditional&&mp1==mpred&&(MACHINE_MODE!=0||mpred==mp+32'd4))
                else $fatal(1,"BRANCHPAIR_RAW_CONTRACT");
            assert(mv1===!mpred_wrong)
                else $fatal(1,"BRANCHPAIR_ANNUL_CONTRACT");
            if(mpred_wrong) assert(!rf_write1)
                else $fatal(1,"BRANCHPAIR_WRONG_PATH_WRITE");
        end
        if(m_redirect||m_kill) assert(!e_fire&&!early_data_request);
        if(early_data_request) begin
            assert(e_fire&&!fault&&mem);
            assert(!mv||m_done);
        end
    end
`endif
`ifndef SYNTHESIS
    integer control_commit_checks=0,control_commit_count=0;
    always @(posedge clk) if(!rst) begin
        if(e_fire&&control)
            assert(!mem&&!csr&&!mret&&!fencei&&!fault)
                else $fatal(1,"CTRLCOMMIT_CAPTURE_KINDS");
        if(mv&&mcontrol)
            assert(!mmem&&!mcsr&&!mmret&&!mfencei&&!mfault)
                else $fatal(1,"CTRLCOMMIT_RESIDENT_KINDS");
        assert(control_commit===(m_done&&!m_bad&&mcontrol))
            else $fatal(1,"CTRLCOMMIT_CYCLE_EQUIVALENCE");
        control_commit_checks=control_commit_checks+1;
        if(control_commit)control_commit_count=control_commit_count+1;
    end
    final $display("CTRLCOMMIT_COVER checked=%0d committed=%0d",control_commit_checks,control_commit_count);
`endif
`ifndef SYNTHESIS
    integer branchpair_packets=0,branchpair_live=0,branchpair_annul=0;
    integer branchpair_taken_next=0,branchpair_not_taken=0,branchpair_bad=0;
    always @(posedge clk) if(!rst&&m_done&&mv1_raw_q&&mcontrol) begin
        branchpair_packets=branchpair_packets+1;
        if(m_bad) branchpair_bad=branchpair_bad+1;
        else if(mv1) begin
            branchpair_live=branchpair_live+1;
            if(mtaken) branchpair_taken_next=branchpair_taken_next+1;
            else branchpair_not_taken=branchpair_not_taken+1;
        end else branchpair_annul=branchpair_annul+1;
    end
    final $display("BRANCHPAIR_COVER packets=%0d live=%0d annul=%0d taken_next=%0d not_taken=%0d bad=%0d",
        branchpair_packets,branchpair_live,branchpair_annul,branchpair_taken_next,branchpair_not_taken,branchpair_bad);
`endif
`ifndef SYNTHESIS
    integer reqpayload_checked=0,reqpayload_early=0,reqpayload_late=0,reqpayload_held=0,reqpayload_turnover=0;
    always @(posedge clk) if(!rst) begin
        assert(!(late_data_request&&early_data_request)) else $fatal(1,"REQPAYLOAD_BOTH_REQUESTS");
        if(d_req_valid) begin
            assert({d_req_addr,d_req_write,d_req_be,d_req_wdata}===
                (early_data_request?{{ea[31:2],2'b0},wr,be,(wr?ew:32'b0)}:{{maddr[31:2],2'b0},mwrite,mbe,mwdata}))
                else $fatal(1,"REQPAYLOAD_ACTIVE_EQUIVALENCE");
            reqpayload_checked=reqpayload_checked+1;
            if(early_data_request) reqpayload_early=reqpayload_early+1;
            if(late_data_request) reqpayload_late=reqpayload_late+1;
            if(!d_req_ready) reqpayload_held=reqpayload_held+1;
            if(d_rsp_valid&&d_rsp_ready) reqpayload_turnover=reqpayload_turnover+1;
        end
    end
    final $display("REQPAYLOAD_COVER checked=%0d early=%0d late=%0d held=%0d turnover=%0d",reqpayload_checked,reqpayload_early,reqpayload_late,reqpayload_held,reqpayload_turnover);
`endif
`ifndef SYNTHESIS
    integer aguselect_checked=0,aguselect_consumed=0,aguselect_negative=0;
    always @(posedge clk) if(!rst&&ev&&((op==7'h03)||(op==7'h23))) begin
        assert(ea===(agu_a+(wr ? imm_s : imm_i)))
            else $fatal(1,"AGUSELECT_ADDRESS_MISMATCH");
        aguselect_checked=aguselect_checked+1;
        if(e_fire) aguselect_consumed=aguselect_consumed+1;
        if(ei[31]) aguselect_negative=aguselect_negative+1;
    end
    final $display("AGUSELECT_COVER checked=%0d consumed=%0d negative=%0d",aguselect_checked,aguselect_consumed,aguselect_negative);
`endif
`ifndef SYNTHESIS
    wire [31:0] csr_original_wdata=(mi[13:12]==2'b01)?mcsr_operand:
        (mi[13:12]==2'b10)?(csr_rdata|mcsr_operand):(csr_rdata&~mcsr_operand);
    integer csr_leaf_write_checks=0,csr_leaf_perf_reads=0;
    always @(posedge clk) if(!rst&&m_done&&!m_bad&&mcsr) begin
        if(csr_write) begin
            assert(csr_wdata===csr_original_wdata)
                else $fatal(1,"CSR_MODIFY_LEAF_IDENTITY");
            csr_leaf_write_checks<=csr_leaf_write_checks+1;
        end
        if(csr_read&&perf_known) csr_leaf_perf_reads<=csr_leaf_perf_reads+1;
    end
    final $display("CSR_MODIFY_LEAF_COVER writes=%0d perf_reads=%0d",
        csr_leaf_write_checks,csr_leaf_perf_reads);
`endif
`ifndef SYNTHESIS
    wire slot1_branch_commit_original=m_done&&!m_bad&&!terminal_commit&&slot1_branch_sel;
    integer slot1_commit_checks=0,slot1_commit_memory=0,slot1_commit_error=0;
    always @(posedge clk) if(!rst) begin
        assert(slot1_branch_commit===slot1_branch_commit_original)
            else $fatal(1,"SLOT1_COMMIT_QUALIFICATION_IDENTITY");
        if(mv&&slot1_branch_sel) begin
            assert(!mcsr&&!mcontrol&&!mmret&&!mfencei)
                else $fatal(1,"SLOT1_COMMIT_PACKET_CLASS");
            slot1_commit_checks<=slot1_commit_checks+1;
            if(mmem) slot1_commit_memory<=slot1_commit_memory+1;
            if(m_response&&d_rsp_error) slot1_commit_error<=slot1_commit_error+1;
        end
    end
    final $display("SLOT1_COMMIT_QUAL_COVER packets=%0d memory=%0d error=%0d",
        slot1_commit_checks,slot1_commit_memory,slot1_commit_error);
`endif
`ifndef SYNTHESIS
    integer branch_half_checks=0,branch_half_low_decides=0;
    always @(posedge clk) if(!rst&&mv&&mcontrol&&mconditional&&mi[14]) begin
        assert(mbranch_order_lt===(mi[13]?mbranch_unsigned_lt:mbranch_signed_lt))
            else $fatal(1,"BRANCH_HALF_COMPARISON_IDENTITY");
        branch_half_checks<=branch_half_checks+1;
        if(mbranch_order_hi_eq_q) branch_half_low_decides<=branch_half_low_decides+1;
    end
    final $display("BRANCH_HALF_COVER checks=%0d lower_decides=%0d",
        branch_half_checks,branch_half_low_decides);
`endif
`ifndef SYNTHESIS
    integer early_alu_predecode_checks=0,early_alu_predecode_slot1=0;
    always @(posedge clk) if(!rst) begin
        assert({e_alu_imm0_q,e_alu_sub0_q,e_alu_left0_q,e_alu_arith0_q}===
               {(ei[6:0]==7'h13),((ei[6:0]==7'h33)&&ei[30]),
                (ei[14:12]==3'd1),((ei[14:12]==3'd5)&&ei[30])})
            else $fatal(1,"EARLY_ALU0_PREDECODE_IDENTITY");
        assert({e_alu_imm1_q,e_alu_sub1_q,e_alu_left1_q,e_alu_arith1_q}===
               {(ei1[6:0]==7'h13),((ei1[6:0]==7'h33)&&ei1[30]),
                (ei1[14:12]==3'd1),((ei1[14:12]==3'd5)&&ei1[30])})
            else $fatal(1,"EARLY_ALU1_PREDECODE_IDENTITY");
        if(ev) begin
            assert(early_alu0===integer_alu(ei,early_a,early_b))
                else $fatal(1,"EARLY_ALU0_DECODED_RESULT");
            early_alu_predecode_checks<=early_alu_predecode_checks+1;
        end
        if(ev1) begin
            assert(early_alu1===(e_bitfusion?bitfusion_result(e_bitfusion_q,early_a,early_b):integer_alu(ei1,early_a1,early_b1)))
                else $fatal(1,"EARLY_ALU1_DECODED_RESULT");
            early_alu_predecode_slot1<=early_alu_predecode_slot1+1;
        end
    end
    final $display("EARLY_ALU_PREDECODE_COVER slot0=%0d slot1=%0d",
        early_alu_predecode_checks,early_alu_predecode_slot1);
`endif
`ifndef SYNTHESIS
    integer rf_model_index;
    always @(posedge clk) begin
        if(rst) begin
            for(rf_model_index=0;rf_model_index<32;rf_model_index=rf_model_index+1)
                rf_immediate_model[rf_model_index]<=0;
        end else begin
            // Original immediate architectural updates, independent of WB.
            if(rf_write0) rf_immediate_model[mr]<=m_value;
            if(rf_write1) rf_immediate_model[mr1]<=mresult1;
        end
    end
    integer rf_wb_checks=0,rf_wb_reads=0,rf_wb_double=0;
    always @(posedge clk) if(!rst) begin
        assert(regs[0]===32'b0) else $fatal(1,"RF_WB_X0");
        if(rf_wb0_valid_q) begin
            assert(rf_wb0_rd_q!=0&&regs[rf_wb0_rd_q]===rf_immediate_model[rf_wb0_rd_q])
                else $fatal(1,"RF_WB_COMMIT0_IDENTITY");
            rf_wb_checks<=rf_wb_checks+1;
        end
        if(rf_wb1_valid_q) begin
            assert(rf_wb1_rd_q!=0&&regs[rf_wb1_rd_q]===rf_immediate_model[rf_wb1_rd_q])
                else $fatal(1,"RF_WB_COMMIT1_IDENTITY");
            if(rf_wb0_valid_q&&rf_wb0_rd_q==rf_wb1_rd_q)
                rf_wb_double<=rf_wb_double+1;
        end
        if(dv&&rf_payload_capture) begin
            assert(read_decode_rf(di[19:15])===rf_immediate_model[di[19:15]]&&
                   read_decode_rf(di[24:20])===rf_immediate_model[di[24:20]])
                else $fatal(1,"RF_WB_DECODE0_IDENTITY");
            rf_wb_reads<=rf_wb_reads+1;
            if(dv1)
                assert(read_decode_rf(di1[19:15])===rf_immediate_model[di1[19:15]]&&
                       read_decode_rf(di1[24:20])===rf_immediate_model[di1[24:20]])
                    else $fatal(1,"RF_WB_DECODE1_IDENTITY");
        end
    end
    final $display("RF_WRITEBACK_COVER commits=%0d reads=%0d double=%0d",
        rf_wb_checks,rf_wb_reads,rf_wb_double);
`endif

`ifndef SYNTHESIS
    integer const_branch_decode=0,const_branch_consume=0,const_branch_held=0,const_branch_killed=0;
    always @(posedge clk) if(!rst) begin
        if(d_fire1&&d_const_branch&&(d_const_a1||d_const_b1)) const_branch_decode++;
        if(ev1&&(e_const_a1_q||e_const_b1_q)) begin
            assert(ei[6:0]==7'h13&&ei[14:12]==0&&ei[19:15]==0&&ei[11:7]!=0&&
                ei1[6:0]==7'h63&&(ei1[14]||ei1[14:13]==0)&&!ei1[8])
                else $fatal(1,"CONST_BRANCH_LEGALITY");
            assert(e_const_a1_q===(ei1[19:15]==ei[11:7])&&
                   e_const_b1_q===(ei1[24:20]==ei[11:7]))
                else $fatal(1,"CONST_BRANCH_SOURCE_MAP");
            if(e_const_a1_q) assert(rf_a1_q==={{20{ei[31]}},ei[31:20]}&&
                !m0_rs1_1&&!m1_rs1_1) else $fatal(1,"CONST_BRANCH_A_STABILITY");
            if(e_const_b1_q) assert(rf_b1_q==={{20{ei[31]}},ei[31:20]}&&
                !m0_rs2_1&&!m1_rs2_1) else $fatal(1,"CONST_BRANCH_B_STABILITY");
            if(e_fire) begin
                const_branch_consume++;
                if(e_const_a1_q) assert(branch1_a==={{20{ei[31]}},ei[31:20]}) else $fatal(1,"CONST_BRANCH_A_EXECUTE");
                if(e_const_b1_q) assert(branch1_b==={{20{ei[31]}},ei[31:20]}) else $fatal(1,"CONST_BRANCH_B_EXECUTE");
            end
            if(!e_fire&&!kill) const_branch_held++;
            if(kill) const_branch_killed++;
        end
    end
    final $display("CONST_BRANCH_COVER decode=%0d consume=%0d held=%0d killed=%0d",const_branch_decode,const_branch_consume,const_branch_held,const_branch_killed);
`endif
endmodule
