`timescale 1ns/1ps
// P3 fixed-event, machine-mode read-only performance CSR bank.
// 0xFC0+2*n is slot n[31:0], 0xFC1+2*n is slot n[63:32].
// The core owns privilege/write checks. Reads have no side effects; software
// uses high/low/high retry for a coherent RV32 snapshot of a running counter.
// Slots 0..18 count qualified event pulses while enable is high. Slots 19..23
// expose existing cache counters directly, independently of this bank's enable.
// Reset of those external values remains the cache owner's responsibility.
// No mcountinhibit coupling: these custom diagnostic counters are independent
// of the architectural mcycle/minstret/HPM counters.
//
// Event slots: 0 fetch_stall, 1 fetch_empty, 2 frontend_flush, 3 decode_stall,
// 4 load_use, 5 memory_stall, 6 branch_count, 7 branch_taken,
// 8 branch_mispredict, 9 branch_flush, 10 prediction_count,
// 11 prediction_correct, 12 fetch_req_stall, 13 fetch_accept,
// 14 fetch_response, 15 data_accept, 16 data_req_stall,
// 17 stale_btb_recovery, 18 decode_issue (instructions, 0/1/2 per cycle).
// Events may overlap. In particular these counters are not a CPI partition.
module p3_perf_counters #(parameter DUAL_ISSUE=0) (
    input wire clk, rst, enable,
    input wire [23:0] event_pulses,
    input wire issue_second,
    input wire [11:0] csr_addr,
    output reg [31:0] csr_rdata,
    output wire csr_known,
    input wire [63:0] i_hit, i_miss, d_hit, d_miss, d_writeback,
    output wire [1535:0] values_flat
);
    // Stable simulation/debug view of every architecturally visible count.
    wire [63:0] event_count_q [0:18];
    genvar g;
    generate for (g=0; g<19; g=g+1) begin: expose_event
        wire fire=enable&&event_pulses[g];
        if (g==18 && DUAL_ISSUE!=0) begin: pending_dual
            // visible=R+pending (mod 2^64), pending in {0,1,2}. Late issue only
            // reaches pending_q/pending_two_q. Low 16 bits keep R,R+1,R+2; the
            // high 48 bits keep H and H+1 with registered low-carry flags.
            reg [15:0] lo0_q,lo1_q,lo2_q;
            reg [47:0] hi_q,hi1_q;
            reg carry1_q,carry2_q;
            reg pending_q,pending_two_q;
            wire [15:0] lo_next=pending_two_q?lo2_q:lo1_q;
            wire hi_step=pending_two_q?carry2_q:carry1_q;
            always @(posedge clk) begin
                if (rst) begin
                    lo0_q<=0;lo1_q<=1;lo2_q<=2;hi_q<=0;hi1_q<=1;
                    carry1_q<=0;carry2_q<=0;pending_q<=0;pending_two_q<=0;
                end else begin
                    pending_q<=fire;
                    pending_two_q<=fire&&issue_second;
                    if (pending_q) begin
                        lo0_q<=lo_next;
                        lo1_q<=lo_next+16'd1;
                        lo2_q<=lo_next+16'd2;
                        carry1_q<=lo_next==16'hffff;
                        carry2_q<=lo_next>=16'hfffe;
                        if (hi_step) begin
                            hi_q<=hi1_q;
                            hi1_q<=hi1_q+48'd1;
                        end
                    end
                end
            end
            wire [47:0] hi_view=pending_q&&(pending_two_q?carry2_q:carry1_q)?hi1_q:hi_q;
            wire [15:0] lo_view=pending_q?lo_next:lo0_q;
            assign event_count_q[g]={hi_view,lo_view};
`ifndef SYNTHESIS
            reg [63:0] reference_q;
            always @(posedge clk) begin
                if (rst) reference_q<=0;
                else if (fire) reference_q<=reference_q+(issue_second?64'd2:64'd1);
            end
            always @(posedge clk) if (!rst) assert(event_count_q[g]===reference_q)
                else $fatal(1,"EV18_PENDING_VISIBLE");
`endif
        end else if (g==0 || g==2 || g==3 || g==4 || g==5 || g==7 || g==8 || g==9 || g==11 || g==12 || g==13 || g==14 || g==15 || g==16 || g==17) begin: pending_bank
            // R1=R+1 and visible=R+pending at every clock boundary.
            // Late fire touches only pending_q.  The old pending event drains
            // even when enable falls; the current enable qualifies new events.
            reg [63:0] raw_count_q, raw_plus_one_q;
            reg pending_q;
            reg [2:0] full_q;
            always @(posedge clk) begin
                if (rst) begin
                    raw_count_q<=0;
                    pending_q<=0;
                end else begin
                    pending_q<=fire;
                    if (pending_q) raw_count_q<=raw_plus_one_q;
                end
            end
            for (genvar chunk=0; chunk<4; chunk=chunk+1) begin: segmented
                wire lower_full;
                if (chunk==0) assign lower_full=1'b1;
                else assign lower_full=&full_q[chunk-1:0];
                always @(posedge clk) begin
                    if (rst) raw_plus_one_q[chunk*16+:16]<=(chunk==0)?16'd1:16'd0;
                    else if (pending_q&&lower_full)
                        raw_plus_one_q[chunk*16+:16]<=raw_plus_one_q[chunk*16+:16]+16'd1;
                end
                if (chunk<3) begin: lookahead
                    always @(posedge clk) begin
                        if (rst) full_q[chunk]<=0;
                        else if (pending_q&&lower_full)
                            full_q[chunk]<=raw_plus_one_q[chunk*16+:16]==16'hfffe;
                    end
                end
            end
            // Both choices are FF outputs: there is no visible pending adder.
            assign event_count_q[g]=pending_q?raw_plus_one_q:raw_count_q;
        end else begin: direct_bank
            reg [63:0] count_q;
            // Visible counts are registers: no pending-delta adder feeds CSR reads.
            // Each segment has an independent incrementer. Registered full flags
            // qualify carries, so a late event only controls segment clock enables.
            wire add_two=(g==18 && DUAL_ISSUE!=0) && issue_second;
            reg [2:0] full_q;
            wire low_carry;
            if (g==18 && DUAL_ISSUE!=0) begin: dual_count
                reg near_full_q;
                wire [15:0] plus_one=count_q[15:0]+16'd1;
                wire [15:0] plus_two=count_q[15:0]+16'd2;
                assign low_carry=full_q[0]||(add_two&&near_full_q);
                always @(posedge clk) begin
                    if (rst) begin
                        count_q[15:0]<=0;
                        full_q[0]<=0;
                        near_full_q<=0;
                    end else if (fire) begin
                        count_q[15:0]<=add_two ? plus_two : plus_one;
                        full_q[0]<=add_two ? (count_q[15:0]==16'hfffd) :
                            (count_q[15:0]==16'hfffe);
                        near_full_q<=add_two ? (count_q[15:0]==16'hfffc) :
                            (count_q[15:0]==16'hfffd);
                    end
                end
            end else begin: single_count
                assign low_carry=full_q[0];
                always @(posedge clk) begin
                    if (rst) begin
                        count_q[15:0]<=0;
                        full_q[0]<=0;
                    end else if (fire) begin
                        count_q[15:0]<=count_q[15:0]+16'd1;
                        full_q[0]<=count_q[15:0]==16'hfffe;
                    end
                end
            end
            for (genvar chunk=1; chunk<4; chunk=chunk+1) begin: segmented
                wire lower_full;
                if (chunk==1) assign lower_full=low_carry;
                else assign lower_full=low_carry&&(&full_q[chunk-1:1]);
                always @(posedge clk) begin
                    if (rst) count_q[chunk*16+:16]<=0;
                    else if (fire&&lower_full)
                        count_q[chunk*16+:16]<=count_q[chunk*16+:16]+16'd1;
                end
                if (chunk<3) begin: lookahead
                    always @(posedge clk) begin
                        if (rst) full_q[chunk]<=0;
                        else if (fire&&lower_full)
                            full_q[chunk]<=count_q[chunk*16+:16]==16'hfffe;
                    end
                end
            end
            assign event_count_q[g]=count_q;
        end
        assign values_flat[g*64+:64] = event_count_q[g];
    end endgenerate
    assign values_flat[19*64+:64] = i_hit;
    assign values_flat[20*64+:64] = i_miss;
    assign values_flat[21*64+:64] = d_hit;
    assign values_flat[22*64+:64] = d_miss;
    assign values_flat[23*64+:64] = d_writeback;

    assign csr_known = csr_addr >= 12'hfc0 && csr_addr <= 12'hfef;
    // Decode all 48 read-only words in parallel. Each selected word is
    // masked before a fixed six-input/eight-group OR reduction; the pending
    // counter values retain their exact same-edge architectural meaning.
    wire [31:0] csr_words[0:47],csr_groups[0:7];
    genvar csr_leaf,csr_group;
    generate for(csr_leaf=0;csr_leaf<48;csr_leaf=csr_leaf+1) begin: csr_word_decode
        assign csr_words[csr_leaf]={32{csr_addr[5:0]==csr_leaf}}&values_flat[csr_leaf*32+:32];
    end
    for(csr_group=0;csr_group<8;csr_group=csr_group+1) begin: csr_word_reduce
        assign csr_groups[csr_group]=csr_words[csr_group*6]|csr_words[csr_group*6+1]|
            csr_words[csr_group*6+2]|csr_words[csr_group*6+3]|
            csr_words[csr_group*6+4]|csr_words[csr_group*6+5];
    end endgenerate
    always @* begin
        csr_rdata=32'd0;
        if(csr_known) csr_rdata=csr_groups[0]|csr_groups[1]|csr_groups[2]|csr_groups[3]|
            csr_groups[4]|csr_groups[5]|csr_groups[6]|csr_groups[7];
    end
endmodule
