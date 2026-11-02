`timescale 1ns/1ps
// Small full-tag BTB with an independently indexed two-bit direction table.
// Training occurs only on legal retired control-flow instructions.
module p2_predictor #(parameter ENABLED=1, BTB_ENTRIES=64, BHT_ENTRIES=256, RAS_DEPTH=0)(
    input wire clk,rst,input wire [31:0] lookup_pc,output wire [31:0] prediction,
    output wire prediction_is_sequential,
    input wire [31:0] lookup_pc1,output wire [31:0] prediction1,
    input wire lookup_accept,lookup_second_valid,fetch_flush,
    input wire train_valid,input wire [31:0] train_pc,train_target,
    input wire train_conditional,train_taken,
    input wire [31:0] train_insn,input wire ras_flush,
    input wire ras_call_valid,input wire [31:0] ras_call_return,
    input wire [31:0] response_sample_pc,input wire response_sample_accept,
    input wire [31:0] response_sample_fast_pc,input wire response_sample_fast_select,
    input wire [31:0] response_lookup_pc,
    output wire [31:0] response_prediction,response_prediction1,
    output wire response_sequential,response_sequential1
);
    localparam integer BI_BITS=$clog2(BTB_ENTRIES), DH_BITS=$clog2(BHT_ENTRIES);
    reg valid[0:BTB_ENTRIES-1];
    // Full-address tags omit only bits already fixed by the selected index.
    localparam integer BT_BITS=30-BI_BITS, BW_BITS=BT_BITS+34;
    localparam integer PAYLOAD_BITS=BT_BITS+36, SEQ_BIT=BW_BITS-1;
    // Pango ADS section 5.16: native distributed RAM, one write/read per
    // parity bank. Standard attributes survive sv2v conversion. Valid bits
    // alone reset; every training write replaces the complete payload.
    // Layout: return hint, call hint, target-word-sequential, conditional,
    // full tag, 32-bit target. Hints remain the high two payload bits.
    (* syn_ramstyle = "lut_ram" *) reg [PAYLOAD_BITS-1:0] payload_even[0:BTB_ENTRIES/2-1];
    (* syn_ramstyle = "lut_ram" *) reg [PAYLOAD_BITS-1:0] payload_odd[0:BTB_ENTRIES/2-1];
`ifndef SYNTHESIS
    // Observation-only views mask stale/uninitialized invalid entries.
    wire conditional[0:BTB_ENTRIES-1];
    wire [BT_BITS-1:0] tag[0:BTB_ENTRIES-1];
    wire [31:0] target[0:BTB_ENTRIES-1];
    genvar debug_row;
    generate for(debug_row=0;debug_row<BTB_ENTRIES;debug_row=debug_row+1) begin: payload_view
        wire [PAYLOAD_BITS-1:0] value=(debug_row%2)?payload_odd[debug_row/2]:payload_even[debug_row/2];
        assign {conditional[debug_row],tag[debug_row],target[debug_row]}=
            valid[debug_row]?value[BW_BITS-2:0]:{(BW_BITS-1){1'b0}};
    end endgenerate
`endif
    // Counter payloads have no reset so each parity bank can infer LUTRAM.
    // Only the one-bit initialized map resets. Conditional BTB hits imply
    // prior conditional training of this exact word, hence an initialized
    // BHT row, even when BTB and BHT sizes differ or other PCs alias the row.
    (* syn_ramstyle = "lut_ram" *) reg [1:0] bht_even[0:BHT_ENTRIES/2-1];
    (* syn_ramstyle = "lut_ram" *) reg [1:0] bht_odd[0:BHT_ENTRIES/2-1];
    reg bht_initialized[0:BHT_ENTRIES-1];
`ifndef SYNTHESIS
    wire [1:0] direction[0:BHT_ENTRIES-1];
    genvar bht_debug_row;
    generate for(bht_debug_row=0;bht_debug_row<BHT_ENTRIES;bht_debug_row=bht_debug_row+1) begin: bht_debug
        wire [1:0] raw_value=(bht_debug_row%2)?bht_odd[bht_debug_row/2]:bht_even[bht_debug_row/2];
        assign direction[bht_debug_row]=bht_initialized[bht_debug_row]?raw_value:2'b01;
    end endgenerate
`endif
    // The core always looks up adjacent words. Route the two PCs to even/odd
    // banks before reading: each bank has only one read selector, including
    // across the last odd row -> first even row and 32-bit PC wraparound.
    localparam integer BR_BITS=(BI_BITS>1)?BI_BITS-1:1;
    localparam integer DR_BITS=(DH_BITS>1)?DH_BITS-1:1;
    wire first_odd=lookup_pc[2];
    // For adjacent queries, only an odd first word advances the even
    // bank row. Keep the increment at bank-word width and avoid the late
    // whole-PC mux after PC+4. Modulo29 handles the32-bit PC wrap exactly.
    wire [28:0] even_word=lookup_pc[31:3]+{{28{1'b0}},first_odd};
    wire [31:0] pc_even={even_word,1'b0,lookup_pc[1:0]};
    // Adjacent word queries always share the odd word's upper bits. When
    // first_odd is zero, adding4 only sets bit2; when it is one, the odd
    // query is the original PC. Preserve low fault-address bits as well.
    wire [31:0] pc_odd={lookup_pc[31:3],1'b1,lookup_pc[1:0]};
    wire [BR_BITS-1:0] be=(pc_even>>3)&(BTB_ENTRIES/2-1);
    wire [BR_BITS-1:0] bo=(pc_odd>>3)&(BTB_ENTRIES/2-1);
    wire [DR_BITS-1:0] de=(pc_even>>3)&(BHT_ENTRIES/2-1);
    wire [DR_BITS-1:0] do_idx=(pc_odd>>3)&(BHT_ENTRIES/2-1);
    wire [BI_BITS-1:0] ti=train_pc[2+:BI_BITS];
    wire [DH_BITS-1:0] td=train_pc[2+:DH_BITS];
    wire [PAYLOAD_BITS-1:0] payload_even_read=payload_even[be];
    wire [PAYLOAD_BITS-1:0] payload_odd_read=payload_odd[bo];
    wire [BW_BITS-1:0] entry_even={valid[2*be],payload_even_read[BW_BITS-2:0]};
    wire [BW_BITS-1:0] entry_odd={valid[2*bo+1],payload_odd_read[BW_BITS-2:0]};
    wire [1:0] direction_even=bht_even[de],direction_odd=bht_odd[do_idx];
    wire hit_even=entry_even[BW_BITS-1]&&(entry_even[BW_BITS-3:32]==pc_even[31:BI_BITS+2]);
    wire hit_odd=entry_odd[BW_BITS-1]&&(entry_odd[BW_BITS-3:32]==pc_odd[31:BI_BITS+2]);
    wire hit=first_odd?hit_odd:hit_even;
    wire hit1=first_odd?hit_even:hit_odd;
    wire conditional0=first_odd?entry_odd[BW_BITS-2]:entry_even[BW_BITS-2];
    wire conditional1=first_odd?entry_even[BW_BITS-2]:entry_odd[BW_BITS-2];
    // Sequential leaves depend only on the query PC. For H=PC[31:3],
    // odd+4 is {H+1,0,PC[1:0]}; even+4 is {H+PC[2],1,PC[1:0]}.
    // Six-bit prefix groups keep late BTB hit/direction out of the carry
    // expression. All arithmetic is modulo 29; preserve unaligned low bits.
    wire [28:0] sequential_word=lookup_pc[31:3];
    wire [4:0] sequential_group_all,sequential_group_prefix;
    assign sequential_group_all[0]=&sequential_word[5:0];
    assign sequential_group_all[1]=&sequential_word[11:6];
    assign sequential_group_all[2]=&sequential_word[17:12];
    assign sequential_group_all[3]=&sequential_word[23:18];
    assign sequential_group_all[4]=&sequential_word[28:24];
    assign sequential_group_prefix[0]=1'b1;
    genvar seq_group,seq_bit;
    generate for(seq_group=1;seq_group<5;seq_group=seq_group+1) begin: seq_groups
        assign sequential_group_prefix[seq_group]=&sequential_group_all[seq_group-1:0];
    end endgenerate
    wire [28:0] sequential_prefix,odd_next_word,even_next_word;
    generate for(seq_bit=0;seq_bit<29;seq_bit=seq_bit+1) begin: seq_bits
        localparam integer GROUP=seq_bit/6,BASE=GROUP*6;
        if(seq_bit==BASE) begin: first
            assign sequential_prefix[seq_bit]=sequential_group_prefix[GROUP];
        end else begin: rest
            assign sequential_prefix[seq_bit]=sequential_group_prefix[GROUP]&&
                (&sequential_word[seq_bit-1:BASE]);
        end
        assign odd_next_word[seq_bit]=sequential_word[seq_bit]^sequential_prefix[seq_bit];
        assign even_next_word[seq_bit]=sequential_word[seq_bit]^(first_odd&&sequential_prefix[seq_bit]);
    end endgenerate
    wire [31:0] sequential_even={even_next_word,1'b1,lookup_pc[1:0]};
    wire [31:0] sequential_odd={odd_next_word,1'b0,lookup_pc[1:0]};
    // Compare tags and select targets inside each bank, then exchange the
    // resulting predictions instead of exchanging full BTB records.
    wire [31:0] pred_even=(ENABLED!=0&&hit_even&&(!entry_even[BW_BITS-2]||direction_even[1]))?entry_even[31:0]:sequential_even;
    wire [31:0] pred_odd=(ENABLED!=0&&hit_odd&&(!entry_odd[BW_BITS-2]||direction_odd[1]))?entry_odd[31:0]:sequential_odd;
    wire [31:0] btb_prediction=first_odd?pred_odd:pred_even;
    wire [31:0] btb_prediction1=first_odd?pred_even:pred_odd;
    // Carry semantic equality beside target data: taken-to-PC+4 is still
    // sequential. Compare each candidate before the late direction/RAS muxes.
    wire btb_even_taken=(ENABLED!=0)&&hit_even&&(!entry_even[BW_BITS-2]||direction_even[1]);
    wire btb_odd_taken=(ENABLED!=0)&&hit_odd&&(!entry_odd[BW_BITS-2]||direction_odd[1]);
    // A hit proves query word == trained word, including the index bits.
    // Keep the low-bit test at lookup because faulting queries may be unaligned.
    wire btb_even_sequential=!btb_even_taken||
        (payload_even_read[SEQ_BIT]&&(entry_even[1:0]==pc_even[1:0]));
    wire btb_odd_sequential=!btb_odd_taken||
        (payload_odd_read[SEQ_BIT]&&(entry_odd[1:0]==pc_odd[1:0]));
    wire btb_sequential=first_odd?btb_odd_sequential:btb_even_sequential;

    // Response snapshot: capture at I-cache request acceptance, then snoop
    // every matching retired update until the next accepted request replaces it.
    reg rs_active_q,rs_valid_even_q,rs_valid_odd_q;
    reg [PAYLOAD_BITS-1:0] rs_payload_even_q,rs_payload_odd_q;
    reg [1:0] rs_direction_even_q,rs_direction_odd_q;
    reg [BR_BITS-1:0] rs_be_q,rs_bo_q;
    reg [DR_BITS-1:0] rs_de_q,rs_do_q;
    // Parallel offer and fast views: the late frontend selector never
    // addresses a table. Normal reads reuse the primary lookup view exactly.
    wire [28:0] rs_fast_even_word=response_sample_fast_pc[31:3]+{{28{1'b0}},response_sample_fast_pc[2]};
    wire [BR_BITS-1:0] rs_fast_be=rs_fast_even_word[BR_BITS-1:0]&(BTB_ENTRIES/2-1);
    wire [BR_BITS-1:0] rs_fast_bo=response_sample_fast_pc[3+:BR_BITS]&(BTB_ENTRIES/2-1);
    wire [DR_BITS-1:0] rs_fast_de=rs_fast_even_word[DR_BITS-1:0]&(BHT_ENTRIES/2-1);
    wire [DR_BITS-1:0] rs_fast_do=response_sample_fast_pc[3+:DR_BITS]&(BHT_ENTRIES/2-1);
    wire [BT_BITS-1:0] rs_normal_even_tag=pc_even[31:BI_BITS+2];
    wire [BT_BITS-1:0] rs_normal_odd_tag=pc_odd[31:BI_BITS+2];
    wire [BT_BITS-1:0] rs_fast_even_tag=rs_fast_even_word[28:BI_BITS-1];
    wire [BT_BITS-1:0] rs_fast_odd_tag=response_sample_fast_pc[31:BI_BITS+2];
    (* syn_keep=1 *) wire [PAYLOAD_BITS-1:0] rs_fast_even_read=payload_even[rs_fast_be];
    (* syn_keep=1 *) wire [PAYLOAD_BITS-1:0] rs_fast_odd_read=payload_odd[rs_fast_bo];
    wire [1:0] rs_fast_direction_even=bht_even[rs_fast_de],rs_fast_direction_odd=bht_odd[rs_fast_do];
    wire rs_fast_valid_even=valid[2*rs_fast_be],rs_fast_valid_odd=valid[2*rs_fast_bo+1];
    wire rs_fast_hit_even=rs_fast_valid_even&&(rs_fast_even_read[BW_BITS-3:32]==rs_fast_even_tag);
    wire rs_fast_hit_odd=rs_fast_valid_odd&&(rs_fast_odd_read[BW_BITS-3:32]==rs_fast_odd_tag);
    wire [BR_BITS-1:0] rs_capture_be=response_sample_fast_select?rs_fast_be:be;
    wire [BR_BITS-1:0] rs_capture_bo=response_sample_fast_select?rs_fast_bo:bo;
    wire [DR_BITS-1:0] rs_capture_de=response_sample_fast_select?rs_fast_de:de;
    wire [DR_BITS-1:0] rs_capture_do=response_sample_fast_select?rs_fast_do:do_idx;
    wire rs_btb_write=(ENABLED!=0)&&train_valid;
    wire rs_bht_write=rs_btb_write&&train_conditional;
    reg [BT_BITS-1:0] rs_tag_even_q,rs_tag_odd_q;
`ifndef SYNTHESIS
    // Old hit registers remain only as independent simulation oracles.
    reg rs_hit_even_q,rs_hit_odd_q;
`endif
    wire [BT_BITS-1:0] rs_capture_even_tag=response_sample_fast_select?rs_fast_even_tag:rs_normal_even_tag;
    wire [BT_BITS-1:0] rs_capture_odd_tag=response_sample_fast_select?rs_fast_odd_tag:rs_normal_odd_tag;
    // Independent response-PC read port, shared training state.
    wire rp_first_odd=response_lookup_pc[2];
    // For adjacent queries, only an odd rp_first word advances the even
    // bank row. Keep the increment at bank-word width and avoid the late
    // whole-PC mux after PC+4. Modulo29 handles the32-bit PC wrap exactly.
    wire [28:0] rp_even_word=response_lookup_pc[31:3]+{{28{1'b0}},rp_first_odd};
    wire [31:0] rp_pc_even={rp_even_word,1'b0,response_lookup_pc[1:0]};
    // Adjacent word queries always share the odd word's upper bits. When
    // rp_first_odd is zero, adding4 only sets bit2; when it is one, the odd
    // query is the original PC. Preserve low fault-address bits as well.
    wire [31:0] rp_pc_odd={response_lookup_pc[31:3],1'b1,response_lookup_pc[1:0]};
    wire [BR_BITS-1:0] rp_be=(rp_pc_even>>3)&(BTB_ENTRIES/2-1);
    wire [BR_BITS-1:0] rp_bo=(rp_pc_odd>>3)&(BTB_ENTRIES/2-1);
    wire [DR_BITS-1:0] rp_de=(rp_pc_even>>3)&(BHT_ENTRIES/2-1);
    wire [DR_BITS-1:0] rp_do_idx=(rp_pc_odd>>3)&(BHT_ENTRIES/2-1);
    wire [PAYLOAD_BITS-1:0] rp_payload_even_read=rs_payload_even_q;
    wire [PAYLOAD_BITS-1:0] rp_payload_odd_read=rs_payload_odd_q;
    wire [BW_BITS-1:0] rp_entry_even={rs_valid_even_q,rp_payload_even_read[BW_BITS-2:0]};
    wire [BW_BITS-1:0] rp_entry_odd={rs_valid_odd_q,rp_payload_odd_read[BW_BITS-2:0]};
    wire [1:0] rp_direction_even=rs_direction_even_q,rp_direction_odd=rs_direction_odd_q;
    // Resolve the response tag from the existing captured payload boundary.
    // Payload/valid/tag/direction capture and held training snoops are unchanged.
    wire rp_hit_even=rs_valid_even_q&&(rs_payload_even_q[BW_BITS-3:32]==rs_tag_even_q);
    wire rp_hit_odd=rs_valid_odd_q&&(rs_payload_odd_q[BW_BITS-3:32]==rs_tag_odd_q);
    wire rp_hit=rp_first_odd?rp_hit_odd:rp_hit_even;
    wire rp_hit1=rp_first_odd?rp_hit_even:rp_hit_odd;
    wire rp_conditional0=rp_first_odd?rp_entry_odd[BW_BITS-2]:rp_entry_even[BW_BITS-2];
    wire rp_conditional1=rp_first_odd?rp_entry_even[BW_BITS-2]:rp_entry_odd[BW_BITS-2];
    // Sequential leaves depend only on the query PC. For H=PC[31:3],
    // odd+4 is {H+1,0,PC[1:0]}; even+4 is {H+PC[2],1,PC[1:0]}.
    // Six-bit prefix groups keep late BTB rp_hit/direction out of the carry
    // expression. All arithmetic is modulo 29; preserve unaligned low bits.
    wire [28:0] rp_sequential_word=response_lookup_pc[31:3];
    wire [4:0] rp_sequential_group_all,rp_sequential_group_prefix;
    assign rp_sequential_group_all[0]=&rp_sequential_word[5:0];
    assign rp_sequential_group_all[1]=&rp_sequential_word[11:6];
    assign rp_sequential_group_all[2]=&rp_sequential_word[17:12];
    assign rp_sequential_group_all[3]=&rp_sequential_word[23:18];
    assign rp_sequential_group_all[4]=&rp_sequential_word[28:24];
    assign rp_sequential_group_prefix[0]=1'b1;
    genvar rp_seq_group,rp_seq_bit;
    generate for(rp_seq_group=1;rp_seq_group<5;rp_seq_group=rp_seq_group+1) begin: rp_seq_groups
        assign rp_sequential_group_prefix[rp_seq_group]=&rp_sequential_group_all[rp_seq_group-1:0];
    end endgenerate
    wire [28:0] rp_sequential_prefix,rp_odd_next_word,rp_even_next_word;
    generate for(rp_seq_bit=0;rp_seq_bit<29;rp_seq_bit=rp_seq_bit+1) begin: rp_seq_bits
        localparam integer rp_GROUP=rp_seq_bit/6,rp_BASE=rp_GROUP*6;
        if(rp_seq_bit==rp_BASE) begin: rp_first
            assign rp_sequential_prefix[rp_seq_bit]=rp_sequential_group_prefix[rp_GROUP];
        end else begin: rp_rest
            assign rp_sequential_prefix[rp_seq_bit]=rp_sequential_group_prefix[rp_GROUP]&&
                (&rp_sequential_word[rp_seq_bit-1:rp_BASE]);
        end
        assign rp_odd_next_word[rp_seq_bit]=rp_sequential_word[rp_seq_bit]^rp_sequential_prefix[rp_seq_bit];
        assign rp_even_next_word[rp_seq_bit]=rp_sequential_word[rp_seq_bit]^(rp_first_odd&&rp_sequential_prefix[rp_seq_bit]);
    end endgenerate
    wire [31:0] rp_sequential_even={rp_even_next_word,1'b1,response_lookup_pc[1:0]};
    wire [31:0] rp_sequential_odd={rp_odd_next_word,1'b0,response_lookup_pc[1:0]};
    // Compare tags and select targets inside each bank, then exchange the
    // resulting predictions instead of exchanging full BTB records.
    wire [31:0] rp_pred_even=(ENABLED!=0&&rp_hit_even&&(!rp_entry_even[BW_BITS-2]||rp_direction_even[1]))?rp_entry_even[31:0]:rp_sequential_even;
    wire [31:0] rp_pred_odd=(ENABLED!=0&&rp_hit_odd&&(!rp_entry_odd[BW_BITS-2]||rp_direction_odd[1]))?rp_entry_odd[31:0]:rp_sequential_odd;
    wire [31:0] rp_btb_prediction=rp_first_odd?rp_pred_odd:rp_pred_even;
    wire [31:0] rp_btb_prediction1=rp_first_odd?rp_pred_even:rp_pred_odd;
    // Carry semantic equality beside target data: taken-to-PC+4 is still
    // sequential. Compare each candidate before the late direction/RAS muxes.
    wire rp_btb_even_taken=(ENABLED!=0)&&rp_hit_even&&(!rp_entry_even[BW_BITS-2]||rp_direction_even[1]);
    wire rp_btb_odd_taken=(ENABLED!=0)&&rp_hit_odd&&(!rp_entry_odd[BW_BITS-2]||rp_direction_odd[1]);
    // A rp_hit proves query word == trained word, including the index bits.
    // Keep the low-bit test at lookup because faulting queries may rp_be unaligned.
    wire rp_btb_even_sequential=!rp_btb_even_taken||
        (rp_payload_even_read[SEQ_BIT]&&(rp_entry_even[1:0]==rp_pc_even[1:0]));
    wire rp_btb_odd_sequential=!rp_btb_odd_taken||
        (rp_payload_odd_read[SEQ_BIT]&&(rp_entry_odd[1:0]==rp_pc_odd[1:0]));
    wire rp_btb_sequential=rp_first_odd?rp_btb_odd_sequential:rp_btb_even_sequential;
    wire rp_safe_even=!(rp_hit_even&&(|rp_payload_even_read[PAYLOAD_BITS-1:PAYLOAD_BITS-2]));
    wire rp_safe_odd=!(rp_hit_odd&&(|rp_payload_odd_read[PAYLOAD_BITS-1:PAYLOAD_BITS-2]));
    wire [31:0] rp_safe_prediction_even=rp_safe_even?rp_pred_even:rp_sequential_even;
    wire [31:0] rp_safe_prediction_odd=rp_safe_odd?rp_pred_odd:rp_sequential_odd;
    assign response_prediction=rp_first_odd?rp_safe_prediction_odd:rp_safe_prediction_even;
    assign response_prediction1=rp_first_odd?rp_safe_prediction_even:rp_safe_prediction_odd;
    wire rp_seq_even=!rp_safe_even||rp_btb_even_sequential;
    wire rp_seq_odd=!rp_safe_odd||rp_btb_odd_sequential;
    assign response_sequential=rp_first_odd?rp_seq_odd:rp_seq_even;
    assign response_sequential1=rp_first_odd?rp_seq_even:rp_seq_odd;

    // ISA hints affect prediction only. Architectural JAL/JALR execution is unchanged.
    wire train_jal=(train_insn[6:0]==7'h6f);
    wire train_jalr=(train_insn[6:0]==7'h67)&&(train_insn[14:12]==3'b000);
    wire rd_link=(train_insn[11:7]==5'd1)||(train_insn[11:7]==5'd5);
    wire rs1_link=(train_insn[19:15]==5'd1)||(train_insn[19:15]==5'd5);
    wire pop_hint=train_jalr&&rs1_link&&(!rd_link||(train_insn[11:7]!=train_insn[19:15]));
    wire ras_push=(RAS_DEPTH!=0)&&(ENABLED!=0)&&train_valid&&(train_jal||train_jalr)&&rd_link;
    wire ras_pop=(RAS_DEPTH!=0)&&(ENABLED!=0)&&train_valid&&pop_hint;
    wire ras_nonempty,ras_override,ras_return1,ras_early_valid;
    wire [31:0] ras_top;
    wire [31:0] ras_early_return;
    // A resolved E-stage call can overlap lookup of a two-instruction callee's
    // return. Forward its link without speculatively changing committed state.
    wire ras_call_forward=ras_override&&ras_call_valid;
    wire [31:0] ras_lookup_top=ras_early_valid?ras_early_return:
        ras_call_forward?ras_call_return:ras_top;
    assign prediction=ras_override?ras_lookup_top:btb_prediction;
    wire ras_early_sequential=(ras_early_return==lookup_pc+32'd4);
    wire ras_call_sequential=(ras_call_return==lookup_pc+32'd4);
    wire ras_top_sequential=(ras_top==lookup_pc+32'd4);
    wire ras_sequential=ras_early_valid?ras_early_sequential:
        ras_call_forward?ras_call_sequential:ras_top_sequential;
    assign prediction_is_sequential=ras_override?ras_sequential:btb_sequential;
    wire ras_override1=(RAS_DEPTH!=0)&&(ENABLED!=0)&&hit1&&!conditional1&&
        ras_return1&&(ras_nonempty||ras_early_valid||ras_call_valid);
    assign prediction1=ras_override1?ras_lookup_top:btb_prediction1;
    generate if(RAS_DEPTH!=0) begin: ras_enabled
        localparam integer COUNT_BITS=$clog2(RAS_DEPTH+1);
        reg [COUNT_BITS-1:0] count_q;
        // Top-first shift stack: fixed top read avoids a variable-index mux.
        // Overflow drops the oldest entry; underflow never wraps the count.
        reg [31:0] stack_q[0:RAS_DEPTH-1];
`ifndef SYNTHESIS
        wire return_entry[0:BTB_ENTRIES-1],call_entry[0:BTB_ENTRIES-1];
        genvar hint_view;
        for(hint_view=0;hint_view<BTB_ENTRIES;hint_view=hint_view+1) begin: hint_debug
            wire [PAYLOAD_BITS-1:0] value=(hint_view%2)?payload_odd[hint_view/2]:payload_even[hint_view/2];
            assign {return_entry[hint_view],call_entry[hint_view]}=
                valid[hint_view]?value[PAYLOAD_BITS-1-:2]:2'b0;
        end
`endif
        reg early_valid_q;
        // Precompute both return candidates in the inactive bank. Its write
        // enables depend only on the registered active-bank pointer, never on
        // late fetch acceptance, call hints, slot selection or flush controls.
        reg [31:0] early_bank0_lo_q,early_bank0_hi_q;
        reg [31:0] early_bank1_lo_q,early_bank1_hi_q;
        reg early_bank_q,early_slot_q,early_zero_q;
        wire [31:0] early_selected_lo=early_bank_q?early_bank1_lo_q:early_bank0_lo_q;
        wire [31:0] early_selected_hi=early_bank_q?early_bank1_hi_q:early_bank0_hi_q;
        wire [31:0] early_return_q=early_zero_q?32'b0:
            (early_slot_q?early_selected_hi:early_selected_lo);
        always @(posedge clk) begin
            if(early_bank_q) begin
                early_bank0_lo_q<=lookup_pc+32'd4;
                early_bank0_hi_q<=lookup_pc1+32'd4;
            end else begin
                early_bank1_lo_q<=lookup_pc+32'd4;
                early_bank1_hi_q<=lookup_pc1+32'd4;
            end
        end
        wire [31:0] train_return=train_pc+32'd4;
        assign ras_early_valid=early_valid_q;
        assign ras_early_return=early_return_q;
        wire [1:0] hint_even=payload_even_read[PAYLOAD_BITS-1-:2];
        wire [1:0] hint_odd=payload_odd_read[PAYLOAD_BITS-1-:2];
        wire return0=first_odd?hint_odd[1]:hint_even[1];
        wire call0=first_odd?hint_odd[0]:hint_even[0];
        wire call1=first_odd?hint_even[0]:hint_odd[0];
        wire fetch_call0=lookup_accept&&hit&&call0;
        wire fetch_call1=lookup_accept&&lookup_second_valid&&hit1&&call1;
        always @(posedge clk) begin
            if(rst||fetch_flush) begin
                early_valid_q<=0;early_bank_q<=0;early_slot_q<=0;early_zero_q<=1;
            end else begin
                if(ras_push&&early_valid_q&&train_return==early_return_q)
                    early_valid_q<=0;
                if(fetch_call0||fetch_call1) begin
                    // The inactive bank captures this cycle's two candidates
                    // at this very edge. Only three bits need the late enable.
                    early_valid_q<=1;
                    early_bank_q<=!early_bank_q;
                    early_slot_q<=fetch_call1;
                    early_zero_q<=0;
                end
            end
        end
`ifndef SYNTHESIS
        reg [31:0] early_return_oracle;
        reg early_valid_oracle;
        integer rasbuffer_checked=0,rasbuffer_calls=0,rasbuffer_slot1=0;
        always @(posedge clk) begin
            if(!rst) begin
                assert({early_valid_q,early_return_q}==={early_valid_oracle,early_return_oracle})
                    else $fatal(1,"RASBUFFER_EARLY_STATE_MISMATCH");
                rasbuffer_checked=rasbuffer_checked+1;
                if(fetch_call0||fetch_call1) rasbuffer_calls=rasbuffer_calls+1;
                if(fetch_call1) rasbuffer_slot1=rasbuffer_slot1+1;
            end
            if(rst||fetch_flush) begin early_valid_oracle<=0;early_return_oracle<=0;end
            else begin
                if(ras_push&&early_valid_oracle&&train_return==early_return_oracle)
                    early_valid_oracle<=0;
                if(fetch_call0||fetch_call1) begin
                    early_valid_oracle<=1;
                    early_return_oracle<=(fetch_call1?lookup_pc1:lookup_pc)+32'd4;
                end
            end
        end
        final $display("RASBUFFER_COVER checked=%0d calls=%0d slot1=%0d",rasbuffer_checked,rasbuffer_calls,rasbuffer_slot1);
`endif
        assign ras_return1=first_odd?hint_even[1]:hint_odd[1];
        integer r;
        assign ras_nonempty=(count_q!=0);
        assign ras_top=stack_q[0];
        assign ras_override=(ENABLED!=0)&&hit&&!conditional0&&return0&&
            (ras_nonempty||ras_early_valid||ras_call_valid);
        always @(posedge clk) begin
            if(rst||ras_flush) begin
                count_q<=0;
                for(r=0;r<RAS_DEPTH;r=r+1) stack_q[r]<=0;
            end else if(ras_push) begin
                stack_q[0]<=train_return;
                if(!ras_pop) begin
                    for(r=1;r<RAS_DEPTH;r=r+1) stack_q[r]<=stack_q[r-1];
                    if(count_q<RAS_DEPTH) count_q<=count_q+1'b1;
                end else if(count_q==0) count_q<=1;
            end else if(ras_pop&&ras_nonempty) begin
                for(r=0;r<RAS_DEPTH-1;r=r+1) stack_q[r]<=stack_q[r+1];
                stack_q[RAS_DEPTH-1]<=0;
                count_q<=count_q-1'b1;
            end
        end
    end else begin: ras_disabled
        assign ras_nonempty=1'b0;
        assign ras_top=32'b0;
        assign ras_override=1'b0;
        assign ras_return1=1'b0;
        assign ras_early_valid=1'b0;
        assign ras_early_return=32'b0;
    end endgenerate
    // Explicit 30-bit modulo arithmetic preserves fffffffc -> 00000000.
    wire [29:0] train_next_word=train_pc[31:2]+30'd1;
    wire train_word_sequential=(train_target[31:2]==train_next_word);
    wire [PAYLOAD_BITS-1:0] training_payload={
        pop_hint&&(train_insn[31:20]==12'b0),
        (train_jal||train_jalr)&&rd_link,
        train_word_sequential,train_conditional,train_pc[31:BI_BITS+2],train_target};
    always @(posedge clk) begin
        if(!rst&&ENABLED!=0&&train_valid&&!ti[0]) payload_even[ti>>1]<=training_payload;
    end
    always @(posedge clk) begin
        if(!rst&&ENABLED!=0&&train_valid&&ti[0]) payload_odd[ti>>1]<=training_payload;
    end
    genvar h;
    // Per-entry sequential blocks keep reset synthesizable and compatible
    // with Verilator 4.038 even when the table exceeds its loop-unroll limit.
    generate for(h=0;h<BTB_ENTRIES;h=h+1) begin: btb_entry
        always @(posedge clk) begin
            if(rst) valid[h]<=0;
            else if(ENABLED!=0&&train_valid&&ti==h[BI_BITS-1:0]) valid[h]<=1;
        end
    end endgenerate
    function [1:0] bht_saturate;
        input [1:0] value;
        input taken;
        begin
            bht_saturate=value;
            if(taken&&value!=2'b11) bht_saturate=value+1'b1;
            if(!taken&&value!=2'b00) bht_saturate=value-1'b1;
        end
    endfunction
    wire [DR_BITS-1:0] bht_train_row=td>>1;
    wire [1:0] bht_train_even=bht_initialized[td]?bht_even[bht_train_row]:2'b01;
    wire [1:0] bht_train_odd=bht_initialized[td]?bht_odd[bht_train_row]:2'b01;
    wire [1:0] bht_next_even=bht_saturate(bht_train_even,train_taken);
    wire [1:0] bht_next_odd=bht_saturate(bht_train_odd,train_taken);
    always @(posedge clk) begin
        if(!rst&&ENABLED!=0&&train_valid&&train_conditional&&!td[0])
            bht_even[bht_train_row]<=bht_next_even;
    end
    always @(posedge clk) begin
        if(!rst&&ENABLED!=0&&train_valid&&train_conditional&&td[0])
            bht_odd[bht_train_row]<=bht_next_odd;
    end
    generate for(h=0;h<BHT_ENTRIES;h=h+1) begin: bht_counter
        always @(posedge clk) begin
            if(rst) bht_initialized[h]<=0;
            else if(ENABLED!=0&&train_valid&&train_conditional&&td==h[DH_BITS-1:0])
                bht_initialized[h]<=1;
        end
    end endgenerate
    // RESPONSE_PARALLEL_BYPASS_BEGIN
    // Resolve training collisions independently for both addresses.
    // Same-edge training wins before the final request-address select.
    wire rs_normal_even_train=rs_btb_write&&(ti[0]==1'b0)&&((ti>>1)==be);
    wire rs_normal_even_bht_train=rs_bht_write&&(td[0]==1'b0)&&((td>>1)==de);
    (* syn_keep=1 *) wire [PAYLOAD_BITS-1:0] rs_normal_even_payload=rs_normal_even_train?training_payload:payload_even_read;
    wire rs_normal_even_valid=rs_normal_even_train||valid[2*be];
    wire rs_normal_even_hit=rs_normal_even_train?(training_payload[BW_BITS-3:32]==rs_normal_even_tag):hit_even;
    wire [1:0] rs_normal_even_direction=rs_normal_even_bht_train?bht_next_even:direction_even;
    wire rs_normal_odd_train=rs_btb_write&&(ti[0]==1'b1)&&((ti>>1)==bo);
    wire rs_normal_odd_bht_train=rs_bht_write&&(td[0]==1'b1)&&((td>>1)==do_idx);
    (* syn_keep=1 *) wire [PAYLOAD_BITS-1:0] rs_normal_odd_payload=rs_normal_odd_train?training_payload:payload_odd_read;
    wire rs_normal_odd_valid=rs_normal_odd_train||valid[2*bo+1];
    wire rs_normal_odd_hit=rs_normal_odd_train?(training_payload[BW_BITS-3:32]==rs_normal_odd_tag):hit_odd;
    wire [1:0] rs_normal_odd_direction=rs_normal_odd_bht_train?bht_next_odd:direction_odd;
    wire rs_fast_even_train=rs_btb_write&&(ti[0]==1'b0)&&((ti>>1)==rs_fast_be);
    wire rs_fast_even_bht_train=rs_bht_write&&(td[0]==1'b0)&&((td>>1)==rs_fast_de);
    (* syn_keep=1 *) wire [PAYLOAD_BITS-1:0] rs_fast_even_payload=rs_fast_even_train?training_payload:rs_fast_even_read;
    wire rs_fast_even_valid=rs_fast_even_train||valid[2*rs_fast_be];
    wire rs_fast_even_hit=rs_fast_even_train?(training_payload[BW_BITS-3:32]==rs_fast_even_tag):rs_fast_hit_even;
    wire [1:0] rs_fast_even_direction=rs_fast_even_bht_train?bht_next_even:rs_fast_direction_even;
    wire rs_fast_odd_train=rs_btb_write&&(ti[0]==1'b1)&&((ti>>1)==rs_fast_bo);
    wire rs_fast_odd_bht_train=rs_bht_write&&(td[0]==1'b1)&&((td>>1)==rs_fast_do);
    (* syn_keep=1 *) wire [PAYLOAD_BITS-1:0] rs_fast_odd_payload=rs_fast_odd_train?training_payload:rs_fast_odd_read;
    wire rs_fast_odd_valid=rs_fast_odd_train||valid[2*rs_fast_bo+1];
    wire rs_fast_odd_hit=rs_fast_odd_train?(training_payload[BW_BITS-3:32]==rs_fast_odd_tag):rs_fast_hit_odd;
    wire [1:0] rs_fast_odd_direction=rs_fast_odd_bht_train?bht_next_odd:rs_fast_direction_odd;
    wire [PAYLOAD_BITS-1:0] rs_take_even_payload=response_sample_fast_select?rs_fast_even_payload:rs_normal_even_payload;
    wire rs_take_even_valid=response_sample_fast_select?rs_fast_even_valid:rs_normal_even_valid;
    wire rs_take_even_hit=response_sample_fast_select?rs_fast_even_hit:rs_normal_even_hit;
    wire [1:0] rs_take_even_direction=response_sample_fast_select?rs_fast_even_direction:rs_normal_even_direction;
    wire [PAYLOAD_BITS-1:0] rs_take_odd_payload=response_sample_fast_select?rs_fast_odd_payload:rs_normal_odd_payload;
    wire rs_take_odd_valid=response_sample_fast_select?rs_fast_odd_valid:rs_normal_odd_valid;
    wire rs_take_odd_hit=response_sample_fast_select?rs_fast_odd_hit:rs_normal_odd_hit;
    wire [1:0] rs_take_odd_direction=response_sample_fast_select?rs_fast_odd_direction:rs_normal_odd_direction;
    // RESPONSE_PARALLEL_BYPASS_END
    // RESPONSE_HIT_UPDATE_BEGIN
    always @(posedge clk) begin
        if(rst) begin rs_tag_even_q<=0;rs_tag_odd_q<=0;end
        else if(response_sample_accept) begin
            rs_tag_even_q<=rs_capture_even_tag;rs_tag_odd_q<=rs_capture_odd_tag;
        end
    end
`ifndef SYNTHESIS
    // Preserve the old hit-update equations as an independent temporal oracle.
    always @(posedge clk) begin
        if(rst) begin rs_hit_even_q<=0;rs_hit_odd_q<=0;end
        else if(response_sample_accept) begin
            rs_hit_even_q<=rs_take_even_hit;rs_hit_odd_q<=rs_take_odd_hit;
        end else if(rs_btb_write&&rs_active_q) begin
            if(!ti[0]&&((ti>>1)==rs_be_q))
                rs_hit_even_q<=training_payload[BW_BITS-3:32]==rs_tag_even_q;
            if(ti[0]&&((ti>>1)==rs_bo_q))
                rs_hit_odd_q<=training_payload[BW_BITS-3:32]==rs_tag_odd_q;
        end
    end
    always @(posedge clk) if(!rst&&rs_active_q) begin
        assert(rp_hit_even===rs_hit_even_q) else $fatal(1,"RETIME_EVEN_OLD_HIT_IDENTITY");
        assert(rp_hit_odd===rs_hit_odd_q) else $fatal(1,"RETIME_ODD_OLD_HIT_IDENTITY");
    end
`endif
    // RESPONSE_HIT_UPDATE_END
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst&&rs_active_q) begin
        assert(rs_hit_even_q===(rs_valid_even_q&&
            (rs_payload_even_q[BW_BITS-3:32]==rp_pc_even[31:BI_BITS+2])))
            else $fatal(1,"RESPONSE_HIT_EVEN_IDENTITY");
        assert(rs_hit_odd_q===(rs_valid_odd_q&&
            (rs_payload_odd_q[BW_BITS-3:32]==rp_pc_odd[31:BI_BITS+2])))
            else $fatal(1,"RESPONSE_HIT_ODD_IDENTITY");
    end
`endif
    // RESPONSE_SNAPSHOT_UPDATE_BEGIN
    always @(posedge clk) begin
        if(rst) begin
            rs_active_q<=0;rs_valid_even_q<=0;rs_valid_odd_q<=0;
            rs_be_q<=0;rs_bo_q<=0;rs_de_q<=0;rs_do_q<=0;
        end else if(response_sample_accept) begin
            rs_active_q<=1;
            rs_be_q<=rs_capture_be;rs_bo_q<=rs_capture_bo;
            rs_de_q<=rs_capture_de;rs_do_q<=rs_capture_do;
            rs_payload_even_q<=rs_take_even_payload;
            rs_payload_odd_q<=rs_take_odd_payload;
            rs_valid_even_q<=rs_take_even_valid;
            rs_valid_odd_q<=rs_take_odd_valid;
            rs_direction_even_q<=rs_take_even_direction;
            rs_direction_odd_q<=rs_take_odd_direction;
        end else if(rs_active_q) begin
            // Held snapshots keep the original row-based alias snoop.
            if(rs_btb_write) begin
                if(!ti[0]&&((ti>>1)==rs_be_q)) begin
                    rs_payload_even_q<=training_payload;rs_valid_even_q<=1;
                end
                if(ti[0]&&((ti>>1)==rs_bo_q)) begin
                    rs_payload_odd_q<=training_payload;rs_valid_odd_q<=1;
                end
            end
            if(rs_bht_write) begin
                if(!td[0]&&((td>>1)==rs_de_q)) rs_direction_even_q<=bht_next_even;
                if(td[0]&&((td>>1)==rs_do_q)) rs_direction_odd_q<=bht_next_odd;
            end
        end
    end
    // RESPONSE_SNAPSHOT_UPDATE_END
`ifndef SYNTHESIS
    integer rs_parallel_normal=0,rs_parallel_fast=0;
    always @(posedge clk) if(!rst&&response_sample_accept) begin
        assert(response_sample_pc===(response_sample_fast_select?response_sample_fast_pc:lookup_pc))
            else $fatal(1,"RESPONSE_PARALLEL_ADDRESS_CONTRACT");
        if(response_sample_fast_select) rs_parallel_fast<=rs_parallel_fast+1;
        else rs_parallel_normal<=rs_parallel_normal+1;
    end
    final $display("RESPONSE_PARALLEL_COVER normal=%0d fast=%0d",rs_parallel_normal,rs_parallel_fast);
`endif
`ifndef SYNTHESIS
    reg [31:0] rs_observed_pc_q;
    integer rs_captures=0,rs_same_edge_train=0,rs_hold_train=0;
    always @(posedge clk) begin
        if(rst) rs_observed_pc_q<=0;
        else if(response_sample_accept) rs_observed_pc_q<=response_sample_pc;
        if(!rst&&response_sample_accept) rs_captures<=rs_captures+1;
        if(!rst&&response_sample_accept&&rs_btb_write) rs_same_edge_train<=rs_same_edge_train+1;
        if(!rst&&!response_sample_accept&&rs_active_q&&rs_btb_write) rs_hold_train<=rs_hold_train+1;
        if(!rst&&rs_active_q) begin
            assert(rs_observed_pc_q===response_lookup_pc) else $fatal(1,"RESPONSE_SNAPSHOT_PC");
            assert(rs_be_q===rp_be&&rs_bo_q===rp_bo&&rs_de_q===rp_de&&rs_do_q===rp_do_idx)
                else $fatal(1,"RESPONSE_SNAPSHOT_INDICES");
            assert(rs_valid_even_q===valid[2*rp_be]&&rs_valid_odd_q===valid[2*rp_bo+1])
                else $fatal(1,"RESPONSE_SNAPSHOT_VALID");
            if(valid[2*rp_be]) assert(rs_payload_even_q===payload_even[rp_be])
                else $fatal(1,"RESPONSE_SNAPSHOT_EVEN_PAYLOAD");
            if(valid[2*rp_bo+1]) assert(rs_payload_odd_q===payload_odd[rp_bo])
                else $fatal(1,"RESPONSE_SNAPSHOT_ODD_PAYLOAD");
            if(bht_initialized[2*rp_de]) assert(rs_direction_even_q===bht_even[rp_de])
                else $fatal(1,"RESPONSE_SNAPSHOT_EVEN_BHT");
            if(bht_initialized[2*rp_do_idx+1]) assert(rs_direction_odd_q===bht_odd[rp_do_idx])
                else $fatal(1,"RESPONSE_SNAPSHOT_ODD_BHT");
        end
    end
    final $display("RESPONSE_SNAPSHOT_COVER captures=%0d simultaneous_train=%0d held_train=%0d",
        rs_captures,rs_same_edge_train,rs_hold_train);
`endif
`ifndef SYNTHESIS
    integer bhtram_checked=0,bhtram_even_hits=0,bhtram_odd_hits=0;
    integer bhtram_first_train=0,bhtram_updates=0,bhtram_query_write=0;
    reg bhtram_pending;
    reg [DH_BITS-1:0] bhtram_pending_index;
    reg [1:0] bhtram_pending_value;
    task bhtram_check_lookup;
        begin
            if(!rst&&!$isunknown({lookup_pc,lookup_pc1})) begin
                // These assertions are observation only; no initialized-map
                // selector is placed on the synthesized prediction path.
                if(hit_even&&entry_even[BW_BITS-2]) begin
                    assert(bht_initialized[2*de]===1'b1&&!$isunknown(direction_even))
                        else $fatal(1,"BHTRAM_EVEN_HIT_UNINITIALIZED");
                    bhtram_even_hits=bhtram_even_hits+1;
                end
                if(hit_odd&&entry_odd[BW_BITS-2]) begin
                    assert(bht_initialized[2*do_idx+1]===1'b1&&!$isunknown(direction_odd))
                        else $fatal(1,"BHTRAM_ODD_HIT_UNINITIALIZED");
                    bhtram_odd_hits=bhtram_odd_hits+1;
                end
                assert(btb_even_taken===((ENABLED!=0)&&hit_even&&(!entry_even[BW_BITS-2]||direction[2*de][1])))
                    else $fatal(1,"BHTRAM_EVEN_DEFAULT_GUARD_MISMATCH");
                assert(btb_odd_taken===((ENABLED!=0)&&hit_odd&&(!entry_odd[BW_BITS-2]||direction[2*do_idx+1][1])))
                    else $fatal(1,"BHTRAM_ODD_DEFAULT_GUARD_MISMATCH");
                bhtram_checked=bhtram_checked+1;
            end
        end
    endtask
    always @(posedge clk) begin
        bhtram_check_lookup();
        bhtram_pending=!rst&&(ENABLED!=0)&&train_valid&&train_conditional;
        bhtram_pending_index=td;
        bhtram_pending_value=td[0]?bht_next_odd:bht_next_even;
        if(bhtram_pending) begin
            bhtram_updates=bhtram_updates+1;
            if(!bht_initialized[td]) bhtram_first_train=bhtram_first_train+1;
        end
        // Check the settled state after the same edge's RAM, initialized bit
        // and BTB payload writes, without depending on simulator NBA ordering.
        #0.001;
        bhtram_check_lookup();
        if(bhtram_pending) begin
            assert(bht_initialized[bhtram_pending_index]===1'b1&&
                   direction[bhtram_pending_index]===bhtram_pending_value)
                else $fatal(1,"BHTRAM_SAME_EDGE_TRAIN_VALUE");
            if((lookup_pc[2+:DH_BITS]===bhtram_pending_index)||
               (lookup_pc1[2+:DH_BITS]===bhtram_pending_index))
                bhtram_query_write=bhtram_query_write+1;
        end
    end
    final $display("BHTRAM_COVER checked=%0d even_hits=%0d odd_hits=%0d first_train=%0d updates=%0d query_write=%0d",
        bhtram_checked,bhtram_even_hits,bhtram_odd_hits,bhtram_first_train,bhtram_updates,bhtram_query_write);
`endif
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst)
        assert(prediction_is_sequential === (prediction==lookup_pc+32'd4))
            else $fatal(1,"PREDICTION_SEQUENTIAL_MISMATCH");
    always @(posedge clk) if(!rst&&lookup_pc1!=(lookup_pc+32'd4)) begin
        $display("ERROR: banked predictor requires adjacent lookup PCs");$finish;
    end
    always @(posedge clk) if(!rst&&ENABLED!=0&&train_valid&&train_pc[1:0]!=2'b00) begin
        $display("ERROR: predictor training PC must be word aligned");$finish;
    end
    initial if(BTB_ENTRIES<2||(BTB_ENTRIES&(BTB_ENTRIES-1))!=0||
               BHT_ENTRIES<2||(BHT_ENTRIES&(BHT_ENTRIES-1))!=0)
        begin $display("ERROR: predictor table sizes must be powers of two >= 2");$finish;end
    initial if(RAS_DEPTH!=0&&RAS_DEPTH!=4&&RAS_DEPTH!=8)
        begin $display("ERROR: RAS_DEPTH must be 0, 4, or 8");$finish;end
`endif
endmodule
