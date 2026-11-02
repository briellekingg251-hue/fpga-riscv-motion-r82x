`timescale 1ns/1ps

// P1 peripheral block: UART TX, GPIO, and a free-running 64-bit timer.
//
// The request/response interface is the local P1 protocol from
// docs/interface_contract.md.  There is one response register, and a request
// is accepted only when that register is empty or its current response is
// consumed in the same cycle.  No response is generated combinationally.
module p1_peripherals #(
    parameter logic [31:0] UART_BASE  = 32'h1000_0000,
    parameter logic [31:0] GPIO_BASE  = 32'h1000_1000,
    parameter logic [31:0] TIMER_BASE = 32'h1000_2000,
    parameter integer      UART_DIVISOR = 8
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic [31:0] req_addr,
    input  logic        req_write,
    input  logic [3:0]  req_be,
    input  logic [31:0] req_wdata,

    output logic        rsp_valid,
    input  logic        rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic        rsp_error,

    output logic        uart_tx,
    output logic [31:0] gpio_out
);

    localparam logic [31:0] UART_DATA_OFF   = 32'h0000_0000;
    localparam logic [31:0] UART_STATUS_OFF = 32'h0000_0004;
    localparam logic [31:0] UART_BAUD_OFF   = 32'h0000_0008;
    localparam logic [31:0] GPIO_DATA_OFF   = 32'h0000_0000;
    localparam logic [31:0] TIMER_LO_OFF   = 32'h0000_0000;
    localparam logic [31:0] TIMER_HI_OFF   = 32'h0000_0004;

    localparam integer UART_DIVISOR_RESET =
        (UART_DIVISOR < 2) ? 2 : UART_DIVISOR;

    logic [63:0] timer_counter;
    logic [31:0] uart_baud_div;
    logic        uart_busy;
    logic [7:0]  uart_data;
    logic [3:0]  uart_bit_index;
    logic [31:0] uart_baud_count;

    wire rsp_consumed = rsp_valid && rsp_ready;
    wire data_access = (req_addr == (UART_BASE + UART_DATA_OFF));
    wire baud_access = (req_addr == (UART_BASE + UART_BAUD_OFF));
    wire data_write_blocked = data_access && req_write && req_be[0] && uart_busy;
    wire baud_write_blocked = baud_access && req_write && (req_be != 4'd0) && uart_busy;

    // A byte-bearing DATA write is held off while a byte is transmitting.
    // DATA reads and writes that do not select lane zero remain available,
    // which lets software inspect DATA without waiting for TX.  A BAUD write
    // with a selected lane waits for the active byte to drain so each accepted
    // write has an observable effect.
    always_comb begin
        req_ready = (!rsp_valid || rsp_ready) &&
                    !data_write_blocked && !baud_write_blocked;
    end

    wire req_fire = req_valid && req_ready;

    // The TX output is idle-high.  uart_bit_index names the bit currently on
    // the pin: 0=start, 1..8=data[0..7], and 9=stop.
    always_ff @(posedge clk) begin
        if (rst) begin
            timer_counter <= 64'd0;
            uart_baud_div <= UART_DIVISOR_RESET;
            uart_busy <= 1'b0;
            uart_data <= 8'd0;
            uart_bit_index <= 4'd0;
            uart_baud_count <= 32'd0;
            uart_tx <= 1'b1;
            gpio_out <= 32'd0;

            rsp_valid <= 1'b0;
            rsp_rdata <= 32'd0;
            rsp_error <= 1'b0;
        end else begin
            timer_counter <= timer_counter + 64'd1;

            // Response register maintenance.  A new response written below
            // wins over the old response consumed on this edge.
            if (rsp_consumed)
                rsp_valid <= 1'b0;

            // UART timing is independent of request/response traffic.
            if (uart_busy) begin
                if (uart_baud_count >= (uart_baud_div - 32'd1)) begin
                    uart_baud_count <= 32'd0;
                    if (uart_bit_index == 4'd9) begin
                        uart_busy <= 1'b0;
                        uart_tx <= 1'b1;
                    end else begin
                        uart_bit_index <= uart_bit_index + 4'd1;
                        if (uart_bit_index == 4'd0)
                            uart_tx <= uart_data[0];
                        else if (uart_bit_index < 4'd8)
                            uart_tx <= uart_data[uart_bit_index[2:0]];
                        else
                            uart_tx <= 1'b1;
                    end
                end else begin
                    uart_baud_count <= uart_baud_count + 32'd1;
                end
            end

            if (req_fire) begin
                // Every accepted request produces exactly one response.  The
                // defaults cover successful reads of zero-valued registers.
                rsp_valid <= 1'b1;
                rsp_rdata <= 32'd0;
                rsp_error <= 1'b0;

                if ((req_addr >= UART_BASE) &&
                    (req_addr < (UART_BASE + 32'h0000_1000))) begin
                    case (req_addr - UART_BASE)
                        UART_DATA_OFF: begin
                            if (req_write) begin
                                if (req_be[0] && !uart_busy) begin
                                    uart_data <= req_wdata[7:0];
                                    uart_busy <= 1'b1;
                                    uart_bit_index <= 4'd0;
                                    uart_baud_count <= 32'd0;
                                    uart_tx <= 1'b0;
                                end
                            end
                        end

                        UART_STATUS_OFF: begin
                            if (req_write) begin
                                rsp_error <= 1'b1;
                            end else begin
                                rsp_rdata <= {31'd0, uart_busy};
                            end
                        end

                        UART_BAUD_OFF: begin
                            if (req_write) begin
                                // BAUD is byte-mergeable.  A write with a
                                // selected lane is held by req_ready until
                                // the active byte has drained.
                                if (!uart_busy) begin
                                    // Form the byte-merged value as a single
                                    // 32-bit expression before clamping.  A
                                    // partial write must preserve untouched
                                    // bytes, including while the old value is
                                    // already at the minimum divisor.
                                    if ({
                                        req_be[3] ? req_wdata[31:24] : uart_baud_div[31:24],
                                        req_be[2] ? req_wdata[23:16] : uart_baud_div[23:16],
                                        req_be[1] ? req_wdata[15:8]  : uart_baud_div[15:8],
                                        req_be[0] ? req_wdata[7:0]   : uart_baud_div[7:0]
                                    } < 32'd2)
                                        uart_baud_div <= 32'd2;
                                    else
                                        uart_baud_div <= {
                                            req_be[3] ? req_wdata[31:24] : uart_baud_div[31:24],
                                            req_be[2] ? req_wdata[23:16] : uart_baud_div[23:16],
                                            req_be[1] ? req_wdata[15:8]  : uart_baud_div[15:8],
                                            req_be[0] ? req_wdata[7:0]   : uart_baud_div[7:0]
                                        };
                                end
                            end else begin
                                rsp_rdata <= uart_baud_div;
                            end
                        end

                        default: begin
                            rsp_error <= 1'b1;
                        end
                    endcase
                end else if ((req_addr >= GPIO_BASE) &&
                             (req_addr < (GPIO_BASE + 32'h0000_1000))) begin
                    case (req_addr - GPIO_BASE)
                        GPIO_DATA_OFF: begin
                            if (req_write) begin
                                if (req_be[0]) gpio_out[7:0]   <= req_wdata[7:0];
                                if (req_be[1]) gpio_out[15:8]  <= req_wdata[15:8];
                                if (req_be[2]) gpio_out[23:16] <= req_wdata[23:16];
                                if (req_be[3]) gpio_out[31:24] <= req_wdata[31:24];
                            end else begin
                                rsp_rdata <= gpio_out;
                            end
                        end

                        default: begin
                            rsp_error <= 1'b1;
                        end
                    endcase
                end else if ((req_addr >= TIMER_BASE) &&
                             (req_addr < (TIMER_BASE + 32'h0000_1000))) begin
                    case (req_addr - TIMER_BASE)
                        TIMER_LO_OFF: begin
                            if (req_write)
                                rsp_error <= 1'b1;
                            else
                                rsp_rdata <= timer_counter[31:0];
                        end

                        TIMER_HI_OFF: begin
                            if (req_write)
                                rsp_error <= 1'b1;
                            else
                                rsp_rdata <= timer_counter[63:32];
                        end

                        default: begin
                            rsp_error <= 1'b1;
                        end
                    endcase
                end else begin
                    rsp_error <= 1'b1;
                end
            end
        end
    end

endmodule
