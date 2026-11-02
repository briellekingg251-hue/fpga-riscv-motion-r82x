`timescale 1ns/1ps
`include "soc_config.vh"
// O2 SoC: core (with I$/D$), burst arbiter to main memory, MMIO router
// (UART/GPIO/TIMER peripherals, performance counters, bus-error unit and the
// EXIT mailbox). Unmapped MMIO accesses get an error response, which the core
// turns into a precise load/store access fault.
module o2_soc #(
    parameter integer UART_DIVISOR = `UART_DIVISOR,
    parameter integer PERF = 1          // performance counters at PERF_BASE
) (
    input  logic        clk, rst,
    input  logic        irq_external_in,
    input  logic        clean_req, output logic clean_done,
    output logic        data_idle,
    output logic        uart_tx,
    output logic [31:0] gpio_out,
    output logic        exit_valid, output logic [31:0] exit_code,
    // memory burst port
    output logic        m_cmd_valid, input logic m_cmd_ready, output logic m_cmd_write,
    output logic [31:0] m_cmd_addr, output logic [7:0] m_cmd_len,
    output logic        m_w_valid, input logic m_w_ready, output logic [31:0] m_w_data,
    output logic [3:0]  m_w_be, output logic m_w_last,
    input  logic        m_r_valid, output logic m_r_ready, input logic [31:0] m_r_data,
    input  logic        m_r_error, m_r_last,
    // trace (simulation / debug)
    output logic [1:0]  tr_v,
    output logic [31:0] tr_pc0, tr_pc1, tr_insn0, tr_insn1,
    output logic        tr_wr0, tr_wr1,
    output logic [4:0]  tr_rd0, tr_rd1,
    output logic [5:0]  tr_pd0, tr_pd1,
    output logic        tr_trap, tr_irq,
    output logic [31:0] tr_cause, tr_epc, tr_csr_old,
    output logic [3:0]  prf_we, output logic [23:0] prf_wa, output logic [127:0] prf_wd,
    output logic        mon_io_rd_v, output logic [31:0] mon_io_addr
);
    logic irq_sw, irq_tm, irq_ex;
    logic c_req_v, c_req_rdy, c_write, io_rsp_v, io_rsp_err;
    logic [31:0] c_addr, c_wdata, io_rdata; logic [3:0] c_be;
    // MMIO request buffer (registered request to the router/peripherals)
    logic io_req_v, io_write; logic [31:0] io_addr, io_wdata; logic [3:0] io_be; logic io_req_rdy;
    assign c_req_rdy = !io_req_v;
    always_ff @(posedge clk) begin
        if (rst) io_req_v <= 1'b0;
        else if (!io_req_v && c_req_v) io_req_v <= 1'b1;
        else if (io_req_v && io_req_rdy) io_req_v <= 1'b0;
        if (!io_req_v) begin io_addr <= c_addr; io_write <= c_write; io_be <= c_be; io_wdata <= c_wdata; end
    end
    logic ic_cmd_valid, ic_cmd_ready, ic_cmd_write, ic_w_valid, ic_w_ready, ic_w_last, ic_r_valid, ic_r_ready, ic_r_error, ic_r_last;
    logic [31:0] ic_cmd_addr, ic_w_data, ic_r_data; logic [7:0] ic_cmd_len; logic [3:0] ic_w_be;
    logic dc_cmd_valid, dc_cmd_ready, dc_cmd_write, dc_w_valid, dc_w_ready, dc_w_last, dc_r_valid, dc_r_ready, dc_r_error, dc_r_last;
    logic [31:0] dc_cmd_addr, dc_w_data, dc_r_data; logic [7:0] dc_cmd_len; logic [3:0] dc_w_be;
    logic [63:0] minstret, mcycle;
    logic [4:0] perf_ev;
    logic bus_err_v, bus_err_wb; logic [31:0] bus_err_addr;
    o2_core core (
        .clk(clk), .rst(rst), .irq_software(irq_sw), .irq_timer(irq_tm), .irq_external(irq_ex),
        .ext_clean_req(clean_req), .ext_clean_done(clean_done), .data_idle(data_idle),
        .io_req_v(c_req_v), .io_req_rdy(c_req_rdy), .io_addr(c_addr), .io_write(c_write), .io_be(c_be),
        .io_wdata(c_wdata), .io_rsp_v(io_rsp_v), .io_rdata(io_rdata), .io_rsp_err(io_rsp_err),
        .ic_cmd_valid(ic_cmd_valid), .ic_cmd_ready(ic_cmd_ready), .ic_cmd_write(ic_cmd_write), .ic_cmd_addr(ic_cmd_addr),
        .ic_cmd_len(ic_cmd_len), .ic_w_valid(ic_w_valid), .ic_w_ready(ic_w_ready), .ic_w_data(ic_w_data), .ic_w_be(ic_w_be),
        .ic_w_last(ic_w_last), .ic_r_valid(ic_r_valid), .ic_r_ready(ic_r_ready), .ic_r_data(ic_r_data),
        .ic_r_error(ic_r_error), .ic_r_last(ic_r_last),
        .dc_cmd_valid(dc_cmd_valid), .dc_cmd_ready(dc_cmd_ready), .dc_cmd_write(dc_cmd_write), .dc_cmd_addr(dc_cmd_addr),
        .dc_cmd_len(dc_cmd_len), .dc_w_valid(dc_w_valid), .dc_w_ready(dc_w_ready), .dc_w_data(dc_w_data), .dc_w_be(dc_w_be),
        .dc_w_last(dc_w_last), .dc_r_valid(dc_r_valid), .dc_r_ready(dc_r_ready), .dc_r_data(dc_r_data),
        .dc_r_error(dc_r_error), .dc_r_last(dc_r_last),
        .tr_v(tr_v), .tr_pc0(tr_pc0), .tr_pc1(tr_pc1), .tr_insn0(tr_insn0), .tr_insn1(tr_insn1),
        .tr_wr0(tr_wr0), .tr_wr1(tr_wr1), .tr_rd0(tr_rd0), .tr_rd1(tr_rd1), .tr_pd0(tr_pd0), .tr_pd1(tr_pd1),
        .tr_trap(tr_trap), .tr_irq(tr_irq), .tr_cause(tr_cause), .tr_epc(tr_epc), .tr_csr_old(tr_csr_old),
        .prf_we_o(prf_we), .prf_wa_o(prf_wa), .prf_wd_o(prf_wd), .minstret(minstret), .mcycle(mcycle),
        .perf_ev(perf_ev), .bus_err_v(bus_err_v), .bus_err_wb(bus_err_wb), .bus_err_addr(bus_err_addr));

    // ---------------- bus-error unit: errors the core cannot report precisely
    // (a committed store whose line could not be allocated, a failed dirty-line
    // write-back) are latched here and raise the machine external interrupt
    // until software clears them.
    //   +0x0 status (R: bit0 pending, bit1 write-back error, bit2 further
    //        errors were dropped; W: clear)   +0x4 address of the first error
    localparam [31:0] BEU_BASE = 32'h10004000;
    wire sel_beu = (io_addr & 32'hfffff000) == BEU_BASE;
    logic beu_pend, beu_wb, beu_ovf;
    logic [31:0] beu_addr, beu_rd;
    always_ff @(posedge clk) begin
        if (rst) begin beu_pend <= 1'b0; beu_ovf <= 1'b0; beu_wb <= 1'b0; beu_addr <= 32'b0; end
        else begin
            logic clr;
            clr = io_req_v && io_req_rdy && sel_beu && io_write && !io_addr[2];
            if (clr) begin beu_pend <= 1'b0; beu_ovf <= 1'b0; end
            if (bus_err_v) begin
                if (!beu_pend || clr) begin beu_pend <= 1'b1; beu_wb <= bus_err_wb; beu_addr <= bus_err_addr; end
                else beu_ovf <= 1'b1;
            end
        end
        if (io_req_v && io_req_rdy) beu_rd <= io_addr[2] ? beu_addr : {29'b0, beu_ovf, beu_wb, beu_pend};
    end

    // ---------------- performance counters (64-bit each, read as lo/hi words)
    //   +0x00 control (bit0: counting enabled, reset 1)
    //   +0x08 cycles  +0x10 instructions  +0x18 I$ misses  +0x20 D$ load accesses
    //   +0x28 D$ load misses  +0x30 front-end stall cycles  +0x38 back-end stall cycles
    localparam [31:0] PERF_BASE = 32'h10003000;
    logic [63:0] pc_cnt [0:6];
    logic perf_en;
    logic [31:0] perf_rd;
    wire sel_perf = PERF != 0 && (io_addr & 32'hfffff000) == PERF_BASE;
    generate if (PERF != 0) begin : g_perf
        always_ff @(posedge clk) begin
            if (rst) begin
                perf_en <= 1'b1;
                for (int i = 0; i < 7; i++) pc_cnt[i] <= 64'b0;
            end else begin
                if (io_req_v && io_req_rdy && sel_perf && io_write && io_addr[5:2] == 4'd0) perf_en <= io_wdata[0];
                if (perf_en) begin
                    pc_cnt[0] <= pc_cnt[0] + 64'd1;
                    pc_cnt[1] <= pc_cnt[1] + {63'b0, tr_v[0]} + {63'b0, tr_v[1]};
                    for (int i = 0; i < 5; i++) if (perf_ev[i]) pc_cnt[2 + i] <= pc_cnt[2 + i] + 64'd1;
                end
            end
            // read data captured with the request (one outstanding MMIO access)
            if (io_req_v && io_req_rdy) begin
                if (io_addr[5:3] == 3'd0) perf_rd <= {31'b0, perf_en};
                else perf_rd <= io_addr[2] ? pc_cnt[io_addr[5:3] - 3'd1][63:32] : pc_cnt[io_addr[5:3] - 3'd1][31:0];
            end
        end
    end else begin : g_noperf
        assign perf_rd = 32'b0;
        assign perf_en = 1'b0;
    end endgenerate

    p2_burst_arbiter2 arbiter (.clk(clk), .rst(rst),
        .a_cmd_valid(ic_cmd_valid), .a_cmd_ready(ic_cmd_ready), .a_cmd_write(ic_cmd_write), .a_cmd_addr(ic_cmd_addr),
        .a_cmd_len(ic_cmd_len), .a_w_valid(ic_w_valid), .a_w_ready(ic_w_ready), .a_w_data(ic_w_data), .a_w_be(ic_w_be),
        .a_w_last(ic_w_last), .a_r_valid(ic_r_valid), .a_r_ready(ic_r_ready), .a_r_data(ic_r_data),
        .a_r_error(ic_r_error), .a_r_last(ic_r_last),
        .b_cmd_valid(dc_cmd_valid), .b_cmd_ready(dc_cmd_ready), .b_cmd_write(dc_cmd_write), .b_cmd_addr(dc_cmd_addr),
        .b_cmd_len(dc_cmd_len), .b_w_valid(dc_w_valid), .b_w_ready(dc_w_ready), .b_w_data(dc_w_data), .b_w_be(dc_w_be),
        .b_w_last(dc_w_last), .b_r_valid(dc_r_valid), .b_r_ready(dc_r_ready), .b_r_data(dc_r_data),
        .b_r_error(dc_r_error), .b_r_last(dc_r_last),
        .m_cmd_valid(m_cmd_valid), .m_cmd_ready(m_cmd_ready), .m_cmd_write(m_cmd_write), .m_cmd_addr(m_cmd_addr),
        .m_cmd_len(m_cmd_len), .m_w_valid(m_w_valid), .m_w_ready(m_w_ready), .m_w_data(m_w_data), .m_w_be(m_w_be),
        .m_w_last(m_w_last), .m_r_valid(m_r_valid), .m_r_ready(m_r_ready), .m_r_data(m_r_data),
        .m_r_error(m_r_error), .m_r_last(m_r_last));

    // ---------------- MMIO router: one outstanding request
    wire sel_periph = ((io_addr & 32'hfffff000) == `UART_BASE) || ((io_addr & 32'hfffff000) == `GPIO_BASE) ||
                      ((io_addr & 32'hfffff000) == `TIMER_BASE);
    wire sel_exit = io_addr == `EXIT_BASE;
    logic p_req_v, p_req_rdy, p_rsp_v, p_rsp_err;
    logic [31:0] p_rdata;
    logic pend, pend_periph, pend_err, pend_perf, pend_beu;
    assign p_req_v = io_req_v && sel_periph && !pend;
    assign io_req_rdy = !pend && (sel_periph ? p_req_rdy : 1'b1);
    assign io_rsp_v = pend && (pend_periph ? p_rsp_v : 1'b1);
    assign io_rdata = pend_periph ? p_rdata : pend_perf ? perf_rd : pend_beu ? beu_rd : 32'b0;
    assign io_rsp_err = pend_periph ? p_rsp_err : pend_err;
    always_ff @(posedge clk) begin
        if (rst) begin
            pend <= 1'b0; pend_periph <= 1'b0; pend_err <= 1'b0; pend_perf <= 1'b0; pend_beu <= 1'b0;
            exit_valid <= 1'b0; exit_code <= 32'b0;
        end else begin
            if (io_rsp_v) pend <= 1'b0;
            if (io_req_v && io_req_rdy) begin
                pend <= 1'b1; pend_periph <= sel_periph; pend_perf <= sel_perf; pend_beu <= sel_beu;
                pend_err <= !sel_periph && !sel_perf && !sel_beu && !(sel_exit && io_write && io_be == 4'hf);
                if (sel_exit && io_write && io_be == 4'hf) begin exit_valid <= 1'b1; exit_code <= io_wdata; end
            end
        end
    end
    assign mon_io_rd_v = io_req_v && io_req_rdy && !io_write;
    assign mon_io_addr = io_addr;
    p2_peripherals #(.UART_BASE(`UART_BASE), .GPIO_BASE(`GPIO_BASE), .TIMER_BASE(`TIMER_BASE),
        .UART_DIVISOR(UART_DIVISOR)) peripherals (
        .clk(clk), .rst(rst), .req_valid(p_req_v), .req_ready(p_req_rdy), .req_addr(io_addr),
        .req_write(io_write), .req_be(io_be), .req_wdata(io_wdata),
        .rsp_valid(p_rsp_v), .rsp_ready(1'b1), .rsp_rdata(p_rdata), .rsp_error(p_rsp_err),
        .uart_tx(uart_tx), .gpio_out(gpio_out), .external_irq(irq_external_in || beu_pend),
        .irq_software(irq_sw), .irq_timer(irq_tm), .irq_external(irq_ex));
endmodule
