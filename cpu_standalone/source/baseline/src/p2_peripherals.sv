`timescale 1ns/1ps

// P2 peripheral block.  UART TX and GPIO retain the P1 request/response
// behavior.  The timer window adds mtime/mtimecmp, software pending, and a
// test external-pending bit with explicit interrupt outputs.
module p2_peripherals #(
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
    output logic [31:0] gpio_out,
    input  logic        external_irq,
    output logic        irq_software,
    output logic        irq_timer,
    output logic        irq_external
);

    localparam logic [31:0] UART_DATA_OFF   = 32'h0000_0000;
    localparam logic [31:0] UART_STATUS_OFF = 32'h0000_0004;
    localparam logic [31:0] UART_BAUD_OFF   = 32'h0000_0008;
    localparam logic [31:0] GPIO_DATA_OFF   = 32'h0000_0000;
    localparam logic [31:0] TIMER_MTIME_LO_OFF = 32'h0000_0000;
    localparam logic [31:0] TIMER_MTIME_HI_OFF = 32'h0000_0004;
    localparam logic [31:0] TIMER_CMP_LO_OFF   = 32'h0000_0008;
    localparam logic [31:0] TIMER_CMP_HI_OFF   = 32'h0000_000c;
    localparam logic [31:0] TIMER_MSIP_OFF     = 32'h0000_0010;
    localparam logic [31:0] TIMER_EXT_OFF      = 32'h0000_0014;

    localparam integer UART_DIVISOR_RESET =
        (UART_DIVISOR < 2) ? 2 : UART_DIVISOR;

    logic [63:0] timer_counter;
    logic [63:0] timer_compare;
    logic        msip_pending;
    logic        ext_test_pending;
    logic [31:0] uart_baud_div;
    logic [31:0] uart_baud_limit;
    logic        uart_busy;
    logic [7:0]  uart_data;
    logic [3:0]  uart_bit_index;
    logic [31:0] uart_baud_count;
    wire [31:0] uart_baud_increment;
    assign uart_baud_increment[0]=~uart_baud_count[0];
    generate for(genvar uart_inc_bit=1;uart_inc_bit<32;uart_inc_bit=uart_inc_bit+1) begin: uart_increment_prefix
        assign uart_baud_increment[uart_inc_bit]=uart_baud_count[uart_inc_bit]^
            (&uart_baud_count[uart_inc_bit-1:0]);
    end endgenerate

    function automatic [31:0] merge_word(
        input [31:0] old_value,
        input [31:0] new_value,
        input [3:0]  byte_enable
    );
        begin
            merge_word = old_value;
            if (byte_enable[0]) merge_word[7:0]   = new_value[7:0];
            if (byte_enable[1]) merge_word[15:8]  = new_value[15:8];
            if (byte_enable[2]) merge_word[23:16] = new_value[23:16];
            if (byte_enable[3]) merge_word[31:24] = new_value[31:24];
        end
    endfunction

    wire rsp_consumed = rsp_valid && rsp_ready;
    wire data_access = (req_addr == (UART_BASE + UART_DATA_OFF));
    wire baud_access = (req_addr == (UART_BASE + UART_BAUD_OFF));
    wire data_write_blocked = data_access && req_write && req_be[0] && uart_busy;
    wire baud_write_blocked = baud_access && req_write && (req_be != 4'd0) && uart_busy;

    always_comb begin
        req_ready = (!rsp_valid || rsp_ready) &&
                    !data_write_blocked && !baud_write_blocked;
    end

    wire req_fire = req_valid && req_ready;
    wire timer_mtime_write = req_fire && req_write && (req_be != 4'd0) &&
        ((req_addr == (TIMER_BASE + TIMER_MTIME_LO_OFF)) ||
         (req_addr == (TIMER_BASE + TIMER_MTIME_HI_OFF)));

    assign irq_software = msip_pending;
    // Compute possible next-state comparisons before late request decode.
    // The result remains exact at each edge: no extra interrupt cycle.
    // Route priority is evaluated on constant compare-write addresses.
    // Preserve configurable overlaps and 32-bit wrapped base arithmetic.
    function automatic timer_route_at(input [31:0] address);
        begin
            timer_route_at = !((address >= UART_BASE) &&
                (address < (UART_BASE + 32'h0000_1000))) &&
                !((address >= GPIO_BASE) &&
                (address < (GPIO_BASE + 32'h0000_1000))) &&
                ((address >= TIMER_BASE) &&
                (address < (TIMER_BASE + 32'h0000_1000)));
        end
    endfunction
    localparam [31:0] CMP_LO_ADDR = TIMER_BASE + TIMER_CMP_LO_OFF;
    localparam [31:0] CMP_HI_ADDR = TIMER_BASE + TIMER_CMP_HI_OFF;
    localparam CMP_LO_ROUTED = timer_route_at(CMP_LO_ADDR);
    localparam CMP_HI_ROUTED = timer_route_at(CMP_HI_ADDR);
    wire timer_cmp_lo_write = CMP_LO_ROUTED && req_fire && req_write &&
        (req_be != 4'd0) && (req_addr == CMP_LO_ADDR);
    wire timer_cmp_hi_write = CMP_HI_ROUTED && req_fire && req_write &&
        (req_be != 4'd0) && (req_addr == CMP_HI_ADDR);
    // Architectural timer state is unchanged. Chunk carry flags describe
    // the current counter; comparison flags describe current C versus T.
    // Moving the comparison reduction after their edge adds no IRQ cycle.
    reg [2:0] timer_full_q;
    reg [3:0] timer_gt_q,timer_eq_q;
    wire [63:0] timer_incremented,timer_counter_next,timer_compare_next;
    wire [63:0] timer_counter_written=(req_addr==(TIMER_BASE+TIMER_MTIME_LO_OFF))?
        {timer_counter[63:32],merge_word(timer_counter[31:0],req_wdata,req_be)}:
        {merge_word(timer_counter[63:32],req_wdata,req_be),timer_counter[31:0]};
    assign timer_counter_next=timer_mtime_write?timer_counter_written:timer_incremented;
    assign timer_compare_next=timer_cmp_lo_write?
        {timer_compare[63:32],merge_word(timer_compare[31:0],req_wdata,req_be)}:
        timer_cmp_hi_write?
        {merge_word(timer_compare[63:32],req_wdata,req_be),timer_compare[31:0]}:timer_compare;
    generate for(genvar tc=0;tc<4;tc=tc+1) begin: timer_chunks
        wire carry;
        if(tc==0) assign carry=1'b1;
        else assign carry=&timer_full_q[tc-1:0];
        assign timer_incremented[tc*16+:16]=timer_counter[tc*16+:16]+carry;
        always @(posedge clk) begin
            if(rst) begin timer_counter[tc*16+:16]<=0;timer_gt_q[tc]<=0;timer_eq_q[tc]<=0;end
            else begin
                timer_counter[tc*16+:16]<=timer_counter_next[tc*16+:16];
                timer_gt_q[tc]<=timer_counter_next[tc*16+:16]>timer_compare_next[tc*16+:16];
                timer_eq_q[tc]<=timer_counter_next[tc*16+:16]==timer_compare_next[tc*16+:16];
            end
        end
        if(tc<3) always @(posedge clk) begin
            if(rst) timer_full_q[tc]<=0;
            else timer_full_q[tc]<=(&timer_counter_next[tc*16+:16]);
        end
    end endgenerate
    wire timer_irq_q=timer_gt_q[3]||(timer_eq_q[3]&&timer_gt_q[2])||
        ((&timer_eq_q[3:2])&&timer_gt_q[1])||
        ((&timer_eq_q[3:1])&&(timer_gt_q[0]||timer_eq_q[0]));
`ifndef SYNTHESIS
    always @(posedge clk) if (!rst)
        assert (timer_irq_q === (timer_counter >= timer_compare))
            else $fatal(1, "TIMER_IRQ_EXACT_VISIBLE");
`endif
    // One registered propagation cycle; timer state/comparison remain exact.
    // RISC-V MTIP propagation may be eventual rather than immediate.
    always @(posedge clk) begin
        if(rst) irq_timer<=1'b0;
        else irq_timer<=timer_irq_q;
    end
`ifndef SYNTHESIS
    // Independent one-cycle contract uses architectural C/T, not timer_irq_q.
    reg timer_visible_reference;
    always @(posedge clk) begin
        if(rst) timer_visible_reference<=1'b0;
        else timer_visible_reference<=(timer_counter>=timer_compare);
    end
    always @(negedge clk)
        assert(irq_timer===timer_visible_reference)
            else $fatal(1,"TIMER_IRQ_REGISTERED_DELAY");
`endif
    assign irq_external = external_irq || ext_test_pending;

    // TX output is idle-high. bit_index 0 is start, 1..8 are data, 9 stop.
    always_ff @(posedge clk) begin
        if (rst) begin
            timer_compare <= 64'hffff_ffff_ffff_ffff;
            msip_pending <= 1'b0;
            ext_test_pending <= 1'b0;
            uart_baud_div <= UART_DIVISOR_RESET;
            uart_baud_limit <= UART_DIVISOR_RESET - 32'd1;
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
            if (rsp_consumed)
                rsp_valid <= 1'b0;

            if (uart_busy) begin
                if (uart_baud_count >= uart_baud_limit) begin
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
                    uart_baud_count <= uart_baud_increment;
                end
            end

            if (req_fire) begin
                rsp_valid <= 1'b1;
                rsp_rdata <= 32'd0;
                rsp_error <= 1'b0;

                if ((req_addr >= UART_BASE) &&
                    (req_addr < (UART_BASE + 32'h0000_1000))) begin
                    case (req_addr)
                        (UART_BASE + UART_DATA_OFF): begin
                            if (req_write && req_be[0] && !uart_busy) begin
                                uart_data <= req_wdata[7:0];
                                uart_busy <= 1'b1;
                                uart_bit_index <= 4'd0;
                                uart_baud_count <= 32'd0;
                                uart_tx <= 1'b0;
                            end
                        end
                        (UART_BASE + UART_STATUS_OFF): begin
                            if (req_write) rsp_error <= 1'b1;
                            else rsp_rdata <= {31'd0, uart_busy};
                        end
                        (UART_BASE + UART_BAUD_OFF): begin
                            if (req_write) begin
                                if (!uart_busy) begin
                                    if (merge_word(uart_baud_div, req_wdata, req_be) < 32'd2) begin
                                        uart_baud_div <= 32'd2;
                                        uart_baud_limit <= 32'd1;
                                    end else begin
                                        uart_baud_div <= merge_word(uart_baud_div, req_wdata, req_be);
                                        uart_baud_limit <= merge_word(uart_baud_div, req_wdata, req_be) - 32'd1;
                                    end
                                end
                            end else begin
                                rsp_rdata <= uart_baud_div;
                            end
                        end
                        default: rsp_error <= 1'b1;
                    endcase
                end else if ((req_addr >= GPIO_BASE) &&
                             (req_addr < (GPIO_BASE + 32'h0000_1000))) begin
                    case (req_addr)
                        (GPIO_BASE + GPIO_DATA_OFF): begin
                            if (req_write) begin
                                if (req_be[0]) gpio_out[7:0]   <= req_wdata[7:0];
                                if (req_be[1]) gpio_out[15:8]  <= req_wdata[15:8];
                                if (req_be[2]) gpio_out[23:16] <= req_wdata[23:16];
                                if (req_be[3]) gpio_out[31:24] <= req_wdata[31:24];
                            end else rsp_rdata <= gpio_out;
                        end
                        default: rsp_error <= 1'b1;
                    endcase
                end else if ((req_addr >= TIMER_BASE) &&
                             (req_addr < (TIMER_BASE + 32'h0000_1000))) begin
                    case (req_addr)
                        (TIMER_BASE + TIMER_MTIME_LO_OFF): begin
                            if (!req_write) rsp_rdata <= timer_counter[31:0];
                        end
                        (TIMER_BASE + TIMER_MTIME_HI_OFF): begin
                            if (!req_write) rsp_rdata <= timer_counter[63:32];
                        end
                        (TIMER_BASE + TIMER_CMP_LO_OFF): begin
                            if (req_write && (req_be != 4'd0))
                                timer_compare <= {timer_compare[63:32],
                                                  merge_word(timer_compare[31:0], req_wdata, req_be)};
                            else if (!req_write)
                                rsp_rdata <= timer_compare[31:0];
                        end
                        (TIMER_BASE + TIMER_CMP_HI_OFF): begin
                            if (req_write && (req_be != 4'd0))
                                timer_compare <= {merge_word(timer_compare[63:32], req_wdata, req_be),
                                                  timer_compare[31:0]};
                            else if (!req_write)
                                rsp_rdata <= timer_compare[63:32];
                        end
                        (TIMER_BASE + TIMER_MSIP_OFF): begin
                            if (req_write) begin
                                if (req_be[0]) msip_pending <= req_wdata[0];
                            end else rsp_rdata <= {31'd0, msip_pending};
                        end
                        (TIMER_BASE + TIMER_EXT_OFF): begin
                            if (req_write) begin
                                if (req_be[0]) ext_test_pending <= req_wdata[0];
                            end else rsp_rdata <= {31'd0, ext_test_pending};
                        end
                        default: rsp_error <= 1'b1;
                    endcase
                end else begin
                    rsp_error <= 1'b1;
                end
            end
        end
    end
`ifndef SYNTHESIS
    integer uart_increment_checks=0,uart_increment_active=0;
    always @(posedge clk) if(!rst) begin
        assert(uart_baud_increment===(uart_baud_count+32'd1))
            else $fatal(1,"UART_INCREMENT_PREFIX_IDENTITY");
        uart_increment_checks<=uart_increment_checks+1;
        if(uart_busy) uart_increment_active<=uart_increment_active+1;
    end
    final $display("UART_INCREMENT_PREFIX_COVER checks=%0d busy=%0d",
        uart_increment_checks,uart_increment_active);
`endif
`ifndef SYNTHESIS
    integer uart_limit_checks=0,uart_limit_busy_checks=0,uart_limit_writes=0;
    always @(posedge clk) if(!rst) begin
        assert(uart_baud_limit===(uart_baud_div-32'd1)) else $fatal(1,"UART_LIMIT_MIRROR_IDENTITY");
        uart_limit_checks<=uart_limit_checks+1;
        if(uart_busy) uart_limit_busy_checks<=uart_limit_busy_checks+1;
        if(req_fire&&req_write&&baud_access&&!uart_busy) uart_limit_writes<=uart_limit_writes+1;
    end
    final $display("UART_LIMIT_COVER checks=%0d busy=%0d writes=%0d",uart_limit_checks,uart_limit_busy_checks,uart_limit_writes);
`endif
endmodule
