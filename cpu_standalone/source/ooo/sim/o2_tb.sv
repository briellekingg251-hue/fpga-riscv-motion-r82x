`timescale 1ns/1ps
`include "soc_config.vh"
// O2 system testbench: memory image via +INIT_HEX, lock-step ISS check of
// every commit (+NOCOSIM disables), UART capture, CoreMark timer window.
// The burst bus passes through o2_mem_shim (+STALL / +ERR_* / +WERR_*).
// Other options: +LIMIT=<cycles>, +TRACE_FROM=<commit #>,
// +PROGRESS=<cycles> (periodic progress line for long runs),
// +SIG_BEGIN=<h> +SIG_END=<h> (dump that RAM range to signature.txt at exit).
// Build with -DTB_RAM_BYTES=<n> for a larger RAM fixture (the ISS models
// 128 KiB only, so such runs use +NOCOSIM).
`ifndef TB_RAM_BYTES
`define TB_RAM_BYTES `RAM_BYTES
`endif
module o2_tb;
    import "DPI-C" function int cosim_init(input string hex);
    import "DPI-C" function int cosim_commit(input int pc, input int insn, input int wr, input int rd,
                                             input int val, input int csr_old);
    import "DPI-C" function int cosim_trap(input int cause, input int epc, input int is_irq);
    import "DPI-C" function void cosim_bus_error(input int lo, input int hi);
    import "DPI-C" function void cosim_final();

    logic clk = 1'b0, rst = 1'b1;
    always #3 clk = ~clk;

    // b_*: SoC side of the shim, m_*: memory side
    logic b_cmd_valid, b_cmd_ready, b_cmd_write, b_w_valid, b_w_ready, b_w_last, b_r_valid, b_r_ready, b_r_error, b_r_last;
    logic [31:0] b_cmd_addr, b_w_data, b_r_data; logic [7:0] b_cmd_len; logic [3:0] b_w_be;
    logic m_cmd_valid, m_cmd_ready, m_cmd_write, m_w_valid, m_w_ready, m_w_last, m_r_valid, m_r_ready, m_r_error, m_r_last;
    logic [31:0] m_cmd_addr, m_w_data, m_r_data; logic [7:0] m_cmd_len; logic [3:0] m_w_be;
    logic uart_tx, exit_valid, clean_req, clean_done, data_idle; logic [31:0] gpio_out, exit_code;
    logic [1:0] tr_v; logic [31:0] tr_pc0, tr_pc1, tr_insn0, tr_insn1, tr_cause, tr_epc, tr_csr_old;
    logic tr_wr0, tr_wr1, tr_trap, tr_irq; logic [4:0] tr_rd0, tr_rd1; logic [5:0] tr_pd0, tr_pd1;
    logic [3:0] prf_we; logic [23:0] prf_wa; logic [127:0] prf_wd;
    logic mon_io_rd_v; logic [31:0] mon_io_addr;

    o2_soc #(.UART_DIVISOR(`UART_DIVISOR)) dut (
        .clk(clk), .rst(rst), .irq_external_in(1'b0), .clean_req(clean_req), .clean_done(clean_done),
        .data_idle(data_idle), .uart_tx(uart_tx), .gpio_out(gpio_out), .exit_valid(exit_valid), .exit_code(exit_code),
        .m_cmd_valid(b_cmd_valid), .m_cmd_ready(b_cmd_ready), .m_cmd_write(b_cmd_write), .m_cmd_addr(b_cmd_addr),
        .m_cmd_len(b_cmd_len), .m_w_valid(b_w_valid), .m_w_ready(b_w_ready), .m_w_data(b_w_data), .m_w_be(b_w_be),
        .m_w_last(b_w_last), .m_r_valid(b_r_valid), .m_r_ready(b_r_ready), .m_r_data(b_r_data),
        .m_r_error(b_r_error), .m_r_last(b_r_last),
        .tr_v(tr_v), .tr_pc0(tr_pc0), .tr_pc1(tr_pc1), .tr_insn0(tr_insn0), .tr_insn1(tr_insn1),
        .tr_wr0(tr_wr0), .tr_wr1(tr_wr1), .tr_rd0(tr_rd0), .tr_rd1(tr_rd1), .tr_pd0(tr_pd0), .tr_pd1(tr_pd1),
        .tr_trap(tr_trap), .tr_irq(tr_irq), .tr_cause(tr_cause), .tr_epc(tr_epc), .tr_csr_old(tr_csr_old),
        .prf_we(prf_we), .prf_wa(prf_wa), .prf_wd(prf_wd), .mon_io_rd_v(mon_io_rd_v), .mon_io_addr(mon_io_addr));
    defparam dut.core.RAM_BYTES = `TB_RAM_BYTES;

    o2_mem_shim shim (
        .clk(clk), .rst(rst),
        .s_cmd_valid(b_cmd_valid), .s_cmd_ready(b_cmd_ready), .s_cmd_write(b_cmd_write), .s_cmd_addr(b_cmd_addr),
        .s_cmd_len(b_cmd_len), .s_w_valid(b_w_valid), .s_w_ready(b_w_ready), .s_w_data(b_w_data), .s_w_be(b_w_be),
        .s_w_last(b_w_last), .s_r_valid(b_r_valid), .s_r_ready(b_r_ready), .s_r_data(b_r_data),
        .s_r_error(b_r_error), .s_r_last(b_r_last),
        .m_cmd_valid(m_cmd_valid), .m_cmd_ready(m_cmd_ready), .m_cmd_write(m_cmd_write), .m_cmd_addr(m_cmd_addr),
        .m_cmd_len(m_cmd_len), .m_w_valid(m_w_valid), .m_w_ready(m_w_ready), .m_w_data(m_w_data), .m_w_be(m_w_be),
        .m_w_last(m_w_last), .m_r_valid(m_r_valid), .m_r_ready(m_r_ready), .m_r_data(m_r_data),
        .m_r_error(m_r_error), .m_r_last(m_r_last));

    p2_burst_sram #(.RAM_BASE(`RAM_BASE), .RAM_BYTES(`TB_RAM_BYTES)) memory (
        .clk(clk), .rst(rst), .cmd_valid(m_cmd_valid), .cmd_ready(m_cmd_ready), .cmd_write(m_cmd_write),
        .cmd_addr(m_cmd_addr), .cmd_len(m_cmd_len), .w_valid(m_w_valid), .w_ready(m_w_ready), .w_data(m_w_data),
        .w_be(m_w_be), .w_last(m_w_last), .r_valid(m_r_valid), .r_ready(m_r_ready), .r_data(m_r_data),
        .r_error(m_r_error), .r_last(m_r_last));

    // shadow PRF for commit values
    logic [31:0] shadow [0:63];
    always @(posedge clk) for (int i = 0; i < 4; i++) if (prf_we[i]) shadow[prf_wa[6*i +: 6]] <= prf_wd[32*i +: 32];

    string hex; bit cosim_on = 1; longint trace_from = -1, progress = 0;
    longint cycle = 0, limit = 400000000, exit_cycle = 0, retired = 0;
    longint timer_read_cycle [0:7]; int timer_reads = 0;
    int uart_fd; int uart_active = 0, uart_count = 0, uart_bit = 0; logic [7:0] uart_byte; logic uart_prev = 1'b1;
    int drain = 0; bit exited = 0, cleaned = 0;
    int unsigned sig_begin = 0, sig_end = 0;

    initial begin
        for (int i = 0; i < 64; i++) shadow[i] = 32'b0;
        if (!$value$plusargs("INIT_HEX=%s", hex)) $fatal(1, "INIT_HEX required");
        if ($test$plusargs("NOCOSIM")) cosim_on = 0;
        void'($value$plusargs("LIMIT=%d", limit));
        void'($value$plusargs("TRACE_FROM=%d", trace_from));
        void'($value$plusargs("PROGRESS=%d", progress));
        void'($value$plusargs("SIG_BEGIN=%h", sig_begin));
        void'($value$plusargs("SIG_END=%h", sig_end));
        $readmemh(hex, memory.mem);
        if (cosim_on && cosim_init(hex) != 0) $fatal(1, "cosim init failed");
        if (cosim_on) begin
            // same plusargs as the shim (initial blocks have no defined order)
            logic [31:0] lo, hi;
            lo = 32'h0; hi = 32'h0;
            void'($value$plusargs("ERR_LO=%h", lo));
            void'($value$plusargs("ERR_HI=%h", hi));
            cosim_bus_error(lo, hi);
        end
        uart_fd = $fopen("uart.txt", "w");
        clean_req = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
    end

    // deadlock detector: dump state if nothing commits for a long time
    longint last_commit = 0;
    always @(posedge clk) if (!rst) begin
        if (tr_v != 0 || tr_trap) last_commit = cycle;
        if (cycle - last_commit == 3000 && !exited) begin
            $display("O2_DEADLOCK cycle=%0d retired=%0d", cycle, retired);
            $display("  ROB count=%0d head=%0d head_pc=%08x insn=%08x done=%b exc=%b rpl=%b fstate=%0d",
                dut.core.rob.count, dut.core.rob.head, dut.core.rob.pc0, dut.core.rob.insn0,
                dut.core.rob.h0_done, dut.core.rob.h0_exc, dut.core.rob.h0_rpl, dut.core.rob.fstate);
            $display("  REN r_v0=%b ren_stall=%b d_v0=%b dis_stall=%b serial=%b fl_count=%0d tag_free=%b",
                dut.core.rename.r_v0, dut.core.rename.ren_stall, dut.core.rename.d_v0, dut.core.rename.dis_stall,
                dut.core.rename.serial_pend, dut.core.rename.fl_count, dut.core.rename.tag_free);
            $display("  IQ0 valid=%b resv=%b free=%0d  IQ1 valid=%b resv=%b free=%0d  IQM valid=%b resv=%b free=%0d",
                dut.core.iq0.valid, dut.core.iq0.resv, dut.core.iq0_free, dut.core.iq1.valid, dut.core.iq1.resv,
                dut.core.iq1_free, dut.core.iqm.valid, dut.core.iqm.resv, dut.core.iqm_free);
            for (int i = 0; i < 8; i++) begin
                if (dut.core.iq0.valid[i]) $display("   iq0[%0d]", i);
                if (dut.core.iq1.valid[i]) $display("   iq1[%0d]", i);
                if (dut.core.iqm.valid[i] || dut.core.iqm.resv[i]) $display("   iqm[%0d]", i);
            end
            $display("  SQ valid=%b issued=%b cmt=%b head=%0d tail=%0d  lstate=%0d rstate=%0d",
                dut.core.lsu.sv, dut.core.lsu.sa, dut.core.lsu.scm, dut.core.lsu.s_head, dut.core.lsu.s_tail,
                dut.core.lsu.lstate, dut.core.lsu.rstate);
            $display("  FE v1=%b pc1=%08x fq_count=%0d refetch=%b ic_busy=%b", dut.core.frontend.v1, dut.core.frontend.pc1,
                dut.core.frontend.fq_count, dut.core.frontend.refetch_wait, dut.core.ic_busy);
            $fatal(1, "DEADLOCK");
        end
    end
    // MMIO writes accepted by the SoC router: a store performed twice (e.g.
    // re-executed after an interrupt) shows up here even though the ISS agrees
    longint mmio_writes = 0, gpio_writes = 0;
    always @(posedge clk) if (!rst && dut.io_req_v && dut.io_req_rdy && dut.io_write) begin
        mmio_writes <= mmio_writes + 1;
        if (dut.io_addr == `GPIO_BASE) gpio_writes <= gpio_writes + 1;
    end

    // RAM range [sig_begin, sig_end) to signature.txt (arch-test style checks)
    task automatic dump_signature();
        int fd;
        if (sig_begin < `RAM_BASE || sig_end > `RAM_BASE + `TB_RAM_BYTES || sig_end <= sig_begin ||
            sig_begin[1:0] != 2'b0 || sig_end[1:0] != 2'b0)
            $fatal(1, "SIGNATURE_BOUNDS");
        fd = $fopen("signature.txt", "w");
        if (fd == 0) $fatal(1, "SIGNATURE_OPEN");
        for (int unsigned a = sig_begin; a < sig_end; a += 4) $fwrite(fd, "%08x\n", memory.mem[(a - `RAM_BASE) >> 2]);
        $fclose(fd);
        $display("SIGNATURE_DUMP words=%0d", (sig_end - sig_begin) / 4);
    endtask

    always @(posedge clk) if (!rst) begin
        cycle <= cycle + 1;
        if (cycle >= limit) begin $display("O2_TIMEOUT cycle=%0d retired=%0d", cycle, retired); cosim_final(); $fatal(1, "TIMEOUT"); end
        if (progress > 0 && cycle > 0 && cycle % progress == 0) begin
            $display("O2_PROGRESS cycle=%0d retired=%0d", cycle, retired);
            $fflush();
        end
        // commits
        if (trace_from >= 0 && retired >= trace_from) begin
            if (tr_v[0]) $display("%0t CMT0 #%0d pc=%08x insn=%08x rd=%0d wr=%b val=%08x", $time, retired, tr_pc0, tr_insn0, tr_rd0, tr_wr0, shadow[tr_pd0]);
            if (tr_v[1]) $display("%0t CMT1 #%0d pc=%08x insn=%08x rd=%0d wr=%b val=%08x", $time, retired+1, tr_pc1, tr_insn1, tr_rd1, tr_wr1, shadow[tr_pd1]);
            if (tr_trap) $display("%0t TRAP cause=%08x epc=%08x", $time, tr_cause, tr_epc);
            if (dut.core.flush) $display("%0t FLUSH pc=%08x", $time, dut.core.flush_pc);
        end
        if (tr_v[0]) begin
            retired = retired + 1;
            if (cosim_on && cosim_commit(tr_pc0, tr_insn0, tr_wr0, tr_rd0, shadow[tr_pd0], tr_csr_old) != 0) begin
                cosim_final(); $fatal(1, "COSIM_FAIL cycle=%0d", cycle);
            end
        end
        if (tr_v[1]) begin
            retired = retired + 1;
            if (cosim_on && cosim_commit(tr_pc1, tr_insn1, tr_wr1, tr_rd1, shadow[tr_pd1], tr_csr_old) != 0) begin
                cosim_final(); $fatal(1, "COSIM_FAIL cycle=%0d", cycle);
            end
        end
        if (tr_trap) begin
            if (cosim_on && cosim_trap(tr_cause, tr_epc, tr_irq) != 0) begin cosim_final(); $fatal(1, "COSIM_TRAP_FAIL"); end
        end
        // CoreMark timer window: TIMER_LOW reads
        if (mon_io_rd_v && mon_io_addr == `TIMER_BASE) begin
            $display("O2_SNAP %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                dut.core.st_cycles, dut.core.st_ok, dut.core.st_mis, dut.core.st_iss0, dut.core.st_iss1, dut.core.st_issm,
                dut.core.st_c0, dut.core.st_c1, dut.core.st_c2, dut.core.st_fq_empty, dut.core.st_ovr, dut.core.st_self,
                dut.core.st_f2miss, dut.core.st_ds_empty, dut.core.st_ds_rob, dut.core.st_ds_iq0, dut.core.st_ds_iq1,
                dut.core.st_ds_iqm, dut.core.st_ds_sq, dut.core.st_ds_tag, dut.core.st_ds_fl, dut.core.st_flush);
            if (timer_reads < 8) timer_read_cycle[timer_reads] = cycle;
            timer_reads = timer_reads + 1;
        end
        // UART
        if (!uart_active && uart_prev && !uart_tx) begin uart_active = 1; uart_count = (3 * `UART_DIVISOR / 2) - 1; uart_bit = 0; end
        else if (uart_active) begin
            if (uart_count > 0) uart_count = uart_count - 1;
            else if (uart_bit < 8) begin uart_byte[uart_bit] = uart_tx; uart_bit = uart_bit + 1; uart_count = `UART_DIVISOR - 1; end
            else begin uart_active = 0; $fwrite(uart_fd, "%c", uart_byte); end
        end
        uart_prev = uart_tx;
        // exit: wait for UART drain, then clean the D$
        if (exit_valid && !exited) begin exited = 1; exit_cycle = cycle; end
        if (exited && !cleaned) begin
            if (!uart_active && uart_tx && data_idle) drain = drain + 1; else drain = 0;
            if (drain > 3000) begin clean_req = 1'b1; end
            if (clean_done) begin
                cleaned = 1; clean_req = 1'b0;
                $fclose(uart_fd);
                $display("O2_EXIT code=%0d exit_cycle=%0d retired=%0d timer_reads=%0d window=%0d",
                         exit_code, exit_cycle, retired, timer_reads,
                         timer_reads >= 2 ? timer_read_cycle[1] - timer_read_cycle[0] : 0);
                $display("O2_MMIO writes=%0d gpio_writes=%0d", mmio_writes, gpio_writes);
                if (sig_begin != 0) dump_signature();
                if (cosim_on) cosim_final();
                $finish;
            end
        end
    end
endmodule
