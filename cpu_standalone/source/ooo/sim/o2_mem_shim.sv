`timescale 1ns/1ps
// Testbench shim on the burst bus between the SoC and the memory model.
//   +STALL=<0..99>       percentage of cycles each handshake (cmd, w, r) stalls
//   +SEED=<n>            stall pattern seed
//   +ERR_LO=<h> +ERR_HI=<h>    read bursts starting in [lo, hi) answer r_error
//                              with poisoned data
//   +ERR_BEAT=<n>        only beat n of such a burst errs (default: every beat)
//   +WERR_LO=<h> +WERR_HI=<h>  write bursts starting in [lo, hi) get an error
//                              acknowledgement
// Error ranges must be 32-byte (cache line) aligned: bursts are matched by
// their start address, the ISS by byte address.
// A stall withholds ready from the master and valid from the memory in the
// same cycle, so both sides see a legal valid/ready wait; a read beat already
// shown to the master stays valid until it is taken.
// Checks: a command or write beat that is not accepted stays valid and
// unchanged; one burst at a time; a write burst has exactly cmd_len beats with
// w_last on the final one, then exactly one acknowledgement; a read burst
// returns exactly cmd_len beats with r_last on the final one.
module o2_mem_shim (
    input  logic        clk, rst,
    // master side (SoC)
    input  logic        s_cmd_valid, output logic s_cmd_ready, input logic s_cmd_write,
    input  logic [31:0] s_cmd_addr, input logic [7:0] s_cmd_len,
    input  logic        s_w_valid, output logic s_w_ready, input logic [31:0] s_w_data,
    input  logic [3:0]  s_w_be, input logic s_w_last,
    output logic        s_r_valid, input logic s_r_ready, output logic [31:0] s_r_data,
    output logic        s_r_error, s_r_last,
    // memory side
    output logic        m_cmd_valid, input logic m_cmd_ready, output logic m_cmd_write,
    output logic [31:0] m_cmd_addr, output logic [7:0] m_cmd_len,
    output logic        m_w_valid, input logic m_w_ready, output logic [31:0] m_w_data,
    output logic [3:0]  m_w_be, output logic m_w_last,
    input  logic        m_r_valid, output logic m_r_ready, input logic [31:0] m_r_data,
    input  logic        m_r_error, m_r_last
);
    int unsigned stall = 0, seed = 1;
    int err_beat = -1;
    logic [31:0] err_lo = 32'h0, err_hi = 32'h0, werr_lo = 32'h0, werr_hi = 32'h0;
    initial begin
        void'($value$plusargs("STALL=%d", stall));
        void'($value$plusargs("SEED=%d", seed));
        void'($value$plusargs("ERR_LO=%h", err_lo));
        void'($value$plusargs("ERR_HI=%h", err_hi));
        void'($value$plusargs("ERR_BEAT=%d", err_beat));
        void'($value$plusargs("WERR_LO=%h", werr_lo));
        void'($value$plusargs("WERR_HI=%h", werr_hi));
        void'($urandom(seed));
    end

    // per-cycle handshake enables
    logic go_c = 1'b1, go_w = 1'b1, go_r = 1'b1;
    always_ff @(posedge clk) begin
        go_c <= $urandom_range(99) >= stall;
        go_w <= $urandom_range(99) >= stall;
        if (!(s_r_valid && !s_r_ready)) go_r <= $urandom_range(99) >= stall;
    end

    // current burst (the memory serves one at a time)
    logic busy, cur_write, cur_err; logic [7:0] cur_len, w_beats, r_beats;
    wire cmd_fire = m_cmd_valid && m_cmd_ready;
    wire w_fire = s_w_valid && s_w_ready;
    wire r_fire = s_r_valid && s_r_ready;
    wire beat_err = cur_err && (cur_write || err_beat < 0 || r_beats == 8'(err_beat));

    assign m_cmd_valid = s_cmd_valid && go_c;
    assign s_cmd_ready = m_cmd_ready && go_c;
    assign m_cmd_write = s_cmd_write; assign m_cmd_addr = s_cmd_addr; assign m_cmd_len = s_cmd_len;
    assign m_w_valid = s_w_valid && go_w;
    assign s_w_ready = m_w_ready && go_w;
    assign m_w_data = s_w_data; assign m_w_be = s_w_be; assign m_w_last = s_w_last;
    assign s_r_valid = m_r_valid && go_r;
    assign m_r_ready = s_r_ready && go_r;
    assign s_r_data = (beat_err && !cur_write) ? 32'hdeadbeef : m_r_data;
    assign s_r_error = m_r_error || beat_err;
    assign s_r_last = m_r_last;

    longint n_cmd = 0, n_stall = 0, n_rerr = 0, n_werr = 0;
    logic p_cmd_wait, p_w_wait, p_cmd_write, p_w_last; logic [31:0] p_cmd_addr, p_w_data;
    logic [7:0] p_cmd_len; logic [3:0] p_w_be;
    always_ff @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0; cur_err <= 1'b0; cur_write <= 1'b0; cur_len <= 8'd0; w_beats <= 8'd0; r_beats <= 8'd0;
            p_cmd_wait <= 1'b0; p_w_wait <= 1'b0;
        end else begin
            if (cmd_fire) begin
                logic err;
                err = s_cmd_write ? (s_cmd_addr >= werr_lo && s_cmd_addr < werr_hi)
                                  : (s_cmd_addr >= err_lo && s_cmd_addr < err_hi);
                assert (!busy) else $fatal(1, "SHIM_CMD_DURING_BURST");
                busy <= 1'b1; cur_write <= s_cmd_write; cur_len <= s_cmd_len; w_beats <= 8'd0; r_beats <= 8'd0;
                cur_err <= err;
                n_cmd <= n_cmd + 1;
                if (err && s_cmd_write) n_werr <= n_werr + 1;
                if (err && !s_cmd_write) n_rerr <= n_rerr + 1;
            end
            if (w_fire) begin
                assert (busy && cur_write && w_beats < cur_len) else $fatal(1, "SHIM_W_OUTSIDE_BURST");
                assert (s_w_last == (w_beats == cur_len - 8'd1)) else $fatal(1, "SHIM_W_LAST beat=%0d", w_beats);
                w_beats <= w_beats + 8'd1;
            end
            if (r_fire) begin
                assert (busy) else $fatal(1, "SHIM_R_OUTSIDE_BURST");
                if (cur_write) begin
                    // the single acknowledgement, after the last write beat
                    assert (w_beats == cur_len && s_r_last) else $fatal(1, "SHIM_W_ACK");
                    busy <= 1'b0;
                end else begin
                    assert (r_beats < cur_len) else $fatal(1, "SHIM_R_EXTRA_BEAT");
                    assert (s_r_last == (r_beats == cur_len - 8'd1)) else $fatal(1, "SHIM_R_LAST beat=%0d", r_beats);
                    r_beats <= r_beats + 8'd1;
                    if (s_r_last) busy <= 1'b0;
                end
            end
            // cycles in which a presented handshake was held back
            if ((s_cmd_valid && !go_c) || (s_w_valid && !go_w) || (m_r_valid && !go_r)) n_stall <= n_stall + 1;
            // a waiting command / write beat must hold
            if (p_cmd_wait)
                assert (s_cmd_valid && s_cmd_write == p_cmd_write && s_cmd_addr == p_cmd_addr && s_cmd_len == p_cmd_len)
                    else $fatal(1, "SHIM_CMD_UNSTABLE");
            if (p_w_wait)
                assert (s_w_valid && s_w_data == p_w_data && s_w_be == p_w_be && s_w_last == p_w_last)
                    else $fatal(1, "SHIM_W_UNSTABLE");
            p_cmd_wait <= s_cmd_valid && !s_cmd_ready;
            p_w_wait <= s_w_valid && !s_w_ready;
        end
        p_cmd_write <= s_cmd_write; p_cmd_addr <= s_cmd_addr; p_cmd_len <= s_cmd_len;
        p_w_data <= s_w_data; p_w_be <= s_w_be; p_w_last <= s_w_last;
    end
    final $display("MEM_SHIM cmds=%0d stalled_cycles=%0d read_errors=%0d write_errors=%0d stall_pct=%0d",
                   n_cmd, n_stall, n_rerr, n_werr, stall);
endmodule
