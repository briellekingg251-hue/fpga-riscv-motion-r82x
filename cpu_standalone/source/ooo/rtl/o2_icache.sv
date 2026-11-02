`timescale 1ns/1ps
// O2 instruction cache: 2-way set associative, 32-byte lines, one aligned
// 16-byte fetch block per cycle. F1 presents the address every cycle; F2
// sees the registered tag hit and the way-selected 128-bit block.
// Per-way data is split into four 32-bit word banks (one per block slot) so a
// refill writes one word per beat and a lookup reads all four slots at once.
//
// Bus contract: a refill is one 8-beat read burst; the slave returns exactly
// cmd_len beats with r_last on the final one (checked in simulation). A burst
// with r_error on any beat leaves the line invalid and records it as the error
// line: the refetch then "hits" with f2_fault set (instruction access fault)
// instead of refilling again. The record is dropped by the next refill or by
// FENCE.I, so a later fetch retries the bus.
module o2_icache #(
    parameter integer SETS = 256,              // per way
    parameter [31:0]  RAM_BASE = 32'h80000000,
    parameter integer RAM_BYTES = 131072
) (
    input  logic        clk, rst,
    // F1 lookup (address is sampled every cycle unless hold)
    input  logic [31:0] f1_pc,
    input  logic        f1_hold,          // keep F2 contents (no new lookup)
    // F2 result for the registered address
    output logic [31:0] f2_pc,
    output logic        f2_hit,
    output logic        f2_cacheable,
    output logic        f2_fault,         // the line's last refill failed (with f2_hit)
    output logic [127:0] f2_block,
    // miss handling
    input  logic        refill_req,       // F2 miss: fetch line of f2_pc
    output logic        busy,             // refill or invalidate in progress
    input  logic        invalidate,       // FENCE.I
    // burst read master
    output logic        cmd_valid, input logic cmd_ready,
    output logic        cmd_write, output logic [31:0] cmd_addr, output logic [7:0] cmd_len,
    output logic        w_valid, input logic w_ready, output logic [31:0] w_data,
    output logic [3:0]  w_be, output logic w_last,
    input  logic        r_valid, output logic r_ready, input logic [31:0] r_data,
    input  logic        r_error, r_last,
    output logic        perf_fill           // a refill starts (performance counter)
);
    localparam integer SB = $clog2(SETS);
    localparam integer RAB = $clog2(RAM_BYTES);
    localparam integer TB = RAB - 5 - SB;        // tag bits inside RAM region
    localparam integer ROWS = SETS * 2;          // 2 blocks of 16B per line

    function automatic logic in_ram(input logic [31:0] a);
        in_ram = (a & ~(RAM_BYTES - 1)) == RAM_BASE;
    endfunction

    (* syn_ramstyle = "lut_ram" *) logic [TB-1:0] tag0 [0:SETS-1];
    (* syn_ramstyle = "lut_ram" *) logic [TB-1:0] tag1 [0:SETS-1];
    // valid / victim bits in LUT-RAM: read port 0 = F1 lookup, 1 = refill start
    logic we_v0, we_v1, we_vt, wd_v, wd_vt; logic [SB-1:0] wa_m;
    logic [1:0] rv0, rv1, rvt;

    logic [31:0] d0_0 [0:ROWS-1]; logic [31:0] d0_1 [0:ROWS-1];
    logic [31:0] d0_2 [0:ROWS-1]; logic [31:0] d0_3 [0:ROWS-1];
    logic [31:0] d1_0 [0:ROWS-1]; logic [31:0] d1_1 [0:ROWS-1];
    logic [31:0] d1_2 [0:ROWS-1]; logic [31:0] d1_3 [0:ROWS-1];
    logic [31:0] q0_0, q0_1, q0_2, q0_3, q1_0, q1_1, q1_2, q1_3;

    wire [SB-1:0] f1_set = f1_pc[5 +: SB];
    wire [TB-1:0] f1_tag = f1_pc[5 + SB +: TB];
    wire [SB:0]   f1_row = f1_pc[4 +: SB + 1];

    // refill state
    localparam [1:0] S_IDLE = 2'd0, S_CMD = 2'd1, S_DATA = 2'd2, S_INV = 2'd3;
    logic [1:0] state;
    logic [31:0] fill_addr;
    logic [2:0] beat;
    logic fill_way;
    logic fill_err;                              // an earlier beat of this burst had r_error
    wire [SB-1:0] fill_set = fill_addr[5 +: SB];
    wire [SB:0] fill_row = {fill_set, beat[2]};
    wire fill_we = (state == S_DATA) && r_valid;
    wire fill_last = fill_we && beat == 3'd7;
    wire fill_ok = !fill_err && !r_error;        // with fill_last: install the line

    // line (index within the RAM window) whose last refill failed
    logic err_v; logic [RAB-6:0] err_line;

    logic hit0_q, hit1_q, err_q, f2_cacheable_q;
    always_ff @(posedge clk) begin
        if (rst) begin
            hit0_q <= 1'b0; hit1_q <= 1'b0; err_q <= 1'b0; f2_pc <= 32'b0; f2_cacheable_q <= 1'b0;
        end else if (!f1_hold) begin
            f2_pc <= f1_pc;
            f2_cacheable_q <= in_ram(f1_pc);
            hit0_q <= rv0[0] && tag0[f1_set] == f1_tag && in_ram(f1_pc);
            hit1_q <= rv1[0] && tag1[f1_set] == f1_tag && in_ram(f1_pc);
            err_q <= err_v && f1_pc[RAB-1:5] == err_line && in_ram(f1_pc);
        end
    end
    always_ff @(posedge clk) begin
        if (!f1_hold) begin
            q0_0 <= d0_0[f1_row]; q0_1 <= d0_1[f1_row]; q0_2 <= d0_2[f1_row]; q0_3 <= d0_3[f1_row];
            q1_0 <= d1_0[f1_row]; q1_1 <= d1_1[f1_row]; q1_2 <= d1_2[f1_row]; q1_3 <= d1_3[f1_row];
        end
        if (fill_we && !fill_way) begin
            case (beat[1:0])
                2'd0: d0_0[fill_row] <= r_data; 2'd1: d0_1[fill_row] <= r_data;
                2'd2: d0_2[fill_row] <= r_data; default: d0_3[fill_row] <= r_data;
            endcase
        end
        if (fill_we && fill_way) begin
            case (beat[1:0])
                2'd0: d1_0[fill_row] <= r_data; 2'd1: d1_1[fill_row] <= r_data;
                2'd2: d1_2[fill_row] <= r_data; default: d1_3[fill_row] <= r_data;
            endcase
        end
    end
    assign f2_hit = hit0_q || hit1_q || err_q;
    assign f2_fault = err_q;
    assign f2_cacheable = f2_cacheable_q;
    assign f2_block = hit1_q ? {q1_3, q1_2, q1_1, q1_0} : {q0_3, q0_2, q0_1, q0_0};

    // tags: written once the whole line has arrived (the valid bit decides
    // whether the line is usable)
    always_ff @(posedge clk) begin
        if (fill_last && !fill_way) tag0[fill_set] <= fill_addr[5 + SB +: TB];
        if (fill_last && fill_way) tag1[fill_set] <= fill_addr[5 + SB +: TB];
    end

    assign busy = state != S_IDLE;
    assign perf_fill = state == S_IDLE && !invalidate && refill_req;
    assign cmd_valid = state == S_CMD;
    assign cmd_write = 1'b0;
    assign cmd_addr = {fill_addr[31:5], 5'b0};
    assign cmd_len = 8'd8;
    assign w_valid = 1'b0; assign w_data = 32'b0; assign w_be = 4'b0; assign w_last = 1'b0;
    assign r_ready = state == S_DATA;

    logic [SB-1:0] inv_set;
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_INV; inv_set <= '0; beat <= 3'd0; fill_way <= 1'b0; fill_addr <= 32'b0;
            fill_err <= 1'b0; err_v <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (invalidate) begin state <= S_INV; inv_set <= '0; err_v <= 1'b0; end
                    else if (refill_req) begin
                        fill_addr <= f2_pc;
                        fill_way <= !rv0[1] ? 1'b0 : !rv1[1] ? 1'b1 : rvt[1];
                        state <= S_CMD;
                        err_v <= 1'b0;
                    end
                end
                S_CMD: if (cmd_ready) begin state <= S_DATA; beat <= 3'd0; fill_err <= 1'b0; end
                S_DATA: if (r_valid) begin
                    beat <= beat + 3'd1;
                    fill_err <= fill_err || r_error;
                    if (beat == 3'd7) begin
                        state <= S_IDLE;
                        if (!fill_ok) begin err_v <= 1'b1; err_line <= fill_addr[RAB-1:5]; end
                    end
                end
                S_INV: begin
                    inv_set <= inv_set + 1'b1;
                    if (inv_set == SB'(SETS - 1)) state <= S_IDLE;
                end
            endcase
        end
    end
    // valid bits: cleared by the invalidate walk, the refill victim is dropped
    // before refilling, set when the fill completes without a bus error
    always_comb begin
        we_v0 = 1'b0; we_v1 = 1'b0; wd_v = 1'b0; wa_m = fill_set;
        we_vt = fill_last; wd_vt = !fill_way;
        if (state == S_INV) begin we_v0 = 1'b1; we_v1 = 1'b1; wa_m = inv_set; we_vt = 1'b1; wd_vt = 1'b0; end
        else if (fill_last) begin we_v0 = !fill_way; we_v1 = fill_way; wd_v = fill_ok; end
        else if (state == S_CMD) begin we_v0 = !fill_way; we_v1 = fill_way; end
    end
    wire [2*SB-1:0] mra = {f2_pc[5 +: SB], f1_set};
    o2_bitram #(.DEPTH(SETS), .AW(SB), .NR(2)) mv0 (.clk(clk), .we(we_v0), .wa(wa_m), .wd(wd_v), .ra(mra), .rd(rv0));
    o2_bitram #(.DEPTH(SETS), .AW(SB), .NR(2)) mv1 (.clk(clk), .we(we_v1), .wa(wa_m), .wd(wd_v), .ra(mra), .rd(rv1));
    o2_bitram #(.DEPTH(SETS), .AW(SB), .NR(2)) mvt (.clk(clk), .we(we_vt), .wa(wa_m), .wd(wd_vt), .ra(mra), .rd(rvt));
`ifndef SYNTHESIS
    always_ff @(posedge clk) if (!rst && fill_we)
        assert (r_last == (beat == 3'd7)) else $fatal(1, "ICACHE_R_LAST beat=%0d last=%b", beat, r_last);
`endif
endmodule
