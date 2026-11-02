// Two masters, round-robin at whole-command boundaries. Selection is registered
// before exposing cmd_valid, so another request cannot change a stalled command.
module p2_burst_arbiter2 (
    input wire clk, rst,
    input wire a_cmd_valid, output wire a_cmd_ready, input wire a_cmd_write,
    input wire [31:0] a_cmd_addr, input wire [7:0] a_cmd_len,
    input wire a_w_valid, output wire a_w_ready, input wire [31:0] a_w_data,
    input wire [3:0] a_w_be, input wire a_w_last,
    output wire a_r_valid, input wire a_r_ready, output wire [31:0] a_r_data,
    output wire a_r_error, a_r_last,
    input wire b_cmd_valid, output wire b_cmd_ready, input wire b_cmd_write,
    input wire [31:0] b_cmd_addr, input wire [7:0] b_cmd_len,
    input wire b_w_valid, output wire b_w_ready, input wire [31:0] b_w_data,
    input wire [3:0] b_w_be, input wire b_w_last,
    output wire b_r_valid, input wire b_r_ready, output wire [31:0] b_r_data,
    output wire b_r_error, b_r_last,
    output wire m_cmd_valid, input wire m_cmd_ready, output wire m_cmd_write,
    output wire [31:0] m_cmd_addr, output wire [7:0] m_cmd_len,
    output wire m_w_valid, input wire m_w_ready, output wire [31:0] m_w_data,
    output wire [3:0] m_w_be, output wire m_w_last,
    input wire m_r_valid, output wire m_r_ready, input wire [31:0] m_r_data,
    input wire m_r_error, m_r_last
);
    localparam [1:0] IDLE=0, COMMAND=1, ACTIVE=2;
    reg [1:0] state;
    reg owner, prefer_b;
    assign m_cmd_valid=state==COMMAND && (owner ? b_cmd_valid : a_cmd_valid) && !rst;
    assign m_cmd_write=owner ? b_cmd_write : a_cmd_write;
    assign m_cmd_addr=owner ? b_cmd_addr : a_cmd_addr;
    assign m_cmd_len=owner ? b_cmd_len : a_cmd_len;
    assign a_cmd_ready=state==COMMAND && !owner && m_cmd_ready && !rst;
    assign b_cmd_ready=state==COMMAND && owner && m_cmd_ready && !rst;
    assign m_w_valid=state==ACTIVE && (owner ? b_w_valid : a_w_valid) && !rst;
    assign m_w_data=owner ? b_w_data : a_w_data;
    assign m_w_be=owner ? b_w_be : a_w_be;
    assign m_w_last=owner ? b_w_last : a_w_last;
    assign a_w_ready=state==ACTIVE && !owner && m_w_ready && !rst;
    assign b_w_ready=state==ACTIVE && owner && m_w_ready && !rst;
    assign a_r_valid=state==ACTIVE && !owner && m_r_valid && !rst;
    assign b_r_valid=state==ACTIVE && owner && m_r_valid && !rst;
    assign a_r_data=m_r_data; assign b_r_data=m_r_data;
    assign a_r_error=m_r_error; assign b_r_error=m_r_error;
    assign a_r_last=m_r_last; assign b_r_last=m_r_last;
    assign m_r_ready=state==ACTIVE && (owner ? b_r_ready : a_r_ready) && !rst;
    always @(posedge clk) begin
        if(rst) begin state<=IDLE; owner<=0; prefer_b<=0; end
        else case(state)
            IDLE: if(a_cmd_valid || b_cmd_valid) begin
                owner<=a_cmd_valid && b_cmd_valid ? prefer_b : b_cmd_valid;
                state<=COMMAND;
            end
            COMMAND: if(m_cmd_valid && m_cmd_ready) state<=ACTIVE;
            ACTIVE: if(m_r_valid && m_r_ready && m_r_last) begin
                prefer_b<=!owner; state<=IDLE;
            end
            default: state<=IDLE;
        endcase
    end
endmodule
