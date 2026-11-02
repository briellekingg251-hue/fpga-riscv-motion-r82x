`timescale 1ns/1ps
// Each candidate is compared before the late 32-bit load source selector.
module p2_branch_predicate(input wire [31:0] other_a,other_b,load,
    input wire take_a,take_b,input wire [2:0] kind,
    output wire equal,high_lt,high_equal,lower_lt,dir_lower_lt,dir_lower_ge);
    wire [4:0] flags[0:2];
    genvar c,n;
    generate for(c=0;c<3;c=c+1) begin: candidates
        wire [31:0] a=(c==1)?load:other_a;
        wire [31:0] b=(c==2)?load:other_b;
        (* syn_keep=1 *) wire [10:0] eq3;
        (* syn_keep=1 *) wire [7:0] eq4,lt4;
        for(n=0;n<10;n=n+1) begin: eq_groups
            assign eq3[n]=a[n*3+:3]==b[n*3+:3];
        end
        assign eq3[10]=a[31:30]==b[31:30];
        for(n=0;n<8;n=n+1) begin: ordered_groups
            assign eq4[n]=a[n*4+:4]==b[n*4+:4];
            assign lt4[n]=a[n*4+:4]<b[n*4+:4];
        end
        wire hi_unsigned_lt=lt4[7]||(eq4[7]&&lt4[6])||
            ((&eq4[7:6])&&lt4[5])||((&eq4[7:5])&&lt4[4]);
        wire lo_unsigned_lt=lt4[3]||(eq4[3]&&lt4[2])||
            ((&eq4[3:2])&&lt4[1])||((&eq4[3:1])&&lt4[0]);
        wire hi_signed_lt=(a[31]!=b[31])?a[31]:hi_unsigned_lt;
        assign flags[c]={(&eq3),hi_unsigned_lt,hi_signed_lt,(&eq4[7:4]),lo_unsigned_lt};
    end endgenerate
    wire [4:0] selected=(take_a&&take_b)?5'b10010:
        take_a?flags[1]:take_b?flags[2]:flags[0];
    assign equal=selected[4];
    assign high_lt=kind[1]?selected[3]:selected[2];
    assign high_equal=selected[1];
    assign lower_lt=selected[0];
    assign dir_lower_lt=((kind==0)&&equal)||((kind==1)&&!equal)||
        (kind[2]&&((high_lt||high_equal)^kind[0]));
    assign dir_lower_ge=((kind==0)&&equal)||((kind==1)&&!equal)||
        (kind[2]&&(high_lt^kind[0]));
endmodule
