`timescale 1ns/1ps
// M-only privileged architecture, ISA snapshot 20260120, Machine ISA v1.13.
// No U/S, Zicntr, PMP, MMU or Sscofpmf. See docs/p2/interface_v2.md.
module p2_csr (
    input wire clk,rst,
    input wire access_valid,input wire [11:0] access_addr,
    input wire access_write,input wire [31:0] access_wdata,
    input wire access_commit,
    input wire perf_known,input wire [31:0] perf_rdata,
    output reg [31:0] access_rdata,output wire access_error,
    output wire [31:0] access_modify_rdata,
    input wire retire,
    input wire retire_second,
    input wire trap_enter,input wire [31:0] trap_pc,trap_cause,trap_tval,
    input wire mret_commit,
    input wire irq_software,irq_timer,irq_external,
    output wire irq_eligible,output wire [31:0] irq_cause,
    output wire [31:0] handler_pc,return_pc,
    output wire [63:0] machine_cycle,machine_retired
);
    reg mie_global,mpie;
    reg [31:0] mie,mtvec,mscratch,mepc,mcause,mtval;
    reg [2:0] inhibit;
    reg [63:0] mcycle,minstret;
    wire unused_trap_low=^trap_pc[1:0]; // mepc is WARL aligned for IALIGN=32.
    wire [31:0] mip={20'b0,irq_external,3'b0,irq_timer,3'b0,irq_software,3'b0};
    wire [31:0] eligible=mip&mie;
    assign irq_eligible=mie_global&&(|eligible);
    assign irq_cause=eligible[11]?32'h8000000b:eligible[3]?32'h80000003:32'h80000007;
    assign handler_pc=mtvec;
    assign return_pc=mepc;
    assign machine_cycle=mcycle;
    assign machine_retired=minstret;
    reg known;
    // Unimplemented HPM counters/event selectors are legal, read-only-zero
    // WARL registers (writes accepted and ignored), rather than missing CSRs.
    wire zero_warl=(access_addr==12'h310)||
        (access_addr>=12'hb03&&access_addr<=12'hb1f)||
        (access_addr>=12'hb83&&access_addr<=12'hb9f)||
        (access_addr>=12'h323&&access_addr<=12'h33f);
    reg standard_known;
    reg [31:0] standard_rdata,perf_read_leaf;
    always @* begin
        standard_known=1;standard_rdata=0;
        case(access_addr)
            12'h300:standard_rdata=32'h1800|{24'b0,mpie,3'b0,mie_global,3'b0};
            12'h301:standard_rdata=32'h40000100;
            12'h304:standard_rdata=mie;
            12'h305:standard_rdata=mtvec;
            12'h320:standard_rdata={29'b0,inhibit};
            12'h340:standard_rdata=mscratch;
            12'h341:standard_rdata=mepc;
            12'h342:standard_rdata=mcause;
            12'h343:standard_rdata=mtval;
            12'h344:standard_rdata=mip;
            12'hb00:standard_rdata=mcycle[31:0];
            12'hb80:standard_rdata=mcycle[63:32];
            12'hb02:standard_rdata=minstret[31:0];
            12'hb82:standard_rdata=minstret[63:32];
            12'hf11,12'hf12,12'hf13,12'hf14,12'hf15:standard_rdata=0;
            default:standard_known=1'b0;
        endcase
        known=standard_known||zero_warl||perf_known;
        // The performance bank is late. Keep it as a parallel OR input,
        // independent of the standard-register data selection tree.
        // A standard CSR still wins even for an arbitrary perf_known input.
        perf_read_leaf=0;
        if(!standard_known&&perf_known) perf_read_leaf=perf_rdata;
        access_rdata=standard_rdata|perf_read_leaf;
    end
    // Only standard CSRs can accept read-modify-write. Performance
    // values remain visible on access_rdata but cannot feed a legal write.
    // The core still applies the original permission/commit gates.
    assign access_modify_rdata=standard_rdata;
    assign access_error=access_valid&&(!known||(access_write&&access_addr[11:10]==2'b11));
    wire write_commit=access_valid&&access_write&&access_commit&&!access_error;
    // Direct architectural state: no visible-count adder or extra cycle.
    // Flags describe the current 16-bit chunks, so a late retire pulse only
    // qualifies local increment enables. No carry ripples between chunks.
    wire cycle_write_lo=write_commit&&(access_addr==12'hb00);
    wire cycle_write_hi=write_commit&&(access_addr==12'hb80);
    wire retired_write_lo=write_commit&&(access_addr==12'hb02);
    wire retired_write_hi=write_commit&&(access_addr==12'hb82);
    wire cycle_write_any=cycle_write_lo||cycle_write_hi;
    wire retired_write_any=retired_write_lo||retired_write_hi;
    wire cycle_tick=!inhibit[0];
    wire retired_tick=retire&&!inhibit[2];
    reg [2:0] cycle_full_q,retired_full_q;
    reg retired_near_q;
    wire retired_low_carry=retired_full_q[0]||(retire_second&&retired_near_q);
    wire [15:0] retired_low_plus_one=minstret[15:0]+16'd1;
    wire [15:0] retired_low_plus_two=minstret[15:0]+16'd2;
    generate for(genvar chunk=0;chunk<4;chunk=chunk+1) begin: counter_segment
        wire cycle_lower_full,retired_lower_full;
        wire cycle_write_here=(chunk<2)?cycle_write_lo:cycle_write_hi;
        wire retired_write_here=(chunk<2)?retired_write_lo:retired_write_hi;
        wire [15:0] write_word=access_wdata[(chunk%2)*16+:16];
        if(chunk==0) begin: low
            assign cycle_lower_full=1'b1;
            assign retired_lower_full=1'b1;
        end else begin: high
            assign cycle_lower_full=&cycle_full_q[chunk-1:0];
            if(chunk==1) assign retired_lower_full=retired_low_carry;
            else assign retired_lower_full=retired_low_carry&&(&retired_full_q[chunk-1:1]);
        end
        always @(posedge clk) begin
            if(rst) mcycle[chunk*16+:16]<=0;
            else if(cycle_write_any) begin
                // A half-write suppresses increment in BOTH halves; preserve
                // the untouched old half even if it would receive a carry.
                if(cycle_write_here) mcycle[chunk*16+:16]<=write_word;
            end else if(cycle_tick&&cycle_lower_full)
                mcycle[chunk*16+:16]<=mcycle[chunk*16+:16]+16'd1;
        end
        if(chunk==0) begin: retired_low
            always @(posedge clk) begin
                if(rst) begin
                    minstret[15:0]<=0;retired_near_q<=0;
                end else if(retired_write_any) begin
                    if(retired_write_here) begin
                        minstret[15:0]<=write_word;
                        retired_near_q<=write_word==16'hfffe;
                    end
                end else if(retired_tick) begin
                    minstret[15:0]<=retire_second?retired_low_plus_two:retired_low_plus_one;
                    retired_near_q<=retire_second?(minstret[15:0]==16'hfffc):(minstret[15:0]==16'hfffd);
                end
            end
        end else begin: retired_high
            always @(posedge clk) begin
                if(rst) minstret[chunk*16+:16]<=0;
                else if(retired_write_any) begin
                    if(retired_write_here) minstret[chunk*16+:16]<=write_word;
                end else if(retired_tick&&retired_lower_full)
                    minstret[chunk*16+:16]<=minstret[chunk*16+:16]+16'd1;
            end
        end
        if(chunk<3) begin: carry_flags
            always @(posedge clk) begin
                if(rst) cycle_full_q[chunk]<=0;
                else if(cycle_write_any) begin
                    if(cycle_write_here) cycle_full_q[chunk]<=write_word==16'hffff;
                end else if(cycle_tick&&cycle_lower_full)
                    cycle_full_q[chunk]<=mcycle[chunk*16+:16]==16'hfffe;
            end
            always @(posedge clk) begin
                if(rst) retired_full_q[chunk]<=0;
                else if(retired_write_any) begin
                    if(retired_write_here) retired_full_q[chunk]<=write_word==16'hffff;
                end else if(retired_tick&&retired_lower_full) begin
                    if(chunk==0)
                        retired_full_q[chunk]<=retire_second?(minstret[15:0]==16'hfffd):(minstret[15:0]==16'hfffe);
                    else retired_full_q[chunk]<=minstret[chunk*16+:16]==16'hfffe;
                end
            end
        end
    end endgenerate
`ifndef SYNTHESIS
    reg counter_flags_valid=0;
    integer csrseg_cycle_ticks=0,csrseg_retired_ticks=0,csrseg_dual_ticks=0,csrseg_half_writes=0;
    always @(posedge clk) begin
        if(rst) counter_flags_valid<=1;
        if(!rst&&counter_flags_valid) begin
            assert(cycle_full_q=={(&mcycle[47:32]),(&mcycle[31:16]),(&mcycle[15:0])})
                else $fatal(1,"CSRSEG_CYCLE_FLAGS");
            assert(retired_full_q=={(&minstret[47:32]),(&minstret[31:16]),(&minstret[15:0])})
                else $fatal(1,"CSRSEG_RETIRED_FLAGS");
            assert(retired_near_q==(minstret[15:0]==16'hfffe))
                else $fatal(1,"CSRSEG_NEAR_FLAG");
            if(cycle_tick&&!cycle_write_any) csrseg_cycle_ticks<=csrseg_cycle_ticks+1;
            if(retired_tick&&!retired_write_any) csrseg_retired_ticks<=csrseg_retired_ticks+1;
            if(retired_tick&&retire_second&&!retired_write_any) csrseg_dual_ticks<=csrseg_dual_ticks+1;
            if(cycle_write_any||retired_write_any) csrseg_half_writes<=csrseg_half_writes+1;
        end
    end
    final $display("CSRSEG_ASSERT_COVER cycle_ticks=%0d retired_ticks=%0d dual_ticks=%0d half_writes=%0d",csrseg_cycle_ticks,csrseg_retired_ticks,csrseg_dual_ticks,csrseg_half_writes);
`endif
    always @(posedge clk) begin
        if(rst) begin
            mie_global<=0;mpie<=0;mie<=0;mtvec<=0;mscratch<=0;
            mepc<=0;mcause<=0;mtval<=0;inhibit<=0;
        end else begin
            if(write_commit) begin
                case(access_addr)
                    12'h300:begin mie_global<=access_wdata[3];mpie<=access_wdata[7];end
                    12'h304:mie<=access_wdata&32'h888;
                    12'h305:mtvec<={access_wdata[31:2],2'b0};
                    12'h320:inhibit<=access_wdata[2:0]&3'b101;
                    12'h340:mscratch<=access_wdata;
                    12'h341:mepc<={access_wdata[31:2],2'b0};
                    12'h342:mcause<=access_wdata;
                    12'h343:mtval<=access_wdata;
                    default:begin end
                endcase
            end
            if(mret_commit) begin mie_global<=mpie;mpie<=1;end
            if(trap_enter) begin
                mepc<={trap_pc[31:2],2'b0};mcause<=trap_cause;mtval<=trap_tval;
                mpie<=mie_global;mie_global<=0;
            end
        end
    end
endmodule
