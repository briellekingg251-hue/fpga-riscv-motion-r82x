// Original P2 implementation. Structural reference: lowRISC Ibex icache docs
// (synchronous lookup stage, allocation only after complete fill); no copied RTL.
module p2_cache #(
    parameter integer READ_ONLY=0, CACHE_BYTES=8192, LINE_BYTES=32,
    parameter [31:0] RAM_BASE=32'h80000000,
    parameter integer RAM_BYTES=131072, ENABLED=1, DC_LOAD_HIT_TURNOVER=0, STORE_PREDECODE=0
) (
    input wire clk, rst,
    input wire req_valid, output wire req_ready,
    input wire [31:0] req_addr, input wire req_write,
    input wire [3:0] req_be, input wire [31:0] req_wdata,
    output wire rsp_valid, input wire rsp_ready,
    output wire [31:0] rsp_rdata, output wire rsp_error,
    // I$ only: the word at req_addr+4, when it remains in the same line.
    // D$ instances always drive rsp_hi_valid low.
    output wire [31:0] rsp_data_hi, output wire rsp_hi_valid,
    output wire [6:0] rsp_predecode,rsp_predecode_hi,
    input wire maint_valid, output wire maint_ready,
    input wire maint_clean, maint_invalidate,
    output wire maint_done, output wire maint_error, output reg fatal,
    output wire cmd_valid, input wire cmd_ready, output wire cmd_write,
    output wire [31:0] cmd_addr, output wire [7:0] cmd_len,
    output wire w_valid, input wire w_ready, output wire [31:0] w_data,
    output wire [3:0] w_be, output wire w_last,
    input wire r_valid, output wire r_ready, input wire [31:0] r_data,
    input wire r_error, r_last,
    output reg [63:0] count_hit, count_miss, count_writeback
);
    localparam integer SETS=CACHE_BYTES/(2*LINE_BYTES);
    localparam integer WORDS=LINE_BYTES/4;
    localparam integer LB=$clog2(LINE_BYTES), SB=$clog2(SETS);
    localparam integer DB=$clog2(CACHE_BYTES/8);
    // Only lines entirely within this RAM region are cached. For an aligned
    // power-of-two region, upper address bits equal RAM_BASE and set/offset
    // bits are already supplied by the entry index. Keep only the remaining
    // variable tag bits; use full addresses for general region geometries.
    localparam integer RAM_AB=$clog2(RAM_BYTES);
    localparam integer COMPACT_TAGS=(RAM_BYTES>0 && (RAM_BYTES&(RAM_BYTES-1))==0 &&
        (RAM_BASE&(RAM_BYTES-1))==0 && RAM_AB>=LB+SB);
    localparam integer TAG_BITS=COMPACT_TAGS ? ((RAM_AB>LB+SB)?RAM_AB-LB-SB:1) : 32;
    localparam [7:0] LAST_BEAT=8'(WORDS-1), LINE_WORDS=8'(WORDS);
    localparam [SB-1:0] LAST_SET=SB'(SETS-1);
    localparam [4:0] IDLE=0, LOOKUP=1, RESPONSE=2, FILL_CMD=3,
      FILL_DATA=4, WB_CMD=5, WB_DATA=6, WB_ACK=7, BY_CMD=8,
      BY_DATA=9, BY_ACK=10, SCAN=11, SCAN_NEXT=12, M_DONE=13, HALT=14, STORE_REREAD=15, INIT_META=16;
    reg [4:0] state;
    // The D$ keeps its original one-read-port-per-way layout.  The I$ splits
    // each way into even/odd word banks, so a lookup at either word parity can
    // synchronously read PC and PC+4 with one read from each bank.  Refill and
    // the external bus remain one 32-bit word per beat.  No data array reset.
    // Keep each tag array in distributed RAM; lookup registers and the
    // existing read/write ordering are unchanged. Separate declarations keep
    // the standard synthesis attribute attached to each way through sv2v.
    (* syn_ramstyle = "lut_ram" *) reg [TAG_BITS-1:0] tag0 [0:SETS-1];
    (* syn_ramstyle = "lut_ram" *) reg [TAG_BITS-1:0] tag1 [0:SETS-1];
    // Reset is a bounded row walk, so metadata can use distributed RAM.
    (* syn_ramstyle = "lut_ram" *) reg valid0 [0:SETS-1];
    (* syn_ramstyle = "lut_ram" *) reg valid1 [0:SETS-1];
    (* syn_ramstyle = "lut_ram" *) reg dirty0 [0:SETS-1];
    (* syn_ramstyle = "lut_ram" *) reg dirty1 [0:SETS-1];
    (* syn_ramstyle = "lut_ram" *) reg replacement_mem [0:SETS-1];
    reg ram_re, ram_we0, ram_we1;
    reg [DB-1:0] ram_raddr, ram_waddr;
    reg [31:0] ram_wdata;
    reg [3:0] ram_be;
    reg [31:0] ram_q0, ram_q1, ram_q0_hi, ram_q1_hi;
    reg [6:0] ram_pre0,ram_pre1,ram_pre0_hi,ram_pre1_hi;
    // The same word write/read transports instruction and metadata atomically.
    function automatic [6:0] cache_predecode;
        input [31:0] insn;
        reg [6:0] op;reg [2:0] f3;reg [6:0] f7;
        begin
            op=insn[6:0];f3=insn[14:12];f7=insn[31:25];
            cache_predecode[0]=(op==7'h37||op==7'h17||
                (op==7'h13&&((f3!=3'b001&&f3!=3'b101)||(f3==3'b001&&f7==0)||(f3==3'b101&&(f7==0||f7==7'h20))))||
                (op==7'h33&&(f7==0||(f7==7'h20&&(f3==0||f3==5)))));
            cache_predecode[1]=(op==7'h37||op==7'h17||op==7'h13||op==7'h33||op==7'h03||op==7'h23||op==7'h63);
            cache_predecode[2]=(op!=7'h23&&op!=7'h63&&insn[11:7]!=0);
            cache_predecode[3]=(op==7'h13||op==7'h33||op==7'h63);
            cache_predecode[4]=(op==7'h33||op==7'h63);
            cache_predecode[5]=(op==7'h63)&&(f3[2]||(f3[2:1]==2'b00))&&!insn[8];
            cache_predecode[6]=(op==7'h63);
        end
    endfunction
    generate if (READ_ONLY != 0) begin : g_icache_banks
        reg [31:0] data0_even [0:SETS*WORDS/2-1];
        reg [31:0] data0_odd  [0:SETS*WORDS/2-1];
        reg [31:0] data1_even [0:SETS*WORDS/2-1];
        reg [31:0] data1_odd  [0:SETS*WORDS/2-1];
        wire [DB-2:0] low_bank_addr=ram_raddr[DB-1:1];
        wire [DB-2:0] high_even_addr=low_bank_addr+1'b1;
        wire next_in_line=ram_raddr[LB-3:0]!={(LB-2){1'b1}};
        always @(posedge clk) begin
            if (ram_re) begin
                if (!ram_raddr[0]) begin
                    ram_q0<=data0_even[low_bank_addr];
                    ram_q1<=data1_even[low_bank_addr];
                    ram_q0_hi<=data0_odd[low_bank_addr];
                    ram_q1_hi<=data1_odd[low_bank_addr];
                end else begin
                    ram_q0<=data0_odd[low_bank_addr];
                    ram_q1<=data1_odd[low_bank_addr];
                    if (next_in_line) begin
                        ram_q0_hi<=data0_even[high_even_addr];
                        ram_q1_hi<=data1_even[high_even_addr];
                    end
                end
            end
            // I$ has no stores: every fill beat writes a complete 32-bit
            // word. One write expression per bank lets PDS infer block RAM.
            if (ram_we0 && !ram_waddr[0]) data0_even[ram_waddr[DB-1:1]]<=ram_wdata;
            if (ram_we0 &&  ram_waddr[0]) data0_odd [ram_waddr[DB-1:1]]<=ram_wdata;
            if (ram_we1 && !ram_waddr[0]) data1_even[ram_waddr[DB-1:1]]<=ram_wdata;
            if (ram_we1 &&  ram_waddr[0]) data1_odd [ram_waddr[DB-1:1]]<=ram_wdata;
        end
    end else begin : g_dcache_banks
        reg [31:0] data0 [0:SETS*WORDS-1];
        reg [31:0] data1 [0:SETS*WORDS-1];
        integer lane_d;
        always @(posedge clk) begin
            if (ram_re) begin
                ram_q0<=data0[ram_raddr];
                ram_q1<=data1[ram_raddr];
            end
            for (lane_d=0;lane_d<4;lane_d=lane_d+1) begin
                if (ram_we0 && ram_be[lane_d]) data0[ram_waddr][8*lane_d+:8]<=ram_wdata[8*lane_d+:8];
                if (ram_we1 && ram_be[lane_d]) data1[ram_waddr][8*lane_d+:8]<=ram_wdata[8*lane_d+:8];
            end
        end
    end endgenerate

    // Independent metadata banks preserve the original 32-bit data RAM layout.
    // An 8-bit side word holds seven flags and one unused padding bit. The
    // mapper may remove the constant pad; its physical cost is measured.
    generate if (READ_ONLY!=0 && STORE_PREDECODE!=0) begin : g_predecode_banks
        reg [7:0] pre0_even [0:SETS*WORDS/2-1];
        reg [7:0] pre0_odd  [0:SETS*WORDS/2-1];
        reg [7:0] pre1_even [0:SETS*WORDS/2-1];
        reg [7:0] pre1_odd  [0:SETS*WORDS/2-1];
        wire [DB-2:0] low_bank_addr=ram_raddr[DB-1:1];
        wire [DB-2:0] high_even_addr=low_bank_addr+1'b1;
        wire next_in_line=ram_raddr[LB-3:0]!={(LB-2){1'b1}};
        always @(posedge clk) begin
            if (ram_re) begin
                if (!ram_raddr[0]) begin
                    ram_pre0<=pre0_even[low_bank_addr];
                    ram_pre1<=pre1_even[low_bank_addr];
                    ram_pre0_hi<=pre0_odd[low_bank_addr];
                    ram_pre1_hi<=pre1_odd[low_bank_addr];
                end else begin
                    ram_pre0<=pre0_odd[low_bank_addr];
                    ram_pre1<=pre1_odd[low_bank_addr];
                    if (next_in_line) begin
                        ram_pre0_hi<=pre0_even[high_even_addr];
                        ram_pre1_hi<=pre1_even[high_even_addr];
                    end
                end
            end
            if (ram_we0 && !ram_waddr[0]) pre0_even[ram_waddr[DB-1:1]]<={1'b0,cache_predecode(ram_wdata)};
            if (ram_we0 &&  ram_waddr[0]) pre0_odd [ram_waddr[DB-1:1]]<={1'b0,cache_predecode(ram_wdata)};
            if (ram_we1 && !ram_waddr[0]) pre1_even[ram_waddr[DB-1:1]]<={1'b0,cache_predecode(ram_wdata)};
            if (ram_we1 &&  ram_waddr[0]) pre1_odd [ram_waddr[DB-1:1]]<={1'b0,cache_predecode(ram_wdata)};
        end
    end endgenerate
    reg [31:0] rsp_rdata_q, rsp_data_hi_q;
    reg [6:0] rsp_pre_q,rsp_pre_hi_q;
    // A request logically clears response payloads. Keep this late acceptance
    // control on two bits, not the reset pins of 64 payload registers.
    reg rsp_lo_zero_q,rsp_hi_zero_q;
    wire [31:0] rsp_rdata_saved=rsp_lo_zero_q?32'b0:rsp_rdata_q;
    wire [31:0] rsp_data_hi_saved=rsp_hi_zero_q?32'b0:rsp_data_hi_q;
    reg rsp_hi_valid_q;
    reg rsp_error_q;
    // Provenance of the held RESPONSE payload; refill/bypass/error never set it.
    reg held_load_hit_q;
    reg [31:0] addr_q, wdata_q, wb_addr_q;
    reg write_q;
    reg [3:0] be_q;
    reg [7:0] beat;
    reg victim_way;
    reg [SB-1:0] victim_set, scan_set;
    reg scan_way, cleaning, invalidating, from_maint, fill_failed, maint_failed;
    wire [SB-1:0] set_q=addr_q[LB+:SB];
    wire [31:0] line_q=addr_q & ~(LINE_BYTES-1);
    wire [TAG_BITS-1:0] line_tag=COMPACT_TAGS ?
        ((RAM_AB==LB+SB)?32'b0:(addr_q>>(LB+SB))) : line_q;
    function automatic [31:0] restore_line;
        input [TAG_BITS-1:0] stored_tag;
        input [SB-1:0] stored_set;
        reg [31:0] tag_extended, set_extended;
        begin
            tag_extended=stored_tag; set_extended=stored_set;
            restore_line=COMPACT_TAGS ?
                (RAM_BASE | (tag_extended<<(LB+SB)) | (set_extended<<LB)) : tag_extended;
        end
    endfunction
    wire [7:0] word_q=8'(addr_q[2+:LB-2]);
    // Read tags/valid bits at the same request edge as the data RAM. This
    // removes the set-index mux from the response/turnover combinational path
    // without adding a lookup cycle. Tag/valid updates cannot overlap request
    // acceptance in this FSM. Snapshot replacement/dirty at the same edge.
    // Only a single-hit LOOKUP can both write replacement and accept a new
    // request; a same-set probe must see that write, not its old RAM value.
    reg lookup_hit0_q, lookup_hit1_q;
    reg lookup_valid0_q, lookup_valid1_q;
    reg lookup_replace_q, lookup_dirty0_q, lookup_dirty1_q;
    // Read-only probes may run before request acceptance. Their results are
    // consumed only in LOOKUP, reached solely after the real handshake; that
    // edge always samples the accepted address. Reading while stalled does
    // not allocate, modify tags, accept a request, or change any response.
    wire [SB-1:0] request_set=(state==STORE_REREAD)?set_q:req_addr[LB+:SB];
    // Compare the same probe address that supplies request_set. Valid snapshots
    // remain separate for invalid-way-first replacement selection.
    wire [31:0] request_probe_addr=(state==STORE_REREAD)?addr_q:req_addr;
    wire [TAG_BITS-1:0] request_probe_tag=COMPACT_TAGS ?
        ((RAM_AB==LB+SB)?32'b0:(request_probe_addr>>(LB+SB))) :
        (request_probe_addr & ~(LINE_BYTES-1));
    wire hit0=lookup_hit0_q;
    wire hit1=lookup_hit1_q;
    always @(posedge clk) begin
        if (rst) begin
            lookup_hit0_q<=0; lookup_hit1_q<=0;
            lookup_valid0_q<=0; lookup_valid1_q<=0;
            lookup_replace_q<=0; lookup_dirty0_q<=0; lookup_dirty1_q<=0;
        end else begin
            lookup_hit0_q<=valid0[request_set] && tag0[request_set]==request_probe_tag;
            lookup_hit1_q<=valid1[request_set] && tag1[request_set]==request_probe_tag;
            lookup_valid0_q<=valid0[request_set]; lookup_valid1_q<=valid1[request_set];
            lookup_dirty0_q<=dirty0[request_set]; lookup_dirty1_q<=dirty1[request_set];
            lookup_replace_q<=replacement_mem[request_set];
            if (state==LOOKUP && (hit0 ^ hit1) && request_set==set_q) begin
                lookup_replace_q<=hit0;
                // A same-set store may accept a different physical word here.
                // Forward only the written way; retain the other dirty bit.
                if (write_q) begin
                    if (hit0) lookup_dirty0_q<=1'b1;
                    if (hit1) lookup_dirty1_q<=1'b1;
                end
            end
        end
    end
    wire choose_way=!lookup_valid0_q ? 1'b0 : !lookup_valid1_q ? 1'b1 : lookup_replace_q;
    wire chosen_dirty,scan_valid,scan_dirty,fill_bad_now;
    reg [SB-1:0] meta_write_set;
    reg meta_v0_we,meta_v1_we,meta_d0_we,meta_d1_we;
    reg meta_valid_value,meta_dirty_value;
    always @* begin
        meta_write_set=victim_set;
        meta_v0_we=0;meta_v1_we=0;meta_d0_we=0;meta_d1_we=0;
        meta_valid_value=0;meta_dirty_value=0;
        case(state)
            INIT_META: begin
                meta_write_set=scan_set;
                meta_v0_we=1;meta_v1_we=1;meta_d0_we=1;meta_d1_we=1;
            end
            LOOKUP: begin
                meta_write_set=set_q;
                if(hit0^hit1) begin
                    meta_d0_we=write_q&&hit0;meta_d1_we=write_q&&hit1;
                    meta_dirty_value=1;
                end else if(!hit0&&!hit1&&!chosen_dirty) begin
                    meta_v0_we=!choose_way;meta_v1_we=choose_way;
                end
            end
            WB_ACK: if(r_valid&&!r_error&&r_last) begin
                meta_d0_we=!victim_way;meta_d1_we=victim_way;
                if(!from_maint||invalidating) begin
                    meta_v0_we=!victim_way;meta_v1_we=victim_way;
                end
            end
            FILL_DATA: if(r_valid&&beat==LAST_BEAT&&!(fill_failed||fill_bad_now)) begin
                meta_v0_we=!victim_way;meta_v1_we=victim_way;
                meta_d0_we=!victim_way;meta_d1_we=victim_way;
                meta_valid_value=1;meta_dirty_value=write_q;
            end
            SCAN: begin
                meta_write_set=scan_set;
                if(!(scan_valid&&scan_dirty&&(cleaning||invalidating))&&invalidating) begin
                    meta_v0_we=!scan_way;meta_v1_we=scan_way;
                end
            end
            default: begin end
        endcase
    end
    always @(posedge clk) if(!rst) begin
        if(meta_v0_we) valid0[meta_write_set]<=meta_valid_value;
        if(meta_v1_we) valid1[meta_write_set]<=meta_valid_value;
        if(meta_d0_we) dirty0[meta_write_set]<=meta_dirty_value;
        if(meta_d1_we) dirty1[meta_write_set]<=meta_dirty_value;
    end
`ifndef SYNTHESIS
    integer meta_init_rows=0,meta_init_completions=0,meta_init_index;
    reg meta_init_check_q;
    always @(posedge clk) begin
        if(rst) begin meta_init_rows<=0;meta_init_check_q<=1;end
        else if(state==INIT_META) begin
            assert(scan_set==meta_init_rows &&
                !{req_ready,rsp_valid,maint_ready,maint_done,cmd_valid,w_valid,r_ready})
                else $fatal(1,"META_INIT_BOUNDARY");
            meta_init_rows<=meta_init_rows+1;
        end else if(meta_init_check_q) begin
            assert(state==IDLE&&meta_init_rows==SETS) else $fatal(1,"META_INIT_LENGTH");
            for(meta_init_index=0;meta_init_index<SETS;meta_init_index=meta_init_index+1)
                assert({valid0[meta_init_index],valid1[meta_init_index],
                        dirty0[meta_init_index],dirty1[meta_init_index]}===4'b0)
                    else $fatal(1,"META_INIT_ROW_CONTENT");
            meta_init_check_q<=0;meta_init_completions<=meta_init_completions+1;
        end
    end
    final $display("META_INIT_COVER rows=%0d completed=%0d",meta_init_rows,meta_init_completions);
`endif

    assign chosen_dirty=choose_way ? lookup_dirty1_q : lookup_dirty0_q;
    // Entry into SCAN comes from IDLE (set zero) or SCAN_NEXT.
    // Read both ways before that edge, while retaining the existing two-cycle
    // scan sequence. No request or metadata write can overlap SCAN entry.
    wire [SB-1:0] scan_probe_set=(state==IDLE)?{SB{1'b0}}:
        ((state==SCAN_NEXT)&&scan_way)?(scan_set+1'b1):scan_set;
    reg scan_valid0_q,scan_valid1_q,scan_dirty0_q,scan_dirty1_q;
    always @(posedge clk) begin
        if(rst) begin
            scan_valid0_q<=0;scan_valid1_q<=0;scan_dirty0_q<=0;scan_dirty1_q<=0;
        end else begin
            scan_valid0_q<=valid0[scan_probe_set];scan_valid1_q<=valid1[scan_probe_set];
            scan_dirty0_q<=dirty0[scan_probe_set];scan_dirty1_q<=dirty1[scan_probe_set];
        end
    end
    assign scan_valid=scan_way?scan_valid1_q:scan_valid0_q;
    assign scan_dirty=scan_way?scan_dirty1_q:scan_dirty0_q;
`ifndef SYNTHESIS
    integer scan_meta_checks=0,scan_meta_dirty=0;
    always @(posedge clk) if(!rst&&state==SCAN) begin
        assert({scan_valid,scan_dirty}===
            {scan_way?valid1[scan_set]:valid0[scan_set],scan_way?dirty1[scan_set]:dirty0[scan_set]})
            else $fatal(1,"SCAN_META_LIVE_EQUIVALENCE");
        scan_meta_checks<=scan_meta_checks+1;
        if(scan_valid&&scan_dirty) scan_meta_dirty<=scan_meta_dirty+1;
    end
    final $display("SCAN_META_COVER checks=%0d dirty=%0d",scan_meta_checks,scan_meta_dirty);
`endif
    wire [32:0] req_ext={1'b0,req_addr};
    wire [32:0] limit_ext={1'b0,RAM_BASE}+RAM_BYTES;
    wire [31:0] req_line=req_addr & ~(LINE_BYTES-1);
    localparam integer BOUNDED_REGION=(RAM_BYTES>=LINE_BYTES)&&(LINE_BYTES>=4)&&
        ((RAM_BYTES&(RAM_BYTES-1))==0)&&((LINE_BYTES&(LINE_BYTES-1))==0)&&
        ((RAM_BASE&(RAM_BYTES-1))==0)&&
        (({1'b0,RAM_BASE}+RAM_BYTES)<=33'h100000000);
    wire word_in_ram,line_in_ram;
    generate if(BOUNDED_REGION) begin: bounded_region
        wire same_region=(req_addr&~(RAM_BYTES-1))==RAM_BASE;
        assign word_in_ram=same_region&&((req_addr&(RAM_BYTES-1))<=RAM_BYTES-4);
        assign line_in_ram=same_region;
    end else begin: generic_region
        assign word_in_ram=req_ext>={1'b0,RAM_BASE} && req_ext+33'd4<=limit_ext;
        assign line_in_ram={1'b0,req_line}>={1'b0,RAM_BASE} && {1'b0,req_line}+LINE_BYTES<=limit_ext;
    end endgenerate
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst&&req_valid) begin
        assert(word_in_ram===(req_ext>={1'b0,RAM_BASE}&&req_ext+33'd4<=limit_ext)&&
               line_in_ram===({1'b0,req_line}>={1'b0,RAM_BASE}&&{1'b0,req_line}+LINE_BYTES<=limit_ext))
            else $fatal(1,"CACHE_REGION_EQUIVALENCE");
    end
`endif
    assign fill_bad_now=r_error || (r_last != (beat==LAST_BEAT));
    wire replacement_hit_write=(state==LOOKUP)&&(hit0^hit1);
    wire replacement_fill_write=(state==FILL_DATA)&&r_valid&&(beat==LAST_BEAT)&&
        !(fill_failed||fill_bad_now);
    wire [SB-1:0] replacement_write_set=replacement_hit_write?set_q:victim_set;
    wire replacement_write_value=replacement_hit_write?hit0:!victim_way;
    always @(posedge clk) begin
        if(!rst&&(replacement_hit_write||replacement_fill_write))
            replacement_mem[replacement_write_set]<=replacement_write_value;
    end
`ifndef SYNTHESIS
    reg [SETS-1:0] replacement_reset_oracle;
    integer replacement_checked=0,replacement_index;
    always @(posedge clk) begin
        if(rst) replacement_reset_oracle<=0;
        else begin
            if(replacement_hit_write) replacement_reset_oracle[set_q]<=hit0;
            if(replacement_fill_write) replacement_reset_oracle[victim_set]<=!victim_way;
            for(replacement_index=0;replacement_index<SETS;replacement_index=replacement_index+1)
                if(state!=INIT_META&&valid0[replacement_index]&&valid1[replacement_index]) begin
                    replacement_checked=replacement_checked+1;
                    assert(replacement_mem[replacement_index]===replacement_reset_oracle[replacement_index])
                        else $fatal(1,"REPLACEMENT_VALID_ENTRY_IDENTITY");
                end
            if(state==LOOKUP)
                assert(choose_way===(!valid0[set_q]?1'b0:!valid1[set_q]?1'b1:replacement_reset_oracle[set_q]))
                    else $fatal(1,"REPLACEMENT_RESET_POLICY_IDENTITY");
        end
    end
    final $display("REPLACEMENT_RAM_COVER usable_entries=%0d",replacement_checked);
`endif

    // All hits use the registered output of the synchronous RAM read.
    // A D$ store writes bytes and marks dirty at the LOOKUP edge. With
    // backpressure it still writes once, then holds RESPONSE as before.
    // Optional D$ turnover uses the old load hit, or a direct store hit whose
    // response is accepted. Same-word collisions use a registered reread
    // before LOOKUP, including an alias under another tag/way.
    // Held store responses retain the original no-turnover behavior.
    // Its response edge can launch the next synchronous read without a write.
    // No request address-to-data bypass: a request edge precedes its LOOKUP.
    // The response is independent of ready; only replacement acceptance depends
    // on ready. Thus a stalled response never launches another RAM read.
    wire fast_hit=state==LOOKUP && (hit0 ^ hit1) && !fatal;
    wire read_only_turnover=(READ_ONLY!=0) && rsp_ready && (state==RESPONSE || fast_hit);
    wire direct_load_hit=fast_hit && !write_q;
    wire held_load_hit=(state==RESPONSE) && held_load_hit_q;
    wire d_load_turnover=(DC_LOAD_HIT_TURNOVER!=0) && (READ_ONLY==0) &&
        (direct_load_hit || held_load_hit) && rsp_valid && rsp_ready && !rsp_error;
    wire d_store_turnover=(DC_LOAD_HIT_TURNOVER!=0) && (READ_ONLY==0) &&
        fast_hit && write_q && rsp_ready;
    wire store_word_collision=d_store_turnover && (req_addr[2+:DB]==addr_q[2+:DB]);
    assign req_ready=(state==IDLE || read_only_turnover || d_load_turnover || d_store_turnover) && !maint_valid && !fatal && !rst;
    // Payload is meaningful only while rsp_valid is asserted. LOOKUP
    // preselects the way data even on a miss; rsp_valid/error still use the
    // complete hit/fatal qualification. RESPONSE uses the held snapshot.
    // This keeps the hit0/hit1 XOR out of the wide payload selection path.
    assign rsp_rdata=(state==LOOKUP) ? (hit1 ? ram_q1 : ram_q0) : rsp_rdata_saved;
    // LOOKUP is entered only by a legal acceptance, which sets error_q=0.
    // Other states already use error_q; no hit qualification is needed here.
    assign rsp_error=rsp_error_q;
    assign rsp_data_hi=(READ_ONLY!=0) ?
        ((state==LOOKUP) ? (hit1 ? ram_q1_hi : ram_q0_hi) : rsp_data_hi_saved) : 32'b0;
    assign rsp_predecode=(READ_ONLY!=0 && STORE_PREDECODE!=0)?
        ((state==LOOKUP)?(hit1?ram_pre1:ram_pre0):(rsp_lo_zero_q?7'b0:rsp_pre_q)):7'b0;
    assign rsp_predecode_hi=(READ_ONLY!=0 && STORE_PREDECODE!=0)?
        ((state==LOOKUP)?(hit1?ram_pre1_hi:ram_pre0_hi):(rsp_hi_zero_q?7'b0:rsp_pre_hi_q)):7'b0;
    assign rsp_hi_valid=(READ_ONLY!=0) && rsp_valid && !rsp_error &&
        (fast_hit ? (word_q!=LAST_BEAT) : rsp_hi_valid_q);
    assign maint_ready=state==IDLE && !fatal && !rst;
    assign rsp_valid=(state==RESPONSE || fast_hit) && !rst;
    assign maint_done=state==M_DONE && !rst;
    assign maint_error=maint_failed;
    assign cmd_valid=(state==FILL_CMD || state==WB_CMD || state==BY_CMD) && !rst;
    assign cmd_write=state==WB_CMD || (state==BY_CMD && write_q);
    assign cmd_addr=state==WB_CMD ? wb_addr_q : state==BY_CMD ? addr_q : line_q;
    assign cmd_len=state==BY_CMD ? 8'd1 : LINE_WORDS;
    assign w_valid=(state==WB_DATA || state==BY_DATA) && !rst;
    assign w_data=state==BY_DATA ? wdata_q : victim_way ? ram_q1 : ram_q0;
    assign w_be=state==BY_DATA ? be_q : 4'hf;
    assign w_last=state==BY_DATA || beat==LAST_BEAT;
    assign r_ready=(state==FILL_DATA || state==WB_ACK || state==BY_ACK) && !rst;
    // Exact same-edge diagnostic counts, split at 16-bit boundaries.
    // full_q[k] always equals &count[k*16+:16]; carry qualification is
    // registered, so no event traverses a 64-bit incrementer.
    wire count_hit_fire=(state==LOOKUP) && (hit0 ^ hit1);
    wire count_miss_fire=(state==LOOKUP) && !hit0 && !hit1;
    wire count_writeback_fire=(state==WB_ACK) && r_valid && !r_error && r_last;
    reg [2:0] count_hit_full_q,count_miss_full_q,count_writeback_full_q;
    genvar count_chunk;
    generate for(count_chunk=0;count_chunk<4;count_chunk=count_chunk+1) begin: segmented_counts
        wire hit_carry,miss_carry,writeback_carry;
        if(count_chunk==0) begin: low
            assign hit_carry=1'b1;
            assign miss_carry=1'b1;
            assign writeback_carry=1'b1;
        end else begin: high
            assign hit_carry=&count_hit_full_q[count_chunk-1:0];
            assign miss_carry=&count_miss_full_q[count_chunk-1:0];
            assign writeback_carry=&count_writeback_full_q[count_chunk-1:0];
        end
        always @(posedge clk) begin
            if(rst) begin
                count_hit[count_chunk*16+:16]<=0;
                count_miss[count_chunk*16+:16]<=0;
                count_writeback[count_chunk*16+:16]<=0;
            end else begin
                if(count_hit_fire && hit_carry)
                    count_hit[count_chunk*16+:16]<=count_hit[count_chunk*16+:16]+16'd1;
                if(count_miss_fire && miss_carry)
                    count_miss[count_chunk*16+:16]<=count_miss[count_chunk*16+:16]+16'd1;
                if(count_writeback_fire && writeback_carry)
                    count_writeback[count_chunk*16+:16]<=count_writeback[count_chunk*16+:16]+16'd1;
            end
        end
        if(count_chunk<3) begin: lookahead
            always @(posedge clk) begin
                if(rst) begin
                    count_hit_full_q[count_chunk]<=0;
                    count_miss_full_q[count_chunk]<=0;
                    count_writeback_full_q[count_chunk]<=0;
                end else begin
                    if(count_hit_fire && hit_carry)
                        count_hit_full_q[count_chunk]<=count_hit[count_chunk*16+:16]==16'hfffe;
                    if(count_miss_fire && miss_carry)
                        count_miss_full_q[count_chunk]<=count_miss[count_chunk*16+:16]==16'hfffe;
                    if(count_writeback_fire && writeback_carry)
                        count_writeback_full_q[count_chunk]<=count_writeback[count_chunk*16+:16]==16'hfffe;
                end
            end
        end
    end endgenerate
    function automatic [31:0] merge_word;
        input [31:0] old_data, new_data;
        input [3:0] mask;
        integer k;
        begin
            merge_word=old_data;
            for(k=0;k<4;k=k+1) if(mask[k]) merge_word[k*8+:8]=new_data[k*8+:8];
        end
    endfunction
    always @* begin
        ram_re=0; ram_raddr=0; ram_we0=0; ram_we1=0;
        ram_waddr=0; ram_wdata=0; ram_be=0;
        if (!rst) begin
            // Probe reads have no architectural side effect. During a miss /
            // writeback, only the existing FSM-controlled victim reads run.
            // LOOKUP consumes the previous edge's accepted-address data before
            // this probe updates RAM outputs; RESPONSE uses its held snapshot.
            if ((ENABLED!=0) && (state==IDLE || state==LOOKUP || state==RESPONSE)) begin
                ram_re=1; ram_raddr=req_addr[2+:DB];
            end
            // The collision edge's RAM outputs are never consumed. Read
            // the accepted address again after the old store has updated RAM.
            if ((READ_ONLY==0) && state==STORE_REREAD) begin
                ram_re=1;ram_raddr=addr_q[2+:DB];
            end
            if (state==LOOKUP && (hit0 ^ hit1) && write_q) begin
                ram_we0=hit0; ram_we1=hit1;
                ram_waddr=addr_q[2+:DB];
                ram_wdata=wdata_q; ram_be=be_q;
            end
            if (state==FILL_DATA && r_valid && r_ready) begin
                ram_we0=!victim_way; ram_we1=victim_way;
                ram_waddr={victim_set,beat[LB-3:0]};
                ram_wdata=(write_q && beat==word_q) ? merge_word(r_data,wdata_q,be_q) : r_data;
                ram_be=4'hf;
            end
            if (state==WB_CMD && cmd_ready) begin
                ram_re=1; ram_raddr={victim_set,{(LB-2){1'b0}}};
            end
            if (state==WB_DATA && w_ready && beat!=LAST_BEAT) begin
                ram_re=1; ram_raddr={victim_set,beat[LB-3:0]}+1'b1;
            end
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            state<=INIT_META;
            addr_q<=0; wdata_q<=0; be_q<=0; write_q<=0; wb_addr_q<=0;
            beat<=0; victim_way<=0; victim_set<=0; scan_set<=0; scan_way<=0;
            cleaning<=0; invalidating<=0; from_maint<=0; fill_failed<=0;
            maint_failed<=0; fatal<=0; rsp_rdata_q<=0; rsp_error_q<=0;
            if (READ_ONLY!=0 && STORE_PREDECODE!=0) begin rsp_pre_q<=0; rsp_pre_hi_q<=0; end
            rsp_data_hi_q<=0; rsp_hi_valid_q<=0; rsp_lo_zero_q<=1; rsp_hi_zero_q<=1;
            held_load_hit_q<=0;
        end else begin
            // Only a stalled successful load hit may create this provenance.
            // All other response sources, maintenance and fatal paths clear it.
            if (state!=RESPONSE) held_load_hit_q<=0;
            case (state)
                INIT_META: begin
                    if(scan_set==LAST_SET) begin scan_set<=0;state<=IDLE;end
                    else scan_set<=scan_set+1'b1;
                end
                IDLE: begin
                    if (maint_valid && maint_ready) begin
                        cleaning<=maint_clean; invalidating<=maint_invalidate;
                        scan_set<=0; scan_way<=0; maint_failed<=0;
                        state<=(ENABLED!=0) ? SCAN : M_DONE;
                    end
                end
                STORE_REREAD: state<=LOOKUP;
                LOOKUP: begin
                    if (hit0 && hit1) begin
                        fatal<=1; state<=HALT;
                    end else if (hit0 || hit1) begin
                        rsp_rdata_q<=hit1 ? ram_q1 : ram_q0; rsp_lo_zero_q<=0;
                        if (READ_ONLY!=0 && STORE_PREDECODE!=0) begin
                            rsp_pre_q<=hit1?ram_pre1:ram_pre0;
                            rsp_pre_hi_q<=hit1?ram_pre1_hi:ram_pre0_hi;
                        end
                        if (READ_ONLY!=0) begin
                            rsp_data_hi_q<=hit1 ? ram_q1_hi : ram_q0_hi; rsp_hi_zero_q<=0;
                            rsp_hi_valid_q<=word_q!=LAST_BEAT;
                        end
                        // Dirty metadata writes use the shared per-way RAM port.
                        // A stalled direct hit is saved before leaving LOOKUP;
                        // RESPONSE then holds payload until the consumer is ready.
                        held_load_hit_q<=fast_hit && !write_q && !rsp_ready;
                        state<=(fast_hit && rsp_ready) ? IDLE : RESPONSE;
                    end else begin
                        victim_way<=choose_way; victim_set<=set_q; beat<=0;
                        wb_addr_q<=restore_line(choose_way ? tag1[set_q] : tag0[set_q],set_q);
                        fill_failed<=0;
                        if (chosen_dirty) state<=WB_CMD;
                        else begin
                            state<=FILL_CMD;
                        end
                    end
                end
                WB_CMD: if (cmd_ready) begin beat<=0; state<=WB_DATA; end
                WB_DATA: if (w_ready) begin
                    if (beat==LAST_BEAT) state<=WB_ACK; else beat<=beat+1'b1;
                end
                WB_ACK: if (r_valid) begin
                    if (r_error || !r_last) begin
                        // Do not change dirty, tags or data; the initiating demand
                        // receives no misleading precise exception for an old store.
                        fatal<=1;
                        if (from_maint) begin maint_failed<=1; state<=M_DONE; end
                        else state<=HALT;
                    end else begin
                        if (from_maint) begin
                            state<=SCAN_NEXT;
                        end else begin
                            beat<=0; fill_failed<=0; state<=FILL_CMD;
                        end
                    end
                end
                FILL_CMD: if (cmd_ready) begin beat<=0; state<=FILL_DATA; end
                FILL_DATA: if (r_valid) begin
                    fill_failed<=fill_failed || fill_bad_now;
                    if (beat==word_q) begin
                        rsp_rdata_q<=r_data; rsp_lo_zero_q<=0;
                        if (READ_ONLY!=0 && STORE_PREDECODE!=0) rsp_pre_q<=cache_predecode(r_data);
                    end
                    if (READ_ONLY!=0 && word_q!=LAST_BEAT && beat==word_q+8'd1) begin
                        rsp_data_hi_q<=r_data; rsp_hi_zero_q<=0;
                        if (STORE_PREDECODE!=0) rsp_pre_hi_q<=cache_predecode(r_data);
                    end
                    if (beat==LAST_BEAT) begin
                        rsp_error_q<=fill_failed || fill_bad_now;
                        rsp_hi_valid_q<=(READ_ONLY!=0) && word_q!=LAST_BEAT &&
                            !(fill_failed || fill_bad_now);
                        if (!(fill_failed || fill_bad_now)) begin
                            if (victim_way) begin
                                tag1[victim_set]<=line_tag;
                            end else begin
                                tag0[victim_set]<=line_tag;
                            end
                        end
                        state<=RESPONSE;
                    end else beat<=beat+1'b1;
                end
                BY_CMD: if (cmd_ready) state<=write_q ? BY_DATA : BY_ACK;
                BY_DATA: if (w_ready) state<=BY_ACK;
                BY_ACK: if (r_valid) begin
                    rsp_rdata_q<=r_data; rsp_lo_zero_q<=0; rsp_error_q<=r_error || !r_last; state<=RESPONSE;
                    if (READ_ONLY!=0 && STORE_PREDECODE!=0) rsp_pre_q<=cache_predecode(r_data);
                end
                RESPONSE: if (rsp_ready) begin
                    held_load_hit_q<=0;
                    state<=IDLE;
                end
                SCAN: begin
                    // Conservative invalidate also writes dirty lines back. This
                    // makes invalidate-only safe for D$ without losing stores.
                    if (scan_valid && scan_dirty && (cleaning || invalidating)) begin
                        victim_set<=scan_set; victim_way<=scan_way;
                        wb_addr_q<=restore_line(scan_way ? tag1[scan_set] : tag0[scan_set],scan_set);
                        from_maint<=1; beat<=0; state<=WB_CMD;
                    end else begin
                        state<=SCAN_NEXT;
                    end
                end
                SCAN_NEXT: begin
                    if (!scan_way) begin scan_way<=1; state<=SCAN; end
                    else if (scan_set==LAST_SET) state<=M_DONE;
                    else begin scan_way<=0; scan_set<=scan_set+1'b1; state<=SCAN; end
                end
                M_DONE: state<=fatal ? HALT : IDLE;
                HALT: state<=HALT;
                default: begin fatal<=1; state<=HALT; end
            endcase
            // Shared request capture covers IDLE and legal response turnover.
            // This intentionally overrides the old transaction's next state/data,
            // after its response has been consumed at this edge.
            if (req_valid && req_ready) begin
                addr_q<=req_addr; write_q<=req_write; be_q<=req_be; wdata_q<=req_wdata;
                rsp_error_q<=0; rsp_lo_zero_q<=1; rsp_hi_zero_q<=1; rsp_hi_valid_q<=0;
                from_maint<=0; held_load_hit_q<=0;
                if (req_addr[1:0]!=0 || ((READ_ONLY!=0) && (req_write || !word_in_ram))) begin
                    rsp_error_q<=1; state<=RESPONSE;
                end else if ((ENABLED!=0) && line_in_ram) state<=store_word_collision?STORE_REREAD:LOOKUP;
                else state<=BY_CMD;
            end
        end
    end
`ifndef SYNTHESIS
    integer store_turnover_consumed=0,store_turnover_same_set=0;
    integer store_reread_count=0;
    always @(posedge clk) if (!rst && req_valid && req_ready && d_store_turnover) begin
        store_turnover_consumed=store_turnover_consumed+1;
        if (request_set==set_q) store_turnover_same_set=store_turnover_same_set+1;
        assert (ram_re && (ram_we0 ^ ram_we1) && ((ram_raddr==ram_waddr)===store_word_collision))
            else $fatal(1,"STORE_TURNOVER_RAM_COLLISION");
    end
    final $display("STORE_TURNOVER_COVER accepted=%0d same_set=%0d",store_turnover_consumed,store_turnover_same_set);
    always @(posedge clk) if(!rst&&state==STORE_REREAD) begin
        store_reread_count=store_reread_count+1;
        assert(!rsp_valid&&!req_ready&&!ram_we0&&!ram_we1&&ram_re&&ram_raddr==addr_q[2+:DB])
            else $fatal(1,"STORE_REREAD_INVARIANT");
    end
    final $display("STORE_REREAD_COVER cycles=%0d",store_reread_count);
    // Only a real acceptance can enter LOOKUP. Probe values outside LOOKUP
    // are deliberately unqualified and have no architectural consumer.
    integer cachemeta_checked=0,cachemeta_same=0,cachemeta_cross=0;
    integer cachemeta_bypass_changed=0,cachemeta_store_blocked=0;
    always @(posedge clk) if (!rst) begin
        if (state==LOOKUP) begin
            cachemeta_checked=cachemeta_checked+1;
            assert ({lookup_replace_q,lookup_dirty0_q,lookup_dirty1_q} ===
                    {replacement_mem[set_q],dirty0[set_q],dirty1[set_q]})
                else $fatal(1,"CACHEMETA_LOOKUP_SNAPSHOT_MISMATCH");
            assert (choose_way === (!valid0[set_q] ? 1'b0 : !valid1[set_q] ? 1'b1 : replacement_mem[set_q]))
                else $fatal(1,"CACHEMETA_CHOOSE_MISMATCH");
            assert (chosen_dirty === (choose_way ? dirty1[set_q] : dirty0[set_q]))
                else $fatal(1,"CACHEMETA_DIRTY_MISMATCH");
        end
        if (req_valid && req_ready && state==LOOKUP) begin
            assert ((hit0 ^ hit1) && (!write_q || d_store_turnover))
                else $fatal(1,"CACHEMETA_ACCEPT_UNSAFE_WRITE_OVERLAP");
            if (request_set==set_q) begin
                cachemeta_same=cachemeta_same+1;
                if (replacement_mem[set_q]!==hit0) cachemeta_bypass_changed=cachemeta_bypass_changed+1;
            end else cachemeta_cross=cachemeta_cross+1;
        end
        if (state==LOOKUP && write_q && (hit0 ^ hit1)) begin
            if (req_valid && req_ready) begin
                assert(d_store_turnover) else $fatal(1,"CACHEMETA_STORE_ACCEPT_COLLISION");
            end else cachemeta_store_blocked=cachemeta_store_blocked+1;
        end
    end
    final $display("CACHEMETA_COVER lookup=%0d same=%0d cross=%0d bypass_changed=%0d store_blocked=%0d",
        cachemeta_checked,cachemeta_same,cachemeta_cross,cachemeta_bypass_changed,cachemeta_store_blocked);
    // Catch future FSM changes that invalidate the retiming invariant.
    always @(posedge clk) if (!rst) begin
        if (state==LOOKUP) begin
            assert(rsp_error_q===1'b0) else $fatal(1,"CACHE_LOOKUP_ERROR_INVARIANT");
            assert (hit0 === (valid0[set_q] && tag0[set_q]==line_tag))
                else $fatal(1,"SYNC_TAG_WAY0_MISMATCH");
            assert (hit1 === (valid1[set_q] && tag1[set_q]==line_tag))
                else $fatal(1,"SYNC_TAG_WAY1_MISMATCH");
        end
        if (req_valid && req_ready)
            assert (state==IDLE || state==RESPONSE || (state==LOOKUP && (hit0^hit1)))
                else $fatal(1,"SYNC_TAG_ACCEPT_OVERLAPS_METADATA_UPDATE");
    end
    initial begin
        if (LINE_BYTES<16 || LINE_BYTES>1020 || (LINE_BYTES & (LINE_BYTES-1))!=0 ||
            SETS<2 || (SETS & (SETS-1))!=0 || CACHE_BYTES != 2*SETS*LINE_BYTES)
            $fatal(1,"Unsupported cache geometry");
    end
`endif
`ifndef SYNTHESIS
    integer cache_predecode_low_checks=0,cache_predecode_high_checks=0;
    always @(posedge clk) if (!rst && READ_ONLY!=0 && STORE_PREDECODE!=0 && rsp_valid && !rsp_error) begin
        assert(rsp_predecode===cache_predecode(rsp_rdata)) else $fatal(1,"ICACHE_PREDECODE_LOW");
        cache_predecode_low_checks<=cache_predecode_low_checks+1;
        if (rsp_hi_valid) begin
            assert(rsp_predecode_hi===cache_predecode(rsp_data_hi)) else $fatal(1,"ICACHE_PREDECODE_HIGH");
            cache_predecode_high_checks<=cache_predecode_high_checks+1;
        end
    end
    final if (READ_ONLY!=0 && STORE_PREDECODE!=0)
        $display("ICACHE_PREDECODE_COVER low=%0d high=%0d",cache_predecode_low_checks,cache_predecode_high_checks);
`endif

endmodule
