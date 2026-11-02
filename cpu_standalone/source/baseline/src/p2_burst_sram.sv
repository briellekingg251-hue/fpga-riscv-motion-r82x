// A single shared synchronous SRAM image. No RAM reset loop and no hidden I/D copy.
module p2_burst_sram #(
    parameter [31:0] RAM_BASE=32'h80000000,
    parameter integer RAM_BYTES=131072,
    parameter INIT_FILE=""
) (
    input wire clk, rst,
    input wire cmd_valid, output wire cmd_ready, input wire cmd_write,
    input wire [31:0] cmd_addr, input wire [7:0] cmd_len,
    input wire w_valid, output wire w_ready, input wire [31:0] w_data,
    input wire [3:0] w_be, input wire w_last,
    output wire r_valid, input wire r_ready, output wire [31:0] r_data,
    output wire r_error, r_last
);
    localparam integer AW=$clog2(RAM_BYTES/4);
    localparam [1:0] IDLE=0, READ=1, WRITE=2, ACK=3;
    reg [1:0] state;
    reg [31:0] mem [0:RAM_BYTES/4-1];
    reg [31:0] read_q;
    reg [AW-1:0] word_addr;
    reg [7:0] beat, length;
    reg bad;
    localparam integer END_BITS=(AW>8?AW:8)+1;
    localparam integer ALIGNED_REGION=(RAM_BYTES>=8)&&
        ((RAM_BYTES&(RAM_BYTES-1))==0)&&((RAM_BASE&(RAM_BYTES-1))==0)&&
        (({1'b0,RAM_BASE}+RAM_BYTES)<=33'h100000000);
    wire cmd_bad;
    generate if(ALIGNED_REGION) begin: bounded_command
        wire address_tag_match=(cmd_addr&~(RAM_BYTES-1))==RAM_BASE;
        wire [END_BITS-1:0] offset_words=END_BITS'((cmd_addr&(RAM_BYTES-1))>>2);
        wire [END_BITS-1:0] end_words=offset_words+END_BITS'(cmd_len);
        assign cmd_bad=(|cmd_addr[1:0])||(cmd_len==0)||!address_tag_match||
            (end_words>END_BITS'(RAM_BYTES/4));
    end else begin: generic_command
        assign cmd_bad=cmd_addr[1:0]!=0 || cmd_len==0 ||
            {1'b0,cmd_addr}<{1'b0,RAM_BASE} ||
            {1'b0,cmd_addr}+({25'b0,cmd_len}<<2)>{1'b0,RAM_BASE}+RAM_BYTES;
    end endgenerate
`ifndef SYNTHESIS
    integer bounded_command_checks=0;
    always @(posedge clk) if(!rst&&cmd_valid) begin
        bounded_command_checks=bounded_command_checks+1;
        assert(cmd_bad===(cmd_addr[1:0]!=0||cmd_len==0||
            {1'b0,cmd_addr}<{1'b0,RAM_BASE}||
            {1'b0,cmd_addr}+({25'b0,cmd_len}<<2)>{1'b0,RAM_BASE}+RAM_BYTES))
            else $fatal(1,"SRAM_COMMAND_BOUNDS_EQUIVALENCE");
    end
    final $display("SRAM_BOUNDS_COVER checked=%0d aligned_region=%0d",bounded_command_checks,ALIGNED_REGION);
`endif
    wire [AW-1:0] first_word=AW'((cmd_addr-RAM_BASE)>>2);
    wire initial_read=cmd_valid && cmd_ready && !cmd_write && !cmd_bad;
    // In an aligned power-of-two RAM, first_word always names allocated
    // storage. A bad read may update this private data register, but bad
    // masks its response until the next command replaces both flags/data.
    // Arbitrary/non-power-of-two geometries keep the original qualification.
    wire first_read_capture=cmd_valid && cmd_ready && !cmd_write &&
        (ALIGNED_REGION || !cmd_bad);
    wire next_read=state==READ && r_valid && r_ready && beat!=length-1 && !bad;
    // initial_read can only fire in IDLE; next_read can only fire in READ.
    // Only the disposable read capture is relaxed; validation is unchanged.
    // Select the address from state alone so cmd_bad is not on the RAM address path.
    wire [AW-1:0] read_addr=state==IDLE ? first_word : word_addr+1'b1;
    integer lane;
    // Untyped string parameters are packed vectors in Verilog. Compare with
    // an equally wide zero so nonempty filenames also lint on Verilator 4.
    initial if (INIT_FILE!={$bits(INIT_FILE){1'b0}}) $readmemh(INIT_FILE,mem);
    always @(posedge clk) begin
        if (first_read_capture || next_read) read_q<=mem[read_addr];
        for (lane=0;lane<4;lane=lane+1)
            if (!rst && state==WRITE && w_valid && w_ready && !bad && w_be[lane])
                mem[word_addr][8*lane+:8]<=w_data[8*lane+:8];
    end
    assign cmd_ready=state==IDLE && !rst;
    assign w_ready=state==WRITE && !rst;
    assign r_valid=(state==READ || state==ACK) && !rst;
    assign r_data=bad || state==ACK ? 32'b0 : read_q;
    assign r_error=bad;
    assign r_last=state==ACK || beat==length-1;
    always @(posedge clk) begin
        if(rst) begin state<=IDLE; word_addr<=0; beat<=0; length<=0; bad<=0; end
        else case(state)
            IDLE: if(cmd_valid) begin
                word_addr<=first_word; beat<=0; length<=cmd_len==0 ? 8'd1 : cmd_len;
                bad<=cmd_bad; state<=cmd_write ? WRITE : READ;
            end
            READ: if(r_ready) begin
                if(beat==length-1) state<=IDLE;
                else begin beat<=beat+1'b1; word_addr<=word_addr+1'b1; end
            end
            WRITE: if(w_valid) begin
                bad<=bad || (w_last!=(beat==length-1));
                if(beat==length-1) state<=ACK;
                else begin beat<=beat+1'b1; word_addr<=word_addr+1'b1; end
            end
            ACK: if(r_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
`ifndef SYNTHESIS
    reg [31:0] original_read_q;
    integer sram_prefetch_extra=0,sram_prefetch_responses=0;
    always @(posedge clk) begin
        if(initial_read||next_read) original_read_q<=mem[read_addr];
        if(!rst) begin
            if(first_read_capture&&!initial_read) begin
                assert(ALIGNED_REGION && read_addr<RAM_BYTES/4)
                    else $fatal(1,"SRAM_PREFETCH_PHYSICAL_RANGE");
                sram_prefetch_extra<=sram_prefetch_extra+1;
            end
            if(r_valid&&!bad&&state==READ) begin
                assert(read_q===original_read_q)
                    else $fatal(1,"SRAM_PREFETCH_RESPONSE_IDENTITY");
                sram_prefetch_responses<=sram_prefetch_responses+1;
            end
        end
    end
    final $display("SRAM_PREFETCH_COVER extra=%0d responses=%0d",sram_prefetch_extra,sram_prefetch_responses);
`endif
endmodule
