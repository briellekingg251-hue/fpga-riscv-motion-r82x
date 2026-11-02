`timescale 1ns/1ps
`include "o2_defs.vh"
// O2 load/store unit with an integrated data cache.
//   Store queue (8): allocated at dispatch, filled when the store issues,
//   committed in order, drained to the cache (port B) after commit.
//   Load pipe: EX = address, tag lookup, BRAM read (port A);
//              M  = way select, store-to-load forwarding, alignment.
//   A load that cannot complete in M (miss, MMIO, partial overlap, refill in
//   progress) is reported as REPLAY; the ROB re-executes it at the head.
//   Head-only memory ops (lat class 3) use a slow, non-speculative path.
// MMIO: every MMIO access is performed by the slow path while the op is the
//   oldest instruction, before it commits, so a bus error response is a
//   precise access fault. An MMIO store issued speculatively only reports
//   REPLAY (via the ROB it comes back head-only); its committed SQ entry is
//   then freed without a second access.
// D$: 2-way, 32-byte lines, write-back/write-allocate, FIFO replacement.
// Bus errors (bursts: exactly cmd_len read beats, one write ack, r_last on the
//   final beat): a refill with r_error leaves the line invalid and records it
//   (fe_*). A load that misses on the recorded line replays head-only; the
//   slow path refills it itself and takes a load access fault if that refill
//   fails. A committed store whose write-allocate refill failed is discarded,
//   and a failed write-back loses the line; both are reported on bus_err_*
//   (imprecise, see the SoC bus-error unit).
module o2_lsu #(
    parameter integer SETS = 256,
    parameter [31:0]  RAM_BASE = 32'h80000000,
    parameter integer RAM_BYTES = 131072
) (
    input  logic        clk, rst,
    // dispatch: SQ allocation
    input  logic [1:0]  sq_alloc,
    output logic [3:0]  sq_tail,          // {wrap, idx}
    output logic [3:0]  sq_count,
    output logic [7:0]  sq_valid,
    output logic [7:0]  sq_issued,
    output logic [7:0]  sq_free,          // pulse: entries freed this cycle
    output logic [1:0]  sq_room,          // registered: [0] >= 1 free, [1] >= 2 free (conservative)
    output logic        spec_ok,          // registered: load queue can take three more speculative loads
    output logic [31:0] md_viol,          // registered: ROB entries of loads that read stale data
    output logic        perf_ld_acc,      // a load reaches the D$ (normal pipe, RAM address)
    output logic        perf_ld_miss,     // a normal-pipe load missed the D$
    output logic        sq_empty,
    // issue from IQM (RR stage outputs, operands bypassed): EX stage inputs
    input  logic        ex_v,
    input  logic        ex_store,
    input  logic [2:0]  ex_op,            // funct3
    input  logic [31:0] ex_base, ex_sdata,
    input  logic [11:0] ex_imm,
    input  logic [5:0]  ex_pd,
    input  logic [4:0]  ex_rob,
    input  logic [2:0]  ex_sqidx,         // store: own entry; load: first younger store
    input  logic [7:0]  ex_sqm,           // load: older stores
    input  logic [7:0]  ex_brm,
    input  logic        ex_head,          // head-only (slow path)
    input  logic [2:0]  ex_slot,          // IQM slot (for ext_done)
    // completions
    output logic        st_done_v, output logic [4:0] st_done_rob,
    output logic        st_exc, output logic [3:0] st_cause, output logic [31:0] st_tval,
    output logic        st_replay,        // MMIO store: re-execute head-only
    // imprecise bus errors: committed store discarded / dirty line write-back failed
    output logic        bus_err_v, output logic bus_err_wb, output logic [31:0] bus_err_addr,
    output logic        ld_wb_v, output logic [5:0] ld_wb_pd, output logic [31:0] ld_wb_data,
    output logic        ld_done_v, output logic [4:0] ld_done_rob,
    output logic        ld_exc, output logic [3:0] ld_cause, output logic [31:0] ld_tval,
    output logic        ld_replay,
    output logic        ld_replay_io,
    output logic        ld_m_v, output logic [5:0] ld_m_pd,   // load in M (for bypass select)
    output logic [7:0]  ext_done,
    output logic        slow_busy,
    // commit
    input  logic [1:0]  sq_commit,        // stores committed this cycle (0..2)
    // recovery
    input  logic        flush,
    input  logic        br_kill, input logic [2:0] br_kill_tag, input logic [3:0] br_kill_sqtail,
    input  logic        br_ok, input logic [2:0] br_ok_tag,
    // maintenance: clean all dirty lines (FENCE.I / end of run)
    input  logic        clean_req, output logic clean_done,
    // MMIO port
    output logic        io_req_v, input logic io_req_rdy,
    output logic [31:0] io_addr, output logic io_write, output logic [3:0] io_be, output logic [31:0] io_wdata,
    input  logic        io_rsp_v, input logic [31:0] io_rdata, input logic io_rsp_err,
    // memory burst master
    output logic        cmd_valid, input logic cmd_ready,
    output logic        cmd_write, output logic [31:0] cmd_addr, output logic [7:0] cmd_len,
    output logic        w_valid, input logic w_ready, output logic [31:0] w_data,
    output logic [3:0]  w_be, output logic w_last,
    input  logic        r_valid, output logic r_ready, input logic [31:0] r_data,
    input  logic        r_error, r_last
);
`include "o2_util.vh"
    localparam integer SB = $clog2(SETS);
    localparam integer RAB = $clog2(RAM_BYTES);
    localparam integer TB = RAB - 5 - SB;
    localparam integer WB = SB + 3;              // word index bits per way

    function automatic logic in_ram(input logic [31:0] a);
        in_ram = (a & ~(RAM_BYTES - 1)) == RAM_BASE;
    endfunction

    // =========================================================== cache arrays
    (* syn_ramstyle = "lut_ram" *) logic [TB-1:0] tagL0 [0:SETS-1];   // load lookup copy
    (* syn_ramstyle = "lut_ram" *) logic [TB-1:0] tagL1 [0:SETS-1];
    (* syn_ramstyle = "lut_ram" *) logic [TB-1:0] tagS0 [0:SETS-1];   // store / refill copy
    (* syn_ramstyle = "lut_ram" *) logic [TB-1:0] tagS1 [0:SETS-1];
    // valid / dirty / victim bits: LUT-RAM bit arrays, 4 read copies each
    //   read port 0: load EX, 1: drain D0, 2: refill/clean, 3: slow path
    logic m_we_v0, m_we_v1, m_we_d0, m_we_d1, m_we_vt;
    logic m_wd_v0, m_wd_v1, m_wd_d0, m_wd_d1, m_wd_vt;
    logic [SB-1:0] m_wa_v, m_wa_d, m_wa_vt;
    logic [4*SB-1:0] m_ra;
    logic [3:0] rv0, rv1, rd0, rd1, rvt;
    o2_bitram #(.DEPTH(SETS), .AW(SB), .NR(4)) mv0 (.clk(clk), .we(m_we_v0), .wa(m_wa_v), .wd(m_wd_v0), .ra(m_ra), .rd(rv0));
    o2_bitram #(.DEPTH(SETS), .AW(SB), .NR(4)) mv1 (.clk(clk), .we(m_we_v1), .wa(m_wa_v), .wd(m_wd_v1), .ra(m_ra), .rd(rv1));
    o2_bitram #(.DEPTH(SETS), .AW(SB), .NR(4)) md0 (.clk(clk), .we(m_we_d0), .wa(m_wa_d), .wd(m_wd_d0), .ra(m_ra), .rd(rd0));
    o2_bitram #(.DEPTH(SETS), .AW(SB), .NR(4)) md1 (.clk(clk), .we(m_we_d1), .wa(m_wa_d), .wd(m_wd_d1), .ra(m_ra), .rd(rd1));
    o2_bitram #(.DEPTH(SETS), .AW(SB), .NR(4)) mvt (.clk(clk), .we(m_we_vt), .wa(m_wa_vt), .wd(m_wd_vt), .ra(m_ra), .rd(rvt));
    logic [SB:0] init_set;               // reset walk
    wire init_busy = !init_set[SB];
    logic [31:0] dat0 [0:SETS*8-1];
    logic [31:0] dat1 [0:SETS*8-1];
    // port A (loads)
    logic [WB-1:0] pa_addr;
    logic [31:0] qa0, qa1;
    always_ff @(posedge clk) begin
        qa0 <= dat0[pa_addr]; qa1 <= dat1[pa_addr];
    end
    // port B (store write, refill write, writeback read)
    logic pb_we0, pb_we1; logic [WB-1:0] pb_addr; logic [31:0] pb_wdata; logic [3:0] pb_be;
    logic [31:0] qb0, qb1;
    always_ff @(posedge clk) begin
        for (int b = 0; b < 4; b++) begin
            if (pb_we0 && pb_be[b]) dat0[pb_addr][8*b +: 8] <= pb_wdata[8*b +: 8];
            if (pb_we1 && pb_be[b]) dat1[pb_addr][8*b +: 8] <= pb_wdata[8*b +: 8];
        end
        qb0 <= dat0[pb_addr]; qb1 <= dat1[pb_addr];
    end
    logic tag_we0, tag_we1; logic [SB-1:0] tag_wset; logic [TB-1:0] tag_wdata;
    always_ff @(posedge clk) begin
        if (tag_we0) begin tagL0[tag_wset] <= tag_wdata; tagS0[tag_wset] <= tag_wdata; end
        if (tag_we1) begin tagL1[tag_wset] <= tag_wdata; tagS1[tag_wset] <= tag_wdata; end
    end

    // =========================================================== store queue
    logic [7:0] sv, sa, scm;              // valid, address issued, committed
    logic [31:0] s_addr [0:7], s_data [0:7];
    logic [3:0] s_be [0:7];
    logic [7:0] s_io;
    logic [3:0] s_head, s_tail, s_cmt;    // {wrap, idx}
    assign sq_tail = s_tail;
    assign sq_count = s_tail - s_head;
    assign sq_valid = sv;
    assign sq_issued = sa;
    assign sq_empty = sq_count == 4'd0;
    // frees during this cycle are seen one cycle late (conservative)
    wire [3:0] sq_cnt_n = s_tail + {2'b0, sq_alloc} - s_head;
    always_ff @(posedge clk) begin
        if (rst) sq_room <= 2'b11;
        else sq_room <= {sq_cnt_n <= 4'd6, sq_cnt_n <= 4'd7};
    end

    // =========================================================== refill engine
    localparam [2:0] R_IDLE = 3'd0, R_WBCMD = 3'd1, R_WBDATA = 3'd2, R_WBACK = 3'd3,
                     R_FCMD = 3'd4, R_FDATA = 3'd5, R_CLEAN = 3'd6;
    logic [2:0] rstate;
    logic [31:0] r_line;                  // line being filled
    logic r_way;
    logic [3:0] r_beat;
    logic [31:0] r_wbaddr;
    logic r_fill_req; logic [31:0] r_fill_addr;
    logic r_clean_mode; logic [SB:0] r_cset; logic r_cway;
    logic r_ferr;                         // an earlier beat of this refill had r_error
    wire rbusy = rstate != R_IDLE || !init_set[SB];
    // line (index within the RAM window) whose latest refill failed
    logic fe_v; logic [RAB-6:0] fe_line;

    // =========================================================== load pipe: EX
    wire [31:0] ex_addr = ex_base + {{20{ex_imm[11]}}, ex_imm};
    wire [1:0] ex_sz = ex_op[1:0];
    wire ex_mis = (ex_sz == 2'd1 && ex_addr[0]) || (ex_sz == 2'd2 && ex_addr[1:0] != 2'b00);
    wire ex_ram = in_ram(ex_addr);
    wire ex_io = !ex_addr[31];
    wire ex_acc = !ex_ram && !ex_io;
    wire ex_kill = flush || (br_kill && ex_brm[br_kill_tag]);
    // cache lookups use their own low-order adder (the full address adder's
    // outputs fan out to the SQ compares, SQ writes and exception paths)
    wire [WB+1:0] ex_lidx = ex_base[WB+1:0] + {{(WB-10){ex_imm[11]}}, ex_imm};
    wire [SB-1:0] ex_set = ex_lidx[5 +: SB];
    wire [TB-1:0] ex_tag = ex_addr[5 + SB +: TB];
    wire [3:0] ex_lbe = (ex_sz == 2'd0) ? (4'b0001 << ex_addr[1:0]) :
                        (ex_sz == 2'd1) ? (4'b0011 << ex_addr[1:0]) : 4'b1111;
    // store: write SQ entry; a normal store completes here, a head-only one
    // completes through the slow path
    wire ex_st = ex_v && ex_store && !ex_kill;
    wire ex_ld = ex_v && !ex_store && !ex_kill && !ex_head;
    wire ex_slow = ex_v && !ex_kill && ex_head;
    // store-to-load forwarding, EX part: per SQ entry, an older store whose
    // word and bytes overlap the load (e_vm) and whether it covers all load
    // bytes (e_cov). A load overlapping more than one older store replays
    // (none in CoreMark), so M only needs the single matching entry.
    logic [7:0] e_vm, e_cov;
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            e_vm[i] = ex_sqm[i] && sv[i] && sa[i] && s_addr[i][31:2] == ex_addr[31:2] && |(s_be[i] & ex_lbe);
            e_cov[i] = (s_be[i] & ex_lbe) == ex_lbe;
        end
    end

    // =========================================================== load pipe: M
    logic m_v, m_hit0, m_hit1, m_exc, m_replay, m_sign, m_io;
    logic [3:0] m_cause; logic [31:0] m_addr; logic [1:0] m_sz; logic [3:0] m_lbe;
    logic [5:0] m_pd; logic [4:0] m_rob; logic [7:0] m_sqm; logic [2:0] m_sqpos; logic [7:0] m_brm;
    logic [7:0] m_vm, m_cov;
    always_ff @(posedge clk) begin
        if (rst) m_v <= 1'b0;
        else m_v <= ex_ld;
        m_hit0 <= rv0[0] && tagL0[ex_set] == ex_tag;
        m_hit1 <= rv1[0] && tagL1[ex_set] == ex_tag;
        m_exc <= ex_mis || ex_acc;
        m_cause <= ex_mis ? 4'd4 : 4'd5;
        m_replay <= ex_io || rbusy;
        m_io <= ex_io;
        m_addr <= ex_addr; m_sz <= ex_sz; m_sign <= !ex_op[2]; m_lbe <= ex_lbe;
        m_pd <= ex_pd; m_rob <= ex_rob; m_sqm <= ex_sqm & ~sq_free; m_sqpos <= ex_sqidx;
        // a branch resolving correctly this cycle frees its tag (it may be reused)
        m_brm <= br_ok ? (ex_brm & ~(8'b1 << br_ok_tag)) : ex_brm;
        // a drained entry keeps its data until reallocated, so a match that
        // drains during M still forwards the right bytes
        m_vm <= e_vm & ~sq_free; m_cov <= e_cov;
    end
    // the slow path's RAM lookup borrows port A: the core issues no IQM op
    // from a head-only op's RR stage until the slow path is idle again
    assign pa_addr = (lstate == L_LOOK) ? l_addr[2 +: WB] : ex_lidx[2 +: WB];
    wire m_kill = flush || (br_kill && m_brm[br_kill_tag]);
    // the load's line had a failed refill: replay it head-only, so the slow
    // path can turn a repeated failure into a precise access fault
    wire m_ferr = fe_v && m_addr[RAB-1:5] == fe_line;
    // store-to-load forwarding, M part: the single matching older store
    logic fwd_any, fwd_hit, fwd_partial; logic [31:0] fwd_data;
    always_comb begin
        fwd_data = 32'b0;
        for (int e = 0; e < 8; e++) fwd_data = fwd_data | ({32{m_vm[e]}} & s_data[e]);
        fwd_any = |m_vm;
        fwd_hit = |(m_vm & m_cov);
        // several matches (or one not covering the load) -> replay
        fwd_partial = |(m_vm & ~m_cov) || (m_vm & (m_vm - 8'd1)) != 8'b0;
    end
    // =========================================================== load queue (speculative loads)
    // A load that executed while an older store had not issued is recorded
    // until every older store has issued; an executing store that overlaps a
    // recorded younger load (or the load in M) marks that load for replay.
    logic [7:0] lq_v; logic [4:0] lq_rob [0:7]; logic [29:0] lq_addr [0:7]; logic [3:0] lq_be [0:7];
    logic [7:0] lq_sqm [0:7]; logic [7:0] lq_brm [0:7];
    wire m_spec = |(m_sqm & ~sa);                           // an older store has not issued
    wire [7:0] lq_free = ~lq_v;
    wire [7:0] lq_aoh = lq_free & (~lq_free + 8'd1);
    wire lq_alloc = m_live && m_spec && !m_exc && m_ok;     // replays are not recorded
    // store in EX against recorded loads and the load in M
    logic [7:0] lq_hit; logic m_hit_st;
    always_comb begin
        for (int i = 0; i < 8; i++)
            lq_hit[i] = ex_st && lq_v[i] && lq_sqm[i][ex_sqidx] && lq_addr[i] == ex_addr[31:2] && |(lq_be[i] & ex_lbe);
        m_hit_st = ex_st && m_v && !m_kill && m_sqm[ex_sqidx] && m_addr[31:2] == ex_addr[31:2] && |(m_lbe & ex_lbe);
    end
    always_ff @(posedge clk) begin
        if (rst) begin lq_v <= 8'b0; md_viol <= 32'b0; spec_ok <= 1'b1; end
        else begin
            logic [31:0] vm;
            vm = 32'b0;
            for (int i = 0; i < 8; i++) if (lq_hit[i]) vm[lq_rob[i]] = 1'b1;
            if (m_hit_st) vm[m_rob] = 1'b1;
            md_viol <= flush ? 32'b0 : vm;
            for (int i = 0; i < 8; i++) begin
                logic [7:0] nsq;
                nsq = lq_sqm[i] & ~sq_free;
                lq_sqm[i] <= nsq;
                if (br_ok) lq_brm[i][br_ok_tag] <= 1'b0;
                // done once all older stores have issued, or killed
                if (flush || (br_kill && lq_brm[i][br_kill_tag]) || (nsq & ~sa) == 8'b0) lq_v[i] <= 1'b0;
                if (lq_alloc && lq_aoh[i] && !flush && !(br_kill && m_brm[br_kill_tag])) begin
                    lq_v[i] <= 1'b1; lq_rob[i] <= m_rob; lq_addr[i] <= m_addr[31:2]; lq_be[i] <= m_lbe;
                    lq_sqm[i] <= m_sqm & ~sq_free; lq_brm[i] <= br_ok ? (m_brm & ~(8'b1 << br_ok_tag)) : m_brm;
                end
            end
            // room for the loads that may be in RR / EX / M
            spec_ok <= popc8(lq_free) >= 4'd4;
        end
    end
    // a partial match replays, so its data value does not matter
    wire [31:0] m_word = fwd_any ? fwd_data : (m_hit1 ? qa1 : qa0);
    wire [31:0] m_shift = m_word >> {m_addr[1:0], 3'b000};
    wire [31:0] m_val = (m_sz == 2'd0) ? {{24{m_sign && m_shift[7]}}, m_shift[7:0]} :
                        (m_sz == 2'd1) ? {{16{m_sign && m_shift[15]}}, m_shift[15:0]} : m_shift;
    wire m_hit = m_hit0 || m_hit1;
    wire m_ok = !m_exc && !m_replay && !fwd_partial && (fwd_hit || m_hit) && !(m_spec && lq_v == 8'hff);
    wire m_live = m_v && !m_kill;
    // refill request from a normal-pipe miss (RAM only)
    // refill request: registered, independent of the forwarding result (a
    // forwarded load that also misses just prefetches its line)
    logic m_miss_q; logic [31:0] m_miss_addr_q;
    always_ff @(posedge clk) begin
        m_miss_q <= !rst && m_v && !m_kill && !m_exc && !m_replay && !m_hit;
        m_miss_addr_q <= m_addr;
    end
    wire m_miss_req = m_miss_q && !flush;
    assign ld_m_v = m_v; assign ld_m_pd = m_pd;
    assign perf_ld_acc = m_live && !m_io;
    assign perf_ld_miss = m_miss_q;

    // =========================================================== slow (head-only) path
    localparam [2:0] L_IDLE = 3'd0, L_WAIT = 3'd1, L_IOREQ = 3'd2, L_IORSP = 3'd3,
                     L_LOOK = 3'd4, L_CHK = 3'd5, L_DONE = 3'd6;
    logic [2:0] lstate;
    logic [31:0] l_addr; logic [1:0] l_sz; logic l_sign; logic [5:0] l_pd; logic [4:0] l_rob;
    logic [2:0] l_slot; logic l_exc; logic [3:0] l_cause; logic [31:0] l_data;
    logic l_store; logic [2:0] l_sq;      // head-only store and its SQ entry (data / byte enables)
    logic l_hit0, l_hit1;
    assign slow_busy = lstate != L_IDLE;
    wire l_ram = in_ram(l_addr);
    wire [31:0] l_shift = l_data >> {l_addr[1:0], 3'b000};
    wire [31:0] l_val = (l_sz == 2'd0) ? {{24{l_sign && l_shift[7]}}, l_shift[7:0]} :
                        (l_sz == 2'd1) ? {{16{l_sign && l_shift[15]}}, l_shift[15:0]} : l_shift;

    // =========================================================== store drain
    // D0: oldest committed entry -> tag lookup (registered); D1: write port B.
    logic d1_v, d1_hit0, d1_hit1, d1_ferr;
    logic [2:0] d1_idx;
    // RAM stores drain one per cycle: dptr runs ahead of the head over
    // entries in D1 / waiting to be freed; a D1 miss rewinds it
    wire [2:0] sh = s_head[2:0];
    logic [2:0] dptr;
    wire drain_cand = sv[dptr] && scm[dptr] && !s_io[dptr];
    wire [SB-1:0] dset = s_addr[dptr][5 +: SB];
    wire [TB-1:0] dtag = s_addr[dptr][5 + SB +: TB];
    logic d_free_pend; logic [2:0] d_free_idx;
    // freed in the same cycle its valid bit clears: a mask bit cleared one
    // cycle late could hit a store that has just reallocated the entry
    assign sq_free = d_free_pend ? (8'b1 << d_free_idx) : 8'b0;
    // L_WAIT waits for committed stores to empty. Keep their drains enabled
    // until that condition is met; otherwise the slow op and SQ wait on each other.
    wire drain_go = drain_cand && (!d1_v || d1_hit0 || d1_hit1) && !rbusy && !r_fill_req &&
                    (lstate == L_IDLE || lstate == L_WAIT);
    // a committed MMIO store was already performed by the slow path: free its
    // entry, in order, without an access
    wire io_skip = sv[sh] && scm[sh] && s_io[sh] && dptr == sh && !d1_v && !d_free_pend;

    // =========================================================== metadata ports
    wire [SB-1:0] fs_set = r_fill_addr[5 +: SB];
    wire [SB-1:0] rl_set = r_line[5 +: SB];
    wire [SB-1:0] d1_set = s_addr[d1_idx][5 +: SB];
    wire refill_start = rstate == R_IDLE && !(clean_req && !r_clean_mode) && r_fill_req && !d1_v &&
        !((rv0[2] && tagS0[fs_set] == r_fill_addr[5 + SB +: TB]) || (rv1[2] && tagS1[fs_set] == r_fill_addr[5 + SB +: TB]));
    wire refill_way = !rv0[2] ? 1'b0 : !rv1[2] ? 1'b1 : rvt[2];
    wire fill_last = rstate == R_FDATA && r_valid && r_beat == 4'd7;
    wire fill_ok = !r_ferr && !r_error;   // with fill_last: install the line
    always_comb begin
        m_ra = {l_addr[5 +: SB], (rstate == R_CLEAN) ? r_cset[SB-1:0] : fs_set, dset, ex_set};
        // valid bits
        m_we_v0 = 1'b0; m_we_v1 = 1'b0; m_wd_v0 = 1'b0; m_wd_v1 = 1'b0; m_wa_v = fs_set;
        if (init_busy) begin m_we_v0 = 1'b1; m_we_v1 = 1'b1; m_wa_v = init_set[SB-1:0]; end
        else if (fill_last) begin m_wa_v = rl_set; m_we_v0 = !r_way; m_we_v1 = r_way; m_wd_v0 = fill_ok; m_wd_v1 = fill_ok; end
        else if (refill_start) begin m_wa_v = fs_set; m_we_v0 = !refill_way; m_we_v1 = refill_way; end
        // dirty bits
        m_we_d0 = 1'b0; m_we_d1 = 1'b0; m_wd_d0 = 1'b0; m_wd_d1 = 1'b0; m_wa_d = rl_set;
        if (init_busy) begin m_we_d0 = 1'b1; m_we_d1 = 1'b1; m_wa_d = init_set[SB-1:0]; end
        else if (fill_last || (rstate == R_WBACK && r_valid)) begin m_wa_d = rl_set; m_we_d0 = !r_way; m_we_d1 = r_way; end
        else if (d1_v && (d1_hit0 || d1_hit1)) begin
            m_wa_d = d1_set; m_we_d0 = d1_hit0; m_we_d1 = d1_hit1; m_wd_d0 = 1'b1; m_wd_d1 = 1'b1;
        end
        // victim bits
        m_we_vt = init_busy || fill_last; m_wa_vt = init_busy ? init_set[SB-1:0] : rl_set; m_wd_vt = init_busy ? 1'b0 : !r_way;
    end

    // =========================================================== outputs: completions
    always_comb begin
        st_done_v = ex_st && !ex_head; st_done_rob = ex_rob;
        st_exc = ex_mis || ex_acc; st_cause = ex_mis ? `EXC_SADDR_MIS : `EXC_SACCESS; st_tval = ex_addr;
        st_replay = ex_io && !ex_mis;
        // normal load completion in M, or slow completion (loads and stores)
        ld_done_v = 1'b0; ld_done_rob = m_rob; ld_exc = 1'b0; ld_cause = m_cause; ld_tval = m_addr;
        ld_replay = 1'b0; ld_wb_v = 1'b0; ld_wb_pd = m_pd; ld_wb_data = m_val; ld_replay_io = m_io || m_ferr;
        ext_done = 8'b0;
        if (m_live) begin
            ld_done_v = 1'b1;
            ld_exc = m_exc;
            ld_replay = !m_exc && !m_ok;
            // written back even when it will replay or trap: either flushes
            // all younger instructions, so the value is never consumed
            ld_wb_v = 1'b1;
        end else if (lstate == L_DONE && !m_live) begin
            ld_done_v = 1'b1; ld_done_rob = l_rob; ld_exc = l_exc; ld_cause = l_cause; ld_tval = l_addr;
            ld_wb_v = !l_exc && !l_store; ld_wb_pd = l_pd; ld_wb_data = l_val;
            ext_done[l_slot] = 1'b1;
        end
    end

    // =========================================================== MMIO port (slow path only)
    assign io_req_v = lstate == L_IOREQ;
    assign io_addr = {l_addr[31:2], 2'b00};
    assign io_write = l_store;
    assign io_be = l_store ? s_be[l_sq] : 4'hf;
    assign io_wdata = s_data[l_sq];

    // =========================================================== port B / tag write muxing
    always_comb begin
        pb_we0 = 1'b0; pb_we1 = 1'b0; pb_addr = {s_addr[d1_idx][5 +: SB], s_addr[d1_idx][4:2]};
        pb_wdata = s_data[d1_idx]; pb_be = s_be[d1_idx];
        tag_we0 = 1'b0; tag_we1 = 1'b0; tag_wset = r_line[5 +: SB]; tag_wdata = r_line[5 + SB +: TB];
        if (rstate == R_FDATA) begin
            pb_addr = {r_line[5 +: SB], r_beat[2:0]}; pb_wdata = r_data; pb_be = 4'hf;
            pb_we0 = r_valid && !r_way; pb_we1 = r_valid && r_way;
            if (r_valid && r_beat == 4'd7) begin tag_we0 = !r_way; tag_we1 = r_way; end
        end else if (rstate == R_WBCMD) begin
            pb_addr = {r_line[5 +: SB], 3'd0};
        end else if (rstate == R_WBDATA) begin
            pb_addr = {r_line[5 +: SB], w_ready ? r_beat[2:0] : r_beat[2:0] - 3'd1};
        end else if (rstate == R_CLEAN) begin
            pb_addr = {r_cset[SB-1:0], 3'b000};
        end else if (d1_v && (d1_hit0 || d1_hit1)) begin
            pb_we0 = d1_hit0; pb_we1 = d1_hit1;
        end
    end
    assign cmd_valid = rstate == R_WBCMD || rstate == R_FCMD;
    assign cmd_write = rstate == R_WBCMD;
    assign cmd_addr = rstate == R_WBCMD ? r_wbaddr : {r_line[31:5], 5'b0};
    assign cmd_len = 8'd8;
    assign w_valid = rstate == R_WBDATA;
    assign w_data = r_way ? qb1 : qb0;
    assign w_be = 4'hf;
    assign w_last = r_beat == 4'd8;
    assign r_ready = rstate == R_FDATA || rstate == R_WBACK;

    // =========================================================== sequential
    wire [3:0] kill_tail = br_kill_sqtail;
    always_ff @(posedge clk) begin
        if (rst) begin
            sv <= 8'b0; sa <= 8'b0; scm <= 8'b0; s_head <= 4'd0; s_tail <= 4'd0; s_cmt <= 4'd0;
            d1_v <= 1'b0; d_free_pend <= 1'b0; dptr <= 3'd0;
            rstate <= R_CLEAN; r_clean_mode <= 1'b0; r_cset <= '0; r_cway <= 1'b0; r_beat <= 4'd0;
            r_ferr <= 1'b0; fe_v <= 1'b0; bus_err_v <= 1'b0;
            lstate <= L_IDLE; init_set <= '0;
            r_fill_req <= 1'b0; clean_done <= 1'b0;
        end else begin
            clean_done <= 1'b0;
            bus_err_v <= 1'b0;
            if (init_busy) init_set <= init_set + 1'b1;
            // ---------------- SQ allocate / kill
            begin
                logic [3:0] nt; logic [7:0] nv;
                nt = s_tail; nv = sv;
                if (flush) begin
                    for (int i = 0; i < 8; i++) if (!scm[i]) nv[i] = 1'b0;
                    nt = s_cmt;
                end else if (br_kill) begin
                    for (int i = 0; i < 8; i++) begin
                        logic [2:0] off; logic [3:0] cnt;
                        off = 3'(i) - kill_tail[2:0];
                        cnt = s_tail - kill_tail;
                        // entries from kill_tail up to the old tail are younger than the branch
                        if ({1'b0, off} < cnt && !scm[i]) nv[i] = 1'b0;
                    end
                    nt = kill_tail;
                end else begin
                    if (sq_alloc != 2'd0) begin
                        nv[s_tail[2:0]] = 1'b1;
                        if (sq_alloc == 2'd2) nv[s_tail[2:0] + 3'd1] = 1'b1;
                        nt = s_tail + {2'b0, sq_alloc};
                    end
                end
                // ---------------- free after drain
                if (d_free_pend) begin nv[d_free_idx] = 1'b0; end
                sv <= nv; s_tail <= nt;
                for (int i = 0; i < 8; i++) if (!nv[i]) begin sa[i] <= 1'b0; scm[i] <= 1'b0; end
            end
            if (d_free_pend) begin
                s_head <= s_head + 4'd1;
                d_free_pend <= 1'b0;
            end
            // ---------------- store issue
            if (ex_st) begin
                sa[ex_sqidx] <= 1'b1;
                s_addr[ex_sqidx] <= ex_addr;
                s_data[ex_sqidx] <= ex_sdata << {ex_addr[1:0], 3'b000};
                s_be[ex_sqidx] <= ex_lbe;
                s_io[ex_sqidx] <= ex_io;
            end
            // ---------------- commit marks
            if (sq_commit != 2'd0) begin
                scm[s_cmt[2:0]] <= 1'b1;
                if (sq_commit == 2'd2) scm[s_cmt[2:0] + 3'd1] <= 1'b1;
                s_cmt <= s_cmt + {2'b0, sq_commit};
            end
            // ---------------- RAM drain pipeline
            d1_v <= 1'b0;
            if (drain_go) begin
                d1_v <= 1'b1; d1_idx <= dptr; dptr <= dptr + 3'd1;
                d1_hit0 <= rv0[1] && tagS0[dset] == dtag;
                d1_hit1 <= rv1[1] && tagS1[dset] == dtag;
                d1_ferr <= fe_v && {dtag, dset} == fe_line;
            end
            if (d1_v) begin
                if (d1_hit0 || d1_hit1) begin
                    d_free_pend <= 1'b1; d_free_idx <= d1_idx;
                end else if (d1_ferr) begin
                    // its line cannot be allocated: discard the store, report it;
                    // the next store to the line tries the refill again
                    d_free_pend <= 1'b1; d_free_idx <= d1_idx; fe_v <= 1'b0;
                    bus_err_v <= 1'b1; bus_err_wb <= 1'b0; bus_err_addr <= s_addr[d1_idx];
                end else begin
                    dptr <= d1_idx;            // retry after the refill
                    if (!r_fill_req && !rbusy) begin r_fill_req <= 1'b1; r_fill_addr <= s_addr[d1_idx]; end
                end
            end
            if (io_skip) begin d_free_pend <= 1'b1; d_free_idx <= sh; dptr <= sh + 3'd1; end
            // ---------------- refill requests from loads
            if (m_miss_req && !r_fill_req && !rbusy) begin r_fill_req <= 1'b1; r_fill_addr <= m_miss_addr_q; end
            // ---------------- refill engine
            case (rstate)
                R_IDLE: begin
                    if (clean_req && !r_clean_mode) begin
                        rstate <= R_CLEAN; r_clean_mode <= 1'b1; r_cset <= '0; r_cway <= 1'b0;
                    end else if (r_fill_req && !d1_v) begin
                        logic [SB-1:0] fs; logic w;
                        fs = r_fill_addr[5 +: SB];
                        r_fill_req <= 1'b0;
                        if (!((rv0[2] && tagS0[fs] == r_fill_addr[5 + SB +: TB]) ||
                              (rv1[2] && tagS1[fs] == r_fill_addr[5 + SB +: TB]))) begin
                            w = !rv0[2] ? 1'b0 : !rv1[2] ? 1'b1 : rvt[2];
                            r_line <= {r_fill_addr[31:5], 5'b0}; r_way <= w; r_beat <= 4'd0;
                            r_wbaddr <= {RAM_BASE[31:RAB], (w ? tagS1[fs] : tagS0[fs]), fs, 5'b0};
                            if (w ? (rv1[2] && rd1[2]) : (rv0[2] && rd0[2])) rstate <= R_WBCMD;
                            else rstate <= R_FCMD;
                        end
                    end
                end
                R_WBCMD: if (cmd_ready) begin rstate <= R_WBDATA; r_beat <= 4'd1; end
                R_WBDATA: if (w_ready) begin
                    if (r_beat == 4'd8) rstate <= R_WBACK;
                    r_beat <= r_beat + 4'd1;
                end
                R_WBACK: if (r_valid) begin
                    if (r_error) begin bus_err_v <= 1'b1; bus_err_wb <= 1'b1; bus_err_addr <= r_wbaddr; end
                    if (r_clean_mode) begin rstate <= R_CLEAN; end
                    else begin rstate <= R_FCMD; r_beat <= 4'd0; end
                end
                R_FCMD: if (cmd_ready) begin rstate <= R_FDATA; r_beat <= 4'd0; r_ferr <= 1'b0; end
                R_FDATA: if (r_valid) begin
                    r_beat <= r_beat + 4'd1;
                    r_ferr <= r_ferr || r_error;
                    if (r_beat == 4'd7) begin
                        rstate <= R_IDLE;
                        if (!fill_ok) begin fe_v <= 1'b1; fe_line <= r_line[RAB-1:5]; end
                        else if (r_line[RAB-1:5] == fe_line) fe_v <= 1'b0;
                    end
                end
                R_CLEAN: begin
                    // walk sets/ways; write back dirty lines (reset walk: just exit)
                    logic [SB-1:0] cs;
                    cs = r_cset[SB-1:0];
                    if (!r_clean_mode) begin
                        rstate <= R_IDLE;
                    end else if (r_cset[SB]) begin
                        rstate <= R_IDLE; r_clean_mode <= 1'b0; clean_done <= 1'b1;
                    end else if (r_cway ? (rv1[2] && rd1[2]) : (rv0[2] && rd0[2])) begin
                        r_way <= r_cway; r_line <= {RAM_BASE[31:RAB], (r_cway ? tagS1[cs] : tagS0[cs]), cs, 5'b0};
                        r_wbaddr <= {RAM_BASE[31:RAB], (r_cway ? tagS1[cs] : tagS0[cs]), cs, 5'b0};
                        r_beat <= 4'd0; rstate <= R_WBCMD;
                        // continue with the next way/set after writeback
                        r_cway <= !r_cway; if (r_cway) r_cset <= r_cset + 1'b1;
                    end else begin
                        r_cway <= !r_cway; if (r_cway) r_cset <= r_cset + 1'b1;
                    end
                end
                default: rstate <= R_IDLE;
            endcase
            // ---------------- slow path
            // a refill of the waiting load's line failed: precise load access fault
            if (fill_last && !fill_ok && lstate == L_WAIT && !l_store && l_ram && r_line[RAB-1:5] == l_addr[RAB-1:5]) begin
                l_exc <= 1'b1; l_cause <= `EXC_LACCESS;
            end
            case (lstate)
                L_IDLE: if (ex_slow) begin
                    lstate <= L_WAIT; l_addr <= ex_addr; l_sz <= ex_sz; l_sign <= !ex_op[2];
                    l_pd <= ex_pd; l_rob <= ex_rob; l_slot <= ex_slot; l_store <= ex_store; l_sq <= ex_sqidx;
                    l_exc <= ex_mis || ex_acc;
                    l_cause <= ex_store ? (ex_mis ? `EXC_SADDR_MIS : `EXC_SACCESS) : (ex_mis ? `EXC_LADDR_MIS : `EXC_LACCESS);
                end
                L_WAIT: begin
                    // a RAM store just completes (its SQ entry drains after commit);
                    // MMIO accesses and RAM loads first wait for older stores
                    if (l_exc || (l_store && l_ram)) lstate <= L_DONE;
                    else if (((sv & scm) == 8'b0) && !rbusy && !d1_v && !d_free_pend && !r_fill_req)
                        lstate <= l_ram ? L_LOOK : L_IOREQ;
                end
                L_IOREQ: if (io_req_rdy) lstate <= L_IORSP;
                L_IORSP: if (io_rsp_v) begin
                    l_data <= io_rdata; l_exc <= io_rsp_err; l_cause <= l_store ? `EXC_SACCESS : `EXC_LACCESS;
                    lstate <= L_DONE;
                end
                L_LOOK: begin
                    l_hit0 <= rv0[3] && tagL0[l_addr[5 +: SB]] == l_addr[5 + SB +: TB];
                    l_hit1 <= rv1[3] && tagL1[l_addr[5 +: SB]] == l_addr[5 + SB +: TB];
                    lstate <= L_CHK;
                end
                L_CHK: begin
                    if (l_hit0 || l_hit1) begin l_data <= l_hit1 ? qa1 : qa0; lstate <= L_DONE; end
                    else begin
                        if (!r_fill_req && !rbusy) begin r_fill_req <= 1'b1; r_fill_addr <= l_addr; end
                        lstate <= L_WAIT;
                    end
                end
                L_DONE: if (!m_live) lstate <= L_IDLE;
                default: lstate <= L_IDLE;
            endcase
            if (flush && lstate != L_IORSP && lstate != L_IOREQ) lstate <= L_IDLE;
        end
    end
`ifndef SYNTHESIS
    longint st_ld = 0, st_fwd1 = 0, st_fwdn = 0, st_part = 0;
    always_ff @(posedge clk) if (!rst && m_live) begin
        st_ld <= st_ld + 1;
        if ($countones(m_vm) == 1) st_fwd1 <= st_fwd1 + 1;
        if ($countones(m_vm) > 1) st_fwdn <= st_fwdn + 1;
        if (fwd_partial) st_part <= st_part + 1;
    end
    final $display("O2_LSU loads=%0d fwd1=%0d fwd_multi=%0d partial=%0d", st_ld, st_fwd1, st_fwdn, st_part);
    // bus contract and SQ invariants
    always_ff @(posedge clk) if (!rst) begin
        if (rstate == R_FDATA && r_valid)
            assert (r_last == (r_beat == 4'd7)) else $fatal(1, "DCACHE_R_LAST beat=%0d last=%b", r_beat, r_last);
        if (rstate == R_WBACK && r_valid)
            assert (r_last) else $fatal(1, "DCACHE_WBACK_R_LAST");
        // only the slow path may perform an MMIO store, so a committed MMIO
        // entry reaching the drain must not belong to a store that never ran
        if (io_skip) assert (sa[sh]) else $fatal(1, "LSU_IO_SKIP_UNISSUED");
        // a discarded store (D1) needs !rbusy two cycles earlier, so it never
        // coincides with a write-back acknowledgement: one bus_err_* event per cycle
        if (d1_v && !d1_hit0 && !d1_hit1 && d1_ferr)
            assert (!(rstate == R_WBACK && r_valid)) else $fatal(1, "LSU_BUS_ERR_COLLISION");
        // nothing else uses port A while the slow path looks up RAM
        if (lstate == L_LOOK) assert (!ex_ld) else $fatal(1, "LSU_PORT_A_CONFLICT");
    end
`endif
`ifdef DEBUG_LSU
    always_ff @(posedge clk) if (!rst) begin
        if (ex_st) $display("%0t ST_EX rob=%0d sq=%0d addr=%08x data=%08x be=%b io=%b", $time, ex_rob, ex_sqidx, ex_addr,
                             ex_sdata << {ex_addr[1:0], 3'b000}, ex_lbe, ex_io);
        if (m_live) $display("%0t LD_M rob=%0d addr=%08x hit=%b%b fwd=%b part=%b replay=%b exc=%b val=%08x sqm=%b vm=%b pos=%0d qa0=%08x qa1=%08x",
                             $time, m_rob, m_addr, m_hit0, m_hit1, fwd_hit, fwd_partial, m_replay, m_exc, m_val, m_sqm, m_vm, m_sqpos, qa0, qa1);
        if (d1_v) $display("%0t DRAIN idx=%0d addr=%08x data=%08x be=%b hit=%b%b", $time, d1_idx, s_addr[d1_idx], s_data[d1_idx],
                           s_be[d1_idx], d1_hit0, d1_hit1);
        if (lstate == L_DONE && !m_live) $display("%0t SLOW rob=%0d store=%b addr=%08x val=%08x exc=%b", $time, l_rob, l_store,
                                                  l_addr, l_val, l_exc);
        if (bus_err_v) $display("%0t BUS_ERR wb=%b addr=%08x", $time, bus_err_wb, bus_err_addr);
        if (rstate == R_FDATA && r_valid && r_beat == 4'd7) $display("%0t FILL line=%08x way=%b", $time, r_line, r_way);
        if (rstate == R_WBCMD && cmd_ready) $display("%0t WB line=%08x way=%b", $time, r_wbaddr, r_way);
        if (flush) $display("%0t LSU_FLUSH head=%0d cmt=%0d tail=%0d sv=%b scm=%b", $time, s_head, s_cmt, s_tail, sv, scm);
        if (sq_commit != 2'd0) $display("%0t SQ_COMMIT n=%0d cmt=%0d", $time, sq_commit, s_cmt);
        if (sq_alloc != 2'd0) $display("%0t SQ_ALLOC n=%0d tail=%0d flush=%b kill=%b", $time, sq_alloc, s_tail, flush, br_kill);
        if (br_kill) $display("%0t LSU_BRKILL tag=%0d sqtail=%0d", $time, br_kill_tag, br_kill_sqtail);
    end
`endif
endmodule
