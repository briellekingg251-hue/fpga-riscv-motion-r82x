`timescale 1ns/1ps

// Small, vendor-neutral synchronous single-port RAM example.
//
// The port has one physical address.  A cycle may read, write, or do both.
// When rd_en and wr_en are both asserted, rd_data is the word value before
// the byte writes in that cycle (read-first read-during-write behavior).
module p1_sync_ram #(
    parameter integer DEPTH_WORDS = 1024,
    parameter integer ADDR_WIDTH =
        (DEPTH_WORDS <= 1) ? 1 : $clog2(DEPTH_WORDS)
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  en,
    input  logic                  rd_en,
    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [3:0]            wstrb,
    input  logic [31:0]           wdata,
    output logic                  rd_valid,
    output logic [31:0]           rd_data
);

    // Memory contents intentionally have no reset loop.  Software or a
    // preload mechanism must initialize locations before relying on them.
    logic [31:0] mem [0:DEPTH_WORDS-1];
    localparam logic [ADDR_WIDTH:0] DEPTH_LIMIT =
        (ADDR_WIDTH + 1)'(DEPTH_WORDS);
    logic [ADDR_WIDTH:0] addr_ext;
    logic        addr_valid;

    assign addr_ext   = {1'b0, addr};
    assign addr_valid = (addr_ext < DEPTH_LIMIT);

    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset control/output state only; the RAM array is not reset.
            rd_valid <= 1'b0;
            rd_data  <= 32'b0;
        end else begin
            // A read request accepted at this edge produces a registered
            // response for the cycle after the request.
            rd_valid <= en && rd_en;

            if (en && rd_en) begin
                if (addr_valid)
                    // This RHS is evaluated before the nonblocking byte
                    // writes below, which defines read-first behavior.
                    rd_data <= mem[addr];
                else
                    rd_data <= 32'b0;
            end

            if (en && wr_en && addr_valid) begin
                for (int lane = 0; lane < 4; lane++) begin
                    if (wstrb[lane])
                        mem[addr][lane*8 +: 8] <= wdata[lane*8 +: 8];
                end
            end
        end
    end

endmodule
