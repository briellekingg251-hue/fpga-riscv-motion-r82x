`timescale 1ns/1ps
`include "soc_config.vh"
`include "p4_regs.vh"
module p2_soc #(parameter MACHINE_MODE=0,BP_ENABLED=0,LEGACY_CORE=0,FIFO_DEPTH=2,RESPONSE_BYPASS=0,BTB_ENTRIES=64,BHT_ENTRIES=256,RAS_DEPTH=0,EARLY_LSU=0,HW_MUL=0,ACCEL_ENABLE=0,IFETCH_DUAL_WORDS=1,IFETCH_LINE_BYTES=32,IFETCH_PREDECODE=0,parameter [31:0] ACCEL_BASE=`P4_ACCEL_BASE)(
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
    input wire irq_software_in,irq_timer_in,irq_external_in,fatal_error,run_stop,
    output wire data_idle,
    output wire [63:0] machine_cycle,machine_retired,
    output wire fence_i_valid,input wire fence_i_ready,fence_i_done,fence_i_error,
    output wire trace_irq_valid,output wire [31:0] trace_irq_pc,trace_irq_cause,
    output wire trace_csr_valid,trace_csr_read,trace_csr_write,
    output wire [11:0] trace_csr_addr,output wire [31:0] trace_csr_rdata,trace_csr_wdata,
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
    wire aqv,aqr,arv,arr,are,accel_irq;
    wire [31:0] ard;
    localparam [1:0] ROUTE_RAM=2'd0,ROUTE_PERIPH=2'd1,ROUTE_ACCEL=2'd2;
    reg pending,terminal_response;
    // One-entry MMIO request register. The existing route remains associated
    // with the CPU transaction from acceptance through its real response.
    reg mmio_valid;
    reg [31:0] mmio_addr_q,mmio_wdata_q;
    reg [3:0] mmio_be_q;
    reg mmio_write_q;
    reg [1:0] route;
    wire select_periph = ((cqa & 32'hfffff000) == `UART_BASE) ||
                         ((cqa & 32'hfffff000) == `GPIO_BASE) ||
                         ((cqa & 32'hfffff000) == `TIMER_BASE);
    wire select_accel = (ACCEL_ENABLE != 0) &&
                        ((cqa & 32'hfffff000) == ACCEL_BASE);
    wire available = !pending || (crv && crr);
    wire select_mmio=select_periph||select_accel;
    wire mmio_target_ready=(route==ROUTE_PERIPH)?pqr:aqr;
    assign pqv = mmio_valid && (route==ROUTE_PERIPH);
    assign aqv = mmio_valid && (route==ROUTE_ACCEL);
    assign d_req_valid = cqv && !select_periph && !select_accel && available;
    assign cqr = available && (select_mmio ? !mmio_valid : d_req_ready);
    assign d_req_addr=cqa;
    assign d_req_write=cqw;
    assign d_req_be=cqb;
    assign d_req_wdata=cqd;
    // Every response uses the target latched at its request handshake. The
    // current CPU request may already name another device during turnover.
    assign crv=pending && ((route==ROUTE_PERIPH) ? prv : ((route==ROUTE_ACCEL) ? arv : d_rsp_valid));
    assign crd=(route==ROUTE_PERIPH) ? prd : ((route==ROUTE_ACCEL) ? ard : d_rsp_data);
    assign cre=(route==ROUTE_PERIPH) ? pre : ((route==ROUTE_ACCEL) ? are : d_rsp_error);
    assign prr=pending && (route==ROUTE_PERIPH) && crr;
    assign arr=pending && (route==ROUTE_ACCEL) && crr;
    assign d_rsp_ready=pending && (route==ROUTE_RAM) && crr;
    always @(posedge clk) begin
        if(rst) begin pending<=0; route<=ROUTE_RAM;terminal_response<=0;end
        else begin
            if(crv && crr) pending<=0;
            if(cqv && cqr) begin
                pending<=1;route<=select_periph ? ROUTE_PERIPH : (select_accel ? ROUTE_ACCEL : ROUTE_RAM);
                terminal_response<=(cqa==`EXIT_BASE)&&cqw&&(cqb==4'hf);
            end
        end
    end
    // Do not cancel an accepted access for IRQ/stop/redirect. The core waits
    // for the selected peripheral response, so its precise retirement and
    // terminal ordering remain governed by the existing pending/route state.
    always @(posedge clk) begin
        if(rst) mmio_valid<=0;
        else begin
            if(mmio_valid&&mmio_target_ready) mmio_valid<=0;
            if(cqv&&cqr&&select_mmio) mmio_valid<=1;
            // Any accepted MMIO request implies !mmio_valid. Empty payload
            // may be overwritten; occupied payload remains stable even if
            // its device has not yet accepted it.
            if(!mmio_valid) begin
                mmio_addr_q<=cqa;mmio_wdata_q<=cqd;
                mmio_be_q<=cqb;mmio_write_q<=cqw;
            end
        end
    end
`ifndef SYNTHESIS
    reg [68:0] mmio_payload_reference;
    integer mmio_payload_checks=0;
    always @(posedge clk) begin
        if(!rst&&cqv&&cqr&&select_mmio) begin
            assert(!mmio_valid) else $fatal(1,"MMIO_PAYLOAD_OCCUPIED_ACCEPT");
            mmio_payload_reference<={cqa,cqd,cqb,cqw};
        end
        if(!rst&&mmio_valid) begin
            mmio_payload_checks=mmio_payload_checks+1;
            assert({mmio_addr_q,mmio_wdata_q,mmio_be_q,mmio_write_q}===mmio_payload_reference)
                else $fatal(1,"MMIO_PAYLOAD_GATE_MITER");
        end
    end
    final $display("MMIO_PAYLOAD_COVER occupied_checks=%0d",mmio_payload_checks);
`endif
    assign mon_p4_enabled = ACCEL_ENABLE != 0;
    assign mon_p4_irq = accel_irq;
    assign mon_p4_rsp_valid = arv;
    generate if(ACCEL_ENABLE==2) begin: pose_accelerator
        p5_pose_mmio #(.BASE_ADDR(ACCEL_BASE)) pose (
            .clk(clk),.rst(rst),.req_valid(aqv),.req_ready(aqr),.req_addr(mmio_addr_q),
            .req_write(mmio_write_q),.req_be(mmio_be_q),.req_wdata(mmio_wdata_q),
            .rsp_valid(arv),.rsp_ready(arr),.rsp_rdata(ard),.rsp_error(are),.irq_o(accel_irq),
            .busy_o(mon_p4_busy),.result_valid_o(mon_p4_result_valid),.pending_o(mon_p4_pending),
            .intr_enable_o(mon_p4_enable),.start_o(mon_p4_start),.complete_o(mon_p4_complete),
            .soft_reset_o(mon_p4_soft_reset),.generation_o(mon_p4_generation),
            .submit_id_o(mon_p4_submit_id),.done_id_o(mon_p4_done_id),
            .result_o(mon_p4_result),.length_o(mon_p4_length)
        );
    end else if(ACCEL_ENABLE!=0) begin: accelerator
        p4_dot_mmio #(.BASE_ADDR(ACCEL_BASE)) dot (
            .clk(clk),.rst(rst),.req_valid(aqv),.req_ready(aqr),.req_addr(mmio_addr_q),
            .req_write(mmio_write_q),.req_be(mmio_be_q),.req_wdata(mmio_wdata_q),
            .rsp_valid(arv),.rsp_ready(arr),.rsp_rdata(ard),.rsp_error(are),.irq_o(accel_irq),
            .busy_o(mon_p4_busy),.result_valid_o(mon_p4_result_valid),.pending_o(mon_p4_pending),
            .intr_enable_o(mon_p4_enable),.start_o(mon_p4_start),.complete_o(mon_p4_complete),
            .soft_reset_o(mon_p4_soft_reset),.generation_o(mon_p4_generation),
            .submit_id_o(mon_p4_submit_id),.done_id_o(mon_p4_done_id),
            .result_o(mon_p4_result),.length_o(mon_p4_length)
        );    end else begin: no_accelerator
        wire unused_disabled_accel = ^{aqv,arr};
        assign aqr=0;assign arv=0;assign ard=0;assign are=0;assign accel_irq=0;
        assign mon_p4_busy=0;assign mon_p4_result_valid=0;assign mon_p4_pending=0;assign mon_p4_enable=0;
        assign mon_p4_start=0;assign mon_p4_complete=0;assign mon_p4_soft_reset=0;
        assign mon_p4_generation=0;assign mon_p4_submit_id=0;assign mon_p4_done_id=0;
        assign mon_p4_result=0;assign mon_p4_length=0;
    end endgenerate
    wire periph_irq_software,periph_irq_timer,periph_irq_external;
    generate if(MACHINE_MODE!=0) begin: machine_peripherals
        p2_peripherals #(.UART_BASE(`UART_BASE),.GPIO_BASE(`GPIO_BASE),
            .TIMER_BASE(`TIMER_BASE),.UART_DIVISOR(`UART_DIVISOR)) peripherals (
            .clk(clk),.rst(rst),.req_valid(pqv),.req_ready(pqr),.req_addr(mmio_addr_q),
            .req_write(mmio_write_q),.req_be(mmio_be_q),.req_wdata(mmio_wdata_q),
            .rsp_valid(prv),.rsp_ready(prr),.rsp_rdata(prd),.rsp_error(pre),
            .uart_tx(uart_tx),.gpio_out(gpio_out),.external_irq(irq_external_in||accel_irq),
            .irq_software(periph_irq_software),.irq_timer(periph_irq_timer),.irq_external(periph_irq_external));
    end else begin: compatibility_peripherals
        assign periph_irq_software=0;assign periph_irq_timer=0;assign periph_irq_external=irq_external_in||accel_irq;
    p1_peripherals #(.UART_BASE(`UART_BASE),.GPIO_BASE(`GPIO_BASE),
        .TIMER_BASE(`TIMER_BASE),.UART_DIVISOR(`UART_DIVISOR)) peripherals (
        .clk(clk),.rst(rst),.req_valid(pqv),.req_ready(pqr),.req_addr(mmio_addr_q),
        .req_write(mmio_write_q),.req_be(mmio_be_q),.req_wdata(mmio_wdata_q),
        .rsp_valid(prv),.rsp_ready(prr),.rsp_rdata(prd),.rsp_error(pre),
        .uart_tx(uart_tx),.gpio_out(gpio_out)
    );
    end endgenerate
    generate if(LEGACY_CORE!=0) begin: compatibility
        // C0 uses the unmodified P1 core. The harness closes request admission
        // only AFTER retired EXIT, then drains accepted responses and RAM clean.
        wire legacy_i_valid,legacy_d_valid;
        reg legacy_stopped,legacy_i_held;
        wire legacy_admit=!run_stop&&!legacy_stopped;
        wire unused_legacy_inputs=^{irq_software_in,irq_timer_in,irq_external_in,
            fatal_error,fence_i_ready,fence_i_done,fence_i_error,
            periph_irq_software,periph_irq_timer,periph_irq_external,perf_cache_flat};
        assign i_req_valid=legacy_i_valid&&(legacy_admit||legacy_i_held);
        assign cqv=legacy_d_valid&&legacy_admit;
        always @(posedge clk) begin
            if(rst) begin legacy_stopped<=0;legacy_i_held<=0;end
            else begin
                legacy_i_held<=i_req_valid&&!i_req_ready;
                if(crv&&crr&&terminal_response&&!cre) legacy_stopped<=1;
            end
        end
        assign data_idle=!pending;
        assign fence_i_valid=0;
        assign trace_irq_valid=0;assign trace_irq_pc=0;assign trace_irq_cause=0;
        assign trace_csr_valid=0;assign trace_csr_read=0;assign trace_csr_write=0;
        assign trace_csr_addr=0;assign trace_csr_rdata=0;assign trace_csr_wdata=0;
        assign machine_cycle=0;assign machine_retired=0;
        assign trace_valid1=0;assign trace_pc1=0;assign trace_insn1=0;
        assign trace_rd1=0;assign trace_wdata1=0;
    p1_core #(.RESET_PC(`RAM_BASE)) core (
        .clk(clk),.rst(rst),
        .i_req_valid(legacy_i_valid),.i_req_ready(i_req_ready&&(legacy_admit||legacy_i_held)),.i_req_addr(i_req_addr),
        .i_rsp_valid(i_rsp_valid),.i_rsp_ready(i_rsp_ready),.i_rsp_data(i_rsp_data),.i_rsp_error(i_rsp_error),
        .d_req_valid(legacy_d_valid),.d_req_ready(cqr&&legacy_admit),.d_req_addr(cqa),.d_req_write(cqw),.d_req_be(cqb),.d_req_wdata(cqd),
        .d_rsp_valid(crv),.d_rsp_ready(crr),.d_rsp_data(crd),.d_rsp_error(cre),
        .trace_valid(trace_valid),.trace_trap(trace_trap),.trace_pc(trace_pc),.trace_insn(trace_insn),
        .trace_rd(trace_rd),.trace_wdata(trace_wdata),.trace_cause(trace_cause),.trace_tval(trace_tval),
        .trace_mem_valid(trace_mem_valid),.trace_mem_write(trace_mem_write),.trace_mem_addr(trace_mem_addr),
        .trace_mem_wdata(trace_mem_wdata),.trace_mem_rdata(trace_mem_rdata),.trace_mem_be(trace_mem_be),
        .halted(halted),.count_cycle(count_cycle),.count_retired(count_retired),.count_if_wait(count_if_wait),
        .count_data_wait(count_data_wait),.count_load_use(count_load_use),.count_redirect(count_redirect),
        .count_reads(count_reads),.count_writes(count_writes)
    );
    end else begin: improved
    p2_core #(.RESET_PC(`RAM_BASE),.MACHINE_MODE(MACHINE_MODE),.BP_ENABLED(BP_ENABLED),.FIFO_DEPTH(FIFO_DEPTH),.RESPONSE_BYPASS(RESPONSE_BYPASS),.BTB_ENTRIES(BTB_ENTRIES),.BHT_ENTRIES(BHT_ENTRIES),.RAS_DEPTH(RAS_DEPTH),.EARLY_LSU(EARLY_LSU),.HW_MUL(HW_MUL),.IFETCH_DUAL_WORDS(IFETCH_DUAL_WORDS),.IFETCH_LINE_BYTES(IFETCH_LINE_BYTES),.IFETCH_PREDECODE(IFETCH_PREDECODE)) core (
        .clk(clk),.rst(rst),
        .perf_cache_flat(perf_cache_flat),
        .irq_software(irq_software_in||periph_irq_software),.irq_timer(irq_timer_in||periph_irq_timer),.irq_external(periph_irq_external),
        .fatal_error(fatal_error),.run_stop(run_stop),.data_idle(data_idle),
        .machine_cycle(machine_cycle),.machine_retired(machine_retired),
        .fence_i_valid(fence_i_valid),.fence_i_ready(fence_i_ready),.fence_i_done(fence_i_done),.fence_i_error(fence_i_error),
        .trace_irq_valid(trace_irq_valid),.trace_irq_pc(trace_irq_pc),.trace_irq_cause(trace_irq_cause),
        .trace_csr_valid(trace_csr_valid),.trace_csr_addr(trace_csr_addr),.trace_csr_read(trace_csr_read),
        .trace_csr_write(trace_csr_write),.trace_csr_rdata(trace_csr_rdata),.trace_csr_wdata(trace_csr_wdata),
        .i_req_valid(i_req_valid),.i_req_ready(i_req_ready),.i_req_addr(i_req_addr),
        .i_rsp_valid(i_rsp_valid),.i_rsp_ready(i_rsp_ready),.i_rsp_data(i_rsp_data),.i_rsp_error(i_rsp_error),
        .i_rsp_data_hi(i_rsp_data_hi),.i_rsp_hi_valid(i_rsp_hi_valid),
        .i_rsp_predecode(i_rsp_predecode),.i_rsp_predecode_hi(i_rsp_predecode_hi),
        .trace_valid1(trace_valid1),.trace_pc1(trace_pc1),.trace_insn1(trace_insn1),
        .trace_rd1(trace_rd1),.trace_wdata1(trace_wdata1),
        .d_req_valid(cqv),.d_req_ready(cqr),.d_req_addr(cqa),.d_req_write(cqw),.d_req_be(cqb),.d_req_wdata(cqd),
        .d_rsp_valid(crv),.d_rsp_ready(crr),.d_rsp_data(crd),.d_rsp_error(cre),
        .d_rsp_terminal(terminal_response),
        .trace_valid(trace_valid),.trace_trap(trace_trap),.trace_pc(trace_pc),.trace_insn(trace_insn),
        .trace_rd(trace_rd),.trace_wdata(trace_wdata),.trace_cause(trace_cause),.trace_tval(trace_tval),
        .trace_mem_valid(trace_mem_valid),.trace_mem_write(trace_mem_write),.trace_mem_addr(trace_mem_addr),
        .trace_mem_wdata(trace_mem_wdata),.trace_mem_rdata(trace_mem_rdata),.trace_mem_be(trace_mem_be),
        .halted(halted),.count_cycle(count_cycle),.count_retired(count_retired),.count_if_wait(count_if_wait),
        .count_data_wait(count_data_wait),.count_load_use(count_load_use),.count_redirect(count_redirect),
        .count_reads(count_reads),.count_writes(count_writes)
    );
    end endgenerate
endmodule
