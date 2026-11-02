`timescale 1ns/1ps
`include "p4_regs.vh"

// P4 owns independent local buffers, never an alias of cached system RAM.
// All request decisions and read snapshots use state before the accepting edge.
module p4_dot_mmio #(
    parameter [31:0] BASE_ADDR = `P4_ACCEL_BASE,
    parameter integer BUFFER_WRITE_PIPELINE = 0
) (
    input  wire        clk, rst,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    input  wire        req_write,
    input  wire [3:0]  req_be,
    input  wire [31:0] req_wdata,
    output reg         rsp_valid,
    input  wire        rsp_ready,
    output reg  [31:0] rsp_rdata,
    output reg         rsp_error,
    output wire        irq_o,
    output wire        busy_o, result_valid_o, pending_o, intr_enable_o,
    output wire        start_o, complete_o, soft_reset_o,
    output wire [31:0] generation_o, submit_id_o, done_id_o, result_o, length_o
);
    // Independent 64-word banks, with byte write enables and one asynchronous
    // read address per bank. Deliberately not reset: software initializes every
    // byte in [0, length). The busy engine owns reads; CPU buffer accesses are
    // legal only while idle, so sharing the read port preserves bus timing.
    reg [31:0] a_bank [0:63];
    reg [31:0] b_bank [0:63];
    reg [31:0] length_reg, submit_id, done_id, result_reg, generation;
    reg result_valid, done_pending, intr_enable;
    wire engine_busy, engine_complete;
    wire [31:0] engine_result;
    wire [7:0] engine_index;
    wire [31:0] offset = req_addr - BASE_ADDR;
    wire in_page = (req_addr >= BASE_ADDR) && (offset < `P4_ACCEL_SIZE);
    wire a_access = (offset >= `P4_A_BUFFER) &&
                    (offset < (`P4_A_BUFFER + 32'd256));
    wire b_access = (offset >= `P4_B_BUFFER) &&
                    (offset < (`P4_B_BUFFER + 32'd256));
    wire [7:0] word_byte = {offset[7:2], 2'b00};
    wire [5:0] bank_read_word = engine_busy ? engine_index[7:2] : word_byte[7:2];
    wire [31:0] a_read_word = a_bank[bank_read_word];
    wire [31:0] b_read_word = b_bank[bank_read_word];
    wire [7:0] engine_a_data = a_read_word[{engine_index[1:0],3'b000}+:8];
    wire [7:0] engine_b_data = b_read_word[{engine_index[1:0],3'b000}+:8];
    reg [31:0] read_snapshot;
    reg access_error;

    // Single outstanding transaction; no same-edge response/request turnover.
    assign req_ready = !rsp_valid && !rst;
    wire req_fire = req_valid && req_ready;
    wire legal_write = req_fire && req_write && !access_error;

    // Break the CPU/cache handshake -> large buffer write-enable path. A
    // request accepted at k is acknowledged at k+1; no new request can be
    // accepted before k+2. Committing its buffer write at k+1 therefore keeps
    // the bus latency, read-after-write and write-before-START behavior.
    // Capture only buffer legality here; control-register decoding is unrelated
    // to buffer writes and must not feed the high-fanout local enables.
    wire buffer_accept = req_fire && req_write && in_page &&
                         (req_addr[1:0] == 2'b00) && !engine_busy;
    wire [3:0] a_write_be, b_write_be;
    wire [7:0] buffer_word_byte;
    wire [31:0] buffer_wdata;
    generate if (BUFFER_WRITE_PIPELINE != 0) begin: buffer_write_pipeline
        reg [3:0] a_be_q, b_be_q;
        reg [7:0] word_byte_q;
        reg [31:0] wdata_q;
        always @(posedge clk) begin
            if (rst) begin
                a_be_q <= 4'b0;
                b_be_q <= 4'b0;
                word_byte_q <= 8'b0;
                wdata_q <= 32'b0;
            end else begin
                a_be_q <= (buffer_accept && a_access) ? req_be : 4'b0;
                b_be_q <= (buffer_accept && b_access) ? req_be : 4'b0;
                if (buffer_accept && (a_access || b_access)) begin
                    word_byte_q <= word_byte;
                    wdata_q <= req_wdata;
                end
            end
        end
        assign a_write_be = a_be_q;
        assign b_write_be = b_be_q;
        assign buffer_word_byte = word_byte_q;
        assign buffer_wdata = wdata_q;
    end else begin: direct_buffer_write
        assign a_write_be = (buffer_accept && a_access) ? req_be : 4'b0;
        assign b_write_be = (buffer_accept && b_access) ? req_be : 4'b0;
        assign buffer_word_byte = word_byte;
        assign buffer_wdata = req_wdata;
    end endgenerate

    // Global reset discards an uncommitted write. SOFT_RESET never resets the
    // buffers, and cannot be accepted while a buffer write is awaiting commit.
    always @(posedge clk) begin
        if (!rst) begin
            if (a_write_be[0]) a_bank[buffer_word_byte[7:2]][7:0] <= buffer_wdata[7:0];
            if (a_write_be[1]) a_bank[buffer_word_byte[7:2]][15:8] <= buffer_wdata[15:8];
            if (a_write_be[2]) a_bank[buffer_word_byte[7:2]][23:16] <= buffer_wdata[23:16];
            if (a_write_be[3]) a_bank[buffer_word_byte[7:2]][31:24] <= buffer_wdata[31:24];
            if (b_write_be[0]) b_bank[buffer_word_byte[7:2]][7:0] <= buffer_wdata[7:0];
            if (b_write_be[1]) b_bank[buffer_word_byte[7:2]][15:8] <= buffer_wdata[15:8];
            if (b_write_be[2]) b_bank[buffer_word_byte[7:2]][23:16] <= buffer_wdata[23:16];
            if (b_write_be[3]) b_bank[buffer_word_byte[7:2]][31:24] <= buffer_wdata[31:24];
        end
    end
    // Command pulses have their own exact legality predicates. In particular,
    // SOFT_RESET must not traverse the generic read/error mux before driving
    // the engine's accumulator reset. Keep these equivalent to access_error's
    // CONTROL/INTR_STATE cases below, including full-word byte enables.
    wire register_write = req_fire && req_write && in_page &&
                          (req_addr[1:0] == 2'b00) && (req_be == 4'hf);
    wire control_write = register_write && (offset == `P4_REG_CONTROL);
    wire start_allowed = !engine_busy && !result_valid && !done_pending &&
                         (length_reg >= 32'd1) && (length_reg <= `P4_CAP_NMAX_VALUE);
    assign start_o = control_write && (req_wdata == 32'd1) && start_allowed;
    assign soft_reset_o = control_write && (req_wdata == 32'd2);
    wire software_w1c = register_write && (offset == `P4_REG_INTR_STATE) &&
                        (req_wdata == 32'd1);
    assign complete_o = engine_complete;
    assign busy_o = engine_busy;
    assign result_valid_o = result_valid;
    assign pending_o = done_pending;
    assign intr_enable_o = intr_enable;
    assign irq_o = done_pending && intr_enable;
    assign generation_o = generation;
    assign submit_id_o = submit_id;
    assign done_id_o = done_id;
    assign result_o = result_reg;
    assign length_o = length_reg;

    p4_int8_dot engine (
        .clk(clk), .rst(rst), .cancel(soft_reset_o), .start(start_o),
        .length(length_reg[8:0]), .read_index(engine_index),
        .a_data(engine_a_data), .b_data(engine_b_data),
        .busy(engine_busy), .complete(engine_complete), .result(engine_result)
    );

    always @* begin
        read_snapshot = 32'd0;
        access_error = 1'b0;
        if (!in_page || (req_addr[1:0] != 2'b00)) begin
            access_error = 1'b1;
        end else if (a_access || b_access) begin
            if (engine_busy) access_error = 1'b1;
            else if (!req_write) begin
                if (a_access)
                    read_snapshot = a_read_word;
                else
                    read_snapshot = b_read_word;
            end
        end else if (req_be != 4'hf) begin
            access_error = 1'b1;
        end else begin
            case (offset)
                `P4_REG_ID_VERSION: begin
                    read_snapshot = `P4_ID_VERSION_VALUE;
                    access_error = req_write;
                end
                `P4_REG_CAP_NMAX: begin
                    read_snapshot = `P4_CAP_NMAX_VALUE;
                    access_error = req_write;
                end
                `P4_REG_CONTROL: if (req_write) begin
                    case (req_wdata)
                        32'd0, 32'd2: access_error = 1'b0;
                        32'd1: access_error = !start_allowed;
                        default: access_error = 1'b1;
                    endcase
                end
                `P4_REG_STATUS: begin
                    read_snapshot = {29'd0, done_pending, result_valid, engine_busy};
                    access_error = req_write;
                end
                `P4_REG_LENGTH: begin
                    read_snapshot = length_reg;
                    access_error = req_write && engine_busy;
                end
                `P4_REG_INTR_STATE: begin
                    read_snapshot = {31'd0, done_pending};
                    access_error = req_write && (req_wdata[31:1] != 31'd0);
                end
                `P4_REG_INTR_ENABLE: begin
                    read_snapshot = {31'd0, intr_enable};
                    access_error = req_write && (req_wdata[31:1] != 31'd0);
                end
                `P4_REG_RESULT: begin
                    read_snapshot = result_reg;
                    access_error = req_write;
                end
                `P4_REG_SUBMIT_ID: begin
                    read_snapshot = submit_id;
                    access_error = req_write;
                end
                `P4_REG_DONE_ID: begin
                    read_snapshot = done_id;
                    access_error = req_write;
                end
                default: access_error = 1'b1;
            endcase
        end
    end

    // Transport state is reset only by global reset. SOFT_RESET is itself an
    // ordinary accepted transaction whose response must remain until consumed.
    always @(posedge clk) begin
        if (rst) begin
            rsp_valid <= 1'b0;
            rsp_rdata <= 32'd0;
            rsp_error <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready) rsp_valid <= 1'b0;
            if (req_fire) begin
                rsp_valid <= 1'b1;
                rsp_rdata <= (req_write || access_error) ? 32'd0 : read_snapshot;
                rsp_error <= access_error;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            length_reg <= 32'd0;
            submit_id <= 32'd0;
            done_id <= 32'd0;
            result_reg <= 32'd0;
            generation <= 32'd0;
            result_valid <= 1'b0;
            done_pending <= 1'b0;
            intr_enable <= 1'b0;
        end else if (soft_reset_o) begin
            length_reg <= 32'd0;
            submit_id <= 32'd0;
            done_id <= 32'd0;
            result_reg <= 32'd0;
            generation <= generation + 32'd1;
            result_valid <= 1'b0;
            done_pending <= 1'b0;
            intr_enable <= 1'b0;
        end else begin
            if (legal_write) begin
                if (offset == `P4_REG_LENGTH) length_reg <= req_wdata;
                else if (offset == `P4_REG_INTR_ENABLE) intr_enable <= req_wdata[0];
            end
            if (start_o) begin
                submit_id <= submit_id + 32'd1;
                result_valid <= 1'b0;
            end
            if (software_w1c) begin
                done_pending <= 1'b0;
                result_valid <= 1'b0;
            end
            // The new event wins a coincident W1C, with result and ID atomic.
            if (engine_complete) begin
                result_reg <= engine_result;
                done_id <= submit_id;
                done_pending <= 1'b1;
                result_valid <= 1'b1;
            end
        end
    end
endmodule
