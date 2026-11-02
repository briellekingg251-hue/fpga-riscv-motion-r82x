`timescale 1ns/1ps
// Compare a formatted load to an operand without creating its 32-bit extension.
module p2_load_eq_narrow(input wire [31:0] data,other,
    input wire [1:0] offset,input wire [2:0] funct3,output wire equal);
    wire [7:0] byte_value=data[{offset,3'b000}+:8];
    wire [15:0] half_value=offset[1]?data[31:16]:data[15:0];
    (* syn_keep=1 *) wire [2:0] byte_groups={byte_value[7:6]==other[7:6],
        byte_value[5:3]==other[5:3],byte_value[2:0]==other[2:0]};
    (* syn_keep=1 *) wire [5:0] half_groups={half_value[15]==other[15],
        half_value[14:12]==other[14:12],half_value[11:9]==other[11:9],
        half_value[8:6]==other[8:6],half_value[5:3]==other[5:3],half_value[2:0]==other[2:0]};
    (* syn_keep=1 *) wire byte_upper_zero=other[31:8]==24'b0;
    (* syn_keep=1 *) wire byte_upper_ones=&other[31:8];
    (* syn_keep=1 *) wire half_upper_zero=other[31:16]==16'b0;
    (* syn_keep=1 *) wire half_upper_ones=&other[31:16];
    wire byte_signed=(&byte_groups)&&(byte_value[7]?byte_upper_ones:byte_upper_zero);
    wire half_signed=(&half_groups)&&(half_value[15]?half_upper_ones:half_upper_zero);
    wire byte_unsigned=(&byte_groups)&&byte_upper_zero;
    wire half_unsigned=(&half_groups)&&half_upper_zero;
    (* syn_keep=1 *) wire [10:0] word_groups;
    genvar chunk;
    generate for(chunk=0;chunk<10;chunk=chunk+1) begin: word_compare
        assign word_groups[chunk]=data[chunk*3+:3]==other[chunk*3+:3];
    end endgenerate
    assign word_groups[10]=data[31:30]==other[31:30];
    wire supported=(funct3==0)||(funct3==1)||(funct3==2)||(funct3==4)||(funct3==5);
    assign equal=((funct3==0)&&byte_signed)||((funct3==1)&&half_signed)||
        ((funct3==2)&&(&word_groups))||((funct3==4)&&byte_unsigned)||
        ((funct3==5)&&half_unsigned)||(!supported&&(other==0));
endmodule
