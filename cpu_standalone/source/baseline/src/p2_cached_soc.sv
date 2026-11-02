`timescale 1ns/1ps
`include "soc_config.vh"
`include "p4_regs.vh"
// Real two-way I/D caches and one shared block-command/burst data interface.
module p2_cached_soc #(
    parameter MACHINE_MODE=1,BP_ENABLED=1,LEGACY_CORE=0,CACHE_ENABLED=1,CACHE_BYTES=8192,LINE_BYTES=32,FIFO_DEPTH=2,RESPONSE_BYPASS=0,BTB_ENTRIES=128,BHT_ENTRIES=256,RAS_DEPTH=4,EARLY_LSU=0,HW_MUL=0,ACCEL_ENABLE=0,
    parameter [31:0] ACCEL_BASE=`P4_ACCEL_BASE,
    parameter integer DC_LOAD_HIT_TURNOVER=0
)(
    input wire clk,rst,run_stop,
    input wire irq_software_in,irq_timer_in,irq_external_in,
    input wire clean_valid,output wire clean_ready,clean_done,clean_error,
    output wire fatal,data_idle,
    output wire [63:0] count_i_hit,count_i_miss,count_d_hit,count_d_miss,count_d_writeback,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire [31:0] cmd_addr,
    output wire [7:0] cmd_len,
    output wire w_valid,
    input wire w_ready,
    output wire [31:0] w_data,
    output wire [3:0] w_be,
    output wire w_last,
    input wire r_valid,
    output wire r_ready,
    input wire [31:0] r_data,
    input wire r_error,
    input wire r_last,
    output wire trace_irq_valid,output wire [31:0] trace_irq_pc,trace_irq_cause,
    output wire trace_csr_valid,trace_csr_read,trace_csr_write,
    output wire [11:0] trace_csr_addr,output wire [31:0] trace_csr_rdata,trace_csr_wdata,
    output wire [63:0] machine_cycle,machine_retired,
    output wire trace_valid, trace_trap,
    output wire trace_valid1,
    output wire [31:0] trace_pc1,trace_insn1,
    output wire [4:0] trace_rd1,
    output wire [31:0] trace_wdata1,
    output wire [31:0] trace_pc, trace_insn,
    output wire [4:0] trace_rd, output wire [31:0] trace_wdata,
    output wire [31:0] trace_cause, trace_tval,
    output wire trace_mem_valid, trace_mem_write,
    output wire [31:0] trace_mem_addr, trace_mem_wdata, trace_mem_rdata,
    output wire [3:0] trace_mem_be,
    output wire halted, uart_tx, output wire [31:0] gpio_out,
    output wire mon_d_req_valid,mon_d_req_ready,mon_d_req_write,
    output wire [31:0] mon_d_req_addr,mon_d_req_wdata,
    output wire [3:0] mon_d_req_be,
    output wire mon_d_rsp_valid,mon_d_rsp_ready,mon_d_rsp_error,
    output wire [31:0] mon_d_rsp_data,
    output wire mon_p4_enabled,mon_p4_busy,mon_p4_result_valid,mon_p4_pending,mon_p4_enable,mon_p4_irq,
    output wire mon_p4_start,mon_p4_complete,mon_p4_soft_reset,mon_p4_rsp_valid,
    output wire [31:0] mon_p4_generation,mon_p4_submit_id,mon_p4_done_id,mon_p4_result,mon_p4_length,
    output wire [63:0] count_cycle, count_retired, count_if_wait, count_data_wait,
    output wire [63:0] count_load_use, count_redirect, count_reads, count_writes
);
    wire iqv,iqr,irv,irr,ire,irhv;wire [31:0] iqa,ird,ird_hi; wire [6:0] ird_pre,ird_pre_hi;
    wire dqv,dqr,dqw,drv,drr,dre;wire [31:0] dqa,dqd,drd;wire [3:0] dqb;
    wire cqv,cqr,crv,crr,cre;wire [31:0] crd;
    wire fi_valid,fi_ready,fi_done,fi_error;
    wire imv,imr,imd,ime,dmv,dmr,dmd,dme,ifatal,dfatal;
    wire [63:0] unused_i_writeback;
    reg route_pending,route_exit,exit_error;
    wire select_exit=(dqa==`EXIT_BASE);
    wire available=!route_pending||(drv&&drr);
    assign cqv=dqv&&!select_exit&&available;
    assign dqr=available&&(select_exit?1'b1:cqr);
    assign drv=route_pending&&(route_exit?1'b1:crv);
    assign drd=route_exit?32'b0:crd;
    assign dre=route_exit?exit_error:cre;
    assign crr=route_pending&&!route_exit&&drr;
    // EXIT is a real, acknowledged completion mailbox, never cached.
    always @(posedge clk) begin
        if(rst) begin route_pending<=0;route_exit<=0;exit_error<=0;end
        else begin
            if(drv&&drr) route_pending<=0;
            if(dqv&&dqr) begin
                route_pending<=1;route_exit<=select_exit;
                exit_error<=!dqw||(dqb!=4'hf);
            end
        end
    end
    localparam [2:0] IDLE=0,DC_REQ=1,DC_WAIT=2,IC_REQ=3,IC_WAIT=4,DONE=5;
    reg [2:0] maintenance;
    reg debug_clean,maintenance_error;
    assign clean_ready=maintenance==IDLE&&run_stop&&data_idle&&!fatal;
    assign fi_ready=maintenance==IDLE&&!clean_valid&&!fatal;
    assign clean_done=maintenance==DONE&&debug_clean;
    assign clean_error=maintenance_error;
    assign fi_done=maintenance==DONE&&!debug_clean;
    assign fi_error=maintenance_error;
    assign dmv=maintenance==DC_REQ;
    assign imv=maintenance==IC_REQ;
    assign fatal=ifatal||dfatal||maintenance_error;
    always @(posedge clk) begin
        if(rst) begin maintenance<=IDLE;debug_clean<=0;maintenance_error<=0;end
        else case(maintenance)
            IDLE:begin
                if(clean_valid&&clean_ready) begin maintenance<=DC_REQ;debug_clean<=1;end
                else if(fi_valid&&fi_ready) begin maintenance<=DC_REQ;debug_clean<=0;end
            end
            DC_REQ:if(dmr) maintenance<=DC_WAIT;
            DC_WAIT:if(dmd) begin
                maintenance_error<=dme;
                maintenance<=dme||debug_clean?DONE:IC_REQ;
            end
            IC_REQ:if(imr) maintenance<=IC_WAIT;
            IC_WAIT:if(imd) begin maintenance_error<=ime;maintenance<=DONE;end
            DONE:maintenance<=IDLE;
            default:maintenance<=IDLE;
        endcase
    end
    p2_soc #(.MACHINE_MODE(MACHINE_MODE),.BP_ENABLED(BP_ENABLED),.LEGACY_CORE(LEGACY_CORE),.FIFO_DEPTH(FIFO_DEPTH),.RESPONSE_BYPASS(RESPONSE_BYPASS),.BTB_ENTRIES(BTB_ENTRIES),.BHT_ENTRIES(BHT_ENTRIES),.RAS_DEPTH(RAS_DEPTH),.EARLY_LSU(EARLY_LSU),.HW_MUL(HW_MUL),.ACCEL_ENABLE(ACCEL_ENABLE),.IFETCH_DUAL_WORDS(CACHE_ENABLED!=0),.IFETCH_LINE_BYTES(LINE_BYTES),.IFETCH_PREDECODE(CACHE_ENABLED!=0),.ACCEL_BASE(ACCEL_BASE)) soc(
        .clk(clk),.rst(rst),.run_stop(run_stop),.fatal_error(fatal),.data_idle(data_idle),
        .perf_cache_flat({count_d_writeback,count_d_miss,count_d_hit,count_i_miss,count_i_hit}),
        .irq_software_in(irq_software_in),.irq_timer_in(irq_timer_in),.irq_external_in(irq_external_in),
        .fence_i_valid(fi_valid),.fence_i_ready(fi_ready),.fence_i_done(fi_done),.fence_i_error(fi_error),
        .i_req_valid(iqv),.i_req_ready(iqr),.i_req_addr(iqa),
        .i_rsp_valid(irv),.i_rsp_ready(irr),.i_rsp_data(ird),.i_rsp_error(ire),
        .i_rsp_data_hi(ird_hi),.i_rsp_hi_valid(irhv),
        .i_rsp_predecode(ird_pre),.i_rsp_predecode_hi(ird_pre_hi),
        .d_req_valid(dqv),.d_req_ready(dqr),.d_req_addr(dqa),.d_req_write(dqw),.d_req_be(dqb),.d_req_wdata(dqd),
        .d_rsp_valid(drv),.d_rsp_ready(drr),.d_rsp_data(drd),.d_rsp_error(dre),
        .trace_irq_valid(trace_irq_valid),
        .trace_irq_pc(trace_irq_pc),
        .trace_irq_cause(trace_irq_cause),
        .trace_csr_valid(trace_csr_valid),
        .trace_csr_read(trace_csr_read),
        .trace_csr_write(trace_csr_write),
        .trace_csr_addr(trace_csr_addr),
        .trace_csr_rdata(trace_csr_rdata),
        .trace_csr_wdata(trace_csr_wdata),
        .machine_cycle(machine_cycle),
        .machine_retired(machine_retired),
        .trace_valid(trace_valid),
        .trace_valid1(trace_valid1),.trace_pc1(trace_pc1),.trace_insn1(trace_insn1),
        .trace_rd1(trace_rd1),.trace_wdata1(trace_wdata1),
        .trace_trap(trace_trap),
        .trace_pc(trace_pc),
        .trace_insn(trace_insn),
        .trace_rd(trace_rd),
        .trace_wdata(trace_wdata),
        .trace_cause(trace_cause),
        .trace_tval(trace_tval),
        .trace_mem_valid(trace_mem_valid),
        .trace_mem_write(trace_mem_write),
        .trace_mem_addr(trace_mem_addr),
        .trace_mem_wdata(trace_mem_wdata),
        .trace_mem_rdata(trace_mem_rdata),
        .trace_mem_be(trace_mem_be),
        .halted(halted),
        .uart_tx(uart_tx),
        .gpio_out(gpio_out),
        .mon_d_req_valid(mon_d_req_valid),
        .mon_d_req_ready(mon_d_req_ready),
        .mon_d_req_write(mon_d_req_write),
        .mon_d_req_addr(mon_d_req_addr),
        .mon_d_req_wdata(mon_d_req_wdata),
        .mon_d_req_be(mon_d_req_be),
        .mon_d_rsp_valid(mon_d_rsp_valid),
        .mon_d_rsp_ready(mon_d_rsp_ready),
        .mon_d_rsp_error(mon_d_rsp_error),
        .mon_d_rsp_data(mon_d_rsp_data),
        .mon_p4_enabled(mon_p4_enabled),.mon_p4_busy(mon_p4_busy),.mon_p4_result_valid(mon_p4_result_valid),
        .mon_p4_pending(mon_p4_pending),.mon_p4_enable(mon_p4_enable),.mon_p4_irq(mon_p4_irq),
        .mon_p4_start(mon_p4_start),.mon_p4_complete(mon_p4_complete),.mon_p4_soft_reset(mon_p4_soft_reset),
        .mon_p4_rsp_valid(mon_p4_rsp_valid),.mon_p4_generation(mon_p4_generation),
        .mon_p4_submit_id(mon_p4_submit_id),.mon_p4_done_id(mon_p4_done_id),
        .mon_p4_result(mon_p4_result),.mon_p4_length(mon_p4_length),
        .count_cycle(count_cycle),
        .count_retired(count_retired),
        .count_if_wait(count_if_wait),
        .count_data_wait(count_data_wait),
        .count_load_use(count_load_use),
        .count_redirect(count_redirect),
        .count_reads(count_reads),
        .count_writes(count_writes)
    );
    wire a_cmd_valid;
    wire a_cmd_ready;
    wire a_cmd_write;
    wire [31:0] a_cmd_addr;
    wire [7:0] a_cmd_len;
    wire a_w_valid;
    wire a_w_ready;
    wire [31:0] a_w_data;
    wire [3:0] a_w_be;
    wire a_w_last;
    wire a_r_valid;
    wire a_r_ready;
    wire [31:0] a_r_data;
    wire a_r_error;
    wire a_r_last;
    wire b_cmd_valid;
    wire b_cmd_ready;
    wire b_cmd_write;
    wire [31:0] b_cmd_addr;
    wire [7:0] b_cmd_len;
    wire b_w_valid;
    wire b_w_ready;
    wire [31:0] b_w_data;
    wire [3:0] b_w_be;
    wire b_w_last;
    wire b_r_valid;
    wire b_r_ready;
    wire [31:0] b_r_data;
    wire b_r_error;
    wire b_r_last;
    p2_cache #(.READ_ONLY(1),.CACHE_BYTES(CACHE_BYTES),.LINE_BYTES(LINE_BYTES),
        .RAM_BASE(`RAM_BASE),.RAM_BYTES(`RAM_BYTES),.ENABLED(CACHE_ENABLED),.STORE_PREDECODE(CACHE_ENABLED!=0)) icache(
        .clk(clk),.rst(rst),
        .req_valid(iqv),.req_ready(iqr),.req_addr(iqa),.req_write(1'b0),.req_be(4'hf),.req_wdata(32'b0),
        .rsp_valid(irv),.rsp_ready(irr),.rsp_rdata(ird),.rsp_error(ire),
        .rsp_data_hi(ird_hi),.rsp_hi_valid(irhv),
        .rsp_predecode(ird_pre),.rsp_predecode_hi(ird_pre_hi),
        .maint_valid(imv),.maint_ready(imr),.maint_clean(1'b0),.maint_invalidate(1'b1),
        .maint_done(imd),.maint_error(ime),.fatal(ifatal),
        .count_hit(count_i_hit),.count_miss(count_i_miss),.count_writeback(unused_i_writeback),
        .cmd_valid(a_cmd_valid),
        .cmd_ready(a_cmd_ready),
        .cmd_write(a_cmd_write),
        .cmd_addr(a_cmd_addr),
        .cmd_len(a_cmd_len),
        .w_valid(a_w_valid),
        .w_ready(a_w_ready),
        .w_data(a_w_data),
        .w_be(a_w_be),
        .w_last(a_w_last),
        .r_valid(a_r_valid),
        .r_ready(a_r_ready),
        .r_data(a_r_data),
        .r_error(a_r_error),
        .r_last(a_r_last)
    );
    p2_cache #(.READ_ONLY(0),.CACHE_BYTES(CACHE_BYTES),.LINE_BYTES(LINE_BYTES),
        .RAM_BASE(`RAM_BASE),.RAM_BYTES(`RAM_BYTES),.ENABLED(CACHE_ENABLED),
        .DC_LOAD_HIT_TURNOVER(DC_LOAD_HIT_TURNOVER)) dcache(
        .clk(clk),.rst(rst),
        .req_valid(cqv),.req_ready(cqr),.req_addr(dqa),.req_write(dqw),.req_be(dqb),.req_wdata(dqd),
        .rsp_valid(crv),.rsp_ready(crr),.rsp_rdata(crd),.rsp_error(cre),
        .maint_valid(dmv),.maint_ready(dmr),.maint_clean(1'b1),.maint_invalidate(1'b0),
        .maint_done(dmd),.maint_error(dme),.fatal(dfatal),
        .count_hit(count_d_hit),.count_miss(count_d_miss),.count_writeback(count_d_writeback),
        .cmd_valid(b_cmd_valid),
        .cmd_ready(b_cmd_ready),
        .cmd_write(b_cmd_write),
        .cmd_addr(b_cmd_addr),
        .cmd_len(b_cmd_len),
        .w_valid(b_w_valid),
        .w_ready(b_w_ready),
        .w_data(b_w_data),
        .w_be(b_w_be),
        .w_last(b_w_last),
        .r_valid(b_r_valid),
        .r_ready(b_r_ready),
        .r_data(b_r_data),
        .r_error(b_r_error),
        .r_last(b_r_last)
    );
    p2_burst_arbiter2 arbiter(.clk(clk),.rst(rst),
        .a_cmd_valid(a_cmd_valid),
        .a_cmd_ready(a_cmd_ready),
        .a_cmd_write(a_cmd_write),
        .a_cmd_addr(a_cmd_addr),
        .a_cmd_len(a_cmd_len),
        .a_w_valid(a_w_valid),
        .a_w_ready(a_w_ready),
        .a_w_data(a_w_data),
        .a_w_be(a_w_be),
        .a_w_last(a_w_last),
        .a_r_valid(a_r_valid),
        .a_r_ready(a_r_ready),
        .a_r_data(a_r_data),
        .a_r_error(a_r_error),
        .a_r_last(a_r_last),
        .b_cmd_valid(b_cmd_valid),
        .b_cmd_ready(b_cmd_ready),
        .b_cmd_write(b_cmd_write),
        .b_cmd_addr(b_cmd_addr),
        .b_cmd_len(b_cmd_len),
        .b_w_valid(b_w_valid),
        .b_w_ready(b_w_ready),
        .b_w_data(b_w_data),
        .b_w_be(b_w_be),
        .b_w_last(b_w_last),
        .b_r_valid(b_r_valid),
        .b_r_ready(b_r_ready),
        .b_r_data(b_r_data),
        .b_r_error(b_r_error),
        .b_r_last(b_r_last),
        .m_cmd_valid(cmd_valid),
        .m_cmd_ready(cmd_ready),
        .m_cmd_write(cmd_write),
        .m_cmd_addr(cmd_addr),
        .m_cmd_len(cmd_len),
        .m_w_valid(w_valid),
        .m_w_ready(w_ready),
        .m_w_data(w_data),
        .m_w_be(w_be),
        .m_w_last(w_last),
        .m_r_valid(r_valid),
        .m_r_ready(r_ready),
        .m_r_data(r_data),
        .m_r_error(r_error),
        .m_r_last(r_last)
    );
endmodule
