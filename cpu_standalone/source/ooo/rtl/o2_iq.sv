`timescale 1ns/1ps
// O2 issue queue: N-entry matrix scheduler (dependency matrix over NC global
// columns), oldest-first age-matrix select, one issue per cycle.
// Wakeup class per entry (lat field):
//   0: wakes its column in the grant cycle (1-cycle ALU)
//   1: wakes one cycle after grant (loads, MUL, CLMUL)
//   2: wakes two cycles after grant (MULH*)
//   3: wakes when ext_done[slot] is asserted (head-only loads / stores)
// An entry with lat>0 stays reserved (not reallocated) until it has woken.
// Every entry is an independent register set (generate), so synthesis never
// sees a multi-write memory.
module o2_iq #(
    parameter integer N = 8,
    parameter integer NC = 24,       // global wake columns
    parameter integer BASE = 0,      // first global column of this queue
    parameter integer PW = 64,       // static payload width
    parameter integer MEM = 0        // memory queue: store-order readiness
) (
    input  logic          clk, rst,
    // dispatch: d_v[k] = rename slot k goes to this queue (slot 0 is older)
    input  logic [1:0]    d_v,
    input  logic [PW-1:0] d_pay0, d_pay1,
    input  logic [NC-1:0] d_dep0, d_dep1,
    input  logic [1:0]    d_lat0, d_lat1,
    input  logic [7:0]    d_brm0, d_brm1,
    input  logic [7:0]    d_sqm0, d_sqm1,    // MEM: older stores still in SQ (loads)
    input  logic          d_store0, d_store1,
    input  logic          d_head0, d_head1,  // head-only (issue only at ROB head)
    input  logic [4:0]    d_rob0, d_rob1,
    output logic [2:0]    a_slot0, a_slot1,  // allocation slots for this cycle
    output logic [3:0]    free_cnt,          // registered, conservative (frees seen a cycle late)
    // global wakeup
    input  logic [NC-1:0] wake_in,
    output logic [N-1:0]  wake_out,
    // issue
    input  logic          issue_en,          // pipe can accept
    input  logic          blk_lat,           // block entries with lat!=0 this cycle
    input  logic          blk_l0,            // block entries with lat==0 this cycle
    output logic          iss_v,
    output logic [2:0]    iss_slot,
    output logic [PW-1:0] iss_pay,
    output logic [7:0]    iss_brm,
    output logic [7:0]    iss_sqm,
    output logic [4:0]    iss_rob,
    output logic [1:0]    iss_lat,
    input  logic [N-1:0]  ext_done,          // lat==3 completion
    // MEM readiness
    input  logic [7:0]    sq_issued,         // SQ entry has address/data
    input  logic [7:0]    sq_free,           // SQ entries freed this cycle
    input  logic          spec_ok,           // MEM: load queue has room for speculative loads
    input  logic [4:0]    rob_head,
    // branch resolution / kills
    input  logic          br_ok, input logic [2:0] br_ok_tag,
    input  logic          br_kill, input logic [2:0] br_kill_tag,
    input  logic          flush
);
`include "o2_util.vh"
    // per-entry state (flattened views)
    logic [N-1:0] valid, resv, req, grant, ready;
    logic [N*PW-1:0] pay_f;
    logic [N*8-1:0]  brm_f, sqm_f;
    logic [N*5-1:0]  rob_f;
    logic [N*2-1:0]  lat_f;
    logic [N*N-1:0]  older_f;

    // ---- allocation from the registered free mask
    wire [N-1:0] freem = ~(valid | resv);
    // N is 8: explicit priority encoders (see o2_util.vh)
    wire [7:0] oh0 = oh_lo8(freem), oh1 = oh_hi8(freem);
    assign a_slot0 = enc8(oh0);
    assign a_slot1 = enc8(oh1);
    // slot 0 takes the lowest free entry; slot 1 the highest when both
    // slots come here, else the lowest
    wire alloc0_ok = d_v[0] && !flush;
    wire alloc1_ok = d_v[1] && !flush;
    wire [7:0] s1oh = d_v[0] ? oh1 : oh0;
    wire [7:0] amask = (alloc0_ok ? oh0 : 8'b0) | (alloc1_ok ? s1oh : 8'b0);
    // free entries next cycle >= free entries now - allocations now
    always_ff @(posedge clk) begin
        if (rst) free_cnt <= 4'(N);
        else free_cnt <= popc8(freem) - {3'b0, alloc0_ok} - {3'b0, alloc1_ok};
    end

    // ---- select: oldest requesting entry
    always_comb begin
        for (int i = 0; i < N; i++) req[i] = ready[i] && issue_en && !(blk_lat && lat_f[2*i +: 2] != 2'd0) &&
                                             !(blk_l0 && lat_f[2*i +: 2] == 2'd0);
        for (int i = 0; i < N; i++) grant[i] = req[i] && !(|(req & older_f[N*i +: N]));
    end
    assign iss_v = |grant;
    always_comb begin
        iss_slot = enc8(grant); iss_pay = '0; iss_brm = 8'b0; iss_sqm = 8'b0; iss_rob = 5'b0; iss_lat = 2'b0;
        for (int i = 0; i < N; i++) begin
            iss_pay = iss_pay | ({PW{grant[i]}} & pay_f[PW*i +: PW]);
            iss_brm = iss_brm | ({8{grant[i]}} & brm_f[8*i +: 8]);
            iss_sqm = iss_sqm | ({8{grant[i]}} & sqm_f[8*i +: 8]);
            iss_rob = iss_rob | ({5{grant[i]}} & rob_f[5*i +: 5]);
            iss_lat = iss_lat | ({2{grant[i]}} & lat_f[2*i +: 2]);
        end
    end

    genvar g;
    generate for (g = 0; g < N; g++) begin : e
        logic v, rv, p1, p2a, p2b, ex;
        logic [NC-1:0] dep;
        logic [N-1:0] old;
        logic [PW-1:0] pay;
        logic [1:0] lat;
        logic [7:0] brm, sqm;
        logic st, hd;
        logic [4:0] rob;
        wire a0 = alloc0_ok && oh0[g];
        wire a1 = alloc1_ok && s1oh[g];
        wire kill = flush || (br_kill && brm[br_kill_tag]);
        wire gr = grant[g];
        always_comb begin
            logic rdy;
            rdy = v && (dep == '0);
            // loads wait for older store addresses only when predicted
            // dependent (payload bit 0) or the load queue is short of room
            if (MEM != 0 && !st && (pay[0] || !spec_ok)) rdy = rdy && ((sqm & ~sq_issued) == 8'b0);
            if (MEM != 0 && hd) rdy = rdy && (rob == rob_head);
            ready[g] = rdy;
        end
        assign wake_out[g] = (gr && lat == 2'd0) || p1 || p2b || (ex && ext_done[g]);
        assign valid[g] = v; assign resv[g] = rv;
        assign pay_f[PW*g +: PW] = pay; assign brm_f[8*g +: 8] = brm; assign sqm_f[8*g +: 8] = sqm;
        assign rob_f[5*g +: 5] = rob; assign lat_f[2*g +: 2] = lat; assign older_f[N*g +: N] = old;
        // control state
        always_ff @(posedge clk) begin
            if (rst) begin
                v <= 1'b0; rv <= 1'b0; p1 <= 1'b0; p2a <= 1'b0; p2b <= 1'b0; ex <= 1'b0;
            end else if (a0 || a1) begin
                v <= 1'b1; rv <= 1'b0; p1 <= 1'b0; p2a <= 1'b0; p2b <= 1'b0; ex <= 1'b0;
            end else begin
                p2b <= p2a && !flush;
                if (gr) begin
                    v <= 1'b0;
                    rv <= lat != 2'd0;
                    p1 <= lat == 2'd1;
                    p2a <= lat == 2'd2;
                    ex <= lat == 2'd3;
                end else begin
                    p1 <= 1'b0; p2a <= 1'b0;
                    if (p1 || p2b || (ex && ext_done[g])) begin rv <= 1'b0; ex <= 1'b0; end
                end
                if (kill) begin
                    v <= 1'b0;
                    if (flush || ex) begin rv <= 1'b0; ex <= 1'b0; end
                    if (flush) begin p1 <= 1'b0; p2a <= 1'b0; p2b <= 1'b0; end
                end
            end
        end
        // payload / dependency / masks
        always_ff @(posedge clk) begin
            if (a0) begin
                dep <= d_dep0 & ~wake_in;
                pay <= d_pay0; lat <= d_lat0;
                brm <= br_ok ? (d_brm0 & ~(8'b1 << br_ok_tag)) : d_brm0;
                sqm <= d_sqm0 & ~sq_free;
                st <= d_store0; hd <= d_head0; rob <= d_rob0;
                old <= valid & ~grant;
            end else if (a1) begin
                dep <= d_dep1 & ~wake_in;
                pay <= d_pay1; lat <= d_lat1;
                brm <= br_ok ? (d_brm1 & ~(8'b1 << br_ok_tag)) : d_brm1;
                sqm <= d_sqm1 & ~sq_free;
                st <= d_store1; hd <= d_head1; rob <= d_rob1;
                old <= (valid & ~grant) | (alloc0_ok ? oh0 : 8'b0);
            end else begin
                dep <= dep & ~wake_in;
                if (br_ok) brm[br_ok_tag] <= 1'b0;
                sqm <= sqm & ~sq_free;
                // a slot allocated this cycle is younger than this entry
                old <= old & ~amask;
            end
        end
    end endgenerate
`ifndef SYNTHESIS
    always_ff @(posedge clk) if (!rst) begin
        if (d_v[0] && d_v[1]) assert (a_slot0 != a_slot1) else $fatal(1, "IQ_DOUBLE_ALLOC");
        if (d_v[0]) assert (freem[a_slot0]) else $fatal(1, "IQ_ALLOC_BUSY0");
        if (d_v[1]) assert (|(freem & s1oh)) else $fatal(1, "IQ_ALLOC_BUSY1");
    end
`endif
endmodule
