`timescale 1ns/1ps
`include "soc_config.vh"
module p1_soc (
    input wire clk, rst,
    output wire i_req_valid, input wire i_req_ready, output wire [31:0] i_req_addr,
    input wire i_rsp_valid, output wire i_rsp_ready,
    input wire [31:0] i_rsp_data, input wire i_rsp_error,
    output wire d_req_valid, input wire d_req_ready,
    output wire [31:0] d_req_addr, output wire d_req_write,
    output wire [3:0] d_req_be, output wire [31:0] d_req_wdata,
    input wire d_rsp_valid, output wire d_rsp_ready,
    input wire [31:0] d_rsp_data, input wire d_rsp_error,
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
    output wire [63:0] count_cycle, count_retired, count_if_wait, count_data_wait,
    output wire [63:0] count_load_use, count_redirect, count_reads, count_writes
);
    wire cqv,cqr,cqw,crv,crr,cre;
    wire [31:0] cqa,cqd,crd;
    wire [3:0] cqb;
    assign mon_d_req_valid=cqv;
    assign mon_d_req_ready=cqr;
    assign mon_d_req_write=cqw;
    assign mon_d_req_addr=cqa;
    assign mon_d_req_wdata=cqd;
    assign mon_d_req_be=cqb;
    assign mon_d_rsp_valid=crv;
    assign mon_d_rsp_ready=crr;
    assign mon_d_rsp_error=cre;
    assign mon_d_rsp_data=crd;
    wire pqv,pqr,prv,prr,pre;
    wire [31:0] prd;
    reg pending, route_periph;
    wire select_periph = ((cqa & 32'hfffff000) == `UART_BASE) ||
                         ((cqa & 32'hfffff000) == `GPIO_BASE) ||
                         ((cqa & 32'hfffff000) == `TIMER_BASE);
    wire available = !pending || (crv && crr);
    assign pqv = cqv && select_periph && available;
    assign d_req_valid = cqv && !select_periph && available;
    assign cqr = available && (select_periph ? pqr : d_req_ready);
    assign d_req_addr=cqa;
    assign d_req_write=cqw;
    assign d_req_be=cqb;
    assign d_req_wdata=cqd;
    assign crv=pending && (route_periph ? prv : d_rsp_valid);
    assign crd=route_periph ? prd : d_rsp_data;
    assign cre=route_periph ? pre : d_rsp_error;
    assign prr=pending && route_periph && crr;
    assign d_rsp_ready=pending && !route_periph && crr;
    always @(posedge clk) begin
        if(rst) begin pending<=0; route_periph<=0; end
        else begin
            if(crv && crr) pending<=0;
            if(cqv && cqr) begin pending<=1; route_periph<=select_periph; end
        end
    end
    p1_peripherals #(.UART_BASE(`UART_BASE),.GPIO_BASE(`GPIO_BASE),
        .TIMER_BASE(`TIMER_BASE),.UART_DIVISOR(`UART_DIVISOR)) peripherals (
        .clk(clk),.rst(rst),.req_valid(pqv),.req_ready(pqr),.req_addr(cqa),
        .req_write(cqw),.req_be(cqb),.req_wdata(cqd),
        .rsp_valid(prv),.rsp_ready(prr),.rsp_rdata(prd),.rsp_error(pre),
        .uart_tx(uart_tx),.gpio_out(gpio_out)
    );
    p1_core #(.RESET_PC(`RAM_BASE)) core (
        .clk(clk),.rst(rst),
        .i_req_valid(i_req_valid),.i_req_ready(i_req_ready),.i_req_addr(i_req_addr),
        .i_rsp_valid(i_rsp_valid),.i_rsp_ready(i_rsp_ready),.i_rsp_data(i_rsp_data),.i_rsp_error(i_rsp_error),
        .d_req_valid(cqv),.d_req_ready(cqr),.d_req_addr(cqa),.d_req_write(cqw),.d_req_be(cqb),.d_req_wdata(cqd),
        .d_rsp_valid(crv),.d_rsp_ready(crr),.d_rsp_data(crd),.d_rsp_error(cre),
        .trace_valid(trace_valid),.trace_trap(trace_trap),.trace_pc(trace_pc),.trace_insn(trace_insn),
        .trace_rd(trace_rd),.trace_wdata(trace_wdata),.trace_cause(trace_cause),.trace_tval(trace_tval),
        .trace_mem_valid(trace_mem_valid),.trace_mem_write(trace_mem_write),.trace_mem_addr(trace_mem_addr),
        .trace_mem_wdata(trace_mem_wdata),.trace_mem_rdata(trace_mem_rdata),.trace_mem_be(trace_mem_be),
        .halted(halted),.count_cycle(count_cycle),.count_retired(count_retired),.count_if_wait(count_if_wait),
        .count_data_wait(count_data_wait),.count_load_use(count_load_use),.count_redirect(count_redirect),
        .count_reads(count_reads),.count_writes(count_writes)
    );
endmodule
