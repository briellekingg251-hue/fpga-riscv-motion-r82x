`timescale 1ns/1ps
// Original P1 RV32I core. See docs/{architecture,interface}_contract.md.
module p1_core #(
    parameter [31:0] RESET_PC = 32'h80000000
) (
    input wire clk, rst,
    output wire i_req_valid, input wire i_req_ready, output wire [31:0] i_req_addr,
    input wire i_rsp_valid, output wire i_rsp_ready,
    input wire [31:0] i_rsp_data, input wire i_rsp_error,
    output wire d_req_valid, input wire d_req_ready,
    output wire [31:0] d_req_addr, output wire d_req_write,
    output wire [3:0] d_req_be, output wire [31:0] d_req_wdata,
    input wire d_rsp_valid, output wire d_rsp_ready,
    input wire [31:0] d_rsp_data, input wire d_rsp_error,
    output reg trace_valid, trace_trap,
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
    reg [31:0] regs [0:31];
    reg fq_valid, fq_discard, fo_valid, fo_discard, fetch_stop;
    reg [31:0] fq_pc, fo_pc, next_pc;
    reg dv, ev, mv;
    reg [31:0] dp, di, ep, ei, mp, mi;
    reg de, ee;
    reg [4:0] mr;
    reg [31:0] mresult, maddr, mwdata, mcause, mtval;
    reg [3:0] mbe;
    reg [2:0] mfunct3;
    reg mmem, mwrite, mfault, msent;

    wire [4:0] rs1 = ei[19:15], rs2 = ei[24:20];
    wire [6:0] op = ei[6:0], f7 = ei[31:25];
    wire [2:0] f3 = ei[14:12];
    wire [31:0] imm_i = {{20{ei[31]}},ei[31:20]};
    wire [31:0] imm_s = {{20{ei[31]}},ei[31:25],ei[11:7]};
    wire [31:0] imm_b = {{19{ei[31]}},ei[31],ei[7],ei[30:25],ei[11:8],1'b0};
    wire [31:0] imm_j = {{11{ei[31]}},ei[31],ei[19:12],ei[20],ei[30:21],1'b0};
    wire [31:0] imm_u = {ei[31:12],12'b0};

    wire m_response = mv && mmem && !mfault && msent && d_rsp_valid;
    wire m_done = mv && (mfault || !mmem || m_response);
    wire m_bad = mfault || (m_response && d_rsp_error);
    wire [31:0] m_final_cause = mfault ? mcause : (mwrite ? 32'd7 : 32'd5);
    wire [31:0] m_final_tval = mfault ? mtval : maddr;
    wire [31:0] load_value;
    p1_load_align load_align(.data(d_rsp_data),.offset(maddr[1:0]),
        .funct3(mfunct3),.result(load_value));
    wire [31:0] m_value = (mmem && !mwrite) ? load_value : mresult;
    reg [31:0] a, b;
    always @* begin
        a = rs1 == 0 ? 0 : regs[rs1];
        b = rs2 == 0 ? 0 : regs[rs2];
        // The youngest older instruction takes priority over the register file.
        if (m_done && !m_bad && mr != 0) begin
            if (mr == rs1) a = m_value;
            if (mr == rs2) b = m_value;
        end
    end

    reg [31:0] er, ea, ew, ecause, etval, target;
    reg [4:0] rd;
    reg [3:0] be;
    reg mem, wr, fault, redirect, legal, use1, use2;
    always @* begin
        er=0; ea=0; ew=0; ecause=2; etval=ei; target=0;
        rd=ei[11:7]; be=0; mem=0; wr=0; fault=0; redirect=0;
        legal=1; use1=0; use2=0;
        case (op)
            7'h37: er=imm_u;
            7'h17: er=ep+imm_u;
            7'h6f: begin er=ep+4; target=ep+imm_j; redirect=1; end
            7'h67: begin
                use1=1; er=ep+4; target=(a+imm_i)&32'hfffffffe;
                redirect=1; if (f3!=0) legal=0;
            end
            7'h63: begin
                use1=1; use2=1; rd=0; target=ep+imm_b;
                case(f3)
                    0: redirect=(a==b);
                    1: redirect=(a!=b);
                    4: redirect=($signed(a)<$signed(b));
                    5: redirect=($signed(a)>=$signed(b));
                    6: redirect=(a<b);
                    7: redirect=(a>=b);
                    default: legal=0;
                endcase
            end
            7'h03,7'h23: begin
                use1=1; use2=(op==7'h23); mem=1; wr=(op==7'h23);
                ea=a+(wr ? imm_s : imm_i); ew=b << {ea[1:0],3'b000};
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
                case(f3)
                    0: er=a+imm_i;
                    2: er={31'b0,($signed(a)<$signed(imm_i))};
                    3: er={31'b0,(a<imm_i)};
                    4: er=a^imm_i;
                    6: er=a|imm_i;
                    7: er=a&imm_i;
                    1: begin er=a << ei[24:20]; if(f7!=0) legal=0; end
                    5: begin
                        er=ei[30] ? $unsigned($signed(a) >>> ei[24:20]) : a >> ei[24:20];
                        if(f7!=0 && f7!=7'h20) legal=0;
                    end
                    default: legal=0;
                endcase
            end
            7'h33: begin
                use1=1; use2=1;
                if(f7!=0 && !(f7==7'h20 && (f3==0 || f3==5))) legal=0;
                case(f3)
                    0: er=ei[30] ? a-b : a+b;
                    1: er=a << b[4:0];
                    2: er={31'b0,($signed(a)<$signed(b))};
                    3: er={31'b0,(a<b)};
                    4: er=a^b;
                    5: er=ei[30] ? $unsigned($signed(a) >>> b[4:0]) : a >> b[4:0];
                    6: er=a|b;
                    7: er=a&b;
                    default: legal=0;
                endcase
            end
            // M serializes all accesses, so older device writes are acknowledged
            // before FENCE advances and no younger access can be issued yet.
            7'h0f: begin rd=0; if(f3!=0) legal=0; end
            7'h73: begin
                rd=0; fault=1; etval=0;
                if(ei==32'h00000073) ecause=11;
                else if(ei==32'h00100073) ecause=3;
                else legal=0;
            end
            default: legal=0;
        endcase
        if(redirect && |target[1:0]) begin fault=1; ecause=0; etval=target; end
        if(!legal) begin fault=1; ecause=2; etval=ei; mem=0; end
        if(ee) begin fault=1; ecause=1; etval=ep; mem=0; end
        if(fault) begin rd=0; redirect=0; end
    end

    wire e_fire = ev && (!mv || m_done) && !(m_done && m_bad) && !halted;
    wire m_kill = m_done && m_bad;
    wire e_kill = e_fire && (redirect || fault);
    wire kill = m_kill || e_kill;
    wire d_fire = dv && (!ev || e_fire) && !kill && !halted;
    assign i_req_valid=fq_valid;
    assign i_req_addr=fq_pc;
    assign i_rsp_ready=fo_valid && (fo_discard || !dv || d_fire || kill || fetch_stop);
    wire i_accept=i_req_valid && i_req_ready;
    wire i_return=i_rsp_valid && i_rsp_ready;
    assign d_req_valid=mv && mmem && !mfault && !msent;
    assign d_req_addr={maddr[31:2],2'b0};
    assign d_req_write=mwrite;
    assign d_req_be=mbe;
    assign d_req_wdata=mwdata;
    assign d_rsp_ready=mv && mmem && !mfault && msent;

    integer n;
    always @(posedge clk) begin
        if(rst) begin
            for(n=0;n<32;n=n+1) regs[n]<=0;
            fq_valid<=1; fq_pc<=RESET_PC; fq_discard<=0;
            fo_valid<=0; fo_pc<=0; fo_discard<=0; next_pc<=RESET_PC+4; fetch_stop<=0;
            dv<=0; ev<=0; mv<=0; dp<=0; di<=0; ep<=0; ei<=0; mp<=0; mi<=0; de<=0; ee<=0;
            mr<=0; mresult<=0; maddr<=0; mwdata<=0; mcause<=0; mtval<=0; mbe<=0; mfunct3<=0;
            mmem<=0; mwrite<=0; mfault<=0; msent<=0; halted<=0;
            trace_valid<=0; trace_trap<=0; trace_pc<=0; trace_insn<=0; trace_rd<=0; trace_wdata<=0;
            trace_cause<=0; trace_tval<=0; trace_mem_valid<=0; trace_mem_write<=0;
            trace_mem_addr<=0; trace_mem_wdata<=0; trace_mem_rdata<=0; trace_mem_be<=0;
            count_cycle<=0; count_retired<=0; count_if_wait<=0; count_data_wait<=0;
            count_load_use<=0; count_redirect<=0; count_reads<=0; count_writes<=0;
        end else begin
            trace_valid<=0;
            if(!halted) begin
                count_cycle<=count_cycle+1;
                if(!dv) count_if_wait<=count_if_wait+1;
                if(mv && mmem && !m_done) count_data_wait<=count_data_wait+1;
                if(ev && mv && mmem && !mwrite && !m_done && mr!=0 &&
                   ((use1 && rs1==mr) || (use2 && rs2==mr))) count_load_use<=count_load_use+1;
            end
            if(d_req_valid && d_req_ready) begin
                msent<=1;
                if(mwrite) count_writes<=count_writes+1; else count_reads<=count_reads+1;
            end
            // W: architectural state and trace are committed together.
            if(m_done) begin
                mv<=0; trace_valid<=1; trace_trap<=m_bad;
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
                if(m_bad) halted<=1;
                else begin
                    count_retired<=count_retired+1;
                    if(mr!=0) regs[mr]<=m_value;
                end
            end
            if(e_fire) begin
                ev<=0; mv<=1; mp<=ep; mi<=ei; mr<=rd; mresult<=er;
                maddr<=ea; mwdata<=ew; mbe<=be; mfunct3<=f3;
                mmem<=mem; mwrite<=wr; mfault<=fault; mcause<=ecause; mtval<=etval; msent<=0;
            end
            if(d_fire) begin ev<=1; ep<=dp; ei<=di; ee<=de; dv<=0; end
            if(i_return) begin
                fo_valid<=0;
                if(!fo_discard && !kill && !fetch_stop) begin
                    dv<=1; dp<=fo_pc; di<=i_rsp_data; de<=i_rsp_error;
                end
            end
            if(i_accept) begin
                fq_valid<=0; fo_valid<=1; fo_pc<=fq_pc;
                fo_discard<=fq_discard || kill || fetch_stop;
            end
            // A registered new offer follows response consumption: one documented
            // turnaround cycle, no same-cycle combinational memory dependency.
            if(!fq_valid && (!fo_valid || i_return) && !fetch_stop && !halted) begin
                fq_valid<=1; fq_pc<=next_pc; fq_discard<=0; next_pc<=next_pc+4;
            end
            if(kill) begin
                dv<=0; ev<=0;
                if(fo_valid && !i_return) fo_discard<=1;
                if(fq_valid && !i_accept) fq_discard<=1;
                // Cancel only an offer created at this edge, never an offer
                // already visible to a peer. Old visible offers must drain.
                if(!fq_valid) fq_valid<=0;
                if(m_kill || fault) fetch_stop<=1;
                else begin next_pc<=target; count_redirect<=count_redirect+1; end
            end
        end
    end
endmodule
