// General RV32 Zbc arithmetic. Four balanced 16x16 polynomial blocks are
// registered here; their final XOR/slice is registered by the core's mresult.
module p2_clmul_pipeline(
    input wire clk,rst,cancel,take,consume,
    input wire [2:0] kind,
    input wire [31:0] a,b,
    output reg ready,
    output wire [31:0] result
);
    function automatic [31:0] poly16;
        input [15:0] lhs,rhs;
        reg [31:0] term[0:15],pair_term[0:7],quad[0:3],octet[0:1];
        integer i;
        begin
            for(i=0;i<16;i=i+1) term[i]=({16'b0,lhs}<<i)&{32{rhs[i]}};
            for(i=0;i<8;i=i+1) pair_term[i]=term[2*i]^term[2*i+1];
            for(i=0;i<4;i=i+1) quad[i]=pair_term[2*i]^pair_term[2*i+1];
            for(i=0;i<2;i=i+1) octet[i]=quad[2*i]^quad[2*i+1];
            poly16=octet[0]^octet[1];
        end
    endfunction
    reg [31:0] ll_q,lh_q,hl_q,hh_q;
    reg [2:0] kind_q;
    wire [63:0] product=({32'b0,ll_q}^{hh_q,32'b0})^
        ({16'b0,lh_q,16'b0}^{16'b0,hl_q,16'b0});
    assign result=(kind_q==3'd1)?product[31:0]:
                  (kind_q==3'd2)?product[62:31]:product[63:32];
    always @(posedge clk) begin
        if(rst||cancel||consume) begin
            ready<=0;
        end else if(take&&!ready) begin
            ll_q<=poly16(a[15:0],b[15:0]);
            lh_q<=poly16(a[15:0],b[31:16]);
            hl_q<=poly16(a[31:16],b[15:0]);
            hh_q<=poly16(a[31:16],b[31:16]);
            kind_q<=kind;
            ready<=1;
        end
    end
endmodule
