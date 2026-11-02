`timescale 1ns/1ps

// One signed 8x8 multiplier, one signed 32-bit accumulator. The buffer owner
// presents the indexed bytes; READ samples them and MAC consumes the samples.
// START at edge k commits the final inclusive sum at edge k + 2*length.
module p4_int8_dot (
    input  wire        clk, rst, cancel, start,
    input  wire [8:0]  length,
    output wire [7:0]  read_index,
    input  wire [7:0]  a_data, b_data,
    output wire        busy,
    output wire        complete,
    output wire [31:0] result
);
    localparam [1:0] IDLE = 2'd0, READ = 2'd1, MAC = 2'd2;
    reg [1:0] state;
    reg [8:0] task_length;
    reg [7:0] index;
    reg signed [7:0] a_sample, b_sample;
    reg signed [31:0] accumulator;
    wire signed [15:0] product = a_sample * b_sample;
    wire signed [31:0] product_extended = {{16{product[15]}}, product};
    wire signed [31:0] sum = accumulator + product_extended;
    wire last_item = ({1'b0, index} + 9'd1) == task_length;

    assign read_index = index;
    assign busy = state != IDLE;
    // These are a pre-edge commit event and its payload, not a delayed pulse.
    assign complete = (state == MAC) && last_item && !rst && !cancel;
    assign result = sum;

    always @(posedge clk) begin
        if (rst || cancel) begin
            state <= IDLE;
            task_length <= 9'd0;
            index <= 8'd0;
        end else begin
            case (state)
                IDLE: if (start) begin
                    state <= READ;
                    task_length <= length;
                    index <= 8'd0;
                end
                READ: begin
                    state <= MAC;
                end
                MAC: begin
                    if (last_item) state <= IDLE;
                    else begin
                        index <= index + 8'd1;
                        state <= READ;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
    // Cancel invalidates control immediately. Data is intentionally not
    // canceled: START clears the accumulator and READ overwrites both samples
    // before any MAC can complete. Keeping cancel out of both reset and enable
    // removes the late MMIO control path from the multiplier/accumulator.
    // On a canceled READ/MAC these updates are harmless, unobservable data.
    always @(posedge clk) begin
        if (rst) begin
            a_sample <= 8'sd0;
            b_sample <= 8'sd0;
            accumulator <= 32'sd0;
        end else begin
            case (state)
                IDLE: if (start) accumulator <= 32'sd0;
                READ: begin
                    a_sample <= $signed(a_data);
                    b_sample <= $signed(b_data);
                end
                MAC: accumulator <= sum;
                default: begin end
            endcase
        end
    end
endmodule
