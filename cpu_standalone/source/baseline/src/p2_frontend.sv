`timescale 1ns/1ps
// One outstanding fetch with a two-entry returned-instruction FIFO.
// A returned request and its successor may handshake at the same edge.
module p2_frontend #(
    parameter [31:0] RESET_PC=32'h80000000,
    parameter integer FIFO_DEPTH=2, RESPONSE_BYPASS=0
)(
    input wire clk,rst,stop,
    input wire redirect_valid,input wire [31:0] redirect_pc,
    output wire [31:0] predict_pc,input wire [31:0] predict_next,
    output wire req_valid,input wire req_ready,output wire [31:0] req_addr,
    input wire rsp_valid,output wire rsp_ready,input wire [31:0] rsp_data,input wire rsp_error,
    output wire out_valid,input wire out_ready,
    output wire [31:0] out_pc,out_insn,out_prediction,output wire out_error
);
    reg [31:0] offer_pc,pending_pc,pending_prediction,recovery_pc;
    reg pending,pending_discard,offer_discard,recovery,held_offer;
    localparam integer PTR_BITS=$clog2(FIFO_DEPTH);
    localparam [PTR_BITS:0] CAPACITY=(PTR_BITS+1)'(FIFO_DEPTH);
    reg [31:0] q_pc[0:FIFO_DEPTH-1],q_insn[0:FIFO_DEPTH-1],q_prediction[0:FIFO_DEPTH-1];
    reg q_error[0:FIFO_DEPTH-1];
    reg [PTR_BITS-1:0] rd_ptr,wr_ptr;
    reg [PTR_BITS:0] count;
    // Empty FIFO fall-through removes a recovery stage without introducing
    // ready -> valid feedback. A stalled bypass is captured into the FIFO.
    wire bypass=(RESPONSE_BYPASS!=0)&&count==0&&pending&&rsp_valid&&
        !pending_discard&&!redirect_valid&&!stop;
    assign out_valid=count!=0||bypass;
    assign out_pc=count!=0?q_pc[rd_ptr]:pending_pc;
    assign out_insn=count!=0?q_insn[rd_ptr]:rsp_data;
    assign out_prediction=count!=0?q_prediction[rd_ptr]:pending_prediction;
    assign out_error=count!=0?q_error[rd_ptr]:rsp_error;
    wire pop=(count!=0)&&out_ready;
    wire bypass_fire=bypass&&out_ready;
    assign rsp_ready=pending&&(pending_discard||redirect_valid||stop||count<CAPACITY||pop);
    wire returning=rsp_valid&&rsp_ready;
    // If an old response enables this offer but ready is low, consuming that
    // response leaves pending=0, so the offer remains continuously visible.
    assign req_valid=(!stop||held_offer)&&(!pending||returning);
    assign req_addr=offer_pc;
    assign predict_pc=offer_pc;
    wire accepting=req_valid&&req_ready;
    wire push=returning&&!pending_discard&&!redirect_valid&&!stop&&!bypass_fire;
    integer j;
    always @(posedge clk) begin
        if(rst) begin
            offer_pc<=RESET_PC;pending<=0;pending_discard<=0;
            pending_pc<=0;pending_prediction<=0;offer_discard<=0;
            recovery<=0;recovery_pc<=0;held_offer<=0;
            rd_ptr<=0;wr_ptr<=0;count<=0;
            for(j=0;j<FIFO_DEPTH;j=j+1) begin
                q_pc[j]<=0;q_insn[j]<=0;q_prediction[j]<=0;q_error[j]<=0;
            end
        end else begin
            held_offer<=req_valid&&!req_ready;
            if(returning) pending<=0;
            if(accepting) begin
                pending<=1;pending_pc<=offer_pc;pending_prediction<=predict_next;
                pending_discard<=offer_discard||redirect_valid||stop;
                offer_pc<=recovery?recovery_pc:predict_next;
                offer_discard<=0;recovery<=0;
            end
            if(pop) rd_ptr<=rd_ptr+1'b1;
            if(push) begin
                q_pc[wr_ptr]<=pending_pc;q_insn[wr_ptr]<=rsp_data;
                q_prediction[wr_ptr]<=pending_prediction;q_error[wr_ptr]<=rsp_error;
                wr_ptr<=wr_ptr+1'b1;
            end
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
            if(redirect_valid) begin
                rd_ptr<=0;wr_ptr<=0;count<=0;
                if(pending&&!returning) pending_discard<=1;
                if(req_valid&&!req_ready) begin
                    offer_discard<=1;recovery<=1;recovery_pc<=redirect_pc;
                end else begin
                    offer_pc<=redirect_pc;offer_discard<=0;recovery<=0;
                end
            end
        end
    end
`ifndef SYNTHESIS
    initial if(FIFO_DEPTH<2||(FIFO_DEPTH&(FIFO_DEPTH-1))!=0)
        $fatal(1,"FIFO_DEPTH must be a power of two >= 2");
    always @(posedge clk) if(!rst) begin
        assert(count<=CAPACITY);
        assert(!(bypass_fire&&push));
    end
`endif
endmodule
