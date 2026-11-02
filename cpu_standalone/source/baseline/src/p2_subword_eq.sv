`timescale 1ns/1ps
// Contract: funct3!=2 when selected. Equality permits using other sign bits
// to qualify extension before the late load data arrives.
module p2_subword_eq(input wire [31:0] data,other,
    input wire [1:0] offset,input wire [2:0] funct3,output wire equal);
    wire byte_zero=other[31:8]==0,byte_ones=&other[31:8];
    wire half_zero=other[31:16]==0,half_ones=&other[31:16];
    wire byte_ok=((funct3==0)&&(other[7]?byte_ones:byte_zero))||((funct3==4)&&byte_zero);
    wire half_ok=((funct3==1)&&(other[15]?half_ones:half_zero))||((funct3==5)&&half_zero);
    wire [3:0] byte_matches;
    wire [1:0] half_matches;
    generate for(genvar b=0;b<4;b=b+1) begin: byte_lanes
        (* syn_keep=1 *) wire [2:0] eq3={data[b*8+6+:2]==other[6+:2],
            data[b*8+3+:3]==other[3+:3],data[b*8+:3]==other[0+:3]};
        assign byte_matches[b]=(&eq3)&&byte_ok&&(offset==b);
    end
    for(genvar h=0;h<2;h=h+1) begin: half_lanes
        (* syn_keep=1 *) wire [5:0] eq3={data[h*16+15]==other[15],
            data[h*16+12+:3]==other[12+:3],data[h*16+9+:3]==other[9+:3],
            data[h*16+6+:3]==other[6+:3],data[h*16+3+:3]==other[3+:3],
            data[h*16+:3]==other[0+:3]};
        assign half_matches[h]=(&eq3)&&half_ok&&(offset[1]==h);
    end endgenerate
    wire supported=(funct3==0)||(funct3==1)||(funct3==4)||(funct3==5);
    assign equal=(|byte_matches)||(|half_matches)||(!supported&&(other==0));
endmodule
