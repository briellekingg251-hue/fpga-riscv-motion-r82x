`timescale 1ns/1ps
`include "soc_config.vh"
`include "p4_regs.vh"
module p2_sim_top #(
    parameter MACHINE_MODE=1,BP_ENABLED=1,LEGACY_CORE=0,CACHE_ENABLED=1,CACHE_BYTES=8192,LINE_BYTES=32,FIFO_DEPTH=2,RESPONSE_BYPASS=0,BTB_ENTRIES=64,BHT_ENTRIES=256,EARLY_LSU=0,HW_MUL=0,ACCEL_ENABLE=0,
    parameter [31:0] ACCEL_BASE=`P4_ACCEL_BASE,
    parameter integer DC_LOAD_HIT_TURNOVER=0
)(
    input wire clk,rst,run_stop,backend_cmd_allow,backend_w_allow,backend_r_allow,
    input wire irq_software_in,irq_timer_in,irq_external_in,
    input wire clean_valid,dump_ram,output wire clean_ready,clean_done,clean_error,
    output wire fatal,data_idle,fetch_idle,
    output wire [1535:0] perf_values,
    output wire [63:0] count_i_hit,count_i_miss,count_d_hit,count_d_miss,count_d_writeback,
    output wire mon_cmd_valid,
    output wire mon_cmd_ready,
    output wire mon_cmd_write,
    output wire [31:0] mon_cmd_addr,
    output wire [7:0] mon_cmd_len,
    output wire mon_w_valid,
    output wire mon_w_ready,
    output wire [31:0] mon_w_data,
    output wire [3:0] mon_w_be,
    output wire mon_w_last,
    output wire mon_r_valid,
    output wire mon_r_ready,
    output wire [31:0] mon_r_data,
    output wire mon_r_error,
    output wire mon_r_last,
    output wire trace_irq_valid,output wire [31:0] trace_irq_pc,trace_irq_cause,
    output wire trace_csr_valid,trace_csr_read,trace_csr_write,
    output wire [11:0] trace_csr_addr,output wire [31:0] trace_csr_rdata,trace_csr_wdata,
    output wire [63:0] machine_cycle,machine_retired,
    output wire trace_valid, trace_trap,
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
    // Observation only: IDLE I$ (maint_ready), no held frontend request,
    // and no unconsumed response. With run_stop asserted, no new offer is
    // created after the existing held request drains.
    assign fetch_idle=!system_soc.iqv && system_soc.imr && !system_soc.irv;
    generate if(LEGACY_CORE==0) begin: perf_observation
        assign perf_values=system_soc.soc.improved.core.unused_perf_values;
    end else begin: no_perf
        assign perf_values=0;
    end endgenerate
    p2_cached_soc #(.MACHINE_MODE(MACHINE_MODE),.BP_ENABLED(BP_ENABLED),.LEGACY_CORE(LEGACY_CORE),.CACHE_ENABLED(CACHE_ENABLED),
        .CACHE_BYTES(CACHE_BYTES),.LINE_BYTES(LINE_BYTES),.FIFO_DEPTH(FIFO_DEPTH),.RESPONSE_BYPASS(RESPONSE_BYPASS),.BTB_ENTRIES(BTB_ENTRIES),.BHT_ENTRIES(BHT_ENTRIES),.EARLY_LSU(EARLY_LSU),.HW_MUL(HW_MUL),.ACCEL_ENABLE(ACCEL_ENABLE),.ACCEL_BASE(ACCEL_BASE),
        .DC_LOAD_HIT_TURNOVER(DC_LOAD_HIT_TURNOVER)) system_soc(
        .clk(clk),
        .rst(rst),
        .run_stop(run_stop),
        .irq_software_in(irq_software_in),
        .irq_timer_in(irq_timer_in),
        .irq_external_in(irq_external_in),
        .clean_valid(clean_valid),
        .clean_ready(clean_ready),
        .clean_done(clean_done),
        .clean_error(clean_error),
        .fatal(fatal),
        .data_idle(data_idle),
        .count_i_hit(count_i_hit),
        .count_i_miss(count_i_miss),
        .count_d_hit(count_d_hit),
        .count_d_miss(count_d_miss),
        .count_d_writeback(count_d_writeback),
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
        .count_writes(count_writes),
        .cmd_valid(mon_cmd_valid),
        .cmd_ready(mon_cmd_ready),
        .cmd_write(mon_cmd_write),
        .cmd_addr(mon_cmd_addr),
        .cmd_len(mon_cmd_len),
        .w_valid(mon_w_valid),
        .w_ready(mon_w_ready),
        .w_data(mon_w_data),
        .w_be(mon_w_be),
        .w_last(mon_w_last),
        .r_valid(mon_r_valid),
        .r_ready(mon_r_ready),
        .r_data(mon_r_data),
        .r_error(mon_r_error),
        .r_last(mon_r_last)
    );
    wire s_cmd_valid;
    wire s_cmd_ready;
    wire s_cmd_write;
    wire [31:0] s_cmd_addr;
    wire [7:0] s_cmd_len;
    wire s_w_valid;
    wire s_w_ready;
    wire [31:0] s_w_data;
    wire [3:0] s_w_be;
    wire s_w_last;
    wire s_r_valid;
    wire s_r_ready;
    wire [31:0] s_r_data;
    wire s_r_error;
    wire s_r_last;
    // Random independent bubbles, with a visible offer latched until accepted.
    reg command_held,write_held,read_held;
    wire ca=backend_cmd_allow||command_held;
    wire wa=backend_w_allow||write_held;
    wire ra=backend_r_allow||read_held;
    always @(posedge clk) begin
        if(rst) begin command_held<=0;write_held<=0;read_held<=0;end
        else begin
            command_held<=s_cmd_valid&&!s_cmd_ready;
            write_held<=s_w_valid&&!s_w_ready;
            read_held<=mon_r_valid&&!mon_r_ready;
        end
    end
    assign s_cmd_valid=mon_cmd_valid&&ca;
    assign mon_cmd_ready=s_cmd_ready&&ca;
    assign s_cmd_write=mon_cmd_write;
    assign s_cmd_addr=mon_cmd_addr;
    assign s_cmd_len=mon_cmd_len;
    assign s_w_valid=mon_w_valid&&wa;
    assign mon_w_ready=s_w_ready&&wa;
    assign s_w_data=mon_w_data;assign s_w_be=mon_w_be;assign s_w_last=mon_w_last;
    assign mon_r_valid=s_r_valid&&ra;
    assign s_r_ready=mon_r_ready&&ra;
    assign mon_r_data=s_r_data;assign mon_r_error=s_r_error;assign mon_r_last=s_r_last;
    p2_burst_sram #(.RAM_BASE(`RAM_BASE),.RAM_BYTES(`RAM_BYTES)) memory(.clk(clk),.rst(rst),
        .cmd_valid(s_cmd_valid),
        .cmd_ready(s_cmd_ready),
        .cmd_write(s_cmd_write),
        .cmd_addr(s_cmd_addr),
        .cmd_len(s_cmd_len),
        .w_valid(s_w_valid),
        .w_ready(s_w_ready),
        .w_data(s_w_data),
        .w_be(s_w_be),
        .w_last(s_w_last),
        .r_valid(s_r_valid),
        .r_ready(s_r_ready),
        .r_data(s_r_data),
        .r_error(s_r_error),
        .r_last(s_r_last)
    );
    string init_path,dump_path;
    reg clean_seen=0;
    initial begin
        if(!$value$plusargs("INIT_HEX=%s",init_path)) $fatal(1,"INIT_HEX required");
        if(!$value$plusargs("DUMP_HEX=%s",dump_path)) $fatal(1,"DUMP_HEX required");
        $readmemh(init_path,memory.mem);
    end
    always @(posedge clk) begin
        if(rst) clean_seen<=0;
        else begin
            if(clean_done&&!clean_error) clean_seen<=1;
            if(!run_stop) clean_seen<=0;
            if(dump_ram) begin
                assert(clean_seen&&run_stop&&data_idle&&!fatal);
                $writememh(dump_path,memory.mem);
            end
        end
    end
endmodule
