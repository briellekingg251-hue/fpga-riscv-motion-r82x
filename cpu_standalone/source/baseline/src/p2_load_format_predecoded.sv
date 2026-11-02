`timescale 1ns/1ps
// Selectors describe the same funct3/offset as the original load formatter.
// They are captured with those fields; no response or execution stage is added.
module p2_load_format_predecoded(input wire [31:0] data,
    input wire [12:0] selectors,output wire [31:0] result);
    wire byte_negative=(data[7]&selectors[7])|(data[15]&selectors[8])|
        (data[23]&selectors[9])|(data[31]&selectors[10]);
    assign result[7:0]=(data[7:0]&{8{selectors[0]}})|
        (data[15:8]&{8{selectors[1]}})|(data[23:16]&{8{selectors[2]}})|
        (data[31:24]&{8{selectors[3]}});
    assign result[15:8]=(data[15:8]&{8{selectors[4]}})|
        (data[31:24]&{8{selectors[5]}})|{8{byte_negative}};
    // Combine registered format controls before the late response sign bits.
    // Keep two different sign partials and each unique formatted output bit
    // local; no common upper sign net drives all downstream consumers.
    // The bitwise distributive rewrite also preserves unknown-value semantics.
    (* syn_keep=1 *) wire sign15_select=selectors[8]|selectors[11];
    (* syn_keep=1 *) wire sign31_select=selectors[10]|selectors[12];
    (* syn_keep=1 *) wire upper_sign_low=(data[7]&selectors[7])|
        (data[15]&sign15_select);
    (* syn_keep=1 *) wire upper_sign_high=(data[23]&selectors[9])|
        (data[31]&sign31_select);
    (* syn_keep=1 *) wire [15:0] upper_result=
        (data[31:16]&{16{selectors[6]}})|{16{upper_sign_low}}|
        {16{upper_sign_high}};
    assign result[31:16]=upper_result;
endmodule
