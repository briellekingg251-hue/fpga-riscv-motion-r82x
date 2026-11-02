`timescale 1ns/1ps
// Two-word in-order fetch queue. One cache request can add two instructions;
// the decode pipe may remove one or two. A second instruction never advances
// alone. The predictor supplies independent metadata for both word PCs.
module p2_frontend_dual #(
    parameter [31:0] RESET_PC=32'h80000000,
    parameter integer FIFO_DEPTH=4, RESPONSE_BYPASS=0, LINE_BYTES=32,
    DUAL_WORDS=1, RESPONSE_PREDECODE=0
)(
    input wire clk,rst,stop,
    input wire redirect_valid,input wire [31:0] redirect_pc,
    input wire fast_redirect,input wire [31:0] fast_pc,fast_pc4,fast_pc8,
    output wire [31:0] predict_pc,input wire [31:0] predict_next,predict_next1,
    input wire predict_sequential,
    output wire [31:0] response_predict_pc,
    input wire [31:0] response_predict_next,response_predict_next1,
    input wire response_predict_sequential,response_predict_sequential1,
    output wire predict_accept,predict_accept_second,
    output wire response_sample_fast_select,
    output wire req_valid,input wire req_ready,output wire [31:0] req_addr,
    input wire rsp_valid,output wire rsp_ready,
    input wire [31:0] rsp_data,rsp_data_hi,
    input wire [6:0] rsp_predecode,rsp_predecode_hi,
    input wire rsp_error,rsp_hi_valid,
    output wire out_valid,input wire out_ready,
    output wire [31:0] out_pc,out_insn,out_prediction,output wire out_error,
    output wire out_sequential,out1_sequential,out_pair_link,
    output wire [6:0] out_predecode,out1_predecode,
    output wire out1_valid,input wire out1_ready,
    output wire [31:0] out1_pc,out1_insn,out1_prediction,output wire out1_error
);
    localparam integer DEPTH=FIFO_DEPTH<8?8:FIFO_DEPTH;
    localparam integer PTR_BITS=$clog2(DEPTH);
    localparam integer COUNT_BITS=PTR_BITS+1;
    reg [31:0] offer_pc,pending_pc,pending_prediction,pending_prediction1;
    reg pending_seq0;
    reg pending_fast;
    reg [31:0] pending_pc8;
    reg [31:0] recovery_pc;
    reg [31:0] tail_prediction_q;
    reg pending,pending_wide,pending_discard,offer_discard,recovery,held_offer;
    reg [31:0] q_pc[0:DEPTH-1],q_insn[0:DEPTH-1],q_prediction[0:DEPTH-1];
    reg [6:0] q_pre[0:DEPTH-1];
    reg q_error[0:DEPTH-1],q_sequential[0:DEPTH-1];
    // q_link[i]: entry i's prediction equals entry i+1's PC (written on enqueue).
    reg q_link[0:DEPTH-1];
    // Fixed heads (see module notes).
    reg [31:0] h0_insn,h1_insn;
    reg h0_error,h1_error,h0_seq,h1_seq,h_link;
    reg [6:0] h0_pre,h1_pre;
    reg [PTR_BITS-1:0] rd_ptr,wr_ptr;
    reg [COUNT_BITS-1:0] count;
    wire [PTR_BITS-1:0] rd_next=rd_ptr+1'b1;
    wire [PTR_BITS-1:0] wr_next=wr_ptr+1'b1;
    wire [PTR_BITS-1:0] wr_prev=wr_ptr-1'b1;
    // This is known at request time and agrees with the I$ high-word valid
    // contract on successful responses. A predicted first-word branch takes
    // priority over the second word, which is then neither queued nor skipped.
    localparam integer POWER_OF_TWO_LINE=(LINE_BYTES>=4)&&((LINE_BYTES&(LINE_BYTES-1))==0);
    // For a power-of-two line, only the byte offset can cross PC+4's boundary.
    wire same_line=POWER_OF_TWO_LINE?((offer_pc&(LINE_BYTES-1))<(LINE_BYTES-4)):
        ((offer_pc & ~(LINE_BYTES-1))==((offer_pc+32'd4) & ~(LINE_BYTES-1)));
    wire offer_wide=(DUAL_WORDS!=0)&&predict_sequential&&same_line;
    assign predict_pc=offer_pc;
    assign response_predict_pc=pending_pc;
    wire returning=rsp_valid&&rsp_ready;
    assign req_valid=(!stop||held_offer)&&(!pending||returning);
    // FAST redirect: request the target now, without a predictor lookup.
    wire early_redirect=fast_redirect&&!held_offer&&!stop&&(!pending||returning);
    assign response_sample_fast_select=early_redirect;
    // Existing fast redirect contract guarantees fast_pc4==fast_pc+4.
    wire fast_wide=(DUAL_WORDS!=0)&&(POWER_OF_TWO_LINE?
        ((fast_pc&(LINE_BYTES-1))<(LINE_BYTES-4)):
        ((fast_pc&~(LINE_BYTES-1))==(fast_pc4&~(LINE_BYTES-1))));
    assign req_addr=early_redirect?fast_pc:offer_pc;
    wire accepting=req_valid&&req_ready;
    assign predict_accept=accepting&&!offer_discard&&!redirect_valid&&!stop&&!response_repair;
    assign predict_accept_second=predict_accept&&offer_wide;
    wire [31:0] predicted_after=offer_wide?predict_next1:predict_next;

    assign out_valid=count!=0;
    assign out_pc=q_pc[rd_ptr];
    assign out_insn=h0_insn;
    assign out_prediction=q_prediction[rd_ptr];
    assign out_error=h0_error;
    assign out_sequential=h0_seq;
    assign out1_valid=count>=2;
    assign out1_pc=q_pc[rd_next];
    assign out1_insn=h1_insn;
    assign out1_prediction=q_prediction[rd_next];
    assign out1_error=h1_error;
    assign out1_sequential=h1_seq;
    assign out_pair_link=h_link;
    assign out_predecode=h0_pre;
    assign out1_predecode=h1_pre;
    wire pop0=out_valid&&out_ready;
    wire pop1=out1_valid&&out1_ready&&pop0;
    wire [1:0] pop_n={1'b0,pop0}+{1'b0,pop1};
    // Reserve queue room from registered occupancy alone. Extra depth absorbs
    // returns without borrowing a same-cycle dequeue. Redirect/stop may discard
    // an accepted response, but cannot drive cache-ready combinationally.
    // A blocked old response becomes discardable after the redirect edge.
    wire credit_one=(count<DEPTH);
    wire credit_two=(count<=DEPTH-2);
    assign rsp_ready=pending&&(pending_discard||
        (pending_wide?credit_two:credit_one));
    wire push0=returning&&!pending_discard&&!redirect_valid&&!stop;
    wire response_use=pending_fast&&!pending_discard&&!rsp_error;
    wire [31:0] response_pred0=response_use?response_predict_next:pending_prediction;
    wire [31:0] response_pred1=response_use?response_predict_next1:pending_prediction1;
    wire response_seq0=response_use?response_predict_sequential:pending_seq0;
    wire response_seq1=response_use?response_predict_sequential1:(pending_prediction1==pending_pc8);
    wire response_wide=pending_wide&&(!response_use||response_seq0);
    wire push1=push0&&response_wide&&rsp_hi_valid;
    // Preserve the target packet. Only its already offered successor is stale.
    // Conservative repair may discard a request even when its PC coincides.
    wire response_repair=push0&&response_use&&(!response_seq0||(push1&&!response_seq1));
    wire [31:0] response_after=push1?response_pred1:response_pred0;
    wire [1:0] push_n={1'b0,push0}+{1'b0,push1};
    always @(posedge clk) begin
        if(rst) begin
            offer_pc<=RESET_PC;pending_pc<=0;pending_prediction<=0;
            pending_prediction1<=0;recovery_pc<=0;pending_seq0<=0;pending_pc8<=0;
            pending<=0;pending_wide<=0;pending_discard<=0;pending_fast<=0;
            offer_discard<=0;recovery<=0;held_offer<=0;
            rd_ptr<=0;wr_ptr<=0;count<=0;
        end else begin
            held_offer<=req_valid&&!req_ready;
            if(returning) begin pending<=0;pending_fast<=0;end
            if(accepting) begin
                pending<=1;pending_pc<=early_redirect?fast_pc:offer_pc;pending_fast<=early_redirect;
                // Early target: conservative sequential prediction of its words.
                pending_prediction<=early_redirect?fast_pc4:predict_next;
                pending_prediction1<=early_redirect?fast_pc8:predict_next1;
                pending_seq0<=early_redirect||predict_sequential;
                pending_pc8<=early_redirect?fast_pc8:offer_pc+32'd8;
                pending_wide<=early_redirect?fast_wide:offer_wide;
                pending_discard<=early_redirect?1'b0:(offer_discard||redirect_valid||stop);
                // A held offer may handshake after stop goes high. Its
                // response will be discarded, so retry that PC on resume.
                offer_pc<=early_redirect?(fast_wide?fast_pc8:fast_pc4):
                    (recovery?recovery_pc:(stop?offer_pc:predicted_after));
                offer_discard<=0;recovery<=0;
            end
            if(response_repair) begin
                if(accepting) begin
                    // The ordinary sequential successor has already handshaken.
                    pending_discard<=1;pending_fast<=0;
                    offer_pc<=response_after;offer_discard<=0;recovery<=0;
                end else if(req_valid&&!req_ready) begin
                    // Never change an externally held request address.
                    offer_discard<=1;recovery<=1;recovery_pc<=response_after;
                end else begin
                    offer_pc<=response_after;offer_discard<=0;recovery<=0;
                end
            end
            // A stopped core may be waiting for I-cache maintenance while
            // E holds the queue full. Mark its old response discardable at
            // this edge, so next-cycle ready does not need queue credit or a
            // combinational stop bypass. Save its PC immediately for resume,
            // even if stop drops before that delayed response is returned.
            // Already-discarded redirect traffic must not rewind recovery.
            if(stop&&pending&&!pending_discard&&!redirect_valid) begin
                if(!returning) pending_discard<=1;
                offer_pc<=pending_pc;
            end
            if(pop0) rd_ptr<=rd_ptr+pop_n;
            if(push0) wr_ptr<=wr_ptr+push_n;
            count<=count+push_n-pop_n;
            if(redirect_valid) begin
                rd_ptr<=0;wr_ptr<=0;count<=0;
                if(pending&&!returning) pending_discard<=1;
                if(early_redirect) begin
                    // Accepted: offer_pc already advanced. Not accepted: the target is
                    // now the held offer (address stable; predicted when it handshakes).
                    if(!req_ready) begin offer_pc<=redirect_pc;offer_discard<=0;recovery<=0;end
                end else if(req_valid&&!req_ready) begin
                    offer_discard<=1;recovery<=1;recovery_pc<=redirect_pc;
                end else begin
                    offer_pc<=redirect_pc;offer_discard<=0;recovery<=0;
                end
            end
        end
    end
    // Payload contents are meaningful only inside the occupied queue range.
    // Credit guarantees these slots are empty before this edge's pops;
    // no dequeue or redirect control enters the wide payload write enables.
    // A discarded response may update such free slots without committing them;
    // the next real push overwrites every payload bit before count exposes it.
    wire payload_write0=pending&&rsp_valid&&
        (pending_wide?credit_two:credit_one);
    wire payload_write1=payload_write0&&response_wide&&rsp_hi_valid;
    // Speculative instruction bits may fill the reserved empty high slot.
    // Commit, PC and prediction/error/link metadata retain their old gate.
    wire data_write1=payload_write0&&pending_wide&&rsp_hi_valid;
    wire seq_new0=response_seq0;
    wire seq_new1=response_seq1;
    // The committed tail prediction avoids a pointer-indexed queue read.
    // It is needed only when an occupied entry precedes this response.
    wire link_new0=(pending_pc==tail_prediction_q);
    wire link_new1=response_seq0;
    // Predecode bits: {is_branch,branch1_ok,use2,use1,writes,pairable0,simple}
    function automatic [6:0] predecode;
        input [31:0] insn;
        reg [6:0] op;reg [2:0] f3;reg [6:0] f7;
        begin
            op=insn[6:0];f3=insn[14:12];f7=insn[31:25];
            predecode[0]=(op==7'h37||op==7'h17||
                (op==7'h13&&((f3!=3'b001&&f3!=3'b101)||(f3==3'b001&&f7==0)||(f3==3'b101&&(f7==0||f7==7'h20))))||
                (op==7'h33&&(f7==0||(f7==7'h20&&(f3==0||f3==5)))));
            predecode[1]=(op==7'h37||op==7'h17||op==7'h13||op==7'h33||op==7'h03||op==7'h23||op==7'h63);
            predecode[2]=(op!=7'h23&&op!=7'h63&&insn[11:7]!=0);
            predecode[3]=(op==7'h13||op==7'h33||op==7'h63);
            predecode[4]=(op==7'h33||op==7'h63);
            predecode[5]=(op==7'h63)&&(f3[2]||(f3[2:1]==2'b00))&&!insn[8];
            predecode[6]=(op==7'h63);
        end
    endfunction
    // Decode payloads independently of the late predictor/response selector.
    (* syn_keep = 1 *) wire [6:0] rsp_pre0=(RESPONSE_PREDECODE!=0)?rsp_predecode:predecode(rsp_data);
    (* syn_keep = 1 *) wire [6:0] rsp_pre1=(RESPONSE_PREDECODE!=0)?rsp_predecode_hi:predecode(rsp_data_hi);
    // Head candidates for entries rd_ptr+k (k=0..3) as they will be after this
    // edge's payload writes. Only early state selects them.
    wire [4*32-1:0] cand_insn;
    wire [3:0] cand_error,cand_seq,cand_link;
    wire [4*7-1:0] cand_pre;
    genvar hk;
    generate for(hk=0;hk<4;hk=hk+1) begin: head_candidate
        wire [PTR_BITS-1:0] idx=rd_ptr+hk;
        wire w0=payload_write0&&(idx==wr_ptr);
        wire w1=payload_write1&&(idx==wr_next);
        wire d1=data_write1&&(idx==wr_next);
        wire l0=payload_write0&&(idx==wr_prev);
        wire l1=payload_write1&&(idx==wr_ptr);
        wire [31:0] insn=w0?rsp_data:d1?rsp_data_hi:q_insn[idx];
        assign cand_insn[hk*32+:32]=insn;
        assign cand_error[hk]=w0?rsp_error:w1?1'b0:q_error[idx];
        assign cand_seq[hk]=w0?seq_new0:w1?seq_new1:q_sequential[idx];
        assign cand_link[hk]=l0?link_new0:l1?link_new1:q_link[idx];
        assign cand_pre[hk*7+:7]=w0?rsp_pre0:d1?rsp_pre1:q_pre[idx];
    end endgenerate
    always @(posedge clk) begin
        // Head mirrors are disposable while count is zero. The first real
        // payload write rebuilds them through existing forwarding before valid.
            // The late pop count only selects among precomputed candidates.
            case(pop_n)
                2'd0: begin
                    h0_insn<=cand_insn[0+:32];h0_error<=cand_error[0];h0_seq<=cand_seq[0];h0_pre<=cand_pre[0+:7];
                    h1_insn<=cand_insn[32+:32];h1_error<=cand_error[1];h1_seq<=cand_seq[1];h1_pre<=cand_pre[7+:7];
                    h_link<=cand_link[0];
                end
                2'd1: begin
                    h0_insn<=cand_insn[32+:32];h0_error<=cand_error[1];h0_seq<=cand_seq[1];h0_pre<=cand_pre[7+:7];
                    h1_insn<=cand_insn[64+:32];h1_error<=cand_error[2];h1_seq<=cand_seq[2];h1_pre<=cand_pre[14+:7];
                    h_link<=cand_link[1];
                end
                default: begin
                    h0_insn<=cand_insn[64+:32];h0_error<=cand_error[2];h0_seq<=cand_seq[2];h0_pre<=cand_pre[14+:7];
                    h1_insn<=cand_insn[96+:32];h1_error<=cand_error[3];h1_seq<=cand_seq[3];h1_pre<=cand_pre[21+:7];
                    h_link<=cand_link[2];
                end
            endcase
    end
    always @(posedge clk) begin
        if(rst) tail_prediction_q<=0;
        else if(push0) tail_prediction_q<=push1?response_pred1:response_pred0;
    end
    always @(posedge clk) begin
        if(!rst) begin
            if(payload_write0) begin
                q_link[wr_prev]<=link_new0;
                q_pc[wr_ptr]<=pending_pc;
                q_insn[wr_ptr]<=rsp_data;
                q_pre[wr_ptr]<=rsp_pre0;
                q_prediction[wr_ptr]<=response_pred0;
                q_error[wr_ptr]<=rsp_error;
                q_sequential[wr_ptr]<=seq_new0;
            end
            if(data_write1) begin q_insn[wr_next]<=rsp_data_hi;q_pre[wr_next]<=rsp_pre1;end
            if(payload_write1) begin
                q_link[wr_ptr]<=link_new1;
                q_pc[wr_next]<=pending_pc+32'd4;
                q_prediction[wr_next]<=response_pred1;
                q_error[wr_next]<=1'b0;
                q_sequential[wr_next]<=seq_new1;
            end
        end
    end
`ifndef SYNTHESIS
    reg [31:0] held_addr_q,early_pc_q;
    reg early_accept_q;
    integer fast_accepted=0,fast_held=0;
    integer response_queries=0,response_repairs=0,response_repair_accepts=0,response_repair_holds=0;
    reg repair_accept_q,repair_hold_q;reg [31:0] repair_after_q;
    always @(posedge clk) begin
        repair_accept_q<=!rst&&response_repair&&accepting;
        repair_hold_q<=!rst&&response_repair&&req_valid&&!req_ready;
        repair_after_q<=response_after;
        if(!rst&&push0&&response_use)response_queries++;
        if(!rst&&response_repair)begin
            response_repairs++;
            if(accepting)response_repair_accepts++;
            if(req_valid&&!req_ready)response_repair_holds++;
            assert(!predict_accept&&!redirect_valid&&!stop&&pending_fast&&!pending_discard)
                else $fatal(1,"RESPONSE_REPAIR_QUALIFIERS");
        end
        if(!rst&&repair_accept_q)assert(pending&&pending_discard&&!pending_fast&&offer_pc===repair_after_q)
            else $fatal(1,"RESPONSE_REPAIR_ACCEPT_IDENTITY");
        if(!rst&&repair_hold_q)assert(held_offer&&offer_discard&&recovery&&recovery_pc===repair_after_q)
            else $fatal(1,"RESPONSE_REPAIR_HOLD_IDENTITY");
        if(!rst&&pending&&response_use)begin
            assert(response_seq0===(response_pred0==pending_pc+32'd4)&&response_seq1===(response_pred1==pending_pc8))
                else $fatal(1,"RESPONSE_PREDICTION_SEQUENTIAL_IDENTITY");
        end
    end
    final $display("RESPONSE_REPREDICT_COVER query=%0d repair=%0d accepted_discard=%0d held_discard=%0d",response_queries,response_repairs,response_repair_accepts,response_repair_holds);

    always @(posedge clk) begin
        held_addr_q<=req_addr;early_pc_q<=fast_pc;
        early_accept_q<=!rst&&early_redirect&&accepting;
        if(!rst&&early_redirect&&accepting) fast_accepted=fast_accepted+1;
        if(!rst&&early_redirect&&!accepting) fast_held=fast_held+1;
    end
    final $display("FASTREDIRECT_FE_COVER accepted=%0d held=%0d",fast_accepted,fast_held);

    initial if(DEPTH<4||(DEPTH&(DEPTH-1))!=0||LINE_BYTES<8||
               (LINE_BYTES&(LINE_BYTES-1))!=0)
        $fatal(1,"dual frontend requires power-of-two depth>=4 and line>=8");
    always @(posedge clk) if(!rst) begin
        assert(predict_sequential === (predict_next==offer_pc+32'd4))
            else $fatal(1,"FRONTEND_PREDICTION_SEQUENTIAL_MISMATCH");
        if(pending) begin
            assert(pending_seq0===(pending_prediction==pending_pc+32'd4)&&
                   pending_pc8===(pending_pc+32'd8))
                else $fatal(1,"PENDING_SEQUENTIAL_IDENTITY");
        end
        assert(count<=DEPTH);
        if(out_valid) assert(out_sequential===(out_prediction==out_pc+32'd4))
            else $fatal(1,"FRONTSEQ_PRIMARY_METADATA");
        if(out1_valid) assert(out1_sequential===(out1_prediction==out1_pc+32'd4))
            else $fatal(1,"FRONTSEQ_SECONDARY_METADATA");
        if(fast_redirect) assert(redirect_valid&&redirect_pc===fast_pc&&fast_pc4===fast_pc+32'd4&&fast_pc8===fast_pc+32'd8)
            else $fatal(1,"FASTREDIRECT_FRONTEND_INPUTS");
        if(early_redirect) assert(req_valid&&req_addr===fast_pc&&!recovery&&!predict_accept)
            else $fatal(1,"FASTREDIRECT_OFFER");
        if(held_offer) assert(req_valid&&req_addr===held_addr_q) else $fatal(1,"HELD_OFFER_UNSTABLE");
        if(early_accept_q) assert(pending&&pending_pc===early_pc_q&&!pending_discard&&pending_prediction===early_pc_q+32'd4)
            else $fatal(1,"FASTREDIRECT_PENDING_IDENTITY");
        if(count!=0) assert(tail_prediction_q===q_prediction[wr_prev])
            else $fatal(1,"TAIL_PREDICTION_IDENTITY");
        // Fixed heads equal the queue entries they mirror whenever visible.
        if(out_valid) assert(h0_insn===q_insn[rd_ptr]&&h0_error===q_error[rd_ptr]&&
            h0_seq===q_sequential[rd_ptr]&&h0_pre===predecode(q_insn[rd_ptr]))
            else $fatal(1,"FIXEDHEAD_H0");
        if(out1_valid) assert(h1_insn===q_insn[rd_next]&&h1_error===q_error[rd_next]&&
            h1_seq===q_sequential[rd_next]&&h1_pre===predecode(q_insn[rd_next])&&
            h_link===(q_prediction[rd_ptr]==q_pc[rd_next]))
            else $fatal(1,"FIXEDHEAD_H1_LINK");
        assert(!out1_ready||pop0);
        assert(!push1||push0);
        if(push0&&pending_wide&&!rsp_error)
            assert(rsp_hi_valid);
    end
`endif
endmodule
