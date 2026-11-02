`timescale 1ns/1ps
`include "soc_config.vh"
// O2 board top for the MES2L676 200K mini board (same pins/constraints as the
// baseline p5_pds_top): 27 MHz in, PLL, key reset, O2 SoC, 128 KiB SRAM image.
module o2_pds_top #(
    parameter real PLL_RATIOF = 36.0,
    parameter real PLL_RATIO0 = 6.0,
    parameter integer PLL_DUTY0 = 6,
    parameter integer PLL_DUTYF = 36,
    parameter INIT_FILE = "../common/program.hex"
) (
    input  wire clk,
    input  wire key0_n,
    output wire uart_tx,
    output wire [3:0] led
);
    wire clk_core, pll_lock;
    p7_board_pll162 #(.RATIOF(PLL_RATIOF), .RATIO0(PLL_RATIO0), .DUTY0(PLL_DUTY0), .DUTYF(PLL_DUTYF)) pll162 (
        .clkin1(clk), .clkout0(clk_core), .lock(pll_lock));
    // key / power-on reset (as p5_mini_top)
    reg [1:0] key_reset_sync = 2'b11;
    reg [16:0] por_count = 17'd0;
    wire key0 = key0_n && pll_lock;
    always @(posedge clk_core or negedge key0)
        if (!key0) key_reset_sync <= 2'b11; else key_reset_sync <= {key_reset_sync[0], 1'b0};
    wire key_reset = key_reset_sync[1];
    wire por_done = &por_count;
    always @(posedge clk_core) if (key_reset) por_count <= 17'd0; else if (!por_done) por_count <= por_count + 17'd1;
    wire reset_n = !key_reset && por_done;
    reg [1:0] reset_sync = 2'b11;
    always @(posedge clk_core or negedge reset_n)
        if (!reset_n) reset_sync <= 2'b11; else reset_sync <= {reset_sync[0], 1'b0};
    wire rst = reset_sync[1];

    wire m_cmd_valid, m_cmd_ready, m_cmd_write, m_w_valid, m_w_ready, m_w_last, m_r_valid, m_r_ready, m_r_error, m_r_last;
    wire [31:0] m_cmd_addr, m_w_data, m_r_data; wire [7:0] m_cmd_len; wire [3:0] m_w_be;
    wire exit_valid, clean_done, data_idle; wire [31:0] exit_code, gpio_out;
    reg clean_req, completed, failed;
    o2_soc soc (
        .clk(clk_core), .rst(rst), .irq_external_in(1'b0), .clean_req(clean_req), .clean_done(clean_done),
        .data_idle(data_idle), .uart_tx(uart_tx), .gpio_out(gpio_out), .exit_valid(exit_valid), .exit_code(exit_code),
        .m_cmd_valid(m_cmd_valid), .m_cmd_ready(m_cmd_ready), .m_cmd_write(m_cmd_write), .m_cmd_addr(m_cmd_addr),
        .m_cmd_len(m_cmd_len), .m_w_valid(m_w_valid), .m_w_ready(m_w_ready), .m_w_data(m_w_data), .m_w_be(m_w_be),
        .m_w_last(m_w_last), .m_r_valid(m_r_valid), .m_r_ready(m_r_ready), .m_r_data(m_r_data),
        .m_r_error(m_r_error), .m_r_last(m_r_last),
        .tr_v(), .tr_pc0(), .tr_pc1(), .tr_insn0(), .tr_insn1(), .tr_wr0(), .tr_wr1(), .tr_rd0(), .tr_rd1(),
        .tr_pd0(), .tr_pd1(), .tr_trap(), .tr_irq(), .tr_cause(), .tr_epc(), .tr_csr_old(),
        .prf_we(), .prf_wa(), .prf_wd(), .mon_io_rd_v(), .mon_io_addr());
    p2_burst_sram #(.RAM_BASE(`RAM_BASE), .RAM_BYTES(`RAM_BYTES), .INIT_FILE(INIT_FILE)) memory (
        .clk(clk_core), .rst(rst), .cmd_valid(m_cmd_valid), .cmd_ready(m_cmd_ready), .cmd_write(m_cmd_write),
        .cmd_addr(m_cmd_addr), .cmd_len(m_cmd_len), .w_valid(m_w_valid), .w_ready(m_w_ready), .w_data(m_w_data),
        .w_be(m_w_be), .w_last(m_w_last), .r_valid(m_r_valid), .r_ready(m_r_ready), .r_data(m_r_data),
        .r_error(m_r_error), .r_last(m_r_last));
    always @(posedge clk_core) begin
        if (rst) begin clean_req <= 1'b0; completed <= 1'b0; failed <= 1'b0; end
        else begin
            if (exit_valid && !clean_req && !completed) begin
                clean_req <= 1'b1;
                if (exit_code != 32'd1) failed <= 1'b1;
            end
            if (clean_done) begin clean_req <= 1'b0; completed <= 1'b1; end
        end
    end
    assign led[0] = completed && !failed;
    assign led[1] = failed;
    assign led[2] = gpio_out[0];
    assign led[3] = gpio_out[1];
endmodule
