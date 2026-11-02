// rtl/storage/fn_sd_spi.v
`timescale 1ns / 1ps
// Mode-0, MSB-first byte SPI in the CPU clock domain. MMIO responds without
// waiting for the card. Divider/CS cannot change in the middle of a byte.
module fn_sd_spi (
 input wire clk, rst, req_valid, req_write,
 input wire [31:0] req_addr, req_wdata,
 input wire [3:0] req_be,
 output wire req_ready,
 output reg rsp_valid, output reg [31:0] rsp_rdata, output reg rsp_error,
 input wire rsp_ready,
 output reg sd_cs_n, sd_sck, sd_mosi, input wire sd_miso
);
 reg [15:0] divider, count;
 reg [7:0] tx, rx, result;
 reg [2:0] bit_index;
 reg busy, done;
 wire accept=req_valid && req_ready;
 assign req_ready=!rsp_valid;
 wire [7:0] off=req_addr[7:0];
 always @(posedge clk) begin
  if(rst) begin
   divider<=16'd203; count<=0; tx<=8'hff; rx<=0; result<=0;
   bit_index<=0; busy<=0; done<=0; sd_cs_n<=1; sd_sck<=0; sd_mosi<=1;
   rsp_valid<=0; rsp_error<=0; rsp_rdata<=0;
  end else begin
   if(rsp_valid && rsp_ready)rsp_valid<=0;
   if(busy) begin
    if(count!=0)count<=count-1'b1;
    else begin
     count<=divider-1'b1;
     if(!sd_sck) begin sd_sck<=1; rx<={rx[6:0],sd_miso}; end
     else begin
      sd_sck<=0;
      if(bit_index==0)begin busy<=0; done<=1; result<=rx; sd_mosi<=1; end
      else begin bit_index<=bit_index-1'b1; tx<={tx[6:0],1'b1}; sd_mosi<=tx[6]; end
     end
    end
   end
   if(accept) begin
    rsp_valid<=1; rsp_error<=0; rsp_rdata<=0;
    if(req_addr[1:0]!=0 || (req_write && req_be!=4'hf))rsp_error<=1;
    else if(req_write) begin
     case(off)
      8'h08: if(busy)rsp_error<=1; else sd_cs_n<=req_wdata[0];
      8'h0c: if(busy || req_wdata<4 || req_wdata>65535)rsp_error<=1; else divider<=req_wdata[15:0];
      8'h10: if(busy)rsp_error<=1; else begin
       tx<=req_wdata[7:0]; rx<=0; sd_mosi<=req_wdata[7];
       sd_sck<=0; count<=divider-1'b1; bit_index<=7; busy<=1; done<=0;
      end
      default:rsp_error<=1;
     endcase
    end else case(off)
     8'h00:rsp_rdata<=32'h53445331;
     8'h04:rsp_rdata<={30'd0,done,busy};
     8'h08:rsp_rdata<={31'd0,sd_cs_n};
     8'h0c:rsp_rdata<={16'd0,divider};
     8'h10:rsp_rdata<={24'd0,result};
     default:rsp_error<=1;
    endcase
   end
  end
 end
endmodule

// rtl/storage/fn_udp_cardlink.v
`timescale 1ns/1ps
// Fixed-size, one outstanding UDP block RPC. Buffers stay stable until reply
// transmission completes; only the ownership toggles cross clock domains.
module fn_net_absent (
    input wire clk, rst,
    input wire req_valid, output wire req_ready,
    input wire [31:0] req_addr, input wire req_write, input wire [3:0] req_be, input wire [31:0] req_wdata,
    output reg rsp_valid, input wire rsp_ready,
    output wire [31:0] rsp_rdata, output wire rsp_error
);
    // R54: the Ethernet card link is removed (SD cards are written with a card
    // reader). Its MMIO window still answers one response per request: reads
    // return 0, writes are accepted, never an error, so the unchanged boot
    // ROM's PC INSTALL loop sees "no network" instead of an access fault.
    assign req_ready = !rsp_valid;
    assign rsp_rdata = 32'd0;
    assign rsp_error = 1'b0;
    always @(posedge clk)
        if (rst) rsp_valid <= 1'b0;
        else if (rsp_valid && rsp_ready) rsp_valid <= 1'b0;
        else if (req_valid && req_ready) rsp_valid <= 1'b1;
    wire unused = &{1'b0, req_addr, req_write, req_be, req_wdata};
endmodule

// rtl/eth/rgmii_interface.v
`timescale 1ns / 1ps

`define UD #1


// Vendor clock source is supplied separately.

// rtl/cpu/fn_cpu_best.v
// Frozen board-tested CPU modules, extracted verbatim; no SoC/top/PLL.
module p1_core (
	clk,
	rst,
	i_req_valid,
	i_req_ready,
	i_req_addr,
	i_rsp_valid,
	i_rsp_ready,
	i_rsp_data,
	i_rsp_error,
	d_req_valid,
	d_req_ready,
	d_req_addr,
	d_req_write,
	d_req_be,
	d_req_wdata,
	d_rsp_valid,
	d_rsp_ready,
	d_rsp_data,
	d_rsp_error,
	trace_valid,
	trace_trap,
	trace_pc,
	trace_insn,
	trace_rd,
	trace_wdata,
	trace_cause,
	trace_tval,
	trace_mem_valid,
	trace_mem_write,
	trace_mem_addr,
	trace_mem_wdata,
	trace_mem_rdata,
	trace_mem_be,
	halted,
	count_cycle,
	count_retired,
	count_if_wait,
	count_data_wait,
	count_load_use,
	count_redirect,
	count_reads,
	count_writes
);
	parameter [31:0] RESET_PC = 32'h80000000;
	input wire clk;
	input wire rst;
	output wire i_req_valid;
	input wire i_req_ready;
	output wire [31:0] i_req_addr;
	input wire i_rsp_valid;
	output wire i_rsp_ready;
	input wire [31:0] i_rsp_data;
	input wire i_rsp_error;
	output wire d_req_valid;
	input wire d_req_ready;
	output wire [31:0] d_req_addr;
	output wire d_req_write;
	output wire [3:0] d_req_be;
	output wire [31:0] d_req_wdata;
	input wire d_rsp_valid;
	output wire d_rsp_ready;
	input wire [31:0] d_rsp_data;
	input wire d_rsp_error;
	output reg trace_valid;
	output reg trace_trap;
	output reg [31:0] trace_pc;
	output reg [31:0] trace_insn;
	output reg [4:0] trace_rd;
	output reg [31:0] trace_wdata;
	output reg [31:0] trace_cause;
	output reg [31:0] trace_tval;
	output reg trace_mem_valid;
	output reg trace_mem_write;
	output reg [31:0] trace_mem_addr;
	output reg [31:0] trace_mem_wdata;
	output reg [31:0] trace_mem_rdata;
	output reg [3:0] trace_mem_be;
	output reg halted;
	output reg [63:0] count_cycle;
	output reg [63:0] count_retired;
	output reg [63:0] count_if_wait;
	output reg [63:0] count_data_wait;
	output reg [63:0] count_load_use;
	output reg [63:0] count_redirect;
	output reg [63:0] count_reads;
	output reg [63:0] count_writes;
	reg [31:0] regs [0:31];
	reg fq_valid;
	reg fq_discard;
	reg fo_valid;
	reg fo_discard;
	reg fetch_stop;
	reg [31:0] fq_pc;
	reg [31:0] fo_pc;
	reg [31:0] next_pc;
	reg dv;
	reg ev;
	reg mv;
	reg [31:0] dp;
	reg [31:0] di;
	reg [31:0] ep;
	reg [31:0] ei;
	reg [31:0] mp;
	reg [31:0] mi;
	reg de;
	reg ee;
	reg [4:0] mr;
	reg [31:0] mresult;
	reg [31:0] maddr;
	reg [31:0] mwdata;
	reg [31:0] mcause;
	reg [31:0] mtval;
	reg [3:0] mbe;
	reg [2:0] mfunct3;
	reg mmem;
	reg mwrite;
	reg mfault;
	reg msent;
	wire [4:0] rs1 = ei[19:15];
	wire [4:0] rs2 = ei[24:20];
	wire [6:0] op = ei[6:0];
	wire [6:0] f7 = ei[31:25];
	wire [2:0] f3 = ei[14:12];
	wire [31:0] imm_i = {{20 {ei[31]}}, ei[31:20]};
	wire [31:0] imm_s = {{20 {ei[31]}}, ei[31:25], ei[11:7]};
	wire [31:0] imm_b = {{19 {ei[31]}}, ei[31], ei[7], ei[30:25], ei[11:8], 1'b0};
	wire [31:0] imm_j = {{11 {ei[31]}}, ei[31], ei[19:12], ei[20], ei[30:21], 1'b0};
	wire [31:0] imm_u = {ei[31:12], 12'b000000000000};
	wire m_response = (((mv && mmem) && !mfault) && msent) && d_rsp_valid;
	wire m_done = mv && ((mfault || !mmem) || m_response);
	wire m_bad = mfault || (m_response && d_rsp_error);
	wire [31:0] m_final_cause = (mfault ? mcause : (mwrite ? 32'd7 : 32'd5));
	wire [31:0] m_final_tval = (mfault ? mtval : maddr);
	wire [31:0] load_value;
	p1_load_align load_align(
		.data(d_rsp_data),
		.offset(maddr[1:0]),
		.funct3(mfunct3),
		.result(load_value)
	);
	wire [31:0] m_value = (mmem && !mwrite ? load_value : mresult);
	reg [31:0] a;
	reg [31:0] b;
	always @(*) begin
		a = (rs1 == 0 ? 0 : regs[rs1]);
		b = (rs2 == 0 ? 0 : regs[rs2]);
		if ((m_done && !m_bad) && (mr != 0)) begin
			if (mr == rs1)
				a = m_value;
			if (mr == rs2)
				b = m_value;
		end
	end
	reg [31:0] er;
	reg [31:0] ea;
	reg [31:0] ew;
	reg [31:0] ecause;
	reg [31:0] etval;
	reg [31:0] target;
	reg [4:0] rd;
	reg [3:0] be;
	reg mem;
	reg wr;
	reg fault;
	reg redirect;
	reg legal;
	reg use1;
	reg use2;
	always @(*) begin
		er = 0;
		ea = 0;
		ew = 0;
		ecause = 2;
		etval = ei;
		target = 0;
		rd = ei[11:7];
		be = 0;
		mem = 0;
		wr = 0;
		fault = 0;
		redirect = 0;
		legal = 1;
		use1 = 0;
		use2 = 0;
		case (op)
			7'h37: er = imm_u;
			7'h17: er = ep + imm_u;
			7'h6f: begin
				er = ep + 4;
				target = ep + imm_j;
				redirect = 1;
			end
			7'h67: begin
				use1 = 1;
				er = ep + 4;
				target = (a + imm_i) & 32'hfffffffe;
				redirect = 1;
				if (f3 != 0)
					legal = 0;
			end
			7'h63: begin
				use1 = 1;
				use2 = 1;
				rd = 0;
				target = ep + imm_b;
				case (f3)
					0: redirect = a == b;
					1: redirect = a != b;
					4: redirect = $signed(a) < $signed(b);
					5: redirect = $signed(a) >= $signed(b);
					6: redirect = a < b;
					7: redirect = a >= b;
					default: legal = 0;
				endcase
			end
			7'h03, 7'h23: begin
				use1 = 1;
				use2 = op == 7'h23;
				mem = 1;
				wr = op == 7'h23;
				ea = a + (wr ? imm_s : imm_i);
				ew = b << {ea[1:0], 3'b000};
				if (wr)
					rd = 0;
				case (f3)
					0: be = 4'b0001 << ea[1:0];
					1: be = 4'b0011 << ea[1:0];
					2: be = 4'b1111;
					4: begin
						be = 4'b0001 << ea[1:0];
						if (wr)
							legal = 0;
					end
					5: begin
						be = 4'b0011 << ea[1:0];
						if (wr)
							legal = 0;
					end
					default: legal = 0;
				endcase
				if ((((f3 == 1) || (f3 == 5)) && ea[0]) || ((f3 == 2) && |ea[1:0])) begin
					fault = 1;
					ecause = (wr ? 6 : 4);
					etval = ea;
				end
			end
			7'h13: begin
				use1 = 1;
				case (f3)
					0: er = a + imm_i;
					2: er = {31'b0000000000000000000000000000000, $signed(a) < $signed(imm_i)};
					3: er = {31'b0000000000000000000000000000000, a < imm_i};
					4: er = a ^ imm_i;
					6: er = a | imm_i;
					7: er = a & imm_i;
					1: begin
						er = a << ei[24:20];
						if (f7 != 0)
							legal = 0;
					end
					5: begin
						er = (ei[30] ? $unsigned($signed(a) >>> ei[24:20]) : a >> ei[24:20]);
						if ((f7 != 0) && (f7 != 7'h20))
							legal = 0;
					end
					default: legal = 0;
				endcase
			end
			7'h33: begin
				use1 = 1;
				use2 = 1;
				if ((f7 != 0) && !((f7 == 7'h20) && ((f3 == 0) || (f3 == 5))))
					legal = 0;
				case (f3)
					0: er = (ei[30] ? a - b : a + b);
					1: er = a << b[4:0];
					2: er = {31'b0000000000000000000000000000000, $signed(a) < $signed(b)};
					3: er = {31'b0000000000000000000000000000000, a < b};
					4: er = a ^ b;
					5: er = (ei[30] ? $unsigned($signed(a) >>> b[4:0]) : a >> b[4:0]);
					6: er = a | b;
					7: er = a & b;
					default: legal = 0;
				endcase
			end
			7'h0f: begin
				rd = 0;
				if (f3 != 0)
					legal = 0;
			end
			7'h73: begin
				rd = 0;
				fault = 1;
				etval = 0;
				if (ei == 32'h00000073)
					ecause = 11;
				else if (ei == 32'h00100073)
					ecause = 3;
				else
					legal = 0;
			end
			default: legal = 0;
		endcase
		if (redirect && |target[1:0]) begin
			fault = 1;
			ecause = 0;
			etval = target;
		end
		if (!legal) begin
			fault = 1;
			ecause = 2;
			etval = ei;
			mem = 0;
		end
		if (ee) begin
			fault = 1;
			ecause = 1;
			etval = ep;
			mem = 0;
		end
		if (fault) begin
			rd = 0;
			redirect = 0;
		end
	end
	wire e_fire = ((ev && (!mv || m_done)) && !(m_done && m_bad)) && !halted;
	wire m_kill = m_done && m_bad;
	wire e_kill = e_fire && (redirect || fault);
	wire kill = m_kill || e_kill;
	wire d_fire = ((dv && (!ev || e_fire)) && !kill) && !halted;
	assign i_req_valid = fq_valid;
	assign i_req_addr = fq_pc;
	assign i_rsp_ready = fo_valid && ((((fo_discard || !dv) || d_fire) || kill) || fetch_stop);
	wire i_accept = i_req_valid && i_req_ready;
	wire i_return = i_rsp_valid && i_rsp_ready;
	assign d_req_valid = ((mv && mmem) && !mfault) && !msent;
	assign d_req_addr = {maddr[31:2], 2'b00};
	assign d_req_write = mwrite;
	assign d_req_be = mbe;
	assign d_req_wdata = mwdata;
	assign d_rsp_ready = ((mv && mmem) && !mfault) && msent;
	integer n;
	always @(posedge clk)
		if (rst) begin
			for (n = 0; n < 32; n = n + 1)
				regs[n] <= 0;
			fq_valid <= 1;
			fq_pc <= RESET_PC;
			fq_discard <= 0;
			fo_valid <= 0;
			fo_pc <= 0;
			fo_discard <= 0;
			next_pc <= RESET_PC + 4;
			fetch_stop <= 0;
			dv <= 0;
			ev <= 0;
			mv <= 0;
			dp <= 0;
			di <= 0;
			ep <= 0;
			ei <= 0;
			mp <= 0;
			mi <= 0;
			de <= 0;
			ee <= 0;
			mr <= 0;
			mresult <= 0;
			maddr <= 0;
			mwdata <= 0;
			mcause <= 0;
			mtval <= 0;
			mbe <= 0;
			mfunct3 <= 0;
			mmem <= 0;
			mwrite <= 0;
			mfault <= 0;
			msent <= 0;
			halted <= 0;
			trace_valid <= 0;
			trace_trap <= 0;
			trace_pc <= 0;
			trace_insn <= 0;
			trace_rd <= 0;
			trace_wdata <= 0;
			trace_cause <= 0;
			trace_tval <= 0;
			trace_mem_valid <= 0;
			trace_mem_write <= 0;
			trace_mem_addr <= 0;
			trace_mem_wdata <= 0;
			trace_mem_rdata <= 0;
			trace_mem_be <= 0;
			count_cycle <= 0;
			count_retired <= 0;
			count_if_wait <= 0;
			count_data_wait <= 0;
			count_load_use <= 0;
			count_redirect <= 0;
			count_reads <= 0;
			count_writes <= 0;
		end
		else begin
			trace_valid <= 0;
			if (!halted) begin
				count_cycle <= count_cycle + 1;
				if (!dv)
					count_if_wait <= count_if_wait + 1;
				if ((mv && mmem) && !m_done)
					count_data_wait <= count_data_wait + 1;
				if ((((((ev && mv) && mmem) && !mwrite) && !m_done) && (mr != 0)) && ((use1 && (rs1 == mr)) || (use2 && (rs2 == mr))))
					count_load_use <= count_load_use + 1;
			end
			if (d_req_valid && d_req_ready) begin
				msent <= 1;
				if (mwrite)
					count_writes <= count_writes + 1;
				else
					count_reads <= count_reads + 1;
			end
			if (m_done) begin
				mv <= 0;
				trace_valid <= 1;
				trace_trap <= m_bad;
				trace_pc <= mp;
				trace_insn <= mi;
				trace_rd <= (m_bad ? 5'b00000 : mr);
				trace_wdata <= (m_bad || (mr == 0) ? 32'b00000000000000000000000000000000 : m_value);
				trace_cause <= (m_bad ? m_final_cause : 32'b00000000000000000000000000000000);
				trace_tval <= (m_bad ? m_final_tval : 32'b00000000000000000000000000000000);
				trace_mem_valid <= mmem;
				trace_mem_write <= mmem && mwrite;
				trace_mem_addr <= (mmem ? {maddr[31:2], 2'b00} : 32'b00000000000000000000000000000000);
				trace_mem_be <= (mmem ? mbe : 4'b0000);
				trace_mem_wdata <= (mmem && mwrite ? mwdata : 32'b00000000000000000000000000000000);
				trace_mem_rdata <= ((mmem && !mwrite) && !m_bad ? d_rsp_data : 32'b00000000000000000000000000000000);
				if (m_bad)
					halted <= 1;
				else begin
					count_retired <= count_retired + 1;
					if (mr != 0)
						regs[mr] <= m_value;
				end
			end
			if (e_fire) begin
				ev <= 0;
				mv <= 1;
				mp <= ep;
				mi <= ei;
				mr <= rd;
				mresult <= er;
				maddr <= ea;
				mwdata <= ew;
				mbe <= be;
				mfunct3 <= f3;
				mmem <= mem;
				mwrite <= wr;
				mfault <= fault;
				mcause <= ecause;
				mtval <= etval;
				msent <= 0;
			end
			if (d_fire) begin
				ev <= 1;
				ep <= dp;
				ei <= di;
				ee <= de;
				dv <= 0;
			end
			if (i_return) begin
				fo_valid <= 0;
				if ((!fo_discard && !kill) && !fetch_stop) begin
					dv <= 1;
					dp <= fo_pc;
					di <= i_rsp_data;
					de <= i_rsp_error;
				end
			end
			if (i_accept) begin
				fq_valid <= 0;
				fo_valid <= 1;
				fo_pc <= fq_pc;
				fo_discard <= (fq_discard || kill) || fetch_stop;
			end
			if (((!fq_valid && (!fo_valid || i_return)) && !fetch_stop) && !halted) begin
				fq_valid <= 1;
				fq_pc <= next_pc;
				fq_discard <= 0;
				next_pc <= next_pc + 4;
			end
			if (kill) begin
				dv <= 0;
				ev <= 0;
				if (fo_valid && !i_return)
					fo_discard <= 1;
				if (fq_valid && !i_accept)
					fq_discard <= 1;
				if (!fq_valid)
					fq_valid <= 0;
				if (m_kill || fault)
					fetch_stop <= 1;
				else begin
					next_pc <= target;
					count_redirect <= count_redirect + 1;
				end
			end
		end
endmodule
module p1_load_align (
	data,
	offset,
	funct3,
	result
);
	input wire [31:0] data;
	input wire [1:0] offset;
	input wire [2:0] funct3;
	output wire [31:0] result;
	wire [7:0] byte_value = data[{offset, 3'b000}+:8];
	wire [15:0] half_value = (offset[1] ? data[31:16] : data[15:0]);
	wire signed_load = !funct3[2];
	wire [31:0] byte_result = ((funct3 == 0) || (funct3 == 4) ? {{24 {byte_value[7] & signed_load}}, byte_value} : 32'b00000000000000000000000000000000);
	wire [31:0] half_result = ((funct3 == 1) || (funct3 == 5) ? {{16 {half_value[15] & signed_load}}, half_value} : 32'b00000000000000000000000000000000);
	wire [31:0] word_result = (funct3 == 2 ? data : 32'b00000000000000000000000000000000);
	assign result = (byte_result ^ half_result) ^ word_result;
endmodule
module p1_peripherals (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_be,
	req_wdata,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	uart_tx,
	gpio_out
);
	reg _sv2v_0;
	parameter [31:0] UART_BASE = 32'h10000000;
	parameter [31:0] GPIO_BASE = 32'h10001000;
	parameter [31:0] TIMER_BASE = 32'h10002000;
	parameter integer UART_DIVISOR = 8;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output reg req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [3:0] req_be;
	input wire [31:0] req_wdata;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output reg uart_tx;
	output reg [31:0] gpio_out;
	localparam [31:0] UART_DATA_OFF = 32'h00000000;
	localparam [31:0] UART_STATUS_OFF = 32'h00000004;
	localparam [31:0] UART_BAUD_OFF = 32'h00000008;
	localparam [31:0] GPIO_DATA_OFF = 32'h00000000;
	localparam [31:0] TIMER_LO_OFF = 32'h00000000;
	localparam [31:0] TIMER_HI_OFF = 32'h00000004;
	localparam integer UART_DIVISOR_RESET = (UART_DIVISOR < 2 ? 2 : UART_DIVISOR);
	reg [63:0] timer_counter;
	reg [31:0] uart_baud_div;
	reg uart_busy;
	reg [7:0] uart_data;
	reg [3:0] uart_bit_index;
	reg [31:0] uart_baud_count;
	wire rsp_consumed = rsp_valid && rsp_ready;
	wire data_access = req_addr == (UART_BASE + UART_DATA_OFF);
	wire baud_access = req_addr == (UART_BASE + UART_BAUD_OFF);
	wire data_write_blocked = ((data_access && req_write) && req_be[0]) && uart_busy;
	wire baud_write_blocked = ((baud_access && req_write) && (req_be != 4'd0)) && uart_busy;
	always @(*) begin
		if (_sv2v_0)
			;
		req_ready = ((!rsp_valid || rsp_ready) && !data_write_blocked) && !baud_write_blocked;
	end
	wire req_fire = req_valid && req_ready;
	always @(posedge clk)
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
		end
		else begin
			timer_counter <= timer_counter + 64'd1;
			if (rsp_consumed)
				rsp_valid <= 1'b0;
			if (uart_busy) begin
				if (uart_baud_count >= (uart_baud_div - 32'd1)) begin
					uart_baud_count <= 32'd0;
					if (uart_bit_index == 4'd9) begin
						uart_busy <= 1'b0;
						uart_tx <= 1'b1;
					end
					else begin
						uart_bit_index <= uart_bit_index + 4'd1;
						if (uart_bit_index == 4'd0)
							uart_tx <= uart_data[0];
						else if (uart_bit_index < 4'd8)
							uart_tx <= uart_data[uart_bit_index[2:0]];
						else
							uart_tx <= 1'b1;
					end
				end
				else
					uart_baud_count <= uart_baud_count + 32'd1;
			end
			if (req_fire) begin
				rsp_valid <= 1'b1;
				rsp_rdata <= 32'd0;
				rsp_error <= 1'b0;
				if ((req_addr >= UART_BASE) && (req_addr < (UART_BASE + 32'h00001000)))
					case (req_addr - UART_BASE)
						UART_DATA_OFF:
							if (req_write) begin
								if (req_be[0] && !uart_busy) begin
									uart_data <= req_wdata[7:0];
									uart_busy <= 1'b1;
									uart_bit_index <= 4'd0;
									uart_baud_count <= 32'd0;
									uart_tx <= 1'b0;
								end
							end
						UART_STATUS_OFF:
							if (req_write)
								rsp_error <= 1'b1;
							else
								rsp_rdata <= {31'd0, uart_busy};
						UART_BAUD_OFF:
							if (req_write) begin
								if (!uart_busy) begin
									if ({(req_be[3] ? req_wdata[31:24] : uart_baud_div[31:24]), (req_be[2] ? req_wdata[23:16] : uart_baud_div[23:16]), (req_be[1] ? req_wdata[15:8] : uart_baud_div[15:8]), (req_be[0] ? req_wdata[7:0] : uart_baud_div[7:0])} < 32'd2)
										uart_baud_div <= 32'd2;
									else
										uart_baud_div <= {(req_be[3] ? req_wdata[31:24] : uart_baud_div[31:24]), (req_be[2] ? req_wdata[23:16] : uart_baud_div[23:16]), (req_be[1] ? req_wdata[15:8] : uart_baud_div[15:8]), (req_be[0] ? req_wdata[7:0] : uart_baud_div[7:0])};
								end
							end
							else
								rsp_rdata <= uart_baud_div;
						default: rsp_error <= 1'b1;
					endcase
				else if ((req_addr >= GPIO_BASE) && (req_addr < (GPIO_BASE + 32'h00001000)))
					case (req_addr - GPIO_BASE)
						GPIO_DATA_OFF:
							if (req_write) begin
								if (req_be[0])
									gpio_out[7:0] <= req_wdata[7:0];
								if (req_be[1])
									gpio_out[15:8] <= req_wdata[15:8];
								if (req_be[2])
									gpio_out[23:16] <= req_wdata[23:16];
								if (req_be[3])
									gpio_out[31:24] <= req_wdata[31:24];
							end
							else
								rsp_rdata <= gpio_out;
						default: rsp_error <= 1'b1;
					endcase
				else if ((req_addr >= TIMER_BASE) && (req_addr < (TIMER_BASE + 32'h00001000)))
					case (req_addr - TIMER_BASE)
						TIMER_LO_OFF:
							if (req_write)
								rsp_error <= 1'b1;
							else
								rsp_rdata <= timer_counter[31:0];
						TIMER_HI_OFF:
							if (req_write)
								rsp_error <= 1'b1;
							else
								rsp_rdata <= timer_counter[63:32];
						default: rsp_error <= 1'b1;
					endcase
				else
					rsp_error <= 1'b1;
			end
		end
	initial _sv2v_0 = 0;
endmodule
module p2_burst_arbiter2 (
	clk,
	rst,
	a_cmd_valid,
	a_cmd_ready,
	a_cmd_write,
	a_cmd_addr,
	a_cmd_len,
	a_w_valid,
	a_w_ready,
	a_w_data,
	a_w_be,
	a_w_last,
	a_r_valid,
	a_r_ready,
	a_r_data,
	a_r_error,
	a_r_last,
	b_cmd_valid,
	b_cmd_ready,
	b_cmd_write,
	b_cmd_addr,
	b_cmd_len,
	b_w_valid,
	b_w_ready,
	b_w_data,
	b_w_be,
	b_w_last,
	b_r_valid,
	b_r_ready,
	b_r_data,
	b_r_error,
	b_r_last,
	m_cmd_valid,
	m_cmd_ready,
	m_cmd_write,
	m_cmd_addr,
	m_cmd_len,
	m_w_valid,
	m_w_ready,
	m_w_data,
	m_w_be,
	m_w_last,
	m_r_valid,
	m_r_ready,
	m_r_data,
	m_r_error,
	m_r_last
);
	input wire clk;
	input wire rst;
	input wire a_cmd_valid;
	output wire a_cmd_ready;
	input wire a_cmd_write;
	input wire [31:0] a_cmd_addr;
	input wire [7:0] a_cmd_len;
	input wire a_w_valid;
	output wire a_w_ready;
	input wire [31:0] a_w_data;
	input wire [3:0] a_w_be;
	input wire a_w_last;
	output wire a_r_valid;
	input wire a_r_ready;
	output wire [31:0] a_r_data;
	output wire a_r_error;
	output wire a_r_last;
	input wire b_cmd_valid;
	output wire b_cmd_ready;
	input wire b_cmd_write;
	input wire [31:0] b_cmd_addr;
	input wire [7:0] b_cmd_len;
	input wire b_w_valid;
	output wire b_w_ready;
	input wire [31:0] b_w_data;
	input wire [3:0] b_w_be;
	input wire b_w_last;
	output wire b_r_valid;
	input wire b_r_ready;
	output wire [31:0] b_r_data;
	output wire b_r_error;
	output wire b_r_last;
	output wire m_cmd_valid;
	input wire m_cmd_ready;
	output wire m_cmd_write;
	output wire [31:0] m_cmd_addr;
	output wire [7:0] m_cmd_len;
	output wire m_w_valid;
	input wire m_w_ready;
	output wire [31:0] m_w_data;
	output wire [3:0] m_w_be;
	output wire m_w_last;
	input wire m_r_valid;
	output wire m_r_ready;
	input wire [31:0] m_r_data;
	input wire m_r_error;
	input wire m_r_last;
	localparam [1:0] IDLE = 0;
	localparam [1:0] COMMAND = 1;
	localparam [1:0] ACTIVE = 2;
	reg [1:0] state;
	reg owner;
	reg prefer_b;
	assign m_cmd_valid = ((state == COMMAND) && (owner ? b_cmd_valid : a_cmd_valid)) && !rst;
	assign m_cmd_write = (owner ? b_cmd_write : a_cmd_write);
	assign m_cmd_addr = (owner ? b_cmd_addr : a_cmd_addr);
	assign m_cmd_len = (owner ? b_cmd_len : a_cmd_len);
	assign a_cmd_ready = (((state == COMMAND) && !owner) && m_cmd_ready) && !rst;
	assign b_cmd_ready = (((state == COMMAND) && owner) && m_cmd_ready) && !rst;
	assign m_w_valid = ((state == ACTIVE) && (owner ? b_w_valid : a_w_valid)) && !rst;
	assign m_w_data = (owner ? b_w_data : a_w_data);
	assign m_w_be = (owner ? b_w_be : a_w_be);
	assign m_w_last = (owner ? b_w_last : a_w_last);
	assign a_w_ready = (((state == ACTIVE) && !owner) && m_w_ready) && !rst;
	assign b_w_ready = (((state == ACTIVE) && owner) && m_w_ready) && !rst;
	assign a_r_valid = (((state == ACTIVE) && !owner) && m_r_valid) && !rst;
	assign b_r_valid = (((state == ACTIVE) && owner) && m_r_valid) && !rst;
	assign a_r_data = m_r_data;
	assign b_r_data = m_r_data;
	assign a_r_error = m_r_error;
	assign b_r_error = m_r_error;
	assign a_r_last = m_r_last;
	assign b_r_last = m_r_last;
	assign m_r_ready = ((state == ACTIVE) && (owner ? b_r_ready : a_r_ready)) && !rst;
	always @(posedge clk)
		if (rst) begin
			state <= IDLE;
			owner <= 0;
			prefer_b <= 0;
		end
		else
			case (state)
				IDLE:
					if (a_cmd_valid || b_cmd_valid) begin
						owner <= (a_cmd_valid && b_cmd_valid ? prefer_b : b_cmd_valid);
						state <= COMMAND;
					end
				COMMAND:
					if (m_cmd_valid && m_cmd_ready)
						state <= ACTIVE;
				ACTIVE:
					if ((m_r_valid && m_r_ready) && m_r_last) begin
						prefer_b <= !owner;
						state <= IDLE;
					end
				default: state <= IDLE;
			endcase
endmodule
module p2_burst_sram (
	clk,
	rst,
	cmd_valid,
	cmd_ready,
	cmd_write,
	cmd_addr,
	cmd_len,
	w_valid,
	w_ready,
	w_data,
	w_be,
	w_last,
	r_valid,
	r_ready,
	r_data,
	r_error,
	r_last
);
	parameter [31:0] RAM_BASE = 32'h80000000;
	parameter integer RAM_BYTES = 131072;
	parameter _sv2v_width_INIT_FILE = 8;
	parameter [_sv2v_width_INIT_FILE - 1:0] INIT_FILE = "";
	input wire clk;
	input wire rst;
	input wire cmd_valid;
	output wire cmd_ready;
	input wire cmd_write;
	input wire [31:0] cmd_addr;
	input wire [7:0] cmd_len;
	input wire w_valid;
	output wire w_ready;
	input wire [31:0] w_data;
	input wire [3:0] w_be;
	input wire w_last;
	output wire r_valid;
	input wire r_ready;
	output wire [31:0] r_data;
	output wire r_error;
	output wire r_last;
	localparam integer AW = $clog2(RAM_BYTES / 4);
	localparam [1:0] IDLE = 0;
	localparam [1:0] READ = 1;
	localparam [1:0] WRITE = 2;
	localparam [1:0] ACK = 3;
	reg [1:0] state;
	reg [31:0] mem [0:(RAM_BYTES / 4) - 1];
	reg [31:0] read_q;
	reg [AW - 1:0] word_addr;
	reg [7:0] beat;
	reg [7:0] length;
	reg bad;
	localparam integer END_BITS = (AW > 8 ? AW : 8) + 1;
	localparam integer ALIGNED_REGION = (((RAM_BYTES >= 8) && ((RAM_BYTES & (RAM_BYTES - 1)) == 0)) && ((RAM_BASE & (RAM_BYTES - 1)) == 0)) && (({1'b0, RAM_BASE} + RAM_BYTES) <= 33'h100000000);
	wire cmd_bad;
	function automatic [END_BITS - 1:0] sv2v_cast_CFFB1;
		input reg [END_BITS - 1:0] inp;
		sv2v_cast_CFFB1 = inp;
	endfunction
	function automatic signed [END_BITS - 1:0] sv2v_cast_CFFB1_signed;
		input reg signed [END_BITS - 1:0] inp;
		sv2v_cast_CFFB1_signed = inp;
	endfunction
	generate
		if (ALIGNED_REGION) begin : bounded_command
			wire address_tag_match = (cmd_addr & ~(RAM_BYTES - 1)) == RAM_BASE;
			wire [END_BITS - 1:0] offset_words = sv2v_cast_CFFB1((cmd_addr & (RAM_BYTES - 1)) >> 2);
			wire [END_BITS - 1:0] end_words = offset_words + sv2v_cast_CFFB1(cmd_len);
			assign cmd_bad = ((|cmd_addr[1:0] || (cmd_len == 0)) || !address_tag_match) || (end_words > sv2v_cast_CFFB1_signed(RAM_BYTES / 4));
		end
		else begin : generic_command
			assign cmd_bad = (((cmd_addr[1:0] != 0) || (cmd_len == 0)) || ({1'b0, cmd_addr} < {1'b0, RAM_BASE})) || (({1'b0, cmd_addr} + ({25'b0000000000000000000000000, cmd_len} << 2)) > ({1'b0, RAM_BASE} + RAM_BYTES));
		end
	endgenerate
	function automatic [AW - 1:0] sv2v_cast_DE851;
		input reg [AW - 1:0] inp;
		sv2v_cast_DE851 = inp;
	endfunction
	wire [AW - 1:0] first_word = sv2v_cast_DE851((cmd_addr - RAM_BASE) >> 2);
	wire initial_read = ((cmd_valid && cmd_ready) && !cmd_write) && !cmd_bad;
	wire first_read_capture = ((cmd_valid && cmd_ready) && !cmd_write) && (ALIGNED_REGION || !cmd_bad);
	wire next_read = ((((state == READ) && r_valid) && r_ready) && (beat != (length - 1))) && !bad;
	wire [AW - 1:0] read_addr = (state == IDLE ? first_word : word_addr + 1'b1);
	integer lane;
	initial if (INIT_FILE != {_sv2v_width_INIT_FILE {1'b0}})
		$readmemh(INIT_FILE, mem);
	always @(posedge clk) begin
		if (first_read_capture || next_read)
			read_q <= mem[read_addr];
		for (lane = 0; lane < 4; lane = lane + 1)
			if (((((!rst && (state == WRITE)) && w_valid) && w_ready) && !bad) && w_be[lane])
				mem[word_addr][8 * lane+:8] <= w_data[8 * lane+:8];
	end
	assign cmd_ready = (state == IDLE) && !rst;
	assign w_ready = (state == WRITE) && !rst;
	assign r_valid = ((state == READ) || (state == ACK)) && !rst;
	assign r_data = (bad || (state == ACK) ? 32'b00000000000000000000000000000000 : read_q);
	assign r_error = bad;
	assign r_last = (state == ACK) || (beat == (length - 1));
	always @(posedge clk)
		if (rst) begin
			state <= IDLE;
			word_addr <= 0;
			beat <= 0;
			length <= 0;
			bad <= 0;
		end
		else
			case (state)
				IDLE:
					if (cmd_valid) begin
						word_addr <= first_word;
						beat <= 0;
						length <= (cmd_len == 0 ? 8'd1 : cmd_len);
						bad <= cmd_bad;
						state <= (cmd_write ? WRITE : READ);
					end
				READ:
					if (r_ready) begin
						if (beat == (length - 1))
							state <= IDLE;
						else begin
							beat <= beat + 1'b1;
							word_addr <= word_addr + 1'b1;
						end
					end
				WRITE:
					if (w_valid) begin
						bad <= bad || (w_last != (beat == (length - 1)));
						if (beat == (length - 1))
							state <= ACK;
						else begin
							beat <= beat + 1'b1;
							word_addr <= word_addr + 1'b1;
						end
					end
				ACK:
					if (r_ready)
						state <= IDLE;
				default: state <= IDLE;
			endcase
endmodule
module p2_cache (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_be,
	req_wdata,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	rsp_data_hi,
	rsp_hi_valid,
	rsp_predecode,
	rsp_predecode_hi,
	maint_valid,
	maint_ready,
	maint_clean,
	maint_invalidate,
	maint_done,
	maint_error,
	fatal,
	cmd_valid,
	cmd_ready,
	cmd_write,
	cmd_addr,
	cmd_len,
	w_valid,
	w_ready,
	w_data,
	w_be,
	w_last,
	r_valid,
	r_ready,
	r_data,
	r_error,
	r_last,
	count_hit,
	count_miss,
	count_writeback
);
	parameter integer READ_ONLY = 0;
	parameter integer CACHE_BYTES = 8192;
	parameter integer LINE_BYTES = 32;
	parameter [31:0] RAM_BASE = 32'h80000000;
	parameter integer RAM_BYTES = 131072;
	parameter integer ENABLED = 1;
	parameter integer DC_LOAD_HIT_TURNOVER = 0;
	parameter integer STORE_PREDECODE = 0;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [3:0] req_be;
	input wire [31:0] req_wdata;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	output wire [31:0] rsp_data_hi;
	output wire rsp_hi_valid;
	output wire [6:0] rsp_predecode;
	output wire [6:0] rsp_predecode_hi;
	input wire maint_valid;
	output wire maint_ready;
	input wire maint_clean;
	input wire maint_invalidate;
	output wire maint_done;
	output wire maint_error;
	output reg fatal;
	output wire cmd_valid;
	input wire cmd_ready;
	output wire cmd_write;
	output wire [31:0] cmd_addr;
	output wire [7:0] cmd_len;
	output wire w_valid;
	input wire w_ready;
	output wire [31:0] w_data;
	output wire [3:0] w_be;
	output wire w_last;
	input wire r_valid;
	output wire r_ready;
	input wire [31:0] r_data;
	input wire r_error;
	input wire r_last;
	output reg [63:0] count_hit;
	output reg [63:0] count_miss;
	output reg [63:0] count_writeback;
	localparam integer SETS = CACHE_BYTES / (2 * LINE_BYTES);
	localparam integer WORDS = LINE_BYTES / 4;
	localparam integer LB = $clog2(LINE_BYTES);
	localparam integer SB = $clog2(SETS);
	localparam integer DB = $clog2(CACHE_BYTES / 8);
	localparam integer RAM_AB = $clog2(RAM_BYTES);
	localparam integer COMPACT_TAGS = (((RAM_BYTES > 0) && ((RAM_BYTES & (RAM_BYTES - 1)) == 0)) && ((RAM_BASE & (RAM_BYTES - 1)) == 0)) && (RAM_AB >= (LB + SB));
	localparam integer TAG_BITS = (COMPACT_TAGS ? (RAM_AB > (LB + SB) ? (RAM_AB - LB) - SB : 1) : 32);
	function automatic signed [7:0] sv2v_cast_8_signed;
		input reg signed [7:0] inp;
		sv2v_cast_8_signed = inp;
	endfunction
	localparam [7:0] LAST_BEAT = sv2v_cast_8_signed(WORDS - 1);
	localparam [7:0] LINE_WORDS = sv2v_cast_8_signed(WORDS);
	function automatic signed [SB - 1:0] sv2v_cast_C2F86_signed;
		input reg signed [SB - 1:0] inp;
		sv2v_cast_C2F86_signed = inp;
	endfunction
	localparam [SB - 1:0] LAST_SET = sv2v_cast_C2F86_signed(SETS - 1);
	localparam [4:0] IDLE = 0;
	localparam [4:0] LOOKUP = 1;
	localparam [4:0] RESPONSE = 2;
	localparam [4:0] FILL_CMD = 3;
	localparam [4:0] FILL_DATA = 4;
	localparam [4:0] WB_CMD = 5;
	localparam [4:0] WB_DATA = 6;
	localparam [4:0] WB_ACK = 7;
	localparam [4:0] BY_CMD = 8;
	localparam [4:0] BY_DATA = 9;
	localparam [4:0] BY_ACK = 10;
	localparam [4:0] SCAN = 11;
	localparam [4:0] SCAN_NEXT = 12;
	localparam [4:0] M_DONE = 13;
	localparam [4:0] HALT = 14;
	localparam [4:0] STORE_REREAD = 15;
	localparam [4:0] INIT_META = 16;
	reg [4:0] state;
	(* syn_ramstyle = "lut_ram" *) reg [TAG_BITS - 1:0] tag0 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg [TAG_BITS - 1:0] tag1 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg valid0 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg valid1 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg dirty0 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg dirty1 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg replacement_mem [0:SETS - 1];
	reg ram_re;
	reg ram_we0;
	reg ram_we1;
	reg [DB - 1:0] ram_raddr;
	reg [DB - 1:0] ram_waddr;
	reg [31:0] ram_wdata;
	reg [3:0] ram_be;
	reg [31:0] ram_q0;
	reg [31:0] ram_q1;
	reg [31:0] ram_q0_hi;
	reg [31:0] ram_q1_hi;
	reg [6:0] ram_pre0;
	reg [6:0] ram_pre1;
	reg [6:0] ram_pre0_hi;
	reg [6:0] ram_pre1_hi;
	function automatic [6:0] cache_predecode;
		input [31:0] insn;
		reg [6:0] op;
		reg [2:0] f3;
		reg [6:0] f7;
		begin
			op = insn[6:0];
			f3 = insn[14:12];
			f7 = insn[31:25];
			cache_predecode[0] = (((op == 7'h37) || (op == 7'h17)) || ((op == 7'h13) && ((((f3 != 3'b001) && (f3 != 3'b101)) || ((f3 == 3'b001) && (f7 == 0))) || ((f3 == 3'b101) && ((f7 == 0) || (f7 == 7'h20)))))) || ((op == 7'h33) && ((f7 == 0) || ((f7 == 7'h20) && ((f3 == 0) || (f3 == 5)))));
			cache_predecode[1] = ((((((op == 7'h37) || (op == 7'h17)) || (op == 7'h13)) || (op == 7'h33)) || (op == 7'h03)) || (op == 7'h23)) || (op == 7'h63);
			cache_predecode[2] = ((op != 7'h23) && (op != 7'h63)) && (insn[11:7] != 0);
			cache_predecode[3] = ((op == 7'h13) || (op == 7'h33)) || (op == 7'h63);
			cache_predecode[4] = (op == 7'h33) || (op == 7'h63);
			cache_predecode[5] = ((op == 7'h63) && (f3[2] || (f3[2:1] == 2'b00))) && !insn[8];
			cache_predecode[6] = op == 7'h63;
		end
	endfunction
	generate
		if (READ_ONLY != 0) begin : g_icache_banks
			reg [31:0] data0_even [0:((SETS * WORDS) / 2) - 1];
			reg [31:0] data0_odd [0:((SETS * WORDS) / 2) - 1];
			reg [31:0] data1_even [0:((SETS * WORDS) / 2) - 1];
			reg [31:0] data1_odd [0:((SETS * WORDS) / 2) - 1];
			wire [DB - 2:0] low_bank_addr = ram_raddr[DB - 1:1];
			wire [DB - 2:0] high_even_addr = low_bank_addr + 1'b1;
			wire next_in_line = ram_raddr[LB - 3:0] != {LB - 2 {1'b1}};
			always @(posedge clk) begin
				if (ram_re) begin
					if (!ram_raddr[0]) begin
						ram_q0 <= data0_even[low_bank_addr];
						ram_q1 <= data1_even[low_bank_addr];
						ram_q0_hi <= data0_odd[low_bank_addr];
						ram_q1_hi <= data1_odd[low_bank_addr];
					end
					else begin
						ram_q0 <= data0_odd[low_bank_addr];
						ram_q1 <= data1_odd[low_bank_addr];
						if (next_in_line) begin
							ram_q0_hi <= data0_even[high_even_addr];
							ram_q1_hi <= data1_even[high_even_addr];
						end
					end
				end
				if (ram_we0 && !ram_waddr[0])
					data0_even[ram_waddr[DB - 1:1]] <= ram_wdata;
				if (ram_we0 && ram_waddr[0])
					data0_odd[ram_waddr[DB - 1:1]] <= ram_wdata;
				if (ram_we1 && !ram_waddr[0])
					data1_even[ram_waddr[DB - 1:1]] <= ram_wdata;
				if (ram_we1 && ram_waddr[0])
					data1_odd[ram_waddr[DB - 1:1]] <= ram_wdata;
			end
		end
		else begin : g_dcache_banks
			reg [31:0] data0 [0:(SETS * WORDS) - 1];
			reg [31:0] data1 [0:(SETS * WORDS) - 1];
			integer lane_d;
			always @(posedge clk) begin
				if (ram_re) begin
					ram_q0 <= data0[ram_raddr];
					ram_q1 <= data1[ram_raddr];
				end
				for (lane_d = 0; lane_d < 4; lane_d = lane_d + 1)
					begin
						if (ram_we0 && ram_be[lane_d])
							data0[ram_waddr][8 * lane_d+:8] <= ram_wdata[8 * lane_d+:8];
						if (ram_we1 && ram_be[lane_d])
							data1[ram_waddr][8 * lane_d+:8] <= ram_wdata[8 * lane_d+:8];
					end
			end
		end
		if ((READ_ONLY != 0) && (STORE_PREDECODE != 0)) begin : g_predecode_banks
			reg [7:0] pre0_even [0:((SETS * WORDS) / 2) - 1];
			reg [7:0] pre0_odd [0:((SETS * WORDS) / 2) - 1];
			reg [7:0] pre1_even [0:((SETS * WORDS) / 2) - 1];
			reg [7:0] pre1_odd [0:((SETS * WORDS) / 2) - 1];
			wire [DB - 2:0] low_bank_addr = ram_raddr[DB - 1:1];
			wire [DB - 2:0] high_even_addr = low_bank_addr + 1'b1;
			wire next_in_line = ram_raddr[LB - 3:0] != {LB - 2 {1'b1}};
			always @(posedge clk) begin
				if (ram_re) begin
					if (!ram_raddr[0]) begin
						ram_pre0 <= pre0_even[low_bank_addr];
						ram_pre1 <= pre1_even[low_bank_addr];
						ram_pre0_hi <= pre0_odd[low_bank_addr];
						ram_pre1_hi <= pre1_odd[low_bank_addr];
					end
					else begin
						ram_pre0 <= pre0_odd[low_bank_addr];
						ram_pre1 <= pre1_odd[low_bank_addr];
						if (next_in_line) begin
							ram_pre0_hi <= pre0_even[high_even_addr];
							ram_pre1_hi <= pre1_even[high_even_addr];
						end
					end
				end
				if (ram_we0 && !ram_waddr[0])
					pre0_even[ram_waddr[DB - 1:1]] <= {1'b0, cache_predecode(ram_wdata)};
				if (ram_we0 && ram_waddr[0])
					pre0_odd[ram_waddr[DB - 1:1]] <= {1'b0, cache_predecode(ram_wdata)};
				if (ram_we1 && !ram_waddr[0])
					pre1_even[ram_waddr[DB - 1:1]] <= {1'b0, cache_predecode(ram_wdata)};
				if (ram_we1 && ram_waddr[0])
					pre1_odd[ram_waddr[DB - 1:1]] <= {1'b0, cache_predecode(ram_wdata)};
			end
		end
	endgenerate
	reg [31:0] rsp_rdata_q;
	reg [31:0] rsp_data_hi_q;
	reg [6:0] rsp_pre_q;
	reg [6:0] rsp_pre_hi_q;
	reg rsp_lo_zero_q;
	reg rsp_hi_zero_q;
	wire [31:0] rsp_rdata_saved = (rsp_lo_zero_q ? 32'b00000000000000000000000000000000 : rsp_rdata_q);
	wire [31:0] rsp_data_hi_saved = (rsp_hi_zero_q ? 32'b00000000000000000000000000000000 : rsp_data_hi_q);
	reg rsp_hi_valid_q;
	reg rsp_error_q;
	reg held_load_hit_q;
	reg [31:0] addr_q;
	reg [31:0] wdata_q;
	reg [31:0] wb_addr_q;
	reg write_q;
	reg [3:0] be_q;
	reg [7:0] beat;
	reg victim_way;
	reg [SB - 1:0] victim_set;
	reg [SB - 1:0] scan_set;
	reg scan_way;
	reg cleaning;
	reg invalidating;
	reg from_maint;
	reg fill_failed;
	reg maint_failed;
	wire [SB - 1:0] set_q = addr_q[LB+:SB];
	wire [31:0] line_q = addr_q & ~(LINE_BYTES - 1);
	wire [TAG_BITS - 1:0] line_tag = (COMPACT_TAGS ? (RAM_AB == (LB + SB) ? 32'b00000000000000000000000000000000 : addr_q >> (LB + SB)) : line_q);
	function automatic [31:0] restore_line;
		input [TAG_BITS - 1:0] stored_tag;
		input [SB - 1:0] stored_set;
		reg [31:0] tag_extended;
		reg [31:0] set_extended;
		begin
			tag_extended = stored_tag;
			set_extended = stored_set;
			restore_line = (COMPACT_TAGS ? (RAM_BASE | (tag_extended << (LB + SB))) | (set_extended << LB) : tag_extended);
		end
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	wire [7:0] word_q = sv2v_cast_8(addr_q[2+:LB - 2]);
	reg lookup_hit0_q;
	reg lookup_hit1_q;
	reg lookup_valid0_q;
	reg lookup_valid1_q;
	reg lookup_replace_q;
	reg lookup_dirty0_q;
	reg lookup_dirty1_q;
	wire [SB - 1:0] request_set = (state == STORE_REREAD ? set_q : req_addr[LB+:SB]);
	wire [31:0] request_probe_addr = (state == STORE_REREAD ? addr_q : req_addr);
	wire [TAG_BITS - 1:0] request_probe_tag = (COMPACT_TAGS ? (RAM_AB == (LB + SB) ? 32'b00000000000000000000000000000000 : request_probe_addr >> (LB + SB)) : request_probe_addr & ~(LINE_BYTES - 1));
	wire hit0 = lookup_hit0_q;
	wire hit1 = lookup_hit1_q;
	always @(posedge clk)
		if (rst) begin
			lookup_hit0_q <= 0;
			lookup_hit1_q <= 0;
			lookup_valid0_q <= 0;
			lookup_valid1_q <= 0;
			lookup_replace_q <= 0;
			lookup_dirty0_q <= 0;
			lookup_dirty1_q <= 0;
		end
		else begin
			lookup_hit0_q <= valid0[request_set] && (tag0[request_set] == request_probe_tag);
			lookup_hit1_q <= valid1[request_set] && (tag1[request_set] == request_probe_tag);
			lookup_valid0_q <= valid0[request_set];
			lookup_valid1_q <= valid1[request_set];
			lookup_dirty0_q <= dirty0[request_set];
			lookup_dirty1_q <= dirty1[request_set];
			lookup_replace_q <= replacement_mem[request_set];
			if (((state == LOOKUP) && (hit0 ^ hit1)) && (request_set == set_q)) begin
				lookup_replace_q <= hit0;
				if (write_q) begin
					if (hit0)
						lookup_dirty0_q <= 1'b1;
					if (hit1)
						lookup_dirty1_q <= 1'b1;
				end
			end
		end
	wire choose_way = (!lookup_valid0_q ? 1'b0 : (!lookup_valid1_q ? 1'b1 : lookup_replace_q));
	wire chosen_dirty;
	wire scan_valid;
	wire scan_dirty;
	wire fill_bad_now;
	reg [SB - 1:0] meta_write_set;
	reg meta_v0_we;
	reg meta_v1_we;
	reg meta_d0_we;
	reg meta_d1_we;
	reg meta_valid_value;
	reg meta_dirty_value;
	always @(*) begin
		meta_write_set = victim_set;
		meta_v0_we = 0;
		meta_v1_we = 0;
		meta_d0_we = 0;
		meta_d1_we = 0;
		meta_valid_value = 0;
		meta_dirty_value = 0;
		case (state)
			INIT_META: begin
				meta_write_set = scan_set;
				meta_v0_we = 1;
				meta_v1_we = 1;
				meta_d0_we = 1;
				meta_d1_we = 1;
			end
			LOOKUP: begin
				meta_write_set = set_q;
				if (hit0 ^ hit1) begin
					meta_d0_we = write_q && hit0;
					meta_d1_we = write_q && hit1;
					meta_dirty_value = 1;
				end
				else if ((!hit0 && !hit1) && !chosen_dirty) begin
					meta_v0_we = !choose_way;
					meta_v1_we = choose_way;
				end
			end
			WB_ACK:
				if ((r_valid && !r_error) && r_last) begin
					meta_d0_we = !victim_way;
					meta_d1_we = victim_way;
					if (!from_maint || invalidating) begin
						meta_v0_we = !victim_way;
						meta_v1_we = victim_way;
					end
				end
			FILL_DATA:
				if ((r_valid && (beat == LAST_BEAT)) && !(fill_failed || fill_bad_now)) begin
					meta_v0_we = !victim_way;
					meta_v1_we = victim_way;
					meta_d0_we = !victim_way;
					meta_d1_we = victim_way;
					meta_valid_value = 1;
					meta_dirty_value = write_q;
				end
			SCAN: begin
				meta_write_set = scan_set;
				if (!((scan_valid && scan_dirty) && (cleaning || invalidating)) && invalidating) begin
					meta_v0_we = !scan_way;
					meta_v1_we = scan_way;
				end
			end
			default:
				;
		endcase
	end
	always @(posedge clk)
		if (!rst) begin
			if (meta_v0_we)
				valid0[meta_write_set] <= meta_valid_value;
			if (meta_v1_we)
				valid1[meta_write_set] <= meta_valid_value;
			if (meta_d0_we)
				dirty0[meta_write_set] <= meta_dirty_value;
			if (meta_d1_we)
				dirty1[meta_write_set] <= meta_dirty_value;
		end
	assign chosen_dirty = (choose_way ? lookup_dirty1_q : lookup_dirty0_q);
	wire [SB - 1:0] scan_probe_set = (state == IDLE ? {SB {1'b0}} : ((state == SCAN_NEXT) && scan_way ? scan_set + 1'b1 : scan_set));
	reg scan_valid0_q;
	reg scan_valid1_q;
	reg scan_dirty0_q;
	reg scan_dirty1_q;
	always @(posedge clk)
		if (rst) begin
			scan_valid0_q <= 0;
			scan_valid1_q <= 0;
			scan_dirty0_q <= 0;
			scan_dirty1_q <= 0;
		end
		else begin
			scan_valid0_q <= valid0[scan_probe_set];
			scan_valid1_q <= valid1[scan_probe_set];
			scan_dirty0_q <= dirty0[scan_probe_set];
			scan_dirty1_q <= dirty1[scan_probe_set];
		end
	assign scan_valid = (scan_way ? scan_valid1_q : scan_valid0_q);
	assign scan_dirty = (scan_way ? scan_dirty1_q : scan_dirty0_q);
	wire [32:0] req_ext = {1'b0, req_addr};
	wire [32:0] limit_ext = {1'b0, RAM_BASE} + RAM_BYTES;
	wire [31:0] req_line = req_addr & ~(LINE_BYTES - 1);
	localparam integer BOUNDED_REGION = (((((RAM_BYTES >= LINE_BYTES) && (LINE_BYTES >= 4)) && ((RAM_BYTES & (RAM_BYTES - 1)) == 0)) && ((LINE_BYTES & (LINE_BYTES - 1)) == 0)) && ((RAM_BASE & (RAM_BYTES - 1)) == 0)) && (({1'b0, RAM_BASE} + RAM_BYTES) <= 33'h100000000);
	wire word_in_ram;
	wire line_in_ram;
	generate
		if (BOUNDED_REGION) begin : bounded_region
			wire same_region = (req_addr & ~(RAM_BYTES - 1)) == RAM_BASE;
			assign word_in_ram = same_region && ((req_addr & (RAM_BYTES - 1)) <= (RAM_BYTES - 4));
			assign line_in_ram = same_region;
		end
		else begin : generic_region
			assign word_in_ram = (req_ext >= {1'b0, RAM_BASE}) && ((req_ext + 33'd4) <= limit_ext);
			assign line_in_ram = ({1'b0, req_line} >= {1'b0, RAM_BASE}) && (({1'b0, req_line} + LINE_BYTES) <= limit_ext);
		end
	endgenerate
	assign fill_bad_now = r_error || (r_last != (beat == LAST_BEAT));
	wire replacement_hit_write = (state == LOOKUP) && (hit0 ^ hit1);
	wire replacement_fill_write = (((state == FILL_DATA) && r_valid) && (beat == LAST_BEAT)) && !(fill_failed || fill_bad_now);
	wire [SB - 1:0] replacement_write_set = (replacement_hit_write ? set_q : victim_set);
	wire replacement_write_value = (replacement_hit_write ? hit0 : !victim_way);
	always @(posedge clk)
		if (!rst && (replacement_hit_write || replacement_fill_write))
			replacement_mem[replacement_write_set] <= replacement_write_value;
	wire fast_hit = ((state == LOOKUP) && (hit0 ^ hit1)) && !fatal;
	wire read_only_turnover = ((READ_ONLY != 0) && rsp_ready) && ((state == RESPONSE) || fast_hit);
	wire direct_load_hit = fast_hit && !write_q;
	wire held_load_hit = (state == RESPONSE) && held_load_hit_q;
	wire d_load_turnover = (((((DC_LOAD_HIT_TURNOVER != 0) && (READ_ONLY == 0)) && (direct_load_hit || held_load_hit)) && rsp_valid) && rsp_ready) && !rsp_error;
	wire d_store_turnover = ((((DC_LOAD_HIT_TURNOVER != 0) && (READ_ONLY == 0)) && fast_hit) && write_q) && rsp_ready;
	wire store_word_collision = d_store_turnover && (req_addr[2+:DB] == addr_q[2+:DB]);
	assign req_ready = ((((((state == IDLE) || read_only_turnover) || d_load_turnover) || d_store_turnover) && !maint_valid) && !fatal) && !rst;
	assign rsp_rdata = (state == LOOKUP ? (hit1 ? ram_q1 : ram_q0) : rsp_rdata_saved);
	assign rsp_error = rsp_error_q;
	assign rsp_data_hi = (READ_ONLY != 0 ? (state == LOOKUP ? (hit1 ? ram_q1_hi : ram_q0_hi) : rsp_data_hi_saved) : 32'b00000000000000000000000000000000);
	assign rsp_predecode = ((READ_ONLY != 0) && (STORE_PREDECODE != 0) ? (state == LOOKUP ? (hit1 ? ram_pre1 : ram_pre0) : (rsp_lo_zero_q ? 7'b0000000 : rsp_pre_q)) : 7'b0000000);
	assign rsp_predecode_hi = ((READ_ONLY != 0) && (STORE_PREDECODE != 0) ? (state == LOOKUP ? (hit1 ? ram_pre1_hi : ram_pre0_hi) : (rsp_hi_zero_q ? 7'b0000000 : rsp_pre_hi_q)) : 7'b0000000);
	assign rsp_hi_valid = (((READ_ONLY != 0) && rsp_valid) && !rsp_error) && (fast_hit ? word_q != LAST_BEAT : rsp_hi_valid_q);
	assign maint_ready = ((state == IDLE) && !fatal) && !rst;
	assign rsp_valid = ((state == RESPONSE) || fast_hit) && !rst;
	assign maint_done = (state == M_DONE) && !rst;
	assign maint_error = maint_failed;
	assign cmd_valid = (((state == FILL_CMD) || (state == WB_CMD)) || (state == BY_CMD)) && !rst;
	assign cmd_write = (state == WB_CMD) || ((state == BY_CMD) && write_q);
	assign cmd_addr = (state == WB_CMD ? wb_addr_q : (state == BY_CMD ? addr_q : line_q));
	assign cmd_len = (state == BY_CMD ? 8'd1 : LINE_WORDS);
	assign w_valid = ((state == WB_DATA) || (state == BY_DATA)) && !rst;
	assign w_data = (state == BY_DATA ? wdata_q : (victim_way ? ram_q1 : ram_q0));
	assign w_be = (state == BY_DATA ? be_q : 4'hf);
	assign w_last = (state == BY_DATA) || (beat == LAST_BEAT);
	assign r_ready = (((state == FILL_DATA) || (state == WB_ACK)) || (state == BY_ACK)) && !rst;
	wire count_hit_fire = (state == LOOKUP) && (hit0 ^ hit1);
	wire count_miss_fire = ((state == LOOKUP) && !hit0) && !hit1;
	wire count_writeback_fire = (((state == WB_ACK) && r_valid) && !r_error) && r_last;
	reg [2:0] count_hit_full_q;
	reg [2:0] count_miss_full_q;
	reg [2:0] count_writeback_full_q;
	genvar _gv_count_chunk_1;
	generate
		for (_gv_count_chunk_1 = 0; _gv_count_chunk_1 < 4; _gv_count_chunk_1 = _gv_count_chunk_1 + 1) begin : segmented_counts
			localparam count_chunk = _gv_count_chunk_1;
			wire hit_carry;
			wire miss_carry;
			wire writeback_carry;
			if (count_chunk == 0) begin : low
				assign hit_carry = 1'b1;
				assign miss_carry = 1'b1;
				assign writeback_carry = 1'b1;
			end
			else begin : high
				assign hit_carry = &count_hit_full_q[count_chunk - 1:0];
				assign miss_carry = &count_miss_full_q[count_chunk - 1:0];
				assign writeback_carry = &count_writeback_full_q[count_chunk - 1:0];
			end
			always @(posedge clk)
				if (rst) begin
					count_hit[count_chunk * 16+:16] <= 0;
					count_miss[count_chunk * 16+:16] <= 0;
					count_writeback[count_chunk * 16+:16] <= 0;
				end
				else begin
					if (count_hit_fire && hit_carry)
						count_hit[count_chunk * 16+:16] <= count_hit[count_chunk * 16+:16] + 16'd1;
					if (count_miss_fire && miss_carry)
						count_miss[count_chunk * 16+:16] <= count_miss[count_chunk * 16+:16] + 16'd1;
					if (count_writeback_fire && writeback_carry)
						count_writeback[count_chunk * 16+:16] <= count_writeback[count_chunk * 16+:16] + 16'd1;
				end
			if (count_chunk < 3) begin : lookahead
				always @(posedge clk)
					if (rst) begin
						count_hit_full_q[count_chunk] <= 0;
						count_miss_full_q[count_chunk] <= 0;
						count_writeback_full_q[count_chunk] <= 0;
					end
					else begin
						if (count_hit_fire && hit_carry)
							count_hit_full_q[count_chunk] <= count_hit[count_chunk * 16+:16] == 16'hfffe;
						if (count_miss_fire && miss_carry)
							count_miss_full_q[count_chunk] <= count_miss[count_chunk * 16+:16] == 16'hfffe;
						if (count_writeback_fire && writeback_carry)
							count_writeback_full_q[count_chunk] <= count_writeback[count_chunk * 16+:16] == 16'hfffe;
					end
			end
		end
	endgenerate
	function automatic [31:0] merge_word;
		input [31:0] old_data;
		input [31:0] new_data;
		input [3:0] mask;
		integer k;
		begin
			merge_word = old_data;
			for (k = 0; k < 4; k = k + 1)
				if (mask[k])
					merge_word[k * 8+:8] = new_data[k * 8+:8];
		end
	endfunction
	always @(*) begin
		ram_re = 0;
		ram_raddr = 0;
		ram_we0 = 0;
		ram_we1 = 0;
		ram_waddr = 0;
		ram_wdata = 0;
		ram_be = 0;
		if (!rst) begin
			if ((ENABLED != 0) && (((state == IDLE) || (state == LOOKUP)) || (state == RESPONSE))) begin
				ram_re = 1;
				ram_raddr = req_addr[2+:DB];
			end
			if ((READ_ONLY == 0) && (state == STORE_REREAD)) begin
				ram_re = 1;
				ram_raddr = addr_q[2+:DB];
			end
			if (((state == LOOKUP) && (hit0 ^ hit1)) && write_q) begin
				ram_we0 = hit0;
				ram_we1 = hit1;
				ram_waddr = addr_q[2+:DB];
				ram_wdata = wdata_q;
				ram_be = be_q;
			end
			if (((state == FILL_DATA) && r_valid) && r_ready) begin
				ram_we0 = !victim_way;
				ram_we1 = victim_way;
				ram_waddr = {victim_set, beat[LB - 3:0]};
				ram_wdata = (write_q && (beat == word_q) ? merge_word(r_data, wdata_q, be_q) : r_data);
				ram_be = 4'hf;
			end
			if ((state == WB_CMD) && cmd_ready) begin
				ram_re = 1;
				ram_raddr = {victim_set, {LB - 2 {1'b0}}};
			end
			if (((state == WB_DATA) && w_ready) && (beat != LAST_BEAT)) begin
				ram_re = 1;
				ram_raddr = {victim_set, beat[LB - 3:0]} + 1'b1;
			end
		end
	end
	always @(posedge clk)
		if (rst) begin
			state <= INIT_META;
			addr_q <= 0;
			wdata_q <= 0;
			be_q <= 0;
			write_q <= 0;
			wb_addr_q <= 0;
			beat <= 0;
			victim_way <= 0;
			victim_set <= 0;
			scan_set <= 0;
			scan_way <= 0;
			cleaning <= 0;
			invalidating <= 0;
			from_maint <= 0;
			fill_failed <= 0;
			maint_failed <= 0;
			fatal <= 0;
			rsp_rdata_q <= 0;
			rsp_error_q <= 0;
			if ((READ_ONLY != 0) && (STORE_PREDECODE != 0)) begin
				rsp_pre_q <= 0;
				rsp_pre_hi_q <= 0;
			end
			rsp_data_hi_q <= 0;
			rsp_hi_valid_q <= 0;
			rsp_lo_zero_q <= 1;
			rsp_hi_zero_q <= 1;
			held_load_hit_q <= 0;
		end
		else begin
			if (state != RESPONSE)
				held_load_hit_q <= 0;
			case (state)
				INIT_META:
					if (scan_set == LAST_SET) begin
						scan_set <= 0;
						state <= IDLE;
					end
					else
						scan_set <= scan_set + 1'b1;
				IDLE:
					if (maint_valid && maint_ready) begin
						cleaning <= maint_clean;
						invalidating <= maint_invalidate;
						scan_set <= 0;
						scan_way <= 0;
						maint_failed <= 0;
						state <= (ENABLED != 0 ? SCAN : M_DONE);
					end
				STORE_REREAD: state <= LOOKUP;
				LOOKUP:
					if (hit0 && hit1) begin
						fatal <= 1;
						state <= HALT;
					end
					else if (hit0 || hit1) begin
						rsp_rdata_q <= (hit1 ? ram_q1 : ram_q0);
						rsp_lo_zero_q <= 0;
						if ((READ_ONLY != 0) && (STORE_PREDECODE != 0)) begin
							rsp_pre_q <= (hit1 ? ram_pre1 : ram_pre0);
							rsp_pre_hi_q <= (hit1 ? ram_pre1_hi : ram_pre0_hi);
						end
						if (READ_ONLY != 0) begin
							rsp_data_hi_q <= (hit1 ? ram_q1_hi : ram_q0_hi);
							rsp_hi_zero_q <= 0;
							rsp_hi_valid_q <= word_q != LAST_BEAT;
						end
						held_load_hit_q <= (fast_hit && !write_q) && !rsp_ready;
						state <= (fast_hit && rsp_ready ? IDLE : RESPONSE);
					end
					else begin
						victim_way <= choose_way;
						victim_set <= set_q;
						beat <= 0;
						wb_addr_q <= restore_line((choose_way ? tag1[set_q] : tag0[set_q]), set_q);
						fill_failed <= 0;
						if (chosen_dirty)
							state <= WB_CMD;
						else
							state <= FILL_CMD;
					end
				WB_CMD:
					if (cmd_ready) begin
						beat <= 0;
						state <= WB_DATA;
					end
				WB_DATA:
					if (w_ready) begin
						if (beat == LAST_BEAT)
							state <= WB_ACK;
						else
							beat <= beat + 1'b1;
					end
				WB_ACK:
					if (r_valid) begin
						if (r_error || !r_last) begin
							fatal <= 1;
							if (from_maint) begin
								maint_failed <= 1;
								state <= M_DONE;
							end
							else
								state <= HALT;
						end
						else if (from_maint)
							state <= SCAN_NEXT;
						else begin
							beat <= 0;
							fill_failed <= 0;
							state <= FILL_CMD;
						end
					end
				FILL_CMD:
					if (cmd_ready) begin
						beat <= 0;
						state <= FILL_DATA;
					end
				FILL_DATA:
					if (r_valid) begin
						fill_failed <= fill_failed || fill_bad_now;
						if (beat == word_q) begin
							rsp_rdata_q <= r_data;
							rsp_lo_zero_q <= 0;
							if ((READ_ONLY != 0) && (STORE_PREDECODE != 0))
								rsp_pre_q <= cache_predecode(r_data);
						end
						if (((READ_ONLY != 0) && (word_q != LAST_BEAT)) && (beat == (word_q + 8'd1))) begin
							rsp_data_hi_q <= r_data;
							rsp_hi_zero_q <= 0;
							if (STORE_PREDECODE != 0)
								rsp_pre_hi_q <= cache_predecode(r_data);
						end
						if (beat == LAST_BEAT) begin
							rsp_error_q <= fill_failed || fill_bad_now;
							rsp_hi_valid_q <= ((READ_ONLY != 0) && (word_q != LAST_BEAT)) && !(fill_failed || fill_bad_now);
							if (!(fill_failed || fill_bad_now)) begin
								if (victim_way)
									tag1[victim_set] <= line_tag;
								else
									tag0[victim_set] <= line_tag;
							end
							state <= RESPONSE;
						end
						else
							beat <= beat + 1'b1;
					end
				BY_CMD:
					if (cmd_ready)
						state <= (write_q ? BY_DATA : BY_ACK);
				BY_DATA:
					if (w_ready)
						state <= BY_ACK;
				BY_ACK:
					if (r_valid) begin
						rsp_rdata_q <= r_data;
						rsp_lo_zero_q <= 0;
						rsp_error_q <= r_error || !r_last;
						state <= RESPONSE;
						if ((READ_ONLY != 0) && (STORE_PREDECODE != 0))
							rsp_pre_q <= cache_predecode(r_data);
					end
				RESPONSE:
					if (rsp_ready) begin
						held_load_hit_q <= 0;
						state <= IDLE;
					end
				SCAN:
					if ((scan_valid && scan_dirty) && (cleaning || invalidating)) begin
						victim_set <= scan_set;
						victim_way <= scan_way;
						wb_addr_q <= restore_line((scan_way ? tag1[scan_set] : tag0[scan_set]), scan_set);
						from_maint <= 1;
						beat <= 0;
						state <= WB_CMD;
					end
					else
						state <= SCAN_NEXT;
				SCAN_NEXT:
					if (!scan_way) begin
						scan_way <= 1;
						state <= SCAN;
					end
					else if (scan_set == LAST_SET)
						state <= M_DONE;
					else begin
						scan_way <= 0;
						scan_set <= scan_set + 1'b1;
						state <= SCAN;
					end
				M_DONE: state <= (fatal ? HALT : IDLE);
				HALT: state <= HALT;
				default: begin
					fatal <= 1;
					state <= HALT;
				end
			endcase
			if (req_valid && req_ready) begin
				addr_q <= req_addr;
				write_q <= req_write;
				be_q <= req_be;
				wdata_q <= req_wdata;
				rsp_error_q <= 0;
				rsp_lo_zero_q <= 1;
				rsp_hi_zero_q <= 1;
				rsp_hi_valid_q <= 0;
				from_maint <= 0;
				held_load_hit_q <= 0;
				if ((req_addr[1:0] != 0) || ((READ_ONLY != 0) && (req_write || !word_in_ram))) begin
					rsp_error_q <= 1;
					state <= RESPONSE;
				end
				else if ((ENABLED != 0) && line_in_ram)
					state <= (store_word_collision ? STORE_REREAD : LOOKUP);
				else
					state <= BY_CMD;
			end
		end
endmodule
module p2_core (
	clk,
	rst,
	perf_cache_flat,
	i_req_valid,
	i_req_ready,
	i_req_addr,
	i_rsp_valid,
	i_rsp_ready,
	i_rsp_data,
	i_rsp_error,
	i_rsp_data_hi,
	i_rsp_hi_valid,
	i_rsp_predecode,
	i_rsp_predecode_hi,
	d_req_valid,
	d_req_ready,
	d_req_addr,
	d_req_write,
	d_req_be,
	d_req_wdata,
	d_rsp_valid,
	d_rsp_ready,
	d_rsp_data,
	d_rsp_error,
	d_rsp_terminal,
	irq_software,
	irq_timer,
	irq_external,
	fatal_error,
	run_stop,
	data_idle,
	machine_cycle,
	machine_retired,
	fence_i_valid,
	fence_i_ready,
	fence_i_done,
	fence_i_error,
	trace_irq_valid,
	trace_irq_pc,
	trace_irq_cause,
	trace_csr_valid,
	trace_csr_read,
	trace_csr_write,
	trace_csr_addr,
	trace_csr_rdata,
	trace_csr_wdata,
	trace_valid,
	trace_trap,
	trace_valid1,
	trace_pc1,
	trace_insn1,
	trace_rd1,
	trace_wdata1,
	trace_pc,
	trace_insn,
	trace_rd,
	trace_wdata,
	trace_cause,
	trace_tval,
	trace_mem_valid,
	trace_mem_write,
	trace_mem_addr,
	trace_mem_wdata,
	trace_mem_rdata,
	trace_mem_be,
	halted,
	count_cycle,
	count_retired,
	count_if_wait,
	count_data_wait,
	count_load_use,
	count_redirect,
	count_reads,
	count_writes
);
	reg _sv2v_0;
	parameter [31:0] RESET_PC = 32'h80000000;
	parameter MACHINE_MODE = 1;
	parameter BP_ENABLED = 1;
	parameter FIFO_DEPTH = 2;
	parameter RESPONSE_BYPASS = 0;
	parameter BTB_ENTRIES = 64;
	parameter BHT_ENTRIES = 256;
	parameter RAS_DEPTH = 0;
	parameter EARLY_LSU = 0;
	parameter HW_MUL = 0;
	parameter IFETCH_DUAL_WORDS = 1;
	parameter IFETCH_LINE_BYTES = 32;
	parameter IFETCH_PREDECODE = 0;
	input wire clk;
	input wire rst;
	input wire [319:0] perf_cache_flat;
	output wire i_req_valid;
	input wire i_req_ready;
	output wire [31:0] i_req_addr;
	input wire i_rsp_valid;
	output wire i_rsp_ready;
	input wire [31:0] i_rsp_data;
	input wire i_rsp_error;
	input wire [31:0] i_rsp_data_hi;
	input wire i_rsp_hi_valid;
	input wire [6:0] i_rsp_predecode;
	input wire [6:0] i_rsp_predecode_hi;
	output wire d_req_valid;
	input wire d_req_ready;
	output wire [31:0] d_req_addr;
	output wire d_req_write;
	output wire [3:0] d_req_be;
	output wire [31:0] d_req_wdata;
	input wire d_rsp_valid;
	output wire d_rsp_ready;
	input wire [31:0] d_rsp_data;
	input wire d_rsp_error;
	input wire d_rsp_terminal;
	input wire irq_software;
	input wire irq_timer;
	input wire irq_external;
	input wire fatal_error;
	input wire run_stop;
	output wire data_idle;
	output wire [63:0] machine_cycle;
	output wire [63:0] machine_retired;
	output wire fence_i_valid;
	input wire fence_i_ready;
	input wire fence_i_done;
	input wire fence_i_error;
	output reg trace_irq_valid;
	output reg [31:0] trace_irq_pc;
	output reg [31:0] trace_irq_cause;
	output reg trace_csr_valid;
	output reg trace_csr_read;
	output reg trace_csr_write;
	output reg [11:0] trace_csr_addr;
	output reg [31:0] trace_csr_rdata;
	output reg [31:0] trace_csr_wdata;
	output reg trace_valid;
	output reg trace_trap;
	output reg trace_valid1;
	output reg [31:0] trace_pc1;
	output reg [31:0] trace_insn1;
	output reg [4:0] trace_rd1;
	output reg [31:0] trace_wdata1;
	output reg [31:0] trace_pc;
	output reg [31:0] trace_insn;
	output reg [4:0] trace_rd;
	output reg [31:0] trace_wdata;
	output reg [31:0] trace_cause;
	output reg [31:0] trace_tval;
	output reg trace_mem_valid;
	output reg trace_mem_write;
	output reg [31:0] trace_mem_addr;
	output reg [31:0] trace_mem_wdata;
	output reg [31:0] trace_mem_rdata;
	output reg [3:0] trace_mem_be;
	output reg halted;
	output reg [63:0] count_cycle;
	output reg [63:0] count_retired;
	output reg [63:0] count_if_wait;
	output reg [63:0] count_data_wait;
	output reg [63:0] count_load_use;
	output reg [63:0] count_redirect;
	output reg [63:0] count_reads;
	output reg [63:0] count_writes;
	(* syn_ramstyle = "lut_ram" *) reg [31:0] rf_bank0 [0:31];
	(* syn_ramstyle = "lut_ram" *) reg [31:0] rf_bank1 [0:31];
	reg [31:0] rf_valid_q;
	reg [31:0] rf_owner_q;
	reg rf_wb0_valid_q;
	reg rf_wb1_valid_q;
	reg [4:0] rf_wb0_rd_q;
	reg [4:0] rf_wb1_rd_q;
	reg [31:0] rf_wb0_data_q;
	reg [31:0] rf_wb1_data_q;
	reg fetch_stop;
	reg terminal_stopped;
	wire dv;
	wire de;
	wire dv1;
	wire de1;
	reg ev;
	reg mv;
	reg ev1;
	reg mv1_raw_q;
	wire mv1;
	reg m_tgt_eq1_q;
	reg m_ft_eq1_q;
	reg m1_branch_q;
	reg m1_bne_q;
	reg [31:0] epred1;
	reg [31:0] m1_fall_q;
	reg m1_wrong_taken_q;
	reg m1_wrong_nt_q;
	reg [3:0] mbranch1_eq8;
	reg [31:0] mtarget1;
	reg e_lui_pair_q;
	wire e_lui_pair = ev1 && e_lui_pair_q;
	function automatic [2:0] bitfusion_kind;
		input [31:0] head;
		input [31:0] tail;
		begin
			bitfusion_kind = 0;
			if (((head[11:7] != 0) && (tail[19:15] == head[11:7])) && (tail[6:0] == 7'h13)) begin
				if (((head[6:0] == 7'h33) && (head[14:12] == 4)) && (head[31:25] == 0)) begin
					if ((tail[14:12] == 7) && (tail[31:20] == 12'h001))
						bitfusion_kind = 1;
					if ((tail[14:12] == 1) && (tail[31:20] == 12'h010))
						bitfusion_kind = 2;
				end
				if ((((head[6:0] == 7'h13) && (head[14:12] == 1)) && (head[31:20] == 12'h010)) && (tail[14:12] == 5)) begin
					if (tail[31:20] == 12'h010)
						bitfusion_kind = 3;
					if (tail[31:20] == 12'h410)
						bitfusion_kind = 4;
				end
			end
		end
	endfunction
	reg [2:0] e_bitfusion_q;
	reg [3:0] e_fusion_sel_q;
	reg e_late1_enable_q;
	reg e_alu_imm0_q;
	reg e_alu_sub0_q;
	reg e_alu_left0_q;
	reg e_alu_arith0_q;
	reg e_alu_imm1_q;
	reg e_alu_sub1_q;
	reg e_alu_left1_q;
	reg e_alu_arith1_q;
	wire e_bitfusion = ev1 && (e_bitfusion_q != 0);
	wire [31:0] di;
	wire [31:0] di1;
	wire [2:0] d_bitfusion = bitfusion_kind(di, di1);
	function automatic [31:0] bitfusion_result;
		input [2:0] kind;
		input [31:0] lhs;
		input [31:0] rhs;
		case (kind)
			1: bitfusion_result = {31'b0000000000000000000000000000000, lhs[0] ^ rhs[0]};
			2: bitfusion_result = {lhs[15:0] ^ rhs[15:0], 16'b0000000000000000};
			3: bitfusion_result = {16'b0000000000000000, lhs[15:0]};
			4: bitfusion_result = {{16 {lhs[15]}}, lhs[15:0]};
			default: bitfusion_result = 0;
		endcase
	endfunction
	wire mv1_exec = (MACHINE_MODE == 0 ? mv1 : mv1_raw_q);
	wire [31:0] dp;
	wire [31:0] dp1;
	wire [31:0] front_prediction;
	wire [31:0] front_prediction1;
	wire front_sequential;
	wire front_sequential1;
	wire front_pair_link;
	wire [6:0] front_pre0;
	wire [6:0] front_pre1;
	reg [31:0] ep;
	reg [31:0] ei;
	reg [31:0] mp;
	reg [31:0] mi;
	reg [31:0] ep1;
	reg [31:0] ei1;
	reg [31:0] mp1;
	reg [31:0] mi1;
	reg ee;
	reg ee1;
	reg [11:0] e_lsu_imm12_q;
	reg e_store_q;
	wire [31:0] e_lsu_imm = {{20 {e_lsu_imm12_q[11]}}, e_lsu_imm12_q};
	reg [4:0] mr;
	reg mr_nonzero_q;
	reg [31:0] mresult;
	reg [31:0] maddr;
	reg [31:0] mwdata;
	reg [31:0] mcause;
	reg [31:0] mtval;
	reg [31:0] mresult1_payload;
	reg [31:0] mlate_b1;
	reg mlate0;
	reg mlate1;
	reg mlate_sub0;
	reg mlate_left0;
	reg mlate_arith0;
	reg mlate_sub1;
	reg mlate_left1;
	reg mlate_arith1;
	reg [4:0] mr1;
	reg hit0_rs1_q;
	reg hit0_rs2_q;
	reg hit0_rs1_1_q;
	reg hit0_rs2_1_q;
	reg hit1_rs1_q;
	reg hit1_rs2_q;
	reg hit1_rs1_1_q;
	reg hit1_rs2_1_q;
	reg mr1_nonzero_q;
	reg mmul_pipe_q;
	reg mmul1_live_q;
	wire [31:0] mul_result;
	reg [1:0] slowL_q;
	reg [1:0] ld_q;
	reg late_q;
	reg [3:0] any_q;
	function automatic hit_next;
		input fire;
		input capture;
		input [4:0] e_dest;
		input [4:0] m_dest;
		input [4:0] d_src;
		input [4:0] e_src;
		hit_next = (fire ? (capture ? e_dest == d_src : e_dest == e_src) : (capture ? m_dest == d_src : m_dest == e_src));
	endfunction
	function automatic literal_hit_next;
		input fire;
		input capture;
		input [4:0] e_dest;
		input [4:0] m_dest;
		input [4:0] d_src;
		input [4:0] e_src;
		input d_literal;
		input e_literal;
		reg normal_hit;
		reg literal_selected;
		reg zero_destination;
		begin
			normal_hit = hit_next(fire, capture, e_dest, m_dest, d_src, e_src);
			literal_selected = (capture ? d_literal : e_literal);
			zero_destination = (fire ? e_dest == 0 : m_dest == 0);
			literal_hit_next = (literal_selected ? zero_destination : normal_hit);
		end
	endfunction
	reg [3:0] mbe;
	reg [2:0] mfunct3;
	reg mmem;
	reg mwrite;
	reg mfault;
	reg msent;
	reg mcsr;
	reg mmret;
	reg mfencei;
	reg mfence_sent;
	reg mcontrol;
	reg mconditional;
	reg [31:0] epred;
	reg [31:0] mtarget_base;
	reg [31:0] commit_next_pc;
	reg m_wrong_taken_q;
	reg m_wrong_nt_q;
	reg [31:0] m_fall_q;
	reg [31:0] m_fall4_q;
	reg [31:0] m_fall8_q;
	reg [31:0] m_tgt4_q;
	reg [31:0] m_tgt8_q;
	reg [31:0] m1_tgt4_q;
	reg [31:0] m1_tgt8_q;
	reg [31:0] m1_fall4_q;
	reg [31:0] m1_fall8_q;
	reg [31:0] mbranch_a;
	reg [31:0] mbranch_b;
	reg [31:0] mpred;
	reg [3:0] mbranch_eq8;
	reg [3:0] mbranch_lt8;
	reg mbranch_signed_top_lt;
	wire mbranch_eq_all = &mbranch_eq8;
	wire mbranch_lo_lt = mbranch_lt8[1] || (mbranch_eq8[1] && mbranch_lt8[0]);
	wire mbranch_hi_eq = mbranch_eq8[3] && mbranch_eq8[2];
	wire mbranch_hi_lt = mbranch_lt8[3] || (mbranch_eq8[3] && mbranch_lt8[2]);
	wire mbranch_hi_signed_lt = mbranch_signed_top_lt || (mbranch_eq8[3] && mbranch_lt8[2]);
	wire mbranch_unsigned_lt = mbranch_hi_lt || (mbranch_hi_eq && mbranch_lo_lt);
	wire mbranch_signed_lt = mbranch_hi_signed_lt || (mbranch_hi_eq && mbranch_lo_lt);
	wire [4:0] rs1 = ei[19:15];
	wire [4:0] rs2 = ei[24:20];
	wire [6:0] op = ei[6:0];
	wire [6:0] f7 = ei[31:25];
	wire [2:0] f3 = ei[14:12];
	wire [31:0] imm_i = {{20 {ei[31]}}, ei[31:20]};
	wire [31:0] imm_s = {{20 {ei[31]}}, ei[31:25], ei[11:7]};
	wire [31:0] imm_b = {{19 {ei[31]}}, ei[31], ei[7], ei[30:25], ei[11:8], 1'b0};
	wire [31:0] imm_j = {{11 {ei[31]}}, ei[31], ei[19:12], ei[20], ei[30:21], 1'b0};
	wire [31:0] imm_u = {ei[31:12], 12'b000000000000};
	wire m_response = (((mv && mmem) && !mfault) && msent) && d_rsp_valid;
	wire m_done = mv && (mfault || (mfencei ? (mfence_sent && fence_i_done) && !fence_i_error : !mmem || m_response));
	wire [31:0] csr_rdata;
	wire [31:0] csr_modify_rdata;
	wire [31:0] csr_wdata;
	wire [31:0] handler_pc;
	wire [31:0] return_pc;
	wire [31:0] irq_cause;
	wire csr_error;
	wire irq_eligible;
	function automatic csr_permission_illegal;
		input [31:0] instruction;
		reg [11:0] address;
		reg standard_known;
		reg zero_known;
		reg performance_known;
		reg write_access;
		begin
			address = instruction[31:20];
			standard_known = ((((((((((((((((((address == 12'h300) || (address == 12'h301)) || (address == 12'h304)) || (address == 12'h305)) || (address == 12'h320)) || (address == 12'h340)) || (address == 12'h341)) || (address == 12'h342)) || (address == 12'h343)) || (address == 12'h344)) || (address == 12'hb00)) || (address == 12'hb80)) || (address == 12'hb02)) || (address == 12'hb82)) || (address == 12'hf11)) || (address == 12'hf12)) || (address == 12'hf13)) || (address == 12'hf14)) || (address == 12'hf15);
			zero_known = (((address == 12'h310) || ((address >= 12'hb03) && (address <= 12'hb1f))) || ((address >= 12'hb83) && (address <= 12'hb9f))) || ((address >= 12'h323) && (address <= 12'h33f));
			performance_known = (address >= 12'hfc0) && (address <= 12'hfef);
			write_access = (instruction[13:12] == 2'b01) || (instruction[19:15] != 0);
			csr_permission_illegal = !((standard_known || zero_known) || performance_known) || (write_access && (address[11:10] == 2'b11));
		end
	endfunction
	reg mcsr_illegal_q;
	wire csr_error_reference;
	assign csr_error = (mv && mcsr) && mcsr_illegal_q;
	wire csr_read = (mi[13:12] != 2'b01) || mr_nonzero_q;
	wire csr_write = (mi[13:12] == 2'b01) || (mi[19:15] != 0);
	wire [31:0] mcsr_operand = (mi[14] ? {27'b000000000000000000000000000, mi[19:15]} : mbranch_a);
	assign csr_wdata = (mi[13:12] == 2'b01 ? mcsr_operand : (mi[13:12] == 2'b10 ? csr_modify_rdata | mcsr_operand : csr_modify_rdata & ~mcsr_operand));
	wire mbranch_taken;
	reg mbranch_low_lt_direction_q;
	reg mbranch_low_ge_direction_q;
	reg mbranch_eq_taken_q;
	reg mbranch_order_hi_lt_q;
	reg mbranch_order_hi_eq_q;
	reg mbranch_order_lo_lt_q;
	wire mbranch_order_lt = mbranch_order_hi_lt_q || (mbranch_order_hi_eq_q && mbranch_order_lo_lt_q);
	reg m1_decision_q;
	reg m1_order_low_lt_q;
	reg m1_order_low_ge_q;
	reg m1_order_lower_lt_q;
	wire m1_order_direction = (m1_order_lower_lt_q ? m1_order_low_lt_q : m1_order_low_ge_q);
	assign mbranch_taken = (mbranch_order_lo_lt_q ? mbranch_low_lt_direction_q : mbranch_low_ge_direction_q);
	function automatic branch_half_direction;
		input [2:0] kind;
		input [31:0] lhs;
		input [31:0] rhs;
		input lower_lt;
		reg [10:0] equal3;
		reg [3:0] high_lt4;
		reg [3:0] high_eq4;
		reg all_equal;
		reg high_unsigned_lt;
		reg high_signed_lt;
		reg high_equal;
		reg high_lt;
		reg ordered;
		integer j;
		begin
			for (j = 0; j < 10; j = j + 1)
				equal3[j] = lhs[j * 3+:3] == rhs[j * 3+:3];
			equal3[10] = lhs[31:30] == rhs[31:30];
			all_equal = &equal3;
			for (j = 0; j < 4; j = j + 1)
				begin
					high_lt4[j] = lhs[16 + (j * 4)+:4] < rhs[16 + (j * 4)+:4];
					high_eq4[j] = lhs[16 + (j * 4)+:4] == rhs[16 + (j * 4)+:4];
				end
			high_unsigned_lt = ((high_lt4[3] || (high_eq4[3] && high_lt4[2])) || ((high_eq4[3] && high_eq4[2]) && high_lt4[1])) || (((high_eq4[3] && high_eq4[2]) && high_eq4[1]) && high_lt4[0]);
			high_signed_lt = (lhs[31] != rhs[31] ? lhs[31] : high_unsigned_lt);
			high_equal = &high_eq4;
			high_lt = (kind[1] ? high_unsigned_lt : high_signed_lt);
			ordered = high_lt || (high_equal && lower_lt);
			branch_half_direction = (((kind == 0) && all_equal) || ((kind == 1) && !all_equal)) || (kind[2] && (ordered ^ kind[0]));
		end
	endfunction
	wire mtaken = mcontrol && (!mconditional || mbranch_taken);
	wire [31:0] mtarget = mtarget_base;
	wire [31:0] mnext = (mtaken ? mtarget : m_fall_q);
	wire mpred_wrong = !mfault && (mtaken ? m_wrong_taken_q : m_wrong_nt_q);
	assign mv1 = mv1_raw_q && (!mcontrol || (mbranch_taken ? m_tgt_eq1_q : m_ft_eq1_q));
	wire mcontrol_misaligned = ((mv && mcontrol) && mtaken) && |mtarget[1:0];
	wire m_bad = ((mfault || mcontrol_misaligned) || (m_response && d_rsp_error)) || (mcsr && csr_error);
	wire control_commit = ((mv && mcontrol) && !mfault) && !mcontrol_misaligned;
	wire [31:0] m_final_cause = (mfault ? mcause : (mcontrol_misaligned ? 32'd0 : (mcsr && csr_error ? 32'd2 : (mwrite ? 32'd7 : 32'd5))));
	wire [31:0] m_final_tval = (mfault ? mtval : (mcontrol_misaligned ? mtarget : (mcsr && csr_error ? mi : maddr)));
	wire irq_wait = (MACHINE_MODE != 0) && irq_eligible;
	wire terminal_commit = (((m_done && !m_bad) && mmem) && mwrite) && d_rsp_terminal;
	wire m1_taken = m1_branch_q && (mi1[14] ? m1_order_direction : m1_decision_q);
	wire m1_mispredict = (m1_taken ? m1_wrong_taken_q : m1_wrong_nt_q);
	wire slot1_branch_sel = mv1_raw_q && m1_branch_q;
	wire slot1_branch_commit = ((mv && slot1_branch_sel) && !mfault) && (!mmem || ((m_response && !d_rsp_error) && (!mwrite || !d_rsp_terminal)));
	wire m1_redirect_raw = slot1_branch_sel && m1_mispredict;
	wire m_redirect0 = (m_done && !m_bad) && mpred_wrong;
	wire m_redirect1 = ((m_done && !m_bad) && !terminal_commit) && m1_redirect_raw;
	wire m_redirect = m_redirect0 || m_redirect1;
	wire fast_ctl = ((mv && mcontrol) && !mcontrol_misaligned) && mpred_wrong;
	reg m_fast_s1_nonmem_q;
	wire fast_s1 = ((mv && mv1_raw_q) && m_fast_s1_nonmem_q) && m1_mispredict;
	wire fast_redirect = (MACHINE_MODE != 0) && (fast_ctl || fast_s1);
	(* syn_keep = 1 *) wire fast_target_s1 = mv1_raw_q && m_fast_s1_nonmem_q;
	wire [31:0] fast_pc = (fast_target_s1 ? (m1_taken ? mtarget1 : m1_fall_q) : (mtaken ? mtarget_base : m_fall_q));
	wire [31:0] fast_pc4 = (fast_target_s1 ? (m1_taken ? m1_tgt4_q : m1_fall4_q) : (mtaken ? m_tgt4_q : m_fall4_q));
	wire [31:0] fast_pc8 = (fast_target_s1 ? (m1_taken ? m1_tgt8_q : m1_fall8_q) : (mtaken ? m_tgt8_q : m_fall8_q));
	wire m_redirect_ctl = (m_done && !m_bad) && (mpred_wrong || m1_redirect_raw);
	wire irq_take = ((((irq_wait && !mv) && !halted) && !fatal_error) && !terminal_stopped) && !run_stop;
	wire mret_commit = (m_done && !m_bad) && mmret;
	wire exception_enter = (m_done && m_bad) && (MACHINE_MODE != 0);
	wire perf_known;
	wire [31:0] perf_rdata;
	p2_csr csrs(
		.clk(clk),
		.rst(rst),
		.access_valid(mv && mcsr),
		.access_addr(mi[31:20]),
		.access_write(csr_write),
		.access_wdata(csr_wdata),
		.access_commit(m_done && !m_bad),
		.perf_known(perf_known),
		.perf_rdata(perf_rdata),
		.access_rdata(csr_rdata),
		.access_modify_rdata(csr_modify_rdata),
		.access_error(csr_error_reference),
		.retire(m_done && !m_bad),
		.retire_second(((m_done && !m_bad) && mv1) && !terminal_commit),
		.trap_enter(exception_enter || irq_take),
		.trap_pc((irq_take ? commit_next_pc : mp)),
		.trap_cause((irq_take ? irq_cause : m_final_cause)),
		.trap_tval((irq_take ? 32'b00000000000000000000000000000000 : m_final_tval)),
		.mret_commit(mret_commit),
		.irq_software(irq_software),
		.irq_timer(irq_timer),
		.irq_external(irq_external),
		.irq_eligible(irq_eligible),
		.irq_cause(irq_cause),
		.handler_pc(handler_pc),
		.return_pc(return_pc),
		.machine_cycle(machine_cycle),
		.machine_retired(machine_retired)
	);
	function automatic [12:0] load_format_decode;
		input [1:0] off;
		input [2:0] kind;
		reg byte_kind;
		reg half_kind;
		reg word_kind;
		integer lane;
		begin
			byte_kind = (kind == 3'd0) || (kind == 3'd4);
			half_kind = (kind == 3'd1) || (kind == 3'd5);
			word_kind = kind == 3'd2;
			load_format_decode = 13'b0000000000000;
			for (lane = 0; lane < 4; lane = lane + 1)
				begin
					load_format_decode[lane] = byte_kind && (off == lane);
					load_format_decode[7 + lane] = (kind == 3'd0) && (off == lane);
				end
			load_format_decode[0] = (load_format_decode[0] || (half_kind && !off[1])) || word_kind;
			load_format_decode[2] = load_format_decode[2] || (half_kind && off[1]);
			load_format_decode[4] = (half_kind && !off[1]) || word_kind;
			load_format_decode[5] = half_kind && off[1];
			load_format_decode[6] = word_kind;
			load_format_decode[11] = (kind == 3'd1) && !off[1];
			load_format_decode[12] = (kind == 3'd1) && off[1];
		end
	endfunction
	reg [12:0] mload_format_q;
	wire [31:0] load_value;
	p2_load_format_predecoded load_align_predecoded(
		.data(d_rsp_data),
		.selectors(mload_format_q),
		.result(load_value)
	);
	function automatic integer_alu_encoding;
		input [31:0] insn;
		integer_alu_encoding = ((insn[6:0] == 7'h13) && ((((insn[14:12] != 1) && (insn[14:12] != 5)) || ((insn[14:12] == 1) && (insn[31:25] == 0))) || ((insn[14:12] == 5) && ((insn[31:25] == 0) || (insn[31:25] == 7'h20))))) || ((insn[6:0] == 7'h33) && ((insn[31:25] == 0) || ((insn[31:25] == 7'h20) && ((insn[14:12] == 0) || (insn[14:12] == 5)))));
	endfunction
	function automatic [31:0] integer_alu;
		input [31:0] insn;
		input [31:0] lhs;
		input [31:0] rhs;
		reg [31:0] right_value;
		reg [31:0] shift_in;
		reg [31:0] shift_out;
		reg [31:0] shift_result;
		reg signed [32:0] signed_shift;
		reg [4:0] amount;
		reg is_sub;
		reg left_shift;
		reg arith_shift;
		integer k;
		begin
			right_value = (insn[6:0] == 7'h13 ? {{20 {insn[31]}}, insn[31:20]} : rhs);
			is_sub = (insn[6:0] == 7'h33) && insn[30];
			amount = right_value[4:0];
			left_shift = insn[14:12] == 1;
			arith_shift = (insn[14:12] == 5) && insn[30];
			for (k = 0; k < 32; k = k + 1)
				shift_in[k] = (left_shift ? lhs[31 - k] : lhs[k]);
			signed_shift = {arith_shift && shift_in[31], shift_in};
			shift_out = signed_shift >>> amount;
			for (k = 0; k < 32; k = k + 1)
				shift_result[k] = (left_shift ? shift_out[31 - k] : shift_out[k]);
			case (insn[14:12])
				0: integer_alu = (lhs + (is_sub ? ~right_value : right_value)) + is_sub;
				1, 5: integer_alu = shift_result;
				2: integer_alu = {31'b0000000000000000000000000000000, $signed(lhs) < $signed(right_value)};
				3: integer_alu = {31'b0000000000000000000000000000000, lhs < right_value};
				4: integer_alu = lhs ^ right_value;
				6: integer_alu = lhs | right_value;
				7: integer_alu = lhs & right_value;
				default: integer_alu = 0;
			endcase
		end
	endfunction
	function automatic [31:0] late_integer_alu;
		input [2:0] operation;
		input [31:0] lhs;
		input [31:0] right_value;
		input is_sub;
		input left_shift;
		input arith_shift;
		reg [31:0] shift_in;
		reg [31:0] shift_out;
		reg [31:0] shift_result;
		reg signed [32:0] signed_shift;
		integer k;
		begin
			for (k = 0; k < 32; k = k + 1)
				shift_in[k] = (left_shift ? lhs[31 - k] : lhs[k]);
			signed_shift = {arith_shift && shift_in[31], shift_in};
			shift_out = signed_shift >>> right_value[4:0];
			for (k = 0; k < 32; k = k + 1)
				shift_result[k] = (left_shift ? shift_out[31 - k] : shift_out[k]);
			case (operation)
				0: late_integer_alu = (lhs + (is_sub ? ~right_value : right_value)) + is_sub;
				1, 5: late_integer_alu = shift_result;
				2: late_integer_alu = {31'b0000000000000000000000000000000, $signed(lhs) < $signed(right_value)};
				3: late_integer_alu = {31'b0000000000000000000000000000000, lhs < right_value};
				4: late_integer_alu = lhs ^ right_value;
				6: late_integer_alu = lhs | right_value;
				7: late_integer_alu = lhs & right_value;
				default: late_integer_alu = 0;
			endcase
		end
	endfunction
	function automatic [31:0] selected_integer_alu;
		input [2:0] operation;
		input [31:0] lhs;
		input [31:0] right_value;
		input [31:0] arithmetic_result;
		input is_sub;
		input left_shift;
		input arith_shift;
		reg [31:0] shift_in;
		reg [31:0] shift_out;
		reg [31:0] shift_result;
		reg signed [32:0] signed_shift;
		integer k;
		begin
			for (k = 0; k < 32; k = k + 1)
				shift_in[k] = (left_shift ? lhs[31 - k] : lhs[k]);
			signed_shift = {arith_shift && shift_in[31], shift_in};
			shift_out = signed_shift >>> right_value[4:0];
			for (k = 0; k < 32; k = k + 1)
				shift_result[k] = (left_shift ? shift_out[31 - k] : shift_out[k]);
			case (operation)
				0: selected_integer_alu = arithmetic_result;
				1, 5: selected_integer_alu = shift_result;
				2: selected_integer_alu = {31'b0000000000000000000000000000000, $signed(lhs) < $signed(right_value)};
				3: selected_integer_alu = {31'b0000000000000000000000000000000, lhs < right_value};
				4: selected_integer_alu = lhs ^ right_value;
				6: selected_integer_alu = lhs | right_value;
				7: selected_integer_alu = lhs & right_value;
				default: selected_integer_alu = 0;
			endcase
		end
	endfunction
	function automatic [31:0] parallel_integer_alu;
		input [2:0] operation;
		input [31:0] lhs;
		input [31:0] right_value;
		input [31:0] arithmetic_result;
		input is_sub;
		input left_shift;
		input arith_shift;
		reg [31:0] reverse_lhs;
		reg [31:0] left_out;
		reg [31:0] right_out;
		reg [31:0] left_result;
		reg signed [32:0] signed_left;
		reg signed [32:0] signed_right;
		reg choose_shift;
		reg choose_left;
		reg choose_right;
		integer k;
		begin
			for (k = 0; k < 32; k = k + 1)
				reverse_lhs[k] = lhs[31 - k];
			signed_left = {arith_shift && lhs[0], reverse_lhs};
			signed_right = {arith_shift && lhs[31], lhs};
			left_out = signed_left >>> right_value[4:0];
			right_out = signed_right >>> right_value[4:0];
			for (k = 0; k < 32; k = k + 1)
				left_result[k] = left_out[31 - k];
			choose_shift = (operation == 1) || (operation == 5);
			choose_left = choose_shift && left_shift;
			choose_right = choose_shift && !left_shift;
			parallel_integer_alu = ((((((({32 {operation == 0}} & arithmetic_result) | ({32 {choose_left}} & left_result)) | ({32 {choose_right}} & right_out)) | ({32 {operation == 2}} & {31'b0000000000000000000000000000000, $signed(lhs) < $signed(right_value)})) | ({32 {operation == 3}} & {31'b0000000000000000000000000000000, lhs < right_value})) | ({32 {operation == 4}} & (lhs ^ right_value))) | ({32 {operation == 6}} & (lhs | right_value))) | ({32 {operation == 7}} & (lhs & right_value));
		end
	endfunction
	(* syn_keep = 1 *) wire [31:0] late_arithmetic0 = (mbranch_a + (mlate_sub0 ? ~mbranch_b : mbranch_b)) + mlate_sub0;
	(* syn_keep = 1 *) wire [31:0] late_arithmetic1 = (mresult1_payload + (mlate_sub1 ? ~mlate_b1 : mlate_b1)) + mlate_sub1;
	wire [31:0] m_alu_nonmul = (mlate0 ? selected_integer_alu(mi[14:12], mbranch_a, mbranch_b, late_arithmetic0, mlate_sub0, mlate_left0, mlate_arith0) : mresult);
	wire [31:0] m_alu_value = (mmul_pipe_q ? mul_result : m_alu_nonmul);
	wire [31:0] mresult1_nonmul = (mlate1 ? selected_integer_alu(mi1[14:12], mresult1_payload, mlate_b1, late_arithmetic1, mlate_sub1, mlate_left1, mlate_arith1) : mresult1_payload);
	wire [31:0] mresult1 = (mmul1_live_q ? mul_result : mresult1_nonmul);
	wire [31:0] m_value = (mcsr ? (csr_read ? csr_rdata : 32'b00000000000000000000000000000000) : (mmem && !mwrite ? load_value : m_alu_value));
	wire [31:0] m_execute_value = (mmem && !mwrite ? load_value : m_alu_value);
	reg e_const_a1_q;
	reg e_const_b1_q;
	wire [4:0] rs1_1 = (e_const_a1_q ? 5'b00000 : ei1[19:15]);
	wire [4:0] rs2_1 = (e_const_b1_q ? 5'b00000 : ei1[24:20]);
	wire m0_rs1 = mr_nonzero_q && hit0_rs1_q;
	wire m0_rs2 = mr_nonzero_q && hit0_rs2_q;
	wire m0_rs1_1 = mr_nonzero_q && hit0_rs1_1_q;
	wire m0_rs2_1 = mr_nonzero_q && hit0_rs2_1_q;
	wire m1_rs1 = mr1_nonzero_q && hit1_rs1_q;
	wire m1_rs2 = mr1_nonzero_q && hit1_rs2_q;
	wire m1_rs1_1 = mr1_nonzero_q && hit1_rs1_1_q;
	wire m1_rs2_1 = mr1_nonzero_q && hit1_rs2_1_q;
	reg [31:0] rf_a_local_q;
	reg [31:0] rf_b_local_q;
	reg [31:0] rf_a1_local_q;
	reg [31:0] rf_b1_local_q;
	(* syn_maxfan = 8 *) reg [2:0] rf_a_source_q;
	(* syn_maxfan = 8 *) reg [2:0] rf_b_source_q;
	(* syn_maxfan = 8 *) reg [2:0] rf_a1_source_q;
	(* syn_maxfan = 8 *) reg [2:0] rf_b1_source_q;
	wire [31:0] rf_a_q = rf_a_local_q;
	wire [31:0] rf_b_q = rf_b_local_q;
	wire [31:0] rf_a1_q = rf_a1_local_q;
	wire [31:0] rf_b1_q = rf_b1_local_q;
	wire rf_write0 = (m_done && !m_bad) && mr_nonzero_q;
	wire rf_write1 = (((m_done && !m_bad) && mv1) && !terminal_commit) && mr1_nonzero_q;
	function automatic [31:0] read_decode_rf;
		input [4:0] index;
		read_decode_rf = ((index == 0) || !rf_valid_q[index] ? 32'b00000000000000000000000000000000 : (rf_wb1_valid_q && (rf_wb1_rd_q == index) ? rf_wb1_data_q : (rf_wb0_valid_q && (rf_wb0_rd_q == index) ? rf_wb0_data_q : (rf_owner_q[index] ? rf_bank1[index] : rf_bank0[index]))));
	endfunction
	always @(posedge clk)
		if (rst) begin
			rf_wb0_valid_q <= 0;
			rf_wb1_valid_q <= 0;
			rf_wb0_rd_q <= 0;
			rf_wb1_rd_q <= 0;
			rf_wb0_data_q <= 0;
			rf_wb1_data_q <= 0;
		end
		else begin
			rf_wb0_valid_q <= rf_write0;
			rf_wb1_valid_q <= rf_write1;
			rf_wb0_rd_q <= mr;
			rf_wb1_rd_q <= mr1;
			rf_wb0_data_q <= m_value;
			rf_wb1_data_q <= mresult1;
		end
	always @(posedge clk)
		if (!rst && rf_wb0_valid_q)
			rf_bank0[rf_wb0_rd_q] <= rf_wb0_data_q;
	always @(posedge clk)
		if (!rst && rf_wb1_valid_q)
			rf_bank1[rf_wb1_rd_q] <= rf_wb1_data_q;
	always @(posedge clk)
		if (rst) begin
			rf_valid_q <= 0;
			rf_owner_q <= 0;
		end
		else begin
			if (rf_write0) begin
				rf_valid_q[mr] <= 1;
				rf_owner_q[mr] <= 0;
			end
			if (rf_write1) begin
				rf_valid_q[mr1] <= 1;
				rf_owner_q[mr1] <= 1;
			end
		end
	wire operand_m1_forward = (mv && mv1_exec) && ((MACHINE_MODE != 0) || !terminal_commit);
	wire operand_m0_load = (mv && mmem) && !mwrite;
	wire a_live_load = (operand_m0_load && m0_rs1) && !(operand_m1_forward && m1_rs1);
	wire b_live_load = (operand_m0_load && m0_rs2) && !(operand_m1_forward && m1_rs2);
	wire a1_live_load = ((operand_m0_load && m0_rs1_1) && !(operand_m1_forward && m1_rs1_1)) && !e_lui_pair;
	wire b1_live_load = (operand_m0_load && m0_rs2_1) && !(operand_m1_forward && m1_rs2_1);
	(* syn_keep = 1 *) wire [31:0] a_nonload = (operand_m1_forward && m1_rs1 ? mresult1 : (mv && m0_rs1 ? m_alu_value : rf_a_q));
	(* syn_keep = 1 *) wire [31:0] b_nonload = (operand_m1_forward && m1_rs2 ? mresult1 : (mv && m0_rs2 ? m_alu_value : rf_b_q));
	(* syn_keep = 1 *) wire [31:0] a1_nonload = (e_lui_pair ? imm_u : (operand_m1_forward && m1_rs1_1 ? mresult1 : (mv && m0_rs1_1 ? m_alu_value : rf_a1_q)));
	(* syn_keep = 1 *) wire [31:0] b1_nonload = (operand_m1_forward && m1_rs2_1 ? mresult1 : (mv && m0_rs2_1 ? m_alu_value : rf_b1_q));
	reg [31:0] a;
	reg [31:0] b;
	reg [31:0] a1;
	reg [31:0] b1;
	always @(*) begin
		a = (a_live_load ? load_value : a_nonload);
		b = (b_live_load ? load_value : b_nonload);
		a1 = (a1_live_load ? load_value : a1_nonload);
		b1 = (b1_live_load ? load_value : b1_nonload);
	end
	function automatic source_is_slow;
		input valid0;
		input valid1;
		input hit0;
		input hit1;
		input dep0;
		input dep1;
		input terminal;
		begin
			source_is_slow = 0;
			if (valid0) begin
				if ((valid1 && hit1) && ((MACHINE_MODE != 0) || !terminal))
					source_is_slow = dep1;
				else if (hit0)
					source_is_slow = dep0;
			end
		end
	endfunction
	wire e_integer0 = integer_alu_encoding(ei);
	wire e_integer1 = integer_alu_encoding(ei1);
	wire e_late0_ref = ((ev && !ee) && e_integer0) && (source_is_slow(mv, mv1_exec, m0_rs1, m1_rs1, (mmem && !mwrite) || mlate0, mlate1, terminal_commit) || ((op == 7'h33) && source_is_slow(mv, mv1_exec, m0_rs2, m1_rs2, (mmem && !mwrite) || mlate0, mlate1, terminal_commit)));
	wire e_late1_ref = e_late1_enable_q && (source_is_slow(mv, mv1_exec, m0_rs1_1, m1_rs1_1, 1'b1, 1'b1, terminal_commit) || ((ei1[6:0] == 7'h33) && source_is_slow(mv, mv1_exec, m0_rs2_1, m1_rs2_1, 1'b1, 1'b1, terminal_commit)));
	wire e_late0 = (MACHINE_MODE != 0 ? (((ev && !ee) && e_integer0) && mv) && (slowL_q[0] || ((op == 7'h33) && slowL_q[1])) : e_late0_ref);
	wire e_late1 = (MACHINE_MODE != 0 ? (e_late1_enable_q && mv) && (any_q[2] || ((ei1[6:0] == 7'h33) && any_q[3])) : e_late1_ref);
	reg [1:0] early_fwd0_q;
	reg [1:0] early_fwd1_q;
	wire early_fwd0_a = (MACHINE_MODE != 0 ? early_fwd0_q[0] : ((!mmem || mwrite) && !mlate0) && m0_rs1);
	wire early_fwd0_b = (MACHINE_MODE != 0 ? early_fwd0_q[1] : ((!mmem || mwrite) && !mlate0) && m0_rs2);
	wire early_fwd1_a = (MACHINE_MODE != 0 ? early_fwd1_q[0] : ((mv1_exec && !mlate1) && !terminal_commit) && m1_rs1);
	wire early_fwd1_b = (MACHINE_MODE != 0 ? early_fwd1_q[1] : ((mv1_exec && !mlate1) && !terminal_commit) && m1_rs2);
	reg [31:0] early_a;
	reg [31:0] early_b;
	reg [31:0] early_a1;
	reg [31:0] early_b1;
	always @(*) begin
		early_a = rf_a_q;
		early_b = rf_b_q;
		early_a1 = rf_a1_q;
		early_b1 = rf_b1_q;
		if (mv) begin
			if (early_fwd0_a)
				early_a = mresult;
			if (early_fwd0_b)
				early_b = mresult;
			if (early_fwd1_a)
				early_a = mresult1_payload;
			if (early_fwd1_b)
				early_b = mresult1_payload;
		end
		if (e_lui_pair)
			early_a1 = imm_u;
	end
	wire [31:0] early_right0 = (e_alu_imm0_q ? {{20 {ei[31]}}, ei[31:20]} : early_b);
	wire [31:0] early_right1 = (e_alu_imm1_q ? {{20 {ei1[31]}}, ei1[31:20]} : early_b1);
	(* syn_keep = 1 *) wire [31:0] early_arithmetic0 = (early_a + (e_alu_sub0_q ? ~early_right0 : early_right0)) + e_alu_sub0_q;
	(* syn_keep = 1 *) wire [31:0] early_arithmetic1 = (early_a1 + (e_alu_sub1_q ? ~early_right1 : early_right1)) + e_alu_sub1_q;
	wire [31:0] early_alu0 = parallel_integer_alu(ei[14:12], early_a, early_right0, early_arithmetic0, e_alu_sub0_q, e_alu_left0_q, e_alu_arith0_q);
	wire [31:0] early_alu1_raw = parallel_integer_alu(ei1[14:12], early_a1, early_right1, early_arithmetic1, e_alu_sub1_q, e_alu_left1_q, e_alu_arith1_q);
	wire [31:0] early_alu1 = (e_bitfusion ? bitfusion_result(e_bitfusion_q, early_a, early_b) : early_alu1_raw);
	wire e_is_mul = (((HW_MUL != 0) && (op == 7'h33)) && (f7 == 7'h01)) && !f3[2];
	wire e_is_zbc = (((HW_MUL != 0) && (op == 7'h33)) && (f7 == 7'h05)) && (((f3 == 3'd1) || (f3 == 3'd2)) || (f3 == 3'd3));
	wire mul_raw_primary_dependency = mv && (m0_rs1 || m0_rs2);
	wire mul_raw_slot1_dependency = (mv && mv1_exec) && (m1_rs1 || m1_rs2);
	wire mul_raw_dependency_ref = ((ev && !ee) && e_is_mul) && (mul_raw_primary_dependency || mul_raw_slot1_dependency);
	wire mul_raw_dependency = (MACHINE_MODE != 0 ? (((ev && !ee) && e_is_mul) && mv) && (any_q[0] || any_q[1]) : mul_raw_dependency_ref);
	reg [31:0] mul_a_decode_q;
	reg [31:0] mul_b_decode_q;
	reg [31:0] mul_a_held_q;
	reg [31:0] mul_b_held_q;
	reg mul_payload_q;
	reg mul_a_decode_stale_q;
	reg mul_b_decode_stale_q;
	reg mul_a_held_stale_q;
	reg mul_b_held_stale_q;
	wire [31:0] mul_a_q = (mul_payload_q ? mul_a_decode_q : mul_a_held_q);
	wire [31:0] mul_b_q = (mul_payload_q ? mul_b_decode_q : mul_b_held_q);
	wire mul_a_stale_q = (mul_payload_q ? mul_a_decode_stale_q : mul_a_held_stale_q);
	wire mul_b_stale_q = (mul_payload_q ? mul_b_decode_stale_q : mul_b_held_stale_q);
	wire mul_stale_hold = ((ev && !ee) && e_is_mul) && (mul_a_stale_q || mul_b_stale_q);
	wire [31:0] mul_a = mul_a_q;
	wire [31:0] mul_b = mul_b_q;
	wire zbc_raw_dependency = ((ev && !ee) && e_is_zbc) && (MACHINE_MODE != 0 ? mv && (any_q[0] || any_q[1]) : mul_raw_primary_dependency || mul_raw_slot1_dependency);
	wire zbc_stale_hold = ((ev && !ee) && e_is_zbc) && (mul_a_stale_q || mul_b_stale_q);
	wire zbc_ready;
	wire [31:0] zbc_result;
	wire zbc_take = (((ev && !ee) && e_is_zbc) && !zbc_raw_dependency) && !zbc_stale_hold;
	wire zbc_hold = ((ev && !ee) && e_is_zbc) && ((!zbc_ready || zbc_raw_dependency) || zbc_stale_hold);
	wire e_lsu_encoding = ((op == 7'h03) && (((((f3 == 0) || (f3 == 1)) || (f3 == 2)) || (f3 == 4)) || (f3 == 5))) || ((op == 7'h23) && (((f3 == 0) || (f3 == 1)) || (f3 == 2)));
	wire agu_late_dependency_ref = ((ev && !ee) && (e_lsu_encoding || ((op == 7'h67) && (f3 == 0)))) && source_is_slow(mv, mv1_exec, m0_rs1, m1_rs1, mlate0, mlate1, terminal_commit);
	wire agu_late_dependency = (MACHINE_MODE != 0 ? (((ev && !ee) && (e_lsu_encoding || ((op == 7'h67) && (f3 == 0)))) && mv) && late_q : agu_late_dependency_ref);
	wire agu_base_load_dependency_ref = (((mv && ((mmem && !mwrite) || mmul_pipe_q)) && m0_rs1) && !(mv1_exec && m1_rs1)) || (((mv && mv1_exec) && m1_rs1) && mmul1_live_q);
	wire agu_base_load_dependency = (MACHINE_MODE != 0 ? mv && ld_q[0] : agu_base_load_dependency_ref);
	wire agu_store_load_dependency_ref = (((mv && ((mmem && !mwrite) || mmul_pipe_q)) && m0_rs2) && !(mv1_exec && m1_rs2)) || (((mv && mv1_exec) && m1_rs2) && mmul1_live_q);
	wire agu_store_load_dependency = (MACHINE_MODE != 0 ? mv && ld_q[1] : agu_store_load_dependency_ref);
	wire agu_load_dependency = ((ev && !ee) && e_lsu_encoding) && (agu_base_load_dependency || ((op == 7'h23) && agu_store_load_dependency));
	wire bitfusion_slow_hold = e_bitfusion && e_late0;
	wire branch_bitwise0 = ((mi[14:12] == 4) || (mi[14:12] == 6)) || (mi[14:12] == 7);
	wire branch_word_load = (mmem && !mwrite) && (mfunct3 == 3'd2);
	wire branch_slow0 = ((mmem && !mwrite) && !branch_word_load) || (mlate0 && !branch_bitwise0);
	wire branch_bitwise1 = ((mi1[14:12] == 4) || (mi1[14:12] == 6)) || (mi1[14:12] == 7);
	wire branch_slow1 = mlate1 && !branch_bitwise1;
	wire branch_subword_load = (mmem && !mwrite) && (mfunct3 != 3'd2);
	wire branch0_slow_hold = ((ev && !ee) && (op == 7'h63)) && (source_is_slow(mv, mv1_exec, m0_rs1, m1_rs1, branch_slow0 && !(!f3[2] && branch_subword_load), branch_slow1, terminal_commit) || source_is_slow(mv, mv1_exec, m0_rs2, m1_rs2, branch_slow0 && !(!f3[2] && branch_subword_load), branch_slow1, terminal_commit));
	wire [2:0] f3_1 = ei1[14:12];
	wire [6:0] op1 = ei1[6:0];
	wire branch1_slow_hold = ((ev1 && !ee1) && (op1 == 7'h63)) && (source_is_slow(mv, mv1_exec, m0_rs1_1, m1_rs1_1, branch_slow0 && !(!f3_1[2] && branch_subword_load), branch_slow1, terminal_commit) || source_is_slow(mv, mv1_exec, m0_rs2_1, m1_rs2_1, branch_slow0 && !(!f3_1[2] && branch_subword_load), branch_slow1, terminal_commit));
	wire jalr_load_dependency = (((ev && !ee) && (op == 7'h67)) && (f3 == 0)) && agu_base_load_dependency;
	wire m_terminal_pending = ((mv && mmem) && mwrite) && d_rsp_terminal;
	wire e_is_mul1 = (((((HW_MUL != 0) && ev1) && !ee1) && (ei1[6:0] == 7'h33)) && (ei1[31:25] == 7'h01)) && (ei1[14:12] == 0);
	wire mul1_raw_dependency = e_is_mul1 && (source_is_slow(mv, mv1_exec, m0_rs1_1, m1_rs1_1, 1'b1, 1'b1, terminal_commit) || source_is_slow(mv, mv1_exec, m0_rs2_1, m1_rs2_1, 1'b1, 1'b1, terminal_commit));
	reg mul1_ready;
	wire mul1_hold = e_is_mul1 && (((MACHINE_MODE == 0) && !mul1_ready) || mul1_raw_dependency);
	wire e_mul_high = e_is_mul && (f3[1:0] != 0);
	reg [2:0] mulh_state;
	wire mul_high_hold = ((ev && !ee) && e_mul_high) && (mulh_state != 3'd4);
	reg mul_low_ready;
	wire mul_low_hold = (((((MACHINE_MODE == 0) && ev) && !ee) && e_is_mul) && !e_mul_high) && !mul_low_ready;
	wire serial_m = mv && ((mcsr || mmret) || mfencei);
	wire e_fire = (((((((((((((((((((((ev && !zbc_hold) && !mul1_hold) && !branch0_slow_hold) && !branch1_slow_hold) && !mul_low_hold) && !mul_high_hold) && !bitfusion_slow_hold) && !mul_raw_dependency) && !mul_stale_hold) && !agu_load_dependency) && !jalr_load_dependency) && !agu_late_dependency) && (!mv || m_done)) && !(m_done && m_bad)) && !m_redirect_ctl) && !halted) && !serial_m) && !irq_wait) && !fatal_error) && !run_stop) && !m_terminal_pending) && !terminal_stopped;
	reg fault;
	wire e_kill = (e_fire && fault) && (MACHINE_MODE == 0);
	wire m_kill = m_done && m_bad;
	wire maintenance_commit = (m_done && !m_bad) && mfencei;
	wire kill = (((((m_kill || m_redirect_ctl) || e_kill) || irq_take) || mret_commit) || maintenance_commit) || terminal_commit;
	p2_clmul_pipeline clmul_pipe(
		.clk(clk),
		.rst(rst),
		.cancel(kill || !ev),
		.take(zbc_take),
		.consume(e_fire),
		.kind(f3),
		.a(mul_a),
		.b(mul_b),
		.ready(zbc_ready),
		.result(zbc_result)
	);
	wire e_mul_pipe = ((MACHINE_MODE != 0) && e_is_mul) && !e_mul_high;
	reg [4:0] mulh_step;
	reg [31:0] mulh_hi;
	reg [31:0] mulh_lo;
	reg [31:0] mulh_a;
	reg [31:0] mulh_b;
	reg mulh_signed_a;
	reg mulh_signed_b;
	wire [32:0] mulh_sum = {1'b0, mulh_hi} + (mulh_lo[0] ? {1'b0, mulh_a} : 33'b000000000000000000000000000000000);
	reg [31:0] agu_a;
	reg [31:0] agu_b;
	always @(*) begin
		agu_a = rf_a_q;
		agu_b = rf_b_q;
		if (mv && (!mmem || mwrite)) begin
			if (!mlate0 && m0_rs1)
				agu_a = mresult;
			if (m0_rs2)
				agu_b = m_alu_value;
		end
		if ((mv && mv1_exec) && ((MACHINE_MODE != 0) || !terminal_commit)) begin
			if (!mlate1 && m1_rs1)
				agu_a = mresult1_payload;
			if (m1_rs2)
				agu_b = mresult1;
		end
	end
	wire store_data_late = source_is_slow(mv, mv1_exec, m0_rs2, m1_rs2, mlate0, mlate1, terminal_commit);
	reg [31:0] early_store_b;
	always @(*) begin
		early_store_b = rf_b_q;
		if (((mv && (!mmem || mwrite)) && !mlate0) && m0_rs2)
			early_store_b = mresult;
		if ((((mv && mv1_exec) && !mlate1) && m1_rs2) && ((MACHINE_MODE != 0) || !terminal_commit))
			early_store_b = mresult1_payload;
	end
	wire e_mul1_pipe = (MACHINE_MODE != 0) && e_is_mul1;
	wire [31:0] mul_shared_a = (e_is_mul1 ? rf_a1_q : mul_a);
	wire [31:0] mul_shared_b = (e_is_mul1 ? rf_b1_q : mul_b);
	wire [31:0] mul_ll = mul_shared_a[15:0] * mul_shared_b[15:0];
	wire [15:0] mul_lh = mul_shared_a[15:0] * mul_shared_b[31:16];
	wire [15:0] mul_hl = mul_shared_a[31:16] * mul_shared_b[15:0];
	reg [31:0] mul_ll_q;
	reg [15:0] mul_lh_q;
	reg [15:0] mul_hl_q;
	always @(posedge clk) begin
		mul_ll_q <= mul_ll;
		mul_lh_q <= mul_lh;
		mul_hl_q <= mul_hl;
	end
	wire [15:0] mul_hi_xor = (mul_ll_q[31:16] ^ mul_lh_q) ^ mul_hl_q;
	wire [15:0] mul_hi_carry = (((mul_ll_q[31:16] & mul_lh_q) | (mul_ll_q[31:16] & mul_hl_q)) | (mul_lh_q & mul_hl_q)) << 1;
	wire [15:0] mul_hi = mul_hi_xor + mul_hi_carry;
	assign mul_result = {mul_hi, mul_ll_q[15:0]};
	function automatic [31:0] agu_add_signed12;
		input [31:0] base_value;
		input [31:0] signed_imm;
		reg [12:0] low_sum;
		reg inc;
		reg dec;
		reg [19:0] prefix_ones;
		reg [19:0] prefix_zeros;
		reg [19:0] upper_result;
		integer bitno;
		begin
			low_sum = {1'b0, base_value[11:0]} + {1'b0, signed_imm[11:0]};
			inc = !signed_imm[31] && low_sum[12];
			dec = signed_imm[31] && !low_sum[12];
			prefix_ones[0] = 1'b1;
			prefix_zeros[0] = 1'b1;
			for (bitno = 1; bitno < 20; bitno = bitno + 1)
				begin
					prefix_ones[bitno] = prefix_ones[bitno - 1] & base_value[bitno + 11];
					prefix_zeros[bitno] = prefix_zeros[bitno - 1] & ~base_value[bitno + 11];
				end
			for (bitno = 0; bitno < 20; bitno = bitno + 1)
				upper_result[bitno] = base_value[bitno + 12] ^ ((inc & prefix_ones[bitno]) | (dec & prefix_zeros[bitno]));
			agu_add_signed12 = {upper_result, low_sum[11:0]};
		end
	endfunction
	(* syn_keep = 1 *) wire [31:0] auipc_value0 = ep + imm_u;
	(* syn_keep = 1 *) wire [31:0] link_value0 = ep + 32'd4;
	wire er0_mul = (op == 7'h33) && e_is_mul;
	wire er0_integer = (op == 7'h13) || (((op == 7'h33) && !e_is_mul) && !e_is_zbc);
	wire [31:0] er = (((((({32 {op == 7'h37}} & imm_u) | ({32 {op == 7'h17}} & auipc_value0)) | ({32 {(op == 7'h6f) || (op == 7'h67)}} & link_value0)) | ({32 {er0_integer}} & early_alu0)) | ({32 {er0_mul && !e_mul_high}} & mul_result)) | ({32 {er0_mul && e_mul_high}} & mulh_hi)) | ({32 {e_is_zbc}} & zbc_result);
	reg [1:0] d_target_kind;
	reg [1:0] e_target_kind_q;
	reg [31:0] d_pc_target_imm;
	reg [31:0] e_pc_target_imm_q;
	always @(*) begin
		d_target_kind = 0;
		d_pc_target_imm = 0;
		case (di[6:0])
			7'h6f: begin
				d_target_kind = 1;
				d_pc_target_imm = {{11 {di[31]}}, di[31], di[19:12], di[20], di[30:21], 1'b0};
			end
			7'h63: begin
				d_target_kind = 1;
				d_pc_target_imm = {{19 {di[31]}}, di[31], di[7], di[30:25], di[11:8], 1'b0};
			end
			7'h67: d_target_kind = 2;
			default:
				;
		endcase
	end
	(* syn_keep = 1 *) wire [31:0] pc_target_sum = ep + e_pc_target_imm_q;
	reg [31:0] target;
	always @(*) begin
		target = 0;
		case (e_target_kind_q)
			1: target = pc_target_sum;
			2: target = (agu_a + imm_i) & 32'hfffffffe;
			default:
				;
		endcase
	end
	reg [31:0] ea;
	reg [31:0] ew;
	reg [31:0] ecause;
	reg [31:0] etval;
	reg [4:0] rd;
	reg [3:0] be;
	reg mem;
	reg wr;
	reg legal;
	reg use1;
	reg use2;
	reg csr;
	reg mret;
	reg fencei;
	reg control;
	reg conditional;
	always @(*) begin
		ea = 0;
		ew = 0;
		ecause = 2;
		etval = ei;
		rd = ei[11:7];
		be = 0;
		mem = 0;
		wr = 0;
		fault = 0;
		legal = 1;
		use1 = 0;
		use2 = 0;
		csr = 0;
		mret = 0;
		fencei = 0;
		control = 0;
		conditional = 0;
		case (op)
			7'h37:
				;
			7'h17:
				;
			7'h6f:
				;
			7'h67: begin
				use1 = 1;
				if (f3 != 0)
					legal = 0;
			end
			7'h63: begin
				use1 = 1;
				use2 = 1;
				rd = 0;
				case (f3)
					0, 1, 4, 5, 6, 7: legal = 1;
					default: legal = 0;
				endcase
			end
			7'h03, 7'h23: begin
				use1 = 1;
				use2 = op == 7'h23;
				mem = 1;
				wr = op == 7'h23;
				ea = agu_add_signed12(agu_a, e_lsu_imm);
				ew = agu_b << {ea[1:0], 3'b000};
				if (wr)
					rd = 0;
				case (f3)
					0: be = 4'b0001 << ea[1:0];
					1: be = 4'b0011 << ea[1:0];
					2: be = 4'b1111;
					4: begin
						be = 4'b0001 << ea[1:0];
						if (wr)
							legal = 0;
					end
					5: begin
						be = 4'b0011 << ea[1:0];
						if (wr)
							legal = 0;
					end
					default: legal = 0;
				endcase
				if ((((f3 == 1) || (f3 == 5)) && ea[0]) || ((f3 == 2) && |ea[1:0])) begin
					fault = 1;
					ecause = (wr ? 6 : 4);
					etval = ea;
				end
			end
			7'h13: begin
				use1 = 1;
				if (!integer_alu_encoding(ei))
					legal = 0;
			end
			7'h33: begin
				use1 = 1;
				use2 = 1;
				if ((!e_is_mul && !e_is_zbc) && !integer_alu_encoding(ei))
					legal = 0;
			end
			7'h0f: begin
				rd = 0;
				if ((f3 == 1) && (MACHINE_MODE != 0))
					fencei = 1;
				else if (f3 != 0)
					legal = 0;
			end
			7'h73:
				if ((MACHINE_MODE != 0) && ((((((f3 == 1) || (f3 == 2)) || (f3 == 3)) || (f3 == 5)) || (f3 == 6)) || (f3 == 7))) begin
					csr = 1;
					use1 = !f3[2];
				end
				else begin
					rd = 0;
					etval = 0;
					if (ei == 32'h00000073) begin
						fault = 1;
						ecause = 11;
					end
					else if (ei == 32'h00100073) begin
						fault = 1;
						ecause = 3;
					end
					else if ((ei == 32'h30200073) && (MACHINE_MODE != 0))
						mret = 1;
					else if ((ei != 32'h10500073) || (MACHINE_MODE == 0))
						legal = 0;
				end
			default: legal = 0;
		endcase
		if (!legal) begin
			fault = 1;
			ecause = 2;
			etval = ei;
			mem = 0;
		end
		if (ee) begin
			fault = 1;
			ecause = 1;
			etval = ep;
			mem = 0;
		end
		control = ((op == 7'h63) || (op == 7'h6f)) || (op == 7'h67);
		conditional = op == 7'h63;
		if (fault) begin
			rd = 0;
			csr = 0;
			mret = 0;
			fencei = 0;
			control = 0;
		end
	end
	wire [31:0] target_plus4;
	wire [31:0] target_plus8;
	assign target_plus4[1:0] = target[1:0];
	assign target_plus4[2] = ~target[2];
	assign target_plus8[2:0] = target[2:0];
	assign target_plus8[3] = ~target[3];
	genvar _gv_bit4_1;
	generate
		for (_gv_bit4_1 = 3; _gv_bit4_1 < 32; _gv_bit4_1 = _gv_bit4_1 + 1) begin : target4_prefix
			localparam bit4 = _gv_bit4_1;
			assign target_plus4[bit4] = target[bit4] ^ &target[bit4 - 1:2];
		end
	endgenerate
	genvar _gv_bit8_1;
	generate
		for (_gv_bit8_1 = 4; _gv_bit8_1 < 32; _gv_bit8_1 = _gv_bit8_1 + 1) begin : target8_prefix
			localparam bit8 = _gv_bit8_1;
			assign target_plus8[bit8] = target[bit8] ^ &target[bit8 - 1:3];
		end
	endgenerate
	wire [6:0] f7_1 = ei1[31:25];
	wire [31:0] imm_i1 = {{20 {ei1[31]}}, ei1[31:20]};
	wire [31:0] imm_u1 = {ei1[31:12], 12'b000000000000};
	(* syn_keep = 1 *) wire [31:0] auipc_value1 = ep1 + imm_u1;
	wire er1_mul_sel = e_is_mul1 && (MACHINE_MODE == 0);
	wire er1_integer_sel = !er1_mul_sel && ((op1 == 7'h13) || (op1 == 7'h33));
	wire [31:0] er1 = ((((((({32 {er1_mul_sel}} & mul_result) | ({32 {!er1_mul_sel && (op1 == 7'h37)}} & imm_u1)) | ({32 {!er1_mul_sel && (op1 == 7'h17)}} & auipc_value1)) | ({32 {er1_integer_sel && !(|e_fusion_sel_q)}} & early_alu1_raw)) | ({32 {er1_integer_sel && e_fusion_sel_q[0]}} & {31'b0000000000000000000000000000000, early_a[0] ^ early_b[0]})) | ({32 {er1_integer_sel && e_fusion_sel_q[1]}} & {early_a[15:0] ^ early_b[15:0], 16'b0000000000000000})) | ({32 {er1_integer_sel && e_fusion_sel_q[2]}} & {16'b0000000000000000, early_a[15:0]})) | ({32 {er1_integer_sel && e_fusion_sel_q[3]}} & {{16 {early_a[15]}}, early_a[15:0]});
	wire [6:0] d0op = di[6:0];
	wire [6:0] d1op = di1[6:0];
	wire [2:0] d1f3 = di1[14:12];
	wire [6:0] d1f7 = di1[31:25];
	wire d0_pairable = front_pre0[1];
	wire d1_simple = front_pre1[0];
	wire d1_mul = ((((((MACHINE_MODE != 0) && (HW_MUL != 0)) && (d1op == 7'h33)) && (d1f7 == 7'h01)) && (d1f3 == 0)) && !((d0op == 7'h33) && (di[31:25] == 7'h01))) && !(((d0op == 7'h33) && (di[31:25] == 7'h05)) && (((di[14:12] == 1) || (di[14:12] == 2)) || (di[14:12] == 3)));
	wire d1_use1 = front_pre1[3];
	wire d1_use2 = front_pre1[4];
	wire d1_branch = ((MACHINE_MODE != 0) && front_pre1[5]) && !front_pre0[6];
	wire d0_writes = front_pre0[2];
	wire d_const_branch = (((d1_branch && (d0op == 7'h13)) && (di[14:12] == 0)) && (di[19:15] == 0)) && (di[11:7] != 0);
	wire d_const_a1 = d_const_branch && (di1[19:15] == di[11:7]);
	wire d_const_b1 = d_const_branch && (di1[24:20] == di[11:7]);
	wire [4:0] d_src_a1 = (d_const_a1 ? 5'b00000 : di1[19:15]);
	wire [4:0] d_src_b1 = (d_const_b1 ? 5'b00000 : di1[24:20]);
	wire [31:0] d_const_value = {{20 {di[31]}}, di[31:20]};
	wire d_lui_pair = ((((d0op == 7'h37) && (di[11:7] != 0)) && (d1op == 7'h13)) && (d1f3 == 0)) && (di1[19:15] == di[11:7]);
	wire d_taken_pair = (((MACHINE_MODE != 0) && (d0op == 7'h63)) && !front_sequential) && (d1_simple || d1_mul);
	wire pair_d = (((((((dv1 && !de) && !de1) && d0_pairable) && ((d1_simple || d1_branch) || d1_mul)) && (front_sequential || d_taken_pair)) && (front_sequential1 || d1_branch)) && front_pair_link) && (((d_lui_pair || d_const_branch) || (d_bitfusion != 0)) || !(d0_writes && (((d1_use1 && (di1[19:15] == di[11:7])) || (d1_use2 && (di1[24:20] == di[11:7]))) || (!front_pre1[6] && (di1[11:7] == di[11:7])))));
	function automatic [31:0] branch_bitwise_value;
		input [2:0] kind;
		input [31:0] lhs;
		input [31:0] rhs;
		case (kind)
			4: branch_bitwise_value = lhs ^ rhs;
			6: branch_bitwise_value = lhs | rhs;
			7: branch_bitwise_value = lhs & rhs;
			default: branch_bitwise_value = 0;
		endcase
	endfunction
	wire [31:0] branch_m0_value = (branch_word_load ? d_rsp_data : (mlate0 ? branch_bitwise_value(mi[14:12], mbranch_a, mbranch_b) : mresult));
	wire [31:0] branch_m1_value = (mlate1 ? branch_bitwise_value(mi1[14:12], mresult1_payload, mlate_b1) : mresult1_payload);
	reg [31:0] branch0_a;
	reg [31:0] branch0_b;
	reg [31:0] branch1_a;
	reg [31:0] branch1_b;
	reg [31:0] branch0_a_other;
	reg [31:0] branch0_b_other;
	reg [31:0] branch1_a_other;
	reg [31:0] branch1_b_other;
	reg [3:0] branch_take0;
	reg [3:0] branch_take1;
	wire [31:0] branch_m0_nonword = (mlate0 ? branch_bitwise_value(mi[14:12], mbranch_a, mbranch_b) : mresult);
	wire [3:0] branch_word_take = (branch_take0 & ~branch_take1) & {4 {branch_word_load}};
	always @(*) begin
		branch_take0 = 0;
		branch_take1 = 0;
		branch0_a_other = rf_a_q;
		branch0_b_other = rf_b_q;
		branch1_a_other = rf_a1_q;
		branch1_b_other = rf_b1_q;
		if (mv && !branch_slow0) begin
			if (m0_rs1) begin
				branch_take0[0] = 1;
				branch0_a_other = branch_m0_nonword;
			end
			if (m0_rs2) begin
				branch_take0[1] = 1;
				branch0_b_other = branch_m0_nonword;
			end
			if (m0_rs1_1) begin
				branch_take0[2] = 1;
				branch1_a_other = branch_m0_nonword;
			end
			if (m0_rs2_1) begin
				branch_take0[3] = 1;
				branch1_b_other = branch_m0_nonword;
			end
		end
		if (((mv && mv1_exec) && !branch_slow1) && ((MACHINE_MODE != 0) || !terminal_commit)) begin
			if (m1_rs1) begin
				branch_take1[0] = 1;
				branch0_a_other = branch_m1_value;
			end
			if (m1_rs2) begin
				branch_take1[1] = 1;
				branch0_b_other = branch_m1_value;
			end
			if (m1_rs1_1) begin
				branch_take1[2] = 1;
				branch1_a_other = branch_m1_value;
			end
			if (m1_rs2_1) begin
				branch_take1[3] = 1;
				branch1_b_other = branch_m1_value;
			end
		end
		branch0_a = (branch_word_take[0] ? d_rsp_data : branch0_a_other);
		branch0_b = (branch_word_take[1] ? d_rsp_data : branch0_b_other);
		branch1_a = (branch_word_take[2] ? d_rsp_data : branch1_a_other);
		branch1_b = (branch_word_take[3] ? d_rsp_data : branch1_b_other);
	end
	wire [3:0] branch_eq_load_take;
	assign branch_eq_load_take[0] = source_is_slow(mv, mv1_exec, m0_rs1, m1_rs1, branch_subword_load, 1'b0, terminal_commit);
	assign branch_eq_load_take[1] = source_is_slow(mv, mv1_exec, m0_rs2, m1_rs2, branch_subword_load, 1'b0, terminal_commit);
	assign branch_eq_load_take[2] = source_is_slow(mv, mv1_exec, m0_rs1_1, m1_rs1_1, branch_subword_load, 1'b0, terminal_commit);
	assign branch_eq_load_take[3] = source_is_slow(mv, mv1_exec, m0_rs2_1, m1_rs2_1, branch_subword_load, 1'b0, terminal_commit);
	wire word_equal0;
	wire word_high_lt0;
	wire word_high_eq0;
	wire word_lower_lt0;
	wire word_dir_lt0;
	wire word_dir_ge0;
	wire word_equal1;
	wire word_high_lt1;
	wire word_high_eq1;
	wire word_lower_lt1;
	wire word_dir_lt1;
	wire word_dir_ge1;
	p2_branch_predicate word_predicate0(
		branch0_a_other,
		branch0_b_other,
		d_rsp_data,
		branch_word_take[0],
		branch_word_take[1],
		f3,
		word_equal0,
		word_high_lt0,
		word_high_eq0,
		word_lower_lt0,
		word_dir_lt0,
		word_dir_ge0
	);
	p2_branch_predicate word_predicate1(
		branch1_a_other,
		branch1_b_other,
		d_rsp_data,
		branch_word_take[2],
		branch_word_take[3],
		f3_1,
		word_equal1,
		word_high_lt1,
		word_high_eq1,
		word_lower_lt1,
		word_dir_lt1,
		word_dir_ge1
	);
	wire load_eq_b0;
	wire load_eq_a0;
	wire load_eq_b1;
	wire load_eq_a1;
	p2_subword_eq eq_b0(
		d_rsp_data,
		branch0_b_other,
		maddr[1:0],
		mfunct3,
		load_eq_b0
	);
	p2_subword_eq eq_a0(
		d_rsp_data,
		branch0_a_other,
		maddr[1:0],
		mfunct3,
		load_eq_a0
	);
	p2_subword_eq eq_b1(
		d_rsp_data,
		branch1_b_other,
		maddr[1:0],
		mfunct3,
		load_eq_b1
	);
	p2_subword_eq eq_a1(
		d_rsp_data,
		branch1_a_other,
		maddr[1:0],
		mfunct3,
		load_eq_a1
	);
	wire branch0_equal = (&branch_eq_load_take[1:0] ? 1'b1 : (branch_eq_load_take[0] ? load_eq_b0 : (branch_eq_load_take[1] ? load_eq_a0 : word_equal0)));
	wire branch1_equal = (&branch_eq_load_take[3:2] ? 1'b1 : (branch_eq_load_take[2] ? load_eq_b1 : (branch_eq_load_take[3] ? load_eq_a1 : word_equal1)));
	always @(posedge clk)
		if (rst)
			mcsr_illegal_q <= 0;
		else if (e_fire)
			mcsr_illegal_q <= csr_permission_illegal(ei);
	always @(posedge clk)
		if (((rst || kill) || e_fire) || !ev1)
			mul1_ready <= 0;
		else if (e_is_mul1 && !mul1_raw_dependency)
			mul1_ready <= 1;
	always @(posedge clk)
		if (((rst || kill) || e_fire) || !ev)
			mul_low_ready <= 0;
		else if ((((!ee && e_is_mul) && !e_mul_high) && !mul_raw_dependency) && !mul_stale_hold)
			mul_low_ready <= 1;
	wire [31:0] redirect_pc = (exception_enter || irq_take ? handler_pc : (mret_commit ? return_pc : (maintenance_commit ? mp + 32'd4 : (m_redirect1 ? (m1_taken ? mtarget1 : m1_fall_q) : mnext))));
	wire d_fire = (((dv && (!ev || e_fire)) && !kill) && !halted) && !terminal_stopped;
	wire d_fire1 = d_fire && pair_d;
	always @(posedge clk)
		if (((rst || kill) || e_fire) || !ev) begin
			mulh_state <= 0;
			mulh_step <= 0;
			mulh_hi <= 0;
			mulh_lo <= 0;
			mulh_a <= 0;
			mulh_b <= 0;
			mulh_signed_a <= 0;
			mulh_signed_b <= 0;
		end
		else
			case (mulh_state)
				0:
					if (((!ee && e_mul_high) && !mul_raw_dependency) && !mul_stale_hold) begin
						mulh_a <= mul_a;
						mulh_b <= mul_b;
						mulh_hi <= 0;
						mulh_lo <= mul_b;
						mulh_signed_a <= mul_a[31] && (f3 != 3);
						mulh_signed_b <= mul_b[31] && (f3 == 1);
						mulh_step <= 0;
						mulh_state <= 1;
					end
				1: begin
					{mulh_hi, mulh_lo} <= {mulh_sum, mulh_lo[31:1]};
					if (mulh_step == 31)
						mulh_state <= 2;
					else
						mulh_step <= mulh_step + 1'b1;
				end
				2: begin
					if (mulh_signed_a)
						mulh_hi <= mulh_hi - mulh_b;
					mulh_state <= 3;
				end
				3: begin
					if (mulh_signed_b)
						mulh_hi <= mulh_hi - mulh_a;
					mulh_state <= 4;
				end
				default:
					;
			endcase
	wire rf_capture_early = (((((((((((((((((!zbc_hold && !mul1_hold) && !branch0_slow_hold) && !branch1_slow_hold) && !mul_low_hold) && !mul_high_hold) && !bitfusion_slow_hold) && !mul_raw_dependency) && !mul_stale_hold) && !agu_load_dependency) && !jalr_load_dependency) && !agu_late_dependency) && (!mv || m_done)) && !halted) && !serial_m) && !irq_wait) && !fatal_error) && !run_stop) && !terminal_stopped;
	wire rf_payload_capture = (MACHINE_MODE == 0 ? d_fire : !ev || rf_capture_early);
	wire rf_operand_write0 = (MACHINE_MODE != 0 ? m_done && mr_nonzero_q : rf_write0);
	wire rf_operand_write1 = (MACHINE_MODE != 0 ? (m_done && mv1_exec) && mr1_nonzero_q : rf_write1);
	wire rf_a_m1 = rf_operand_write1 && ((rf_payload_capture && (mr1 == di[19:15])) || (!rf_payload_capture && hit1_rs1_q));
	wire rf_a_m0 = (rf_operand_write0 && !rf_a_m1) && ((rf_payload_capture && (mr == di[19:15])) || (!rf_payload_capture && hit0_rs1_q));
	wire rf_a_raw = (rf_payload_capture && !rf_a_m0) && !rf_a_m1;
	wire rf_a_enable = (rf_payload_capture || rf_a_m0) || rf_a_m1;
	wire [31:0] rf_a_next = (({32 {rf_a_m1}} & mresult1) | ({32 {rf_a_m0}} & m_value)) | ({32 {rf_a_raw}} & read_decode_rf(di[19:15]));
	wire rf_b_m1 = rf_operand_write1 && ((rf_payload_capture && (mr1 == di[24:20])) || (!rf_payload_capture && hit1_rs2_q));
	wire rf_b_m0 = (rf_operand_write0 && !rf_b_m1) && ((rf_payload_capture && (mr == di[24:20])) || (!rf_payload_capture && hit0_rs2_q));
	wire rf_b_raw = (rf_payload_capture && !rf_b_m0) && !rf_b_m1;
	wire rf_b_enable = (rf_payload_capture || rf_b_m0) || rf_b_m1;
	wire [31:0] rf_b_next = (({32 {rf_b_m1}} & mresult1) | ({32 {rf_b_m0}} & m_value)) | ({32 {rf_b_raw}} & read_decode_rf(di[24:20]));
	wire rf_a1_m1 = rf_operand_write1 && (((rf_payload_capture && !d_const_a1) && (mr1 == di1[19:15])) || (!rf_payload_capture && hit1_rs1_1_q));
	wire rf_a1_m0 = (rf_operand_write0 && !rf_a1_m1) && (((rf_payload_capture && !d_const_a1) && (mr == di1[19:15])) || (!rf_payload_capture && hit0_rs1_1_q));
	wire rf_a1_raw = (rf_payload_capture && !rf_a1_m0) && !rf_a1_m1;
	wire rf_a1_enable = (rf_payload_capture || rf_a1_m0) || rf_a1_m1;
	wire [31:0] rf_a1_next = (({32 {rf_a1_m1}} & mresult1) | ({32 {rf_a1_m0}} & m_value)) | ({32 {rf_a1_raw}} & (d_const_a1 ? d_const_value : read_decode_rf(di1[19:15])));
	wire rf_b1_m1 = rf_operand_write1 && (((rf_payload_capture && !d_const_b1) && (mr1 == di1[24:20])) || (!rf_payload_capture && hit1_rs2_1_q));
	wire rf_b1_m0 = (rf_operand_write0 && !rf_b1_m1) && (((rf_payload_capture && !d_const_b1) && (mr == di1[24:20])) || (!rf_payload_capture && hit0_rs2_1_q));
	wire rf_b1_raw = (rf_payload_capture && !rf_b1_m0) && !rf_b1_m1;
	wire rf_b1_enable = (rf_payload_capture || rf_b1_m0) || rf_b1_m1;
	wire [31:0] rf_b1_next = (({32 {rf_b1_m1}} & mresult1) | ({32 {rf_b1_m0}} & m_value)) | ({32 {rf_b1_raw}} & (d_const_b1 ? d_const_value : read_decode_rf(di1[24:20])));
	always @(posedge clk)
		if (rst) begin
			rf_a_local_q <= 0;
			rf_b_local_q <= 0;
			rf_a1_local_q <= 0;
			rf_b1_local_q <= 0;
			rf_a_source_q <= 3'b001;
			rf_b_source_q <= 3'b001;
			rf_a1_source_q <= 3'b001;
			rf_b1_source_q <= 3'b001;
		end
		else begin
			rf_a_local_q <= rf_a_q;
			rf_a_source_q <= 3'b001;
			if (rf_a_enable) begin
				rf_a_local_q <= rf_a_next;
				rf_a_source_q <= {rf_a_m1, rf_a_m0, rf_a_raw};
			end
			rf_b_local_q <= rf_b_q;
			rf_b_source_q <= 3'b001;
			if (rf_b_enable) begin
				rf_b_local_q <= rf_b_next;
				rf_b_source_q <= {rf_b_m1, rf_b_m0, rf_b_raw};
			end
			rf_a1_local_q <= rf_a1_q;
			rf_a1_source_q <= 3'b001;
			if (rf_a1_enable) begin
				rf_a1_local_q <= rf_a1_next;
				rf_a1_source_q <= {rf_a1_m1, rf_a1_m0, rf_a1_raw};
			end
			rf_b1_local_q <= rf_b1_q;
			rf_b1_source_q <= 3'b001;
			if (rf_b1_enable) begin
				rf_b1_local_q <= rf_b1_next;
				rf_b1_source_q <= {rf_b1_m1, rf_b1_m0, rf_b1_raw};
			end
		end
	wire mul_m0_slow = (mcsr || (mmem && !mwrite)) || mmul_pipe_q;
	wire mul_da1 = rf_operand_write1 && (mr1 == di[19:15]);
	wire mul_da0 = (rf_operand_write0 && !mul_da1) && (mr == di[19:15]);
	wire mul_db1 = rf_operand_write1 && (mr1 == di[24:20]);
	wire mul_db0 = (rf_operand_write0 && !mul_db1) && (mr == di[24:20]);
	wire mul_ha1 = rf_operand_write1 && hit1_rs1_q;
	wire mul_ha0 = (rf_operand_write0 && !mul_ha1) && hit0_rs1_q;
	wire mul_hb1 = rf_operand_write1 && hit1_rs2_q;
	wire mul_hb0 = (rf_operand_write0 && !mul_hb1) && hit0_rs2_q;
	wire [31:0] mul_a_decode_next = (({32 {mul_da1}} & mresult1_nonmul) | ({32 {mul_da0}} & m_alu_nonmul)) | ({32 {!mul_da1 && !mul_da0}} & read_decode_rf(di[19:15]));
	wire [31:0] mul_b_decode_next = (({32 {mul_db1}} & mresult1_nonmul) | ({32 {mul_db0}} & m_alu_nonmul)) | ({32 {!mul_db1 && !mul_db0}} & read_decode_rf(di[24:20]));
	wire [31:0] mul_a_held_next = (({32 {mul_ha1}} & mresult1_nonmul) | ({32 {mul_ha0}} & m_alu_nonmul)) | ({32 {!mul_ha1 && !mul_ha0}} & rf_a_q);
	wire [31:0] mul_b_held_next = (({32 {mul_hb1}} & mresult1_nonmul) | ({32 {mul_hb0}} & m_alu_nonmul)) | ({32 {!mul_hb1 && !mul_hb0}} & rf_b_q);
	always @(posedge clk)
		if (rst) begin
			mul_a_decode_q <= 0;
			mul_b_decode_q <= 0;
			mul_a_held_q <= 0;
			mul_b_held_q <= 0;
			mul_payload_q <= 0;
			mul_a_decode_stale_q <= 0;
			mul_b_decode_stale_q <= 0;
			mul_a_held_stale_q <= 0;
			mul_b_held_stale_q <= 0;
		end
		else begin
			mul_a_decode_q <= mul_a_decode_next;
			mul_b_decode_q <= mul_b_decode_next;
			mul_a_held_q <= mul_a_held_next;
			mul_b_held_q <= mul_b_held_next;
			mul_payload_q <= rf_payload_capture;
			mul_a_decode_stale_q <= (mul_da0 && mul_m0_slow) || (mul_da1 && mmul1_live_q);
			mul_b_decode_stale_q <= (mul_db0 && mul_m0_slow) || (mul_db1 && mmul1_live_q);
			mul_a_held_stale_q <= (mul_ha0 && mul_m0_slow) || (mul_ha1 && mmul1_live_q);
			mul_b_held_stale_q <= (mul_hb0 && mul_m0_slow) || (mul_hb1 && mmul1_live_q);
		end
	wire [31:0] predict_pc;
	wire [31:0] predicted_next;
	wire [31:0] predicted_next1;
	wire predicted_sequential;
	wire [31:0] response_predict_pc;
	wire [31:0] response_predicted_next;
	wire [31:0] response_predicted_next1;
	wire response_predicted_seq;
	wire response_predicted_seq1;
	wire predict_accept;
	wire predict_accept_second;
	wire response_sample_fast_select;
	p2_predictor #(
		.ENABLED(BP_ENABLED),
		.BTB_ENTRIES(BTB_ENTRIES),
		.BHT_ENTRIES(BHT_ENTRIES),
		.RAS_DEPTH(RAS_DEPTH)
	) predictor(
		.clk(clk),
		.rst(rst),
		.lookup_pc(predict_pc),
		.prediction(predicted_next),
		.prediction_is_sequential(predicted_sequential),
		.response_sample_pc(i_req_addr),
		.response_sample_accept(i_req_valid && i_req_ready),
		.response_sample_fast_pc(fast_pc),
		.response_sample_fast_select(response_sample_fast_select),
		.response_lookup_pc(response_predict_pc),
		.response_prediction(response_predicted_next),
		.response_prediction1(response_predicted_next1),
		.response_sequential(response_predicted_seq),
		.response_sequential1(response_predicted_seq1),
		.lookup_pc1(predict_pc + 32'd4),
		.prediction1(predicted_next1),
		.lookup_accept(predict_accept),
		.lookup_second_valid(predict_accept_second),
		.fetch_flush(kill),
		.train_valid(control_commit || slot1_branch_commit),
		.train_pc((slot1_branch_sel ? mp1 : mp)),
		.train_target((slot1_branch_sel ? mtarget1 : mtarget)),
		.train_conditional(slot1_branch_sel || mconditional),
		.train_taken((slot1_branch_sel ? m1_taken : mtaken)),
		.train_insn((slot1_branch_sel ? mi1 : mi)),
		.ras_flush((((m_kill || irq_take) || mret_commit) || maintenance_commit) || terminal_commit),
		.ras_call_valid((control_commit && ((mi[6:0] == 7'h6f) || (mi[6:0] == 7'h67))) && ((mi[11:7] == 5'd1) || (mi[11:7] == 5'd5))),
		.ras_call_return(mp + 32'd4)
	);
	p2_frontend_dual #(
		.RESET_PC(RESET_PC),
		.FIFO_DEPTH(FIFO_DEPTH),
		.RESPONSE_BYPASS(RESPONSE_BYPASS),
		.DUAL_WORDS(IFETCH_DUAL_WORDS),
		.LINE_BYTES(IFETCH_LINE_BYTES),
		.RESPONSE_PREDECODE(IFETCH_PREDECODE)
	) frontend(
		.clk(clk),
		.rst(rst),
		.stop(((((halted || fetch_stop) || (mv && mfencei)) || fatal_error) || run_stop) || terminal_stopped),
		.redirect_valid(kill),
		.redirect_pc(redirect_pc),
		.fast_redirect(fast_redirect),
		.fast_pc(fast_pc),
		.fast_pc4(fast_pc4),
		.fast_pc8(fast_pc8),
		.predict_pc(predict_pc),
		.predict_next(predicted_next),
		.predict_next1(predicted_next1),
		.predict_sequential(predicted_sequential),
		.response_predict_pc(response_predict_pc),
		.response_predict_next(response_predicted_next),
		.response_predict_next1(response_predicted_next1),
		.response_predict_sequential(response_predicted_seq),
		.response_predict_sequential1(response_predicted_seq1),
		.predict_accept(predict_accept),
		.predict_accept_second(predict_accept_second),
		.response_sample_fast_select(response_sample_fast_select),
		.req_valid(i_req_valid),
		.req_ready(i_req_ready),
		.req_addr(i_req_addr),
		.rsp_valid(i_rsp_valid),
		.rsp_ready(i_rsp_ready),
		.rsp_data(i_rsp_data),
		.rsp_error(i_rsp_error),
		.rsp_data_hi(i_rsp_data_hi),
		.rsp_hi_valid(i_rsp_hi_valid),
		.rsp_predecode(i_rsp_predecode),
		.rsp_predecode_hi(i_rsp_predecode_hi),
		.out_valid(dv),
		.out_ready(d_fire),
		.out_pc(dp),
		.out_insn(di),
		.out_prediction(front_prediction),
		.out_error(de),
		.out_sequential(front_sequential),
		.out1_sequential(front_sequential1),
		.out_pair_link(front_pair_link),
		.out_predecode(front_pre0),
		.out1_predecode(front_pre1),
		.out1_valid(dv1),
		.out1_ready(d_fire1),
		.out1_pc(dp1),
		.out1_insn(di1),
		.out1_prediction(front_prediction1),
		.out1_error(de1)
	);
	wire [1:0] lsu_align_low = agu_a[1:0] + e_lsu_imm[1:0];
	wire lsu_align_bad = (((f3 == 1) || (f3 == 5)) && lsu_align_low[0]) || ((f3 == 2) && |lsu_align_low);
	wire lsu_encoding_legal = ((op == 7'h03) || (op == 7'h23)) && ((((f3 == 0) || (f3 == 1)) || (f3 == 2)) || ((op == 7'h03) && ((f3 == 4) || (f3 == 5))));
	wire lsu_payload_legal = (lsu_encoding_legal && !lsu_align_bad) && !ee;
	wire late_data_request = ((mv && mmem) && !mfault) && !msent;
	wire address_base_forwarded = mv && (m0_rs1 || (mv1_exec && m1_rs1));
	wire registered_base_ready = (((MACHINE_MODE != 0) && mv) && !ld_q[0]) && !late_q;
	wire [31:0] early_address_base = (MACHINE_MODE != 0 ? early_a : rf_a_q);
	wire [31:0] early_address = agu_add_signed12(early_address_base, e_lsu_imm);
	wire [3:0] early_be = (f3[1:0] == 0 ? 4'b0001 << early_address[1:0] : (f3[1:0] == 1 ? 4'b0011 << early_address[1:0] : 4'b1111));
	wire early_data_request = ((((EARLY_LSU != 0) && e_fire) && lsu_payload_legal) && (!address_base_forwarded || registered_base_ready)) && (!e_store_q || !store_data_late);
	wire [31:0] early_write_data = (e_store_q ? early_store_b << {early_address[1:0], 3'b000} : 32'b00000000000000000000000000000000);
	assign d_req_valid = late_data_request || early_data_request;
	assign d_req_addr = (late_data_request ? {maddr[31:2], 2'b00} : {early_address[31:2], 2'b00});
	assign d_req_write = (late_data_request ? mwrite : e_store_q);
	assign d_req_be = (late_data_request ? mbe : early_be);
	assign d_req_wdata = (late_data_request ? mwdata : early_write_data);
	assign d_rsp_ready = ((mv && mmem) && !mfault) && msent;
	assign fence_i_valid = ((mv && mfencei) && !mfence_sent) && !halted;
	assign data_idle = !mv;
	wire perf_active = (!halted && !terminal_stopped) && !run_stop;
	wire retired_control = control_commit || slot1_branch_commit;
	wire retired_taken = (slot1_branch_sel ? m1_taken : mtaken);
	wire retired_wrong = (slot1_branch_sel ? m1_mispredict : mpred_wrong);
	wire [31:0] retired_pc = (slot1_branch_sel ? mp1 : mp);
	wire [31:0] retired_insn = (slot1_branch_sel ? mi1 : mi);
	wire load_use_event = ((((ev && mv) && mmem) && !mwrite) && !m_done) && ((use1 && m0_rs1) || (use2 && m0_rs2));
	wire [23:0] perf_events;
	assign perf_events[0] = ((!ev || e_fire) && !dv) && !kill;
	assign perf_events[1] = !dv;
	assign perf_events[2] = kill;
	assign perf_events[3] = (dv && !d_fire) && !kill;
	assign perf_events[4] = load_use_event;
	assign perf_events[5] = (mv && mmem) && !m_done;
	assign perf_events[6] = retired_control;
	assign perf_events[7] = retired_control && retired_taken;
	assign perf_events[8] = retired_control && retired_wrong;
	assign perf_events[9] = m_redirect;
	assign perf_events[10] = retired_control;
	assign perf_events[11] = retired_control && !retired_wrong;
	assign perf_events[12] = i_req_valid && !i_req_ready;
	assign perf_events[13] = i_req_valid && i_req_ready;
	assign perf_events[14] = i_rsp_valid && i_rsp_ready;
	assign perf_events[15] = d_req_valid && d_req_ready;
	assign perf_events[16] = d_req_valid && !d_req_ready;
	assign perf_events[17] = ((m_done && !m_bad) && !mcontrol) && mpred_wrong;
	assign perf_events[18] = d_fire;
	assign perf_events[23:19] = 0;
	wire [1535:0] unused_perf_values;
	p3_perf_counters #(.DUAL_ISSUE(1)) perf(
		.clk(clk),
		.rst(rst),
		.enable(perf_active),
		.event_pulses(perf_events),
		.issue_second(d_fire1),
		.csr_addr(mi[31:20]),
		.csr_rdata(perf_rdata),
		.csr_known(perf_known),
		.i_hit(perf_cache_flat[0+:64]),
		.i_miss(perf_cache_flat[64+:64]),
		.d_hit(perf_cache_flat[128+:64]),
		.d_miss(perf_cache_flat[192+:64]),
		.d_writeback(perf_cache_flat[256+:64]),
		.values_flat(unused_perf_values)
	);
	wire fl_v1n = (e_fire ? ev1 && !fault : mv1_raw_q);
	wire fl_nz1n = (e_fire ? (op1 != 7'h63) && (ei1[11:7] != 0) : mr1_nonzero_q);
	wire fl_nz0n = (e_fire ? rd != 0 : mr_nonzero_q);
	wire fl_ld0n = (e_fire ? (mem && !wr) || e_mul_pipe : (mmem && !mwrite) || mmul_pipe_q);
	wire fl_late0n = (e_fire ? (e_late0 || e_mul_pipe) && !fault : mlate0);
	wire fl_late1n = (e_fire ? (e_late1 || e_mul1_pipe) && !fault : mlate1 && !mmul1_live_q);
	wire fl_mul1n = (e_fire && e_mul1_pipe) && !fault;
	wire fl_h0n_0 = hit_next(e_fire, rf_payload_capture, ei[11:7], mr, di[19:15], rs1);
	wire fl_h1n_0 = hit_next(e_fire, rf_payload_capture, ei1[11:7], mr1, di[19:15], rs1);
	wire fl_sel1_0 = (fl_v1n && fl_nz1n) && fl_h1n_0;
	wire fl_sel0_0 = fl_nz0n && fl_h0n_0;
	wire fl_h0n_1 = hit_next(e_fire, rf_payload_capture, ei[11:7], mr, di[24:20], rs2);
	wire fl_h1n_1 = hit_next(e_fire, rf_payload_capture, ei1[11:7], mr1, di[24:20], rs2);
	wire fl_sel1_1 = (fl_v1n && fl_nz1n) && fl_h1n_1;
	wire fl_sel0_1 = fl_nz0n && fl_h0n_1;
	wire fl_h0n_2 = literal_hit_next(e_fire, rf_payload_capture, ei[11:7], mr, di1[19:15], ei1[19:15], d_const_a1, e_const_a1_q);
	wire fl_h1n_2 = literal_hit_next(e_fire, rf_payload_capture, ei1[11:7], mr1, di1[19:15], ei1[19:15], d_const_a1, e_const_a1_q);
	wire fl_sel1_2 = (fl_v1n && fl_nz1n) && fl_h1n_2;
	wire fl_sel0_2 = fl_nz0n && fl_h0n_2;
	wire fl_h0n_3 = literal_hit_next(e_fire, rf_payload_capture, ei[11:7], mr, di1[24:20], ei1[24:20], d_const_b1, e_const_b1_q);
	wire fl_h1n_3 = literal_hit_next(e_fire, rf_payload_capture, ei1[11:7], mr1, di1[24:20], ei1[24:20], d_const_b1, e_const_b1_q);
	wire fl_sel1_3 = (fl_v1n && fl_nz1n) && fl_h1n_3;
	wire fl_sel0_3 = fl_nz0n && fl_h0n_3;
	always @(posedge clk)
		if (rst || kill) begin
			e_fusion_sel_q <= 0;
			e_late1_enable_q <= 0;
		end
		else if (rf_payload_capture) begin
			e_fusion_sel_q <= {d_fire1 && (d_bitfusion == 32'sd4), d_fire1 && (d_bitfusion == 32'sd3), d_fire1 && (d_bitfusion == 32'sd2), d_fire1 && (d_bitfusion == 32'sd1)};
			e_late1_enable_q <= (((d_fire1 && !de1) && !d_lui_pair) && (d_bitfusion == 0)) && integer_alu_encoding(di1);
		end
		else if (e_fire) begin
			e_fusion_sel_q <= 0;
			e_late1_enable_q <= 0;
		end
	wire branch_payload_capture = !mv || m_done;
	always @(posedge clk)
		if (rst) begin
			mtarget_base <= 0;
			mtarget1 <= 0;
			mpred <= 0;
			mbranch_a <= 0;
			mbranch_b <= 0;
			mbranch_eq8 <= 4'b1111;
			mbranch_lt8 <= 0;
			mbranch_signed_top_lt <= 0;
			mbranch_eq_taken_q <= 1;
			mbranch_low_lt_direction_q <= 1;
			mbranch_low_ge_direction_q <= 1;
			mbranch_order_hi_lt_q <= 0;
			mbranch_order_hi_eq_q <= 1;
			mbranch_order_lo_lt_q <= 0;
			m1_decision_q <= 1;
			m1_order_low_lt_q <= 0;
			m1_order_low_ge_q <= 0;
			m1_order_lower_lt_q <= 0;
			m_tgt_eq1_q <= 0;
			m_ft_eq1_q <= 1;
			mbranch1_eq8 <= 4'b1111;
			m_wrong_taken_q <= 0;
			m_wrong_nt_q <= 1;
			m_fall_q <= 4;
			m_fall4_q <= 8;
			m_fall8_q <= 12;
			m_tgt4_q <= 4;
			m_tgt8_q <= 8;
			m1_tgt4_q <= 4;
			m1_tgt8_q <= 8;
			m1_fall4_q <= 8;
			m1_fall8_q <= 12;
			m1_wrong_taken_q <= 0;
			m1_wrong_nt_q <= 0;
			m1_fall_q <= 4;
		end
		else if (branch_payload_capture) begin
			mtarget_base <= target;
			mtarget1 <= ep1 + {{19 {ei1[31]}}, ei1[31], ei1[7], ei1[30:25], ei1[11:8], 1'b0};
			mpred <= epred;
			mbranch_a <= a;
			mbranch_b <= (e_late0 && (op == 7'h13) ? imm_i : b);
			mbranch_eq8 <= {a[31:24] == b[31:24], a[23:16] == b[23:16], a[15:8] == b[15:8], a[7:0] == b[7:0]};
			mbranch_lt8 <= {branch0_a[31:24] < branch0_b[31:24], branch0_a[23:16] < branch0_b[23:16], branch0_a[15:8] < branch0_b[15:8], branch0_a[7:0] < branch0_b[7:0]};
			mbranch_signed_top_lt <= $signed(branch0_a[31:24]) < $signed(branch0_b[31:24]);
			mbranch_eq_taken_q <= (f3[0] ? !branch0_equal : branch0_equal);
			mbranch_low_lt_direction_q <= (f3[2] ? word_dir_lt0 : (f3[0] ? !branch0_equal : branch0_equal));
			mbranch_low_ge_direction_q <= (f3[2] ? word_dir_ge0 : (f3[0] ? !branch0_equal : branch0_equal));
			mbranch_order_hi_lt_q <= word_high_lt0;
			mbranch_order_hi_eq_q <= word_high_eq0;
			mbranch_order_lo_lt_q <= word_lower_lt0;
			m1_decision_q <= (ei1[12] ? !branch1_equal : branch1_equal);
			m1_order_low_lt_q <= word_dir_lt1;
			m1_order_low_ge_q <= word_dir_ge1;
			m1_order_lower_lt_q <= word_lower_lt1;
			m_tgt_eq1_q <= target == ep1;
			m_ft_eq1_q <= (ep + 32'd4) == ep1;
			mbranch1_eq8 <= {a1[31:24] == b1[31:24], a1[23:16] == b1[23:16], a1[15:8] == b1[15:8], a1[7:0] == b1[7:0]};
			m_wrong_taken_q <= target != epred;
			m_wrong_nt_q <= (ep + 32'd4) != epred;
			m_fall_q <= ep + 32'd4;
			m_fall4_q <= ep + 32'd8;
			m_fall8_q <= ep + 32'd12;
			m_tgt4_q <= target_plus4;
			m_tgt8_q <= target_plus8;
			m1_tgt4_q <= (ep1 + {{19 {ei1[31]}}, ei1[31], ei1[7], ei1[30:25], ei1[11:8], 1'b0}) + 32'd4;
			m1_tgt8_q <= (ep1 + {{19 {ei1[31]}}, ei1[31], ei1[7], ei1[30:25], ei1[11:8], 1'b0}) + 32'd8;
			m1_fall4_q <= ep1 + 32'd8;
			m1_fall8_q <= ep1 + 32'd12;
			m1_wrong_taken_q <= (ep1 + {{19 {ei1[31]}}, ei1[31], ei1[7], ei1[30:25], ei1[11:8], 1'b0}) != epred1;
			m1_wrong_nt_q <= (ep1 + 32'd4) != epred1;
			m1_fall_q <= ep1 + 32'd4;
		end
	always @(posedge clk)
		if (rst) begin
			fetch_stop <= 0;
			terminal_stopped <= 0;
			ev <= 0;
			mv <= 0;
			ep <= 0;
			ei <= 0;
			mp <= 0;
			mi <= 0;
			ee <= 0;
			e_target_kind_q <= 0;
			e_pc_target_imm_q <= 0;
			e_lsu_imm12_q <= 0;
			e_store_q <= 0;
			e_alu_imm0_q <= 0;
			e_alu_sub0_q <= 0;
			e_alu_left0_q <= 0;
			e_alu_arith0_q <= 0;
			e_alu_imm1_q <= 0;
			e_alu_sub1_q <= 0;
			e_alu_left1_q <= 0;
			e_alu_arith1_q <= 0;
			ev1 <= 0;
			mv1_raw_q <= 0;
			ep1 <= 0;
			ei1 <= 0;
			mp1 <= 0;
			mi1 <= 0;
			ee1 <= 0;
			e_lui_pair_q <= 0;
			e_bitfusion_q <= 0;
			e_const_a1_q <= 0;
			e_const_b1_q <= 0;
			mresult1_payload <= 0;
			mlate_b1 <= 0;
			mlate0 <= 0;
			mmul_pipe_q <= 0;
			mlate1 <= 0;
			mmul1_live_q <= 0;
			mr1 <= 0;
			mlate_sub0 <= 0;
			mlate_left0 <= 0;
			mlate_arith0 <= 0;
			mlate_sub1 <= 0;
			mlate_left1 <= 0;
			mlate_arith1 <= 0;
			hit0_rs1_q <= 1;
			hit0_rs2_q <= 1;
			hit0_rs1_1_q <= 1;
			hit0_rs2_1_q <= 1;
			hit1_rs1_q <= 1;
			hit1_rs2_q <= 1;
			hit1_rs1_1_q <= 1;
			hit1_rs2_1_q <= 1;
			mr1_nonzero_q <= 0;
			slowL_q <= 0;
			ld_q <= 0;
			late_q <= 0;
			any_q <= 0;
			early_fwd0_q <= 0;
			early_fwd1_q <= 0;
			mr <= 0;
			mr_nonzero_q <= 0;
			mresult <= 0;
			maddr <= 0;
			mload_format_q <= load_format_decode(2'b00, 3'b000);
			mwdata <= 0;
			mcause <= 0;
			mtval <= 0;
			mbe <= 0;
			mfunct3 <= 0;
			mmem <= 0;
			mwrite <= 0;
			mfault <= 0;
			msent <= 0;
			halted <= 0;
			mcsr <= 0;
			mmret <= 0;
			mfencei <= 0;
			mfence_sent <= 0;
			mcontrol <= 0;
			mconditional <= 0;
			epred <= 0;
			commit_next_pc <= RESET_PC;
			m1_branch_q <= 0;
			m_fast_s1_nonmem_q <= 0;
			m1_bne_q <= 0;
			epred1 <= 4;
			trace_irq_valid <= 0;
			trace_irq_pc <= 0;
			trace_irq_cause <= 0;
			trace_csr_valid <= 0;
			trace_csr_read <= 0;
			trace_csr_write <= 0;
			trace_csr_addr <= 0;
			trace_csr_rdata <= 0;
			trace_csr_wdata <= 0;
			trace_valid <= 0;
			trace_trap <= 0;
			trace_pc <= 0;
			trace_insn <= 0;
			trace_rd <= 0;
			trace_wdata <= 0;
			trace_valid1 <= 0;
			trace_pc1 <= 0;
			trace_insn1 <= 0;
			trace_rd1 <= 0;
			trace_wdata1 <= 0;
			trace_cause <= 0;
			trace_tval <= 0;
			trace_mem_valid <= 0;
			trace_mem_write <= 0;
			trace_mem_addr <= 0;
			trace_mem_wdata <= 0;
			trace_mem_rdata <= 0;
			trace_mem_be <= 0;
			count_cycle <= 0;
			count_retired <= 0;
			count_if_wait <= 0;
			count_data_wait <= 0;
			count_load_use <= 0;
			count_redirect <= 0;
			count_reads <= 0;
			count_writes <= 0;
		end
		else begin
			trace_valid <= 0;
			trace_valid1 <= 0;
			trace_irq_valid <= 0;
			trace_csr_valid <= 0;
			early_fwd0_q[0] <= (fl_sel0_0 && !fl_ld0n) && !fl_late0n;
			early_fwd0_q[1] <= (fl_sel0_1 && !fl_ld0n) && !fl_late0n;
			early_fwd1_q[0] <= fl_sel1_0 && !fl_late1n;
			early_fwd1_q[1] <= fl_sel1_1 && !fl_late1n;
			slowL_q[0] <= (fl_sel1_0 ? fl_late1n : (fl_sel0_0 ? fl_ld0n || fl_late0n : 1'b0));
			ld_q[0] <= (fl_sel1_0 ? fl_mul1n : fl_sel0_0 && fl_ld0n);
			slowL_q[1] <= (fl_sel1_1 ? fl_late1n : (fl_sel0_1 ? fl_ld0n || fl_late0n : 1'b0));
			ld_q[1] <= (fl_sel1_1 ? fl_mul1n : fl_sel0_1 && fl_ld0n);
			late_q <= (fl_sel1_0 ? fl_late1n : fl_sel0_0 && fl_late0n);
			any_q[0] <= fl_sel1_0 || fl_sel0_0;
			any_q[1] <= fl_sel1_1 || fl_sel0_1;
			any_q[2] <= fl_sel1_2 || fl_sel0_2;
			any_q[3] <= fl_sel1_3 || fl_sel0_3;
			hit0_rs1_q <= hit_next(e_fire, rf_payload_capture, ei[11:7], mr, di[19:15], rs1);
			hit0_rs2_q <= hit_next(e_fire, rf_payload_capture, ei[11:7], mr, di[24:20], rs2);
			hit0_rs1_1_q <= literal_hit_next(e_fire, rf_payload_capture, ei[11:7], mr, di1[19:15], ei1[19:15], d_const_a1, e_const_a1_q);
			hit0_rs2_1_q <= literal_hit_next(e_fire, rf_payload_capture, ei[11:7], mr, di1[24:20], ei1[24:20], d_const_b1, e_const_b1_q);
			hit1_rs1_q <= hit_next(e_fire, rf_payload_capture, ei1[11:7], mr1, di[19:15], rs1);
			hit1_rs2_q <= hit_next(e_fire, rf_payload_capture, ei1[11:7], mr1, di[24:20], rs2);
			hit1_rs1_1_q <= literal_hit_next(e_fire, rf_payload_capture, ei1[11:7], mr1, di1[19:15], ei1[19:15], d_const_a1, e_const_a1_q);
			hit1_rs2_1_q <= literal_hit_next(e_fire, rf_payload_capture, ei1[11:7], mr1, di1[24:20], ei1[24:20], d_const_b1, e_const_b1_q);
			if (e_fire)
				mr1_nonzero_q <= (op1 != 7'h63) && (ei1[11:7] != 0);
			if (terminal_commit)
				terminal_stopped <= 1;
			if (terminal_stopped)
				;
			if (fatal_error || ((mfence_sent && fence_i_done) && fence_i_error))
				halted <= 1;
			if (fence_i_valid && fence_i_ready)
				mfence_sent <= 1;
			if (!halted) begin
				count_cycle <= count_cycle + 1;
				if (!dv)
					count_if_wait <= count_if_wait + 1;
				if ((mv && mmem) && !m_done)
					count_data_wait <= count_data_wait + 1;
				if (load_use_event)
					count_load_use <= count_load_use + 1;
			end
			if (d_req_valid && d_req_ready) begin
				msent <= 1;
				if (d_req_write)
					count_writes <= count_writes + 1;
				else
					count_reads <= count_reads + 1;
			end
			if (m_done) begin
				mv <= 0;
				trace_valid <= 1;
				trace_trap <= m_bad;
				mv1_raw_q <= 0;
				if ((mv1 && !m_bad) && !terminal_commit) begin
					trace_valid1 <= 1;
					trace_pc1 <= mp1;
					trace_insn1 <= mi1;
					trace_rd1 <= mr1;
					trace_wdata1 <= (mr1 == 0 ? 32'b00000000000000000000000000000000 : mresult1);
				end
				trace_pc <= mp;
				trace_insn <= mi;
				trace_rd <= (m_bad ? 5'b00000 : mr);
				trace_wdata <= (m_bad || (mr == 0) ? 32'b00000000000000000000000000000000 : m_value);
				trace_cause <= (m_bad ? m_final_cause : 32'b00000000000000000000000000000000);
				trace_tval <= (m_bad ? m_final_tval : 32'b00000000000000000000000000000000);
				trace_mem_valid <= mmem;
				trace_mem_write <= mmem && mwrite;
				trace_mem_addr <= (mmem ? {maddr[31:2], 2'b00} : 32'b00000000000000000000000000000000);
				trace_mem_be <= (mmem ? mbe : 4'b0000);
				trace_mem_wdata <= (mmem && mwrite ? mwdata : 32'b00000000000000000000000000000000);
				trace_mem_rdata <= ((mmem && !mwrite) && !m_bad ? d_rsp_data : 32'b00000000000000000000000000000000);
				trace_csr_valid <= mcsr && !m_bad;
				trace_csr_addr <= mi[31:20];
				trace_csr_read <= csr_read;
				trace_csr_write <= csr_write;
				trace_csr_rdata <= (csr_read ? csr_rdata : 32'b00000000000000000000000000000000);
				trace_csr_wdata <= (csr_write ? csr_wdata : 32'b00000000000000000000000000000000);
				if (m_bad) begin
					if (MACHINE_MODE == 0)
						halted <= 1;
					else
						commit_next_pc <= handler_pc;
				end
				else begin
					count_retired <= count_retired + (mv1 && !terminal_commit ? 64'd2 : 64'd1);
					commit_next_pc <= (mmret ? return_pc : (mv1 && !terminal_commit ? (m1_taken ? mtarget1 : mp1 + 32'd4) : mnext));
				end
			end
			if (mmul1_live_q) begin
				mresult1_payload <= mul_result;
				mlate1 <= 0;
				mmul1_live_q <= 0;
			end
			if (e_fire) begin
				ev <= 0;
				mv <= 1;
				mp <= ep;
				mi <= ei;
				mr <= rd;
				mr_nonzero_q <= rd != 0;
				mresult <= er;
				ev1 <= 0;
				mv1_raw_q <= ev1 && !fault;
				mp1 <= ep1;
				mi1 <= ei1;
				mr1 <= (op1 == 7'h63 ? 5'd0 : ei1[11:7]);
				m1_branch_q <= op1 == 7'h63;
				m_fast_s1_nonmem_q <= (op1 == 7'h63) && !mem;
				m1_bne_q <= f3_1[0];
				mresult1_payload <= (e_late1 ? a1 : er1);
				mlate_b1 <= (ei1[6:0] == 7'h13 ? {{20 {ei1[31]}}, ei1[31:20]} : b1);
				mlate0 <= (e_late0 || e_mul_pipe) && !fault;
				mmul_pipe_q <= e_mul_pipe && !fault;
				mlate1 <= (e_late1 || e_mul1_pipe) && !fault;
				mmul1_live_q <= e_mul1_pipe && !fault;
				mlate_sub0 <= (op == 7'h33) && ei[30];
				mlate_left0 <= f3 == 3'd1;
				mlate_arith0 <= (f3 == 3'd5) && ei[30];
				mlate_sub1 <= (ei1[6:0] == 7'h33) && ei1[30];
				mlate_left1 <= ei1[14:12] == 3'd1;
				mlate_arith1 <= (ei1[14:12] == 3'd5) && ei1[30];
				maddr <= ea;
				mload_format_q <= load_format_decode(ea[1:0], f3);
				mwdata <= (wr ? ew : 32'b00000000000000000000000000000000);
				mbe <= be;
				mfunct3 <= f3;
				mmem <= mem;
				mwrite <= wr;
				mfault <= fault;
				mcause <= ecause;
				mtval <= etval;
				msent <= early_data_request && d_req_ready;
				mcsr <= csr;
				mmret <= mret;
				mfencei <= fencei;
				mfence_sent <= 0;
				mcontrol <= control;
				mconditional <= conditional;
			end
			if (d_fire) begin
				ev <= 1;
				ev1 <= d_fire1;
			end
			if (rf_payload_capture) begin
				e_lui_pair_q <= d_lui_pair;
				e_bitfusion_q <= d_bitfusion;
				e_const_a1_q <= d_const_a1;
				e_const_b1_q <= d_const_b1;
				epred <= front_prediction;
				epred1 <= front_prediction1;
				ep <= dp;
				ei <= di;
				ee <= de;
				e_target_kind_q <= d_target_kind;
				e_pc_target_imm_q <= d_pc_target_imm;
				e_store_q <= di[6:0] == 7'h23;
				e_alu_imm0_q <= di[6:0] == 7'h13;
				e_alu_sub0_q <= (di[6:0] == 7'h33) && di[30];
				e_alu_left0_q <= di[14:12] == 3'd1;
				e_alu_arith0_q <= (di[14:12] == 3'd5) && di[30];
				e_alu_imm1_q <= di1[6:0] == 7'h13;
				e_alu_sub1_q <= (di1[6:0] == 7'h33) && di1[30];
				e_alu_left1_q <= di1[14:12] == 3'd1;
				e_alu_arith1_q <= (di1[14:12] == 3'd5) && di1[30];
				e_lsu_imm12_q <= (di[5] ? {di[31:25], di[11:7]} : di[31:20]);
				ep1 <= dp1;
				ei1 <= di1;
				ee1 <= de1;
			end
			if (kill) begin
				ev <= 0;
				ev1 <= 0;
				if ((MACHINE_MODE == 0) && (m_kill || (fault && (!m_redirect || terminal_commit))))
					fetch_stop <= 1;
				else
					count_redirect <= count_redirect + 1;
			end
			if (irq_take) begin
				trace_irq_valid <= 1;
				trace_irq_pc <= commit_next_pc;
				trace_irq_cause <= irq_cause;
				commit_next_pc <= handler_pc;
			end
		end
	initial _sv2v_0 = 0;
endmodule
module p2_csr (
	clk,
	rst,
	access_valid,
	access_addr,
	access_write,
	access_wdata,
	access_commit,
	perf_known,
	perf_rdata,
	access_rdata,
	access_error,
	access_modify_rdata,
	retire,
	retire_second,
	trap_enter,
	trap_pc,
	trap_cause,
	trap_tval,
	mret_commit,
	irq_software,
	irq_timer,
	irq_external,
	irq_eligible,
	irq_cause,
	handler_pc,
	return_pc,
	machine_cycle,
	machine_retired
);
	input wire clk;
	input wire rst;
	input wire access_valid;
	input wire [11:0] access_addr;
	input wire access_write;
	input wire [31:0] access_wdata;
	input wire access_commit;
	input wire perf_known;
	input wire [31:0] perf_rdata;
	output reg [31:0] access_rdata;
	output wire access_error;
	output wire [31:0] access_modify_rdata;
	input wire retire;
	input wire retire_second;
	input wire trap_enter;
	input wire [31:0] trap_pc;
	input wire [31:0] trap_cause;
	input wire [31:0] trap_tval;
	input wire mret_commit;
	input wire irq_software;
	input wire irq_timer;
	input wire irq_external;
	output wire irq_eligible;
	output wire [31:0] irq_cause;
	output wire [31:0] handler_pc;
	output wire [31:0] return_pc;
	output wire [63:0] machine_cycle;
	output wire [63:0] machine_retired;
	reg mie_global;
	reg mpie;
	reg [31:0] mie;
	reg [31:0] mtvec;
	reg [31:0] mscratch;
	reg [31:0] mepc;
	reg [31:0] mcause;
	reg [31:0] mtval;
	reg [2:0] inhibit;
	reg [63:0] mcycle;
	reg [63:0] minstret;
	wire unused_trap_low = ^trap_pc[1:0];
	wire [31:0] mip = {20'b00000000000000000000, irq_external, 3'b000, irq_timer, 3'b000, irq_software, 3'b000};
	wire [31:0] eligible = mip & mie;
	assign irq_eligible = mie_global && |eligible;
	assign irq_cause = (eligible[11] ? 32'h8000000b : (eligible[3] ? 32'h80000003 : 32'h80000007));
	assign handler_pc = mtvec;
	assign return_pc = mepc;
	assign machine_cycle = mcycle;
	assign machine_retired = minstret;
	reg known;
	wire zero_warl = (((access_addr == 12'h310) || ((access_addr >= 12'hb03) && (access_addr <= 12'hb1f))) || ((access_addr >= 12'hb83) && (access_addr <= 12'hb9f))) || ((access_addr >= 12'h323) && (access_addr <= 12'h33f));
	reg standard_known;
	reg [31:0] standard_rdata;
	reg [31:0] perf_read_leaf;
	always @(*) begin
		standard_known = 1;
		standard_rdata = 0;
		case (access_addr)
			12'h300: standard_rdata = 32'h00001800 | {24'b000000000000000000000000, mpie, 3'b000, mie_global, 3'b000};
			12'h301: standard_rdata = 32'h40000100;
			12'h304: standard_rdata = mie;
			12'h305: standard_rdata = mtvec;
			12'h320: standard_rdata = {29'b00000000000000000000000000000, inhibit};
			12'h340: standard_rdata = mscratch;
			12'h341: standard_rdata = mepc;
			12'h342: standard_rdata = mcause;
			12'h343: standard_rdata = mtval;
			12'h344: standard_rdata = mip;
			12'hb00: standard_rdata = mcycle[31:0];
			12'hb80: standard_rdata = mcycle[63:32];
			12'hb02: standard_rdata = minstret[31:0];
			12'hb82: standard_rdata = minstret[63:32];
			12'hf11, 12'hf12, 12'hf13, 12'hf14, 12'hf15: standard_rdata = 0;
			default: standard_known = 1'b0;
		endcase
		known = (standard_known || zero_warl) || perf_known;
		perf_read_leaf = 0;
		if (!standard_known && perf_known)
			perf_read_leaf = perf_rdata;
		access_rdata = standard_rdata | perf_read_leaf;
	end
	assign access_modify_rdata = standard_rdata;
	assign access_error = access_valid && (!known || (access_write && (access_addr[11:10] == 2'b11)));
	wire write_commit = ((access_valid && access_write) && access_commit) && !access_error;
	wire cycle_write_lo = write_commit && (access_addr == 12'hb00);
	wire cycle_write_hi = write_commit && (access_addr == 12'hb80);
	wire retired_write_lo = write_commit && (access_addr == 12'hb02);
	wire retired_write_hi = write_commit && (access_addr == 12'hb82);
	wire cycle_write_any = cycle_write_lo || cycle_write_hi;
	wire retired_write_any = retired_write_lo || retired_write_hi;
	wire cycle_tick = !inhibit[0];
	wire retired_tick = retire && !inhibit[2];
	reg [2:0] cycle_full_q;
	reg [2:0] retired_full_q;
	reg retired_near_q;
	wire retired_low_carry = retired_full_q[0] || (retire_second && retired_near_q);
	wire [15:0] retired_low_plus_one = minstret[15:0] + 16'd1;
	wire [15:0] retired_low_plus_two = minstret[15:0] + 16'd2;
	genvar _gv_chunk_1;
	generate
		for (_gv_chunk_1 = 0; _gv_chunk_1 < 4; _gv_chunk_1 = _gv_chunk_1 + 1) begin : counter_segment
			localparam chunk = _gv_chunk_1;
			wire cycle_lower_full;
			wire retired_lower_full;
			wire cycle_write_here = (chunk < 2 ? cycle_write_lo : cycle_write_hi);
			wire retired_write_here = (chunk < 2 ? retired_write_lo : retired_write_hi);
			wire [15:0] write_word = access_wdata[(chunk % 2) * 16+:16];
			if (chunk == 0) begin : low
				assign cycle_lower_full = 1'b1;
				assign retired_lower_full = 1'b1;
			end
			else begin : high
				assign cycle_lower_full = &cycle_full_q[chunk - 1:0];
				if (chunk == 1) begin : genblk1
					assign retired_lower_full = retired_low_carry;
				end
				else begin : genblk1
					assign retired_lower_full = retired_low_carry && &retired_full_q[chunk - 1:1];
				end
			end
			always @(posedge clk)
				if (rst)
					mcycle[chunk * 16+:16] <= 0;
				else if (cycle_write_any) begin
					if (cycle_write_here)
						mcycle[chunk * 16+:16] <= write_word;
				end
				else if (cycle_tick && cycle_lower_full)
					mcycle[chunk * 16+:16] <= mcycle[chunk * 16+:16] + 16'd1;
			if (chunk == 0) begin : retired_low
				always @(posedge clk)
					if (rst) begin
						minstret[15:0] <= 0;
						retired_near_q <= 0;
					end
					else if (retired_write_any) begin
						if (retired_write_here) begin
							minstret[15:0] <= write_word;
							retired_near_q <= write_word == 16'hfffe;
						end
					end
					else if (retired_tick) begin
						minstret[15:0] <= (retire_second ? retired_low_plus_two : retired_low_plus_one);
						retired_near_q <= (retire_second ? minstret[15:0] == 16'hfffc : minstret[15:0] == 16'hfffd);
					end
			end
			else begin : retired_high
				always @(posedge clk)
					if (rst)
						minstret[chunk * 16+:16] <= 0;
					else if (retired_write_any) begin
						if (retired_write_here)
							minstret[chunk * 16+:16] <= write_word;
					end
					else if (retired_tick && retired_lower_full)
						minstret[chunk * 16+:16] <= minstret[chunk * 16+:16] + 16'd1;
			end
			if (chunk < 3) begin : carry_flags
				always @(posedge clk)
					if (rst)
						cycle_full_q[chunk] <= 0;
					else if (cycle_write_any) begin
						if (cycle_write_here)
							cycle_full_q[chunk] <= write_word == 16'hffff;
					end
					else if (cycle_tick && cycle_lower_full)
						cycle_full_q[chunk] <= mcycle[chunk * 16+:16] == 16'hfffe;
				always @(posedge clk)
					if (rst)
						retired_full_q[chunk] <= 0;
					else if (retired_write_any) begin
						if (retired_write_here)
							retired_full_q[chunk] <= write_word == 16'hffff;
					end
					else if (retired_tick && retired_lower_full) begin
						if (chunk == 0)
							retired_full_q[chunk] <= (retire_second ? minstret[15:0] == 16'hfffd : minstret[15:0] == 16'hfffe);
						else
							retired_full_q[chunk] <= minstret[chunk * 16+:16] == 16'hfffe;
					end
			end
		end
	endgenerate
	always @(posedge clk)
		if (rst) begin
			mie_global <= 0;
			mpie <= 0;
			mie <= 0;
			mtvec <= 0;
			mscratch <= 0;
			mepc <= 0;
			mcause <= 0;
			mtval <= 0;
			inhibit <= 0;
		end
		else begin
			if (write_commit)
				case (access_addr)
					12'h300: begin
						mie_global <= access_wdata[3];
						mpie <= access_wdata[7];
					end
					12'h304: mie <= access_wdata & 32'h00000888;
					12'h305: mtvec <= {access_wdata[31:2], 2'b00};
					12'h320: inhibit <= access_wdata[2:0] & 3'b101;
					12'h340: mscratch <= access_wdata;
					12'h341: mepc <= {access_wdata[31:2], 2'b00};
					12'h342: mcause <= access_wdata;
					12'h343: mtval <= access_wdata;
					default:
						;
				endcase
			if (mret_commit) begin
				mie_global <= mpie;
				mpie <= 1;
			end
			if (trap_enter) begin
				mepc <= {trap_pc[31:2], 2'b00};
				mcause <= trap_cause;
				mtval <= trap_tval;
				mpie <= mie_global;
				mie_global <= 0;
			end
		end
endmodule
module p2_frontend (
	clk,
	rst,
	stop,
	redirect_valid,
	redirect_pc,
	predict_pc,
	predict_next,
	req_valid,
	req_ready,
	req_addr,
	rsp_valid,
	rsp_ready,
	rsp_data,
	rsp_error,
	out_valid,
	out_ready,
	out_pc,
	out_insn,
	out_prediction,
	out_error
);
	parameter [31:0] RESET_PC = 32'h80000000;
	parameter integer FIFO_DEPTH = 2;
	parameter integer RESPONSE_BYPASS = 0;
	input wire clk;
	input wire rst;
	input wire stop;
	input wire redirect_valid;
	input wire [31:0] redirect_pc;
	output wire [31:0] predict_pc;
	input wire [31:0] predict_next;
	output wire req_valid;
	input wire req_ready;
	output wire [31:0] req_addr;
	input wire rsp_valid;
	output wire rsp_ready;
	input wire [31:0] rsp_data;
	input wire rsp_error;
	output wire out_valid;
	input wire out_ready;
	output wire [31:0] out_pc;
	output wire [31:0] out_insn;
	output wire [31:0] out_prediction;
	output wire out_error;
	reg [31:0] offer_pc;
	reg [31:0] pending_pc;
	reg [31:0] pending_prediction;
	reg [31:0] recovery_pc;
	reg pending;
	reg pending_discard;
	reg offer_discard;
	reg recovery;
	reg held_offer;
	localparam integer PTR_BITS = $clog2(FIFO_DEPTH);
	function automatic signed [((PTR_BITS + 0) >= 0 ? PTR_BITS + 1 : 1 - (PTR_BITS + 0)) - 1:0] sv2v_cast_8B9F8_signed;
		input reg signed [((PTR_BITS + 0) >= 0 ? PTR_BITS + 1 : 1 - (PTR_BITS + 0)) - 1:0] inp;
		sv2v_cast_8B9F8_signed = inp;
	endfunction
	localparam [PTR_BITS:0] CAPACITY = sv2v_cast_8B9F8_signed(FIFO_DEPTH);
	reg [31:0] q_pc [0:FIFO_DEPTH - 1];
	reg [31:0] q_insn [0:FIFO_DEPTH - 1];
	reg [31:0] q_prediction [0:FIFO_DEPTH - 1];
	reg q_error [0:FIFO_DEPTH - 1];
	reg [PTR_BITS - 1:0] rd_ptr;
	reg [PTR_BITS - 1:0] wr_ptr;
	reg [PTR_BITS:0] count;
	wire bypass = ((((((RESPONSE_BYPASS != 0) && (count == 0)) && pending) && rsp_valid) && !pending_discard) && !redirect_valid) && !stop;
	assign out_valid = (count != 0) || bypass;
	assign out_pc = (count != 0 ? q_pc[rd_ptr] : pending_pc);
	assign out_insn = (count != 0 ? q_insn[rd_ptr] : rsp_data);
	assign out_prediction = (count != 0 ? q_prediction[rd_ptr] : pending_prediction);
	assign out_error = (count != 0 ? q_error[rd_ptr] : rsp_error);
	wire pop = (count != 0) && out_ready;
	wire bypass_fire = bypass && out_ready;
	assign rsp_ready = pending && ((((pending_discard || redirect_valid) || stop) || (count < CAPACITY)) || pop);
	wire returning = rsp_valid && rsp_ready;
	assign req_valid = (!stop || held_offer) && (!pending || returning);
	assign req_addr = offer_pc;
	assign predict_pc = offer_pc;
	wire accepting = req_valid && req_ready;
	wire push = (((returning && !pending_discard) && !redirect_valid) && !stop) && !bypass_fire;
	integer j;
	always @(posedge clk)
		if (rst) begin
			offer_pc <= RESET_PC;
			pending <= 0;
			pending_discard <= 0;
			pending_pc <= 0;
			pending_prediction <= 0;
			offer_discard <= 0;
			recovery <= 0;
			recovery_pc <= 0;
			held_offer <= 0;
			rd_ptr <= 0;
			wr_ptr <= 0;
			count <= 0;
			for (j = 0; j < FIFO_DEPTH; j = j + 1)
				begin
					q_pc[j] <= 0;
					q_insn[j] <= 0;
					q_prediction[j] <= 0;
					q_error[j] <= 0;
				end
		end
		else begin
			held_offer <= req_valid && !req_ready;
			if (returning)
				pending <= 0;
			if (accepting) begin
				pending <= 1;
				pending_pc <= offer_pc;
				pending_prediction <= predict_next;
				pending_discard <= (offer_discard || redirect_valid) || stop;
				offer_pc <= (recovery ? recovery_pc : predict_next);
				offer_discard <= 0;
				recovery <= 0;
			end
			if (pop)
				rd_ptr <= rd_ptr + 1'b1;
			if (push) begin
				q_pc[wr_ptr] <= pending_pc;
				q_insn[wr_ptr] <= rsp_data;
				q_prediction[wr_ptr] <= pending_prediction;
				q_error[wr_ptr] <= rsp_error;
				wr_ptr <= wr_ptr + 1'b1;
			end
			case ({push, pop})
				2'b10: count <= count + 1'b1;
				2'b01: count <= count - 1'b1;
				default:
					;
			endcase
			if (redirect_valid) begin
				rd_ptr <= 0;
				wr_ptr <= 0;
				count <= 0;
				if (pending && !returning)
					pending_discard <= 1;
				if (req_valid && !req_ready) begin
					offer_discard <= 1;
					recovery <= 1;
					recovery_pc <= redirect_pc;
				end
				else begin
					offer_pc <= redirect_pc;
					offer_discard <= 0;
					recovery <= 0;
				end
			end
		end
endmodule
module p2_peripherals (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_be,
	req_wdata,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	uart_tx,
	gpio_out,
	external_irq,
	irq_software,
	irq_timer,
	irq_external
);
	reg _sv2v_0;
	parameter [31:0] UART_BASE = 32'h10000000;
	parameter [31:0] GPIO_BASE = 32'h10001000;
	parameter [31:0] TIMER_BASE = 32'h10002000;
	parameter integer UART_DIVISOR = 8;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output reg req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [3:0] req_be;
	input wire [31:0] req_wdata;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output reg uart_tx;
	output reg [31:0] gpio_out;
	input wire external_irq;
	output wire irq_software;
	output reg irq_timer;
	output wire irq_external;
	localparam [31:0] UART_DATA_OFF = 32'h00000000;
	localparam [31:0] UART_STATUS_OFF = 32'h00000004;
	localparam [31:0] UART_BAUD_OFF = 32'h00000008;
	localparam [31:0] GPIO_DATA_OFF = 32'h00000000;
	localparam [31:0] TIMER_MTIME_LO_OFF = 32'h00000000;
	localparam [31:0] TIMER_MTIME_HI_OFF = 32'h00000004;
	localparam [31:0] TIMER_CMP_LO_OFF = 32'h00000008;
	localparam [31:0] TIMER_CMP_HI_OFF = 32'h0000000c;
	localparam [31:0] TIMER_MSIP_OFF = 32'h00000010;
	localparam [31:0] TIMER_EXT_OFF = 32'h00000014;
	localparam integer UART_DIVISOR_RESET = (UART_DIVISOR < 2 ? 2 : UART_DIVISOR);
	reg [63:0] timer_counter;
	reg [63:0] timer_compare;
	reg msip_pending;
	reg ext_test_pending;
	reg [31:0] uart_baud_div;
	reg [31:0] uart_baud_limit;
	reg uart_busy;
	reg [7:0] uart_data;
	reg [3:0] uart_bit_index;
	reg [31:0] uart_baud_count;
	wire [31:0] uart_baud_increment;
	assign uart_baud_increment[0] = ~uart_baud_count[0];
	genvar _gv_uart_inc_bit_1;
	generate
		for (_gv_uart_inc_bit_1 = 1; _gv_uart_inc_bit_1 < 32; _gv_uart_inc_bit_1 = _gv_uart_inc_bit_1 + 1) begin : uart_increment_prefix
			localparam uart_inc_bit = _gv_uart_inc_bit_1;
			assign uart_baud_increment[uart_inc_bit] = uart_baud_count[uart_inc_bit] ^ &uart_baud_count[uart_inc_bit - 1:0];
		end
	endgenerate
	function automatic [31:0] merge_word;
		input [31:0] old_value;
		input [31:0] new_value;
		input [3:0] byte_enable;
		begin
			merge_word = old_value;
			if (byte_enable[0])
				merge_word[7:0] = new_value[7:0];
			if (byte_enable[1])
				merge_word[15:8] = new_value[15:8];
			if (byte_enable[2])
				merge_word[23:16] = new_value[23:16];
			if (byte_enable[3])
				merge_word[31:24] = new_value[31:24];
		end
	endfunction
	wire rsp_consumed = rsp_valid && rsp_ready;
	wire data_access = req_addr == (UART_BASE + UART_DATA_OFF);
	wire baud_access = req_addr == (UART_BASE + UART_BAUD_OFF);
	wire data_write_blocked = ((data_access && req_write) && req_be[0]) && uart_busy;
	wire baud_write_blocked = ((baud_access && req_write) && (req_be != 4'd0)) && uart_busy;
	always @(*) begin
		if (_sv2v_0)
			;
		req_ready = ((!rsp_valid || rsp_ready) && !data_write_blocked) && !baud_write_blocked;
	end
	wire req_fire = req_valid && req_ready;
	wire timer_mtime_write = ((req_fire && req_write) && (req_be != 4'd0)) && ((req_addr == (TIMER_BASE + TIMER_MTIME_LO_OFF)) || (req_addr == (TIMER_BASE + TIMER_MTIME_HI_OFF)));
	assign irq_software = msip_pending;
	function automatic timer_route_at;
		input [31:0] address;
		timer_route_at = (!((address >= UART_BASE) && (address < (UART_BASE + 32'h00001000))) && !((address >= GPIO_BASE) && (address < (GPIO_BASE + 32'h00001000)))) && ((address >= TIMER_BASE) && (address < (TIMER_BASE + 32'h00001000)));
	endfunction
	localparam [31:0] CMP_LO_ADDR = TIMER_BASE + TIMER_CMP_LO_OFF;
	localparam [31:0] CMP_HI_ADDR = TIMER_BASE + TIMER_CMP_HI_OFF;
	localparam CMP_LO_ROUTED = timer_route_at(CMP_LO_ADDR);
	localparam CMP_HI_ROUTED = timer_route_at(CMP_HI_ADDR);
	wire timer_cmp_lo_write = (((CMP_LO_ROUTED && req_fire) && req_write) && (req_be != 4'd0)) && (req_addr == CMP_LO_ADDR);
	wire timer_cmp_hi_write = (((CMP_HI_ROUTED && req_fire) && req_write) && (req_be != 4'd0)) && (req_addr == CMP_HI_ADDR);
	reg [2:0] timer_full_q;
	reg [3:0] timer_gt_q;
	reg [3:0] timer_eq_q;
	wire [63:0] timer_incremented;
	wire [63:0] timer_counter_next;
	wire [63:0] timer_compare_next;
	wire [63:0] timer_counter_written = (req_addr == (TIMER_BASE + TIMER_MTIME_LO_OFF) ? {timer_counter[63:32], merge_word(timer_counter[31:0], req_wdata, req_be)} : {merge_word(timer_counter[63:32], req_wdata, req_be), timer_counter[31:0]});
	assign timer_counter_next = (timer_mtime_write ? timer_counter_written : timer_incremented);
	assign timer_compare_next = (timer_cmp_lo_write ? {timer_compare[63:32], merge_word(timer_compare[31:0], req_wdata, req_be)} : (timer_cmp_hi_write ? {merge_word(timer_compare[63:32], req_wdata, req_be), timer_compare[31:0]} : timer_compare));
	genvar _gv_tc_1;
	generate
		for (_gv_tc_1 = 0; _gv_tc_1 < 4; _gv_tc_1 = _gv_tc_1 + 1) begin : timer_chunks
			localparam tc = _gv_tc_1;
			wire carry;
			if (tc == 0) begin : genblk1
				assign carry = 1'b1;
			end
			else begin : genblk1
				assign carry = &timer_full_q[tc - 1:0];
			end
			assign timer_incremented[tc * 16+:16] = timer_counter[tc * 16+:16] + carry;
			always @(posedge clk)
				if (rst) begin
					timer_counter[tc * 16+:16] <= 0;
					timer_gt_q[tc] <= 0;
					timer_eq_q[tc] <= 0;
				end
				else begin
					timer_counter[tc * 16+:16] <= timer_counter_next[tc * 16+:16];
					timer_gt_q[tc] <= timer_counter_next[tc * 16+:16] > timer_compare_next[tc * 16+:16];
					timer_eq_q[tc] <= timer_counter_next[tc * 16+:16] == timer_compare_next[tc * 16+:16];
				end
			if (tc < 3) begin : genblk2
				always @(posedge clk)
					if (rst)
						timer_full_q[tc] <= 0;
					else
						timer_full_q[tc] <= &timer_counter_next[tc * 16+:16];
			end
		end
	endgenerate
	wire timer_irq_q = ((timer_gt_q[3] || (timer_eq_q[3] && timer_gt_q[2])) || (&timer_eq_q[3:2] && timer_gt_q[1])) || (&timer_eq_q[3:1] && (timer_gt_q[0] || timer_eq_q[0]));
	always @(posedge clk)
		if (rst)
			irq_timer <= 1'b0;
		else
			irq_timer <= timer_irq_q;
	assign irq_external = external_irq || ext_test_pending;
	always @(posedge clk)
		if (rst) begin
			timer_compare <= 64'hffffffffffffffff;
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
		end
		else begin
			if (rsp_consumed)
				rsp_valid <= 1'b0;
			if (uart_busy) begin
				if (uart_baud_count >= uart_baud_limit) begin
					uart_baud_count <= 32'd0;
					if (uart_bit_index == 4'd9) begin
						uart_busy <= 1'b0;
						uart_tx <= 1'b1;
					end
					else begin
						uart_bit_index <= uart_bit_index + 4'd1;
						if (uart_bit_index == 4'd0)
							uart_tx <= uart_data[0];
						else if (uart_bit_index < 4'd8)
							uart_tx <= uart_data[uart_bit_index[2:0]];
						else
							uart_tx <= 1'b1;
					end
				end
				else
					uart_baud_count <= uart_baud_increment;
			end
			if (req_fire) begin
				rsp_valid <= 1'b1;
				rsp_rdata <= 32'd0;
				rsp_error <= 1'b0;
				if ((req_addr >= UART_BASE) && (req_addr < (UART_BASE + 32'h00001000)))
					case (req_addr)
						UART_BASE + UART_DATA_OFF:
							if ((req_write && req_be[0]) && !uart_busy) begin
								uart_data <= req_wdata[7:0];
								uart_busy <= 1'b1;
								uart_bit_index <= 4'd0;
								uart_baud_count <= 32'd0;
								uart_tx <= 1'b0;
							end
						UART_BASE + UART_STATUS_OFF:
							if (req_write)
								rsp_error <= 1'b1;
							else
								rsp_rdata <= {31'd0, uart_busy};
						UART_BASE + UART_BAUD_OFF:
							if (req_write) begin
								if (!uart_busy) begin
									if (merge_word(uart_baud_div, req_wdata, req_be) < 32'd2) begin
										uart_baud_div <= 32'd2;
										uart_baud_limit <= 32'd1;
									end
									else begin
										uart_baud_div <= merge_word(uart_baud_div, req_wdata, req_be);
										uart_baud_limit <= merge_word(uart_baud_div, req_wdata, req_be) - 32'd1;
									end
								end
							end
							else
								rsp_rdata <= uart_baud_div;
						default: rsp_error <= 1'b1;
					endcase
				else if ((req_addr >= GPIO_BASE) && (req_addr < (GPIO_BASE + 32'h00001000)))
					case (req_addr)
						GPIO_BASE + GPIO_DATA_OFF:
							if (req_write) begin
								if (req_be[0])
									gpio_out[7:0] <= req_wdata[7:0];
								if (req_be[1])
									gpio_out[15:8] <= req_wdata[15:8];
								if (req_be[2])
									gpio_out[23:16] <= req_wdata[23:16];
								if (req_be[3])
									gpio_out[31:24] <= req_wdata[31:24];
							end
							else
								rsp_rdata <= gpio_out;
						default: rsp_error <= 1'b1;
					endcase
				else if ((req_addr >= TIMER_BASE) && (req_addr < (TIMER_BASE + 32'h00001000)))
					case (req_addr)
						TIMER_BASE + TIMER_MTIME_LO_OFF:
							if (!req_write)
								rsp_rdata <= timer_counter[31:0];
						TIMER_BASE + TIMER_MTIME_HI_OFF:
							if (!req_write)
								rsp_rdata <= timer_counter[63:32];
						TIMER_BASE + TIMER_CMP_LO_OFF:
							if (req_write && (req_be != 4'd0))
								timer_compare <= {timer_compare[63:32], merge_word(timer_compare[31:0], req_wdata, req_be)};
							else if (!req_write)
								rsp_rdata <= timer_compare[31:0];
						TIMER_BASE + TIMER_CMP_HI_OFF:
							if (req_write && (req_be != 4'd0))
								timer_compare <= {merge_word(timer_compare[63:32], req_wdata, req_be), timer_compare[31:0]};
							else if (!req_write)
								rsp_rdata <= timer_compare[63:32];
						TIMER_BASE + TIMER_MSIP_OFF:
							if (req_write) begin
								if (req_be[0])
									msip_pending <= req_wdata[0];
							end
							else
								rsp_rdata <= {31'd0, msip_pending};
						TIMER_BASE + TIMER_EXT_OFF:
							if (req_write) begin
								if (req_be[0])
									ext_test_pending <= req_wdata[0];
							end
							else
								rsp_rdata <= {31'd0, ext_test_pending};
						default: rsp_error <= 1'b1;
					endcase
				else
					rsp_error <= 1'b1;
			end
		end
	initial _sv2v_0 = 0;
endmodule
module p2_predictor (
	clk,
	rst,
	lookup_pc,
	prediction,
	prediction_is_sequential,
	lookup_pc1,
	prediction1,
	lookup_accept,
	lookup_second_valid,
	fetch_flush,
	train_valid,
	train_pc,
	train_target,
	train_conditional,
	train_taken,
	train_insn,
	ras_flush,
	ras_call_valid,
	ras_call_return,
	response_sample_pc,
	response_sample_accept,
	response_sample_fast_pc,
	response_sample_fast_select,
	response_lookup_pc,
	response_prediction,
	response_prediction1,
	response_sequential,
	response_sequential1
);
	parameter ENABLED = 1;
	parameter BTB_ENTRIES = 64;
	parameter BHT_ENTRIES = 256;
	parameter RAS_DEPTH = 0;
	input wire clk;
	input wire rst;
	input wire [31:0] lookup_pc;
	output wire [31:0] prediction;
	output wire prediction_is_sequential;
	input wire [31:0] lookup_pc1;
	output wire [31:0] prediction1;
	input wire lookup_accept;
	input wire lookup_second_valid;
	input wire fetch_flush;
	input wire train_valid;
	input wire [31:0] train_pc;
	input wire [31:0] train_target;
	input wire train_conditional;
	input wire train_taken;
	input wire [31:0] train_insn;
	input wire ras_flush;
	input wire ras_call_valid;
	input wire [31:0] ras_call_return;
	input wire [31:0] response_sample_pc;
	input wire response_sample_accept;
	input wire [31:0] response_sample_fast_pc;
	input wire response_sample_fast_select;
	input wire [31:0] response_lookup_pc;
	output wire [31:0] response_prediction;
	output wire [31:0] response_prediction1;
	output wire response_sequential;
	output wire response_sequential1;
	localparam integer BI_BITS = $clog2(BTB_ENTRIES);
	localparam integer DH_BITS = $clog2(BHT_ENTRIES);
	reg valid [0:BTB_ENTRIES - 1];
	localparam integer BT_BITS = 30 - BI_BITS;
	localparam integer BW_BITS = BT_BITS + 34;
	localparam integer PAYLOAD_BITS = BT_BITS + 36;
	localparam integer SEQ_BIT = BW_BITS - 1;
	(* syn_ramstyle = "lut_ram" *) reg [PAYLOAD_BITS - 1:0] payload_even [0:(BTB_ENTRIES / 2) - 1];
	(* syn_ramstyle = "lut_ram" *) reg [PAYLOAD_BITS - 1:0] payload_odd [0:(BTB_ENTRIES / 2) - 1];
	(* syn_ramstyle = "lut_ram" *) reg [1:0] bht_even [0:(BHT_ENTRIES / 2) - 1];
	(* syn_ramstyle = "lut_ram" *) reg [1:0] bht_odd [0:(BHT_ENTRIES / 2) - 1];
	reg bht_initialized [0:BHT_ENTRIES - 1];
	localparam integer BR_BITS = (BI_BITS > 1 ? BI_BITS - 1 : 1);
	localparam integer DR_BITS = (DH_BITS > 1 ? DH_BITS - 1 : 1);
	wire first_odd = lookup_pc[2];
	wire [28:0] even_word = lookup_pc[31:3] + {{28 {1'b0}}, first_odd};
	wire [31:0] pc_even = {even_word, 1'b0, lookup_pc[1:0]};
	wire [31:0] pc_odd = {lookup_pc[31:3], 1'b1, lookup_pc[1:0]};
	wire [BR_BITS - 1:0] be = (pc_even >> 3) & ((BTB_ENTRIES / 2) - 1);
	wire [BR_BITS - 1:0] bo = (pc_odd >> 3) & ((BTB_ENTRIES / 2) - 1);
	wire [DR_BITS - 1:0] de = (pc_even >> 3) & ((BHT_ENTRIES / 2) - 1);
	wire [DR_BITS - 1:0] do_idx = (pc_odd >> 3) & ((BHT_ENTRIES / 2) - 1);
	wire [BI_BITS - 1:0] ti = train_pc[2+:BI_BITS];
	wire [DH_BITS - 1:0] td = train_pc[2+:DH_BITS];
	wire [PAYLOAD_BITS - 1:0] payload_even_read = payload_even[be];
	wire [PAYLOAD_BITS - 1:0] payload_odd_read = payload_odd[bo];
	wire [BW_BITS - 1:0] entry_even = {valid[2 * be], payload_even_read[BW_BITS - 2:0]};
	wire [BW_BITS - 1:0] entry_odd = {valid[(2 * bo) + 1], payload_odd_read[BW_BITS - 2:0]};
	wire [1:0] direction_even = bht_even[de];
	wire [1:0] direction_odd = bht_odd[do_idx];
	wire hit_even = entry_even[BW_BITS - 1] && (entry_even[BW_BITS - 3:32] == pc_even[31:BI_BITS + 2]);
	wire hit_odd = entry_odd[BW_BITS - 1] && (entry_odd[BW_BITS - 3:32] == pc_odd[31:BI_BITS + 2]);
	wire hit = (first_odd ? hit_odd : hit_even);
	wire hit1 = (first_odd ? hit_even : hit_odd);
	wire conditional0 = (first_odd ? entry_odd[BW_BITS - 2] : entry_even[BW_BITS - 2]);
	wire conditional1 = (first_odd ? entry_even[BW_BITS - 2] : entry_odd[BW_BITS - 2]);
	wire [28:0] sequential_word = lookup_pc[31:3];
	wire [4:0] sequential_group_all;
	wire [4:0] sequential_group_prefix;
	assign sequential_group_all[0] = &sequential_word[5:0];
	assign sequential_group_all[1] = &sequential_word[11:6];
	assign sequential_group_all[2] = &sequential_word[17:12];
	assign sequential_group_all[3] = &sequential_word[23:18];
	assign sequential_group_all[4] = &sequential_word[28:24];
	assign sequential_group_prefix[0] = 1'b1;
	genvar _gv_seq_group_1;
	genvar _gv_seq_bit_1;
	generate
		for (_gv_seq_group_1 = 1; _gv_seq_group_1 < 5; _gv_seq_group_1 = _gv_seq_group_1 + 1) begin : seq_groups
			localparam seq_group = _gv_seq_group_1;
			assign sequential_group_prefix[seq_group] = &sequential_group_all[seq_group - 1:0];
		end
	endgenerate
	wire [28:0] sequential_prefix;
	wire [28:0] odd_next_word;
	wire [28:0] even_next_word;
	generate
		for (_gv_seq_bit_1 = 0; _gv_seq_bit_1 < 29; _gv_seq_bit_1 = _gv_seq_bit_1 + 1) begin : seq_bits
			localparam seq_bit = _gv_seq_bit_1;
			localparam integer GROUP = seq_bit / 6;
			localparam integer BASE = GROUP * 6;
			if (seq_bit == BASE) begin : first
				assign sequential_prefix[seq_bit] = sequential_group_prefix[GROUP];
			end
			else begin : rest
				assign sequential_prefix[seq_bit] = sequential_group_prefix[GROUP] && &sequential_word[seq_bit - 1:BASE];
			end
			assign odd_next_word[seq_bit] = sequential_word[seq_bit] ^ sequential_prefix[seq_bit];
			assign even_next_word[seq_bit] = sequential_word[seq_bit] ^ (first_odd && sequential_prefix[seq_bit]);
		end
	endgenerate
	wire [31:0] sequential_even = {even_next_word, 1'b1, lookup_pc[1:0]};
	wire [31:0] sequential_odd = {odd_next_word, 1'b0, lookup_pc[1:0]};
	wire [31:0] pred_even = (((ENABLED != 0) && hit_even) && (!entry_even[BW_BITS - 2] || direction_even[1]) ? entry_even[31:0] : sequential_even);
	wire [31:0] pred_odd = (((ENABLED != 0) && hit_odd) && (!entry_odd[BW_BITS - 2] || direction_odd[1]) ? entry_odd[31:0] : sequential_odd);
	wire [31:0] btb_prediction = (first_odd ? pred_odd : pred_even);
	wire [31:0] btb_prediction1 = (first_odd ? pred_even : pred_odd);
	wire btb_even_taken = ((ENABLED != 0) && hit_even) && (!entry_even[BW_BITS - 2] || direction_even[1]);
	wire btb_odd_taken = ((ENABLED != 0) && hit_odd) && (!entry_odd[BW_BITS - 2] || direction_odd[1]);
	wire btb_even_sequential = !btb_even_taken || (payload_even_read[SEQ_BIT] && (entry_even[1:0] == pc_even[1:0]));
	wire btb_odd_sequential = !btb_odd_taken || (payload_odd_read[SEQ_BIT] && (entry_odd[1:0] == pc_odd[1:0]));
	wire btb_sequential = (first_odd ? btb_odd_sequential : btb_even_sequential);
	reg rs_active_q;
	reg rs_valid_even_q;
	reg rs_valid_odd_q;
	reg [PAYLOAD_BITS - 1:0] rs_payload_even_q;
	reg [PAYLOAD_BITS - 1:0] rs_payload_odd_q;
	reg [1:0] rs_direction_even_q;
	reg [1:0] rs_direction_odd_q;
	reg [BR_BITS - 1:0] rs_be_q;
	reg [BR_BITS - 1:0] rs_bo_q;
	reg [DR_BITS - 1:0] rs_de_q;
	reg [DR_BITS - 1:0] rs_do_q;
	wire [28:0] rs_fast_even_word = response_sample_fast_pc[31:3] + {{28 {1'b0}}, response_sample_fast_pc[2]};
	wire [BR_BITS - 1:0] rs_fast_be = rs_fast_even_word[BR_BITS - 1:0] & ((BTB_ENTRIES / 2) - 1);
	wire [BR_BITS - 1:0] rs_fast_bo = response_sample_fast_pc[3+:BR_BITS] & ((BTB_ENTRIES / 2) - 1);
	wire [DR_BITS - 1:0] rs_fast_de = rs_fast_even_word[DR_BITS - 1:0] & ((BHT_ENTRIES / 2) - 1);
	wire [DR_BITS - 1:0] rs_fast_do = response_sample_fast_pc[3+:DR_BITS] & ((BHT_ENTRIES / 2) - 1);
	wire [BT_BITS - 1:0] rs_normal_even_tag = pc_even[31:BI_BITS + 2];
	wire [BT_BITS - 1:0] rs_normal_odd_tag = pc_odd[31:BI_BITS + 2];
	wire [BT_BITS - 1:0] rs_fast_even_tag = rs_fast_even_word[28:BI_BITS - 1];
	wire [BT_BITS - 1:0] rs_fast_odd_tag = response_sample_fast_pc[31:BI_BITS + 2];
	(* syn_keep = 1 *) wire [PAYLOAD_BITS - 1:0] rs_fast_even_read = payload_even[rs_fast_be];
	(* syn_keep = 1 *) wire [PAYLOAD_BITS - 1:0] rs_fast_odd_read = payload_odd[rs_fast_bo];
	wire [1:0] rs_fast_direction_even = bht_even[rs_fast_de];
	wire [1:0] rs_fast_direction_odd = bht_odd[rs_fast_do];
	wire rs_fast_valid_even = valid[2 * rs_fast_be];
	wire rs_fast_valid_odd = valid[(2 * rs_fast_bo) + 1];
	wire rs_fast_hit_even = rs_fast_valid_even && (rs_fast_even_read[BW_BITS - 3:32] == rs_fast_even_tag);
	wire rs_fast_hit_odd = rs_fast_valid_odd && (rs_fast_odd_read[BW_BITS - 3:32] == rs_fast_odd_tag);
	wire [BR_BITS - 1:0] rs_capture_be = (response_sample_fast_select ? rs_fast_be : be);
	wire [BR_BITS - 1:0] rs_capture_bo = (response_sample_fast_select ? rs_fast_bo : bo);
	wire [DR_BITS - 1:0] rs_capture_de = (response_sample_fast_select ? rs_fast_de : de);
	wire [DR_BITS - 1:0] rs_capture_do = (response_sample_fast_select ? rs_fast_do : do_idx);
	wire rs_btb_write = (ENABLED != 0) && train_valid;
	wire rs_bht_write = rs_btb_write && train_conditional;
	reg [BT_BITS - 1:0] rs_tag_even_q;
	reg [BT_BITS - 1:0] rs_tag_odd_q;
	wire [BT_BITS - 1:0] rs_capture_even_tag = (response_sample_fast_select ? rs_fast_even_tag : rs_normal_even_tag);
	wire [BT_BITS - 1:0] rs_capture_odd_tag = (response_sample_fast_select ? rs_fast_odd_tag : rs_normal_odd_tag);
	wire rp_first_odd = response_lookup_pc[2];
	wire [28:0] rp_even_word = response_lookup_pc[31:3] + {{28 {1'b0}}, rp_first_odd};
	wire [31:0] rp_pc_even = {rp_even_word, 1'b0, response_lookup_pc[1:0]};
	wire [31:0] rp_pc_odd = {response_lookup_pc[31:3], 1'b1, response_lookup_pc[1:0]};
	wire [BR_BITS - 1:0] rp_be = (rp_pc_even >> 3) & ((BTB_ENTRIES / 2) - 1);
	wire [BR_BITS - 1:0] rp_bo = (rp_pc_odd >> 3) & ((BTB_ENTRIES / 2) - 1);
	wire [DR_BITS - 1:0] rp_de = (rp_pc_even >> 3) & ((BHT_ENTRIES / 2) - 1);
	wire [DR_BITS - 1:0] rp_do_idx = (rp_pc_odd >> 3) & ((BHT_ENTRIES / 2) - 1);
	wire [PAYLOAD_BITS - 1:0] rp_payload_even_read = rs_payload_even_q;
	wire [PAYLOAD_BITS - 1:0] rp_payload_odd_read = rs_payload_odd_q;
	wire [BW_BITS - 1:0] rp_entry_even = {rs_valid_even_q, rp_payload_even_read[BW_BITS - 2:0]};
	wire [BW_BITS - 1:0] rp_entry_odd = {rs_valid_odd_q, rp_payload_odd_read[BW_BITS - 2:0]};
	wire [1:0] rp_direction_even = rs_direction_even_q;
	wire [1:0] rp_direction_odd = rs_direction_odd_q;
	wire rp_hit_even = rs_valid_even_q && (rs_payload_even_q[BW_BITS - 3:32] == rs_tag_even_q);
	wire rp_hit_odd = rs_valid_odd_q && (rs_payload_odd_q[BW_BITS - 3:32] == rs_tag_odd_q);
	wire rp_hit = (rp_first_odd ? rp_hit_odd : rp_hit_even);
	wire rp_hit1 = (rp_first_odd ? rp_hit_even : rp_hit_odd);
	wire rp_conditional0 = (rp_first_odd ? rp_entry_odd[BW_BITS - 2] : rp_entry_even[BW_BITS - 2]);
	wire rp_conditional1 = (rp_first_odd ? rp_entry_even[BW_BITS - 2] : rp_entry_odd[BW_BITS - 2]);
	wire [28:0] rp_sequential_word = response_lookup_pc[31:3];
	wire [4:0] rp_sequential_group_all;
	wire [4:0] rp_sequential_group_prefix;
	assign rp_sequential_group_all[0] = &rp_sequential_word[5:0];
	assign rp_sequential_group_all[1] = &rp_sequential_word[11:6];
	assign rp_sequential_group_all[2] = &rp_sequential_word[17:12];
	assign rp_sequential_group_all[3] = &rp_sequential_word[23:18];
	assign rp_sequential_group_all[4] = &rp_sequential_word[28:24];
	assign rp_sequential_group_prefix[0] = 1'b1;
	genvar _gv_rp_seq_group_1;
	genvar _gv_rp_seq_bit_1;
	generate
		for (_gv_rp_seq_group_1 = 1; _gv_rp_seq_group_1 < 5; _gv_rp_seq_group_1 = _gv_rp_seq_group_1 + 1) begin : rp_seq_groups
			localparam rp_seq_group = _gv_rp_seq_group_1;
			assign rp_sequential_group_prefix[rp_seq_group] = &rp_sequential_group_all[rp_seq_group - 1:0];
		end
	endgenerate
	wire [28:0] rp_sequential_prefix;
	wire [28:0] rp_odd_next_word;
	wire [28:0] rp_even_next_word;
	generate
		for (_gv_rp_seq_bit_1 = 0; _gv_rp_seq_bit_1 < 29; _gv_rp_seq_bit_1 = _gv_rp_seq_bit_1 + 1) begin : rp_seq_bits
			localparam rp_seq_bit = _gv_rp_seq_bit_1;
			localparam integer rp_GROUP = rp_seq_bit / 6;
			localparam integer rp_BASE = rp_GROUP * 6;
			if (rp_seq_bit == rp_BASE) begin : rp_first
				assign rp_sequential_prefix[rp_seq_bit] = rp_sequential_group_prefix[rp_GROUP];
			end
			else begin : rp_rest
				assign rp_sequential_prefix[rp_seq_bit] = rp_sequential_group_prefix[rp_GROUP] && &rp_sequential_word[rp_seq_bit - 1:rp_BASE];
			end
			assign rp_odd_next_word[rp_seq_bit] = rp_sequential_word[rp_seq_bit] ^ rp_sequential_prefix[rp_seq_bit];
			assign rp_even_next_word[rp_seq_bit] = rp_sequential_word[rp_seq_bit] ^ (rp_first_odd && rp_sequential_prefix[rp_seq_bit]);
		end
	endgenerate
	wire [31:0] rp_sequential_even = {rp_even_next_word, 1'b1, response_lookup_pc[1:0]};
	wire [31:0] rp_sequential_odd = {rp_odd_next_word, 1'b0, response_lookup_pc[1:0]};
	wire [31:0] rp_pred_even = (((ENABLED != 0) && rp_hit_even) && (!rp_entry_even[BW_BITS - 2] || rp_direction_even[1]) ? rp_entry_even[31:0] : rp_sequential_even);
	wire [31:0] rp_pred_odd = (((ENABLED != 0) && rp_hit_odd) && (!rp_entry_odd[BW_BITS - 2] || rp_direction_odd[1]) ? rp_entry_odd[31:0] : rp_sequential_odd);
	wire [31:0] rp_btb_prediction = (rp_first_odd ? rp_pred_odd : rp_pred_even);
	wire [31:0] rp_btb_prediction1 = (rp_first_odd ? rp_pred_even : rp_pred_odd);
	wire rp_btb_even_taken = ((ENABLED != 0) && rp_hit_even) && (!rp_entry_even[BW_BITS - 2] || rp_direction_even[1]);
	wire rp_btb_odd_taken = ((ENABLED != 0) && rp_hit_odd) && (!rp_entry_odd[BW_BITS - 2] || rp_direction_odd[1]);
	wire rp_btb_even_sequential = !rp_btb_even_taken || (rp_payload_even_read[SEQ_BIT] && (rp_entry_even[1:0] == rp_pc_even[1:0]));
	wire rp_btb_odd_sequential = !rp_btb_odd_taken || (rp_payload_odd_read[SEQ_BIT] && (rp_entry_odd[1:0] == rp_pc_odd[1:0]));
	wire rp_btb_sequential = (rp_first_odd ? rp_btb_odd_sequential : rp_btb_even_sequential);
	wire rp_safe_even = !(rp_hit_even && |rp_payload_even_read[PAYLOAD_BITS - 1:PAYLOAD_BITS - 2]);
	wire rp_safe_odd = !(rp_hit_odd && |rp_payload_odd_read[PAYLOAD_BITS - 1:PAYLOAD_BITS - 2]);
	wire [31:0] rp_safe_prediction_even = (rp_safe_even ? rp_pred_even : rp_sequential_even);
	wire [31:0] rp_safe_prediction_odd = (rp_safe_odd ? rp_pred_odd : rp_sequential_odd);
	assign response_prediction = (rp_first_odd ? rp_safe_prediction_odd : rp_safe_prediction_even);
	assign response_prediction1 = (rp_first_odd ? rp_safe_prediction_even : rp_safe_prediction_odd);
	wire rp_seq_even = !rp_safe_even || rp_btb_even_sequential;
	wire rp_seq_odd = !rp_safe_odd || rp_btb_odd_sequential;
	assign response_sequential = (rp_first_odd ? rp_seq_odd : rp_seq_even);
	assign response_sequential1 = (rp_first_odd ? rp_seq_even : rp_seq_odd);
	wire train_jal = train_insn[6:0] == 7'h6f;
	wire train_jalr = (train_insn[6:0] == 7'h67) && (train_insn[14:12] == 3'b000);
	wire rd_link = (train_insn[11:7] == 5'd1) || (train_insn[11:7] == 5'd5);
	wire rs1_link = (train_insn[19:15] == 5'd1) || (train_insn[19:15] == 5'd5);
	wire pop_hint = (train_jalr && rs1_link) && (!rd_link || (train_insn[11:7] != train_insn[19:15]));
	wire ras_push = ((((RAS_DEPTH != 0) && (ENABLED != 0)) && train_valid) && (train_jal || train_jalr)) && rd_link;
	wire ras_pop = (((RAS_DEPTH != 0) && (ENABLED != 0)) && train_valid) && pop_hint;
	wire ras_nonempty;
	wire ras_override;
	wire ras_return1;
	wire ras_early_valid;
	wire [31:0] ras_top;
	wire [31:0] ras_early_return;
	wire ras_call_forward = ras_override && ras_call_valid;
	wire [31:0] ras_lookup_top = (ras_early_valid ? ras_early_return : (ras_call_forward ? ras_call_return : ras_top));
	assign prediction = (ras_override ? ras_lookup_top : btb_prediction);
	wire ras_early_sequential = ras_early_return == (lookup_pc + 32'd4);
	wire ras_call_sequential = ras_call_return == (lookup_pc + 32'd4);
	wire ras_top_sequential = ras_top == (lookup_pc + 32'd4);
	wire ras_sequential = (ras_early_valid ? ras_early_sequential : (ras_call_forward ? ras_call_sequential : ras_top_sequential));
	assign prediction_is_sequential = (ras_override ? ras_sequential : btb_sequential);
	wire ras_override1 = (((((RAS_DEPTH != 0) && (ENABLED != 0)) && hit1) && !conditional1) && ras_return1) && ((ras_nonempty || ras_early_valid) || ras_call_valid);
	assign prediction1 = (ras_override1 ? ras_lookup_top : btb_prediction1);
	generate
		if (RAS_DEPTH != 0) begin : ras_enabled
			localparam integer COUNT_BITS = $clog2(RAS_DEPTH + 1);
			reg [COUNT_BITS - 1:0] count_q;
			reg [31:0] stack_q [0:RAS_DEPTH - 1];
			reg early_valid_q;
			reg [31:0] early_bank0_lo_q;
			reg [31:0] early_bank0_hi_q;
			reg [31:0] early_bank1_lo_q;
			reg [31:0] early_bank1_hi_q;
			reg early_bank_q;
			reg early_slot_q;
			reg early_zero_q;
			wire [31:0] early_selected_lo = (early_bank_q ? early_bank1_lo_q : early_bank0_lo_q);
			wire [31:0] early_selected_hi = (early_bank_q ? early_bank1_hi_q : early_bank0_hi_q);
			wire [31:0] early_return_q = (early_zero_q ? 32'b00000000000000000000000000000000 : (early_slot_q ? early_selected_hi : early_selected_lo));
			always @(posedge clk)
				if (early_bank_q) begin
					early_bank0_lo_q <= lookup_pc + 32'd4;
					early_bank0_hi_q <= lookup_pc1 + 32'd4;
				end
				else begin
					early_bank1_lo_q <= lookup_pc + 32'd4;
					early_bank1_hi_q <= lookup_pc1 + 32'd4;
				end
			wire [31:0] train_return = train_pc + 32'd4;
			assign ras_early_valid = early_valid_q;
			assign ras_early_return = early_return_q;
			wire [1:0] hint_even = payload_even_read[PAYLOAD_BITS - 1-:2];
			wire [1:0] hint_odd = payload_odd_read[PAYLOAD_BITS - 1-:2];
			wire return0 = (first_odd ? hint_odd[1] : hint_even[1]);
			wire call0 = (first_odd ? hint_odd[0] : hint_even[0]);
			wire call1 = (first_odd ? hint_even[0] : hint_odd[0]);
			wire fetch_call0 = (lookup_accept && hit) && call0;
			wire fetch_call1 = ((lookup_accept && lookup_second_valid) && hit1) && call1;
			always @(posedge clk)
				if (rst || fetch_flush) begin
					early_valid_q <= 0;
					early_bank_q <= 0;
					early_slot_q <= 0;
					early_zero_q <= 1;
				end
				else begin
					if ((ras_push && early_valid_q) && (train_return == early_return_q))
						early_valid_q <= 0;
					if (fetch_call0 || fetch_call1) begin
						early_valid_q <= 1;
						early_bank_q <= !early_bank_q;
						early_slot_q <= fetch_call1;
						early_zero_q <= 0;
					end
				end
			assign ras_return1 = (first_odd ? hint_even[1] : hint_odd[1]);
			integer r;
			assign ras_nonempty = count_q != 0;
			assign ras_top = stack_q[0];
			assign ras_override = ((((ENABLED != 0) && hit) && !conditional0) && return0) && ((ras_nonempty || ras_early_valid) || ras_call_valid);
			always @(posedge clk)
				if (rst || ras_flush) begin
					count_q <= 0;
					for (r = 0; r < RAS_DEPTH; r = r + 1)
						stack_q[r] <= 0;
				end
				else if (ras_push) begin
					stack_q[0] <= train_return;
					if (!ras_pop) begin
						for (r = 1; r < RAS_DEPTH; r = r + 1)
							stack_q[r] <= stack_q[r - 1];
						if (count_q < RAS_DEPTH)
							count_q <= count_q + 1'b1;
					end
					else if (count_q == 0)
						count_q <= 1;
				end
				else if (ras_pop && ras_nonempty) begin
					for (r = 0; r < (RAS_DEPTH - 1); r = r + 1)
						stack_q[r] <= stack_q[r + 1];
					stack_q[RAS_DEPTH - 1] <= 0;
					count_q <= count_q - 1'b1;
				end
		end
		else begin : ras_disabled
			assign ras_nonempty = 1'b0;
			assign ras_top = 32'b00000000000000000000000000000000;
			assign ras_override = 1'b0;
			assign ras_return1 = 1'b0;
			assign ras_early_valid = 1'b0;
			assign ras_early_return = 32'b00000000000000000000000000000000;
		end
	endgenerate
	wire [29:0] train_next_word = train_pc[31:2] + 30'd1;
	wire train_word_sequential = train_target[31:2] == train_next_word;
	wire [PAYLOAD_BITS - 1:0] training_payload = {pop_hint && (train_insn[31:20] == 12'b000000000000), (train_jal || train_jalr) && rd_link, train_word_sequential, train_conditional, train_pc[31:BI_BITS + 2], train_target};
	always @(posedge clk)
		if (((!rst && (ENABLED != 0)) && train_valid) && !ti[0])
			payload_even[ti >> 1] <= training_payload;
	always @(posedge clk)
		if (((!rst && (ENABLED != 0)) && train_valid) && ti[0])
			payload_odd[ti >> 1] <= training_payload;
	genvar _gv_h_1;
	generate
		for (_gv_h_1 = 0; _gv_h_1 < BTB_ENTRIES; _gv_h_1 = _gv_h_1 + 1) begin : btb_entry
			localparam h = _gv_h_1;
			always @(posedge clk)
				if (rst)
					valid[h] <= 0;
				else if (((ENABLED != 0) && train_valid) && (ti == h[BI_BITS - 1:0]))
					valid[h] <= 1;
		end
	endgenerate
	function [1:0] bht_saturate;
		input [1:0] value;
		input taken;
		begin
			bht_saturate = value;
			if (taken && (value != 2'b11))
				bht_saturate = value + 1'b1;
			if (!taken && (value != 2'b00))
				bht_saturate = value - 1'b1;
		end
	endfunction
	wire [DR_BITS - 1:0] bht_train_row = td >> 1;
	wire [1:0] bht_train_even = (bht_initialized[td] ? bht_even[bht_train_row] : 2'b01);
	wire [1:0] bht_train_odd = (bht_initialized[td] ? bht_odd[bht_train_row] : 2'b01);
	wire [1:0] bht_next_even = bht_saturate(bht_train_even, train_taken);
	wire [1:0] bht_next_odd = bht_saturate(bht_train_odd, train_taken);
	always @(posedge clk)
		if ((((!rst && (ENABLED != 0)) && train_valid) && train_conditional) && !td[0])
			bht_even[bht_train_row] <= bht_next_even;
	always @(posedge clk)
		if ((((!rst && (ENABLED != 0)) && train_valid) && train_conditional) && td[0])
			bht_odd[bht_train_row] <= bht_next_odd;
	generate
		for (_gv_h_1 = 0; _gv_h_1 < BHT_ENTRIES; _gv_h_1 = _gv_h_1 + 1) begin : bht_counter
			localparam h = _gv_h_1;
			always @(posedge clk)
				if (rst)
					bht_initialized[h] <= 0;
				else if ((((ENABLED != 0) && train_valid) && train_conditional) && (td == h[DH_BITS - 1:0]))
					bht_initialized[h] <= 1;
		end
	endgenerate
	wire rs_normal_even_train = (rs_btb_write && (ti[0] == 1'b0)) && ((ti >> 1) == be);
	wire rs_normal_even_bht_train = (rs_bht_write && (td[0] == 1'b0)) && ((td >> 1) == de);
	(* syn_keep = 1 *) wire [PAYLOAD_BITS - 1:0] rs_normal_even_payload = (rs_normal_even_train ? training_payload : payload_even_read);
	wire rs_normal_even_valid = rs_normal_even_train || valid[2 * be];
	wire rs_normal_even_hit = (rs_normal_even_train ? training_payload[BW_BITS - 3:32] == rs_normal_even_tag : hit_even);
	wire [1:0] rs_normal_even_direction = (rs_normal_even_bht_train ? bht_next_even : direction_even);
	wire rs_normal_odd_train = (rs_btb_write && (ti[0] == 1'b1)) && ((ti >> 1) == bo);
	wire rs_normal_odd_bht_train = (rs_bht_write && (td[0] == 1'b1)) && ((td >> 1) == do_idx);
	(* syn_keep = 1 *) wire [PAYLOAD_BITS - 1:0] rs_normal_odd_payload = (rs_normal_odd_train ? training_payload : payload_odd_read);
	wire rs_normal_odd_valid = rs_normal_odd_train || valid[(2 * bo) + 1];
	wire rs_normal_odd_hit = (rs_normal_odd_train ? training_payload[BW_BITS - 3:32] == rs_normal_odd_tag : hit_odd);
	wire [1:0] rs_normal_odd_direction = (rs_normal_odd_bht_train ? bht_next_odd : direction_odd);
	wire rs_fast_even_train = (rs_btb_write && (ti[0] == 1'b0)) && ((ti >> 1) == rs_fast_be);
	wire rs_fast_even_bht_train = (rs_bht_write && (td[0] == 1'b0)) && ((td >> 1) == rs_fast_de);
	(* syn_keep = 1 *) wire [PAYLOAD_BITS - 1:0] rs_fast_even_payload = (rs_fast_even_train ? training_payload : rs_fast_even_read);
	wire rs_fast_even_valid = rs_fast_even_train || valid[2 * rs_fast_be];
	wire rs_fast_even_hit = (rs_fast_even_train ? training_payload[BW_BITS - 3:32] == rs_fast_even_tag : rs_fast_hit_even);
	wire [1:0] rs_fast_even_direction = (rs_fast_even_bht_train ? bht_next_even : rs_fast_direction_even);
	wire rs_fast_odd_train = (rs_btb_write && (ti[0] == 1'b1)) && ((ti >> 1) == rs_fast_bo);
	wire rs_fast_odd_bht_train = (rs_bht_write && (td[0] == 1'b1)) && ((td >> 1) == rs_fast_do);
	(* syn_keep = 1 *) wire [PAYLOAD_BITS - 1:0] rs_fast_odd_payload = (rs_fast_odd_train ? training_payload : rs_fast_odd_read);
	wire rs_fast_odd_valid = rs_fast_odd_train || valid[(2 * rs_fast_bo) + 1];
	wire rs_fast_odd_hit = (rs_fast_odd_train ? training_payload[BW_BITS - 3:32] == rs_fast_odd_tag : rs_fast_hit_odd);
	wire [1:0] rs_fast_odd_direction = (rs_fast_odd_bht_train ? bht_next_odd : rs_fast_direction_odd);
	wire [PAYLOAD_BITS - 1:0] rs_take_even_payload = (response_sample_fast_select ? rs_fast_even_payload : rs_normal_even_payload);
	wire rs_take_even_valid = (response_sample_fast_select ? rs_fast_even_valid : rs_normal_even_valid);
	wire rs_take_even_hit = (response_sample_fast_select ? rs_fast_even_hit : rs_normal_even_hit);
	wire [1:0] rs_take_even_direction = (response_sample_fast_select ? rs_fast_even_direction : rs_normal_even_direction);
	wire [PAYLOAD_BITS - 1:0] rs_take_odd_payload = (response_sample_fast_select ? rs_fast_odd_payload : rs_normal_odd_payload);
	wire rs_take_odd_valid = (response_sample_fast_select ? rs_fast_odd_valid : rs_normal_odd_valid);
	wire rs_take_odd_hit = (response_sample_fast_select ? rs_fast_odd_hit : rs_normal_odd_hit);
	wire [1:0] rs_take_odd_direction = (response_sample_fast_select ? rs_fast_odd_direction : rs_normal_odd_direction);
	always @(posedge clk)
		if (rst) begin
			rs_tag_even_q <= 0;
			rs_tag_odd_q <= 0;
		end
		else if (response_sample_accept) begin
			rs_tag_even_q <= rs_capture_even_tag;
			rs_tag_odd_q <= rs_capture_odd_tag;
		end
	always @(posedge clk)
		if (rst) begin
			rs_active_q <= 0;
			rs_valid_even_q <= 0;
			rs_valid_odd_q <= 0;
			rs_be_q <= 0;
			rs_bo_q <= 0;
			rs_de_q <= 0;
			rs_do_q <= 0;
		end
		else if (response_sample_accept) begin
			rs_active_q <= 1;
			rs_be_q <= rs_capture_be;
			rs_bo_q <= rs_capture_bo;
			rs_de_q <= rs_capture_de;
			rs_do_q <= rs_capture_do;
			rs_payload_even_q <= rs_take_even_payload;
			rs_payload_odd_q <= rs_take_odd_payload;
			rs_valid_even_q <= rs_take_even_valid;
			rs_valid_odd_q <= rs_take_odd_valid;
			rs_direction_even_q <= rs_take_even_direction;
			rs_direction_odd_q <= rs_take_odd_direction;
		end
		else if (rs_active_q) begin
			if (rs_btb_write) begin
				if (!ti[0] && ((ti >> 1) == rs_be_q)) begin
					rs_payload_even_q <= training_payload;
					rs_valid_even_q <= 1;
				end
				if (ti[0] && ((ti >> 1) == rs_bo_q)) begin
					rs_payload_odd_q <= training_payload;
					rs_valid_odd_q <= 1;
				end
			end
			if (rs_bht_write) begin
				if (!td[0] && ((td >> 1) == rs_de_q))
					rs_direction_even_q <= bht_next_even;
				if (td[0] && ((td >> 1) == rs_do_q))
					rs_direction_odd_q <= bht_next_odd;
			end
		end
endmodule
module p3_perf_counters (
	clk,
	rst,
	enable,
	event_pulses,
	issue_second,
	csr_addr,
	csr_rdata,
	csr_known,
	i_hit,
	i_miss,
	d_hit,
	d_miss,
	d_writeback,
	values_flat
);
	parameter DUAL_ISSUE = 0;
	input wire clk;
	input wire rst;
	input wire enable;
	input wire [23:0] event_pulses;
	input wire issue_second;
	input wire [11:0] csr_addr;
	output reg [31:0] csr_rdata;
	output wire csr_known;
	input wire [63:0] i_hit;
	input wire [63:0] i_miss;
	input wire [63:0] d_hit;
	input wire [63:0] d_miss;
	input wire [63:0] d_writeback;
	output wire [1535:0] values_flat;
	wire [63:0] event_count_q [0:18];
	genvar _gv_g_1;
	generate
		for (_gv_g_1 = 0; _gv_g_1 < 19; _gv_g_1 = _gv_g_1 + 1) begin : expose_event
			localparam g = _gv_g_1;
			wire fire = enable && event_pulses[g];
			if ((g == 18) && (DUAL_ISSUE != 0)) begin : pending_dual
				reg [15:0] lo0_q;
				reg [15:0] lo1_q;
				reg [15:0] lo2_q;
				reg [47:0] hi_q;
				reg [47:0] hi1_q;
				reg carry1_q;
				reg carry2_q;
				reg pending_q;
				reg pending_two_q;
				wire [15:0] lo_next = (pending_two_q ? lo2_q : lo1_q);
				wire hi_step = (pending_two_q ? carry2_q : carry1_q);
				always @(posedge clk)
					if (rst) begin
						lo0_q <= 0;
						lo1_q <= 1;
						lo2_q <= 2;
						hi_q <= 0;
						hi1_q <= 1;
						carry1_q <= 0;
						carry2_q <= 0;
						pending_q <= 0;
						pending_two_q <= 0;
					end
					else begin
						pending_q <= fire;
						pending_two_q <= fire && issue_second;
						if (pending_q) begin
							lo0_q <= lo_next;
							lo1_q <= lo_next + 16'd1;
							lo2_q <= lo_next + 16'd2;
							carry1_q <= lo_next == 16'hffff;
							carry2_q <= lo_next >= 16'hfffe;
							if (hi_step) begin
								hi_q <= hi1_q;
								hi1_q <= hi1_q + 48'd1;
							end
						end
					end
				wire [47:0] hi_view = (pending_q && (pending_two_q ? carry2_q : carry1_q) ? hi1_q : hi_q);
				wire [15:0] lo_view = (pending_q ? lo_next : lo0_q);
				assign event_count_q[g] = {hi_view, lo_view};
			end
			else if (((((((((((((((g == 0) || (g == 2)) || (g == 3)) || (g == 4)) || (g == 5)) || (g == 7)) || (g == 8)) || (g == 9)) || (g == 11)) || (g == 12)) || (g == 13)) || (g == 14)) || (g == 15)) || (g == 16)) || (g == 17)) begin : pending_bank
				reg [63:0] raw_count_q;
				reg [63:0] raw_plus_one_q;
				reg pending_q;
				reg [2:0] full_q;
				always @(posedge clk)
					if (rst) begin
						raw_count_q <= 0;
						pending_q <= 0;
					end
					else begin
						pending_q <= fire;
						if (pending_q)
							raw_count_q <= raw_plus_one_q;
					end
				genvar _gv_chunk_1;
				for (_gv_chunk_1 = 0; _gv_chunk_1 < 4; _gv_chunk_1 = _gv_chunk_1 + 1) begin : segmented
					localparam chunk = _gv_chunk_1;
					wire lower_full;
					if (chunk == 0) begin : genblk1
						assign lower_full = 1'b1;
					end
					else begin : genblk1
						assign lower_full = &full_q[chunk - 1:0];
					end
					always @(posedge clk)
						if (rst)
							raw_plus_one_q[chunk * 16+:16] <= (chunk == 0 ? 16'd1 : 16'd0);
						else if (pending_q && lower_full)
							raw_plus_one_q[chunk * 16+:16] <= raw_plus_one_q[chunk * 16+:16] + 16'd1;
					if (chunk < 3) begin : lookahead
						always @(posedge clk)
							if (rst)
								full_q[chunk] <= 0;
							else if (pending_q && lower_full)
								full_q[chunk] <= raw_plus_one_q[chunk * 16+:16] == 16'hfffe;
					end
				end
				assign event_count_q[g] = (pending_q ? raw_plus_one_q : raw_count_q);
			end
			else begin : direct_bank
				reg [63:0] count_q;
				wire add_two = ((g == 18) && (DUAL_ISSUE != 0)) && issue_second;
				reg [2:0] full_q;
				wire low_carry;
				if ((g == 18) && (DUAL_ISSUE != 0)) begin : dual_count
					reg near_full_q;
					wire [15:0] plus_one = count_q[15:0] + 16'd1;
					wire [15:0] plus_two = count_q[15:0] + 16'd2;
					assign low_carry = full_q[0] || (add_two && near_full_q);
					always @(posedge clk)
						if (rst) begin
							count_q[15:0] <= 0;
							full_q[0] <= 0;
							near_full_q <= 0;
						end
						else if (fire) begin
							count_q[15:0] <= (add_two ? plus_two : plus_one);
							full_q[0] <= (add_two ? count_q[15:0] == 16'hfffd : count_q[15:0] == 16'hfffe);
							near_full_q <= (add_two ? count_q[15:0] == 16'hfffc : count_q[15:0] == 16'hfffd);
						end
				end
				else begin : single_count
					assign low_carry = full_q[0];
					always @(posedge clk)
						if (rst) begin
							count_q[15:0] <= 0;
							full_q[0] <= 0;
						end
						else if (fire) begin
							count_q[15:0] <= count_q[15:0] + 16'd1;
							full_q[0] <= count_q[15:0] == 16'hfffe;
						end
				end
				genvar _gv_chunk_2;
				for (_gv_chunk_2 = 1; _gv_chunk_2 < 4; _gv_chunk_2 = _gv_chunk_2 + 1) begin : segmented
					localparam chunk = _gv_chunk_2;
					wire lower_full;
					if (chunk == 1) begin : genblk1
						assign lower_full = low_carry;
					end
					else begin : genblk1
						assign lower_full = low_carry && &full_q[chunk - 1:1];
					end
					always @(posedge clk)
						if (rst)
							count_q[chunk * 16+:16] <= 0;
						else if (fire && lower_full)
							count_q[chunk * 16+:16] <= count_q[chunk * 16+:16] + 16'd1;
					if (chunk < 3) begin : lookahead
						always @(posedge clk)
							if (rst)
								full_q[chunk] <= 0;
							else if (fire && lower_full)
								full_q[chunk] <= count_q[chunk * 16+:16] == 16'hfffe;
					end
				end
				assign event_count_q[g] = count_q;
			end
			assign values_flat[g * 64+:64] = event_count_q[g];
		end
	endgenerate
	assign values_flat[1216+:64] = i_hit;
	assign values_flat[1280+:64] = i_miss;
	assign values_flat[1344+:64] = d_hit;
	assign values_flat[1408+:64] = d_miss;
	assign values_flat[1472+:64] = d_writeback;
	assign csr_known = (csr_addr >= 12'hfc0) && (csr_addr <= 12'hfef);
	wire [31:0] csr_words [0:47];
	wire [31:0] csr_groups [0:7];
	genvar _gv_csr_leaf_1;
	genvar _gv_csr_group_1;
	generate
		for (_gv_csr_leaf_1 = 0; _gv_csr_leaf_1 < 48; _gv_csr_leaf_1 = _gv_csr_leaf_1 + 1) begin : csr_word_decode
			localparam csr_leaf = _gv_csr_leaf_1;
			assign csr_words[csr_leaf] = {32 {csr_addr[5:0] == csr_leaf}} & values_flat[csr_leaf * 32+:32];
		end
		for (_gv_csr_group_1 = 0; _gv_csr_group_1 < 8; _gv_csr_group_1 = _gv_csr_group_1 + 1) begin : csr_word_reduce
			localparam csr_group = _gv_csr_group_1;
			assign csr_groups[csr_group] = ((((csr_words[csr_group * 6] | csr_words[(csr_group * 6) + 1]) | csr_words[(csr_group * 6) + 2]) | csr_words[(csr_group * 6) + 3]) | csr_words[(csr_group * 6) + 4]) | csr_words[(csr_group * 6) + 5];
		end
	endgenerate
	always @(*) begin
		csr_rdata = 32'd0;
		if (csr_known)
			csr_rdata = ((((((csr_groups[0] | csr_groups[1]) | csr_groups[2]) | csr_groups[3]) | csr_groups[4]) | csr_groups[5]) | csr_groups[6]) | csr_groups[7];
	end
endmodule
module p2_frontend_dual (
	clk,
	rst,
	stop,
	redirect_valid,
	redirect_pc,
	fast_redirect,
	fast_pc,
	fast_pc4,
	fast_pc8,
	predict_pc,
	predict_next,
	predict_next1,
	predict_sequential,
	response_predict_pc,
	response_predict_next,
	response_predict_next1,
	response_predict_sequential,
	response_predict_sequential1,
	predict_accept,
	predict_accept_second,
	response_sample_fast_select,
	req_valid,
	req_ready,
	req_addr,
	rsp_valid,
	rsp_ready,
	rsp_data,
	rsp_data_hi,
	rsp_predecode,
	rsp_predecode_hi,
	rsp_error,
	rsp_hi_valid,
	out_valid,
	out_ready,
	out_pc,
	out_insn,
	out_prediction,
	out_error,
	out_sequential,
	out1_sequential,
	out_pair_link,
	out_predecode,
	out1_predecode,
	out1_valid,
	out1_ready,
	out1_pc,
	out1_insn,
	out1_prediction,
	out1_error
);
	parameter [31:0] RESET_PC = 32'h80000000;
	parameter integer FIFO_DEPTH = 4;
	parameter integer RESPONSE_BYPASS = 0;
	parameter integer LINE_BYTES = 32;
	parameter integer DUAL_WORDS = 1;
	parameter integer RESPONSE_PREDECODE = 0;
	input wire clk;
	input wire rst;
	input wire stop;
	input wire redirect_valid;
	input wire [31:0] redirect_pc;
	input wire fast_redirect;
	input wire [31:0] fast_pc;
	input wire [31:0] fast_pc4;
	input wire [31:0] fast_pc8;
	output wire [31:0] predict_pc;
	input wire [31:0] predict_next;
	input wire [31:0] predict_next1;
	input wire predict_sequential;
	output wire [31:0] response_predict_pc;
	input wire [31:0] response_predict_next;
	input wire [31:0] response_predict_next1;
	input wire response_predict_sequential;
	input wire response_predict_sequential1;
	output wire predict_accept;
	output wire predict_accept_second;
	output wire response_sample_fast_select;
	output wire req_valid;
	input wire req_ready;
	output wire [31:0] req_addr;
	input wire rsp_valid;
	output wire rsp_ready;
	input wire [31:0] rsp_data;
	input wire [31:0] rsp_data_hi;
	input wire [6:0] rsp_predecode;
	input wire [6:0] rsp_predecode_hi;
	input wire rsp_error;
	input wire rsp_hi_valid;
	output wire out_valid;
	input wire out_ready;
	output wire [31:0] out_pc;
	output wire [31:0] out_insn;
	output wire [31:0] out_prediction;
	output wire out_error;
	output wire out_sequential;
	output wire out1_sequential;
	output wire out_pair_link;
	output wire [6:0] out_predecode;
	output wire [6:0] out1_predecode;
	output wire out1_valid;
	input wire out1_ready;
	output wire [31:0] out1_pc;
	output wire [31:0] out1_insn;
	output wire [31:0] out1_prediction;
	output wire out1_error;
	localparam integer DEPTH = (FIFO_DEPTH < 8 ? 8 : FIFO_DEPTH);
	localparam integer PTR_BITS = $clog2(DEPTH);
	localparam integer COUNT_BITS = PTR_BITS + 1;
	reg [31:0] offer_pc;
	reg [31:0] pending_pc;
	reg [31:0] pending_prediction;
	reg [31:0] pending_prediction1;
	reg pending_seq0;
	reg pending_fast;
	reg [31:0] pending_pc8;
	reg [31:0] recovery_pc;
	reg [31:0] tail_prediction_q;
	reg pending;
	reg pending_wide;
	reg pending_discard;
	reg offer_discard;
	reg recovery;
	reg held_offer;
	reg [31:0] q_pc [0:DEPTH - 1];
	reg [31:0] q_insn [0:DEPTH - 1];
	reg [31:0] q_prediction [0:DEPTH - 1];
	reg [6:0] q_pre [0:DEPTH - 1];
	reg q_error [0:DEPTH - 1];
	reg q_sequential [0:DEPTH - 1];
	reg q_link [0:DEPTH - 1];
	reg [31:0] h0_insn;
	reg [31:0] h1_insn;
	reg h0_error;
	reg h1_error;
	reg h0_seq;
	reg h1_seq;
	reg h_link;
	reg [6:0] h0_pre;
	reg [6:0] h1_pre;
	reg [PTR_BITS - 1:0] rd_ptr;
	reg [PTR_BITS - 1:0] wr_ptr;
	reg [COUNT_BITS - 1:0] count;
	wire [PTR_BITS - 1:0] rd_next = rd_ptr + 1'b1;
	wire [PTR_BITS - 1:0] wr_next = wr_ptr + 1'b1;
	wire [PTR_BITS - 1:0] wr_prev = wr_ptr - 1'b1;
	localparam integer POWER_OF_TWO_LINE = (LINE_BYTES >= 4) && ((LINE_BYTES & (LINE_BYTES - 1)) == 0);
	wire same_line = (POWER_OF_TWO_LINE ? (offer_pc & (LINE_BYTES - 1)) < (LINE_BYTES - 4) : (offer_pc & ~(LINE_BYTES - 1)) == ((offer_pc + 32'd4) & ~(LINE_BYTES - 1)));
	wire offer_wide = ((DUAL_WORDS != 0) && predict_sequential) && same_line;
	assign predict_pc = offer_pc;
	assign response_predict_pc = pending_pc;
	wire returning = rsp_valid && rsp_ready;
	assign req_valid = (!stop || held_offer) && (!pending || returning);
	wire early_redirect = ((fast_redirect && !held_offer) && !stop) && (!pending || returning);
	assign response_sample_fast_select = early_redirect;
	wire fast_wide = (DUAL_WORDS != 0) && (POWER_OF_TWO_LINE ? (fast_pc & (LINE_BYTES - 1)) < (LINE_BYTES - 4) : (fast_pc & ~(LINE_BYTES - 1)) == (fast_pc4 & ~(LINE_BYTES - 1)));
	assign req_addr = (early_redirect ? fast_pc : offer_pc);
	wire accepting = req_valid && req_ready;
	wire push0 = ((returning && !pending_discard) && !redirect_valid) && !stop;
	wire response_use = (pending_fast && !pending_discard) && !rsp_error;
	wire response_seq0 = (response_use ? response_predict_sequential : pending_seq0);
	wire response_wide = pending_wide && (!response_use || response_seq0);
	wire push1 = (push0 && response_wide) && rsp_hi_valid;
	wire response_seq1 = (response_use ? response_predict_sequential1 : pending_prediction1 == pending_pc8);
	wire response_repair = (push0 && response_use) && (!response_seq0 || (push1 && !response_seq1));
	assign predict_accept = (((accepting && !offer_discard) && !redirect_valid) && !stop) && !response_repair;
	assign predict_accept_second = predict_accept && offer_wide;
	wire [31:0] predicted_after = (offer_wide ? predict_next1 : predict_next);
	assign out_valid = count != 0;
	assign out_pc = q_pc[rd_ptr];
	assign out_insn = h0_insn;
	assign out_prediction = q_prediction[rd_ptr];
	assign out_error = h0_error;
	assign out_sequential = h0_seq;
	assign out1_valid = count >= 2;
	assign out1_pc = q_pc[rd_next];
	assign out1_insn = h1_insn;
	assign out1_prediction = q_prediction[rd_next];
	assign out1_error = h1_error;
	assign out1_sequential = h1_seq;
	assign out_pair_link = h_link;
	assign out_predecode = h0_pre;
	assign out1_predecode = h1_pre;
	wire pop0 = out_valid && out_ready;
	wire pop1 = (out1_valid && out1_ready) && pop0;
	wire [1:0] pop_n = {1'b0, pop0} + {1'b0, pop1};
	wire credit_one = count < DEPTH;
	wire credit_two = count <= (DEPTH - 2);
	assign rsp_ready = pending && (pending_discard || (pending_wide ? credit_two : credit_one));
	wire [31:0] response_pred0 = (response_use ? response_predict_next : pending_prediction);
	wire [31:0] response_pred1 = (response_use ? response_predict_next1 : pending_prediction1);
	wire [31:0] response_after = (push1 ? response_pred1 : response_pred0);
	wire [1:0] push_n = {1'b0, push0} + {1'b0, push1};
	always @(posedge clk)
		if (rst) begin
			offer_pc <= RESET_PC;
			pending_pc <= 0;
			pending_prediction <= 0;
			pending_prediction1 <= 0;
			recovery_pc <= 0;
			pending_seq0 <= 0;
			pending_pc8 <= 0;
			pending <= 0;
			pending_wide <= 0;
			pending_discard <= 0;
			pending_fast <= 0;
			offer_discard <= 0;
			recovery <= 0;
			held_offer <= 0;
			rd_ptr <= 0;
			wr_ptr <= 0;
			count <= 0;
		end
		else begin
			held_offer <= req_valid && !req_ready;
			if (returning) begin
				pending <= 0;
				pending_fast <= 0;
			end
			if (accepting) begin
				pending <= 1;
				pending_pc <= (early_redirect ? fast_pc : offer_pc);
				pending_fast <= early_redirect;
				pending_prediction <= (early_redirect ? fast_pc4 : predict_next);
				pending_prediction1 <= (early_redirect ? fast_pc8 : predict_next1);
				pending_seq0 <= early_redirect || predict_sequential;
				pending_pc8 <= (early_redirect ? fast_pc8 : offer_pc + 32'd8);
				pending_wide <= (early_redirect ? fast_wide : offer_wide);
				pending_discard <= (early_redirect ? 1'b0 : (offer_discard || redirect_valid) || stop);
				offer_pc <= (early_redirect ? (fast_wide ? fast_pc8 : fast_pc4) : (recovery ? recovery_pc : (stop ? offer_pc : predicted_after)));
				offer_discard <= 0;
				recovery <= 0;
			end
			if (response_repair) begin
				if (accepting) begin
					pending_discard <= 1;
					pending_fast <= 0;
					offer_pc <= response_after;
					offer_discard <= 0;
					recovery <= 0;
				end
				else if (req_valid && !req_ready) begin
					offer_discard <= 1;
					recovery <= 1;
					recovery_pc <= response_after;
				end
				else begin
					offer_pc <= response_after;
					offer_discard <= 0;
					recovery <= 0;
				end
			end
			if (((stop && pending) && !pending_discard) && !redirect_valid) begin
				if (!returning)
					pending_discard <= 1;
				offer_pc <= pending_pc;
			end
			if (pop0)
				rd_ptr <= rd_ptr + pop_n;
			if (push0)
				wr_ptr <= wr_ptr + push_n;
			count <= (count + push_n) - pop_n;
			if (redirect_valid) begin
				rd_ptr <= 0;
				wr_ptr <= 0;
				count <= 0;
				if (pending && !returning)
					pending_discard <= 1;
				if (early_redirect) begin
					if (!req_ready) begin
						offer_pc <= redirect_pc;
						offer_discard <= 0;
						recovery <= 0;
					end
				end
				else if (req_valid && !req_ready) begin
					offer_discard <= 1;
					recovery <= 1;
					recovery_pc <= redirect_pc;
				end
				else begin
					offer_pc <= redirect_pc;
					offer_discard <= 0;
					recovery <= 0;
				end
			end
		end
	wire payload_write0 = (pending && rsp_valid) && (pending_wide ? credit_two : credit_one);
	wire payload_write1 = (payload_write0 && response_wide) && rsp_hi_valid;
	wire data_write1 = (payload_write0 && pending_wide) && rsp_hi_valid;
	wire seq_new0 = response_seq0;
	wire seq_new1 = response_seq1;
	wire link_new0 = pending_pc == tail_prediction_q;
	wire link_new1 = response_seq0;
	function automatic [6:0] predecode;
		input [31:0] insn;
		reg [6:0] op;
		reg [2:0] f3;
		reg [6:0] f7;
		begin
			op = insn[6:0];
			f3 = insn[14:12];
			f7 = insn[31:25];
			predecode[0] = (((op == 7'h37) || (op == 7'h17)) || ((op == 7'h13) && ((((f3 != 3'b001) && (f3 != 3'b101)) || ((f3 == 3'b001) && (f7 == 0))) || ((f3 == 3'b101) && ((f7 == 0) || (f7 == 7'h20)))))) || ((op == 7'h33) && ((f7 == 0) || ((f7 == 7'h20) && ((f3 == 0) || (f3 == 5)))));
			predecode[1] = ((((((op == 7'h37) || (op == 7'h17)) || (op == 7'h13)) || (op == 7'h33)) || (op == 7'h03)) || (op == 7'h23)) || (op == 7'h63);
			predecode[2] = ((op != 7'h23) && (op != 7'h63)) && (insn[11:7] != 0);
			predecode[3] = ((op == 7'h13) || (op == 7'h33)) || (op == 7'h63);
			predecode[4] = (op == 7'h33) || (op == 7'h63);
			predecode[5] = ((op == 7'h63) && (f3[2] || (f3[2:1] == 2'b00))) && !insn[8];
			predecode[6] = op == 7'h63;
		end
	endfunction
	(* syn_keep = 1 *) wire [6:0] rsp_pre0 = (RESPONSE_PREDECODE != 0 ? rsp_predecode : predecode(rsp_data));
	(* syn_keep = 1 *) wire [6:0] rsp_pre1 = (RESPONSE_PREDECODE != 0 ? rsp_predecode_hi : predecode(rsp_data_hi));
	wire [127:0] cand_insn;
	wire [3:0] cand_error;
	wire [3:0] cand_seq;
	wire [3:0] cand_link;
	wire [27:0] cand_pre;
	genvar _gv_hk_1;
	generate
		for (_gv_hk_1 = 0; _gv_hk_1 < 4; _gv_hk_1 = _gv_hk_1 + 1) begin : head_candidate
			localparam hk = _gv_hk_1;
			wire [PTR_BITS - 1:0] idx = rd_ptr + hk;
			wire w0 = payload_write0 && (idx == wr_ptr);
			wire w1 = payload_write1 && (idx == wr_next);
			wire d1 = data_write1 && (idx == wr_next);
			wire l0 = payload_write0 && (idx == wr_prev);
			wire l1 = payload_write1 && (idx == wr_ptr);
			wire [31:0] insn = (w0 ? rsp_data : (d1 ? rsp_data_hi : q_insn[idx]));
			assign cand_insn[hk * 32+:32] = insn;
			assign cand_error[hk] = (w0 ? rsp_error : (w1 ? 1'b0 : q_error[idx]));
			assign cand_seq[hk] = (w0 ? seq_new0 : (w1 ? seq_new1 : q_sequential[idx]));
			assign cand_link[hk] = (l0 ? link_new0 : (l1 ? link_new1 : q_link[idx]));
			assign cand_pre[hk * 7+:7] = (w0 ? rsp_pre0 : (d1 ? rsp_pre1 : q_pre[idx]));
		end
	endgenerate
	always @(posedge clk)
		case (pop_n)
			2'd0: begin
				h0_insn <= cand_insn[0+:32];
				h0_error <= cand_error[0];
				h0_seq <= cand_seq[0];
				h0_pre <= cand_pre[0+:7];
				h1_insn <= cand_insn[32+:32];
				h1_error <= cand_error[1];
				h1_seq <= cand_seq[1];
				h1_pre <= cand_pre[7+:7];
				h_link <= cand_link[0];
			end
			2'd1: begin
				h0_insn <= cand_insn[32+:32];
				h0_error <= cand_error[1];
				h0_seq <= cand_seq[1];
				h0_pre <= cand_pre[7+:7];
				h1_insn <= cand_insn[64+:32];
				h1_error <= cand_error[2];
				h1_seq <= cand_seq[2];
				h1_pre <= cand_pre[14+:7];
				h_link <= cand_link[1];
			end
			default: begin
				h0_insn <= cand_insn[64+:32];
				h0_error <= cand_error[2];
				h0_seq <= cand_seq[2];
				h0_pre <= cand_pre[14+:7];
				h1_insn <= cand_insn[96+:32];
				h1_error <= cand_error[3];
				h1_seq <= cand_seq[3];
				h1_pre <= cand_pre[21+:7];
				h_link <= cand_link[2];
			end
		endcase
	always @(posedge clk)
		if (rst)
			tail_prediction_q <= 0;
		else if (push0)
			tail_prediction_q <= (push1 ? response_pred1 : response_pred0);
	always @(posedge clk)
		if (!rst) begin
			if (payload_write0) begin
				q_link[wr_prev] <= link_new0;
				q_pc[wr_ptr] <= pending_pc;
				q_insn[wr_ptr] <= rsp_data;
				q_pre[wr_ptr] <= rsp_pre0;
				q_prediction[wr_ptr] <= response_pred0;
				q_error[wr_ptr] <= rsp_error;
				q_sequential[wr_ptr] <= seq_new0;
			end
			if (data_write1) begin
				q_insn[wr_next] <= rsp_data_hi;
				q_pre[wr_next] <= rsp_pre1;
			end
			if (payload_write1) begin
				q_link[wr_ptr] <= link_new1;
				q_pc[wr_next] <= pending_pc + 32'd4;
				q_prediction[wr_next] <= response_pred1;
				q_error[wr_next] <= 1'b0;
				q_sequential[wr_next] <= seq_new1;
			end
		end
endmodule
module p2_load_eq_narrow (
	data,
	other,
	offset,
	funct3,
	equal
);
	input wire [31:0] data;
	input wire [31:0] other;
	input wire [1:0] offset;
	input wire [2:0] funct3;
	output wire equal;
	wire [7:0] byte_value = data[{offset, 3'b000}+:8];
	wire [15:0] half_value = (offset[1] ? data[31:16] : data[15:0]);
	(* syn_keep = 1 *) wire [2:0] byte_groups = {byte_value[7:6] == other[7:6], byte_value[5:3] == other[5:3], byte_value[2:0] == other[2:0]};
	(* syn_keep = 1 *) wire [5:0] half_groups = {half_value[15] == other[15], half_value[14:12] == other[14:12], half_value[11:9] == other[11:9], half_value[8:6] == other[8:6], half_value[5:3] == other[5:3], half_value[2:0] == other[2:0]};
	(* syn_keep = 1 *) wire byte_upper_zero = other[31:8] == 24'b000000000000000000000000;
	(* syn_keep = 1 *) wire byte_upper_ones = &other[31:8];
	(* syn_keep = 1 *) wire half_upper_zero = other[31:16] == 16'b0000000000000000;
	(* syn_keep = 1 *) wire half_upper_ones = &other[31:16];
	wire byte_signed = &byte_groups && (byte_value[7] ? byte_upper_ones : byte_upper_zero);
	wire half_signed = &half_groups && (half_value[15] ? half_upper_ones : half_upper_zero);
	wire byte_unsigned = &byte_groups && byte_upper_zero;
	wire half_unsigned = &half_groups && half_upper_zero;
	(* syn_keep = 1 *) wire [10:0] word_groups;
	genvar _gv_chunk_1;
	generate
		for (_gv_chunk_1 = 0; _gv_chunk_1 < 10; _gv_chunk_1 = _gv_chunk_1 + 1) begin : word_compare
			localparam chunk = _gv_chunk_1;
			assign word_groups[chunk] = data[chunk * 3+:3] == other[chunk * 3+:3];
		end
	endgenerate
	assign word_groups[10] = data[31:30] == other[31:30];
	wire supported = ((((funct3 == 0) || (funct3 == 1)) || (funct3 == 2)) || (funct3 == 4)) || (funct3 == 5);
	assign equal = ((((((funct3 == 0) && byte_signed) || ((funct3 == 1) && half_signed)) || ((funct3 == 2) && &word_groups)) || ((funct3 == 4) && byte_unsigned)) || ((funct3 == 5) && half_unsigned)) || (!supported && (other == 0));
endmodule
module p2_branch_predicate (
	other_a,
	other_b,
	load,
	take_a,
	take_b,
	kind,
	equal,
	high_lt,
	high_equal,
	lower_lt,
	dir_lower_lt,
	dir_lower_ge
);
	input wire [31:0] other_a;
	input wire [31:0] other_b;
	input wire [31:0] load;
	input wire take_a;
	input wire take_b;
	input wire [2:0] kind;
	output wire equal;
	output wire high_lt;
	output wire high_equal;
	output wire lower_lt;
	output wire dir_lower_lt;
	output wire dir_lower_ge;
	wire [4:0] flags [0:2];
	genvar _gv_c_1;
	genvar _gv_n_1;
	generate
		for (_gv_c_1 = 0; _gv_c_1 < 3; _gv_c_1 = _gv_c_1 + 1) begin : candidates
			localparam c = _gv_c_1;
			wire [31:0] a = (c == 1 ? load : other_a);
			wire [31:0] b = (c == 2 ? load : other_b);
			(* syn_keep = 1 *) wire [10:0] eq3;
			(* syn_keep = 1 *) wire [7:0] eq4;
			(* syn_keep = 1 *) wire [7:0] lt4;
			for (_gv_n_1 = 0; _gv_n_1 < 10; _gv_n_1 = _gv_n_1 + 1) begin : eq_groups
				localparam n = _gv_n_1;
				assign eq3[n] = a[n * 3+:3] == b[n * 3+:3];
			end
			assign eq3[10] = a[31:30] == b[31:30];
			for (_gv_n_1 = 0; _gv_n_1 < 8; _gv_n_1 = _gv_n_1 + 1) begin : ordered_groups
				localparam n = _gv_n_1;
				assign eq4[n] = a[n * 4+:4] == b[n * 4+:4];
				assign lt4[n] = a[n * 4+:4] < b[n * 4+:4];
			end
			wire hi_unsigned_lt = ((lt4[7] || (eq4[7] && lt4[6])) || (&eq4[7:6] && lt4[5])) || (&eq4[7:5] && lt4[4]);
			wire lo_unsigned_lt = ((lt4[3] || (eq4[3] && lt4[2])) || (&eq4[3:2] && lt4[1])) || (&eq4[3:1] && lt4[0]);
			wire hi_signed_lt = (a[31] != b[31] ? a[31] : hi_unsigned_lt);
			assign flags[c] = {&eq3, hi_unsigned_lt, hi_signed_lt, &eq4[7:4], lo_unsigned_lt};
		end
	endgenerate
	wire [4:0] selected = (take_a && take_b ? 5'b10010 : (take_a ? flags[1] : (take_b ? flags[2] : flags[0])));
	assign equal = selected[4];
	assign high_lt = (kind[1] ? selected[3] : selected[2]);
	assign high_equal = selected[1];
	assign lower_lt = selected[0];
	assign dir_lower_lt = (((kind == 0) && equal) || ((kind == 1) && !equal)) || (kind[2] && ((high_lt || high_equal) ^ kind[0]));
	assign dir_lower_ge = (((kind == 0) && equal) || ((kind == 1) && !equal)) || (kind[2] && (high_lt ^ kind[0]));
endmodule
module p2_subword_eq (
	data,
	other,
	offset,
	funct3,
	equal
);
	input wire [31:0] data;
	input wire [31:0] other;
	input wire [1:0] offset;
	input wire [2:0] funct3;
	output wire equal;
	wire byte_zero = other[31:8] == 0;
	wire byte_ones = &other[31:8];
	wire half_zero = other[31:16] == 0;
	wire half_ones = &other[31:16];
	wire byte_ok = ((funct3 == 0) && (other[7] ? byte_ones : byte_zero)) || ((funct3 == 4) && byte_zero);
	wire half_ok = ((funct3 == 1) && (other[15] ? half_ones : half_zero)) || ((funct3 == 5) && half_zero);
	wire [3:0] byte_matches;
	wire [1:0] half_matches;
	genvar _gv_b_1;
	generate
		for (_gv_b_1 = 0; _gv_b_1 < 4; _gv_b_1 = _gv_b_1 + 1) begin : byte_lanes
			localparam b = _gv_b_1;
			(* syn_keep = 1 *) wire [2:0] eq3 = {data[(b * 8) + 6+:2] == other[6+:2], data[(b * 8) + 3+:3] == other[3+:3], data[b * 8+:3] == other[0+:3]};
			assign byte_matches[b] = (&eq3 && byte_ok) && (offset == b);
		end
	endgenerate
	genvar _gv_h_1;
	generate
		for (_gv_h_1 = 0; _gv_h_1 < 2; _gv_h_1 = _gv_h_1 + 1) begin : half_lanes
			localparam h = _gv_h_1;
			(* syn_keep = 1 *) wire [5:0] eq3 = {data[(h * 16) + 15] == other[15], data[(h * 16) + 12+:3] == other[12+:3], data[(h * 16) + 9+:3] == other[9+:3], data[(h * 16) + 6+:3] == other[6+:3], data[(h * 16) + 3+:3] == other[3+:3], data[h * 16+:3] == other[0+:3]};
			assign half_matches[h] = (&eq3 && half_ok) && (offset[1] == h);
		end
	endgenerate
	wire supported = (((funct3 == 0) || (funct3 == 1)) || (funct3 == 4)) || (funct3 == 5);
	assign equal = (|byte_matches || |half_matches) || (!supported && (other == 0));
endmodule
module p2_load_format_predecoded (
	data,
	selectors,
	result
);
	input wire [31:0] data;
	input wire [12:0] selectors;
	output wire [31:0] result;
	wire byte_negative = (((data[7] & selectors[7]) | (data[15] & selectors[8])) | (data[23] & selectors[9])) | (data[31] & selectors[10]);
	assign result[7:0] = (((data[7:0] & {8 {selectors[0]}}) | (data[15:8] & {8 {selectors[1]}})) | (data[23:16] & {8 {selectors[2]}})) | (data[31:24] & {8 {selectors[3]}});
	assign result[15:8] = ((data[15:8] & {8 {selectors[4]}}) | (data[31:24] & {8 {selectors[5]}})) | {8 {byte_negative}};
	(* syn_keep = 1 *) wire sign15_select = selectors[8] | selectors[11];
	(* syn_keep = 1 *) wire sign31_select = selectors[10] | selectors[12];
	(* syn_keep = 1 *) wire upper_sign_low = (data[7] & selectors[7]) | (data[15] & sign15_select);
	(* syn_keep = 1 *) wire upper_sign_high = (data[23] & selectors[9]) | (data[31] & sign31_select);
	(* syn_keep = 1 *) wire [15:0] upper_result = ((data[31:16] & {16 {selectors[6]}}) | {16 {upper_sign_low}}) | {16 {upper_sign_high}};
	assign result[31:16] = upper_result;
endmodule

// rtl/cpu/fn_soc_ext.v
module p2_soc (
	clk,
	rst,
	ext_req_valid,
	ext_req_ready,
	ext_req_addr,
	ext_req_write,
	ext_req_be,
	ext_req_wdata,
	ext_rsp_valid,
	ext_rsp_ready,
	ext_rsp_rdata,
	ext_rsp_error,
	ext_irq,
	perf_cache_flat,
	i_req_valid,
	i_req_ready,
	i_req_addr,
	i_rsp_valid,
	i_rsp_ready,
	i_rsp_data,
	i_rsp_error,
	i_rsp_data_hi,
	i_rsp_hi_valid,
	i_rsp_predecode,
	i_rsp_predecode_hi,
	d_req_valid,
	d_req_ready,
	d_req_addr,
	d_req_write,
	d_req_be,
	d_req_wdata,
	d_rsp_valid,
	d_rsp_ready,
	d_rsp_data,
	d_rsp_error,
	irq_software_in,
	irq_timer_in,
	irq_external_in,
	fatal_error,
	run_stop,
	data_idle,
	machine_cycle,
	machine_retired,
	fence_i_valid,
	fence_i_ready,
	fence_i_done,
	fence_i_error,
	trace_irq_valid,
	trace_irq_pc,
	trace_irq_cause,
	trace_csr_valid,
	trace_csr_read,
	trace_csr_write,
	trace_csr_addr,
	trace_csr_rdata,
	trace_csr_wdata,
	trace_valid,
	trace_trap,
	trace_valid1,
	trace_pc1,
	trace_insn1,
	trace_rd1,
	trace_wdata1,
	trace_pc,
	trace_insn,
	trace_rd,
	trace_wdata,
	trace_cause,
	trace_tval,
	trace_mem_valid,
	trace_mem_write,
	trace_mem_addr,
	trace_mem_wdata,
	trace_mem_rdata,
	trace_mem_be,
	halted,
	uart_tx,
	gpio_out,
	mon_d_req_valid,
	mon_d_req_ready,
	mon_d_req_write,
	mon_d_req_addr,
	mon_d_req_wdata,
	mon_d_req_be,
	mon_d_rsp_valid,
	mon_d_rsp_ready,
	mon_d_rsp_error,
	mon_d_rsp_data,
	mon_p4_enabled,
	mon_p4_busy,
	mon_p4_result_valid,
	mon_p4_pending,
	mon_p4_enable,
	mon_p4_irq,
	mon_p4_start,
	mon_p4_complete,
	mon_p4_soft_reset,
	mon_p4_rsp_valid,
	mon_p4_generation,
	mon_p4_submit_id,
	mon_p4_done_id,
	mon_p4_result,
	mon_p4_length,
	count_cycle,
	count_retired,
	count_if_wait,
	count_data_wait,
	count_load_use,
	count_redirect,
	count_reads,
	count_writes
);
	parameter [31:0] RESET_PC = 32'h80018000;
	parameter MACHINE_MODE = 0;
	parameter BP_ENABLED = 0;
	parameter LEGACY_CORE = 0;
	parameter FIFO_DEPTH = 2;
	parameter RESPONSE_BYPASS = 0;
	parameter BTB_ENTRIES = 64;
	parameter BHT_ENTRIES = 256;
	parameter RAS_DEPTH = 0;
	parameter EARLY_LSU = 0;
	parameter HW_MUL = 0;
	parameter ACCEL_ENABLE = 0;
	parameter IFETCH_DUAL_WORDS = 1;
	parameter IFETCH_LINE_BYTES = 32;
	parameter IFETCH_PREDECODE = 0;
	parameter [31:0] ACCEL_BASE = 32'h10003000;
	parameter ACCEL_EXTERNAL = 0;
	input wire clk;
	input wire rst;
	output wire ext_req_valid;
	input wire ext_req_ready;
	output wire [31:0] ext_req_addr;
	output wire ext_req_write;
	output wire [3:0] ext_req_be;
	output wire [31:0] ext_req_wdata;
	input wire ext_rsp_valid;
	output wire ext_rsp_ready;
	input wire [31:0] ext_rsp_rdata;
	input wire ext_rsp_error;
	input wire ext_irq;
	input wire [319:0] perf_cache_flat;
	output wire i_req_valid;
	input wire i_req_ready;
	output wire [31:0] i_req_addr;
	input wire i_rsp_valid;
	output wire i_rsp_ready;
	input wire [31:0] i_rsp_data;
	input wire i_rsp_error;
	input wire [31:0] i_rsp_data_hi;
	input wire i_rsp_hi_valid;
	input wire [6:0] i_rsp_predecode;
	input wire [6:0] i_rsp_predecode_hi;
	output wire d_req_valid;
	input wire d_req_ready;
	output wire [31:0] d_req_addr;
	output wire d_req_write;
	output wire [3:0] d_req_be;
	output wire [31:0] d_req_wdata;
	input wire d_rsp_valid;
	output wire d_rsp_ready;
	input wire [31:0] d_rsp_data;
	input wire d_rsp_error;
	input wire irq_software_in;
	input wire irq_timer_in;
	input wire irq_external_in;
	input wire fatal_error;
	input wire run_stop;
	output wire data_idle;
	output wire [63:0] machine_cycle;
	output wire [63:0] machine_retired;
	output wire fence_i_valid;
	input wire fence_i_ready;
	input wire fence_i_done;
	input wire fence_i_error;
	output wire trace_irq_valid;
	output wire [31:0] trace_irq_pc;
	output wire [31:0] trace_irq_cause;
	output wire trace_csr_valid;
	output wire trace_csr_read;
	output wire trace_csr_write;
	output wire [11:0] trace_csr_addr;
	output wire [31:0] trace_csr_rdata;
	output wire [31:0] trace_csr_wdata;
	output wire trace_valid;
	output wire trace_trap;
	output wire trace_valid1;
	output wire [31:0] trace_pc1;
	output wire [31:0] trace_insn1;
	output wire [4:0] trace_rd1;
	output wire [31:0] trace_wdata1;
	output wire [31:0] trace_pc;
	output wire [31:0] trace_insn;
	output wire [4:0] trace_rd;
	output wire [31:0] trace_wdata;
	output wire [31:0] trace_cause;
	output wire [31:0] trace_tval;
	output wire trace_mem_valid;
	output wire trace_mem_write;
	output wire [31:0] trace_mem_addr;
	output wire [31:0] trace_mem_wdata;
	output wire [31:0] trace_mem_rdata;
	output wire [3:0] trace_mem_be;
	output wire halted;
	output wire uart_tx;
	output wire [31:0] gpio_out;
	output wire mon_d_req_valid;
	output wire mon_d_req_ready;
	output wire mon_d_req_write;
	output wire [31:0] mon_d_req_addr;
	output wire [31:0] mon_d_req_wdata;
	output wire [3:0] mon_d_req_be;
	output wire mon_d_rsp_valid;
	output wire mon_d_rsp_ready;
	output wire mon_d_rsp_error;
	output wire [31:0] mon_d_rsp_data;
	output wire mon_p4_enabled;
	output wire mon_p4_busy;
	output wire mon_p4_result_valid;
	output wire mon_p4_pending;
	output wire mon_p4_enable;
	output wire mon_p4_irq;
	output wire mon_p4_start;
	output wire mon_p4_complete;
	output wire mon_p4_soft_reset;
	output wire mon_p4_rsp_valid;
	output wire [31:0] mon_p4_generation;
	output wire [31:0] mon_p4_submit_id;
	output wire [31:0] mon_p4_done_id;
	output wire [31:0] mon_p4_result;
	output wire [31:0] mon_p4_length;
	output wire [63:0] count_cycle;
	output wire [63:0] count_retired;
	output wire [63:0] count_if_wait;
	output wire [63:0] count_data_wait;
	output wire [63:0] count_load_use;
	output wire [63:0] count_redirect;
	output wire [63:0] count_reads;
	output wire [63:0] count_writes;
	wire cqv;
	wire cqr;
	wire cqw;
	wire crv;
	wire crr;
	wire cre;
	wire [31:0] cqa;
	wire [31:0] cqd;
	wire [31:0] crd;
	wire [3:0] cqb;
	assign mon_d_req_valid = cqv;
	assign mon_d_req_ready = cqr;
	assign mon_d_req_write = cqw;
	assign mon_d_req_addr = cqa;
	assign mon_d_req_wdata = cqd;
	assign mon_d_req_be = cqb;
	assign mon_d_rsp_valid = crv;
	assign mon_d_rsp_ready = crr;
	assign mon_d_rsp_error = cre;
	assign mon_d_rsp_data = crd;
	wire pqv;
	wire pqr;
	wire prv;
	wire prr;
	wire pre;
	wire [31:0] prd;
	wire aqv;
	wire aqr;
	wire arv;
	wire arr;
	wire are;
	wire accel_irq;
	wire [31:0] ard;
	localparam [1:0] ROUTE_RAM = 2'd0;
	localparam [1:0] ROUTE_PERIPH = 2'd1;
	localparam [1:0] ROUTE_ACCEL = 2'd2;
	reg pending;
	reg terminal_response;
	reg mmio_valid;
	reg [31:0] mmio_addr_q;
	reg [31:0] mmio_wdata_q;
	reg [3:0] mmio_be_q;
	reg mmio_write_q;
	reg [1:0] route;
	wire select_periph = (((cqa & 32'hfffff000) == 32'h10000000) || ((cqa & 32'hfffff000) == 32'h10001000)) || ((cqa & 32'hfffff000) == 32'h10002000);
	// Full pose window belongs only to the external accelerator configuration.
	// Preserve the legacy 4 KiB window and all 32 address bits downstream.
	wire select_accel = (ACCEL_ENABLE != 0) &&
		(((cqa & 32'hfffff000) == ACCEL_BASE) ||
		 ((ACCEL_EXTERNAL != 0) && (cqa[31:15] == 17'h02001)));
	wire available = !pending || (crv && crr);
	wire select_mmio = select_periph || select_accel;
	wire mmio_target_ready = (route == ROUTE_PERIPH ? pqr : aqr);
	assign pqv = mmio_valid && (route == ROUTE_PERIPH);
	assign aqv = mmio_valid && (route == ROUTE_ACCEL);
	assign d_req_valid = ((cqv && !select_periph) && !select_accel) && available;
	assign cqr = available && (select_mmio ? !mmio_valid : d_req_ready);
	assign d_req_addr = cqa;
	assign d_req_write = cqw;
	assign d_req_be = cqb;
	assign d_req_wdata = cqd;
	assign crv = pending && (route == ROUTE_PERIPH ? prv : (route == ROUTE_ACCEL ? arv : d_rsp_valid));
	assign crd = (route == ROUTE_PERIPH ? prd : (route == ROUTE_ACCEL ? ard : d_rsp_data));
	assign cre = (route == ROUTE_PERIPH ? pre : (route == ROUTE_ACCEL ? are : d_rsp_error));
	assign prr = (pending && (route == ROUTE_PERIPH)) && crr;
	assign arr = (pending && (route == ROUTE_ACCEL)) && crr;
	assign d_rsp_ready = (pending && (route == ROUTE_RAM)) && crr;
	always @(posedge clk)
		if (rst) begin
			pending <= 0;
			route <= ROUTE_RAM;
			terminal_response <= 0;
		end
		else begin
			if (crv && crr)
				pending <= 0;
			if (cqv && cqr) begin
				pending <= 1;
				route <= (select_periph ? ROUTE_PERIPH : (select_accel ? ROUTE_ACCEL : ROUTE_RAM));
				terminal_response <= ((cqa == 32'h20000000) && cqw) && (cqb == 4'hf);
			end
		end
	always @(posedge clk)
		if (rst)
			mmio_valid <= 0;
		else begin
			if (mmio_valid && mmio_target_ready)
				mmio_valid <= 0;
			if ((cqv && cqr) && select_mmio)
				mmio_valid <= 1;
			if (!mmio_valid) begin
				mmio_addr_q <= cqa;
				mmio_wdata_q <= cqd;
				mmio_be_q <= cqb;
				mmio_write_q <= cqw;
			end
		end
	assign mon_p4_enabled = ACCEL_ENABLE != 0;
	assign mon_p4_irq = accel_irq;
	assign mon_p4_rsp_valid = arv;
	generate
		if ((ACCEL_ENABLE != 0) && (ACCEL_EXTERNAL != 0)) begin : external_accel
			assign ext_req_valid = aqv;
			assign aqr = ext_req_ready;
			assign ext_req_addr = mmio_addr_q;
			assign ext_req_write = mmio_write_q;
			assign ext_req_be = mmio_be_q;
			assign ext_req_wdata = mmio_wdata_q;
			assign arv = ext_rsp_valid;
			assign ext_rsp_ready = arr;
			assign ard = ext_rsp_rdata;
			assign are = ext_rsp_error;
			assign accel_irq = ext_irq;
			assign mon_p4_busy = 0;
			assign mon_p4_result_valid = 0;
			assign mon_p4_pending = 0;
			assign mon_p4_enable = 0;
			assign mon_p4_start = 0;
			assign mon_p4_complete = 0;
			assign mon_p4_soft_reset = 0;
			assign mon_p4_generation = 0;
			assign mon_p4_submit_id = 0;
			assign mon_p4_done_id = 0;
			assign mon_p4_result = 0;
			assign mon_p4_length = 0;
		end
		else if (ACCEL_ENABLE != 0) begin : accelerator
			wire unused_ext = ^{ext_req_ready, ext_rsp_valid, ext_rsp_rdata, ext_rsp_error, ext_irq};
			assign ext_req_valid = 0;
			assign ext_req_addr = 0;
			assign ext_req_write = 0;
			assign ext_req_be = 0;
			assign ext_req_wdata = 0;
			assign ext_rsp_ready = 0;
			p4_dot_mmio #(.BASE_ADDR(ACCEL_BASE)) dot(
				.clk(clk),
				.rst(rst),
				.req_valid(aqv),
				.req_ready(aqr),
				.req_addr(mmio_addr_q),
				.req_write(mmio_write_q),
				.req_be(mmio_be_q),
				.req_wdata(mmio_wdata_q),
				.rsp_valid(arv),
				.rsp_ready(arr),
				.rsp_rdata(ard),
				.rsp_error(are),
				.irq_o(accel_irq),
				.busy_o(mon_p4_busy),
				.result_valid_o(mon_p4_result_valid),
				.pending_o(mon_p4_pending),
				.intr_enable_o(mon_p4_enable),
				.start_o(mon_p4_start),
				.complete_o(mon_p4_complete),
				.soft_reset_o(mon_p4_soft_reset),
				.generation_o(mon_p4_generation),
				.submit_id_o(mon_p4_submit_id),
				.done_id_o(mon_p4_done_id),
				.result_o(mon_p4_result),
				.length_o(mon_p4_length)
			);
		end
		else begin : no_accelerator
			wire unused_disabled_accel = ^{aqv, arr};
			wire unused_ext = ^{ext_req_ready, ext_rsp_valid, ext_rsp_rdata, ext_rsp_error, ext_irq};
			assign ext_req_valid = 0;
			assign ext_req_addr = 0;
			assign ext_req_write = 0;
			assign ext_req_be = 0;
			assign ext_req_wdata = 0;
			assign ext_rsp_ready = 0;
			assign aqr = 0;
			assign arv = 0;
			assign ard = 0;
			assign are = 0;
			assign accel_irq = 0;
			assign mon_p4_busy = 0;
			assign mon_p4_result_valid = 0;
			assign mon_p4_pending = 0;
			assign mon_p4_enable = 0;
			assign mon_p4_start = 0;
			assign mon_p4_complete = 0;
			assign mon_p4_soft_reset = 0;
			assign mon_p4_generation = 0;
			assign mon_p4_submit_id = 0;
			assign mon_p4_done_id = 0;
			assign mon_p4_result = 0;
			assign mon_p4_length = 0;
		end
	endgenerate
	wire periph_irq_software;
	wire periph_irq_timer;
	wire periph_irq_external;
	generate
		if (MACHINE_MODE != 0) begin : machine_peripherals
			p2_peripherals #(
				.UART_BASE(32'h10000000),
				.GPIO_BASE(32'h10001000),
				.TIMER_BASE(32'h10002000),
				.UART_DIVISOR(32'h00000557)
			) peripherals(
				.clk(clk),
				.rst(rst),
				.req_valid(pqv),
				.req_ready(pqr),
				.req_addr(mmio_addr_q),
				.req_write(mmio_write_q),
				.req_be(mmio_be_q),
				.req_wdata(mmio_wdata_q),
				.rsp_valid(prv),
				.rsp_ready(prr),
				.rsp_rdata(prd),
				.rsp_error(pre),
				.uart_tx(uart_tx),
				.gpio_out(gpio_out),
				.external_irq(irq_external_in || accel_irq),
				.irq_software(periph_irq_software),
				.irq_timer(periph_irq_timer),
				.irq_external(periph_irq_external)
			);
		end
		else begin : compatibility_peripherals
			assign periph_irq_software = 0;
			assign periph_irq_timer = 0;
			assign periph_irq_external = irq_external_in || accel_irq;
			p1_peripherals #(
				.UART_BASE(32'h10000000),
				.GPIO_BASE(32'h10001000),
				.TIMER_BASE(32'h10002000),
				.UART_DIVISOR(32'h00000557)
			) peripherals(
				.clk(clk),
				.rst(rst),
				.req_valid(pqv),
				.req_ready(pqr),
				.req_addr(mmio_addr_q),
				.req_write(mmio_write_q),
				.req_be(mmio_be_q),
				.req_wdata(mmio_wdata_q),
				.rsp_valid(prv),
				.rsp_ready(prr),
				.rsp_rdata(prd),
				.rsp_error(pre),
				.uart_tx(uart_tx),
				.gpio_out(gpio_out)
			);
		end
		if (LEGACY_CORE != 0) begin : compatibility
			wire legacy_i_valid;
			wire legacy_d_valid;
			reg legacy_stopped;
			reg legacy_i_held;
			wire legacy_admit = !run_stop && !legacy_stopped;
			wire unused_legacy_inputs = ^{irq_software_in, irq_timer_in, irq_external_in, fatal_error, fence_i_ready, fence_i_done, fence_i_error, periph_irq_software, periph_irq_timer, periph_irq_external, perf_cache_flat};
			assign i_req_valid = legacy_i_valid && (legacy_admit || legacy_i_held);
			assign cqv = legacy_d_valid && legacy_admit;
			always @(posedge clk)
				if (rst) begin
					legacy_stopped <= 0;
					legacy_i_held <= 0;
				end
				else begin
					legacy_i_held <= i_req_valid && !i_req_ready;
					if (((crv && crr) && terminal_response) && !cre)
						legacy_stopped <= 1;
				end
			assign data_idle = !pending;
			assign fence_i_valid = 0;
			assign trace_irq_valid = 0;
			assign trace_irq_pc = 0;
			assign trace_irq_cause = 0;
			assign trace_csr_valid = 0;
			assign trace_csr_read = 0;
			assign trace_csr_write = 0;
			assign trace_csr_addr = 0;
			assign trace_csr_rdata = 0;
			assign trace_csr_wdata = 0;
			assign machine_cycle = 0;
			assign machine_retired = 0;
			assign trace_valid1 = 0;
			assign trace_pc1 = 0;
			assign trace_insn1 = 0;
			assign trace_rd1 = 0;
			assign trace_wdata1 = 0;
			p1_core #(.RESET_PC(RESET_PC)) core(
				.clk(clk),
				.rst(rst),
				.i_req_valid(legacy_i_valid),
				.i_req_ready(i_req_ready && (legacy_admit || legacy_i_held)),
				.i_req_addr(i_req_addr),
				.i_rsp_valid(i_rsp_valid),
				.i_rsp_ready(i_rsp_ready),
				.i_rsp_data(i_rsp_data),
				.i_rsp_error(i_rsp_error),
				.d_req_valid(legacy_d_valid),
				.d_req_ready(cqr && legacy_admit),
				.d_req_addr(cqa),
				.d_req_write(cqw),
				.d_req_be(cqb),
				.d_req_wdata(cqd),
				.d_rsp_valid(crv),
				.d_rsp_ready(crr),
				.d_rsp_data(crd),
				.d_rsp_error(cre),
				.trace_valid(trace_valid),
				.trace_trap(trace_trap),
				.trace_pc(trace_pc),
				.trace_insn(trace_insn),
				.trace_rd(trace_rd),
				.trace_wdata(trace_wdata),
				.trace_cause(trace_cause),
				.trace_tval(trace_tval),
				.trace_mem_valid(trace_mem_valid),
				.trace_mem_write(trace_mem_write),
				.trace_mem_addr(trace_mem_addr),
				.trace_mem_wdata(trace_mem_wdata),
				.trace_mem_rdata(trace_mem_rdata),
				.trace_mem_be(trace_mem_be),
				.halted(halted),
				.count_cycle(count_cycle),
				.count_retired(count_retired),
				.count_if_wait(count_if_wait),
				.count_data_wait(count_data_wait),
				.count_load_use(count_load_use),
				.count_redirect(count_redirect),
				.count_reads(count_reads),
				.count_writes(count_writes)
			);
		end
		else begin : improved
			p2_core #(
				.RESET_PC(RESET_PC),
				.MACHINE_MODE(MACHINE_MODE),
				.BP_ENABLED(BP_ENABLED),
				.FIFO_DEPTH(FIFO_DEPTH),
				.RESPONSE_BYPASS(RESPONSE_BYPASS),
				.BTB_ENTRIES(BTB_ENTRIES),
				.BHT_ENTRIES(BHT_ENTRIES),
				.RAS_DEPTH(RAS_DEPTH),
				.EARLY_LSU(EARLY_LSU),
				.HW_MUL(HW_MUL),
				.IFETCH_DUAL_WORDS(IFETCH_DUAL_WORDS),
				.IFETCH_LINE_BYTES(IFETCH_LINE_BYTES),
				.IFETCH_PREDECODE(IFETCH_PREDECODE)
			) core(
				.clk(clk),
				.rst(rst),
				.perf_cache_flat(perf_cache_flat),
				.irq_software(irq_software_in || periph_irq_software),
				.irq_timer(irq_timer_in || periph_irq_timer),
				.irq_external(periph_irq_external),
				.fatal_error(fatal_error),
				.run_stop(run_stop),
				.data_idle(data_idle),
				.machine_cycle(machine_cycle),
				.machine_retired(machine_retired),
				.fence_i_valid(fence_i_valid),
				.fence_i_ready(fence_i_ready),
				.fence_i_done(fence_i_done),
				.fence_i_error(fence_i_error),
				.trace_irq_valid(trace_irq_valid),
				.trace_irq_pc(trace_irq_pc),
				.trace_irq_cause(trace_irq_cause),
				.trace_csr_valid(trace_csr_valid),
				.trace_csr_addr(trace_csr_addr),
				.trace_csr_read(trace_csr_read),
				.trace_csr_write(trace_csr_write),
				.trace_csr_rdata(trace_csr_rdata),
				.trace_csr_wdata(trace_csr_wdata),
				.i_req_valid(i_req_valid),
				.i_req_ready(i_req_ready),
				.i_req_addr(i_req_addr),
				.i_rsp_valid(i_rsp_valid),
				.i_rsp_ready(i_rsp_ready),
				.i_rsp_data(i_rsp_data),
				.i_rsp_error(i_rsp_error),
				.i_rsp_data_hi(i_rsp_data_hi),
				.i_rsp_hi_valid(i_rsp_hi_valid),
				.i_rsp_predecode(i_rsp_predecode),
				.i_rsp_predecode_hi(i_rsp_predecode_hi),
				.trace_valid1(trace_valid1),
				.trace_pc1(trace_pc1),
				.trace_insn1(trace_insn1),
				.trace_rd1(trace_rd1),
				.trace_wdata1(trace_wdata1),
				.d_req_valid(cqv),
				.d_req_ready(cqr),
				.d_req_addr(cqa),
				.d_req_write(cqw),
				.d_req_be(cqb),
				.d_req_wdata(cqd),
				.d_rsp_valid(crv),
				.d_rsp_ready(crr),
				.d_rsp_data(crd),
				.d_rsp_error(cre),
				.d_rsp_terminal(terminal_response),
				.trace_valid(trace_valid),
				.trace_trap(trace_trap),
				.trace_pc(trace_pc),
				.trace_insn(trace_insn),
				.trace_rd(trace_rd),
				.trace_wdata(trace_wdata),
				.trace_cause(trace_cause),
				.trace_tval(trace_tval),
				.trace_mem_valid(trace_mem_valid),
				.trace_mem_write(trace_mem_write),
				.trace_mem_addr(trace_mem_addr),
				.trace_mem_wdata(trace_mem_wdata),
				.trace_mem_rdata(trace_mem_rdata),
				.trace_mem_be(trace_mem_be),
				.halted(halted),
				.count_cycle(count_cycle),
				.count_retired(count_retired),
				.count_if_wait(count_if_wait),
				.count_data_wait(count_data_wait),
				.count_load_use(count_load_use),
				.count_redirect(count_redirect),
				.count_reads(count_reads),
				.count_writes(count_writes)
			);
		end
	endgenerate
endmodule
module p2_cached_soc (
	clk,
	rst,
	run_stop,
	ext_req_valid,
	ext_req_ready,
	ext_req_addr,
	ext_req_write,
	ext_req_be,
	ext_req_wdata,
	ext_rsp_valid,
	ext_rsp_ready,
	ext_rsp_rdata,
	ext_rsp_error,
	ext_irq,
	irq_software_in,
	irq_timer_in,
	irq_external_in,
	clean_valid,
	clean_ready,
	clean_done,
	clean_error,
	fatal,
	data_idle,
	count_i_hit,
	count_i_miss,
	count_d_hit,
	count_d_miss,
	count_d_writeback,
	cmd_valid,
	cmd_ready,
	cmd_write,
	cmd_addr,
	cmd_len,
	w_valid,
	w_ready,
	w_data,
	w_be,
	w_last,
	r_valid,
	r_ready,
	r_data,
	r_error,
	r_last,
	trace_irq_valid,
	trace_irq_pc,
	trace_irq_cause,
	trace_csr_valid,
	trace_csr_read,
	trace_csr_write,
	trace_csr_addr,
	trace_csr_rdata,
	trace_csr_wdata,
	machine_cycle,
	machine_retired,
	trace_valid,
	trace_trap,
	trace_valid1,
	trace_pc1,
	trace_insn1,
	trace_rd1,
	trace_wdata1,
	trace_pc,
	trace_insn,
	trace_rd,
	trace_wdata,
	trace_cause,
	trace_tval,
	trace_mem_valid,
	trace_mem_write,
	trace_mem_addr,
	trace_mem_wdata,
	trace_mem_rdata,
	trace_mem_be,
	halted,
	uart_tx,
	gpio_out,
	mon_d_req_valid,
	mon_d_req_ready,
	mon_d_req_write,
	mon_d_req_addr,
	mon_d_req_wdata,
	mon_d_req_be,
	mon_d_rsp_valid,
	mon_d_rsp_ready,
	mon_d_rsp_error,
	mon_d_rsp_data,
	mon_p4_enabled,
	mon_p4_busy,
	mon_p4_result_valid,
	mon_p4_pending,
	mon_p4_enable,
	mon_p4_irq,
	mon_p4_start,
	mon_p4_complete,
	mon_p4_soft_reset,
	mon_p4_rsp_valid,
	mon_p4_generation,
	mon_p4_submit_id,
	mon_p4_done_id,
	mon_p4_result,
	mon_p4_length,
	count_cycle,
	count_retired,
	count_if_wait,
	count_data_wait,
	count_load_use,
	count_redirect,
	count_reads,
	count_writes
);
	parameter [31:0] RESET_PC = 32'h80018000;
	parameter MACHINE_MODE = 1;
	parameter BP_ENABLED = 1;
	parameter LEGACY_CORE = 0;
	parameter CACHE_ENABLED = 1;
	parameter CACHE_BYTES = 8192;
	parameter LINE_BYTES = 32;
	parameter FIFO_DEPTH = 2;
	parameter RESPONSE_BYPASS = 0;
	parameter BTB_ENTRIES = 128;
	parameter BHT_ENTRIES = 256;
	parameter RAS_DEPTH = 4;
	parameter EARLY_LSU = 0;
	parameter HW_MUL = 0;
	parameter ACCEL_ENABLE = 0;
	parameter [31:0] ACCEL_BASE = 32'h10003000;
	parameter ACCEL_EXTERNAL = 0;
	parameter integer DC_LOAD_HIT_TURNOVER = 0;
	// Cached RAM window (block RAM + DDR3 behind the burst port).
	parameter [31:0] RAM_WINDOW_BYTES = 32'h00020000;
	input wire clk;
	input wire rst;
	input wire run_stop;
	output wire ext_req_valid;
	input wire ext_req_ready;
	output wire [31:0] ext_req_addr;
	output wire ext_req_write;
	output wire [3:0] ext_req_be;
	output wire [31:0] ext_req_wdata;
	input wire ext_rsp_valid;
	output wire ext_rsp_ready;
	input wire [31:0] ext_rsp_rdata;
	input wire ext_rsp_error;
	input wire ext_irq;
	input wire irq_software_in;
	input wire irq_timer_in;
	input wire irq_external_in;
	input wire clean_valid;
	output wire clean_ready;
	output wire clean_done;
	output wire clean_error;
	output wire fatal;
	output wire data_idle;
	output wire [63:0] count_i_hit;
	output wire [63:0] count_i_miss;
	output wire [63:0] count_d_hit;
	output wire [63:0] count_d_miss;
	output wire [63:0] count_d_writeback;
	output wire cmd_valid;
	input wire cmd_ready;
	output wire cmd_write;
	output wire [31:0] cmd_addr;
	output wire [7:0] cmd_len;
	output wire w_valid;
	input wire w_ready;
	output wire [31:0] w_data;
	output wire [3:0] w_be;
	output wire w_last;
	input wire r_valid;
	output wire r_ready;
	input wire [31:0] r_data;
	input wire r_error;
	input wire r_last;
	output wire trace_irq_valid;
	output wire [31:0] trace_irq_pc;
	output wire [31:0] trace_irq_cause;
	output wire trace_csr_valid;
	output wire trace_csr_read;
	output wire trace_csr_write;
	output wire [11:0] trace_csr_addr;
	output wire [31:0] trace_csr_rdata;
	output wire [31:0] trace_csr_wdata;
	output wire [63:0] machine_cycle;
	output wire [63:0] machine_retired;
	output wire trace_valid;
	output wire trace_trap;
	output wire trace_valid1;
	output wire [31:0] trace_pc1;
	output wire [31:0] trace_insn1;
	output wire [4:0] trace_rd1;
	output wire [31:0] trace_wdata1;
	output wire [31:0] trace_pc;
	output wire [31:0] trace_insn;
	output wire [4:0] trace_rd;
	output wire [31:0] trace_wdata;
	output wire [31:0] trace_cause;
	output wire [31:0] trace_tval;
	output wire trace_mem_valid;
	output wire trace_mem_write;
	output wire [31:0] trace_mem_addr;
	output wire [31:0] trace_mem_wdata;
	output wire [31:0] trace_mem_rdata;
	output wire [3:0] trace_mem_be;
	output wire halted;
	output wire uart_tx;
	output wire [31:0] gpio_out;
	output wire mon_d_req_valid;
	output wire mon_d_req_ready;
	output wire mon_d_req_write;
	output wire [31:0] mon_d_req_addr;
	output wire [31:0] mon_d_req_wdata;
	output wire [3:0] mon_d_req_be;
	output wire mon_d_rsp_valid;
	output wire mon_d_rsp_ready;
	output wire mon_d_rsp_error;
	output wire [31:0] mon_d_rsp_data;
	output wire mon_p4_enabled;
	output wire mon_p4_busy;
	output wire mon_p4_result_valid;
	output wire mon_p4_pending;
	output wire mon_p4_enable;
	output wire mon_p4_irq;
	output wire mon_p4_start;
	output wire mon_p4_complete;
	output wire mon_p4_soft_reset;
	output wire mon_p4_rsp_valid;
	output wire [31:0] mon_p4_generation;
	output wire [31:0] mon_p4_submit_id;
	output wire [31:0] mon_p4_done_id;
	output wire [31:0] mon_p4_result;
	output wire [31:0] mon_p4_length;
	output wire [63:0] count_cycle;
	output wire [63:0] count_retired;
	output wire [63:0] count_if_wait;
	output wire [63:0] count_data_wait;
	output wire [63:0] count_load_use;
	output wire [63:0] count_redirect;
	output wire [63:0] count_reads;
	output wire [63:0] count_writes;
	wire iqv;
	wire iqr;
	wire irv;
	wire irr;
	wire ire;
	wire irhv;
	wire [31:0] iqa;
	wire [31:0] ird;
	wire [31:0] ird_hi;
	wire [6:0] ird_pre, ird_pre_hi;
	wire dqv;
	wire dqr;
	wire dqw;
	wire drv;
	wire drr;
	wire dre;
	wire [31:0] dqa;
	wire [31:0] dqd;
	wire [31:0] drd;
	wire [3:0] dqb;
	wire cqv;
	wire cqr;
	wire crv;
	wire crr;
	wire cre;
	wire [31:0] crd;
	wire fi_valid;
	wire fi_ready;
	wire fi_done;
	wire fi_error;
	wire imv;
	wire imr;
	wire imd;
	wire ime;
	wire dmv;
	wire dmr;
	wire dmd;
	wire dme;
	wire ifatal;
	wire dfatal;
	wire [63:0] unused_i_writeback;
	reg route_pending;
	reg route_exit;
	reg exit_error;
	wire select_exit = dqa == 32'h20000000;
	wire available = !route_pending || (drv && drr);
	assign cqv = (dqv && !select_exit) && available;
	assign dqr = available && (select_exit ? 1'b1 : cqr);
	assign drv = route_pending && (route_exit ? 1'b1 : crv);
	assign drd = (route_exit ? 32'b00000000000000000000000000000000 : crd);
	assign dre = (route_exit ? exit_error : cre);
	assign crr = (route_pending && !route_exit) && drr;
	always @(posedge clk)
		if (rst) begin
			route_pending <= 0;
			route_exit <= 0;
			exit_error <= 0;
		end
		else begin
			if (drv && drr)
				route_pending <= 0;
			if (dqv && dqr) begin
				route_pending <= 1;
				route_exit <= select_exit;
				exit_error <= !dqw || (dqb != 4'hf);
			end
		end
	localparam [2:0] IDLE = 0;
	localparam [2:0] DC_REQ = 1;
	localparam [2:0] DC_WAIT = 2;
	localparam [2:0] IC_REQ = 3;
	localparam [2:0] IC_WAIT = 4;
	localparam [2:0] DONE = 5;
	localparam [2:0] DRAIN_REQ = 6;
	localparam [2:0] DRAIN_WAIT = 7;
	reg [2:0] maintenance;
	reg debug_clean;
	// The DDR bridge acknowledges posted writes when queued. An ordered read
	// after D-cache maintenance waits for those writes at the DDR engine.
	// This is inside the retained SD SoC; the frozen CPU/cache are unchanged.
	reg posted_ddr;
	reg [31:0] posted_addr;
	reg burst_pending;
	wire arb_cmd_valid, arb_cmd_ready, arb_cmd_write;
	wire [31:0] arb_cmd_addr;
	wire [7:0] arb_cmd_len;
	wire arb_w_valid, arb_w_ready, arb_w_last;
	wire [31:0] arb_w_data;
	wire [3:0] arb_w_be;
	wire arb_r_valid, arb_r_ready;
	wire drain_owns = (maintenance == DRAIN_WAIT) ||
	                  ((maintenance == DRAIN_REQ) && !burst_pending);
	assign cmd_valid = drain_owns ? (maintenance == DRAIN_REQ) : arb_cmd_valid;
	assign cmd_write = drain_owns ? 1'b0 : arb_cmd_write;
	assign cmd_addr = drain_owns ? posted_addr : arb_cmd_addr;
	assign cmd_len = drain_owns ? 8'd1 : arb_cmd_len;
	assign arb_cmd_ready = !drain_owns && cmd_ready;
	assign w_valid = !drain_owns && arb_w_valid;
	assign arb_w_ready = !drain_owns && w_ready;
	assign w_data = arb_w_data;
	assign w_be = arb_w_be;
	assign w_last = arb_w_last;
	assign arb_r_valid = !drain_owns && r_valid;
	assign r_ready = drain_owns ? (maintenance == DRAIN_WAIT) : arb_r_ready;
	always @(posedge clk) begin
		if (rst) begin
			posted_ddr <= 0;
			posted_addr <= 32'h80020000;
			burst_pending <= 0;
		end else begin
			if (!drain_owns && r_valid && r_ready && r_last) burst_pending <= 0;
			if (!drain_owns && cmd_valid && cmd_ready) begin
				burst_pending <= 1;
				if (cmd_write && cmd_addr >= 32'h80020000 && cmd_addr < 32'h84000000) begin
					posted_ddr <= 1;
					posted_addr <= {cmd_addr[31:5], 5'b0};
				end
			end
			if (maintenance == DRAIN_WAIT && r_valid && r_ready && r_last)
				posted_ddr <= 0;
		end
	end
	reg maintenance_error;
	assign clean_ready = (((maintenance == IDLE) && run_stop) && data_idle) && !fatal;
	assign fi_ready = ((maintenance == IDLE) && !clean_valid) && !fatal;
	assign clean_done = (maintenance == DONE) && debug_clean;
	assign clean_error = maintenance_error;
	assign fi_done = (maintenance == DONE) && !debug_clean;
	assign fi_error = maintenance_error;
	assign dmv = maintenance == DC_REQ;
	assign imv = maintenance == IC_REQ;
	assign fatal = (ifatal || dfatal) || maintenance_error;
	always @(posedge clk)
		if (rst) begin
			maintenance <= IDLE;
			debug_clean <= 0;
			maintenance_error <= 0;
		end
		else
			case (maintenance)
				IDLE:
					if (clean_valid && clean_ready) begin
						maintenance <= DC_REQ;
						debug_clean <= 1;
					end
					else if (fi_valid && fi_ready) begin
						maintenance <= DC_REQ;
						debug_clean <= 0;
					end
				DC_REQ:
					if (dmr)
						maintenance <= DC_WAIT;
				DC_WAIT:
					if (dmd) begin
						maintenance_error <= dme;
						maintenance <= dme ? DONE : (posted_ddr ? DRAIN_REQ : (debug_clean ? DONE : IC_REQ));
					end
				DRAIN_REQ:
					if (!burst_pending && cmd_valid && cmd_ready) maintenance <= DRAIN_WAIT;
				DRAIN_WAIT:
					if (r_valid && r_ready) begin
						maintenance_error <= maintenance_error || r_error;
						if (r_last) maintenance <= (r_error || maintenance_error || debug_clean) ? DONE : IC_REQ;
					end
				IC_REQ:
					if (imr)
						maintenance <= IC_WAIT;
				IC_WAIT:
					if (imd) begin
						maintenance_error <= ime;
						maintenance <= DONE;
					end
				DONE: maintenance <= IDLE;
				default: maintenance <= IDLE;
			endcase
	p2_soc #(
		.RESET_PC(RESET_PC),
		.MACHINE_MODE(MACHINE_MODE),
		.BP_ENABLED(BP_ENABLED),
		.LEGACY_CORE(LEGACY_CORE),
		.FIFO_DEPTH(FIFO_DEPTH),
		.RESPONSE_BYPASS(RESPONSE_BYPASS),
		.BTB_ENTRIES(BTB_ENTRIES),
		.BHT_ENTRIES(BHT_ENTRIES),
		.RAS_DEPTH(RAS_DEPTH),
		.EARLY_LSU(EARLY_LSU),
		.HW_MUL(HW_MUL),
		.ACCEL_ENABLE(ACCEL_ENABLE),
		.IFETCH_DUAL_WORDS(CACHE_ENABLED != 0),
		.IFETCH_LINE_BYTES(LINE_BYTES),
		.IFETCH_PREDECODE(CACHE_ENABLED != 0),
		.ACCEL_BASE(ACCEL_BASE),
		.ACCEL_EXTERNAL(ACCEL_EXTERNAL)
	) soc(
		.clk(clk),
		.rst(rst),
		.run_stop(run_stop),
		.ext_req_valid(ext_req_valid),
		.ext_req_ready(ext_req_ready),
		.ext_req_addr(ext_req_addr),
		.ext_req_write(ext_req_write),
		.ext_req_be(ext_req_be),
		.ext_req_wdata(ext_req_wdata),
		.ext_rsp_valid(ext_rsp_valid),
		.ext_rsp_ready(ext_rsp_ready),
		.ext_rsp_rdata(ext_rsp_rdata),
		.ext_rsp_error(ext_rsp_error),
		.ext_irq(ext_irq),
		.fatal_error(fatal),
		.data_idle(data_idle),
		.perf_cache_flat({count_d_writeback, count_d_miss, count_d_hit, count_i_miss, count_i_hit}),
		.irq_software_in(irq_software_in),
		.irq_timer_in(irq_timer_in),
		.irq_external_in(irq_external_in),
		.fence_i_valid(fi_valid),
		.fence_i_ready(fi_ready),
		.fence_i_done(fi_done),
		.fence_i_error(fi_error),
		.i_req_valid(iqv),
		.i_req_ready(iqr),
		.i_req_addr(iqa),
		.i_rsp_valid(irv),
		.i_rsp_ready(irr),
		.i_rsp_data(ird),
		.i_rsp_error(ire),
		.i_rsp_data_hi(ird_hi),
		.i_rsp_hi_valid(irhv),
		.i_rsp_predecode(ird_pre),
		.i_rsp_predecode_hi(ird_pre_hi),
		.d_req_valid(dqv),
		.d_req_ready(dqr),
		.d_req_addr(dqa),
		.d_req_write(dqw),
		.d_req_be(dqb),
		.d_req_wdata(dqd),
		.d_rsp_valid(drv),
		.d_rsp_ready(drr),
		.d_rsp_data(drd),
		.d_rsp_error(dre),
		.trace_irq_valid(trace_irq_valid),
		.trace_irq_pc(trace_irq_pc),
		.trace_irq_cause(trace_irq_cause),
		.trace_csr_valid(trace_csr_valid),
		.trace_csr_read(trace_csr_read),
		.trace_csr_write(trace_csr_write),
		.trace_csr_addr(trace_csr_addr),
		.trace_csr_rdata(trace_csr_rdata),
		.trace_csr_wdata(trace_csr_wdata),
		.machine_cycle(machine_cycle),
		.machine_retired(machine_retired),
		.trace_valid(trace_valid),
		.trace_valid1(trace_valid1),
		.trace_pc1(trace_pc1),
		.trace_insn1(trace_insn1),
		.trace_rd1(trace_rd1),
		.trace_wdata1(trace_wdata1),
		.trace_trap(trace_trap),
		.trace_pc(trace_pc),
		.trace_insn(trace_insn),
		.trace_rd(trace_rd),
		.trace_wdata(trace_wdata),
		.trace_cause(trace_cause),
		.trace_tval(trace_tval),
		.trace_mem_valid(trace_mem_valid),
		.trace_mem_write(trace_mem_write),
		.trace_mem_addr(trace_mem_addr),
		.trace_mem_wdata(trace_mem_wdata),
		.trace_mem_rdata(trace_mem_rdata),
		.trace_mem_be(trace_mem_be),
		.halted(halted),
		.uart_tx(uart_tx),
		.gpio_out(gpio_out),
		.mon_d_req_valid(mon_d_req_valid),
		.mon_d_req_ready(mon_d_req_ready),
		.mon_d_req_write(mon_d_req_write),
		.mon_d_req_addr(mon_d_req_addr),
		.mon_d_req_wdata(mon_d_req_wdata),
		.mon_d_req_be(mon_d_req_be),
		.mon_d_rsp_valid(mon_d_rsp_valid),
		.mon_d_rsp_ready(mon_d_rsp_ready),
		.mon_d_rsp_error(mon_d_rsp_error),
		.mon_d_rsp_data(mon_d_rsp_data),
		.mon_p4_enabled(mon_p4_enabled),
		.mon_p4_busy(mon_p4_busy),
		.mon_p4_result_valid(mon_p4_result_valid),
		.mon_p4_pending(mon_p4_pending),
		.mon_p4_enable(mon_p4_enable),
		.mon_p4_irq(mon_p4_irq),
		.mon_p4_start(mon_p4_start),
		.mon_p4_complete(mon_p4_complete),
		.mon_p4_soft_reset(mon_p4_soft_reset),
		.mon_p4_rsp_valid(mon_p4_rsp_valid),
		.mon_p4_generation(mon_p4_generation),
		.mon_p4_submit_id(mon_p4_submit_id),
		.mon_p4_done_id(mon_p4_done_id),
		.mon_p4_result(mon_p4_result),
		.mon_p4_length(mon_p4_length),
		.count_cycle(count_cycle),
		.count_retired(count_retired),
		.count_if_wait(count_if_wait),
		.count_data_wait(count_data_wait),
		.count_load_use(count_load_use),
		.count_redirect(count_redirect),
		.count_reads(count_reads),
		.count_writes(count_writes)
	);
	wire a_cmd_valid;
	wire a_cmd_ready;
	wire a_cmd_write;
	wire [31:0] a_cmd_addr;
	wire [7:0] a_cmd_len;
	wire a_w_valid;
	wire a_w_ready;
	wire [31:0] a_w_data;
	wire [3:0] a_w_be;
	wire a_w_last;
	wire a_r_valid;
	wire a_r_ready;
	wire [31:0] a_r_data;
	wire a_r_error;
	wire a_r_last;
	wire b_cmd_valid;
	wire b_cmd_ready;
	wire b_cmd_write;
	wire [31:0] b_cmd_addr;
	wire [7:0] b_cmd_len;
	wire b_w_valid;
	wire b_w_ready;
	wire [31:0] b_w_data;
	wire [3:0] b_w_be;
	wire b_w_last;
	wire b_r_valid;
	wire b_r_ready;
	wire [31:0] b_r_data;
	wire b_r_error;
	wire b_r_last;
	p2_cache #(
		.READ_ONLY(1),
		.CACHE_BYTES(CACHE_BYTES),
		.LINE_BYTES(LINE_BYTES),
		.RAM_BASE(32'h80000000),
		.RAM_BYTES(RAM_WINDOW_BYTES),
		.ENABLED(CACHE_ENABLED),
		.STORE_PREDECODE(CACHE_ENABLED != 0)
	) icache(
		.clk(clk),
		.rst(rst),
		.req_valid(iqv),
		.req_ready(iqr),
		.req_addr(iqa),
		.req_write(1'b0),
		.req_be(4'hf),
		.req_wdata(32'b00000000000000000000000000000000),
		.rsp_valid(irv),
		.rsp_ready(irr),
		.rsp_rdata(ird),
		.rsp_error(ire),
		.rsp_data_hi(ird_hi),
		.rsp_hi_valid(irhv),
		.rsp_predecode(ird_pre),
		.rsp_predecode_hi(ird_pre_hi),
		.maint_valid(imv),
		.maint_ready(imr),
		.maint_clean(1'b0),
		.maint_invalidate(1'b1),
		.maint_done(imd),
		.maint_error(ime),
		.fatal(ifatal),
		.count_hit(count_i_hit),
		.count_miss(count_i_miss),
		.count_writeback(unused_i_writeback),
		.cmd_valid(a_cmd_valid),
		.cmd_ready(a_cmd_ready),
		.cmd_write(a_cmd_write),
		.cmd_addr(a_cmd_addr),
		.cmd_len(a_cmd_len),
		.w_valid(a_w_valid),
		.w_ready(a_w_ready),
		.w_data(a_w_data),
		.w_be(a_w_be),
		.w_last(a_w_last),
		.r_valid(a_r_valid),
		.r_ready(a_r_ready),
		.r_data(a_r_data),
		.r_error(a_r_error),
		.r_last(a_r_last)
	);
	p2_cache #(
		.READ_ONLY(0),
		.CACHE_BYTES(CACHE_BYTES),
		.LINE_BYTES(LINE_BYTES),
		.RAM_BASE(32'h80000000),
		.RAM_BYTES(RAM_WINDOW_BYTES),
		.ENABLED(CACHE_ENABLED),
		.DC_LOAD_HIT_TURNOVER(DC_LOAD_HIT_TURNOVER)
	) dcache(
		.clk(clk),
		.rst(rst),
		.req_valid(cqv),
		.req_ready(cqr),
		.req_addr(dqa),
		.req_write(dqw),
		.req_be(dqb),
		.req_wdata(dqd),
		.rsp_valid(crv),
		.rsp_ready(crr),
		.rsp_rdata(crd),
		.rsp_error(cre),
		.maint_valid(dmv),
		.maint_ready(dmr),
		.maint_clean(1'b1),
		.maint_invalidate(1'b0),
		.maint_done(dmd),
		.maint_error(dme),
		.fatal(dfatal),
		.count_hit(count_d_hit),
		.count_miss(count_d_miss),
		.count_writeback(count_d_writeback),
		.cmd_valid(b_cmd_valid),
		.cmd_ready(b_cmd_ready),
		.cmd_write(b_cmd_write),
		.cmd_addr(b_cmd_addr),
		.cmd_len(b_cmd_len),
		.w_valid(b_w_valid),
		.w_ready(b_w_ready),
		.w_data(b_w_data),
		.w_be(b_w_be),
		.w_last(b_w_last),
		.r_valid(b_r_valid),
		.r_ready(b_r_ready),
		.r_data(b_r_data),
		.r_error(b_r_error),
		.r_last(b_r_last)
	);
	p2_burst_arbiter2 arbiter(
		.clk(clk),
		.rst(rst),
		.a_cmd_valid(a_cmd_valid),
		.a_cmd_ready(a_cmd_ready),
		.a_cmd_write(a_cmd_write),
		.a_cmd_addr(a_cmd_addr),
		.a_cmd_len(a_cmd_len),
		.a_w_valid(a_w_valid),
		.a_w_ready(a_w_ready),
		.a_w_data(a_w_data),
		.a_w_be(a_w_be),
		.a_w_last(a_w_last),
		.a_r_valid(a_r_valid),
		.a_r_ready(a_r_ready),
		.a_r_data(a_r_data),
		.a_r_error(a_r_error),
		.a_r_last(a_r_last),
		.b_cmd_valid(b_cmd_valid),
		.b_cmd_ready(b_cmd_ready),
		.b_cmd_write(b_cmd_write),
		.b_cmd_addr(b_cmd_addr),
		.b_cmd_len(b_cmd_len),
		.b_w_valid(b_w_valid),
		.b_w_ready(b_w_ready),
		.b_w_data(b_w_data),
		.b_w_be(b_w_be),
		.b_w_last(b_w_last),
		.b_r_valid(b_r_valid),
		.b_r_ready(b_r_ready),
		.b_r_data(b_r_data),
		.b_r_error(b_r_error),
		.b_r_last(b_r_last),
		.m_cmd_valid(arb_cmd_valid),
		.m_cmd_ready(arb_cmd_ready),
		.m_cmd_write(arb_cmd_write),
		.m_cmd_addr(arb_cmd_addr),
		.m_cmd_len(arb_cmd_len),
		.m_w_valid(arb_w_valid),
		.m_w_ready(arb_w_ready),
		.m_w_data(arb_w_data),
		.m_w_be(arb_w_be),
		.m_w_last(arb_w_last),
		.m_r_valid(arb_r_valid),
		.m_r_ready(arb_r_ready),
		.m_r_data(r_data),
		.m_r_error(r_error),
		.m_r_last(r_last)
	);
endmodule

// rtl/cpu/fn_cpu_core.v
`timescale 1ns / 1ps
// fn_cpu_core: frozen board-tested best CPU with the SD/PAL SoC adapter:
//  * module name,
//  * external MMIO exports the legacy 0x10004000..0x10004fff and complete
//    pose 0x10008000..0x1000ffff windows, preserving response ownership,
//  * the synchronous core reset is exported as rst_out.
// Cache/core/predictor parameters are exactly the sealed configuration, except
// that the cached RAM window is 64 MiB: the low 128 KiB stay block RAM and
// 0x80020000..0x83ffffff is exported as a burst port for the DDR3 bridge.
module fn_cpu_core (
	clk,
	reset_n,
	rst_out,
	ext_req_valid,
	ext_req_ready,
	ext_req_addr,
	ext_req_write,
	ext_req_be,
	ext_req_wdata,
	ext_rsp_valid,
	ext_rsp_ready,
	ext_rsp_rdata,
	ext_rsp_error,
	external_irq,
	uart_tx,
	gpio_out,
	completed,
	failed,
	ddr_cmd_valid,
	ddr_cmd_ready,
	ddr_cmd_write,
	ddr_cmd_addr,
	ddr_cmd_len,
	ddr_w_valid,
	ddr_w_ready,
	ddr_w_data,
	ddr_w_be,
	ddr_w_last,
	ddr_r_valid,
	ddr_r_ready,
	ddr_r_data,
	ddr_r_error,
	ddr_r_last
);
	parameter [31:0] RESET_PC = 32'h80018000;
	parameter _sv2v_width_INIT_FILE = 88;
	parameter [_sv2v_width_INIT_FILE - 1:0] INIT_FILE = "program.hex";
	parameter integer DC_LOAD_HIT_TURNOVER = 1;
	input wire clk;
	input wire reset_n;
	output wire rst_out;
	output wire ext_req_valid;
	input wire ext_req_ready;
	output wire [31:0] ext_req_addr;
	output wire ext_req_write;
	output wire [3:0] ext_req_be;
	output wire [31:0] ext_req_wdata;
	input wire ext_rsp_valid;
	output wire ext_rsp_ready;
	input wire [31:0] ext_rsp_rdata;
	input wire ext_rsp_error;
	input wire external_irq;
	output wire uart_tx;
	output wire [31:0] gpio_out;
	output reg completed;
	output reg failed;
	// DDR3 part of the cached window (0x80020000..0x83ffffff), see fn_mem_split
	output wire ddr_cmd_valid;
	input wire ddr_cmd_ready;
	output wire ddr_cmd_write;
	output wire [31:0] ddr_cmd_addr;
	output wire [7:0] ddr_cmd_len;
	output wire ddr_w_valid;
	input wire ddr_w_ready;
	output wire [31:0] ddr_w_data;
	output wire [3:0] ddr_w_be;
	output wire ddr_w_last;
	input wire ddr_r_valid;
	output wire ddr_r_ready;
	input wire [31:0] ddr_r_data;
	input wire ddr_r_error;
	input wire ddr_r_last;
    reg [1:0] reset_sync = 2'b11;
    always @(posedge clk or negedge reset_n)
        if (!reset_n) reset_sync <= 2'b11;
        else reset_sync <= {reset_sync[0], 1'b0};
    wire rst = reset_sync[1];
    assign rst_out = rst;
    wire exit_valid, data_idle, clean_done;
    wire [31:0] exit_code;
    reg clean_req;
    wire [1:0] tr_v;
    wire [31:0] trace_pc, trace_pc1, trace_insn, trace_insn1;
    wire unused_trace_irq_valid, unused_trace_irq;
    wire [31:0] unused_trace_irq_pc, unused_trace_irq_cause;
    wire [31:0] unused_trace_tval = 0;
    wire [31:0] unused_ila_pc = trace_pc;
    wire cmd_valid, cmd_ready, cmd_write, w_valid, w_ready, w_last;
    wire [31:0] cmd_addr, w_data, r_data;
    wire [7:0] cmd_len;
    wire [3:0] w_be;
    wire r_valid, r_ready, r_error, r_last;
    wire core_ext_req_valid, core_ext_req_ready, core_ext_req_write;
    wire [31:0] core_ext_req_addr, core_ext_req_wdata;
    wire [3:0] core_ext_req_be;
    wire core_ext_rsp_valid, core_ext_rsp_ready, core_ext_rsp_error;
    wire [31:0] core_ext_rsp_rdata;
    wire core_ddr_cmd_valid, core_ddr_cmd_ready, core_ddr_w_valid, core_ddr_w_ready;
    wire core_ddr_r_valid, core_ddr_r_ready, core_ddr_r_error, core_ddr_r_last;
    wire [31:0] core_ddr_r_data;
    wire raw_cmd_valid, raw_cmd_ready, raw_cmd_write, raw_w_valid, raw_w_ready, raw_w_last;
    wire raw_r_valid, raw_r_ready, raw_r_error, raw_r_last;
    wire [31:0] raw_cmd_addr, raw_w_data, raw_r_data;
    wire [7:0] raw_cmd_len;
    wire [3:0] raw_w_be;
    wire order_failed;
    always @(posedge clk) begin
        if (rst) begin clean_req <= 0; completed <= 0; failed <= 0; end
        else begin
            if (exit_valid && data_idle && !clean_req && !completed) begin
                clean_req <= 1;
                if (exit_code != 1) failed <= 1;
            end
            if (clean_done && clean_req) begin clean_req <= 0; completed <= 1; end
            if (order_failed) failed <= 1;
        end
    end
    o2_soc #(.RESET_PC(RESET_PC), .RAM_BYTES(32'h04000000), .UART_DIVISOR(1367), .EXT_MMIO(1), .PERF(0)) soc(
        .clk(clk), .rst(rst), .irq_external_in(external_irq), .clean_req(clean_req), .clean_done(clean_done),
        .data_idle(data_idle), .uart_tx(uart_tx), .gpio_out(gpio_out), .exit_valid(exit_valid), .exit_code(exit_code),
        .m_cmd_valid(raw_cmd_valid), .m_cmd_ready(raw_cmd_ready), .m_cmd_write(raw_cmd_write),
        .m_cmd_addr(raw_cmd_addr), .m_cmd_len(raw_cmd_len), .m_w_valid(raw_w_valid), .m_w_ready(raw_w_ready),
        .m_w_data(raw_w_data), .m_w_be(raw_w_be), .m_w_last(raw_w_last),
        .m_r_valid(raw_r_valid), .m_r_ready(raw_r_ready), .m_r_data(raw_r_data), .m_r_error(raw_r_error), .m_r_last(raw_r_last),
        .ext_req_valid(core_ext_req_valid), .ext_req_ready(core_ext_req_ready), .ext_req_addr(core_ext_req_addr),
        .ext_req_write(core_ext_req_write), .ext_req_be(core_ext_req_be), .ext_req_wdata(core_ext_req_wdata),
        .ext_rsp_valid(core_ext_rsp_valid), .ext_rsp_ready(core_ext_rsp_ready), .ext_rsp_rdata(core_ext_rsp_rdata),
        .ext_rsp_error(core_ext_rsp_error), .tr_v(tr_v), .tr_pc0(trace_pc), .tr_pc1(trace_pc1),
        .tr_insn0(trace_insn), .tr_insn1(trace_insn1), .tr_trap(unused_trace_irq_valid), .tr_irq(unused_trace_irq),
        .tr_cause(unused_trace_irq_cause), .tr_epc(unused_trace_irq_pc));
    fn_ddr_write_order order_gate(
        .clk(clk), .rst(rst), .failed(order_failed),
        .s_cmd_valid(raw_cmd_valid), .s_cmd_ready(raw_cmd_ready), .s_cmd_write(raw_cmd_write),
        .s_cmd_addr(raw_cmd_addr), .s_cmd_len(raw_cmd_len), .s_w_valid(raw_w_valid), .s_w_ready(raw_w_ready),
        .s_w_data(raw_w_data), .s_w_be(raw_w_be), .s_w_last(raw_w_last),
        .s_r_valid(raw_r_valid), .s_r_ready(raw_r_ready), .s_r_data(raw_r_data), .s_r_error(raw_r_error), .s_r_last(raw_r_last),
        .m_cmd_valid(cmd_valid), .m_cmd_ready(cmd_ready), .m_cmd_write(cmd_write), .m_cmd_addr(cmd_addr), .m_cmd_len(cmd_len),
        .m_w_valid(w_valid), .m_w_ready(w_ready), .m_w_data(w_data), .m_w_be(w_be), .m_w_last(w_last),
        .m_r_valid(r_valid), .m_r_ready(r_ready), .m_r_data(r_data), .m_r_error(r_error), .m_r_last(r_last));
	wire bram_cmd_valid, bram_cmd_ready, bram_w_valid, bram_w_ready;
	wire bram_r_valid, bram_r_ready, bram_r_error, bram_r_last;
	wire [31:0] bram_r_data;
	fn_mem_split #(.SPLIT_ADDR(32'h80020000)) split(
		.clk(clk),
		.rst(rst),
		.cmd_valid(cmd_valid),
		.cmd_ready(cmd_ready),
		.cmd_write(cmd_write),
		.cmd_addr(cmd_addr),
		.cmd_len(cmd_len),
		.w_valid(w_valid),
		.w_ready(w_ready),
		.w_data(w_data),
		.w_be(w_be),
		.w_last(w_last),
		.r_valid(r_valid),
		.r_ready(r_ready),
		.r_data(r_data),
		.r_error(r_error),
		.r_last(r_last),
		.a_cmd_valid(bram_cmd_valid),
		.a_cmd_ready(bram_cmd_ready),
		.a_w_valid(bram_w_valid),
		.a_w_ready(bram_w_ready),
		.a_r_valid(bram_r_valid),
		.a_r_ready(bram_r_ready),
		.a_r_data(bram_r_data),
		.a_r_error(bram_r_error),
		.a_r_last(bram_r_last),
		.b_cmd_valid(core_ddr_cmd_valid),
		.b_cmd_ready(core_ddr_cmd_ready),
		.b_w_valid(core_ddr_w_valid),
		.b_w_ready(core_ddr_w_ready),
		.b_r_valid(core_ddr_r_valid),
		.b_r_ready(core_ddr_r_ready),
		.b_r_data(core_ddr_r_data),
		.b_r_error(core_ddr_r_error),
		.b_r_last(core_ddr_r_last)
	);
	// Boundary register slices: every signal between the CPU region and the
	// platform (MMIO router/GPU hub/pose endpoint, DDR adapter) is a register on
	// both sides. Handshakes and ordering are unchanged; +1 cycle per direction.
	fn_reg_slice #(.W(69)) ext_req_slice(.clk(clk), .rst(rst),
		.s_valid(core_ext_req_valid), .s_ready(core_ext_req_ready),
		.s_data({core_ext_req_write, core_ext_req_be, core_ext_req_addr, core_ext_req_wdata}),
		.m_valid(ext_req_valid), .m_ready(ext_req_ready),
		.m_data({ext_req_write, ext_req_be, ext_req_addr, ext_req_wdata}));
	fn_reg_slice #(.W(33)) ext_rsp_slice(.clk(clk), .rst(rst),
		.s_valid(ext_rsp_valid), .s_ready(ext_rsp_ready),
		.s_data({ext_rsp_error, ext_rsp_rdata}),
		.m_valid(core_ext_rsp_valid), .m_ready(core_ext_rsp_ready),
		.m_data({core_ext_rsp_error, core_ext_rsp_rdata}));
	fn_reg_slice #(.W(41)) ddr_cmd_slice(.clk(clk), .rst(rst),
		.s_valid(core_ddr_cmd_valid), .s_ready(core_ddr_cmd_ready),
		.s_data({cmd_write, cmd_addr, cmd_len}),
		.m_valid(ddr_cmd_valid), .m_ready(ddr_cmd_ready),
		.m_data({ddr_cmd_write, ddr_cmd_addr, ddr_cmd_len}));
	fn_reg_slice #(.W(37)) ddr_w_slice(.clk(clk), .rst(rst),
		.s_valid(core_ddr_w_valid), .s_ready(core_ddr_w_ready),
		.s_data({w_last, w_be, w_data}),
		.m_valid(ddr_w_valid), .m_ready(ddr_w_ready),
		.m_data({ddr_w_last, ddr_w_be, ddr_w_data}));
	fn_reg_slice #(.W(34)) ddr_r_slice(.clk(clk), .rst(rst),
		.s_valid(ddr_r_valid), .s_ready(ddr_r_ready),
		.s_data({ddr_r_last, ddr_r_error, ddr_r_data}),
		.m_valid(core_ddr_r_valid), .m_ready(core_ddr_r_ready),
		.m_data({core_ddr_r_last, core_ddr_r_error, core_ddr_r_data}));
	p2_burst_sram #(
		.RAM_BASE(32'h80000000),
		.RAM_BYTES(32'h00020000),
		._sv2v_width_INIT_FILE(_sv2v_width_INIT_FILE),
		.INIT_FILE(INIT_FILE)
	) memory(
		.clk(clk),
		.rst(rst),
		.cmd_valid(bram_cmd_valid),
		.cmd_ready(bram_cmd_ready),
		.cmd_write(cmd_write),
		.cmd_addr(cmd_addr),
		.cmd_len(cmd_len),
		.w_valid(bram_w_valid),
		.w_ready(bram_w_ready),
		.w_data(w_data),
		.w_be(w_be),
		.w_last(w_last),
		.r_valid(bram_r_valid),
		.r_ready(bram_r_ready),
		.r_data(bram_r_data),
		.r_error(bram_r_error),
		.r_last(bram_r_last)
	);
endmodule

// rtl/cpu/fn_mem_split.v
`timescale 1ns / 1ps
// Burst-port splitter behind the s80 cache arbiter (one transaction at a time).
// Addresses below SPLIT_ADDR go to the block RAM (resident loader, ABI 1/2
// games, boot info); the rest of the cached window goes to the DDR3 bridge.
// The target is chosen when the command is accepted and held until its last
// r-beat (read data, or the single acknowledgement beat of a write).
module fn_mem_split #(
    parameter [31:0] SPLIT_ADDR = 32'h80020000
) (
    input  wire        clk,
    input  wire        rst,
    // from the cache arbiter
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire        cmd_write,
    input  wire [31:0] cmd_addr,
    input  wire [7:0]  cmd_len,
    input  wire        w_valid,
    output wire        w_ready,
    input  wire [31:0] w_data,
    input  wire [3:0]  w_be,
    input  wire        w_last,
    output wire        r_valid,
    input  wire        r_ready,
    output wire [31:0] r_data,
    output wire        r_error,
    output wire        r_last,
    // block RAM
    output wire        a_cmd_valid,
    input  wire        a_cmd_ready,
    output wire        a_w_valid,
    input  wire        a_w_ready,
    input  wire        a_r_valid,
    output wire        a_r_ready,
    input  wire [31:0] a_r_data,
    input  wire        a_r_error,
    input  wire        a_r_last,
    // DDR3 bridge
    output wire        b_cmd_valid,
    input  wire        b_cmd_ready,
    output wire        b_w_valid,
    input  wire        b_w_ready,
    input  wire        b_r_valid,
    output wire        b_r_ready,
    input  wire [31:0] b_r_data,
    input  wire        b_r_error,
    input  wire        b_r_last
);
    reg busy, sel_b;
    wire to_b = cmd_addr >= SPLIT_ADDR;
    wire use_b = busy ? sel_b : to_b;

    assign a_cmd_valid = cmd_valid && !busy && !to_b;
    assign b_cmd_valid = cmd_valid && !busy && to_b;
    assign cmd_ready   = !busy && (to_b ? b_cmd_ready : a_cmd_ready);
    assign a_w_valid   = w_valid && busy && !sel_b;
    assign b_w_valid   = w_valid && busy && sel_b;
    assign w_ready     = busy && (sel_b ? b_w_ready : a_w_ready);
    assign r_valid     = busy && (sel_b ? b_r_valid : a_r_valid);
    assign r_data      = sel_b ? b_r_data : a_r_data;
    assign r_error     = sel_b ? b_r_error : a_r_error;
    assign r_last      = sel_b ? b_r_last : a_r_last;
    assign a_r_ready   = r_ready && busy && !sel_b;
    assign b_r_ready   = r_ready && busy && sel_b;

    always @(posedge clk)
        if (rst) begin
            busy  <= 1'b0;
            sel_b <= 1'b0;
        end else begin
            if (cmd_valid && cmd_ready) begin
                busy  <= 1'b1;
                sel_b <= to_b;
            end else if (r_valid && r_ready && r_last)
                busy <= 1'b0;
        end
    wire unused = &{1'b0, use_b, cmd_write, cmd_len, w_data, w_be, w_last};
endmodule

// rtl/storage/fn_ddr_bridge.v
`timescale 1ns / 1ps
// CPU burst port (p2 cmd/w/r, CPU clock) -> Pango HMIC_S DDR3 AXI (core_clk).
//
// The s80 caches move 32-byte lines; one DDR3 x32 BL8 AXI beat is 256 bits,
// so every cache command maps to exactly one AXI beat (awlen/arlen = 0).
// The CPU address maps 1:1 onto the DDR byte address modulo 64 MiB
// (0x80020000 -> DDR 0x00020000).  Commands of 1..8 words inside one aligned 32-byte block are accepted (byte
// strobes cover partial writes); anything else, or an address outside
// [WINDOW_BASE, WINDOW_BASE+WINDOW_BYTES), returns r_error like p2_burst_sram.
//
// Protocol of the CPU side follows p2_burst_sram: a read returns cmd_len
// r-beats, a write takes cmd_len w-beats and is acknowledged by one r-beat.
// Writes are posted: the acknowledgement is given once the line is queued.
// The DDR-side engine executes queued requests strictly one at a time and in
// order (write data fully taken, then a short guard before the next command),
// so a read can never overtake an earlier write.
//
// HMIC_S AXI subset (as in the vendor example): AXI addresses count 32-bit
// DQ words, write data is pulled with axi_wready (no WVALID), read data is
// pushed with axi_rvalid (no RREADY), and there is no B channel.
//
// Resets: the DDR side is held in reset until calibration (ddr_init_done) and
// whenever the CPU is reset; the CPU side stays in reset until the DDR side
// has left reset, so both FIFO pointer sets always restart together.
module fn_ddr_bridge #(
    parameter [31:0] WINDOW_BASE  = 32'h80020000,
    parameter [31:0] WINDOW_BYTES = 32'h03fe0000,  // up to 0x83ffffff
    parameter integer GUARD_CYCLES = 15,
    parameter integer CTRL_ADDR_WIDTH = 28
) (
    // CPU clock domain
    input  wire        clk,
    input  wire        rst,
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire        cmd_write,
    input  wire [31:0] cmd_addr,
    input  wire [7:0]  cmd_len,
    input  wire        w_valid,
    output wire        w_ready,
    input  wire [31:0] w_data,
    input  wire [3:0]  w_be,
    input  wire        w_last,
    output wire        r_valid,
    input  wire        r_ready,
    output wire [31:0] r_data,
    output wire        r_error,
    output wire        r_last,
    output wire        ddr_ready,        // CPU domain: calibrated and out of reset
    output reg  [15:0] error_count,      // rejected commands (diagnostics)
    // DDR controller clock domain
    input  wire        core_clk,
    input  wire        ddr_init_done,
    output reg  [CTRL_ADDR_WIDTH-1:0] axi_awaddr,
    output reg         axi_awvalid,
    input  wire        axi_awready,
    output wire [255:0] axi_wdata,
    output wire [31:0] axi_wstrb,
    input  wire        axi_wready,
    output reg  [CTRL_ADDR_WIDTH-1:0] axi_araddr,
    output reg         axi_arvalid,
    input  wire        axi_arready,
    input  wire [255:0] axi_rdata,
    input  wire        axi_rvalid,
    input  wire        axi_rlast
);
    localparam integer REQ_W = 1 + 21 + 32 + 256;

    // ------------------------------------------------------------ resets
    reg [2:0] cpu_rst_core = 3'b111;   // CPU reset seen in core_clk
    reg [2:0] core_rst_cpu = 3'b111;   // DDR-side reset seen in clk
    reg [1:0] init_core = 2'b00;
    always @(posedge core_clk or posedge rst)
        if (rst) cpu_rst_core <= 3'b111;
        else     cpu_rst_core <= {cpu_rst_core[1:0], 1'b0};
    always @(posedge core_clk) init_core <= {init_core[0], ddr_init_done};
    wire core_rst = cpu_rst_core[2] || !init_core[1];
    always @(posedge clk or posedge core_rst)
        if (core_rst) core_rst_cpu <= 3'b111;
        else          core_rst_cpu <= {core_rst_cpu[1:0], 1'b0};
    wire bridge_rst = rst || core_rst_cpu[2];
    assign ddr_ready = !bridge_rst;

    // ------------------------------------------------------------ FIFOs
    reg              req_wen;
    reg  [REQ_W-1:0] req_wdata;
    wire             req_full, req_empty;
    wire             req_ren;
    wire [REQ_W-1:0] req_rdata;
    reg              rsp_wen;
    reg  [255:0]     rsp_wdata;
    wire             rsp_full, rsp_empty;
    wire             rsp_ren;
    wire [255:0]     rsp_rdata;
    wire [2:0]       unused_req_level, unused_rsp_level;

    fn_async_fifo #(.DW(REQ_W), .AW(2)) u_req (
        .wclk(clk), .wrst(bridge_rst), .wen(req_wen), .wdata(req_wdata), .wfull(req_full), .wlevel(unused_req_level),
        .rclk(core_clk), .rrst(core_rst), .ren(req_ren), .rdata(req_rdata), .rempty(req_empty));
    fn_async_fifo #(.DW(256), .AW(2)) u_rsp (
        .wclk(core_clk), .wrst(core_rst), .wen(rsp_wen), .wdata(rsp_wdata), .wfull(rsp_full), .wlevel(unused_rsp_level),
        .rclk(clk), .rrst(bridge_rst), .ren(rsp_ren), .rdata(rsp_rdata), .rempty(rsp_empty));

    // ------------------------------------------------------------ CPU side
    localparam [2:0] C_IDLE = 3'd0, C_WDATA = 3'd1, C_WPUSH = 3'd2, C_ACK = 3'd3,
                     C_RWAIT = 3'd4, C_RPOP = 3'd5, C_RDATA = 3'd6;
    reg [2:0]   cstate;
    reg [31:0]  addr_q;
    reg [3:0]   beat;        // word index inside the line for the next beat
    reg [7:0]   remaining;
    reg         bad;
    reg [255:0] line;
    reg [31:0]  strobe;

    wire [32:0] cmd_end = {1'b0, cmd_addr} + {23'd0, cmd_len, 2'b00};
    wire cmd_bad = (cmd_addr[1:0] != 2'd0) || (cmd_len == 8'd0) || (cmd_len > 8'd8) ||
                   ({1'b0, cmd_addr[4:2]} + {1'b0, cmd_len[3:0]} > 5'd8) ||
                   (cmd_addr < WINDOW_BASE) || (cmd_end > {1'b0, WINDOW_BASE} + {1'b0, WINDOW_BYTES});

    assign cmd_ready = (cstate == C_IDLE) && !bridge_rst && !req_full;
    assign w_ready   = (cstate == C_WDATA) && !bridge_rst;
    assign r_valid   = ((cstate == C_ACK) || (cstate == C_RDATA)) && !bridge_rst;
    assign r_last    = (cstate == C_ACK) || (remaining == 8'd1);
    assign r_error   = bad;
    assign r_data    = (bad || cstate != C_RDATA) ? 32'd0 : line[{beat[2:0], 5'd0} +: 32];

    integer lane;
    always @(posedge clk) begin
        req_wen <= 1'b0;
        if (bridge_rst) begin
            cstate      <= C_IDLE;
            bad         <= 1'b0;
            remaining   <= 8'd0;
            beat        <= 4'd0;
            error_count <= 16'd0;
        end else case (cstate)
            C_IDLE: begin
                // R58: req_wdata is consumed only with req_wen, which is never
                // high in C_IDLE; preloading the read request every idle cycle
                // keeps cmd_bad and the handshake off its 310 CEs.
                req_wdata <= {1'b0, cmd_addr[25:5], 32'd0, 256'd0};
                if (cmd_valid && cmd_ready) begin
                    addr_q    <= cmd_addr;
                    beat      <= {1'b0, cmd_addr[4:2]};
                    remaining <= cmd_len;
                    bad       <= cmd_bad;
                    strobe    <= 32'd0;
                    if (cmd_bad) error_count <= error_count + 16'd1;
                    if (cmd_write) cstate <= C_WDATA;
                    else if (cmd_bad) cstate <= C_RDATA;
                    else begin
                        req_wen <= 1'b1;
                        cstate  <= C_RWAIT;
                    end
                end
            end
            C_WDATA: if (w_valid) begin
                if (!bad) begin
                    for (lane = 0; lane < 4; lane = lane + 1)
                        if (w_be[lane]) begin
                            line[{beat[2:0], lane[1:0], 3'd0} +: 8] <= w_data[8 * lane +: 8];
                            strobe[{beat[2:0], lane[1:0]}] <= 1'b1;
                        end
                end
                if (w_last != (remaining == 8'd1)) bad <= 1'b1;
                beat      <= beat + 4'd1;
                remaining <= remaining - 8'd1;
                if (remaining == 8'd1 || w_last) cstate <= C_WPUSH;
            end
            C_WPUSH: begin
                // line/strobe now hold the final beat; queue unless rejected
                if (!bad) begin
                    req_wen   <= 1'b1;
                    req_wdata <= {1'b1, addr_q[25:5], strobe, line};
                end else error_count <= error_count + 16'd1;
                cstate <= C_ACK;
            end
            C_ACK: if (r_ready) cstate <= C_IDLE;
            C_RWAIT: if (!rsp_empty) cstate <= C_RPOP;
            C_RPOP: begin line <= rsp_rdata; cstate <= C_RDATA; end
            C_RDATA: if (r_ready) begin
                beat      <= beat + 4'd1;
                remaining <= remaining - 8'd1;
                if (remaining == 8'd1) cstate <= C_IDLE;
            end
            default: cstate <= C_IDLE;
        endcase
    end
    // FIFO read data is registered on the ren edge: popping while leaving
    // C_RWAIT makes rsp_rdata valid during C_RPOP.
    assign rsp_ren = (cstate == C_RWAIT) && !rsp_empty && !bridge_rst;

    // ------------------------------------------------------------ DDR side
    localparam [2:0] D_IDLE = 3'd0, D_LOAD = 3'd1, D_WADDR = 3'd2, D_WDATA = 3'd3,
                     D_RADDR = 3'd4, D_RDATA = 3'd5, D_GUARD = 3'd6;
    reg [2:0]       dstate;
    reg [REQ_W-1:0] cur;
    reg [7:0]       guard;
    reg             wtaken, aw_done;
    assign req_ren = (dstate == D_IDLE) && !req_empty && !core_rst;
    assign axi_wdata = cur[255:0];
    assign axi_wstrb = cur[287:256];
    wire [CTRL_ADDR_WIDTH-1:0] line_dq_addr = {{(CTRL_ADDR_WIDTH-24){1'b0}}, cur[308:288], 3'b000};

    always @(posedge core_clk) begin
        rsp_wen <= 1'b0;
        if (core_rst) begin
            dstate      <= D_IDLE;
            axi_awvalid <= 1'b0;
            axi_arvalid <= 1'b0;
            guard       <= 8'd0;
            wtaken      <= 1'b0;
            aw_done     <= 1'b0;
        end else case (dstate)
            D_IDLE: if (!req_empty) dstate <= D_LOAD;
            D_LOAD: begin
                // req_rdata is valid in this cycle (registered on the ren edge)
                cur <= req_rdata;
                if (req_rdata[REQ_W-1]) begin
                    axi_awaddr  <= {{(CTRL_ADDR_WIDTH-24){1'b0}}, req_rdata[308:288], 3'b000};
                    axi_awvalid <= 1'b1;
                    wtaken      <= 1'b0;
                    aw_done     <= 1'b0;
                    dstate      <= D_WADDR;
                end else begin
                    axi_araddr  <= {{(CTRL_ADDR_WIDTH-24){1'b0}}, req_rdata[308:288], 3'b000};
                    axi_arvalid <= 1'b1;
                    dstate      <= D_RADDR;
                end
            end
            D_WADDR: begin
                if (axi_wready) wtaken <= 1'b1;
                if (axi_awready) begin axi_awvalid <= 1'b0; dstate <= D_WDATA; end
            end
            D_WDATA: if (axi_wready || wtaken) begin
                guard  <= GUARD_CYCLES[7:0];
                dstate <= D_GUARD;
            end
            D_RADDR: if (axi_arready) begin axi_arvalid <= 1'b0; dstate <= D_RDATA; end
            D_RDATA: if (axi_rvalid) begin
                rsp_wdata <= axi_rdata;
                rsp_wen   <= 1'b1;
                dstate    <= D_IDLE;
            end
            D_GUARD: if (guard == 8'd0) dstate <= D_IDLE; else guard <= guard - 8'd1;
            default: dstate <= D_IDLE;
        endcase
    end
    wire unused = &{1'b0, line_dq_addr, rsp_full, axi_rlast, aw_done};
endmodule

// rtl/storage/fn_uart_link.v
`timescale 1ns / 1ps
// UART install link (CPU clock domain), MMIO window 0x10004E00.
//
//  0x00 R  ID "UAR1"
//  0x04 R  STATUS {16'rx_count, 13'0, overflow, tx_busy, rx_avail}
//  0x08 R  RXDATA {23'0, valid, byte}: reading pops the byte (valid=0: empty)
//  0x0C W  TXDATA byte (ignored while tx_busy)
//  0x10 RW DIVIDER CPU clocks per bit, 16..65535 (reset: 115200 baud)
//  0x14 RW CONTROL bit0: drive the board uart_tx pin from this transmitter
//                  bit1: write 1 to clear the overflow flag
//
// 8N1, LSB first. The receiver samples each bit in its middle after a
// 2-flip-flop synchronizer; a 2 KiB FIFO absorbs a whole sector frame while
// the firmware is busy writing the SD card.
module fn_uart_link #(
    parameter [15:0] RESET_DIVIDER = 16'd1205
) (
    input  wire        clk,
    input  wire        rst,
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
    input  wire        uart_rx,
    output wire        uart_tx,
    output reg         take_tx
);
    reg [15:0] divider;

    // ------------------------------------------------------------ receiver
    reg [2:0]  rx_sync = 3'b111;
    reg        rx_busy;
    reg [15:0] rx_count_down;
    reg [3:0]  rx_bit;
    reg [7:0]  rx_shift;
    reg        rx_push;
    reg [7:0]  rx_byte;
    always @(posedge clk) rx_sync <= {rx_sync[1:0], uart_rx};
    wire rx_in = rx_sync[2];

    always @(posedge clk) begin
        rx_push <= 1'b0;
        if (rst) begin
            rx_busy <= 1'b0;
        end else if (!rx_busy) begin
            if (!rx_in) begin                  // start bit edge
                rx_busy       <= 1'b1;
                rx_bit        <= 4'd0;
                rx_count_down <= {1'b0, divider[15:1]};   // middle of the start bit
            end
        end else if (rx_count_down != 16'd0) begin
            rx_count_down <= rx_count_down - 16'd1;
        end else begin
            rx_count_down <= divider - 16'd1;
            if (rx_bit == 4'd0) begin
                if (rx_in) rx_busy <= 1'b0;    // glitch, not a start bit
                rx_bit <= 4'd1;
            end else if (rx_bit <= 4'd8) begin
                rx_shift <= {rx_in, rx_shift[7:1]};
                rx_bit   <= rx_bit + 4'd1;
            end else begin                     // stop bit
                rx_busy <= 1'b0;
                if (rx_in) begin rx_push <= 1'b1; rx_byte <= rx_shift; end
            end
        end
    end

    // 2 KiB FIFO with a prefetched head byte
    reg [7:0]  fifo [0:2047];
    reg [10:0] wptr, rptr;
    reg [11:0] count;
    reg        head_valid;
    reg [7:0]  head;
    reg        overflow;
    wire       pop;
    wire       fill_head = !head_valid && count != 12'd0;
    always @(posedge clk) if (rx_push && count != 12'd2048) fifo[wptr] <= rx_byte;
    always @(posedge clk) if (fill_head) head <= fifo[rptr];
    always @(posedge clk) begin
        if (rst) begin
            wptr <= 11'd0; rptr <= 11'd0; count <= 12'd0; head_valid <= 1'b0; overflow <= 1'b0;
        end else begin
            if (rx_push) begin
                if (count == 12'd2048) overflow <= 1'b1;
                else wptr <= wptr + 11'd1;
            end
            if (fill_head) begin rptr <= rptr + 11'd1; head_valid <= 1'b1; end
            else if (pop) head_valid <= 1'b0;
            count <= count + ((rx_push && count != 12'd2048) ? 12'd1 : 12'd0) - (fill_head ? 12'd1 : 12'd0);
            if (req_valid && req_ready && req_write && req_addr[7:0] == 8'h14 && req_wdata[1]) overflow <= 1'b0;
        end
    end

    // ------------------------------------------------------------ transmitter
    reg        tx_busy;
    reg [15:0] tx_count_down;
    reg [3:0]  tx_bit;
    reg [9:0]  tx_shift;
    reg        tx_line;
    assign uart_tx = tx_line;
    always @(posedge clk) begin
        if (rst) begin
            tx_busy <= 1'b0;
            tx_line <= 1'b1;
        end else if (!tx_busy) begin
            if (req_valid && req_ready && req_write && req_addr[7:0] == 8'h0c) begin
                tx_busy       <= 1'b1;
                tx_shift      <= {1'b1, req_wdata[7:0], 1'b0};
                tx_bit        <= 4'd0;
                tx_count_down <= 16'd0;
            end
        end else if (tx_count_down != 16'd0) begin
            tx_count_down <= tx_count_down - 16'd1;
        end else if (tx_bit == 4'd10) begin
            tx_busy <= 1'b0;
            tx_line <= 1'b1;
        end else begin
            tx_line       <= tx_shift[0];
            tx_shift      <= {1'b1, tx_shift[9:1]};
            tx_bit        <= tx_bit + 4'd1;
            tx_count_down <= divider - 16'd1;
        end
    end

    // ------------------------------------------------------------ MMIO
    assign req_ready = !rsp_valid;
    assign pop = req_valid && req_ready && !req_write && req_addr[7:0] == 8'h08 && head_valid;
    always @(posedge clk) begin
        if (rst) begin
            rsp_valid <= 1'b0; rsp_error <= 1'b0; rsp_rdata <= 32'd0;
            divider <= RESET_DIVIDER; take_tx <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready) rsp_valid <= 1'b0;
            if (req_valid && req_ready) begin
                rsp_valid <= 1'b1;
                rsp_error <= 1'b0;
                rsp_rdata <= 32'd0;
                if (req_addr[1:0] != 2'd0 || (req_write && req_be != 4'hf)) rsp_error <= 1'b1;
                else if (req_write) case (req_addr[7:0])
                    8'h0c: ;
                    8'h10: if (req_wdata[31:16] != 16'd0 || req_wdata[15:0] < 16'd16) rsp_error <= 1'b1;
                           else divider <= req_wdata[15:0];
                    8'h14: take_tx <= req_wdata[0];
                    default: rsp_error <= 1'b1;
                endcase else case (req_addr[7:0])
                    8'h00: rsp_rdata <= 32'h55415231;
                    8'h04: rsp_rdata <= {4'd0, count, 13'd0, overflow, tx_busy, head_valid};
                    8'h08: rsp_rdata <= {23'd0, head_valid, head};
                    8'h10: rsp_rdata <= {16'd0, divider};
                    8'h14: rsp_rdata <= {31'd0, take_tx};
                    default: rsp_error <= 1'b1;
                endcase
            end
        end
    end
endmodule

// rtl/touch/fn_i2c_master.v
`timescale 1ns / 1ps
// Small, bounded I2C register transaction engine for GT911.
// 16-bit register address, one-byte writes, 1..63-byte burst reads.
// SDA is open drain. SCL is a master output (GT911 does not stretch SCL).
// A NACK aborts through STOP. A stuck-low idle SDA gets nine recovery clocks
// and a STOP, then reports an error so the client can reset the peripheral.
module fn_i2c_master #(
    parameter CLK_HZ = 27000000,
    parameter I2C_HZ = 100000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        read,
    input  wire [15:0] address,
    input  wire [5:0]  length,
    input  wire [7:0]  write_data,
    output reg         busy,
    output reg         done,
    output reg         error,
    output reg         rx_valid,
    output reg  [5:0]  rx_index,
    output reg  [7:0]  rx_data,
    output reg         scl,
    inout  wire        sda
);
    localparam DIV_RAW = (CLK_HZ + I2C_HZ*4 - 1)/(I2C_HZ*4);
    // Three system clocks per quarter cover the SDA synchronizer latency.
    localparam DIV = (DIV_RAW < 3) ? 3 : DIV_RAW;
    localparam [5:0]
        IDLE=0, START0=1, START1=2, START2=3,
        TX0=4, TX1=5, TX2=6, TX3=7,
        TA0=8, TA1=9, TA2=10, TA3=11,
        RESTART0=12, RESTART1=13, RESTART2=14, RESTART3=15,
        RX0=16, RX1=17, RX2=18, RX3=19,
        RA0=20, RA1=21, RA2=22, RA3=23,
        STOP0=24, STOP1=25, STOP2=26, STOP3=27,
        REC0=28, REC1=29, REC2=30, REC3=31,
        START_SETUP=32, START_HOLD=33, RESTART_SETUP=34,
        RESTART_HOLD=35, STOP_SETUP=36, STOP_WAIT=37;
    reg [5:0] state;
    reg [31:0] divider;
    reg sda_low;
    reg [1:0] sda_sync;
    reg reading;
    reg [15:0] addr_latched;
    reg [7:0] data_latched;
    reg [5:0] count_latched;
    reg [5:0] byte_index;
    reg [2:0] bit_index;
    reg [2:0] tx_stage;
    reg [7:0] tx_shift, rx_shift;
    reg ack_ok;
    reg [3:0] recovery_count;
    assign sda = sda_low ? 1'b0 : 1'bz;

    always @(posedge clk) begin
        if (rst)
            sda_sync <= 2'b11;
        else
            sda_sync <= {sda_sync[0], sda};
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            divider <= 0;
            busy <= 0;
            done <= 0;
            error <= 0;
            rx_valid <= 0;
            rx_index <= 0;
            rx_data <= 0;
            scl <= 1;
            sda_low <= 0;
            reading <= 0;
            addr_latched <= 0;
            data_latched <= 0;
            count_latched <= 1;
            byte_index <= 0;
            bit_index <= 7;
            tx_stage <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
            ack_ok <= 0;
            recovery_count <= 0;
        end else begin
            done <= 0;
            rx_valid <= 0;
            if (state == IDLE) begin
                divider <= 0;
                scl <= 1;
                sda_low <= 0;
                if (start) begin
                    reading <= read;
                    addr_latched <= address;
                    data_latched <= write_data;
                    count_latched <= (length == 0) ? 6'd1 : length;
                    byte_index <= 0;
                    bit_index <= 7;
                    tx_stage <= 0;
                    tx_shift <= 8'hba; // 7-bit address 0x5D, write
                    busy <= 1;
                    error <= 0;
                    recovery_count <= 0;
                    if (!sda_sync[1]) begin
                        error <= 1;
                        state <= REC0;
                    end else
                        state <= START0;
                end
            end else if (divider == DIV-1) begin
                divider <= 0;
                case (state)
                    // Standard-mode START/STOP setup and hold need >=4 us,
                    // so each has two quarter ticks at the selected rate.
                    START0: begin
                        scl <= 1;
                        sda_low <= 0;
                        // Check again after the divider delay: immediately
                        // after reset the two-stage input may still read high.
                        if (!sda_sync[1]) begin
                            error <= 1;
                            recovery_count <= 0;
                            state <= REC0;
                        end else state <= START_SETUP;
                    end
                    START_SETUP: state <= START1;
                    START1: begin sda_low <= 1; state <= START_HOLD; end
                    START_HOLD: state <= START2;
                    START2: begin scl <= 0; state <= TX0; end
                    TX0: begin sda_low <= !tx_shift[bit_index]; state <= TX1; end
                    TX1: begin scl <= 1; state <= TX2; end
                    TX2: state <= TX3;
                    TX3: begin
                        scl <= 0;
                        if (bit_index == 0)
                            state <= TA0;
                        else begin bit_index <= bit_index-1'b1; state <= TX0; end
                    end
                    TA0: begin sda_low <= 0; state <= TA1; end
                    TA1: begin scl <= 1; state <= TA2; end
                    TA2: begin ack_ok <= !sda_sync[1]; state <= TA3; end
                    TA3: begin
                        scl <= 0;
                        bit_index <= 7;
                        if (!ack_ok) begin error <= 1; state <= STOP0; end
                        else case (tx_stage)
                            0: begin tx_shift <= addr_latched[15:8]; tx_stage <= 1; state <= TX0; end
                            1: begin tx_shift <= addr_latched[7:0]; tx_stage <= 2; state <= TX0; end
                            2: begin
                                if (reading) state <= RESTART0;
                                else begin tx_shift <= data_latched; tx_stage <= 4; state <= TX0; end
                            end
                            3: begin rx_shift <= 0; state <= RX0; end
                            default: state <= STOP0;
                        endcase
                    end
                    RESTART0: begin sda_low <= 0; state <= RESTART1; end
                    RESTART1: begin scl <= 1; state <= RESTART_SETUP; end
                    RESTART_SETUP: state <= RESTART2;
                    RESTART2: begin sda_low <= 1; state <= RESTART_HOLD; end
                    RESTART_HOLD: state <= RESTART3;
                    RESTART3: begin
                        scl <= 0;
                        tx_shift <= 8'hbb;
                        tx_stage <= 3;
                        state <= TX0;
                    end
                    RX0: begin sda_low <= 0; state <= RX1; end
                    RX1: begin scl <= 1; state <= RX2; end
                    RX2: begin rx_shift <= {rx_shift[6:0], sda_sync[1]}; state <= RX3; end
                    RX3: begin
                        scl <= 0;
                        if (bit_index == 0) begin
                            rx_data <= rx_shift;
                            rx_index <= byte_index;
                            rx_valid <= 1;
                            state <= RA0;
                        end else begin bit_index <= bit_index-1'b1; state <= RX0; end
                    end
                    RA0: begin
                        // ACK every byte except the final byte, which is NACKed.
                        sda_low <= (byte_index+1'b1 < count_latched);
                        state <= RA1;
                    end
                    RA1: begin scl <= 1; state <= RA2; end
                    RA2: state <= RA3;
                    RA3: begin
                        scl <= 0;
                        if (byte_index+1'b1 >= count_latched)
                            state <= STOP0;
                        else begin
                            byte_index <= byte_index+1'b1;
                            bit_index <= 7;
                            state <= RX0;
                        end
                    end
                    STOP0: begin scl <= 0; sda_low <= 1; state <= STOP1; end
                    STOP1: begin scl <= 1; state <= STOP_SETUP; end
                    STOP_SETUP: state <= STOP2;
                    STOP2: begin sda_low <= 0; state <= STOP_WAIT; end
                    STOP_WAIT: state <= STOP3;
                    STOP3: begin
                        if (!sda_sync[1]) error <= 1;
                        busy <= 0;
                        done <= 1;
                        state <= IDLE;
                    end
                    REC0: begin scl <= 0; sda_low <= 0; state <= REC1; end
                    REC1: begin scl <= 1; state <= REC2; end
                    REC2: state <= REC3;
                    REC3: begin
                        scl <= 0;
                        if (recovery_count == 8) state <= STOP0;
                        else begin recovery_count <= recovery_count+1'b1; state <= REC0; end
                    end
                    default: begin error <= 1; state <= STOP0; end
                endcase
            end else
                divider <= divider+1'b1;
        end
    end
endmodule

// rtl/touch/fn_gt911.v
`timescale 1ns / 1ps
// GT911 single-finger host. The sensor configuration/calibration is preserved.
// Register layout follows the GOODIX GT911 Programming Guide: 0x814e status,
// 0x814f + 8*n point records, ASCII product ID at 0x8140.
// Reference: https://www.lcd-module.de/fileadmin/eng/pdf/zubehoer/GT911_Programming_Guide_Rev.10.pdf
// Every publication changes state/xy/seq/errors together with sample_valid.
// state: bit0 down, bit1 ID/init OK, bit2 fault, bits7:4 count, bits15:8 ID.
// xy: x[15:0], y[31:16]. A released or faulty sample always has count/ID/xy=0.
// Simulation: lower CLK_HZ (e.g. 1000000), I2C_HZ (e.g. 100000), and the
// millisecond parameters. The mandatory INT-low hold also scales with CLK_HZ.
module fn_gt911 #(
    parameter CLK_HZ = 27000000,
    parameter I2C_HZ = 100000,
    parameter RESET_LOW_MS = 20,
    parameter RESET_WAIT_MS = 100,
    parameter INT_HOLD_MS = 55,
    parameter POLL_MS = 5,
    parameter STALE_MS = 150
) (
    input  wire        clk,
    input  wire        rst,
    output wire        ctp_rst_n,
    inout  wire        ctp_int,
    output wire        scl,
    inout  wire        sda,
    output reg         sample_valid,
    output reg  [31:0] sample_state,
    output reg  [31:0] sample_xy,
    output reg [127:0] sample_xy_extra,
    output reg [39:0] sample_ids,
    output reg  [31:0] sample_seq,
    output reg  [31:0] sample_errors
);
    localparam CYCLES_MS = (CLK_HZ/1000 < 1) ? 1 : CLK_HZ/1000;
    localparam RESET_CYCLES = (RESET_LOW_MS < 1) ? 1 : CYCLES_MS*RESET_LOW_MS;
    localparam WAIT_CYCLES = (RESET_WAIT_MS < 1) ? 1 : CYCLES_MS*RESET_WAIT_MS;
    localparam POLL_CYCLES = (POLL_MS < 1) ? 1 : CYCLES_MS*POLL_MS;
    localparam STALE_CYCLES = (STALE_MS < 1) ? 1 : CYCLES_MS*STALE_MS;
    localparam INT_HOLD_CYCLES = (INT_HOLD_MS < 1) ? 1 : CYCLES_MS*INT_HOLD_MS;
    localparam [3:0]
        RESET_LOW=0, INT_HOLD=1, BOOT_WAIT=2, ID_START=3, ID_WAIT=4,
        IDLE=5, STATUS_START=6, STATUS_WAIT=7, POINT_START=8,
        POINT_WAIT=9, CLEAR_START=10, CLEAR_WAIT=11, FAIL=12;
    reg [3:0] state;
    reg [31:0] timer, stale_timer;
    reg [23:0] product_id;
    reg [7:0] status_byte;
    reg [3:0] point_count;
    reg [7:0] point_id;
    reg [15:0] point_x, point_y;
    reg [159:0] all_points;
    reg [39:0] all_ids;
    reg bad_frame;
    reg i2c_start, i2c_read;
    reg [15:0] i2c_addr;
    reg [5:0] i2c_length;
    wire i2c_busy, i2c_done, i2c_error, rx_valid;
    wire [5:0] rx_index;
    wire [7:0] rx_data;
    wire resetting = (state == RESET_LOW || state == INT_HOLD || state == BOOT_WAIT);
    assign ctp_rst_n = !rst && (state != RESET_LOW);
    // INT=0 selects 0x5D. Keep low through the reset edge and INT_HOLD_MS
    // afterwards, then float for RESET_WAIT_MS before accessing I2C. Defaults
    // satisfy the >50 ms hold/settle requirements; testbenches may shorten
    // both parameters. Never drive INT high.
    assign ctp_int = (rst || state == RESET_LOW || state == INT_HOLD) ? 1'b0 : 1'bz;

    fn_i2c_master #(.CLK_HZ(CLK_HZ), .I2C_HZ(I2C_HZ)) u_i2c (
        .clk(clk), .rst(rst || resetting), .start(i2c_start),
        .read(i2c_read), .address(i2c_addr), .length(i2c_length),
        .write_data(8'h00), .busy(i2c_busy), .done(i2c_done),
        .error(i2c_error), .rx_valid(rx_valid), .rx_index(rx_index),
        .rx_data(rx_data), .scl(scl), .sda(sda)
    );

    task publish;
        input [31:0] new_state;
        input [31:0] new_xy;
        input add_error;
        begin
            sample_valid <= 1;
            sample_state <= new_state;
            sample_xy <= new_xy;
            sample_xy_extra <= new_state[0] ? all_points[159:32] : 128'd0;
            sample_ids <= new_state[0] ? all_ids : 40'd0;
            sample_seq <= sample_seq+1'b1;
            sample_errors <= sample_errors+add_error;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state <= RESET_LOW;
            timer <= 0;
            stale_timer <= 0;
            product_id <= 0;
            status_byte <= 0;
            point_count <= 0;
            point_id <= 0;
            point_x <= 0;
            point_y <= 0;
            all_points <= 0;
            all_ids <= 0;
            bad_frame <= 0;
            i2c_start <= 0;
            i2c_read <= 1;
            i2c_addr <= 0;
            i2c_length <= 1;
            sample_valid <= 0;
            sample_state <= 0;
            sample_xy <= 0;
            sample_xy_extra <= 0;
            sample_ids <= 0;
            sample_seq <= 0;
            sample_errors <= 0;
        end else begin
            sample_valid <= 0;
            i2c_start <= 0;
            if (!sample_state[0])
                stale_timer <= 0;
            else if (stale_timer < STALE_CYCLES)
                stale_timer <= stale_timer+1'b1;

            // Byte events precede i2c_done, so complete buffers are stable when
            // the state below examines a completed transaction.
            if (rx_valid) begin
                if (state == ID_WAIT) begin
                    case (rx_index)
                        0: product_id[7:0] <= rx_data;
                        1: product_id[15:8] <= rx_data;
                        2: product_id[23:16] <= rx_data;
                        default: begin end
                    endcase
                end else if (state == STATUS_WAIT)
                    status_byte <= rx_data;
                else if (state == POINT_WAIT) begin
                    // Keep the legacy first-contact register and publish all
                    // other coordinates atomically in the extended mailbox.
                    case (rx_index[2:0])
                        0: all_ids[rx_index[5:3]*8 +: 8] <= rx_data;
                        1: all_points[rx_index[5:3]*32 +: 8] <= rx_data;
                        2: all_points[rx_index[5:3]*32+8 +: 8] <= rx_data;
                        3: all_points[rx_index[5:3]*32+16 +: 8] <= rx_data;
                        4: all_points[rx_index[5:3]*32+24 +: 8] <= rx_data;
                        default: begin end
                    endcase
                    case (rx_index)
                        0: point_id <= rx_data;
                        1: point_x[7:0] <= rx_data;
                        2: point_x[15:8] <= rx_data;
                        3: point_y[7:0] <= rx_data;
                        4: point_y[15:8] <= rx_data;
                        default: begin end
                    endcase
                end
            end

            case (state)
                RESET_LOW: begin
                    if (timer >= RESET_CYCLES-1) begin timer <= 0; state <= INT_HOLD; end
                    else timer <= timer+1'b1;
                end
                INT_HOLD: begin
                    if (timer >= INT_HOLD_CYCLES-1) begin timer <= 0; state <= BOOT_WAIT; end
                    else timer <= timer+1'b1;
                end
                BOOT_WAIT: begin
                    if (timer >= WAIT_CYCLES-1) begin timer <= 0; state <= ID_START; end
                    else timer <= timer+1'b1;
                end
                ID_START: begin
                    i2c_addr <= 16'h8140;
                    i2c_read <= 1;
                    i2c_length <= 4;
                    i2c_start <= 1;
                    product_id <= 0;
                    state <= ID_WAIT;
                end
                ID_WAIT: if (i2c_done) begin
                    if (i2c_error || product_id != 24'h313139)
                        state <= FAIL;
                    else begin
                        // Re-identification proves connectivity, not a real
                        // finger-up event. Preserve a fault after recovery
                        // until a fresh ready frame establishes touch state.
                        // This prevents a held finger from rearming actions
                        // when the bus briefly fails and the sensor resets.
                        publish((sample_errors == 0) ? 32'h00000002 : 32'h00000006,
                                32'h0, 1'b0);
                        timer <= 0;
                        state <= IDLE;
                    end
                end
                IDLE: begin
                    // A sensor that stops producing frames must never leave
                    // the game cutting forever. Keep polling after release.
                    if (sample_state[0] && stale_timer >= STALE_CYCLES) begin
                        publish(32'h00000006, 32'h0, 1'b1);
                        stale_timer <= 0;
                    end
                    if (timer >= POLL_CYCLES-1) begin timer <= 0; state <= STATUS_START; end
                    else timer <= timer+1'b1;
                end
                STATUS_START: begin
                    i2c_addr <= 16'h814e;
                    i2c_read <= 1;
                    i2c_length <= 1;
                    i2c_start <= 1;
                    state <= STATUS_WAIT;
                end
                STATUS_WAIT: if (i2c_done) begin
                    if (i2c_error)
                        state <= FAIL;
                    else if (!status_byte[7]) begin
                        timer <= 0;
                        state <= IDLE;
                    end else begin
                        point_count <= status_byte[3:0];
                        point_id <= 0;
                        point_x <= 0;
                        point_y <= 0;
                        all_points <= 0;
                        all_ids <= 0;
                        bad_frame <= (status_byte[3:0] > 5);
                        if (status_byte[3:0] == 0 || status_byte[3:0] > 5)
                            state <= CLEAR_START;
                        else
                            state <= POINT_START;
                    end
                end
                POINT_START: begin
                    i2c_addr <= 16'h814f;
                    i2c_read <= 1;
                    i2c_length <= {point_count[2:0], 3'b000};
                    i2c_start <= 1;
                    state <= POINT_WAIT;
                end
                POINT_WAIT: if (i2c_done) begin
                    if (i2c_error) state <= FAIL;
                    else state <= CLEAR_START;
                end
                CLEAR_START: begin
                    i2c_addr <= 16'h814e;
                    i2c_read <= 0;
                    i2c_length <= 1;
                    i2c_start <= 1;
                    state <= CLEAR_WAIT;
                end
                CLEAR_WAIT: if (i2c_done) begin
                    if (i2c_error)
                        state <= FAIL;
                    else begin
                        if (bad_frame)
                            publish(32'h00000006, 32'h0, 1'b1);
                        else if (point_count == 0)
                            publish(32'h00000002, 32'h0, 1'b0);
                        else
                            publish({16'b0, point_id, point_count, 4'b0011},
                                    {point_y, point_x}, 1'b0);
                        stale_timer <= 0;
                        timer <= 0;
                        state <= IDLE;
                    end
                end
                FAIL: begin
                    // Publish an explicit release, then rerun reset/address/ID.
                    publish(32'h00000004, 32'h0, 1'b1);
                    stale_timer <= 0;
                    timer <= 0;
                    state <= RESET_LOW;
                end
                default: begin timer <= 0; state <= FAIL; end
            endcase
        end
    end
endmodule

// rtl/touch/fn_touch_cdc.v
`timescale 1ns / 1ps
// Coherent latest-sample mailbox. Payload remains held until the destination
// acknowledges the synchronized request; new samples wait in a pending slot.
// Both resets derive from the same system reset (async assert, sync release).
module fn_touch_cdc (
    input wire src_clk, input wire src_rst, input wire src_valid,
    input wire [31:0] src_state, src_xy, src_seq, src_errors,
    input wire [127:0] src_xy_extra,
    input wire [39:0] src_ids,
    input wire dst_clk, input wire dst_rst,
    output reg [31:0] dst_state, dst_xy, dst_seq, dst_errors,
    output reg [127:0] dst_xy_extra,
    output reg [39:0] dst_ids
);
    reg [295:0] pending, held;
    reg dirty, request;
    reg ack;
    reg ack_s1, ack_s2;
    reg req_s1, req_s2;
    always @(posedge src_clk or posedge src_rst) begin
        if (src_rst) begin
            pending <= 296'd0;
            held <= 296'd0;
            dirty <= 1'b0;
            request <= 1'b0;
            ack_s1 <= 1'b0;
            ack_s2 <= 1'b0;
        end else begin
            ack_s1 <= ack;
            ack_s2 <= ack_s1;
            if (dirty && request == ack_s2) begin
                held <= pending;
                request <= ~request;
                dirty <= 1'b0;
            end
            // Last assignment wins when publishing the previous pending sample.
            if (src_valid) begin
                pending <= {src_state, src_xy, src_seq, src_errors, src_xy_extra, src_ids};
                dirty <= 1'b1;
            end
        end
    end
    always @(posedge dst_clk or posedge dst_rst) begin
        if (dst_rst) begin
            req_s1 <= 1'b0;
            req_s2 <= 1'b0;
            ack <= 1'b0;
            dst_state <= 32'd0;
            dst_xy <= 32'd0;
            dst_seq <= 32'd0;
            dst_errors <= 32'd0;
            dst_xy_extra <= 128'd0;
            dst_ids <= 40'd0;
        end else begin
            req_s1 <= request;
            req_s2 <= req_s1;
            if (req_s2 != ack) begin
                {dst_state, dst_xy, dst_seq, dst_errors, dst_xy_extra, dst_ids} <= held;
                ack <= req_s2;
            end
        end
    end
endmodule

// rtl/video/fn_async_fifo.v
`timescale 1ns / 1ps
// Dual-clock FIFO (gray-coded pointers, 2-FF synchronisers).
// Write side lives in the CPU clock domain, read side in the pixel domain.
// Read data is registered: assert ren while !rempty, data is valid next cycle.
module fn_async_fifo #(
    parameter DW = 38,
    parameter AW = 10
) (
    input  wire          wclk,
    input  wire          wrst,
    input  wire          wen,
    input  wire [DW-1:0] wdata,
    output reg           wfull,
    output reg  [AW:0]   wlevel,

    input  wire          rclk,
    input  wire          rrst,
    input  wire          ren,
    output reg  [DW-1:0] rdata,
    output reg           rempty
);
    function [AW:0] gray2bin;
        input [AW:0] g;
        integer k;
        begin
            gray2bin[AW] = g[AW];
            for (k = AW - 1; k >= 0; k = k - 1)
                gray2bin[k] = gray2bin[k + 1] ^ g[k];
        end
    endfunction

    reg [DW-1:0] mem [0:(1 << AW) - 1];

    // ------------------------------------------------------------ write side
    reg  [AW:0] wbin, wgray;
    reg  [AW:0] rgray_s1, rgray_s2;
    reg  [AW:0] rbin_w;
    reg  [AW:0] rgray;
    wire        wpush   = wen & ~wfull;
    wire [AW:0] wbin_n  = wbin + {{AW{1'b0}}, wpush};
    wire [AW:0] wgray_n = (wbin_n >> 1) ^ wbin_n;

    always @(posedge wclk)
        if (wpush) mem[wbin[AW-1:0]] <= wdata;

    always @(posedge wclk) begin
        if (wrst) begin
            wbin     <= {(AW + 1){1'b0}};
            wgray    <= {(AW + 1){1'b0}};
            rgray_s1 <= {(AW + 1){1'b0}};
            rgray_s2 <= {(AW + 1){1'b0}};
            rbin_w   <= {(AW + 1){1'b0}};
            wfull    <= 1'b0;
            wlevel   <= {(AW + 1){1'b0}};
        end else begin
            wbin     <= wbin_n;
            wgray    <= wgray_n;
            rgray_s1 <= rgray;
            rgray_s2 <= rgray_s1;
            rbin_w   <= gray2bin(rgray_s2);
            wfull    <= (wgray_n == {~rgray_s2[AW:AW-1], rgray_s2[AW-2:0]});
            wlevel   <= wbin - rbin_w;
        end
    end

    // ------------------------------------------------------------ read side
    reg  [AW:0] rbin;
    reg  [AW:0] wgray_s1, wgray_s2;
    wire        rpop    = ren & ~rempty;
    wire [AW:0] rbin_n  = rbin + {{AW{1'b0}}, rpop};
    wire [AW:0] rgray_n = (rbin_n >> 1) ^ rbin_n;

    always @(posedge rclk)
        if (rpop) rdata <= mem[rbin[AW-1:0]];

    always @(posedge rclk) begin
        if (rrst) begin
            rbin     <= {(AW + 1){1'b0}};
            rgray    <= {(AW + 1){1'b0}};
            wgray_s1 <= {(AW + 1){1'b0}};
            wgray_s2 <= {(AW + 1){1'b0}};
            rempty   <= 1'b1;
        end else begin
            rbin     <= rbin_n;
            rgray    <= rgray_n;
            wgray_s1 <= wgray;
            wgray_s2 <= wgray_s1;
            rempty   <= (rgray_n == wgray_s2);
        end
    end
endmodule
module fn_async_fifo_rfan #(
    parameter DW = 38,
    parameter AW = 10
) (
    input  wire          wclk,
    input  wire          wrst,
    input  wire          wen,
    input  wire [DW-1:0] wdata,
    output reg           wfull,
    output reg  [AW:0]   wlevel,

    input  wire          rclk,
    input  wire          rrst,
    input  wire          ren,
    output reg  [DW-1:0] rdata,
    output reg           rempty
);
    function [AW:0] gray2bin;
        input [AW:0] g;
        integer k;
        begin
            gray2bin[AW] = g[AW];
            for (k = AW - 1; k >= 0; k = k - 1)
                gray2bin[k] = gray2bin[k + 1] ^ g[k];
        end
    endfunction

    reg [DW-1:0] mem [0:(1 << AW) - 1];

    // ------------------------------------------------------------ write side
    reg  [AW:0] wbin, wgray;
    reg  [AW:0] rgray_s1, rgray_s2;
    reg  [AW:0] rbin_w;
    reg  [AW:0] rgray;
    wire        wpush   = wen & ~wfull;
    wire [AW:0] wbin_n  = wbin + {{AW{1'b0}}, wpush};
    wire [AW:0] wgray_n = (wbin_n >> 1) ^ wbin_n;

    always @(posedge wclk)
        if (wpush) mem[wbin[AW-1:0]] <= wdata;

    always @(posedge wclk) begin
        if (wrst) begin
            wbin     <= {(AW + 1){1'b0}};
            wgray    <= {(AW + 1){1'b0}};
            rgray_s1 <= {(AW + 1){1'b0}};
            rgray_s2 <= {(AW + 1){1'b0}};
            rbin_w   <= {(AW + 1){1'b0}};
            wfull    <= 1'b0;
            wlevel   <= {(AW + 1){1'b0}};
        end else begin
            wbin     <= wbin_n;
            wgray    <= wgray_n;
            rgray_s1 <= rgray;
            rgray_s2 <= rgray_s1;
            rbin_w   <= gray2bin(rgray_s2);
            wfull    <= (wgray_n == {~rgray_s2[AW:AW-1], rgray_s2[AW-2:0]});
            wlevel   <= wbin - rbin_w;
        end
    end

    // ------------------------------------------------------------ read side
    // R70: replicate the read pointer that addresses the wide distributed RAM.
    (* syn_maxfan = 16 *) reg  [AW:0] rbin;
    reg  [AW:0] wgray_s1, wgray_s2;
    wire        rpop    = ren & ~rempty;
    wire [AW:0] rbin_n  = rbin + {{AW{1'b0}}, rpop};
    wire [AW:0] rgray_n = (rbin_n >> 1) ^ rbin_n;

    always @(posedge rclk)
        if (rpop) rdata <= mem[rbin[AW-1:0]];

    always @(posedge rclk) begin
        if (rrst) begin
            rbin     <= {(AW + 1){1'b0}};
            rgray    <= {(AW + 1){1'b0}};
            wgray_s1 <= {(AW + 1){1'b0}};
            wgray_s2 <= {(AW + 1){1'b0}};
            rempty   <= 1'b1;
        end else begin
            rbin     <= rbin_n;
            rgray    <= rgray_n;
            wgray_s1 <= wgray;
            wgray_s2 <= wgray_s1;
            rempty   <= (rgray_n == wgray_s2);
        end
    end
endmodule

// rtl/video/fn_mmio_hub.v
`timescale 1ns / 1ps
// CPU-domain MMIO slave for the display engine window (4 KiB at BASE).
//
// Protocol matches p2_soc's accelerator route: one request is accepted when
// req_valid && req_ready; exactly one registered response follows.
//
//  write  0x000-0x0FC : GPU command, pushed as {offset[7:2], wdata} into the
//                       pixel-domain command FIFO (full 32-bit stores only;
//                       the store stalls while the FIFO is full)
//  read   0x000 ID      "FNG1"
//         0x004 STATUS  [0] fifo empty [1] fifo full [2] gpu idle [3] vblank
//                       [31:16] free FIFO entries
//         0x008 FRAME   display frame counter (16 bit)
//         0x00C SWAPS   completed buffer swaps (16 bit)
//         0x010 FBSIZE  {height, width} of the framebuffer
//         0x014 LCDSIZE {height, width} of the panel
//         0x018 CLOCK   CPU clock in Hz
//         0x100 TOUCH_STATE (read latches a coherent XY/SEQ/ERRORS snapshot)
//         0x104 TOUCH_XY    {y[15:0], x[15:0]} in panel pixels
//         0x108 TOUCH_SEQ   sample publication counter
//         0x10C TOUCH_ERRORS cumulative communication/invalid-frame errors
//  anything else reads 0 / write is ignored (no bus error).
module fn_mmio_hub #(
    parameter [31:0] CLOCK_HZ = 32'd138857143,
    parameter        FIFO_AW  = 10
) (
    input  wire        clk,
    input  wire        rst,

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

    output wire               cmd_wen,
    output wire [37:0]        cmd_wdata,
    input  wire               cmd_full,
    input  wire [FIFO_AW:0]   cmd_level,

    input  wire [15:0] pix_frame_gray,
    input  wire [15:0] pix_swap_gray,
    input  wire        pix_idle,
    input  wire        pix_vblank,
    input  wire [31:0] touch_state,
    input  wire [31:0] touch_xy,
    input  wire [31:0] touch_seq,
    input  wire [31:0] touch_errors,
    input  wire [127:0] touch_xy_extra,
    input  wire [39:0] touch_ids
);
    localparam [31:0] ID_VALUE = 32'h464E4731;   // "FNG1"
    localparam [FIFO_AW:0] DEPTH = 1 << FIFO_AW;

    function [15:0] gray2bin16;
        input [15:0] g;
        integer k;
        begin
            gray2bin16[15] = g[15];
            for (k = 14; k >= 0; k = k - 1)
                gray2bin16[k] = gray2bin16[k + 1] ^ g[k];
        end
    endfunction

    wire [11:0] off    = req_addr[11:0];
    wire        is_cmd = (off[11:8] == 4'd0);
    wire        stall  = req_write && is_cmd && cmd_full;

    assign req_ready = !rsp_valid && !stall;
    wire   accept    = req_valid && req_ready;

    assign cmd_wen   = accept && req_write && is_cmd && (req_be == 4'hF);
    assign cmd_wdata = {off[7:2], req_wdata};

    // ------------------------------------------------ status synchronisers
    reg [15:0] frame_g1, frame_g2, swap_g1, swap_g2;
    reg        idle_s1, idle_s2, vb_s1, vb_s2;
    reg [15:0] frame_bin, swap_bin;
    reg [15:0] free_q;
    always @(posedge clk) begin
        frame_g1  <= pix_frame_gray;
        frame_g2  <= frame_g1;
        swap_g1   <= pix_swap_gray;
        swap_g2   <= swap_g1;
        idle_s1   <= pix_idle;
        idle_s2   <= idle_s1;
        vb_s1     <= pix_vblank;
        vb_s2     <= vb_s1;
        frame_bin <= gray2bin16(frame_g2);
        swap_bin  <= gray2bin16(swap_g2);
        free_q    <= DEPTH - cmd_level;
    end

    wire fifo_empty = (cmd_level == {(FIFO_AW + 1){1'b0}});

    reg [31:0] touch_xy_snap, touch_seq_snap, touch_errors_snap;
    reg [127:0] touch_xy_extra_snap;
    reg [39:0] touch_ids_snap;
    reg [31:0] rd_mux;
    always @(*) begin
        case (off)
            12'h000: rd_mux = ID_VALUE;
            12'h004: rd_mux = {free_q, 12'd0, vb_s2, idle_s2 & fifo_empty, cmd_full, fifo_empty};
            12'h008: rd_mux = {16'd0, frame_bin};
            12'h00C: rd_mux = {16'd0, swap_bin};
            12'h010: rd_mux = {16'd300, 16'd512};
            12'h014: rd_mux = {16'd600, 16'd1024};
            12'h018: rd_mux = CLOCK_HZ;
            12'h100: rd_mux = touch_state;
            12'h104: rd_mux = touch_xy_snap;
            12'h108: rd_mux = touch_seq_snap;
            12'h10C: rd_mux = touch_errors_snap;
            12'h110: rd_mux = touch_xy_extra_snap[31:0];
            12'h114: rd_mux = touch_xy_extra_snap[63:32];
            12'h118: rd_mux = touch_xy_extra_snap[95:64];
            12'h11C: rd_mux = touch_xy_extra_snap[127:96];
            12'h120: rd_mux = touch_ids_snap[31:0];
            12'h124: rd_mux = 32'h54435035; // TCP5: extended coherent touch ABI
            12'h128: rd_mux = {24'd0,touch_ids_snap[39:32]};
            12'h12C: rd_mux = 32'h54494435; // TID5: coherent five-contact track IDs
            default: rd_mux = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            rsp_valid <= 1'b0;
            rsp_rdata <= 32'd0;
            rsp_error <= 1'b0;
            touch_xy_snap <= 32'd0;
            touch_seq_snap <= 32'd0;
            touch_errors_snap <= 32'd0;
            touch_xy_extra_snap <= 128'd0;
            touch_ids_snap <= 40'd0;
        end else begin
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;
            if (accept) begin
                if (!req_write && off == 12'h100) begin
                    touch_xy_snap <= touch_xy;
                    touch_seq_snap <= touch_seq;
                    touch_errors_snap <= touch_errors;
                    touch_xy_extra_snap <= touch_xy_extra;
                    touch_ids_snap <= touch_ids;
                end
                rsp_valid <= 1'b1;
                rsp_error <= 1'b0;
                rsp_rdata <= req_write ? 32'd0 : rd_mux;
            end
        end
    end
endmodule

// rtl/video/fn_video_timing.v
`timescale 1ns / 1ps
// 1024x600 LCD timing, same parameters and HS/VS/DE phase relationship as the
// 7-inch panel reference design (color_bar.v): per line FP, SYNC, BP, ACTIVE;
// the line counter advances at the start of HSYNC, so VS edges line up with
// HS leading edges.  All outputs are registered and mutually aligned.
module fn_video_timing #(
    parameter H_ACTIVE = 1024,
    parameter H_FP     = 160,
    parameter H_SYNC   = 20,
    parameter H_BP     = 140,
    parameter V_ACTIVE = 600,
    parameter V_FP     = 12,
    parameter V_SYNC   = 3,
    parameter V_BP     = 20,
    parameter HS_POL   = 1'b0,
    parameter VS_POL   = 1'b0
) (
    input  wire        clk,
    input  wire        rst,
    output reg         hs,
    output reg         vs,
    output reg         de,
    output reg  [10:0] x,
    output reg  [9:0]  y,
    output reg         frame_latch,   // one pulse per frame, inside vblank, before line 0
    output reg         vblank
);
    localparam H_START = H_FP + H_SYNC + H_BP;
    localparam V_START = V_FP + V_SYNC + V_BP;
    localparam H_TOTAL = H_START + H_ACTIVE;
    localparam V_TOTAL = V_START + V_ACTIVE;

    reg [10:0] hc;
    reg [9:0]  vc;

    always @(posedge clk) begin
        if (rst) begin
            hc <= 11'd0;
            vc <= 10'd0;
        end else begin
            hc <= (hc == H_TOTAL - 1) ? 11'd0 : hc + 11'd1;
            if (hc == H_FP - 1)
                vc <= (vc == V_TOTAL - 1) ? 10'd0 : vc + 10'd1;
        end
    end

    wire h_act = (hc >= H_START);
    wire v_act = (vc >= V_START);

    always @(posedge clk) begin
        if (rst) begin
            hs          <= ~HS_POL;
            vs          <= ~VS_POL;
            de          <= 1'b0;
            x           <= 11'd0;
            y           <= 10'd0;
            frame_latch <= 1'b0;
            vblank      <= 1'b1;
        end else begin
            hs          <= ((hc >= H_FP) && (hc < H_FP + H_SYNC)) ? HS_POL : ~HS_POL;
            vs          <= ((vc >= V_FP) && (vc < V_FP + V_SYNC)) ? VS_POL : ~VS_POL;
            de          <= h_act && v_act;
            x           <= hc - H_START;
            y           <= vc - V_START;
            frame_latch <= (vc == V_START - 1) && (hc == 11'd0);
            vblank      <= !v_act;
        end
    end
endmodule

// rtl/video/fn_framebuffer.v
`timescale 1ns / 1ps
// Double-buffered 512x300 8bpp framebuffer.
//
// Each buffer is split into 38 banks of 8 lines x 512 pixels = 4096 bytes, so
// every bank maps onto exactly one 36 Kb DRM (4K x 9) and no depth rounding
// wastes memory (2 x 38 = 76 DRMs).  The rasterizer only ever writes the draw
// buffer and scan-out only reads the display buffer, so a bank never sees a
// read and a write from different agents at the same time.
//
// Write port: registered once, then written (2 cycle write latency).
// Read port : rdata valid 2 cycles after rbuf/rx/ry.
module fn_fb_bank (
    input  wire        clk,
    input  wire        we,
    input  wire [11:0] waddr,
    input  wire [7:0]  wdata,
    input  wire [11:0] raddr,
    output reg  [7:0]  rdata
);
    reg [7:0] mem [0:4095];
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule

module fn_framebuffer #(
    parameter FB_H = 300
) (
    input  wire       clk,
    input  wire       we,
    input  wire       wbuf,
    input  wire [8:0] wx,
    input  wire [8:0] wy,
    input  wire [7:0] wdata,
    input  wire       rbuf,
    input  wire [8:0] rx,
    input  wire [8:0] ry,
    output reg  [7:0] rdata
);
    localparam NB = (FB_H + 7) / 8;

    reg        we_q;
    reg        wbuf_q;
    reg [5:0]  wbank_q;
    reg [11:0] waddr_q;
    reg [7:0]  wdata_q;
    always @(posedge clk) begin
        we_q    <= we;
        wbuf_q  <= wbuf;
        wbank_q <= wy[8:3];
        waddr_q <= {wy[2:0], wx};
        wdata_q <= wdata;
    end

    wire [11:0] raddr = {ry[2:0], rx};
    reg  [6:0]  rsel_q;
    always @(posedge clk) rsel_q <= {rbuf, ry[8:3]};

    // bank outputs, indexed {buffer, bank} with 64 slots per buffer
    wire [8 * 128 - 1:0] q_flat;

    genvar b, k;
    generate
        for (b = 0; b < 2; b = b + 1) begin : buffer
            for (k = 0; k < 64; k = k + 1) begin : bank
                if (k < NB) begin : used
                    fn_fb_bank u_bank (
                        .clk   (clk),
                        .we    (we_q && (wbuf_q == b) && (wbank_q == k)),
                        .waddr (waddr_q),
                        .wdata (wdata_q),
                        .raddr (raddr),
                        .rdata (q_flat[(b * 64 + k) * 8 +: 8])
                    );
                end else begin : unused
                    assign q_flat[(b * 64 + k) * 8 +: 8] = 8'd0;
                end
            end
        end
    endgenerate

    always @(posedge clk) rdata <= q_flat[rsel_q * 8 +: 8];
endmodule

// rtl/video/fn_memories.v
`timescale 1ns / 1ps
// Palette RAM and the two asset ROMs of the display engine.
// INIT parameters are absolute paths of the generated .hex files
// (see build/fn_paths.vh, produced by the build script).

// 256 x 24-bit palette, one write port (command processor) and one
// registered read port (scan-out), both in the pixel clock domain.
module fn_palette #(
    parameter INIT = "palette.hex"
) (
    input  wire        clk,
    input  wire        we,
    input  wire [7:0]  waddr,
    input  wire [23:0] wdata,
    input  wire [7:0]  raddr,
    output reg  [23:0] rdata
);
    reg [23:0] mem [0:255];
    initial $readmemh(INIT, mem);
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule

// The sprite ROM (fn_sprite_rom) is generated into fn_sprite_rom.v by
// assets/gen_assets.py: one DRM bank per image.

// 128 glyphs x 16 rows x 16 bit (MSB = leftmost pixel), address {ch, row}.
module fn_font_rom #(
    parameter INIT = "font.hex"
) (
    input  wire        clk,
    input  wire [10:0] addr,
    output reg  [15:0] q
);
    reg [15:0] rom [0:2047];
    reg [15:0] q0;
    initial $readmemh(INIT, rom);
    always @(posedge clk) begin
        q0 <= rom[addr];
        q  <= q0;
    end
endmodule

// rtl/storage/fn_sprite_cache.v
`timescale 1ns / 1ps
// GPU v2 sprite cache: 64 writable 4KiB banks, address {slot[5:0],v,u}.
// Upload commands run only after earlier raster operations have drained.
// Reset invalidates slots without resetting the RAM, preserving block-RAM
// inference. A slot remains transparent until its first upload write.
module fn_sprite_bank (
    input  wire        clk,
    input  wire        we,
    input  wire [11:0] addr,
    input  wire [11:0] waddr,
    input  wire [7:0]  wdata,
    output reg  [7:0]  q
);
    reg [7:0] mem [0:4095];
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        q <= mem[addr];
    end
endmodule

module fn_sprite_rom (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire [17:0] addr,
    input  wire [17:0] waddr,
    input  wire [7:0]  wdata,
    output reg  [7:0]  q
);
    wire [511:0] values;
    reg [63:0] valid;
    reg [5:0] selected;
    genvar i;
    generate for (i = 0; i < 64; i = i + 1) begin : banks
        fn_sprite_bank bank (
            .clk(clk), .we(we && !rst && waddr[17:12] == i),
            .addr(addr[11:0]), .waddr(waddr[11:0]), .wdata(wdata),
            .q(values[i*8+:8])
        );
    end endgenerate

    always @(posedge clk) begin
        if (rst) begin
            valid <= 64'd0;
            selected <= 6'd0;
            q <= 8'd0;
        end else begin
            if (we) valid[waddr[17:12]] <= 1'b1;
            // Bank read followed by registered mux: the original two cycles.
            selected <= addr[17:12];
            q <= valid[selected] ? values[selected*8+:8] : 8'd0;
        end
    end
endmodule

// rtl/video/fn_bg_gen.v
`timescale 1ns / 1ps
// Procedural wood-plank background, 3-cycle pipeline.
// Bit-exact with tools/fnlib.py bg_index(); LUTs come from fn_bg_lut.vh.
module fn_bg_gen (
    input  wire       clk,
    input  wire [8:0] x,
    input  wire [8:0] y,
    input  wire [3:0] variant,
    output reg  [7:0] color
);
// include fn_bg_lut.vh
// Generated by tools/fnlib.py -- do not edit.
function [7:0] bg_seed; input [2:0] i;
  case (i)
    3'd0: bg_seed = 8'd195;
    3'd1: bg_seed = 8'd148;
    3'd2: bg_seed = 8'd237;
    3'd3: bg_seed = 8'd75;
    3'd4: bg_seed = 8'd223;
    3'd5: bg_seed = 8'd121;
    3'd6: bg_seed = 8'd187;
    3'd7: bg_seed = 8'd246;
    default: bg_seed = 8'd0;
  endcase
endfunction
function [2:0] bg_wave; input [5:0] i;
  case (i)
    6'd0: bg_wave = 3'd3;
    6'd1: bg_wave = 3'd3;
    6'd2: bg_wave = 3'd4;
    6'd3: bg_wave = 3'd4;
    6'd4: bg_wave = 3'd4;
    6'd5: bg_wave = 3'd4;
    6'd6: bg_wave = 3'd5;
    6'd7: bg_wave = 3'd5;
    6'd8: bg_wave = 3'd5;
    6'd9: bg_wave = 3'd5;
    6'd10: bg_wave = 3'd5;
    6'd11: bg_wave = 3'd6;
    6'd12: bg_wave = 3'd6;
    6'd13: bg_wave = 3'd6;
    6'd14: bg_wave = 3'd6;
    6'd15: bg_wave = 3'd6;
    6'd16: bg_wave = 3'd6;
    6'd17: bg_wave = 3'd6;
    6'd18: bg_wave = 3'd6;
    6'd19: bg_wave = 3'd6;
    6'd20: bg_wave = 3'd6;
    6'd21: bg_wave = 3'd6;
    6'd22: bg_wave = 3'd5;
    6'd23: bg_wave = 3'd5;
    6'd24: bg_wave = 3'd5;
    6'd25: bg_wave = 3'd5;
    6'd26: bg_wave = 3'd5;
    6'd27: bg_wave = 3'd4;
    6'd28: bg_wave = 3'd4;
    6'd29: bg_wave = 3'd4;
    6'd30: bg_wave = 3'd4;
    6'd31: bg_wave = 3'd3;
    6'd32: bg_wave = 3'd3;
    6'd33: bg_wave = 3'd3;
    6'd34: bg_wave = 3'd2;
    6'd35: bg_wave = 3'd2;
    6'd36: bg_wave = 3'd2;
    6'd37: bg_wave = 3'd2;
    6'd38: bg_wave = 3'd1;
    6'd39: bg_wave = 3'd1;
    6'd40: bg_wave = 3'd1;
    6'd41: bg_wave = 3'd1;
    6'd42: bg_wave = 3'd1;
    6'd43: bg_wave = 3'd0;
    6'd44: bg_wave = 3'd0;
    6'd45: bg_wave = 3'd0;
    6'd46: bg_wave = 3'd0;
    6'd47: bg_wave = 3'd0;
    6'd48: bg_wave = 3'd0;
    6'd49: bg_wave = 3'd0;
    6'd50: bg_wave = 3'd0;
    6'd51: bg_wave = 3'd0;
    6'd52: bg_wave = 3'd0;
    6'd53: bg_wave = 3'd0;
    6'd54: bg_wave = 3'd1;
    6'd55: bg_wave = 3'd1;
    6'd56: bg_wave = 3'd1;
    6'd57: bg_wave = 3'd1;
    6'd58: bg_wave = 3'd1;
    6'd59: bg_wave = 3'd2;
    6'd60: bg_wave = 3'd2;
    6'd61: bg_wave = 3'd2;
    6'd62: bg_wave = 3'd2;
    6'd63: bg_wave = 3'd3;
    default: bg_wave = 3'd0;
  endcase
endfunction
function [1:0] bg_grain; input [5:0] i;
  case (i)
    6'd0: bg_grain = 2'd2;
    6'd1: bg_grain = 2'd2;
    6'd2: bg_grain = 2'd2;
    6'd3: bg_grain = 2'd2;
    6'd4: bg_grain = 2'd2;
    6'd5: bg_grain = 2'd2;
    6'd6: bg_grain = 2'd2;
    6'd7: bg_grain = 2'd2;
    6'd8: bg_grain = 2'd1;
    6'd9: bg_grain = 2'd1;
    6'd10: bg_grain = 2'd0;
    6'd11: bg_grain = 2'd0;
    6'd12: bg_grain = 2'd0;
    6'd13: bg_grain = 2'd0;
    6'd14: bg_grain = 2'd0;
    6'd15: bg_grain = 2'd2;
    6'd16: bg_grain = 2'd2;
    6'd17: bg_grain = 2'd2;
    6'd18: bg_grain = 2'd2;
    6'd19: bg_grain = 2'd2;
    6'd20: bg_grain = 2'd2;
    6'd21: bg_grain = 2'd2;
    6'd22: bg_grain = 2'd2;
    6'd23: bg_grain = 2'd2;
    6'd24: bg_grain = 2'd0;
    6'd25: bg_grain = 2'd2;
    6'd26: bg_grain = 2'd2;
    6'd27: bg_grain = 2'd3;
    6'd28: bg_grain = 2'd1;
    6'd29: bg_grain = 2'd1;
    6'd30: bg_grain = 2'd1;
    6'd31: bg_grain = 2'd1;
    6'd32: bg_grain = 2'd2;
    6'd33: bg_grain = 2'd2;
    6'd34: bg_grain = 2'd2;
    6'd35: bg_grain = 2'd2;
    6'd36: bg_grain = 2'd2;
    6'd37: bg_grain = 2'd2;
    6'd38: bg_grain = 2'd2;
    6'd39: bg_grain = 2'd0;
    6'd40: bg_grain = 2'd0;
    6'd41: bg_grain = 2'd0;
    6'd42: bg_grain = 2'd0;
    6'd43: bg_grain = 2'd0;
    6'd44: bg_grain = 2'd0;
    6'd45: bg_grain = 2'd1;
    6'd46: bg_grain = 2'd1;
    6'd47: bg_grain = 2'd1;
    6'd48: bg_grain = 2'd1;
    6'd49: bg_grain = 2'd3;
    6'd50: bg_grain = 2'd3;
    6'd51: bg_grain = 2'd3;
    6'd52: bg_grain = 2'd3;
    6'd53: bg_grain = 2'd1;
    6'd54: bg_grain = 2'd2;
    6'd55: bg_grain = 2'd2;
    6'd56: bg_grain = 2'd2;
    6'd57: bg_grain = 2'd2;
    6'd58: bg_grain = 2'd2;
    6'd59: bg_grain = 2'd2;
    6'd60: bg_grain = 2'd1;
    6'd61: bg_grain = 2'd1;
    6'd62: bg_grain = 2'd1;
    6'd63: bg_grain = 2'd1;
    default: bg_grain = 2'd2;
  endcase
endfunction
function [8:0] bg_joint; input [2:0] i;
  case (i)
    3'd0: bg_joint = 9'd148;
    3'd1: bg_joint = 9'd274;
    3'd2: bg_joint = 9'd272;
    3'd3: bg_joint = 9'd31;
    3'd4: bg_joint = 9'd511;
    3'd5: bg_joint = 9'd116;
    3'd6: bg_joint = 9'd250;
    3'd7: bg_joint = 9'd109;
    default: bg_joint = 9'd511;
  endcase
endfunction
function [3:0] bg_bayer; input [1:0] y; input [1:0] x;
  case ({y, x})
    4'd0: bg_bayer = 4'd0;
    4'd1: bg_bayer = 4'd8;
    4'd2: bg_bayer = 4'd2;
    4'd3: bg_bayer = 4'd10;
    4'd4: bg_bayer = 4'd12;
    4'd5: bg_bayer = 4'd4;
    4'd6: bg_bayer = 4'd14;
    4'd7: bg_bayer = 4'd6;
    4'd8: bg_bayer = 4'd3;
    4'd9: bg_bayer = 4'd11;
    4'd10: bg_bayer = 4'd1;
    4'd11: bg_bayer = 4'd9;
    4'd12: bg_bayer = 4'd15;
    4'd13: bg_bayer = 4'd7;
    4'd14: bg_bayer = 4'd13;
    4'd15: bg_bayer = 4'd5;
    default: bg_bayer = 4'd0;
  endcase
endfunction
localparam integer BG_VIG_DITHER = 320;
localparam integer BG_VIG_T0 = 11000;
localparam integer BG_VIG_T1 = 19000;
localparam integer BG_VIG_T2 = 27500;
localparam integer BG_PAL_BASE = 16;

// end include fn_bg_lut.vh

    // ---------------------------------------------------------- stage 1
    wire [7:0] seed_s = bg_seed(x[8:6]) ^ {variant, variant};
    wire [8:0] jy     = bg_joint(x[8:6]);

    reg  [7:0] s1_s;
    reg  [5:0] s1_lx;
    reg  [5:0] s1_widx;
    reg  [7:0] s1_dxc;
    reg  [7:0] s1_dyc;
    reg  [3:0] s1_bay;
    reg        s1_j0, s1_j1;
    always @(posedge clk) begin
        s1_s    <= seed_s;
        s1_lx   <= x[5:0];
        s1_widx <= y[7:2] + seed_s[5:0];
        s1_dxc  <= x[8] ? x[7:0] : ~x[7:0];
        s1_dyc  <= (y >= 9'd150) ? (y - 9'd150) : (9'd149 - y);
        s1_bay  <= bg_bayer(y[1:0], x[1:0]);
        s1_j0   <= (y == jy);
        s1_j1   <= ({1'b0, y} == ({1'b0, jy} + 10'd1));
    end

    // ---------------------------------------------------------- stage 2
    reg  [7:0]  s2_s;
    reg  [5:0]  s2_lx;
    reg  [2:0]  s2_wv;
    reg  [15:0] s2_dx2, s2_dy2;
    reg  [12:0] s2_bay;
    reg         s2_j0, s2_j1;
    always @(posedge clk) begin
        s2_s   <= s1_s;
        s2_lx  <= s1_lx;
        s2_wv  <= bg_wave(s1_widx);
        s2_dx2 <= s1_dxc * s1_dxc;
        s2_dy2 <= s1_dyc * s1_dyc;
        s2_bay <= s1_bay * BG_VIG_DITHER;
        s2_j0  <= s1_j0;
        s2_j1  <= s1_j1;
    end

    // ---------------------------------------------------------- stage 3
    wire [5:0]  gi    = s2_lx + {3'd0, s2_wv} + s2_s[7:2];
    wire [1:0]  code  = bg_grain(gi);
    wire [2:0]  base  = 3'd3 + {2'd0, s2_s[0]} + {2'd0, s2_s[1]};
    wire [3:0]  graw  = {1'b0, base} + {2'd0, code};          // base + code, offset by +2
    wire [2:0]  grain = (graw < 4'd3) ? 3'd1 : (graw > 4'd9) ? 3'd7 : graw[2:0] - 3'd2;
    wire [2:0]  edge_hi = (base >= 3'd5) ? 3'd7 : base + 3'd2;
    reg  [2:0]  shade;
    always @(*) begin
        if (s2_lx == 6'd0)       shade = 3'd0;
        else if (s2_lx == 6'd1)  shade = 3'd1;
        else if (s2_lx == 6'd63) shade = edge_hi;
        else                     shade = grain;
        if (s2_j0)      shade = 3'd0;
        else if (s2_j1) shade = 3'd2;
    end
    wire [16:0] d = {3'd0, s2_dx2[15:2]} + {1'b0, s2_dy2} + {4'd0, s2_bay};
    wire [1:0]  lvl = (d < BG_VIG_T0) ? 2'd0 : (d < BG_VIG_T1) ? 2'd1 :
                      (d < BG_VIG_T2) ? 2'd2 : 2'd3;
    wire [7:0] pal_base = BG_PAL_BASE;
    always @(posedge clk)
        color <= pal_base + {3'd0, lvl, 3'd0} + {5'd0, shade};
endmodule

// rtl/video/fn_raster.v
`timescale 1ns / 1ps
// Rasterizer: walks a destination rectangle one pixel per clock and writes the
// opaque pixels of the selected source into the draw framebuffer.
//
//   FILL    constant colour
//   BG      procedural wood (fn_bg_gen)
//   SPRITE  64x64 8bpp image (64 slots), affine sampled: u = u0 + i*dudx + j*dudy,
//           v = v0 + i*dvdx + j*dvdy (Q16.16); index 0 is transparent.
//           flags[0] SOLID  opaque texels are drawn in 'color' (silhouette/flash)
//           flags[1] WRAP   u, v wrap modulo 64 instead of clipping (tiling)
//           flags[2] REMAP  opaque texels are drawn as texel + 'color' (mod 256)
//   flags[3] DITHER (SPRITE and FILL) only pixels with even x + y are written
//   GLYPH   16x16 1bpp glyph, same affine sampling, drawn in 'color'
//   CIRCLE  disc of radius r centred in a (2r+1)^2 box: (i-r)^2+(j-r)^2 <= r^2+r
//
// Columns left of the framebuffer are skipped at the start of every row (the
// affine start is advanced by skip*dudx / skip*dvdx once per command), rows
// outside the framebuffer are skipped in one cycle, the rest of a row right of
// the framebuffer is skipped, and the walk stops at the first row below it.
// Semantics match tools/gpu_model.py exactly.
//
// Pipeline: P1/P2 left-clip setup, S0 walk -> S1 source address -> S2 ROM/mult
//           -> S3 ROM out -> S4 write
module fn_raster #(
    parameter FONT_INIT = "font.hex"
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        sprite_we,
    input  wire [17:0] sprite_addr,
    input  wire [7:0]  sprite_data,

    input  wire        start,
    input  wire [2:0]  mode,
    input  wire [15:0] x0,
    input  wire [15:0] y0,
    input  wire [9:0]  w,
    input  wire [9:0]  h,
    input  wire [7:0]  color,
    input  wire [31:0] u0,
    input  wire [31:0] v0,
    input  wire [31:0] dudx,
    input  wire [31:0] dvdx,
    input  wire [31:0] dudy,
    input  wire [31:0] dvdy,
    input  wire [6:0]  src,
    input  wire [3:0]  flags,
    input  wire [5:0]  radius,
    input  wire [3:0]  variant,
    output wire        busy,

    // fb_we is valid, not a one-clock pulse: accept at fb_we && fb_ready.
    // The pixel tuple stays stable until accepted. This is one clock domain.
    input  wire        fb_ready,
    output wire        fb_we,
    output wire [8:0]  fb_x,
    output wire [8:0]  fb_y,
    output wire [7:0]  fb_data
);
    localparam [2:0] M_FILL = 3'd0, M_BG = 3'd1, M_SPRITE = 3'd2, M_GLYPH = 3'd3, M_CIRCLE = 3'd4;
    localparam integer FB_W = 512;
    localparam integer FB_H = 300;

    // ---------------------------------------------------------- latched op
    reg [2:0]  l_mode;
    reg [15:0] l_x0;
    reg [9:0]  l_w, l_h;
    reg [7:0]  l_color;
    reg [31:0] l_dudx, l_dvdx, l_dudy, l_dvdy;
    reg [6:0]  l_src;
    reg [3:0]  l_flags;
    reg [9:0]  l_skip;            // columns left of the framebuffer
    reg [15:0] l_x0c;             // first visible column
    reg [31:0] l_u0, l_v0, l_uskip, l_vskip;
    reg [1:0]  prep;
    reg [5:0]  l_r;
    reg [12:0] l_r2;
    reg [3:0]  l_variant;

    // ---------------------------------------------------------- S0 walk
    reg        running;
    reg [9:0]  i, j;
    reg [16:0] dx, dy;            // signed
    reg [31:0] u, v, urow, vrow;

    wire row_on   = !dy[16] && (dy < FB_H);
    wire below    = !dy[16] && (dy >= FB_H);
    wire right    = !dx[16] && (dx >= FB_W);
    wire last_col = (i == l_w - 10'd1);
    wire last_row = (j == l_h - 10'd1);
    wire walk_pixel = running && row_on && !right;
    wire pixel_credit;
    wire emit     = walk_pixel && pixel_credit;
    wire row_adv  = !row_on || right || last_col;

    // left clip: skip = min(-x0, w) for negative x0
    wire [16:0] neg_x0  = 17'd0 - {x0[15], x0};
    wire [9:0]  skip_in = !x0[15] ? 10'd0 : ((neg_x0 >= {7'd0, w}) ? w : neg_x0[9:0]);

    always @(posedge clk) begin
        if (rst) begin
            running <= 1'b0;
            prep    <= 2'd0;
        end else if (start && !busy) begin
            running   <= 1'b0;
            prep      <= ((w != 10'd0) && (h != 10'd0)) ? 2'd1 : 2'd0;
            l_skip    <= skip_in;
            l_x0c     <= x0 + {6'd0, skip_in};
            l_u0      <= u0;
            l_v0      <= v0;
            j         <= 10'd0;
            dy        <= {y0[15], y0};
            l_mode    <= mode;
            l_x0      <= x0;
            l_w       <= w;
            l_h       <= h;
            l_color   <= color;
            l_dudx    <= dudx;
            l_dvdx    <= dvdx;
            l_dudy    <= dudy;
            l_dvdy    <= dvdy;
            l_src     <= src;
            l_flags   <= flags;
            l_r       <= radius;
            l_r2      <= radius * radius + radius;
            l_variant <= variant;
        end else if (prep == 2'd1) begin
            l_uskip <= l_dudx * {22'd0, l_skip};
            l_vskip <= l_dvdx * {22'd0, l_skip};
            prep    <= 2'd2;
        end else if (prep == 2'd2) begin
            prep    <= 2'd0;
            running <= (l_skip != l_w);      // fully left of the framebuffer: nothing
            i       <= l_skip;
            dx      <= {l_x0c[15], l_x0c};
            u       <= l_u0 + l_uskip;
            v       <= l_v0 + l_vskip;
            urow    <= l_u0 + l_uskip;
            vrow    <= l_v0 + l_vskip;
        end else if (running && (!walk_pixel || pixel_credit)) begin
            if (below) begin
                running <= 1'b0;
            end else if (row_adv) begin
                i    <= l_skip;
                j    <= j + 10'd1;
                dx   <= {l_x0c[15], l_x0c};
                dy   <= dy + 17'd1;
                urow <= urow + l_dudy;
                vrow <= vrow + l_dvdy;
                u    <= urow + l_dudy;
                v    <= vrow + l_dvdy;
                if (last_row) running <= 1'b0;
            end else begin
                i  <= i + 10'd1;
                dx <= dx + 17'd1;
                u  <= u + l_dudx;
                v  <= v + l_dvdx;
            end
        end
    end

    // ---------------------------------------------------------- S1 address
    reg        v1, on1;
    reg [8:0]  x1, y1;
    reg [17:0] spr_addr;
    reg        spr_in1, dith1;
    reg [10:0] font_addr;
    reg [3:0]  bit1;
    reg        gl_in1;
    reg signed [7:0] ci1, cj1;
    always @(posedge clk) begin
        v1        <= emit && !rst;
        on1       <= !dx[16];
        x1        <= dx[8:0];
        y1        <= dy[8:0];
        spr_addr  <= {l_src[5:0], v[21:16], u[21:16]};
        spr_in1   <= l_flags[1] || ((u[31:22] == 10'd0) && (v[31:22] == 10'd0));
        dith1     <= l_flags[3] && (dx[0] ^ dy[0]);
        font_addr <= {l_src, v[19:16]};
        bit1      <= u[19:16];
        gl_in1    <= (u[31:20] == 12'd0) && (v[31:20] == 12'd0);
        ci1       <= $signed({1'b0, i[6:0]}) - $signed({2'b00, l_r});
        cj1       <= $signed({1'b0, j[6:0]}) - $signed({2'b00, l_r});
    end

    // ---------------------------------------------------------- sources
    wire [7:0]  spr_q;
    wire [15:0] font_q;
    wire [7:0]  bg_q;
    fn_sprite_rom u_sprite_rom (
        .clk(clk), .rst(rst), .addr(spr_addr), .q(spr_q),
        .we(sprite_we), .waddr(sprite_addr), .wdata(sprite_data)
    );
    fn_font_rom   #(.INIT(FONT_INIT))   u_font_rom   (.clk(clk), .addr(font_addr), .q(font_q));
    fn_bg_gen u_bg (.clk(clk), .x(dx[8:0]), .y(dy[8:0]), .variant(l_variant), .color(bg_q));

    // ---------------------------------------------------------- S2
    reg        v2, on2, spr_in2, gl_in2, dith2;
    reg [8:0]  x2, y2;
    reg [3:0]  bit2;
    reg [13:0] sq2;
    always @(posedge clk) begin
        v2      <= v1 && !rst;
        on2     <= on1;
        x2      <= x1;
        y2      <= y1;
        spr_in2 <= spr_in1;
        gl_in2  <= gl_in1;
        dith2   <= dith1;
        bit2    <= bit1;
        sq2     <= ci1 * ci1 + cj1 * cj1;
    end

    // ---------------------------------------------------------- S3
    reg        v3, on3, spr_in3, gl_in3, cin3, dith3;
    reg [8:0]  x3, y3;
    reg [3:0]  bit3;
    always @(posedge clk) begin
        v3      <= v2 && !rst;
        on3     <= on2;
        x3      <= x2;
        y3      <= y2;
        spr_in3 <= spr_in2;
        gl_in3  <= gl_in2;
        dith3   <= dith2;
        bit3    <= bit2;
        cin3    <= ({1'b0, sq2} <= {2'b00, l_r2});
    end

    // ---------------------------------------------------------- S4 write
    reg       op;
    reg [7:0] col;
    always @(*) begin
        case (l_mode)
            M_FILL:   begin op = 1'b1;                           col = l_color; end
            M_BG:     begin op = 1'b1;                           col = bg_q; end
            M_SPRITE: begin op = spr_in3 && (spr_q != 8'd0);
                            col = l_flags[0] ? l_color : (l_flags[2] ? spr_q + l_color : spr_q); end
            M_GLYPH:  begin op = gl_in3 && font_q[4'd15 - bit3]; col = l_color; end
            M_CIRCLE: begin op = cin3;                           col = l_color; end
            default:  begin op = 1'b0;                           col = l_color; end
        endcase
    end

    // Eight pixel slots, including the visible output head. Every S1/S2/S3
    // token reserves a slot before the opacity decision/source data exists.
    // Stop only S0, never freeze a synchronous source RAM or its responses.
    // A suppressed transparent/dither/clipped token releases its reservation
    // at S4; an opaque token converts it to an occupied slot atomically.
    localparam [3:0] PIXEL_DEPTH = 4'd8;
    reg [25:0] pixels [0:7];
    reg [2:0] pixel_rd, pixel_wr;
    reg [3:0] pixel_count;
    wire pixel_pop = fb_we && fb_ready;
    wire pixel_push = v3 && on3 && op && !dith3;
    wire [3:0] pixel_reserved = pixel_count + {3'd0, v1}
                                                + {3'd0, v2} + {3'd0, v3};
    assign pixel_credit = (pixel_reserved < PIXEL_DEPTH) || pixel_pop;

    // A pushed S4 pixel is visible after this edge, exactly as the original
    // registered write was with fb_ready=1. Empty output data is unspecified.
    assign fb_we = !rst && (pixel_count != 4'd0);
    assign {fb_x, fb_y, fb_data} = pixels[pixel_rd];

    reg v4;
    always @(posedge clk) begin
        if (rst) begin
            pixel_rd    <= 3'd0;
            pixel_wr    <= 3'd0;
            pixel_count <= 4'd0;
            v4          <= 1'b0;
        end else begin
            v4    <= v3;
            if (pixel_push) begin
                pixels[pixel_wr] <= {x3, y3, col};
                pixel_wr <= pixel_wr + 3'd1;
            end
            if (pixel_pop) pixel_rd <= pixel_rd + 3'd1;
            case ({pixel_push, pixel_pop})
                2'b10: pixel_count <= pixel_count + 4'd1;
                2'b01: pixel_count <= pixel_count - 4'd1;
                default: ;
            endcase
        end
    end

    // Command completion includes the final accepted write. An unchanged
    // fn_gpu_cmd S_WAIT therefore also fences C_SWAP/UPLOAD/next primitives.
    // Reset intentionally aborts all pending tokens/pixels; it is not a drain.
    assign busy = running | (prep != 2'd0) | v1 | v2 | v3 | v4 | fb_we;
endmodule

// rtl/video/fn_gpu_cmd.v
`timescale 1ns / 1ps
// Command processor (pixel clock domain).
//
// Pops {idx[5:0], data[31:0]} entries from the command FIFO and executes them
// strictly in order.  Parameter writes take 2 cycles; drawing commands launch
// the rasterizer and wait for it; SWAP asks scan-out to show the draw buffer
// from the next frame and waits until that has happened before drawing into
// the other buffer, so the displayed buffer is never written.
//
//  idx  1 COLOR   2 DST {y,x} s16   3 SIZE {h,w}   4..9 U0 V0 DUDX DVDX DUDY DVDY
//      10 FLAGS (bit0 SOLID, bit1 WRAP, bit2 REMAP: sprites; bit3 DITHER: sprites, RECT)
//      16 CLEAR c  17 BG variant  18 RECT  19 SPRITE img[5:0]  20 GLYPH ch
//      21 TEXT {scale-1[26:25], ch[24:18], y[17:9], x[8:0]}
//      22 CIRCLE {color[31:24], r[23:18], cy[17:9], cx[8:0]}
//      23 PSET {color[31:24], y[17:9], x[8:0]}
//      24 PALETTE {index[31:24], rgb[23:0]}   25 SWAP
//      26 SPRITE_UPLOAD {reserved[31:26], byte_addr[25:8], pixel[7:0]}
module fn_gpu_cmd (
    input  wire        clk,
    input  wire        rst,

    input  wire        fifo_empty,
    output wire        fifo_ren,
    input  wire [37:0] fifo_rdata,

    input  wire        frame_latch,

    output reg         r_start,
    output reg  [2:0]  r_mode,
    output reg  [15:0] r_x0,
    output reg  [15:0] r_y0,
    output reg  [9:0]  r_w,
    output reg  [9:0]  r_h,
    output reg  [7:0]  r_color,
    output reg  [31:0] r_u0,
    output reg  [31:0] r_v0,
    output reg  [31:0] r_dudx,
    output reg  [31:0] r_dvdx,
    output reg  [31:0] r_dudy,
    output reg  [31:0] r_dvdy,
    output reg  [6:0]  r_src,
    output reg  [3:0]  r_flags,
    output reg  [5:0]  r_radius,
    output reg  [3:0]  r_variant,
    input  wire        r_busy,

    output reg         pal_we,
    output reg         sprite_we,
    output reg  [17:0]  sprite_addr,
    output reg  [7:0]   sprite_data,
    output reg  [7:0]  pal_addr,
    output reg  [23:0] pal_data,

    output reg         draw_buf,
    output reg         disp_buf,

    output reg  [15:0] frame_gray,
    output reg  [15:0] swap_gray,
    output reg  [15:0] frame_count,
    output reg         idle
);
    localparam [2:0] M_FILL = 3'd0, M_BG = 3'd1, M_SPRITE = 3'd2, M_GLYPH = 3'd3, M_CIRCLE = 3'd4;

    localparam [5:0] R_COLOR = 6'd1, R_DST = 6'd2, R_SIZE = 6'd3, R_U0 = 6'd4, R_V0 = 6'd5,
                     R_DUDX = 6'd6, R_DVDX = 6'd7, R_DUDY = 6'd8, R_DVDY = 6'd9, R_FLAGS = 6'd10,
                     C_CLEAR = 6'd16, C_BG = 6'd17, C_RECT = 6'd18, C_SPRITE = 6'd19,
                     C_GLYPH = 6'd20, C_TEXT = 6'd21, C_CIRCLE = 6'd22, C_PSET = 6'd23,
                     C_PALETTE = 6'd24, C_SWAP = 6'd25, C_UPLOAD = 6'd26;

    localparam [1:0] S_IDLE = 2'd0, S_EXEC = 2'd1, S_WAIT = 2'd2, S_SWAP = 2'd3;

    reg [1:0] state;
    reg       disp_req;
    reg [15:0] swap_count;

    // user-visible parameter registers
    reg [7:0]  p_color;
    reg [15:0] p_x0, p_y0;
    reg [9:0]  p_w, p_h;
    reg [31:0] p_u0, p_v0, p_dudx, p_dvdx, p_dudy, p_dvdy;
    reg [3:0]  p_flags;

    wire [5:0]  idx = fifo_rdata[37:32];
    wire [31:0] d   = fifo_rdata[31:0];

    assign fifo_ren = (state == S_IDLE) && !fifo_empty;

    // TEXT helpers
    wire [1:0]  t_sc   = d[26:25];
    wire [2:0]  t_sc1  = {1'b0, t_sc} + 3'd1;
    reg  [31:0] t_inv;
    always @(*) begin
        case (t_sc)
            2'd0: t_inv = 32'h0001_0000;
            2'd1: t_inv = 32'h0000_8000;
            2'd2: t_inv = 32'h0000_5556;
            default: t_inv = 32'h0000_4000;
        endcase
    end
    // CIRCLE helpers
    wire [5:0]  c_r  = d[23:18];
    wire [15:0] c_x0 = {7'd0, d[8:0]} - {10'd0, c_r};
    wire [15:0] c_y0 = {7'd0, d[17:9]} - {10'd0, c_r};
    wire [9:0]  c_w  = {3'd0, c_r, 1'b1};

    always @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            r_start     <= 1'b0;
            pal_we      <= 1'b0;
            sprite_we   <= 1'b0;
            sprite_addr <= 18'd0;
            sprite_data <= 8'd0;
            draw_buf    <= 1'b1;
            disp_buf    <= 1'b0;
            disp_req    <= 1'b0;
            frame_count <= 16'd0;
            swap_count  <= 16'd0;
            frame_gray  <= 16'd0;
            swap_gray   <= 16'd0;
            idle        <= 1'b0;
            p_color     <= 8'd0;
            p_x0        <= 16'd0;
            p_y0        <= 16'd0;
            p_w         <= 10'd0;
            p_h         <= 10'd0;
            p_u0        <= 32'd0;
            p_v0        <= 32'd0;
            p_dudx      <= 32'h0001_0000;
            p_dvdx      <= 32'd0;
            p_dudy      <= 32'd0;
            p_dvdy      <= 32'h0001_0000;
            p_flags     <= 4'd0;
            r_mode      <= M_FILL;
            r_x0        <= 16'd0;
            r_y0        <= 16'd0;
            r_w         <= 10'd0;
            r_h         <= 10'd0;
            r_color     <= 8'd0;
            r_u0        <= 32'd0;
            r_v0        <= 32'd0;
            r_dudx      <= 32'd0;
            r_dvdx      <= 32'd0;
            r_dudy      <= 32'd0;
            r_dvdy      <= 32'd0;
            r_src       <= 7'd0;
            r_flags     <= 4'd0;
            r_radius    <= 6'd0;
            r_variant   <= 4'd0;
        end else begin
            r_start    <= 1'b0;
            pal_we     <= 1'b0;
            sprite_we  <= 1'b0;
            frame_gray <= frame_count ^ (frame_count >> 1);
            swap_gray  <= swap_count ^ (swap_count >> 1);
            idle       <= (state == S_IDLE) && fifo_empty && !r_busy && !r_start;

            if (frame_latch) begin
                disp_buf    <= disp_req;
                frame_count <= frame_count + 16'd1;
            end

            case (state)
                S_IDLE: if (!fifo_empty) state <= S_EXEC;

                S_EXEC: begin
                    state <= S_IDLE;
                    case (idx)
                        R_COLOR: p_color <= d[7:0];
                        R_DST:   begin p_x0 <= d[15:0]; p_y0 <= d[31:16]; end
                        R_SIZE:  begin p_w <= d[9:0]; p_h <= d[25:16]; end
                        R_U0:    p_u0 <= d;
                        R_V0:    p_v0 <= d;
                        R_DUDX:  p_dudx <= d;
                        R_DVDX:  p_dvdx <= d;
                        R_DUDY:  p_dudy <= d;
                        R_DVDY:  p_dvdy <= d;
                        R_FLAGS: p_flags <= d[3:0];

                        C_CLEAR, C_BG: begin
                            r_mode    <= (idx == C_BG) ? M_BG : M_FILL;
                            r_x0      <= 16'd0;
                            r_y0      <= 16'd0;
                            r_w       <= 10'd512;
                            r_h       <= 10'd300;
                            r_color   <= d[7:0];
                            r_variant <= d[3:0];
                            r_flags   <= 4'd0;
                            r_start   <= 1'b1;
                            state     <= S_WAIT;
                        end
                        C_RECT: begin
                            r_mode  <= M_FILL;
                            r_x0    <= p_x0;
                            r_y0    <= p_y0;
                            r_w     <= p_w;
                            r_h     <= p_h;
                            r_color <= p_color;
                            r_flags <= {p_flags[3], 3'b000};
                            r_start <= 1'b1;
                            state   <= S_WAIT;
                        end
                        C_SPRITE, C_GLYPH: begin
                            r_mode  <= (idx == C_SPRITE) ? M_SPRITE : M_GLYPH;
                            r_x0    <= p_x0;
                            r_y0    <= p_y0;
                            r_w     <= p_w;
                            r_h     <= p_h;
                            r_color <= p_color;
                            r_u0    <= p_u0;
                            r_v0    <= p_v0;
                            r_dudx  <= p_dudx;
                            r_dvdx  <= p_dvdx;
                            r_dudy  <= p_dudy;
                            r_dvdy  <= p_dvdy;
                            r_src   <= (idx == C_SPRITE) ? {1'b0, d[5:0]} : d[6:0];
                            r_flags <= (idx == C_SPRITE) ? p_flags : 4'd0;
                            r_start <= 1'b1;
                            state   <= S_WAIT;
                        end
                        C_TEXT: begin
                            r_mode  <= M_GLYPH;
                            r_x0    <= {7'd0, d[8:0]};
                            r_y0    <= {7'd0, d[17:9]};
                            r_w     <= {3'd0, t_sc1, 4'd0};
                            r_h     <= {3'd0, t_sc1, 4'd0};
                            r_color <= p_color;
                            r_u0    <= 32'd0;
                            r_v0    <= 32'd0;
                            r_dudx  <= t_inv;
                            r_dvdx  <= 32'd0;
                            r_dudy  <= 32'd0;
                            r_dvdy  <= t_inv;
                            r_src   <= d[24:18];
                            r_flags <= 4'd0;
                            r_start <= 1'b1;
                            state   <= S_WAIT;
                        end
                        C_CIRCLE: begin
                            r_mode   <= M_CIRCLE;
                            r_x0     <= c_x0;
                            r_y0     <= c_y0;
                            r_w      <= c_w;
                            r_h      <= c_w;
                            r_radius <= c_r;
                            r_color  <= d[31:24];
                            r_flags  <= 4'd0;
                            r_start  <= 1'b1;
                            state    <= S_WAIT;
                        end
                        C_PSET: begin
                            r_mode  <= M_FILL;
                            r_x0    <= {7'd0, d[8:0]};
                            r_y0    <= {7'd0, d[17:9]};
                            r_w     <= 10'd1;
                            r_h     <= 10'd1;
                            r_color <= d[31:24];
                            r_flags <= 4'd0;
                            r_start <= 1'b1;
                            state   <= S_WAIT;
                        end
                        C_PALETTE: begin
                            pal_we   <= 1'b1;
                            pal_addr <= d[31:24];
                            pal_data <= d[23:0];
                        end
                        C_UPLOAD: begin
                            // FIFO ordering guarantees the prior draw has drained.
                            sprite_we   <= 1'b1;
                            sprite_addr <= d[25:8];
                            sprite_data <= d[7:0];
                        end
                        C_SWAP: begin
                            disp_req <= draw_buf;
                            state    <= S_SWAP;
                        end
                        default: ;
                    endcase
                end

                S_WAIT: if (!r_start && !r_busy) state <= S_IDLE;

                S_SWAP: if (disp_buf == disp_req) begin
                    draw_buf   <= ~draw_buf;
                    swap_count <= swap_count + 16'd1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

// rtl/video/fn_gpu_top.v
`timescale 1ns / 1ps
// Fruit Ninja display engine top.
//
//  CPU clock domain : fn_mmio_hub + FIFO write side (only a few registers)
//  pixel domain     : command processor, rasterizer, framebuffer, palette,
//                     LCD timing and scan-out (512x300 -> 1024x600, 2x2 pixels)
module fn_gpu_top #(
    parameter        FONT_INIT   = "font.hex",
    parameter        PAL_INIT    = "palette.hex",
    parameter [31:0] CLOCK_HZ    = 32'd138857143
) (
    input  wire        cpu_clk,
    input  wire        cpu_rst,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    input  wire        req_write,
    input  wire [3:0]  req_be,
    input  wire [31:0] req_wdata,
    output wire        rsp_valid,
    input  wire        rsp_ready,
    output wire [31:0] rsp_rdata,
    output wire        rsp_error,

    input  wire [31:0] touch_state,
    input  wire [31:0] touch_xy,
    input  wire [31:0] touch_seq,
    input  wire [31:0] touch_errors,
    input  wire [127:0] touch_xy_extra,
    input  wire [39:0] touch_ids,

    input  wire        pix_clk,
    input  wire        pix_rst,
    output reg         lcd_hs,
    output reg         lcd_vs,
    output reg         lcd_de,
    output reg  [7:0]  lcd_r,
    output reg  [7:0]  lcd_g,
    output reg  [7:0]  lcd_b,
    output wire        frame_toggle
);
    localparam FIFO_AW = 10;

    // ------------------------------------------------ CPU side
    wire               cmd_wen;
    wire [37:0]        cmd_wdata;
    wire               cmd_full;
    wire [FIFO_AW:0]   cmd_level;
    wire [15:0]        frame_gray, swap_gray;
    wire               gpu_idle, vblank;

    fn_mmio_hub #(.CLOCK_HZ(CLOCK_HZ), .FIFO_AW(FIFO_AW)) u_hub (
        .clk(cpu_clk), .rst(cpu_rst),
        .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
        .req_write(req_write), .req_be(req_be), .req_wdata(req_wdata),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_rdata(rsp_rdata), .rsp_error(rsp_error),
        .cmd_wen(cmd_wen), .cmd_wdata(cmd_wdata), .cmd_full(cmd_full), .cmd_level(cmd_level),
        .pix_frame_gray(frame_gray), .pix_swap_gray(swap_gray),
        .pix_idle(gpu_idle), .pix_vblank(vblank),
        .touch_state(touch_state), .touch_xy(touch_xy),
        .touch_seq(touch_seq), .touch_errors(touch_errors), .touch_xy_extra(touch_xy_extra), .touch_ids(touch_ids)
    );

    wire        fifo_empty, fifo_ren;
    wire [37:0] fifo_rdata;
    fn_async_fifo #(.DW(38), .AW(FIFO_AW)) u_fifo (
        .wclk(cpu_clk), .wrst(cpu_rst), .wen(cmd_wen), .wdata(cmd_wdata),
        .wfull(cmd_full), .wlevel(cmd_level),
        .rclk(pix_clk), .rrst(pix_rst), .ren(fifo_ren), .rdata(fifo_rdata), .rempty(fifo_empty)
    );

    // ------------------------------------------------ pixel side
    wire        hs0, vs0, de0, frame_latch;
    wire [10:0] tx;
    wire [9:0]  ty;
    fn_video_timing u_timing (
        .clk(pix_clk), .rst(pix_rst), .hs(hs0), .vs(vs0), .de(de0),
        .x(tx), .y(ty), .frame_latch(frame_latch), .vblank(vblank)
    );

    wire        r_start, r_busy;
    wire [3:0]  r_flags;
    wire [2:0]  r_mode;
    wire [15:0] r_x0, r_y0;
    wire [9:0]  r_w, r_h;
    wire [7:0]  r_color;
    wire [31:0] r_u0, r_v0, r_dudx, r_dvdx, r_dudy, r_dvdy;
    wire [6:0]  r_src;
    wire [5:0]  r_radius;
    wire [3:0]  r_variant;
    wire        pal_we;
    wire        sprite_we;
    wire [17:0] sprite_addr;
    wire [7:0]  sprite_data;
    wire [7:0]  pal_waddr;
    wire [23:0] pal_wdata;
    wire        draw_buf, disp_buf;
    wire [15:0] frame_count;

    fn_gpu_cmd u_cmd (
        .clk(pix_clk), .rst(pix_rst),
        .fifo_empty(fifo_empty), .fifo_ren(fifo_ren), .fifo_rdata(fifo_rdata),
        .frame_latch(frame_latch),
        .r_start(r_start), .r_mode(r_mode), .r_x0(r_x0), .r_y0(r_y0), .r_w(r_w), .r_h(r_h),
        .r_color(r_color), .r_u0(r_u0), .r_v0(r_v0), .r_dudx(r_dudx), .r_dvdx(r_dvdx),
        .r_dudy(r_dudy), .r_dvdy(r_dvdy), .r_src(r_src), .r_flags(r_flags),
        .r_radius(r_radius), .r_variant(r_variant), .r_busy(r_busy),
        .pal_we(pal_we), .pal_addr(pal_waddr), .pal_data(pal_wdata),
        .sprite_we(sprite_we), .sprite_addr(sprite_addr), .sprite_data(sprite_data),
        .draw_buf(draw_buf), .disp_buf(disp_buf),
        .frame_gray(frame_gray), .swap_gray(swap_gray), .frame_count(frame_count),
        .idle(gpu_idle)
    );

    wire       fb_we;
    wire [8:0] fb_wx, fb_wy;
    wire [7:0] fb_wdata;
    fn_raster #(.FONT_INIT(FONT_INIT)) u_raster (
        .sprite_we(sprite_we), .sprite_addr(sprite_addr), .sprite_data(sprite_data),
        .clk(pix_clk), .rst(pix_rst),
        .start(r_start), .mode(r_mode), .x0(r_x0), .y0(r_y0), .w(r_w), .h(r_h),
        .color(r_color), .u0(r_u0), .v0(r_v0), .dudx(r_dudx), .dvdx(r_dvdx),
        .dudy(r_dudy), .dvdy(r_dvdy), .src(r_src), .flags(r_flags),
        .radius(r_radius), .variant(r_variant), .busy(r_busy),
        .fb_we(fb_we), .fb_x(fb_wx), .fb_y(fb_wy), .fb_data(fb_wdata)
    );

    // ------------------------------------------------ scan-out
    // c0 timing -> c1 bank read -> c2 bank mux -> c3 palette -> c4 LCD pins
    wire [7:0] fb_index;
    fn_framebuffer u_fb (
        .clk(pix_clk),
        .we(fb_we), .wbuf(draw_buf), .wx(fb_wx), .wy(fb_wy), .wdata(fb_wdata),
        .rbuf(disp_buf), .rx(tx[9:1]), .ry(ty[9:1]), .rdata(fb_index)
    );

    wire [23:0] rgb;
    fn_palette #(.INIT(PAL_INIT)) u_pal (
        .clk(pix_clk), .we(pal_we), .waddr(pal_waddr), .wdata(pal_wdata),
        .raddr(fb_index), .rdata(rgb)
    );

    reg [2:0] hs_d, vs_d, de_d;
    always @(posedge pix_clk) begin
        hs_d <= {hs_d[1:0], hs0};
        vs_d <= {vs_d[1:0], vs0};
        de_d <= {de_d[1:0], de0};
        if (pix_rst) begin
            lcd_hs <= 1'b1;
            lcd_vs <= 1'b1;
            lcd_de <= 1'b0;
            lcd_r  <= 8'd0;
            lcd_g  <= 8'd0;
            lcd_b  <= 8'd0;
        end else begin
            lcd_hs <= hs_d[2];
            lcd_vs <= vs_d[2];
            lcd_de <= de_d[2];
            lcd_r  <= de_d[2] ? rgb[23:16] : 8'd0;
            lcd_g  <= de_d[2] ? rgb[15:8]  : 8'd0;
            lcd_b  <= de_d[2] ? rgb[7:0]   : 8'd0;
        end
    end

    assign frame_toggle = frame_count[5];
endmodule

// VENDOR_VIDEO_PLL_INSERTION_POINT

// rtl/board/cpu_pll162.v
// Exact frozen CPU PLL extraction; no physical signoff implied.
module p7_board_pll162 (
    
    output wire clkout0,
    
    input wire clkin1,
    
    output wire lock           
    );

    // Parameter
    
    localparam real    CLKIN_FREQ       = 27.0; //@IPC float 10.0,500.0 
    
    localparam         LOCK_MODE        = 0; //@IPC enum 0,1
    
    localparam integer STATIC_RATIOI    = 1; //@IPC int 1,80
    
    localparam integer STATIC_RATIOM    = 1; //@IPC int 1,128 
    
    localparam real    STATIC_RATIO0    = 6.0; //@IPC int 1.0000,128.0000 
        
    localparam integer STATIC_RATIO1    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO2    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO3    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO4    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO5    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO6    = 17; //@IPC int 1,128 
    
    localparam real    STATIC_RATIOF    = 35.0; //@IPC int 1.0000,128.0000 
        
    localparam integer STATIC_RATIOPHY  = 1; //@IPC int 1,128 
    
    localparam integer STATIC_DUTY0     = 6; //@IPC int 2,255
    
    localparam integer STATIC_DUTY1     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY2     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY3     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY4     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY5     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY6     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTYF     = 36; //@IPC int 2,255
    
    localparam integer STATIC_DUTYPHY   = 2; //@IPC int 2,255
    
    localparam integer STATIC_PHASE     = 0; //@IPC int 0,63 
    
    localparam integer STATIC_PHASE0    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE1    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE2    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE3    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE4    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE5    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE6    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASEF    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASEPHY  = 0; //@IPC int 0,7 
    
    localparam integer STATIC_CPHASE0   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE1   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE2   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE3   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE4   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE5   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE6   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASEF   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASEPHY = 0; //@IPC int 0,127 
    
    localparam         CLK_DPS0_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS1_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS2_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS3_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS4_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS5_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS6_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPSF_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_CAS5_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT0_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT1_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT2_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT3_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT4_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT5_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT6_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUTF_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUTPHY_SYN_EN = "FALSE"; //@IPC bool 
    
    localparam         SSC_MODE         = "DISABLE"; //@IPC enum DISABLE, DOWN_LOW, DOWN_HIGH, CENTER_LOW, CENTER_HIGH
    
    localparam real    SSC_FREQ         = 25; //@IPC int 25,250
    
    localparam         INTERNAL_FB      = "CLKOUTF"; //@IPC enum CLKOUT0,CLKOUT1,CLKOUT2,CLKOUT3,CLKOUT4,CLKOUT5,CLKOUT6,DISABLE 
    
    localparam         EXTERNAL_FB      = "DISABLE"; //@IPC enum CLKOUT0,CLKOUT1,CLKOUT2,CLKOUT3,CLKOUT4,CLKOUT5,CLKOUT6,DISABLE 
    
    localparam         BANDWIDTH        = "OPTIMIZED"; //@IPC enum OPTIMIZED,LOW,HIGH 
    
    wire clkin2;
    assign clkin2 = 1'b0;
    
    wire clkfb;
    assign clkfb = 1'b0;
    
    wire clkin_sel;
    assign clkin_sel = 1'b0;
    
    wire dps_clk;
    wire dps_en;
    wire dps_dir;
    assign dps_clk = 1'b0;
    assign dps_en = 1'b0;
    assign dps_dir = 1'b0;
        
    wire clkout0_syn;
    assign clkout0_syn = 1'b0;
    
    wire clkout1_syn;
    assign clkout1_syn = 1'b0;
    
    wire clkout2_syn;
    assign clkout2_syn = 1'b0;
    
    wire clkout3_syn;
    assign clkout3_syn = 1'b0;
    
    wire clkout4_syn;
    assign clkout4_syn = 1'b0;
    
    wire clkout5_syn;
    assign clkout5_syn = 1'b0;
        
    wire clkout6_syn;
    assign clkout6_syn = 1'b0;
        
    wire clkoutf_syn;
    assign clkoutf_syn = 1'b0;
    
    wire pll_pwd;
    assign pll_pwd = 1'b0;
    
    wire rst;
    assign rst = 1'b0;
    
    wire apb_clk;
    wire apb_rst_n;
    wire [4:0] apb_addr;
    wire apb_sel;
    wire apb_en;
    wire apb_write;
    wire [15:0] apb_wdata;

    assign apb_clk = 1'd0;
    assign apb_rst_n = 1'd0;
    assign apb_addr [4:0] = 5'd0;
    assign apb_sel = 1'd0;
    assign apb_en = 1'd0;
    assign apb_write = 1'd0;
    assign apb_wdata [15:0] = 16'd0;
    
    GTP_GPLL #(

    .CLKIN_FREQ      (CLKIN_FREQ    ),   
    .LOCK_MODE       (LOCK_MODE     ),   
    .STATIC_RATIOI   (STATIC_RATIOI ),   
    .STATIC_RATIOM   (STATIC_RATIOM ),   
    
    .STATIC_RATIO0   (STATIC_RATIO0 ),   
    .STATIC_RATIO1   (STATIC_RATIO1 ),   
    .STATIC_RATIO2   (STATIC_RATIO2 ),   
    .STATIC_RATIO3   (STATIC_RATIO3 ),   
    .STATIC_RATIO4   (STATIC_RATIO4 ),   
    
    .STATIC_RATIO5   (STATIC_RATIO5 ),   
    .STATIC_RATIO6   (STATIC_RATIO6 ),   
    
    .STATIC_RATIOF   (STATIC_RATIOF ),   
    
    .STATIC_DUTY0    (STATIC_DUTY0  ),  
    .STATIC_DUTY1    (STATIC_DUTY1  ),  
    .STATIC_DUTY2    (STATIC_DUTY2  ),  
    .STATIC_DUTY3    (STATIC_DUTY3  ),  
    .STATIC_DUTY4    (STATIC_DUTY4  ),  
    
    .STATIC_DUTY5    (STATIC_DUTY5  ),  
    .STATIC_DUTY6    (STATIC_DUTY6  ),  
    
    .STATIC_DUTYF    (STATIC_DUTYF  ),  
    
    .STATIC_PHASE    (STATIC_PHASE  ),
    
    .STATIC_PHASE0   (STATIC_PHASE0 ),
    .STATIC_PHASE1   (STATIC_PHASE1 ),
    .STATIC_PHASE2   (STATIC_PHASE2 ),
    .STATIC_PHASE3   (STATIC_PHASE3 ),
    .STATIC_PHASE4   (STATIC_PHASE4 ),
    
    .STATIC_PHASE5   (STATIC_PHASE5 ),
    .STATIC_PHASE6   (STATIC_PHASE6 ),
    
    .STATIC_PHASEF   (STATIC_PHASEF ),
    
    .STATIC_CPHASE0  (STATIC_CPHASE0),
    .STATIC_CPHASE1  (STATIC_CPHASE1),
    .STATIC_CPHASE2  (STATIC_CPHASE2),
    .STATIC_CPHASE3  (STATIC_CPHASE3),
    .STATIC_CPHASE4  (STATIC_CPHASE4),
    
    .STATIC_CPHASE5  (STATIC_CPHASE5),
    .STATIC_CPHASE6  (STATIC_CPHASE6),
    
    .STATIC_CPHASEF  (STATIC_CPHASEF),
    
    .CLK_DPS0_EN     (CLK_DPS0_EN   ),  
    .CLK_DPS1_EN     (CLK_DPS1_EN   ),  
    .CLK_DPS2_EN     (CLK_DPS2_EN   ),  
    .CLK_DPS3_EN     (CLK_DPS3_EN   ),  
    .CLK_DPS4_EN     (CLK_DPS4_EN   ),  
    .CLK_DPS5_EN     (CLK_DPS5_EN   ),  
    .CLK_DPS6_EN     (CLK_DPS6_EN   ),  
    .CLK_DPSF_EN     (CLK_DPSF_EN   ),  
    .CLK_CAS5_EN     (CLK_CAS5_EN   ),  
    
    .CLKOUT0_SYN_EN  (CLKOUT0_SYN_EN),
    .CLKOUT1_SYN_EN  (CLKOUT1_SYN_EN),
    .CLKOUT2_SYN_EN  (CLKOUT2_SYN_EN),
    .CLKOUT3_SYN_EN  (CLKOUT3_SYN_EN),
    .CLKOUT4_SYN_EN  (CLKOUT4_SYN_EN),
    
    .CLKOUT5_SYN_EN  (CLKOUT5_SYN_EN),
    .CLKOUT6_SYN_EN  (CLKOUT6_SYN_EN),
    
    .CLKOUTF_SYN_EN  (CLKOUTF_SYN_EN),
    
    .SSC_MODE       (SSC_MODE       ),
    .SSC_FREQ       (SSC_FREQ       ),
    
    .INTERNAL_FB    (INTERNAL_FB    ),
    .EXTERNAL_FB    (EXTERNAL_FB    ),
    .BANDWIDTH      (BANDWIDTH      )
    
    ) u_gpll (
    
    .CLKOUT0        (clkout0        ),
        
    .CLKOUT0N       (               ),
    
    .CLKOUT1        (               ),
    
    .CLKOUT1N       (               ),
    
    .CLKOUT2        (               ),
    
    .CLKOUT2N       (               ),
    
    .CLKOUT3        (               ),
    
    .CLKOUT3N       (               ),
    
    .CLKOUT4        (               ),
    
    .CLKOUT5        (               ),
        
    .CLKOUT6        (               ),
        
    .CLKOUTF        (               ),
    
    .CLKOUTFN       (               ),
    
    .LOCK           (lock           ),
    
    .DPS_DONE       (               ),
        
    .DPS_CLK        (dps_clk        ),
    .DPS_EN         (dps_en         ),
    .DPS_DIR        (dps_dir        ),
    
    .CLKIN1         (clkin1         ),
    
    .CLKIN2         (clkin2         ),
    
    .CLKFB          (clkfb          ),
    .CLKIN_SEL      (clkin_sel      ),
    .CLKOUT0_SYN    (clkout0_syn    ),
    .CLKOUT1_SYN    (clkout1_syn    ),
    .CLKOUT2_SYN    (clkout2_syn    ),
    .CLKOUT3_SYN    (clkout3_syn    ),
    .CLKOUT4_SYN    (clkout4_syn    ),
    
    .CLKOUT5_SYN    (clkout5_syn    ),
    .CLKOUT6_SYN    (clkout6_syn    ),
    
    .CLKOUTF_SYN    (clkoutf_syn    ),
    .PLL_PWD        (pll_pwd        ),
    .RST            (rst            ),
    
    .APB_RDATA      (               ),
    .APB_READY      (               ),
    
    .APB_CLK        (apb_clk        ),
    .APB_RST_N      (apb_rst_n      ),
    .APB_ADDR       (apb_addr[4:0]  ),
    .APB_SEL        (apb_sel        ),
    .APB_EN         (apb_en         ),
    .APB_WRITE      (apb_write      ),
    .APB_WDATA      (apb_wdata[15:0])   
);


endmodule

// rtl/control/fn_control_router.v
`timescale 1ns/1ps
// One outstanding transaction. Endpoints hold responses until handshake and
// share rst; reset cancels the transaction at ALL endpoints. No burst protocol.
module fn_control_router (
    input wire clk, rst,
    input wire req_valid, output wire req_ready,
    input wire [31:0] req_addr, req_wdata,
    input wire req_write, input wire [3:0] req_be,
    output wire rsp_valid, input wire rsp_ready,
    output wire [31:0] rsp_rdata, output wire rsp_error,
    output wire legacy_req_valid, input wire legacy_req_ready,
    output wire [31:0] legacy_req_addr, legacy_req_wdata,
    output wire legacy_req_write, output wire [3:0] legacy_req_be,
    input wire legacy_rsp_valid, output wire legacy_rsp_ready,
    input wire [31:0] legacy_rsp_rdata, input wire legacy_rsp_error,
    output wire pose_req_valid, input wire pose_req_ready,
    output wire [31:0] pose_req_addr, pose_req_wdata,
    output wire pose_req_write, output wire [3:0] pose_req_be,
    input wire pose_rsp_valid, output wire pose_rsp_ready,
    input wire [31:0] pose_rsp_rdata, input wire pose_rsp_error
);
    localparam OWNER_ERROR=2'd0, OWNER_LEGACY=2'd1, OWNER_POSE=2'd2;
    reg busy;
    reg [1:0] owner;
    wire hit_pose = req_addr[31:15] == 17'h02001; // 10008000..1000ffff
    wire hit_legacy = req_addr[31:12] == 20'h10004;
    wire available = !rst && !busy;
    assign req_ready = available && (hit_pose ? pose_req_ready :
                                       hit_legacy ? legacy_req_ready : 1'b1);
    assign pose_req_valid = available && req_valid && hit_pose;
    assign legacy_req_valid = available && req_valid && !hit_pose && hit_legacy;
    assign legacy_req_addr=req_addr;
    assign pose_req_addr=req_addr;
    assign legacy_req_wdata=req_wdata;
    assign pose_req_wdata=req_wdata;
    assign legacy_req_write=req_write;
    assign pose_req_write=req_write;
    assign legacy_req_be=req_be;
    assign pose_req_be=req_be;
    assign rsp_valid = !rst && busy && (owner==OWNER_POSE ? pose_rsp_valid :
                             owner==OWNER_LEGACY ? legacy_rsp_valid : 1'b1);
    assign rsp_rdata = owner==OWNER_POSE ? pose_rsp_rdata :
                      owner==OWNER_LEGACY ? legacy_rsp_rdata : 32'd0;
    assign rsp_error = owner==OWNER_POSE ? pose_rsp_error :
                      owner==OWNER_LEGACY ? legacy_rsp_error : 1'b1;
    assign pose_rsp_ready = !rst && busy && owner==OWNER_POSE && rsp_ready;
    assign legacy_rsp_ready = !rst && busy && owner==OWNER_LEGACY && rsp_ready;
    always @(posedge clk) begin
        if (rst) begin busy<=0; owner<=OWNER_ERROR; end
        else begin
            if (rsp_valid && rsp_ready) busy<=0;
            if (req_valid && req_ready) begin
                busy<=1;
                owner<=hit_pose ? OWNER_POSE : hit_legacy ? OWNER_LEGACY : OWNER_ERROR;
            end
        end
    end
endmodule

// rtl/control/fn_pose_absent.v
`timescale 1ns/1ps
// Production placeholder: no camera/AI connected. One registered access error
// per accepted request; shared reset cancels outstanding work.
module fn_pose_absent (
    input wire clk, rst,
    input wire req_valid, output wire req_ready,
    input wire [31:0] req_addr, req_wdata,
    input wire req_write, input wire [3:0] req_be,
    output reg rsp_valid, input wire rsp_ready,
    output wire [31:0] rsp_rdata, output wire rsp_error
);
    wire unused_request = ^{req_addr,req_wdata,req_write,req_be};
    assign req_ready = !rst && !rsp_valid;
    assign rsp_rdata = 32'd0;
    assign rsp_error = 1'b1;
    always @(posedge clk) begin
        if(rst) rsp_valid <= 1'b0;
        else begin
            if(rsp_valid && rsp_ready) rsp_valid <= 1'b0;
            if(req_valid && req_ready) rsp_valid <= 1'b1;
        end
    end
endmodule

// rtl/board/fn_system.v
`timescale 1ns / 1ps
// CPU + display engine, clocked by already-generated clocks (shared by the
// board top and the full-system simulation).
//
// CPU reset follows the sealed p5_mini_top: asynchronous key assertion,
// 2-FF release, then a 2^17-cycle power-on counter.  The pixel-domain reset is
// a reset bridge of the CPU core reset, so the command FIFO pointers of both
// domains always leave reset in the right order.
// include fn_paths.vh
// Generated by tools/gen_paths.py
`define FN_SPRITE_HEX "E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/sprites.hex"
`define FN_FONT_HEX "E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/font.hex"
`define FN_PAL_HEX "E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/palette.hex"
`define FN_PROGRAM_HEX "E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96/boot_nes_program.hex"
`define FN_PROGRAM_HEX_BITS 1064

// end include fn_paths.vh

module fn_system #(
    parameter [31:0] CPU_BOOT_PC = 32'h80018000,
    parameter [31:0] CLOCK_HZ = 32'd157500000,
    parameter TOUCH_CLOCK_HZ = 27000000,
    parameter TOUCH_I2C_HZ = 100000,
    parameter TOUCH_RESET_LOW_MS = 20,
    parameter TOUCH_INT_HOLD_MS = 55,
    parameter TOUCH_RESET_WAIT_MS = 100,
    parameter TOUCH_POLL_MS = 5,
    parameter TOUCH_STALE_MS = 150
) (
    input wire hdmi_clk,hdmi_lock,
    output wire hdmi_reset,hdmi_hs,hdmi_vs,hdmi_de,output wire [10:0] hdmi_x,output wire [9:0] hdmi_y,output wire [23:0] hdmi_rgb,
    input  wire       cpu_clk,
    input  wire       pix_clk,
    input wire gpu_clk,
    input  wire       touch_clk,
    output wire       ctp_rst_n,
    inout  wire       ctp_int,
    output wire       ctp_scl,
    inout  wire       ctp_sda,
    // Pose endpoint: cpu_clk/cpu_rst domain, single request/response.
    // AI/camera integration and CDC remain a separate integration step.
    output wire pose_mmio_rst,
    output wire pose_req_valid, input wire pose_req_ready,
    output wire [31:0] pose_req_addr, pose_req_wdata,
    output wire pose_req_write, output wire [3:0] pose_req_be,
    input wire pose_rsp_valid, output wire pose_rsp_ready,
    input wire [31:0] pose_rsp_rdata, input wire pose_rsp_error,
    input  wire       key_n,          // active-low reset, already qualified by PLL lock
    output wire       uart_tx,
    output reg  [6:0] backlight_level,   // LCD backlight PWM high time, percent
    input  wire       uart_rx,
    output wire [3:0] led,
    output wire       lcd_hs,
    output wire       lcd_vs,
    output wire       lcd_de,
    output wire [7:0] lcd_r,
    output wire [7:0] lcd_g,
    output wire [7:0] lcd_b,
    output wire sd_cs_n, sd_sck, sd_mosi,
    input wire sd_miso,
    input wire eth_clk, eth_rst, eth_rx_valid, eth_rx_error,
    input wire [7:0] eth_rx_data,
    output wire eth_tx_valid, output wire [7:0] eth_tx_data,
    // DDR3 controller (HMIC_S AXI subset, ddr_core_clk domain)
    input  wire         ddr_core_clk,
    input  wire         ddr_init_done,
    output wire         ddr_controller_resetn,
    output wire [27:0]  ddr_axi_awaddr,
    output wire         ddr_axi_awvalid,
    input  wire         ddr_axi_awready,
    output wire [255:0] ddr_axi_wdata,
    output wire [31:0]  ddr_axi_wstrb,
    input  wire         ddr_axi_wready,
    output wire [27:0]  ddr_axi_araddr,
    output wire         ddr_axi_arvalid,
    input  wire         ddr_axi_arready,
    input  wire [255:0] ddr_axi_rdata,
    input  wire         ddr_axi_rvalid,
    input  wire         ddr_axi_rlast
);
    // ------------------------------------------------ CPU reset (as p5_mini_top)
    reg  [1:0]  key_reset_sync = 2'b11;
    reg  [16:0] por_count = 17'd0;
    wire        key_reset = key_reset_sync[1];
    wire        por_done  = &por_count;
    wire        reset_n   = !key_reset && por_done;

    always @(posedge cpu_clk or negedge key_n)
        if (!key_n) key_reset_sync <= 2'b11;
        else        key_reset_sync <= {key_reset_sync[0], 1'b0};

    always @(posedge cpu_clk)
        if (key_reset)      por_count <= 17'd0;
        else if (!por_done) por_count <= por_count + 17'd1;

    // ------------------------------------------------ CPU
    wire        cpu_rst;
    wire [31:0] gpio_out;
    wire        completed, failed;
    wire        ext_req_valid, ext_req_ready, ext_req_write;
    wire [31:0] ext_req_addr, ext_req_wdata;
    wire [3:0]  ext_req_be;
    wire        ext_rsp_valid, ext_rsp_ready, ext_rsp_error;
    wire [31:0] ext_rsp_rdata;

    wire        ddr_cmd_valid, ddr_cmd_ready, ddr_cmd_write, ddr_w_valid, ddr_w_ready, ddr_w_last;
    wire        ddr_r_valid, ddr_r_ready, ddr_r_error, ddr_r_last, ddr_ready;
    wire [31:0] ddr_cmd_addr, ddr_w_data, ddr_r_data;
    wire [7:0]  ddr_cmd_len;
    wire [3:0]  ddr_w_be;
    wire [15:0] ddr_errors;
    wire        core_uart_tx, link_uart_tx, link_take_tx;
    assign uart_tx = link_take_tx ? link_uart_tx : core_uart_tx;
    fn_cpu_core #(
        .RESET_PC(CPU_BOOT_PC),
        ._sv2v_width_INIT_FILE(`FN_PROGRAM_HEX_BITS),
        .INIT_FILE(`FN_PROGRAM_HEX),
        .DC_LOAD_HIT_TURNOVER(1)
    ) u_cpu (
        .clk(cpu_clk),
        .reset_n(reset_n),
        .rst_out(cpu_rst),
        .ext_req_valid(ext_req_valid),
        .ext_req_ready(ext_req_ready),
        .ext_req_addr(ext_req_addr),
        .ext_req_write(ext_req_write),
        .ext_req_be(ext_req_be),
        .ext_req_wdata(ext_req_wdata),
        .ext_rsp_valid(ext_rsp_valid),
        .ext_rsp_ready(ext_rsp_ready),
        .ext_rsp_rdata(ext_rsp_rdata),
        .ext_rsp_error(ext_rsp_error),
        .external_irq(1'b0),
        .uart_tx(core_uart_tx),
        .gpio_out(gpio_out),
        .completed(completed),
        .failed(failed),
        .ddr_cmd_valid(ddr_cmd_valid), .ddr_cmd_ready(ddr_cmd_ready), .ddr_cmd_write(ddr_cmd_write),
        .ddr_cmd_addr(ddr_cmd_addr), .ddr_cmd_len(ddr_cmd_len),
        .ddr_w_valid(ddr_w_valid), .ddr_w_ready(ddr_w_ready), .ddr_w_data(ddr_w_data),
        .ddr_w_be(ddr_w_be), .ddr_w_last(ddr_w_last),
        .ddr_r_valid(ddr_r_valid), .ddr_r_ready(ddr_r_ready), .ddr_r_data(ddr_r_data),
        .ddr_r_error(ddr_r_error), .ddr_r_last(ddr_r_last)
    );

    // Reset native IP together with CPU session; do not feed calibration back into its reset.
    assign ddr_controller_resetn = key_n && !cpu_rst;
    // ------------------------------------------------ DDR3 behind the caches


    // ------------------------------------------------ pixel-domain reset bridge
    reg [2:0] pix_rst_sync = 3'b111;
    always @(posedge pix_clk or posedge cpu_rst)
        if (cpu_rst) pix_rst_sync <= 3'b111;
        else         pix_rst_sync <= {pix_rst_sync[1:0], 1'b0};
    wire pix_rst = pix_rst_sync[2];

    // ------------------------------------------------ 27 MHz GT911 + CPU mailbox
    reg [2:0] touch_rst_sync = 3'b111;
    always @(posedge touch_clk or posedge cpu_rst)
        if (cpu_rst) touch_rst_sync <= 3'b111;
        else touch_rst_sync <= {touch_rst_sync[1:0], 1'b0};
    wire touch_rst = touch_rst_sync[2];
    wire touch_valid;
    wire [31:0] raw_touch_state, raw_touch_xy, raw_touch_seq, raw_touch_errors;
    wire [31:0] touch_state, touch_xy, touch_seq, touch_errors;
    wire [127:0] raw_touch_xy_extra, touch_xy_extra;
    wire [39:0] raw_touch_ids, touch_ids;
    fn_gt911 #(
        .CLK_HZ(TOUCH_CLOCK_HZ), .I2C_HZ(TOUCH_I2C_HZ),
        .RESET_LOW_MS(TOUCH_RESET_LOW_MS), .RESET_WAIT_MS(TOUCH_RESET_WAIT_MS),
        .INT_HOLD_MS(TOUCH_INT_HOLD_MS),
        .POLL_MS(TOUCH_POLL_MS), .STALE_MS(TOUCH_STALE_MS)
    ) u_touch (
        .clk(touch_clk), .rst(touch_rst),
        .ctp_rst_n(ctp_rst_n), .ctp_int(ctp_int), .scl(ctp_scl), .sda(ctp_sda),
        .sample_valid(touch_valid), .sample_state(raw_touch_state),
        .sample_xy(raw_touch_xy), .sample_seq(raw_touch_seq), .sample_errors(raw_touch_errors),
        .sample_xy_extra(raw_touch_xy_extra), .sample_ids(raw_touch_ids)
    );
    fn_touch_cdc u_touch_cdc (
        .src_clk(touch_clk), .src_rst(touch_rst), .src_valid(touch_valid),
        .src_state(raw_touch_state), .src_xy(raw_touch_xy),
        .src_seq(raw_touch_seq), .src_errors(raw_touch_errors),
        .src_xy_extra(raw_touch_xy_extra), .src_ids(raw_touch_ids),
        .dst_clk(cpu_clk), .dst_rst(cpu_rst),
        .dst_state(touch_state), .dst_xy(touch_xy),
        .dst_seq(touch_seq), .dst_errors(touch_errors),
        .dst_xy_extra(touch_xy_extra), .dst_ids(touch_ids)
    );

    // ------------------------------------------------ display engine
    wire frame_toggle;
    wire legacy_req_valid, legacy_req_ready, legacy_req_write;
    wire [31:0] legacy_req_addr, legacy_req_wdata;
    wire [3:0] legacy_req_be;
    wire legacy_rsp_valid, legacy_rsp_ready, legacy_rsp_error;
    wire [31:0] legacy_rsp_rdata;
    assign pose_mmio_rst = cpu_rst;
    fn_control_router u_control_router (
        .clk(cpu_clk), .rst(cpu_rst),
        .req_valid(ext_req_valid), .req_ready(ext_req_ready),
        .req_addr(ext_req_addr), .req_write(ext_req_write),
        .req_be(ext_req_be), .req_wdata(ext_req_wdata),
        .rsp_valid(ext_rsp_valid), .rsp_ready(ext_rsp_ready),
        .rsp_rdata(ext_rsp_rdata), .rsp_error(ext_rsp_error),
        .legacy_req_valid(legacy_req_valid), .legacy_req_ready(legacy_req_ready),
        .legacy_req_addr(legacy_req_addr), .legacy_req_write(legacy_req_write),
        .legacy_req_be(legacy_req_be), .legacy_req_wdata(legacy_req_wdata),
        .legacy_rsp_valid(legacy_rsp_valid), .legacy_rsp_ready(legacy_rsp_ready),
        .legacy_rsp_rdata(legacy_rsp_rdata), .legacy_rsp_error(legacy_rsp_error),
        .pose_req_valid(pose_req_valid), .pose_req_ready(pose_req_ready),
        .pose_req_addr(pose_req_addr), .pose_req_write(pose_req_write),
        .pose_req_be(pose_req_be), .pose_req_wdata(pose_req_wdata),
        .pose_rsp_valid(pose_rsp_valid), .pose_rsp_ready(pose_rsp_ready),
        .pose_rsp_rdata(pose_rsp_rdata), .pose_rsp_error(pose_rsp_error)
    );
    // Exactly one outstanding external request; remember its response owner.
    wire select_sd = legacy_req_addr[11:8] == 4'h2;
    wire gpu_req_ready, gpu_rsp_valid, gpu_rsp_error;
    wire sd_req_ready, sd_rsp_valid, sd_rsp_error;
    wire [31:0] gpu_rsp_rdata, sd_rsp_rdata;
    // 0x10004F00: DDR3 status {error_count[31:16], ready[0]} (read only)
    // 0x10004F04: LCD backlight level, percent of PWM high time (reset 70; vendor design used 20)
    wire select_ddr = legacy_req_addr[11:8] == 4'hF;
    // 0x10004E00: UART install link (fn_uart_link)
    wire select_ul = legacy_req_addr[11:8] == 4'hE;
    wire select_net = legacy_req_addr[11:8] >= 4'h3 && !select_ddr && !select_ul;
    wire ul_req_ready, ul_rsp_valid, ul_rsp_error;
    wire [31:0] ul_rsp_rdata;
    wire net_req_ready, net_rsp_valid, net_rsp_error;
    wire [31:0] net_rsp_rdata;
    reg route_net;
    reg route_ddr;
    reg route_ul;
    reg route_sd;
    reg route_busy;
    always @(posedge cpu_clk)
        if(cpu_rst) begin route_net <= 1'b0; route_sd <= 1'b0; route_ddr <= 1'b0; route_ul <= 1'b0; route_busy <= 1'b0; end
        else begin
            if(legacy_rsp_valid && legacy_rsp_ready) route_busy <= 1'b0;
            if(legacy_req_valid && legacy_req_ready) begin route_net <= select_net; route_sd <= select_sd; route_ddr <= select_ddr; route_ul <= select_ul; route_busy <= 1'b1; end
        end
    reg ddr_rsp_valid, ddr_rsp_error;
    reg [31:0] ddr_rsp_rdata;
    wire ddr_req_ready = !ddr_rsp_valid;
    always @(posedge cpu_clk)
        if (cpu_rst) begin ddr_rsp_valid <= 1'b0; ddr_rsp_error <= 1'b0; ddr_rsp_rdata <= 32'd0; backlight_level <= 7'd70; end
        else begin
            if (ddr_rsp_valid && legacy_rsp_ready && route_ddr && !route_ul) ddr_rsp_valid <= 1'b0;
            if (legacy_req_valid && select_ddr && !route_busy && ddr_req_ready) begin
                ddr_rsp_valid <= 1'b1;
                ddr_rsp_error <= 1'b0;
                ddr_rsp_rdata <= 32'd0;
                if (legacy_req_addr[7:0] == 8'h00 && !legacy_req_write) ddr_rsp_rdata <= {ddr_errors, 15'd0, ddr_ready};
                else if (legacy_req_addr[7:0] == 8'h04) begin
                    // 0x10004F04: LCD backlight high time in percent (0..100)
                    if (!legacy_req_write) ddr_rsp_rdata <= {25'd0, backlight_level};
                    else if (legacy_req_be != 4'hf || legacy_req_wdata > 32'd100) ddr_rsp_error <= 1'b1;
                    else backlight_level <= legacy_req_wdata[6:0];
                end else ddr_rsp_error <= 1'b1;
            end
        end
    assign legacy_req_ready = !route_busy && (select_ul ? ul_req_ready : select_ddr ? ddr_req_ready : select_net ? net_req_ready : select_sd ? sd_req_ready : gpu_req_ready);
    assign legacy_rsp_valid = route_ul ? ul_rsp_valid : route_ddr ? ddr_rsp_valid : route_net ? net_rsp_valid : route_sd ? sd_rsp_valid : gpu_rsp_valid;
    assign legacy_rsp_rdata = route_ul ? ul_rsp_rdata : route_ddr ? ddr_rsp_rdata : route_net ? net_rsp_rdata : route_sd ? sd_rsp_rdata : gpu_rsp_rdata;
    assign legacy_rsp_error = route_ul ? ul_rsp_error : route_ddr ? ddr_rsp_error : route_net ? net_rsp_error : route_sd ? sd_rsp_error : gpu_rsp_error;
    fn_uart_link u_uart_link (
        .clk(cpu_clk), .rst(cpu_rst),
        .req_valid(legacy_req_valid && select_ul && !route_busy), .req_ready(ul_req_ready),
        .req_addr(legacy_req_addr), .req_write(legacy_req_write), .req_be(legacy_req_be), .req_wdata(legacy_req_wdata),
        .rsp_valid(ul_rsp_valid), .rsp_ready(legacy_rsp_ready && route_ul),
        .rsp_rdata(ul_rsp_rdata), .rsp_error(ul_rsp_error),
        .uart_rx(uart_rx), .uart_tx(link_uart_tx), .take_tx(link_take_tx)
    );
    // R54: Ethernet card link removed; fn_net_absent keeps its MMIO window
    // answering (and keeps the u_net instance name the test benches probe).
    fn_net_absent u_net (
        .clk(cpu_clk), .rst(cpu_rst),
        .req_valid(legacy_req_valid && select_net && !route_busy), .req_ready(net_req_ready),
        .req_addr(legacy_req_addr), .req_write(legacy_req_write), .req_be(legacy_req_be), .req_wdata(legacy_req_wdata),
        .rsp_valid(net_rsp_valid), .rsp_ready(legacy_rsp_ready && route_net),
        .rsp_rdata(net_rsp_rdata), .rsp_error(net_rsp_error)
    );
    assign eth_tx_valid = 1'b0;
    assign eth_tx_data = 8'd0;
    fn_sd_spi u_sd (
        .clk(cpu_clk), .rst(cpu_rst),
        .req_valid(legacy_req_valid && select_sd && !route_busy), .req_ready(sd_req_ready),
        .req_addr(legacy_req_addr), .req_write(legacy_req_write), .req_be(legacy_req_be), .req_wdata(legacy_req_wdata),
        .rsp_valid(sd_rsp_valid), .rsp_ready(legacy_rsp_ready && route_sd && !route_net && !route_ddr && !route_ul),
        .rsp_rdata(sd_rsp_rdata), .rsp_error(sd_rsp_error),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
    );
    fn_gpu_ddr_system_split #(
        .FONT_INIT(`FN_FONT_HEX),
        .PAL_INIT(`FN_PAL_HEX),
        .CLOCK_HZ(CLOCK_HZ)
    ) u_gpu (
        .hdmi_clk(hdmi_clk),.hdmi_lock(hdmi_lock),.hdmi_reset(hdmi_reset),.hdmi_hs(hdmi_hs),.hdmi_vs(hdmi_vs),.hdmi_de(hdmi_de),.hdmi_x(hdmi_x),.hdmi_y(hdmi_y),.hdmi_rgb(hdmi_rgb),
        .cpu_clk(cpu_clk), .cpu_rst(cpu_rst),
        .req_valid(legacy_req_valid && !select_sd && !select_net && !select_ddr && !select_ul && !route_busy), .req_ready(gpu_req_ready), .req_addr(legacy_req_addr),
        .req_write(legacy_req_write), .req_be(legacy_req_be), .req_wdata(legacy_req_wdata),
        .rsp_valid(gpu_rsp_valid), .rsp_ready(legacy_rsp_ready && !route_sd && !route_net && !route_ddr && !route_ul), .rsp_rdata(gpu_rsp_rdata),
        .rsp_error(gpu_rsp_error),
        .touch_state(touch_state), .touch_xy(touch_xy),
        .touch_seq(touch_seq), .touch_errors(touch_errors), .touch_xy_extra(touch_xy_extra), .touch_ids(touch_ids),
        .draw_clk(gpu_clk), .pix_clk(pix_clk),
        .ddr_clk(ddr_core_clk), .calibrated(ddr_init_done),
        .cmd_valid(ddr_cmd_valid), .cmd_ready(ddr_cmd_ready), .cmd_write(ddr_cmd_write),
        .cmd_addr(ddr_cmd_addr), .cmd_len(ddr_cmd_len),
        .w_valid(ddr_w_valid), .w_ready(ddr_w_ready), .w_data(ddr_w_data), .w_be(ddr_w_be), .w_last(ddr_w_last),
        .r_valid(ddr_r_valid), .r_ready(ddr_r_ready), .r_data(ddr_r_data), .r_error(ddr_r_error), .r_last(ddr_r_last),
        .ddr_ready(ddr_ready), .error_count(ddr_errors),
        .axi_awaddr(ddr_axi_awaddr), .axi_awvalid(ddr_axi_awvalid), .axi_awready(ddr_axi_awready),
        .axi_wdata(ddr_axi_wdata), .axi_wstrb(ddr_axi_wstrb), .axi_wready(ddr_axi_wready),
        .axi_araddr(ddr_axi_araddr), .axi_arvalid(ddr_axi_arvalid), .axi_arready(ddr_axi_arready),
        .axi_rdata(ddr_axi_rdata), .axi_rvalid(ddr_axi_rvalid), .axi_rlast(ddr_axi_rlast),
        .framebuffer_underflow(), .framebuffer_error(),
        .lcd_hs(lcd_hs), .lcd_vs(lcd_vs), .lcd_de(lcd_de),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b),
        .frame_toggle(frame_toggle)
    );

    // LED0/1: firmware GPIO[0]/[1], LED2: blinks with the display frame counter,
    // LED3: CPU fatal/failed
    assign led = {failed, frame_toggle, gpio_out[1], gpio_out[0]};
endmodule

// rtl/pose/pe.sv
module pe (
	clk,
	clk_en,
	D,
	W,
	y_in,
	y_out
);
	parameter DATA_WIDTH = 10'd7;
	parameter WEIGHT_WIDTH = 10'd8;
	parameter ADDER2_WIDTH = 10'd18;
	parameter OUTPUT_WIDTH = 10'd19;
	parameter USE_DSP_PE = "no";
	input clk;
	input clk_en;
	input [DATA_WIDTH - 1:0] D;
	input signed [WEIGHT_WIDTH - 1:0] W;
	input signed [ADDER2_WIDTH - 1:0] y_in;
	output reg signed [OUTPUT_WIDTH - 1:0] y_out;
	localparam signed [31:0] PRODUCT_WIDTH = DATA_WIDTH + WEIGHT_WIDTH;
	function automatic signed [PRODUCT_WIDTH - 1:0] mul_no_dsp;
		input reg [DATA_WIDTH - 1:0] d_in;
		input reg signed [WEIGHT_WIDTH - 1:0] w_in;
		reg signed [PRODUCT_WIDTH - 1:0] acc;
		reg signed [PRODUCT_WIDTH - 1:0] d_ext;
		reg signed [31:0] bit_idx;
		begin
			acc = 1'sb0;
			d_ext = $signed({1'b0, d_in});
			for (bit_idx = 0; bit_idx < (WEIGHT_WIDTH - 1); bit_idx = bit_idx + 1)
				if (w_in[bit_idx])
					acc = acc + (d_ext <<< bit_idx);
			if (w_in[WEIGHT_WIDTH - 1])
				acc = acc - (d_ext <<< (WEIGHT_WIDTH - 1));
			mul_no_dsp = acc;
		end
	endfunction
	reg signed [PRODUCT_WIDTH - 1:0] mult_result_reg;
	reg signed [DATA_WIDTH:0] D_reg;
	reg signed [WEIGHT_WIDTH - 1:0] W_reg;
	reg signed [DATA_WIDTH:0] D_reg_reg;
	reg signed [WEIGHT_WIDTH - 1:0] W_reg_reg;
	always @(posedge clk)
		if (clk_en) begin
			if (USE_DSP_PE == "yes") begin
				D_reg <= $signed({1'b0, D});
				W_reg <= W;
				D_reg_reg <= D_reg;
				W_reg_reg <= W_reg;
				y_out <= (D_reg_reg * W_reg_reg) + y_in;
			end
			else begin
				D_reg <= $signed({1'b0, D});
				W_reg <= W;
				mult_result_reg <= mul_no_dsp(D_reg, W_reg);
				y_out <= y_in + mult_result_reg;
			end
		end
endmodule
module p2_fifo (
	clk,
	rst,
	in_valid,
	in_ready,
	in_data,
	out_valid,
	out_ready,
	out_data
);
	parameter integer WIDTH = 8;
	parameter integer DEPTH = 16;
	input wire clk;
	input wire rst;
	input wire in_valid;
	output wire in_ready;
	input wire [WIDTH - 1:0] in_data;
	output wire out_valid;
	input wire out_ready;
	output wire [WIDTH - 1:0] out_data;
	localparam integer AW = (DEPTH > 1 ? $clog2(DEPTH) : 1);
	(* syn_ramstyle = "lut_ram" *) reg [WIDTH - 1:0] mem [0:DEPTH - 1];
	reg [AW - 1:0] wp;
	reg [AW - 1:0] rp;
	reg [AW:0] count;
	assign in_ready = !rst && (count < DEPTH);
	assign out_valid = count != 0;
	assign out_data = mem[rp];
	wire push = in_valid && in_ready;
	wire pop = out_valid && out_ready;
	always @(posedge clk) begin
		if (push)
			mem[wp] <= in_data;
		if (rst) begin
			wp <= 0;
			rp <= 0;
			count <= 0;
		end
		else begin
			if (push)
				wp <= (wp == (DEPTH - 1) ? 0 : wp + 1'b1);
			if (pop)
				rp <= (rp == (DEPTH - 1) ? 0 : rp + 1'b1);
			count <= (count + (push ? 1'b1 : 1'b0)) - (pop ? 1'b1 : 1'b0);
		end
	end
endmodule
module p2_async_fifo (
	wclk,
	wrst,
	wvalid,
	wdata,
	wfull,
	rclk,
	rrst,
	rvalid,
	rready,
	rdata
);
	parameter integer WIDTH = 17;
	parameter integer AW = 5;
	input wire wclk;
	input wire wrst;
	input wire wvalid;
	input wire [WIDTH - 1:0] wdata;
	output wire wfull;
	input wire rclk;
	input wire rrst;
	output wire rvalid;
	input wire rready;
	output wire [WIDTH - 1:0] rdata;
	localparam integer DEPTH = 1 << AW;
	reg [WIDTH - 1:0] mem [0:DEPTH - 1];
	reg [AW:0] wbin;
	reg [AW:0] wgray;
	reg [AW:0] rbin;
	reg [AW:0] rgray;
	(* async_reg = "true" *) reg [AW:0] rgray_w1;
	(* async_reg = "true" *) reg [AW:0] rgray_w2;
	(* async_reg = "true" *) reg [AW:0] wgray_r1;
	(* async_reg = "true" *) reg [AW:0] wgray_r2;
	wire [AW:0] wbin_next = wbin + 1'b1;
	wire [AW:0] rbin_next = rbin + 1'b1;
	assign wfull = wgray == {~rgray_w2[AW:AW - 1], rgray_w2[AW - 2:0]};
	assign rvalid = rgray != wgray_r2;
	assign rdata = mem[rbin[AW - 1:0]];
	always @(posedge wclk) begin
		if (wvalid && !wfull)
			mem[wbin[AW - 1:0]] <= wdata;
		if (wrst) begin
			wbin <= 0;
			wgray <= 0;
			rgray_w1 <= 0;
			rgray_w2 <= 0;
		end
		else begin
			rgray_w1 <= rgray;
			rgray_w2 <= rgray_w1;
			if (wvalid && !wfull) begin
				wbin <= wbin_next;
				wgray <= wbin_next ^ (wbin_next >> 1);
			end
		end
	end
	always @(posedge rclk)
		if (rrst) begin
			rbin <= 0;
			rgray <= 0;
			wgray_r1 <= 0;
			wgray_r2 <= 0;
		end
		else begin
			wgray_r1 <= wgray;
			wgray_r2 <= wgray_r1;
			if (rvalid && rready) begin
				rbin <= rbin_next;
				rgray <= rbin_next ^ (rbin_next >> 1);
			end
		end
endmodule
module p2_window3x3 (
	clk,
	rst,
	start_valid,
	start_ready,
	start_frame_id,
	in_valid,
	in_ready,
	in_data,
	in_last,
	out_valid,
	out_ready,
	out_window,
	out_y,
	out_x,
	out_frame_id,
	out_last,
	out_rows_ok,
	busy,
	frame_error
);
	parameter integer H = 192;
	parameter integer W = 128;
	parameter integer CIN = 3;
	parameter integer STRIDE = 2;
	parameter integer VW = 8 * CIN;
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [31:0] start_frame_id;
	input wire in_valid;
	output wire in_ready;
	input wire [VW - 1:0] in_data;
	input wire in_last;
	output wire out_valid;
	input wire out_ready;
	output wire [(9 * VW) - 1:0] out_window;
	output wire [15:0] out_y;
	output wire [15:0] out_x;
	output wire [31:0] out_frame_id;
	output wire out_last;
	output wire [1:0] out_rows_ok;
	output wire busy;
	output reg frame_error;
	localparam integer XW = $clog2(W + 2);
	localparam integer YW = $clog2(H + 2);
	reg [XW - 1:0] px;
	reg [YW - 1:0] py;
	reg active;
	reg scan_done;
	reg [31:0] frame_id;
	(* syn_ramstyle = "lut_ram" *) reg [(2 * VW) - 1:0] lines [0:W + 1];
	wire [(2 * VW) - 1:0] line_q = lines[px];
	reg [VW - 1:0] t1;
	reg [VW - 1:0] t2;
	reg [VW - 1:0] m1;
	reg [VW - 1:0] m2;
	reg [VW - 1:0] b1;
	reg [VW - 1:0] b2;
	wire real_pixel = (((py > 0) && (py <= H)) && (px > 0)) && (px <= W);
	wire token_ok = !real_pixel || in_valid;
	wire [VW - 1:0] token = (real_pixel ? in_data : {VW {1'b0}});
	wire [VW - 1:0] top = line_q[(2 * VW) - 1:VW];
	wire [VW - 1:0] middle = line_q[VW - 1:0];
	assign out_rows_ok = 2'b11;
	wire emit_window = (((py >= 2) && (px >= 2)) && (((py - 2) % STRIDE) == 0)) && (((px - 2) % STRIDE) == 0);
	wire running = active && !scan_done;
	assign out_valid = (running && emit_window) && token_ok;
	assign out_window = {token, b1, b2, middle, m1, m2, top, t1, t2};
	assign out_y = (py - 2) / STRIDE;
	assign out_x = (px - 2) / STRIDE;
	assign out_frame_id = frame_id;
	assign out_last = (((py - 2) / STRIDE) == ((H - 1) / STRIDE)) && (((px - 2) / STRIDE) == ((W - 1) / STRIDE));
	wire step = ((!rst && running) && token_ok) && (!emit_window || out_ready);
	assign in_ready = step && real_pixel;
	assign start_ready = !rst && !active;
	assign busy = active;
	always @(posedge clk)
		if (rst) begin
			px <= 0;
			py <= 0;
			active <= 0;
			scan_done <= 0;
			frame_id <= 0;
			frame_error <= 0;
			t1 <= 0;
			t2 <= 0;
			m1 <= 0;
			m2 <= 0;
			b1 <= 0;
			b2 <= 0;
		end
		else begin
			if (start_valid && start_ready) begin
				active <= 1;
				scan_done <= 0;
				px <= 0;
				py <= 0;
				frame_id <= start_frame_id;
				frame_error <= 0;
			end
			if (step) begin
				lines[px] <= {line_q[VW - 1:0], token};
				if (px == 0) begin
					t2 <= 0;
					m2 <= 0;
					b2 <= 0;
				end
				else begin
					t2 <= t1;
					m2 <= m1;
					b2 <= b1;
				end
				t1 <= top;
				m1 <= middle;
				b1 <= token;
				if (emit_window && out_last)
					active <= 0;
				if (px == (W + 1)) begin
					px <= 0;
					if (py == (H + 1))
						scan_done <= 1;
					else
						py <= py + 1'b1;
				end
				else
					px <= px + 1'b1;
				if (real_pixel && (in_last != ((py == H) && (px == W)))) begin
					frame_error <= 1;
					active <= 0;
					scan_done <= 1;
				end
			end
		end
endmodule
module p2_window_cs (
	clk,
	rst,
	start_valid,
	start_ready,
	start_frame_id,
	in_valid,
	in_ready,
	in_data,
	in_last,
	win_valid,
	win_release,
	rd_ch,
	tap_data,
	out_y,
	out_x,
	out_frame_id,
	out_last,
	frame_error
);
	parameter integer H = 192;
	parameter integer W = 128;
	parameter integer CIN = 3;
	parameter integer STRIDE = 2;
	parameter integer CW = (CIN > 1 ? $clog2(CIN) : 1);
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [31:0] start_frame_id;
	input wire in_valid;
	output wire in_ready;
	input wire [(8 * CIN) - 1:0] in_data;
	input wire in_last;
	output wire win_valid;
	input wire win_release;
	input wire [CW - 1:0] rd_ch;
	output wire [71:0] tap_data;
	output wire [15:0] out_y;
	output wire [15:0] out_x;
	output wire [31:0] out_frame_id;
	output wire out_last;
	output reg frame_error;
	localparam integer NB = 3 + STRIDE;
	localparam integer XW = $clog2(W + 2);
	localparam integer YW = $clog2(H + 2);
	localparam integer LDEPTH = (W + 2) * CIN;
	localparam integer LAW = $clog2(LDEPTH);
	localparam integer SW = $clog2(NB);
	reg [XW - 1:0] px;
	reg [YW - 1:0] py;
	reg active;
	reg scan_done;
	reg [31:0] frame_id;
	reg filling;
	reg [CW - 1:0] fch;
	reg [LAW - 1:0] fbase;
	reg rd_pending;
	reg [CW - 1:0] wch;
	reg [SW - 1:0] fill_slot;
	reg [15:0] filled;
	wire real_pixel = (((py > 0) && (py <= H)) && (px > 0)) && (px <= W);
	reg [1:0] npend;
	reg [15:0] pend_first [0:1];
	reg [SW - 1:0] pend_slot [0:1];
	reg [15:0] pend_y [0:1];
	reg [15:0] pend_x [0:1];
	reg pend_last [0:1];
	assign win_valid = npend != 0;
	assign out_y = pend_y[0];
	assign out_x = pend_x[0];
	assign out_last = pend_last[0];
	assign out_frame_id = frame_id;
	wire [15:0] oldest_needed = (npend != 0 ? pend_first[0] : filled - 16'd2);
	wire [15:0] fill_gap = filled - oldest_needed;
	wire bank_free = fill_gap < NB;
	wire running = active && !scan_done;
	wire token_ok = !real_pixel || in_valid;
	wire can_fill = (((running && !filling) && token_ok) && bank_free) && (npend < 2);
	wire emit_here = (((py >= 2) && (px >= 2)) && (((py - 2) % STRIDE) == 0)) && (((px - 2) % STRIDE) == 0);
	reg [15:0] line_q;
	reg rd_pending_last;
	wire rd_issue = filling && !rd_pending_last;
	reg [(8 * CIN) - 1:0] tok_q;
	wire [7:0] token_byte = tok_q[8 * wch+:8];
	wire wr_cycle = rd_pending;
	wire [LAW - 1:0] rd_addr = fbase + fch;
	wire [LAW - 1:0] wr_addr = fbase + wch;
	generate
		if (LDEPTH >= 512) begin : line_block
			(* syn_ramstyle = "block_ram" *) reg [15:0] lines [0:LDEPTH - 1];
			always @(posedge clk) begin
				if (rd_issue)
					line_q <= lines[rd_addr];
				if (wr_cycle)
					lines[wr_addr] <= {line_q[7:0], token_byte};
			end
		end
		else begin : line_lut
			(* syn_ramstyle = "lut_ram" *) reg [15:0] lines [0:LDEPTH - 1];
			always @(posedge clk) begin
				if (rd_issue)
					line_q <= lines[rd_addr];
				if (wr_cycle)
					lines[wr_addr] <= {line_q[7:0], token_byte};
			end
		end
	endgenerate
	genvar _gv_rr_1;
	genvar _gv_bb_1;
	wire [7:0] bank_q [0:2][0:NB - 1];
	generate
		for (_gv_rr_1 = 0; _gv_rr_1 < 3; _gv_rr_1 = _gv_rr_1 + 1) begin : row
			localparam rr = _gv_rr_1;
			for (_gv_bb_1 = 0; _gv_bb_1 < NB; _gv_bb_1 = _gv_bb_1 + 1) begin : bank
				localparam bb = _gv_bb_1;
				(* syn_ramstyle = "lut_ram" *) reg [7:0] mem [0:CIN - 1];
				wire [7:0] wdata = (rr == 0 ? line_q[15:8] : (rr == 1 ? line_q[7:0] : token_byte));
				always @(posedge clk)
					if (wr_cycle && (fill_slot == bb))
						mem[wch] <= wdata;
				assign bank_q[rr][bb] = mem[rd_ch];
			end
		end
	endgenerate
	genvar _gv_kx_1;
	generate
		for (_gv_rr_1 = 0; _gv_rr_1 < 3; _gv_rr_1 = _gv_rr_1 + 1) begin : tap_row
			localparam rr = _gv_rr_1;
			for (_gv_kx_1 = 0; _gv_kx_1 < 3; _gv_kx_1 = _gv_kx_1 + 1) begin : tap_col
				localparam kx = _gv_kx_1;
				wire [SW:0] s = pend_slot[0] + kx;
				wire [SW - 1:0] slot = (s >= NB ? s - NB : s);
				assign tap_data[8 * ((rr * 3) + kx)+:8] = bank_q[rr][slot];
			end
		end
	endgenerate
	assign start_ready = (!rst && !active) && !filling;
	wire col_done = wr_cycle && (wch == (CIN - 1));
	assign in_ready = can_fill && real_pixel;
	integer k;
	always @(posedge clk)
		if (rst) begin
			px <= 0;
			py <= 0;
			active <= 0;
			scan_done <= 0;
			frame_id <= 0;
			frame_error <= 0;
			filling <= 0;
			fch <= 0;
			fbase <= 0;
			rd_pending <= 0;
			rd_pending_last <= 0;
			wch <= 0;
			fill_slot <= 0;
			filled <= 0;
			npend <= 0;
			for (k = 0; k < 2; k = k + 1)
				begin
					pend_first[k] <= 0;
					pend_slot[k] <= 0;
					pend_y[k] <= 0;
					pend_x[k] <= 0;
					pend_last[k] <= 0;
				end
		end
		else begin
			if (start_valid && start_ready) begin
				active <= 1;
				scan_done <= 0;
				px <= 0;
				py <= 0;
				fbase <= 0;
				frame_id <= start_frame_id;
				frame_error <= 0;
			end
			rd_pending <= rd_issue;
			if (rd_issue) begin
				wch <= fch;
				if (fch == (CIN - 1))
					rd_pending_last <= 1;
				else
					fch <= fch + 1'b1;
			end
			if (can_fill) begin
				filling <= 1;
				fch <= 0;
				rd_pending_last <= 0;
				tok_q <= (real_pixel ? in_data : {8 * CIN {1'b0}});
				if (real_pixel && (in_last != ((py == H) && (px == W)))) begin
					frame_error <= 1;
					active <= 0;
					scan_done <= 1;
				end
			end
			if (win_release && (npend != 0)) begin
				pend_first[0] <= pend_first[1];
				pend_slot[0] <= pend_slot[1];
				pend_y[0] <= pend_y[1];
				pend_x[0] <= pend_x[1];
				pend_last[0] <= pend_last[1];
			end
			if (col_done) begin
				filling <= 0;
				rd_pending_last <= 0;
				fch <= 0;
				filled <= filled + 1'b1;
				fill_slot <= (fill_slot == (NB - 1) ? 0 : fill_slot + 1'b1);
				if (emit_here) begin
					if (win_release && (npend != 0))
						k = npend - 1;
					else
						k = npend;
					pend_first[k] <= filled - 16'd2;
					pend_slot[k] <= (fill_slot >= 2 ? fill_slot - 2 : (fill_slot + NB) - 2);
					pend_y[k] <= (py - 2) / STRIDE;
					pend_x[k] <= (px - 2) / STRIDE;
					pend_last[k] <= (((py - 2) / STRIDE) == ((H - 1) / STRIDE)) && (((px - 2) / STRIDE) == ((W - 1) / STRIDE));
					if ((((py - 2) / STRIDE) == ((H - 1) / STRIDE)) && (((px - 2) / STRIDE) == ((W - 1) / STRIDE)))
						scan_done <= 1;
				end
				if (px == (W + 1)) begin
					px <= 0;
					fbase <= 0;
					if (py == (H + 1))
						scan_done <= 1;
					else
						py <= py + 1'b1;
				end
				else begin
					px <= px + 1'b1;
					fbase <= fbase + CIN;
				end
			end
			npend <= (npend + (col_done && emit_here ? 1'b1 : 1'b0)) - (win_release && (npend != 0) ? 1'b1 : 1'b0);
			if ((win_release && (npend != 0)) && pend_last[0])
				active <= 0;
		end
endmodule
module p2_systolic (
	clk,
	rst,
	in_valid,
	in_ready,
	in_window,
	in_rows_ok,
	in_taps,
	rd_ch,
	in_frame_id,
	in_y,
	in_x,
	in_last,
	out_valid,
	out_ready,
	out_data,
	out_frame_id,
	out_y,
	out_x,
	out_last
);
	parameter integer CIN = 3;
	parameter integer COUT = 16;
	parameter integer TAPS = 9;
	parameter integer PAGES = 1;
	parameter integer COLS = 1;
	parameter integer SHIFT = 8;
	parameter integer RELU = 1;
	parameter USE_DSP_PE = "yes";
	parameter WEIGHT_FILE = "weights.mem";
	parameter WEIGHT_FILE1 = "";
	parameter WEIGHT_FILE2 = "";
	parameter WEIGHT_FILE3 = "";
	parameter [(32 * COUT) - 1:0] BIAS_VEC = 0;
	parameter integer CS = 0;
	parameter integer CI = CIN / PAGES;
	parameter integer CO = COUT / COLS;
	parameter integer PERIOD = CI * CO;
	parameter integer WW = ((8 * TAPS) * PAGES) * COLS;
	input wire clk;
	input wire rst;
	input wire in_valid;
	output wire in_ready;
	input wire [((8 * TAPS) * CIN) - 1:0] in_window;
	input wire [1:0] in_rows_ok;
	input wire [(8 * TAPS) - 1:0] in_taps;
	output wire [((CIN / PAGES) > 1 ? $clog2(CIN / PAGES) : 1) - 1:0] rd_ch;
	input wire [31:0] in_frame_id;
	input wire [15:0] in_y;
	input wire [15:0] in_x;
	input wire in_last;
	output reg out_valid;
	input wire out_ready;
	output reg [(8 * COUT) - 1:0] out_data;
	output reg [31:0] out_frame_id;
	output reg [15:0] out_y;
	output reg [15:0] out_x;
	output reg out_last;
	localparam integer LATENCY = (TAPS + COLS) + 2;
	localparam integer TAGD = ((LATENCY + 1) / PERIOD) + 2;
	localparam integer PW = (PERIOD > 1 ? $clog2(PERIOD) : 1);
	localparam integer TW = $clog2(TAGD + 1);
	localparam integer IW = (CI > 1 ? $clog2(CI) : 1);
	localparam integer OW = (CO > 1 ? $clog2(CO) : 1);
	localparam integer COPY = (CS == 0) && (PERIOD < 512);
	localparam integer TILE = 1024;
	localparam integer NT = ((PERIOD > TILE) && (WW >= 72) ? ((PERIOD + TILE) - 1) / TILE : 1);
	reg [((8 * TAPS) * CIN) - 1:0] window_q;
	reg [1:0] rows_q;
	reg issue_active;
	reg holding;
	reg [PW - 1:0] phase;
	reg [IW - 1:0] pci;
	reg [OW - 1:0] pco;
	reg [WW - 1:0] weight_q;
	reg [(8 * COUT) - 1:0] out_build;
	reg [LATENCY - 1:0] valid_pipe;
	reg [IW - 1:0] ci_pipe [0:LATENCY - 1];
	reg [OW - 1:0] co_pipe [0:LATENCY - 1];
	reg [64:0] tag_mem [0:TAGD - 1];
	reg [TW - 1:0] tag_count;
	reg [TW - 1:0] tag_wr;
	reg [TW - 1:0] tag_rd;
	wire last_phase = phase == (PERIOD - 1);
	wire [IW - 1:0] done_ci = ci_pipe[LATENCY - 1];
	wire [OW - 1:0] done_co = co_pipe[LATENCY - 1];
	reg q_valid;
	reg [IW - 1:0] q_ci;
	reg [OW - 1:0] q_co;
	// R69: registered column values (col_r) are written into out_build one
	// advance after the q stage; completion moves with them.
	reg r_valid;
	reg [OW - 1:0] r_co;
	reg [(8 * COLS) - 1:0] col_r;
	wire completing = r_valid && (r_co == (CO - 1));
	wire stall = completing && out_valid;
	wire advance = !stall;
	wire start;
	wire release_window;
	generate
		if (COPY) begin : copy_window
			assign in_ready = ((!rst && advance) && last_phase) && (tag_count < TAGD);
			assign start = in_valid && in_ready;
			assign release_window = 1'b0;
		end
		else begin : held_window
			assign start = ((((!rst && advance) && in_valid) && !holding) && last_phase) && (tag_count < TAGD);
			assign release_window = ((advance && holding) && issue_active) && last_phase;
			assign in_ready = release_window;
		end
	endgenerate
	wire [((8 * TAPS) * CIN) - 1:0] issue_window = (COPY ? window_q : in_window);
	wire [1:0] issue_rows = (COPY ? rows_q : in_rows_ok);
	assign rd_ch = pci;
	generate
		if (NT > 1) begin : rom_tiled
			reg [1:0] tile_q;
			wire [WW - 1:0] tile_data [0:NT - 1];
			always @(posedge clk)
				if (advance)
					tile_q <= phase[PW - 1:10];
			always @(*) weight_q = tile_data[tile_q];
			genvar _gv_t_1;
			for (_gv_t_1 = 0; _gv_t_1 < NT; _gv_t_1 = _gv_t_1 + 1) begin : tile
				localparam t = _gv_t_1;
				localparam integer WORDS = ((PERIOD - (t * TILE)) < TILE ? PERIOD - (t * TILE) : TILE);
				(* syn_ramstyle = "block_ram" *) reg [WW - 1:0] mem [0:WORDS - 1];
				reg [WW - 1:0] q;
				if (t == 0) begin : l0
					initial $readmemh(WEIGHT_FILE, mem);
				end
				if (t == 1) begin : l1
					initial $readmemh(WEIGHT_FILE1, mem);
				end
				if (t == 2) begin : l2
					initial $readmemh(WEIGHT_FILE2, mem);
				end
				if (t == 3) begin : l3
					initial $readmemh(WEIGHT_FILE3, mem);
				end
				always @(posedge clk)
					if (advance && (phase[PW - 1:10] == t))
						q <= mem[phase[9:0]];
				assign tile_data[t] = q;
			end
		end
		else if (PERIOD >= 256) begin : rom_block
			(* syn_ramstyle = "block_ram" *) reg [WW - 1:0] weight_mem [0:PERIOD - 1];
			initial $readmemh(WEIGHT_FILE, weight_mem);
			always @(posedge clk)
				if (advance)
					weight_q <= weight_mem[phase];
		end
		else begin : rom_small
			reg [WW - 1:0] weight_mem [0:PERIOD - 1];
			initial $readmemh(WEIGHT_FILE, weight_mem);
			always @(posedge clk)
				if (advance)
					weight_q <= weight_mem[phase];
		end
	endgenerate
	wire signed [31:0] page_result [0:PAGES - 1][0:COLS - 1];
	wire signed [31:0] aligned_result [0:PAGES - 1][0:COLS - 1];
	genvar _gv_p_1;
	genvar _gv_c_1;
	genvar _gv_r_1;
	generate
		for (_gv_p_1 = 0; _gv_p_1 < PAGES; _gv_p_1 = _gv_p_1 + 1) begin : page
			localparam p = _gv_p_1;
			for (_gv_r_1 = 0; _gv_r_1 < TAPS; _gv_r_1 = _gv_r_1 + 1) begin : act
				localparam r = _gv_r_1;
				reg [7:0] d [0:(r + COLS) - 1];
				integer k;
				always @(posedge clk)
					if (advance) begin
						d[0] <= ((((TAPS == 9) && (r < 3)) && !issue_rows[1]) || ((((TAPS == 9) && (r >= 3)) && (r < 6)) && !issue_rows[0]) ? 8'd0 : (CS ? in_taps[8 * r+:8] : issue_window[8 * (((r * CIN) + (p * CI)) + pci)+:8]));
						for (k = 1; k < (r + COLS); k = k + 1)
							d[k] <= d[k - 1];
					end
			end
			for (_gv_c_1 = 0; _gv_c_1 < COLS; _gv_c_1 = _gv_c_1 + 1) begin : column
				localparam c = _gv_c_1;
				wire signed [31:0] chain [0:TAPS];
				assign chain[0] = 0;
				for (_gv_r_1 = 0; _gv_r_1 < TAPS; _gv_r_1 = _gv_r_1 + 1) begin : tap
					localparam r = _gv_r_1;
					pe #(
						.DATA_WIDTH(8),
						.WEIGHT_WIDTH(8),
						.ADDER2_WIDTH(32),
						.OUTPUT_WIDTH(32),
						.USE_DSP_PE(USE_DSP_PE)
					) cell_pe(
						.clk(clk),
						.clk_en(advance),
						.D(act[r].d[r + c]),
						.W(weight_q[8 * ((((p * COLS) + c) * TAPS) + r)+:8]),
						.y_in(chain[r]),
						.y_out(chain[r + 1])
					);
				end
				assign page_result[p][c] = chain[TAPS];
				if (((COLS - c) - 1) == 0) begin : nodeskew
					assign aligned_result[p][c] = page_result[p][c];
				end
				else begin : deskew
					reg signed [31:0] delay_line [0:(COLS - c) - 2];
					integer d;
					always @(posedge clk)
						if (advance) begin
							delay_line[0] <= page_result[p][c];
							for (d = 1; d < ((COLS - c) - 1); d = d + 1)
								delay_line[d] <= delay_line[d - 1];
						end
					assign aligned_result[p][c] = delay_line[(COLS - c) - 2];
				end
			end
		end
	endgenerate
	wire [7:0] col_value [0:COLS - 1];
	generate
		for (_gv_c_1 = 0; _gv_c_1 < COLS; _gv_c_1 = _gv_c_1 + 1) begin : acc
			localparam c = _gv_c_1;
			(* syn_ramstyle = "lut_ram" *) reg signed [31:0] partial [0:CO - 1];
			wire signed [31:0] bias = BIAS_VEC[32 * ((c * CO) + done_co)+:32];
			reg signed [32:0] total;
			reg signed [32:0] total_q;
			reg signed [33:0] rounded;
			integer j;
			wire bypass = q_valid && (q_co == done_co);
			always @(*) begin
				total = (done_ci == 0 ? bias : (bypass ? $signed(total_q[31:0]) : partial[done_co]));
				for (j = 0; j < PAGES; j = j + 1)
					total = total + aligned_result[j][c];
			end
			always @(posedge clk)
				if (advance) begin
					if (valid_pipe[LATENCY - 1])
						total_q <= total;
					if (q_valid)
						partial[q_co] <= total_q[31:0];
				end
			always @(*) begin
				rounded = $signed({total_q[32], total_q});
				rounded = (rounded >>> SHIFT) + ((rounded >>> (SHIFT - 1)) & 1);
			end
			assign col_value[c] = (RELU ? (rounded < 0 ? 8'd0 : (rounded > 255 ? 8'd255 : rounded[7:0])) : (rounded < -128 ? 8'h80 : (rounded > 127 ? 8'h7f : rounded[7:0])));
		end
	endgenerate
	integer i;
	reg [(8 * COUT) - 1:0] build;
	always @(posedge clk)
		if (rst) begin
			issue_active <= 0;
			holding <= 0;
			phase <= PERIOD - 1;
			pci <= CI - 1;
			pco <= CO - 1;
			valid_pipe <= 0;
			tag_count <= 0;
			tag_wr <= 0;
			tag_rd <= 0;
			out_valid <= 0;
			out_data <= 0;
			out_frame_id <= 0;
			out_y <= 0;
			out_x <= 0;
			out_last <= 0;
			out_build <= 0;
			q_valid <= 0;
			r_valid <= 0;
			q_ci <= 0;
			q_co <= 0;
			for (i = 0; i < LATENCY; i = i + 1)
				begin
					ci_pipe[i] <= 0;
					co_pipe[i] <= 0;
				end
		end
		else begin
			if (out_valid && out_ready)
				out_valid <= 0;
			if (advance) begin
				valid_pipe <= {valid_pipe[LATENCY - 2:0], issue_active};
				ci_pipe[0] <= pci;
				co_pipe[0] <= pco;
				for (i = 1; i < LATENCY; i = i + 1)
					begin
						ci_pipe[i] <= ci_pipe[i - 1];
						co_pipe[i] <= co_pipe[i - 1];
					end
				if ((!issue_active && (valid_pipe == 0)) && !start) begin
					phase <= PERIOD - 1;
					pci <= CI - 1;
					pco <= CO - 1;
				end
				else begin
					phase <= (last_phase ? 0 : phase + 1'b1);
					if (pco == (CO - 1)) begin
						pco <= 0;
						pci <= (pci == (CI - 1) ? 0 : pci + 1'b1);
					end
					else
						pco <= pco + 1'b1;
				end
				if (release_window)
					holding <= 0;
				if (start) begin
					if (COPY) begin
						window_q <= in_window;
						rows_q <= in_rows_ok;
					end
					issue_active <= 1;
					holding <= !COPY;
					tag_mem[tag_wr] <= {in_last, in_x, in_y, in_frame_id};
					tag_wr <= (tag_wr == (TAGD - 1) ? 0 : tag_wr + 1'b1);
				end
				else if (last_phase)
					issue_active <= 0;
				q_valid <= valid_pipe[LATENCY - 1];
				q_ci <= done_ci;
				q_co <= done_co;
				r_valid <= q_valid && (q_ci == (CI - 1));
				r_co <= q_co;
				for (i = 0; i < COLS; i = i + 1)
					col_r[i * 8+:8] <= col_value[i];
				build = out_build;
				if (r_valid)
					for (i = 0; i < COLS; i = i + 1)
						build[((i * CO) + r_co) * 8+:8] = col_r[i * 8+:8];
				out_build <= build;
				if (completing) begin
					out_valid <= 1;
					out_data <= build;
					{out_last, out_x, out_y, out_frame_id} <= tag_mem[tag_rd];
					tag_rd <= (tag_rd == (TAGD - 1) ? 0 : tag_rd + 1'b1);
				end
				tag_count <= (tag_count + (start ? 1'b1 : 1'b0)) - (completing ? 1'b1 : 1'b0);
			end
		end
endmodule
module p2_layer (
	clk,
	rst,
	start_valid,
	start_ready,
	start_frame_id,
	in_valid,
	in_ready,
	in_data,
	in_last,
	out_valid,
	out_ready,
	out_data,
	out_frame_id,
	out_y,
	out_x,
	out_last,
	frame_error
);
	parameter integer H = 192;
	parameter integer W = 128;
	parameter integer CIN = 3;
	parameter integer COUT = 16;
	parameter integer KERNEL = 3;
	parameter integer STRIDE = 2;
	parameter integer PAGES = 1;
	parameter integer COLS = 1;
	parameter integer SHIFT = 8;
	parameter integer RELU = 1;
	parameter integer FIFO_DEPTH = 0;
	parameter USE_DSP_PE = "yes";
	parameter WEIGHT_FILE = "weights.mem";
	parameter WEIGHT_FILE1 = "";
	parameter WEIGHT_FILE2 = "";
	parameter WEIGHT_FILE3 = "";
	parameter [(32 * COUT) - 1:0] BIAS_VEC = 0;
	parameter integer CS = (KERNEL == 3) && (PAGES == 1);
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [31:0] start_frame_id;
	input wire in_valid;
	output wire in_ready;
	input wire [(8 * CIN) - 1:0] in_data;
	input wire in_last;
	output wire out_valid;
	input wire out_ready;
	output wire [(8 * COUT) - 1:0] out_data;
	output wire [31:0] out_frame_id;
	output wire [15:0] out_y;
	output wire [15:0] out_x;
	output wire out_last;
	output wire frame_error;
	wire f_valid;
	wire f_ready;
	wire f_last;
	wire [(8 * CIN) - 1:0] f_data;
	generate
		if (FIFO_DEPTH > 0) begin : row_fifo
			p2_fifo #(
				.WIDTH((8 * CIN) + 1),
				.DEPTH(FIFO_DEPTH)
			) fifo(
				.clk(clk),
				.rst(rst),
				.in_valid(in_valid),
				.in_ready(in_ready),
				.in_data({in_last, in_data}),
				.out_valid(f_valid),
				.out_ready(f_ready),
				.out_data({f_last, f_data})
			);
		end
		else begin : direct
			assign f_valid = in_valid;
			assign in_ready = f_ready;
			assign f_data = in_data;
			assign f_last = in_last;
		end
	endgenerate
	wire window_valid;
	wire window_ready;
	wire window_last;
	wire [1:0] window_rows_ok;
	wire [71:0] window_taps;
	localparam integer RCW = ((CIN / PAGES) > 1 ? $clog2(CIN / PAGES) : 1);
	wire [RCW - 1:0] window_rd_ch;
	wire [(((8 * CIN) * KERNEL) * KERNEL) - 1:0] window_data;
	wire [31:0] window_frame_id;
	wire [15:0] window_y;
	wire [15:0] window_x;
	generate
		if ((KERNEL == 3) && CS) begin : serial
			p2_window_cs #(
				.H(H),
				.W(W),
				.CIN(CIN),
				.STRIDE(STRIDE)
			) window(
				.clk(clk),
				.rst(rst),
				.start_valid(start_valid),
				.start_ready(start_ready),
				.start_frame_id(start_frame_id),
				.in_valid(f_valid),
				.in_ready(f_ready),
				.in_data(f_data),
				.in_last(f_last),
				.win_valid(window_valid),
				.win_release(window_ready),
				.rd_ch(window_rd_ch),
				.tap_data(window_taps),
				.out_y(window_y),
				.out_x(window_x),
				.out_frame_id(window_frame_id),
				.out_last(window_last),
				.frame_error(frame_error)
			);
			assign window_data = 0;
			assign window_rows_ok = 2'b11;
		end
		else if (KERNEL == 3) begin : spatial
			p2_window3x3 #(
				.H(H),
				.W(W),
				.CIN(CIN),
				.STRIDE(STRIDE)
			) window(
				.clk(clk),
				.rst(rst),
				.start_valid(start_valid),
				.start_ready(start_ready),
				.start_frame_id(start_frame_id),
				.in_valid(f_valid),
				.in_ready(f_ready),
				.in_data(f_data),
				.in_last(f_last),
				.out_valid(window_valid),
				.out_ready(window_ready),
				.out_window(window_data),
				.out_y(window_y),
				.out_x(window_x),
				.out_frame_id(window_frame_id),
				.out_last(window_last),
				.out_rows_ok(window_rows_ok),
				.busy(),
				.frame_error(frame_error)
			);
			assign window_taps = 0;
		end
		else begin : pointwise
			reg active;
			reg held;
			reg held_last;
			reg error;
			reg [15:0] x;
			reg [15:0] y;
			reg [15:0] hx;
			reg [15:0] hy;
			reg [31:0] frame;
			reg [(8 * CIN) - 1:0] held_data;
			wire room = !held || window_ready;
			assign start_ready = (!rst && !active) && !held;
			assign f_ready = (!rst && active) && room;
			assign window_valid = held;
			assign window_data = held_data;
			assign window_frame_id = frame;
			assign window_x = hx;
			assign window_y = hy;
			assign window_last = held_last;
			assign window_rows_ok = 2'b11;
			assign window_taps = 0;
			assign frame_error = error;
			always @(posedge clk)
				if (rst) begin
					active <= 0;
					held <= 0;
					held_last <= 0;
					error <= 0;
					x <= 0;
					y <= 0;
					hx <= 0;
					hy <= 0;
					frame <= 0;
					held_data <= 0;
				end
				else begin
					if (held && window_ready)
						held <= 0;
					if (start_valid && start_ready) begin
						active <= 1;
						x <= 0;
						y <= 0;
						frame <= start_frame_id;
						error <= 0;
					end
					if (f_valid && f_ready) begin
						held <= 1;
						held_data <= f_data;
						hx <= x;
						hy <= y;
						held_last <= f_last;
						if (f_last != ((x == (W - 1)) && (y == (H - 1)))) begin
							active <= 0;
							error <= 1;
						end
						else if (f_last)
							active <= 0;
						if (x == (W - 1)) begin
							x <= 0;
							y <= y + 1'b1;
						end
						else
							x <= x + 1'b1;
					end
				end
		end
	endgenerate
	p2_systolic #(
		.CIN(CIN),
		.COUT(COUT),
		.TAPS(KERNEL * KERNEL),
		.PAGES(PAGES),
		.COLS(COLS),
		.SHIFT(SHIFT),
		.RELU(RELU),
		.USE_DSP_PE(USE_DSP_PE),
		.WEIGHT_FILE(WEIGHT_FILE),
		.WEIGHT_FILE1(WEIGHT_FILE1),
		.WEIGHT_FILE2(WEIGHT_FILE2),
		.WEIGHT_FILE3(WEIGHT_FILE3),
		.BIAS_VEC(BIAS_VEC),
		.CS(CS)
	) dot(
		.clk(clk),
		.rst(rst),
		.in_valid(window_valid),
		.in_ready(window_ready),
		.in_window(window_data),
		.in_rows_ok(window_rows_ok),
		.in_taps(window_taps[((8 * KERNEL) * KERNEL) - 1:0]),
		.rd_ch(window_rd_ch),
		.in_frame_id(window_frame_id),
		.in_y(window_y),
		.in_x(window_x),
		.in_last(window_last),
		.out_valid(out_valid),
		.out_ready(out_ready),
		.out_data(out_data),
		.out_frame_id(out_frame_id),
		.out_y(out_y),
		.out_x(out_x),
		.out_last(out_last)
	);
endmodule
module p2_net_det (
	clk,
	rst,
	start_valid,
	start_ready,
	start_frame_id,
	in_valid,
	in_ready,
	in_data,
	in_last,
	heat_valid,
	heat_last,
	heat_ready,
	heat_data,
	heat_y,
	heat_x,
	heat_frame_id,
	other_valid,
	other_last,
	other_ready,
	other_data,
	other_y,
	other_x,
	other_frame_id,
	error
);
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [31:0] start_frame_id;
	input wire in_valid;
	output wire in_ready;
	input wire [23:0] in_data;
	input wire in_last;
	output wire heat_valid;
	output wire heat_last;
	input wire heat_ready;
	output wire [7:0] heat_data;
	output wire [15:0] heat_y;
	output wire [15:0] heat_x;
	output wire [31:0] heat_frame_id;
	output wire other_valid;
	output wire other_last;
	input wire other_ready;
	output wire [31:0] other_data;
	output wire [15:0] other_y;
	output wire [15:0] other_x;
	output wire [31:0] other_frame_id;
	output wire error;
	wire v0;
	wire ready0;
	wire last0;
	wire start0;
	wire err0;
	wire [127:0] data0;
	wire [15:0] y0;
	wire [15:0] x0;
	wire [31:0] frame0;
	wire v1;
	wire ready1;
	wire last1;
	wire start1;
	wire err1;
	wire [255:0] data1;
	wire [15:0] y1;
	wire [15:0] x1;
	wire [31:0] frame1;
	wire v2;
	wire ready2;
	wire last2;
	wire start2;
	wire err2;
	wire [255:0] data2;
	wire [15:0] y2;
	wire [15:0] x2;
	wire [31:0] frame2;
	wire v3;
	wire ready3;
	wire last3;
	wire start3;
	wire err3;
	wire [511:0] data3;
	wire [15:0] y3;
	wire [15:0] x3;
	wire [31:0] frame3;
	wire v4;
	wire ready4;
	wire last4;
	wire start4;
	wire err4;
	wire [511:0] data4;
	wire [15:0] y4;
	wire [15:0] x4;
	wire [31:0] frame4;
	wire v5;
	wire ready5;
	wire last5;
	wire start5;
	wire err5;
	wire [511:0] data5;
	wire [15:0] y5;
	wire [15:0] x5;
	wire [31:0] frame5;
	wire v6;
	wire ready6;
	wire last6;
	wire start6;
	wire err6;
	wire [511:0] data6;
	wire [15:0] y6;
	wire [15:0] x6;
	wire [31:0] frame6;
	wire v7;
	wire ready7;
	wire last7;
	wire start7;
	wire err7;
	wire [511:0] data7;
	wire [15:0] y7;
	wire [15:0] x7;
	wire [31:0] frame7;
	wire v8;
	wire ready8;
	wire last8;
	wire start8;
	wire err8;
	wire [511:0] data8;
	wire [15:0] y8;
	wire [15:0] x8;
	wire [31:0] frame8;
	wire v9;
	wire ready9;
	wire last9;
	wire start9;
	wire err9;
	wire [7:0] data9;
	wire [15:0] y9;
	wire [15:0] x9;
	wire [31:0] frame9;
	wire v10;
	wire ready10;
	wire last10;
	wire start10;
	wire err10;
	wire [31:0] data10;
	wire [15:0] y10;
	wire [15:0] x10;
	wire [31:0] frame10;
	// R81: per-layer start queues (two frames in flight); was the AND of start0/start1/start2/start3/start4/start5/start6/start7/start8/start9/start10.
	wire qs0_valid;
	wire qs0_full;
	wire qs0_empty;
	wire [31:0] qs0_id;
	wire qs1_valid;
	wire qs1_full;
	wire qs1_empty;
	wire [31:0] qs1_id;
	wire qs2_valid;
	wire qs2_full;
	wire qs2_empty;
	wire [31:0] qs2_id;
	wire qs3_valid;
	wire qs3_full;
	wire qs3_empty;
	wire [31:0] qs3_id;
	wire qs4_valid;
	wire qs4_full;
	wire qs4_empty;
	wire [31:0] qs4_id;
	wire qs5_valid;
	wire qs5_full;
	wire qs5_empty;
	wire [31:0] qs5_id;
	wire qs6_valid;
	wire qs6_full;
	wire qs6_empty;
	wire [31:0] qs6_id;
	wire qs7_valid;
	wire qs7_full;
	wire qs7_empty;
	wire [31:0] qs7_id;
	wire qs8_valid;
	wire qs8_full;
	wire qs8_empty;
	wire [31:0] qs8_id;
	wire qs9_valid;
	wire qs9_full;
	wire qs9_empty;
	wire [31:0] qs9_id;
	wire qs10_valid;
	wire qs10_full;
	wire qs10_empty;
	wire [31:0] qs10_id;
	assign start_ready = !(qs0_full | qs1_full | qs2_full | qs3_full | qs4_full | qs5_full | qs6_full | qs7_full | qs8_full | qs9_full | qs10_full) && qs0_empty && start0;
	wire start_fire = start_valid && start_ready;
	p2_start_q q0(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs0_full),
		.empty(qs0_empty), .start_valid(qs0_valid), .start_ready(start0), .start_id(qs0_id));
	p2_start_q q1(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs1_full),
		.empty(qs1_empty), .start_valid(qs1_valid), .start_ready(start1), .start_id(qs1_id));
	p2_start_q q2(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs2_full),
		.empty(qs2_empty), .start_valid(qs2_valid), .start_ready(start2), .start_id(qs2_id));
	p2_start_q q3(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs3_full),
		.empty(qs3_empty), .start_valid(qs3_valid), .start_ready(start3), .start_id(qs3_id));
	p2_start_q q4(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs4_full),
		.empty(qs4_empty), .start_valid(qs4_valid), .start_ready(start4), .start_id(qs4_id));
	p2_start_q q5(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs5_full),
		.empty(qs5_empty), .start_valid(qs5_valid), .start_ready(start5), .start_id(qs5_id));
	p2_start_q q6(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs6_full),
		.empty(qs6_empty), .start_valid(qs6_valid), .start_ready(start6), .start_id(qs6_id));
	p2_start_q q7(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs7_full),
		.empty(qs7_empty), .start_valid(qs7_valid), .start_ready(start7), .start_id(qs7_id));
	p2_start_q q8(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs8_full),
		.empty(qs8_empty), .start_valid(qs8_valid), .start_ready(start8), .start_id(qs8_id));
	p2_start_q q9(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs9_full),
		.empty(qs9_empty), .start_valid(qs9_valid), .start_ready(start9), .start_id(qs9_id));
	p2_start_q q10(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs10_full),
		.empty(qs10_empty), .start_valid(qs10_valid), .start_ready(start10), .start_id(qs10_id));
	assign in_ready = ready0;
	p2_layer #(
		.H(96),
		.W(160),
		.CIN(3),
		.COUT(16),
		.KERNEL(3),
		.STRIDE(2),
		.PAGES(1),
		.COLS(1),
		.SHIFT(9),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer0/weights.mem"),
		.BIAS_VEC(512'h5defffffdd500000cd800000d6600001d440000101c00001adc00000e7c0000134a00000f5f0000214d00000ffa00001242000014fa000013cc00001351)
	) layer0(
		.clk(clk),
		.rst(rst),
		.start_valid(qs0_valid),
		.start_ready(start0),
		.start_frame_id(qs0_id),
		.in_valid(in_valid),
		.in_ready(ready0),
		.in_data(in_data),
		.in_last(in_last),
		.out_valid(v0),
		.out_ready(ready1),
		.out_data(data0),
		.out_frame_id(frame0),
		.out_y(y0),
		.out_x(x0),
		.out_last(last0),
		.frame_error(err0)
	);
	p2_layer #(
		.H(48),
		.W(80),
		.CIN(16),
		.COUT(32),
		.KERNEL(3),
		.STRIDE(2),
		.PAGES(1),
		.COLS(1),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(80),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer1/weights.mem"),
		.BIAS_VEC(1024'hfffffe66fffffe6d00000ff200000a4600000ca300000183000003d2000003ee0000037f00000026000012d1000009dc00000416000000abfffff0c4000007d400000449000001980000004200000493ffffff7300000e0b00000b33000001a1000005c6000002c9000003de0000008f000001830000011b0000054100000463)
	) layer1(
		.clk(clk),
		.rst(rst),
		.start_valid(qs1_valid),
		.start_ready(start1),
		.start_frame_id(qs1_id),
		.in_valid(v0),
		.in_ready(ready1),
		.in_data(data0),
		.in_last(last0),
		.out_valid(v1),
		.out_ready(ready2),
		.out_data(data1),
		.out_frame_id(frame1),
		.out_y(y1),
		.out_x(x1),
		.out_last(last1),
		.frame_error(err1)
	);
	p2_layer #(
		.H(24),
		.W(40),
		.CIN(32),
		.COUT(32),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(1),
		.SHIFT(6),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer2/weights.mem"),
		.BIAS_VEC(1024'hcc4fffffdcf0000084f000002810000013900000ac70000068700000299fffffd9d0000035a0000005100000b1700000070000006d8ffffff83000004bb00000945fffffcfafffffeb100000329ffffff99ffffff2a0000030e000007310000019b000001b4fffffd26000001b10000084c000000830000061a000004d3)
	) layer2(
		.clk(clk),
		.rst(rst),
		.start_valid(qs2_valid),
		.start_ready(start2),
		.start_frame_id(qs2_id),
		.in_valid(v1),
		.in_ready(ready2),
		.in_data(data1),
		.in_last(last1),
		.out_valid(v2),
		.out_ready(ready3),
		.out_data(data2),
		.out_frame_id(frame2),
		.out_y(y2),
		.out_x(x2),
		.out_last(last2),
		.frame_error(err2)
	);
	p2_layer #(
		.H(24),
		.W(40),
		.CIN(32),
		.COUT(64),
		.KERNEL(3),
		.STRIDE(2),
		.PAGES(1),
		.COLS(1),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(40),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer3/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer3/weights_t1.mem"),
		.BIAS_VEC(2048'hfffff62e00000065000007aafffffe6900000eb9fffffa0800000cfeffffff3400000ae800001002000013c4000028e7000015fbfffffba5ffffe9cc0000163000000ce8000007a10000119f00000aa0fffffa50000014f20000390dffffe460ffffff26000010d500000ae100000c50fffffe45000004640000098c00000e49fffff5e900000b2b000006b70000032100000c96000015bc00000ed4000007000000003c000023e6000008bf00000b430000028d000002860000092f00000024fffffc8b0000156b0000053100001e8600000914000001a700000061000001ed0000154200000c1ffffff98f0000198c0000111bfffff6b8000002b000000dc4)
	) layer3(
		.clk(clk),
		.rst(rst),
		.start_valid(qs3_valid),
		.start_ready(start3),
		.start_frame_id(qs3_id),
		.in_valid(v2),
		.in_ready(ready3),
		.in_data(data2),
		.in_last(last2),
		.out_valid(v3),
		.out_ready(ready4),
		.out_data(data3),
		.out_frame_id(frame3),
		.out_y(y3),
		.out_x(x3),
		.out_last(last3),
		.frame_error(err3)
	);
	p2_layer #(
		.H(12),
		.W(20),
		.CIN(64),
		.COUT(64),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(1),
		.SHIFT(8),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer4/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer4/weights_t1.mem"),
		.WEIGHT_FILE2("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer4/weights_t2.mem"),
		.WEIGHT_FILE3("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer4/weights_t3.mem"),
		.BIAS_VEC(2048'h1085000014710000152c000030e2fffff4e1ffffff7400001c2ffffffe1100000812ffffffca000026abffffd13e000027d10000185500000ca5000009e3000002d30000176600002d5e00000cad0000121b000001da0000008c00000b1f0000093dfffff8c800002379000039c8000000d50000003800000cc5000011ba0000247500000b6300001e710000052700000f2a00000cb1fffff0a300002d06000019d4fffff705fffffb1f000029a90000025c00001bb20000231400002d76000006f3000006de0000244100001be20000242e000019aa00002ea400001a4600000d84000004e2000007f3000012220000188b00001ea8000003d3000019aa)
	) layer4(
		.clk(clk),
		.rst(rst),
		.start_valid(qs4_valid),
		.start_ready(start4),
		.start_frame_id(qs4_id),
		.in_valid(v3),
		.in_ready(ready4),
		.in_data(data3),
		.in_last(last3),
		.out_valid(v4),
		.out_ready(ready5),
		.out_data(data4),
		.out_frame_id(frame4),
		.out_y(y4),
		.out_x(x4),
		.out_last(last4),
		.frame_error(err4)
	);
	p2_layer #(
		.H(12),
		.W(20),
		.CIN(64),
		.COUT(64),
		.KERNEL(3),
		.STRIDE(2),
		.PAGES(1),
		.COLS(1),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(20),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer5/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer5/weights_t1.mem"),
		.WEIGHT_FILE2("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer5/weights_t2.mem"),
		.WEIGHT_FILE3("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer5/weights_t3.mem"),
		.BIAS_VEC(2048'h1047fffff2550000035ffffff938000005fafffff98600000da400000331000002e600000ce5000012f3000009050000137900000eaa00002058000009ae000019fb00001f7e0000045e0000108ffffff3fbfffffdbc000005cbfffff9810000192c00000eae00000b01fffff33d00001719000002f80000046500001554000000b600000c650000042800000d3f00000a710000138600000775000016b6fffff49f0000099500000467fffffe9c0000149f000010e9000008b200000baa0000162700000d4e00000c5600000e3200000b05000002020000153f00000fc2fffffd8b0000082400001045000005000000025d0000147d000019610000095d)
	) layer5(
		.clk(clk),
		.rst(rst),
		.start_valid(qs5_valid),
		.start_ready(start5),
		.start_frame_id(qs5_id),
		.in_valid(v4),
		.in_ready(ready5),
		.in_data(data4),
		.in_last(last4),
		.out_valid(v5),
		.out_ready(ready6),
		.out_data(data5),
		.out_frame_id(frame5),
		.out_y(y5),
		.out_x(x5),
		.out_last(last5),
		.frame_error(err5)
	);
	p2_layer #(
		.H(6),
		.W(10),
		.CIN(64),
		.COUT(64),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(2),
		.SHIFT(8),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer6/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer6/weights_t1.mem"),
		.BIAS_VEC(2048'hfffff55e000010680000111600000bcd00000579fffff485000010e9ffffec740000158bfffff2420000100a00001e5b00001bf1fffff9d400002775000020b000001f250000005d00001d5a00001f7400000c5800001cbdffffcefefffff48c00001a3800001ccd0000168e00001be800001a8f000021b500000695000016ae00002136000013ff00000cbbfffffcbe00003183fffff3b600001be700001a5600001cf700000baa00000b94fffffc660000140b00001fb80000199000001e430000285300001cb9000013290000126100001e0400000dc000003b5c000030e20000235c000008adffffeab20000029400000552ffffeac000000d350000379a)
	) layer6(
		.clk(clk),
		.rst(rst),
		.start_valid(qs6_valid),
		.start_ready(start6),
		.start_frame_id(qs6_id),
		.in_valid(v5),
		.in_ready(ready6),
		.in_data(data5),
		.in_last(last5),
		.out_valid(v6),
		.out_ready(ready7),
		.out_data(data6),
		.out_frame_id(frame6),
		.out_y(y6),
		.out_x(x6),
		.out_last(last6),
		.frame_error(err6)
	);
	p2_layer #(
		.H(6),
		.W(10),
		.CIN(64),
		.COUT(64),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(2),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer7/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer7/weights_t1.mem"),
		.BIAS_VEC(2048'hffffedfd00000f02000013f500000f3400000473000005b10000056800000c0200000c2200000a7c0000069a0000042400000ac0000000f9000002e000000ce300001e5100000594000011a700001042000003eb00000ac5ffffe98e00000d690000108000000b110000084800000f470000059b00000b910000187b00000a37fffff507000008bb000011fb0000150f0000045b000002810000117800000582000011b900000be3fffffec000000ce500000ff000000dee00000c5800000ca000000e750000122a000011ec00000173000015f5000008aa00000888000010dbffffe8d2000010c90000144efffffca70000091b0000028d00000a0200000cbb)
	) layer7(
		.clk(clk),
		.rst(rst),
		.start_valid(qs7_valid),
		.start_ready(start7),
		.start_frame_id(qs7_id),
		.in_valid(v6),
		.in_ready(ready7),
		.in_data(data6),
		.in_last(last6),
		.out_valid(v7),
		.out_ready(ready8),
		.out_data(data7),
		.out_frame_id(frame7),
		.out_y(y7),
		.out_x(x7),
		.out_last(last7),
		.frame_error(err7)
	);
	p2_layer #(
		.H(6),
		.W(10),
		.CIN(64),
		.COUT(64),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(2),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer8/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer8/weights_t1.mem"),
		.BIAS_VEC(2048'hb6f0000118a00000c0a000000c600000f43000015e800000b700000145400000df3000008a0ffffef16000007f60000111900001cb900000be8000005830000077500001a990000051c00000c1200000be80000103bfffffd2d0000085e000014ab000009fd00001040fffffcc200000b2900000b84ffffefd70000049700000ccd000015330000105b000008090000029c00000e9f00000a1e00000a3b00000e28fffff86cfffff86c000008cf000015e20000102700001779000015c00000059b0000091d0000134200000465fffff5de00000faf00001538fffff09effffd5810000119f0000034a000019e10000091100000df6fffff89500000e49)
	) layer8(
		.clk(clk),
		.rst(rst),
		.start_valid(qs8_valid),
		.start_ready(start8),
		.start_frame_id(qs8_id),
		.in_valid(v7),
		.in_ready(ready8),
		.in_data(data7),
		.in_last(last7),
		.out_valid(v8),
		.out_ready(ready9 & ready10),
		.out_data(data8),
		.out_frame_id(frame8),
		.out_y(y8),
		.out_x(x8),
		.out_last(last8),
		.frame_error(err8)
	);
	p2_layer #(
		.H(6),
		.W(10),
		.CIN(64),
		.COUT(1),
		.KERNEL(1),
		.STRIDE(1),
		.PAGES(1),
		.COLS(1),
		.SHIFT(9),
		.RELU(0),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer9/weights.mem"),
		.BIAS_VEC(32'hffffc5fe)
	) layer9(
		.clk(clk),
		.rst(rst),
		.start_valid(qs9_valid),
		.start_ready(start9),
		.start_frame_id(qs9_id),
		.in_valid(v8 && ready10),
		.in_ready(ready9),
		.in_data(data8),
		.in_last(last8),
		.out_valid(v9),
		.out_ready(heat_ready),
		.out_data(data9),
		.out_frame_id(frame9),
		.out_y(y9),
		.out_x(x9),
		.out_last(last9),
		.frame_error(err9)
	);
	p2_layer #(
		.H(6),
		.W(10),
		.CIN(64),
		.COUT(4),
		.KERNEL(1),
		.STRIDE(1),
		.PAGES(1),
		.COLS(1),
		.SHIFT(8),
		.RELU(0),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/det/layer10/weights.mem"),
		.BIAS_VEC(128'h000004db000007130000016500000092)
	) layer10(
		.clk(clk),
		.rst(rst),
		.start_valid(qs10_valid),
		.start_ready(start10),
		.start_frame_id(qs10_id),
		.in_valid(v8 && ready9),
		.in_ready(ready10),
		.in_data(data8),
		.in_last(last8),
		.out_valid(v10),
		.out_ready(other_ready),
		.out_data(data10),
		.out_frame_id(frame10),
		.out_y(y10),
		.out_x(x10),
		.out_last(last10),
		.frame_error(err10)
	);
	assign heat_valid = v9;
	assign heat_data = data9;
	assign heat_y = y9;
	assign heat_x = x9;
	assign heat_last = last9;
	assign heat_frame_id = frame9;
	assign other_valid = v10;
	assign other_data = data10;
	assign other_y = y10;
	assign other_x = x10;
	assign other_last = last10;
	assign other_frame_id = frame10;
	assign error = (((((((((err0 | err1) | err2) | err3) | err4) | err5) | err6) | err7) | err8) | err9) | err10;
endmodule
module p2_net_pose (
	clk,
	rst,
	start_valid,
	start_ready,
	start_frame_id,
	in_valid,
	in_ready,
	in_data,
	in_last,
	heat_valid,
	heat_last,
	heat_ready,
	heat_data,
	heat_y,
	heat_x,
	heat_frame_id,
	other_valid,
	other_last,
	other_ready,
	other_data,
	other_y,
	other_x,
	other_frame_id,
	error
);
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [31:0] start_frame_id;
	input wire in_valid;
	output wire in_ready;
	input wire [23:0] in_data;
	input wire in_last;
	output wire heat_valid;
	output wire heat_last;
	input wire heat_ready;
	output wire [95:0] heat_data;
	output wire [15:0] heat_y;
	output wire [15:0] heat_x;
	output wire [31:0] heat_frame_id;
	output wire other_valid;
	output wire other_last;
	input wire other_ready;
	output wire [191:0] other_data;
	output wire [15:0] other_y;
	output wire [15:0] other_x;
	output wire [31:0] other_frame_id;
	output wire error;
	wire v0;
	wire ready0;
	wire last0;
	wire start0;
	wire err0;
	wire [127:0] data0;
	wire [15:0] y0;
	wire [15:0] x0;
	wire [31:0] frame0;
	wire v1;
	wire ready1;
	wire last1;
	wire start1;
	wire err1;
	wire [255:0] data1;
	wire [15:0] y1;
	wire [15:0] x1;
	wire [31:0] frame1;
	wire v2;
	wire ready2;
	wire last2;
	wire start2;
	wire err2;
	wire [255:0] data2;
	wire [15:0] y2;
	wire [15:0] x2;
	wire [31:0] frame2;
	wire v3;
	wire ready3;
	wire last3;
	wire start3;
	wire err3;
	wire [255:0] data3;
	wire [15:0] y3;
	wire [15:0] x3;
	wire [31:0] frame3;
	wire v4;
	wire ready4;
	wire last4;
	wire start4;
	wire err4;
	wire [511:0] data4;
	wire [15:0] y4;
	wire [15:0] x4;
	wire [31:0] frame4;
	wire v5;
	wire ready5;
	wire last5;
	wire start5;
	wire err5;
	wire [511:0] data5;
	wire [15:0] y5;
	wire [15:0] x5;
	wire [31:0] frame5;
	wire v6;
	wire ready6;
	wire last6;
	wire start6;
	wire err6;
	wire [511:0] data6;
	wire [15:0] y6;
	wire [15:0] x6;
	wire [31:0] frame6;
	wire v7;
	wire ready7;
	wire last7;
	wire start7;
	wire err7;
	wire [767:0] data7;
	wire [15:0] y7;
	wire [15:0] x7;
	wire [31:0] frame7;
	wire v8;
	wire ready8;
	wire last8;
	wire start8;
	wire err8;
	wire [767:0] data8;
	wire [15:0] y8;
	wire [15:0] x8;
	wire [31:0] frame8;
	wire v9;
	wire ready9;
	wire last9;
	wire start9;
	wire err9;
	wire [767:0] data9;
	wire [15:0] y9;
	wire [15:0] x9;
	wire [31:0] frame9;
	wire v10;
	wire ready10;
	wire last10;
	wire start10;
	wire err10;
	wire [767:0] data10;
	wire [15:0] y10;
	wire [15:0] x10;
	wire [31:0] frame10;
	wire v11;
	wire ready11;
	wire last11;
	wire start11;
	wire err11;
	wire [767:0] data11;
	wire [15:0] y11;
	wire [15:0] x11;
	wire [31:0] frame11;
	wire v12;
	wire ready12;
	wire last12;
	wire start12;
	wire err12;
	wire [767:0] data12;
	wire [15:0] y12;
	wire [15:0] x12;
	wire [31:0] frame12;
	wire v13;
	wire ready13;
	wire last13;
	wire start13;
	wire err13;
	wire [95:0] data13;
	wire [15:0] y13;
	wire [15:0] x13;
	wire [31:0] frame13;
	wire v14;
	wire ready14;
	wire last14;
	wire start14;
	wire err14;
	wire [191:0] data14;
	wire [15:0] y14;
	wire [15:0] x14;
	wire [31:0] frame14;
	// R81: per-layer start queues (two frames in flight); was the AND of start0/start1/start2/start3/start4/start5/start6/start7/start8/start9/start10/start11/start12/start13/start14.
	wire qs0_valid;
	wire qs0_full;
	wire qs0_empty;
	wire [31:0] qs0_id;
	wire qs1_valid;
	wire qs1_full;
	wire qs1_empty;
	wire [31:0] qs1_id;
	wire qs2_valid;
	wire qs2_full;
	wire qs2_empty;
	wire [31:0] qs2_id;
	wire qs3_valid;
	wire qs3_full;
	wire qs3_empty;
	wire [31:0] qs3_id;
	wire qs4_valid;
	wire qs4_full;
	wire qs4_empty;
	wire [31:0] qs4_id;
	wire qs5_valid;
	wire qs5_full;
	wire qs5_empty;
	wire [31:0] qs5_id;
	wire qs6_valid;
	wire qs6_full;
	wire qs6_empty;
	wire [31:0] qs6_id;
	wire qs7_valid;
	wire qs7_full;
	wire qs7_empty;
	wire [31:0] qs7_id;
	wire qs8_valid;
	wire qs8_full;
	wire qs8_empty;
	wire [31:0] qs8_id;
	wire qs9_valid;
	wire qs9_full;
	wire qs9_empty;
	wire [31:0] qs9_id;
	wire qs10_valid;
	wire qs10_full;
	wire qs10_empty;
	wire [31:0] qs10_id;
	wire qs11_valid;
	wire qs11_full;
	wire qs11_empty;
	wire [31:0] qs11_id;
	wire qs12_valid;
	wire qs12_full;
	wire qs12_empty;
	wire [31:0] qs12_id;
	wire qs13_valid;
	wire qs13_full;
	wire qs13_empty;
	wire [31:0] qs13_id;
	wire qs14_valid;
	wire qs14_full;
	wire qs14_empty;
	wire [31:0] qs14_id;
	assign start_ready = !(qs0_full | qs1_full | qs2_full | qs3_full | qs4_full | qs5_full | qs6_full | qs7_full | qs8_full | qs9_full | qs10_full | qs11_full | qs12_full | qs13_full | qs14_full);
	wire start_fire = start_valid && start_ready;
	p2_start_q q0(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs0_full),
		.empty(qs0_empty), .start_valid(qs0_valid), .start_ready(start0), .start_id(qs0_id));
	p2_start_q q1(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs1_full),
		.empty(qs1_empty), .start_valid(qs1_valid), .start_ready(start1), .start_id(qs1_id));
	p2_start_q q2(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs2_full),
		.empty(qs2_empty), .start_valid(qs2_valid), .start_ready(start2), .start_id(qs2_id));
	p2_start_q q3(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs3_full),
		.empty(qs3_empty), .start_valid(qs3_valid), .start_ready(start3), .start_id(qs3_id));
	p2_start_q q4(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs4_full),
		.empty(qs4_empty), .start_valid(qs4_valid), .start_ready(start4), .start_id(qs4_id));
	p2_start_q q5(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs5_full),
		.empty(qs5_empty), .start_valid(qs5_valid), .start_ready(start5), .start_id(qs5_id));
	p2_start_q q6(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs6_full),
		.empty(qs6_empty), .start_valid(qs6_valid), .start_ready(start6), .start_id(qs6_id));
	p2_start_q q7(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs7_full),
		.empty(qs7_empty), .start_valid(qs7_valid), .start_ready(start7), .start_id(qs7_id));
	p2_start_q q8(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs8_full),
		.empty(qs8_empty), .start_valid(qs8_valid), .start_ready(start8), .start_id(qs8_id));
	p2_start_q q9(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs9_full),
		.empty(qs9_empty), .start_valid(qs9_valid), .start_ready(start9), .start_id(qs9_id));
	p2_start_q q10(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs10_full),
		.empty(qs10_empty), .start_valid(qs10_valid), .start_ready(start10), .start_id(qs10_id));
	p2_start_q q11(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs11_full),
		.empty(qs11_empty), .start_valid(qs11_valid), .start_ready(start11), .start_id(qs11_id));
	p2_start_q q12(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs12_full),
		.empty(qs12_empty), .start_valid(qs12_valid), .start_ready(start12), .start_id(qs12_id));
	p2_start_q q13(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs13_full),
		.empty(qs13_empty), .start_valid(qs13_valid), .start_ready(start13), .start_id(qs13_id));
	p2_start_q q14(.clk(clk), .rst(rst), .push(start_fire), .push_id(start_frame_id), .full(qs14_full),
		.empty(qs14_empty), .start_valid(qs14_valid), .start_ready(start14), .start_id(qs14_id));
	assign in_ready = ready0;
	p2_layer #(
		.H(288),
		.W(192),
		.CIN(3),
		.COUT(16),
		.KERNEL(3),
		.STRIDE(2),
		.PAGES(1),
		.COLS(1),
		.SHIFT(9),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer0/weights.mem"),
		.BIAS_VEC(512'h1a66000012310000257800001069000007e7000015fa0000048900000b8b00000a91000019a7000010f5ffff8956000000c30000126100001c9d00001273)
	) layer0(
		.clk(clk),
		.rst(rst),
		.start_valid(qs0_valid),
		.start_ready(start0),
		.start_frame_id(qs0_id),
		.in_valid(in_valid),
		.in_ready(ready0),
		.in_data(in_data),
		.in_last(in_last),
		.out_valid(v0),
		.out_ready(ready1),
		.out_data(data0),
		.out_frame_id(frame0),
		.out_y(y0),
		.out_x(x0),
		.out_last(last0),
		.frame_error(err0)
	);
	p2_layer #(
		.H(144),
		.W(96),
		.CIN(16),
		.COUT(32),
		.KERNEL(3),
		.STRIDE(2),
		.PAGES(1),
		.COLS(2),
		.SHIFT(6),
		.RELU(1),
		.FIFO_DEPTH(96),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer1/weights.mem"),
		.BIAS_VEC(1024'h15c000001f2000003510000003c000002b600000212000000fd000008af00000836000009c60000018c000004160000033cfffffcb9000000bd000001280000001c000000c500000061ffffff9bfffff15300000d5f000000f2000000c10000011c000004ac000004ee000003c0000000ea00000661000000c7000008ea)
	) layer1(
		.clk(clk),
		.rst(rst),
		.start_valid(qs1_valid),
		.start_ready(start1),
		.start_frame_id(qs1_id),
		.in_valid(v0),
		.in_ready(ready1),
		.in_data(data0),
		.in_last(last0),
		.out_valid(v1),
		.out_ready(ready2),
		.out_data(data1),
		.out_frame_id(frame1),
		.out_y(y1),
		.out_x(x1),
		.out_last(last1),
		.frame_error(err1)
	);
	p2_layer #(
		.H(72),
		.W(48),
		.CIN(32),
		.COUT(32),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(4),
		.SHIFT(5),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer2/weights.mem"),
		.BIAS_VEC(1024'h57300000324000003d800000675000004a4000000fe00000763000006f70000043e0000055600000529000000d80000012e0000033a000003d6000003c1000000ae00000581000000f20000055300000308000002fb0000042d000007c0000003bf00000600000000a4ffffff6c000004f9000006c0000003cffffffb95)
	) layer2(
		.clk(clk),
		.rst(rst),
		.start_valid(qs2_valid),
		.start_ready(start2),
		.start_frame_id(qs2_id),
		.in_valid(v1),
		.in_ready(ready2),
		.in_data(data1),
		.in_last(last1),
		.out_valid(v2),
		.out_ready(ready3),
		.out_data(data2),
		.out_frame_id(frame2),
		.out_y(y2),
		.out_x(x2),
		.out_last(last2),
		.frame_error(err2)
	);
	p2_layer #(
		.H(72),
		.W(48),
		.CIN(32),
		.COUT(32),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(4),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer3/weights.mem"),
		.BIAS_VEC(1024'ha9cfffffc8900000a62000003af00001c3d000012410000254a00001a57000011d000001c3400002db7000005140000122700000f52000022cc000043f8000000ab00000c77000007dc000006be0000060b000005bbfffffc2d000002cf0000022d000009ee000009fb0000111a00000c79fffff93d0000103a00000d4c)
	) layer3(
		.clk(clk),
		.rst(rst),
		.start_valid(qs3_valid),
		.start_ready(start3),
		.start_frame_id(qs3_id),
		.in_valid(v2),
		.in_ready(ready3),
		.in_data(data2),
		.in_last(last2),
		.out_valid(v3),
		.out_ready(ready4),
		.out_data(data3),
		.out_frame_id(frame3),
		.out_y(y3),
		.out_x(x3),
		.out_last(last3),
		.frame_error(err3)
	);
	p2_layer #(
		.H(72),
		.W(48),
		.CIN(32),
		.COUT(64),
		.KERNEL(3),
		.STRIDE(2),
		.PAGES(1),
		.COLS(2),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(48),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer4/weights.mem"),
		.BIAS_VEC(2048'hfffffb00fffff94200001375ffffedc0fffffc73fffff58300000c1e00001a69ffffe7010000102fffffffbcffffff0cfffff63e00000082ffffec57ffffdb61ffffeb2bfffff21afffff7f5000000a5fffff02efffff3cd0000109600000607fffff4effffffea5000002e5fffff216fffff50f0000053900001a10ffffee8300002bdbffffe5b60000211100000197000003230000225e00002d58fffffe3900000bf4ffffffc100000b0f000013a20000071d00000eaf00000128ffffef7f000002c7fffffdc5ffffe5ddffffff49fffff908fffff73efffffc810000145700003c130000004dfffff36400000a4afffff3ba00000cca00000afd00000103)
	) layer4(
		.clk(clk),
		.rst(rst),
		.start_valid(qs4_valid),
		.start_ready(start4),
		.start_frame_id(qs4_id),
		.in_valid(v3),
		.in_ready(ready4),
		.in_data(data3),
		.in_last(last3),
		.out_valid(v4),
		.out_ready(ready5),
		.out_data(data4),
		.out_frame_id(frame4),
		.out_y(y4),
		.out_x(x4),
		.out_last(last4),
		.frame_error(err4)
	);
	p2_layer #(
		.H(36),
		.W(24),
		.CIN(64),
		.COUT(64),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(4),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer5/weights.mem"),
		.BIAS_VEC(2048'h17d000000237000009aa00000c750000091b000011f600000d96000000660000005000000789000020e700000e39000009f0000005fa000006d600000cba00000a16000010a300000f190000129dfffff5490000086100000a2bfffffee30000170600000793ffffd3f9000011de000003f8000013fb00000bd40000065f000004b7ffffffef00001156fffffd8a00001255fffff94b00000d510000029afffff5f0fffffdf4000011ac0000085700001cb300003e0700001308fffffb450000094000001cb700002062ffffffbb0000152b00000410000002e00000237a00001f7400001af4ffffff90fffff95200000684fffff0930000120b00000e19)
	) layer5(
		.clk(clk),
		.rst(rst),
		.start_valid(qs5_valid),
		.start_ready(start5),
		.start_frame_id(qs5_id),
		.in_valid(v4),
		.in_ready(ready5),
		.in_data(data4),
		.in_last(last4),
		.out_valid(v5),
		.out_ready(ready6),
		.out_data(data5),
		.out_frame_id(frame5),
		.out_y(y5),
		.out_x(x5),
		.out_last(last5),
		.frame_error(err5)
	);
	p2_layer #(
		.H(36),
		.W(24),
		.CIN(64),
		.COUT(64),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(4),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer6/weights.mem"),
		.BIAS_VEC(2048'hfffff4da00001aa800000730fffff7f30000038b000018e00000130e0000101300000ca90000146800000a390000079f00000704000001980000000100000f0b00000f96ffffec2f00001043000005a5000004f90000071afffff93efffffe2300000735000001f30000117300000dfa000007d600000eba0000014afffffc7300000418000006210000053300001247000003010000113a0000067800000601fffffcc300000c05000012d6fffff92700000eef0000123400000e82000002af00000b4cffffffd9fffff8e800000bb1fffffcbc00000116000006680000068700001a7500001550000017fcffffffa5000012e1fffffc3600000f83fffff3c0)
	) layer6(
		.clk(clk),
		.rst(rst),
		.start_valid(qs6_valid),
		.start_ready(start6),
		.start_frame_id(qs6_id),
		.in_valid(v5),
		.in_ready(ready6),
		.in_data(data5),
		.in_last(last5),
		.out_valid(v6),
		.out_ready(ready7),
		.out_data(data6),
		.out_frame_id(frame6),
		.out_y(y6),
		.out_x(x6),
		.out_last(last6),
		.frame_error(err6)
	);
	p2_layer #(
		.H(36),
		.W(24),
		.CIN(64),
		.COUT(96),
		.KERNEL(3),
		.STRIDE(2),
		.PAGES(1),
		.COLS(4),
		.SHIFT(8),
		.RELU(1),
		.FIFO_DEPTH(24),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer7/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer7/weights_t1.mem"),
		.BIAS_VEC(3072'h24650000196b00002ff40000254f00004a160000291c000013f700002155ffffd468000034e300001e3600004cc6ffffd8f3000055900000476a0000295f0000272e00003e77fffffe6c00002b28000040ffffffbb6c000036f500003a760000264700002ae900002c9800002a41000023d8fffff334000035dc00002499ffffa40bffffe91b00005e2c0000541c00001fed0000192200002da3000050eb00000eb20000505700000fb6000021740000367700001fb00000282d00001ac4ffff9afa000062edffffee6f000006fa000029330000051f000023a300003f090000486d0000314300003dc0fffffee3000025bf00003a69000014be000021f1ffffebef00001cac00000b2200001fabfffffd6bffffff97000007f30000219f00001062000021c40000190d000029e40000275e000016b000000bc1fffff4a90000038900002aeb000025bb000031410000220400005280ffffec690000122c000010880000274f00003bcd000015cb00003bcd000027050000137a00003266)
	) layer7(
		.clk(clk),
		.rst(rst),
		.start_valid(qs7_valid),
		.start_ready(start7),
		.start_frame_id(qs7_id),
		.in_valid(v6),
		.in_ready(ready7),
		.in_data(data6),
		.in_last(last6),
		.out_valid(v7),
		.out_ready(ready8),
		.out_data(data7),
		.out_frame_id(frame7),
		.out_y(y7),
		.out_x(x7),
		.out_last(last7),
		.frame_error(err7)
	);
	p2_layer #(
		.H(18),
		.W(12),
		.CIN(96),
		.COUT(96),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(4),
		.SHIFT(8),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer8/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer8/weights_t1.mem"),
		.WEIGHT_FILE2("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer8/weights_t2.mem"),
		.BIAS_VEC(3072'h35fe000021c100000e72fffff84100001b3000000add00001a75fffff070fffffac800001cd200002029fffff91d00000ee5000015a8fffffa610000136fffffe6e200001eca000020f5000004210000033f00002da500001b9800002169000016410000160f0000098bfffff7f5fffff2140000050e00000b3c00000f29ffffdc52fffff1d8000028180000002c000012a8000013fffffff75a00001647000004f7000009ed00004da7fffff3a100001aeefffff5cd00001e28000004c60000071900001f1e00000dce00001fd200001598fffff73e00001c77ffffe795000030e9000009ed0000046c000015a800001a920000099300000b0f000006ba000006afffffe87200000ba3ffffedd4fffff9f1fffffe5500000d4affffd4a7ffffff79000009dd0000086f0000073f00000112fffff6d700000a4300000655000010b40000263a00002150000030e4fffff52e00002670fffff2f1000021900000148500000ad50000180affffed37000015ef00002529000005a100000970)
	) layer8(
		.clk(clk),
		.rst(rst),
		.start_valid(qs8_valid),
		.start_ready(start8),
		.start_frame_id(qs8_id),
		.in_valid(v7),
		.in_ready(ready8),
		.in_data(data7),
		.in_last(last7),
		.out_valid(v8),
		.out_ready(ready9),
		.out_data(data8),
		.out_frame_id(frame8),
		.out_y(y8),
		.out_x(x8),
		.out_last(last8),
		.frame_error(err8)
	);
	p2_layer #(
		.H(18),
		.W(12),
		.CIN(96),
		.COUT(96),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(4),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer9/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer9/weights_t1.mem"),
		.WEIGHT_FILE2("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer9/weights_t2.mem"),
		.BIAS_VEC(3072'h15ed0000044b000001220000064b0000007400000c5efffffc7800000b6d00000884000005d500000e01fffffffa000006080000135f000002e800000318fffffef600000c4d00000986fffff8e3000011ff000001cc00000d5e0000097e00000814000002c00000073100000ffe000008f4000007f30000157c00000e4800000adb00000da200000a43000006fb000011ca0000094bfffffe72000009ef000009d80000000a0000077000000ac2000006ad000004260000038e00000c3d00000da9ffffefa7fffff68f00000bdcffffd96000000d2000000dd5000002cd00000e23000008eb000001dd000000b800000af500000457000008ca00000a2100000a0e0000015300000f3a000006cd000000170000081900000950000006fc0000046200000dca000008d5fffffe2800000a0bfffffc8a00000580000012dc000008c30000092e000007ebffffca830000050d00000cc8ffffff0f00000de4000005d10000079bfffffd12000000fd00000e3c0000013600000944000003fc)
	) layer9(
		.clk(clk),
		.rst(rst),
		.start_valid(qs9_valid),
		.start_ready(start9),
		.start_frame_id(qs9_id),
		.in_valid(v8),
		.in_ready(ready9),
		.in_data(data8),
		.in_last(last8),
		.out_valid(v9),
		.out_ready(ready10),
		.out_data(data9),
		.out_frame_id(frame9),
		.out_y(y9),
		.out_x(x9),
		.out_last(last9),
		.frame_error(err9)
	);
	p2_layer #(
		.H(18),
		.W(12),
		.CIN(96),
		.COUT(96),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(4),
		.SHIFT(6),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer10/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer10/weights_t1.mem"),
		.WEIGHT_FILE2("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer10/weights_t2.mem"),
		.BIAS_VEC(3072'h28700000490000001da000001c0ffffeaaffffffffd000000580000008b00000209000000a600000509000004e4fffffec000000292000002ed0000032d000002b600000045000005be0000024e0000035effffffc80000022b000003040000000a0000042500000328000000e3000001b5000003d000000088000003e0fffffacd000001d10000007d00000084fffffe7a000002e000000576fffffe1b000003bc00000483fffffdac00000495000003c6000002d7000000aafffffec7fffffb8a000001fc000001f0000000f500000324fffffd640000017600000057000001cb000001c00000050e000004740000040d000000bffffff2e2fffff945fffffffdffffffc00000030d000006e8000003f200000247fffffe24fffffded000004ba00000478fffffb6dfffffd7f000005d50000053c000001c70000024dffffff0e000001e6fffffd90fffffe270000037100000287ffffffb800000624000000f8000001d000000615ffffff88ffffff63fffffc27fffffe400000024a)
	) layer10(
		.clk(clk),
		.rst(rst),
		.start_valid(qs10_valid),
		.start_ready(start10),
		.start_frame_id(qs10_id),
		.in_valid(v9),
		.in_ready(ready10),
		.in_data(data9),
		.in_last(last9),
		.out_valid(v10),
		.out_ready(ready11),
		.out_data(data10),
		.out_frame_id(frame10),
		.out_y(y10),
		.out_x(x10),
		.out_last(last10),
		.frame_error(err10)
	);
	p2_layer #(
		.H(18),
		.W(12),
		.CIN(96),
		.COUT(96),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(4),
		.SHIFT(7),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer11/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer11/weights_t1.mem"),
		.WEIGHT_FILE2("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer11/weights_t2.mem"),
		.BIAS_VEC(3072'h690fffffba600000a9a00000e8d0000061500000cb700000a71fffffd1000000e2700000092000008f900000a55000005f400000a1700000c5b0000018000000b9d0000077b00000bd90000095e00000e5a00000a0f000005a40000105200000b5d00000899000005ff0000093b000005f2000002580000057e00000367fffffc150000092800000be8000005510000099d000000d800000217000006d100000923000003bb00000c0e000007e400000ae70000022000000d8f00000d0a000003c10000075300000fdc000007ce000004fb0000093d000005550000093c00001432000009cf00000b1600000b9300000d54000009ed00000137000007a4000003720000023b00000d0e00000547000006bd00000e8a000008cb00000bd5000008ea000000a2000005790000079700000aca00000a3a0000061700000ae1000007a500000829000007ebfffffcca000010a4000005dd000005fb000001d4000006d3ffffffdf000003f500000be1000008d9000005d7000012d80000084b)
	) layer11(
		.clk(clk),
		.rst(rst),
		.start_valid(qs11_valid),
		.start_ready(start11),
		.start_frame_id(qs11_id),
		.in_valid(v10),
		.in_ready(ready11),
		.in_data(data10),
		.in_last(last10),
		.out_valid(v11),
		.out_ready(ready12),
		.out_data(data11),
		.out_frame_id(frame11),
		.out_y(y11),
		.out_x(x11),
		.out_last(last11),
		.frame_error(err11)
	);
	p2_layer #(
		.H(18),
		.W(12),
		.CIN(96),
		.COUT(96),
		.KERNEL(3),
		.STRIDE(1),
		.PAGES(1),
		.COLS(4),
		.SHIFT(6),
		.RELU(1),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer12/weights_t0.mem"),
		.WEIGHT_FILE1("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer12/weights_t1.mem"),
		.WEIGHT_FILE2("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer12/weights_t2.mem"),
		.BIAS_VEC(3072'h10990000162100000ddefffffdc100000ecbffffff5a00000e5c0000193a00000ea500000c52000012b2fffffcf20000115f000001880000071efffffc45000011a000000ca40000103e00000b9a000025e8000015a30000117500000bf200000ea8ffffff4800000d02000010fd0000026b000011c60000239a0000307500000f3b00000346000004030000198b00000dabfffffd910000021400000d050000125600000800000003f000000986000013d200000d1200000471000000c7fffffe0f000005920000159ffffff68f000021330000153a00000e5f0000018500000fd700001dc500001715000006d2fffffe1200000f07000017b30000096700000aea00000f7b000004eb00000edb000003b100000222000010b20000107500000f35000011eb000010920000160900000a12000011610000123800000f1700000d7e000000c8000014d0000010d7fffff89600000bba00000680000003710000162b000010420000003d00000eb200000a05000008c10000121600000428)
	) layer12(
		.clk(clk),
		.rst(rst),
		.start_valid(qs12_valid),
		.start_ready(start12),
		.start_frame_id(qs12_id),
		.in_valid(v11),
		.in_ready(ready12),
		.in_data(data11),
		.in_last(last11),
		.out_valid(v12),
		.out_ready(ready13 & ready14),
		.out_data(data12),
		.out_frame_id(frame12),
		.out_y(y12),
		.out_x(x12),
		.out_last(last12),
		.frame_error(err12)
	);
	p2_layer #(
		.H(18),
		.W(12),
		.CIN(96),
		.COUT(12),
		.KERNEL(1),
		.STRIDE(1),
		.PAGES(1),
		.COLS(2),
		.SHIFT(9),
		.RELU(0),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer13/weights.mem"),
		.BIAS_VEC(384'hffffca4fffffce06ffffd05cffffccc5ffffd4a3ffffd185ffffccbdffffcc1dffffcd9effffcc4dffffcbc3ffffcd69)
	) layer13(
		.clk(clk),
		.rst(rst),
		.start_valid(qs13_valid),
		.start_ready(start13),
		.start_frame_id(qs13_id),
		.in_valid(v12 && ready14),
		.in_ready(ready13),
		.in_data(data12),
		.in_last(last12),
		.out_valid(v13),
		.out_ready(heat_ready),
		.out_data(data13),
		.out_frame_id(frame13),
		.out_y(y13),
		.out_x(x13),
		.out_last(last13),
		.frame_error(err13)
	);
	p2_layer #(
		.H(18),
		.W(12),
		.CIN(96),
		.COUT(24),
		.KERNEL(1),
		.STRIDE(1),
		.PAGES(1),
		.COLS(3),
		.SHIFT(8),
		.RELU(0),
		.FIFO_DEPTH(0),
		.USE_DSP_PE("yes"),
		.WEIGHT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/resources/rom/pose/layer14/weights.mem"),
		.BIAS_VEC(768'hfffffebcffffff1cfffffef500000186fffffef400000058ffffff89000000560000003bffffff88fffffeda0000010f000001810000011100000029ffffff87fffffedeffffffd6000001bf00000172ffffff6affffff79000001530000012f)
	) layer14(
		.clk(clk),
		.rst(rst),
		.start_valid(qs14_valid),
		.start_ready(start14),
		.start_frame_id(qs14_id),
		.in_valid(v12 && ready13),
		.in_ready(ready14),
		.in_data(data12),
		.in_last(last12),
		.out_valid(v14),
		.out_ready(other_ready),
		.out_data(data14),
		.out_frame_id(frame14),
		.out_y(y14),
		.out_x(x14),
		.out_last(last14),
		.frame_error(err14)
	);
	assign heat_valid = v13;
	assign heat_data = data13;
	assign heat_y = y13;
	assign heat_x = x13;
	assign heat_last = last13;
	assign heat_frame_id = frame13;
	assign other_valid = v14;
	assign other_data = data14;
	assign other_y = y14;
	assign other_x = x14;
	assign other_last = last14;
	assign other_frame_id = frame14;
	assign error = (((((((((((((err0 | err1) | err2) | err3) | err4) | err5) | err6) | err7) | err8) | err9) | err10) | err11) | err12) | err13) | err14;
endmodule
module p2_cam_stream (
	cam_clk,
	cam_rst,
	cam_en,
	cam_vs,
	cam_data,
	clk,
	rst,
	pix_valid,
	pix,
	x,
	y,
	sof,
	eol,
	overflow
);
	parameter integer CAM_W = 1280;
	parameter integer CAM_H = 720;
	input wire cam_clk;
	input wire cam_rst;
	input wire cam_en;
	input wire cam_vs;
	input wire [15:0] cam_data;
	input wire clk;
	input wire rst;
	output reg pix_valid;
	output reg [15:0] pix;
	output reg [10:0] x;
	output reg [9:0] y;
	output reg sof;
	output reg eol;
	output reg overflow;
	reg vs_q;
	reg sof_pending;
	wire wfull;
	always @(posedge cam_clk)
		if (cam_rst) begin
			vs_q <= 0;
			sof_pending <= 0;
		end
		else begin
			vs_q <= cam_vs;
			if (cam_vs && !vs_q)
				sof_pending <= 1;
			else if (cam_en)
				sof_pending <= 0;
		end
	reg ovf_cam;
	always @(posedge cam_clk)
		if (cam_rst)
			ovf_cam <= 0;
		else if (cam_en && wfull)
			ovf_cam <= 1;
	wire rvalid;
	wire [16:0] rdata;
	p2_async_fifo #(
		.WIDTH(17),
		.AW(5)
	) fifo(
		.wclk(cam_clk),
		.wrst(cam_rst),
		.wvalid(cam_en),
		.wdata({sof_pending, cam_data}),
		.wfull(wfull),
		.rclk(clk),
		.rrst(rst),
		.rvalid(rvalid),
		.rready(1'b1),
		.rdata(rdata)
	);
	(* async_reg = "true" *) reg ovf_s1;
	(* async_reg = "true" *) reg ovf_s2;
	reg [10:0] nx;
	reg [9:0] ny;
	always @(posedge clk)
		if (rst) begin
			pix_valid <= 0;
			pix <= 0;
			x <= 0;
			y <= 0;
			sof <= 0;
			eol <= 0;
			nx <= 0;
			ny <= 0;
			ovf_s1 <= 0;
			ovf_s2 <= 0;
			overflow <= 0;
		end
		else begin
			ovf_s1 <= ovf_cam;
			ovf_s2 <= ovf_s1;
			overflow <= ovf_s2;
			pix_valid <= rvalid;
			sof <= rvalid && rdata[16];
			if (rvalid) begin
				pix <= rdata[15:0];
				if (rdata[16]) begin
					x <= 0;
					y <= 0;
					eol <= CAM_W == 1;
					nx <= 1;
					ny <= 0;
				end
				else begin
					x <= nx;
					y <= ny;
					eol <= nx == (CAM_W - 1);
					if (nx == (CAM_W - 1)) begin
						nx <= 0;
						ny <= ny + 1'b1;
					end
					else
						nx <= nx + 1'b1;
				end
			end
			else
				eol <= 0;
		end
endmodule
module p2_det_sampler (
	clk,
	rst,
	pix_valid,
	pix,
	x,
	y,
	sof,
	net_start_ready,
	net_start_valid,
	out_valid,
	out_ready,
	out_data,
	out_last,
	overflow,
	frame_short,
	busy
);
	parameter integer CAM_W = 1280;
	parameter integer CAM_H = 720;
	parameter integer OW = 160;
	parameter integer OH = 96;
	parameter integer TOP = 3;
	parameter integer STEP = 8;
	input wire clk;
	input wire rst;
	input wire pix_valid;
	input wire [15:0] pix;
	input wire [10:0] x;
	input wire [9:0] y;
	input wire sof;
	input wire net_start_ready;
	output wire net_start_valid;
	output wire out_valid;
	input wire out_ready;
	output wire [23:0] out_data;
	output wire out_last;
	output reg overflow;
	output reg frame_short;
	output wire busy;
	localparam integer REAL = OW * (CAM_H / STEP);
	localparam integer PAD = OW * TOP;
	localparam integer TOTAL = OW * OH;
	localparam IDLE = 0;
	localparam TOPPAD = 1;
	localparam MID = 2;
	localparam BOTPAD = 3;
	reg [1:0] state;
	reg sampling;
	reg fill;
	reg [15:0] count;
	assign busy = state != IDLE;
	assign net_start_valid = sof && (state == IDLE);
	wire admit = net_start_valid && net_start_ready;
	wire take = ((((pix_valid && (sampling || admit)) && (x < CAM_W)) && (y < CAM_H)) && (x[2:0] == 0)) && (y[2:0] == 0);
	wire f_in_ready;
	wire f_valid;
	wire [23:0] f_data;
	wire [23:0] rgb = {pix[4:0], 3'b000, pix[10:5], 2'b00, pix[15:11], 3'b000};
	p2_fifo #(
		.WIDTH(24),
		.DEPTH(256)
	) samples(
		.clk(clk),
		.rst(rst),
		.in_valid(take),
		.in_ready(f_in_ready),
		.in_data(rgb),
		.out_valid(f_valid),
		.out_ready((state == MID) && out_ready),
		.out_data(f_data)
	);
	assign out_valid = ((state == TOPPAD) || (state == BOTPAD)) || ((state == MID) && (f_valid || fill));
	assign out_data = ((state == MID) && f_valid ? f_data : 24'd0);
	assign out_last = count == (TOTAL - 1);
	wire fire = out_valid && out_ready;
	always @(posedge clk)
		if (rst) begin
			state <= IDLE;
			sampling <= 0;
			fill <= 0;
			count <= 0;
			overflow <= 0;
			frame_short <= 0;
		end
		else begin
			if (take && !f_in_ready)
				overflow <= 1;
			if (admit) begin
				state <= TOPPAD;
				sampling <= 1;
				fill <= 0;
				count <= 0;
			end
			else begin
				if (sof && (state != IDLE)) begin
					sampling <= 0;
					fill <= 1;
					frame_short <= 1;
				end
				if (fire) begin
					count <= count + 1'b1;
					if ((state == TOPPAD) && (count == (PAD - 1)))
						state <= MID;
					if ((state == MID) && (count == ((PAD + REAL) - 1))) begin
						state <= BOTPAD;
						sampling <= 0;
					end
					if ((state == BOTPAD) && (count == (TOTAL - 1))) begin
						state <= IDLE;
						fill <= 0;
					end
				end
			end
		end
endmodule
module p2_crop (
	clk,
	rst,
	pix_valid,
	pix,
	x,
	y,
	sof,
	eol,
	start,
	x0,
	y0,
	step,
	wr_valid,
	wr_addr,
	wr_data,
	rows_ready,
	busy,
	overrun,
	zr_valid,
	zr_row,
	zr_zero
);
	parameter integer CAM_W = 1280;
	parameter integer CAM_H = 720;
	parameter integer OW = 192;
	parameter integer OH = 288;
	input wire clk;
	input wire rst;
	input wire pix_valid;
	input wire [15:0] pix;
	input wire [10:0] x;
	input wire [9:0] y;
	input wire sof;
	input wire eol;
	input wire start;
	input wire signed [31:0] x0;
	input wire signed [31:0] y0;
	input wire [31:0] step;
	output reg wr_valid;
	output reg [15:0] wr_addr;
	output reg [23:0] wr_data;
	output reg [8:0] rows_ready;
	output wire busy;
	output reg overrun;
	output wire zr_valid;
	output wire [8:0] zr_row;
	output wire zr_zero;
	localparam integer HALF = CAM_W / 2;
	reg [10:0] rows_done;
	reg [9:0] cur_row;
	wire [9:0] addr_e;
	wire [9:0] addr_o;
	reg [15:0] q [0:7];
	genvar _gv_g_1;
	generate
		for (_gv_g_1 = 0; _gv_g_1 < 8; _gv_g_1 = _gv_g_1 + 1) begin : line_bank
			localparam g = _gv_g_1;
			reg [15:0] mem [0:HALF - 1];
			always @(posedge clk) begin
				if (((pix_valid && (x < CAM_W)) && (y < CAM_H)) && ({y[1:0], x[0]} == g))
					mem[x[10:1]] <= pix;
				q[g] <= mem[(g % 2 ? addr_o : addr_e)];
			end
		end
	endgenerate
	always @(posedge clk)
		if (rst) begin
			rows_done <= 0;
			cur_row <= 0;
		end
		else if (pix_valid) begin
			cur_row <= y;
			if (sof)
				rows_done <= (eol ? 1 : 0);
			else if (eol && (y < CAM_H))
				rows_done <= y + 1'b1;
		end
	localparam IDLE = 0;
	localparam WAITROW = 1;
	localparam RUN = 2;
	localparam FLUSH = 3;
	reg [1:0] state;
	reg [8:0] oy;
	reg [7:0] ox;
	reg signed [31:0] sy;
	reg signed [31:0] sx;
	reg signed [31:0] rx0;
	reg [31:0] rstep;
	reg frame_seen;
	assign busy = state != IDLE;
	wire signed [21:0] row0 = $signed(sy[31:16]);
	wire signed [21:0] row1 = row0 + 1;
	wire signed [21:0] need = (row1 > (CAM_H - 1) ? CAM_H - 1 : row1);
	wire row_ready_now = ((row1 < 0) || (row0 > (CAM_H - 1))) || ($signed({11'b00000000000, rows_done}) > need);
	// R81: a row entirely above the frame (both source rows < 0) is all zero. It is
	// skipped in one cycle and reported on zr_* (the feed sends zeros for it), so the
	// crop reaches the first frame row before the 4-row line buffer moves on (an ROI
	// reaching far above the frame used to cost 192 cycles per such row: overrun).
	wire skip_row = ((state == WAITROW) && !sof) && (row1 < 0);
	assign zr_valid = skip_row || (((state == WAITROW) && !sof) && row_ready_now);
	assign zr_row = oy;
	assign zr_zero = skip_row;
	reg [2:0] pipe_flush;
	always @(posedge clk)
		if (rst) begin
			state <= IDLE;
			oy <= 0;
			ox <= 0;
			sy <= 0;
			sx <= 0;
			rx0 <= 0;
			rstep <= 0;
			overrun <= 0;
			frame_seen <= 0;
		end
		else
			case (state)
				IDLE:
					if (start) begin
						state <= WAITROW;
						oy <= 0;
						sy <= y0;
						rx0 <= x0;
						rstep <= step;
						frame_seen <= 1;
					end
				WAITROW:
					if (sof) begin
						state <= FLUSH;
						overrun <= 1;
					end
					else if (skip_row) begin
						oy <= oy + 1'b1;
						sy <= sy + $signed(rstep);
						if (oy == (OH - 1))
							state <= FLUSH;
					end
					else if (row_ready_now) begin
						if ((((row0 >= 0) && (row0 <= (CAM_H - 1))) && (rows_done < CAM_H)) && ($signed({12'b000000000000, cur_row}) >= (row0 + 3)))
							overrun <= 1;
						state <= RUN;
						ox <= 0;
						sx <= rx0;
					end
				RUN:
					if (sof) begin
						overrun <= 1;
						state <= FLUSH;
					end
					else begin
						sx <= sx + $signed(rstep);
						if (ox == (OW - 1)) begin
							oy <= oy + 1'b1;
							sy <= sy + $signed(rstep);
							state <= (oy == (OH - 1) ? FLUSH : WAITROW);
						end
						ox <= ox + 1'b1;
					end
				FLUSH:
					if (pipe_flush == 0)
						state <= IDLE;
			endcase
	wire signed [21:0] c0 = $signed(sx[31:16]);
	wire signed [21:0] c1 = c0 + 1;
	wire s0_valid = state == RUN;
	wire [21:0] c0p1 = c0 + 1;
	assign addr_e = ((c0 < -1) || (c0 > (CAM_W - 1)) ? 10'd0 : c0p1[10:1]);
	assign addr_o = ((c0 < 0) || (c0 > (CAM_W - 1)) ? 10'd0 : c0[10:1]);
	reg s1_valid;
	reg s1_c0odd;
	reg s1_m00;
	reg s1_m01;
	reg s1_m10;
	reg s1_m11;
	reg s1_last;
	reg [7:0] s1_fx;
	reg [7:0] s1_fy;
	reg [1:0] s1_b0;
	reg [1:0] s1_b1;
	reg [15:0] s1_addr_out;
	wire in_c0 = (c0 >= 0) && (c0 <= (CAM_W - 1));
	wire in_c1 = (c1 >= 0) && (c1 <= (CAM_W - 1));
	wire in_r0 = (row0 >= 0) && (row0 <= (CAM_H - 1));
	wire in_r1 = (row1 >= 0) && (row1 <= (CAM_H - 1));
	always @(posedge clk) begin
		s1_valid <= s0_valid && !rst;
		s1_c0odd <= c0[0];
		s1_m00 <= in_r0 && in_c0;
		s1_m01 <= in_r0 && in_c1;
		s1_m10 <= in_r1 && in_c0;
		s1_m11 <= in_r1 && in_c1;
		s1_fx <= sx[15:8];
		s1_fy <= sy[15:8];
		s1_b0 <= row0[1:0];
		s1_b1 <= row1[1:0];
		s1_addr_out <= (oy * OW) + ox;
		s1_last <= ox == (OW - 1);
	end
	function automatic [23:0] expand;
		input [15:0] p;
		input m;
		expand = (m ? {p[4:0], 3'b000, p[10:5], 2'b00, p[15:11], 3'b000} : 24'd0);
	endfunction
	wire [15:0] e0 = q[{s1_b0, 1'b0}];
	wire [15:0] o0 = q[{s1_b0, 1'b1}];
	wire [15:0] e1 = q[{s1_b1, 1'b0}];
	wire [15:0] o1 = q[{s1_b1, 1'b1}];
	wire [23:0] p00 = expand((s1_c0odd ? o0 : e0), s1_m00);
	wire [23:0] p01 = expand((s1_c0odd ? e0 : o0), s1_m01);
	wire [23:0] p10 = expand((s1_c0odd ? o1 : e1), s1_m10);
	wire [23:0] p11 = expand((s1_c0odd ? e1 : o1), s1_m11);
	reg s1a_valid;
	reg s1a_last;
	reg [7:0] s1a_fx;
	reg [7:0] s1a_fy;
	reg [15:0] s1a_addr;
	reg [23:0] r00;
	reg [23:0] r01;
	reg [23:0] r10;
	reg [23:0] r11;
	always @(posedge clk) begin
		s1a_valid <= s1_valid && !rst;
		s1a_last <= s1_last;
		s1a_fx <= s1_fx;
		s1a_fy <= s1_fy;
		s1a_addr <= s1_addr_out;
		r00 <= p00;
		r01 <= p01;
		r10 <= p10;
		r11 <= p11;
	end
	reg s2_valid;
	reg s2_last;
	reg [7:0] s2_fy;
	reg [15:0] s2_addr;
	reg [15:0] h0 [0:2];
	reg [15:0] h1 [0:2];
	wire [8:0] wx1 = {1'b0, s1a_fx};
	wire [8:0] wx0 = 9'd256 - {1'b0, s1a_fx};
	integer ch;
	always @(posedge clk) begin
		s2_valid <= s1a_valid && !rst;
		s2_last <= s1a_last;
		s2_fy <= s1a_fy;
		s2_addr <= s1a_addr;
		for (ch = 0; ch < 3; ch = ch + 1)
			begin
				h0[ch] <= (r00[8 * ch+:8] * wx0) + (r01[8 * ch+:8] * wx1);
				h1[ch] <= (r10[8 * ch+:8] * wx0) + (r11[8 * ch+:8] * wx1);
			end
	end
	wire [8:0] wy1 = {1'b0, s2_fy};
	wire [8:0] wy0 = 9'd256 - {1'b0, s2_fy};
	reg [24:0] v;
	reg [23:0] outpix;
	always @(posedge clk)
		if (rst) begin
			wr_valid <= 0;
			rows_ready <= 0;
		end
		else begin
			wr_valid <= s2_valid;
			wr_addr <= s2_addr;
			for (ch = 0; ch < 3; ch = ch + 1)
				begin
					v = ((h0[ch] * wy0) + (h1[ch] * wy1)) + 25'd32768;
					outpix[8 * ch+:8] = v[23:16];
				end
			wr_data <= outpix;
			if ((state == IDLE) && start)
				rows_ready <= 0;
			else if (((state == WAITROW) || (state == RUN)) && sof)
				rows_ready <= OH;
			else if ((s2_valid && s2_last) || skip_row)
				rows_ready <= rows_ready + 1'b1;
		end
	always @(posedge clk)
		if (rst)
			pipe_flush <= 0;
		else if (state == RUN)
			pipe_flush <= 3'd5;
		else if (pipe_flush != 0)
			pipe_flush <= pipe_flush - 1'b1;
endmodule
module p2_vision_ai (
	clk,
	rst,
	pose_release,
	det_release,
	roi_ack,
	pose_capture_ms,
	det_capture_ms,
	pose_dropped,
	det_dropped,
	clock_ms,
	captured,
	clock_gray,
	captured_gray,
	pose_drop_gray,
	det_drop_gray,
	pix_valid,
	pix,
	x,
	y,
	sof,
	eol,
	cam_overflow,
	roi_x0,
	roi_y0,
	roi_step,
	roi_enable,
	roi_toggle,
	pose_toggle,
	pose_frame,
	pose_bank,
	pose_x0,
	pose_y0,
	pose_step,
	det_toggle,
	det_frame,
	det_bank,
	frame_toggle,
	flags,
	pose_we,
	pose_waddr,
	pose_wdata,
	det_we,
	det_waddr,
	det_wdata
);
	parameter integer CAM_W = 1280;
	parameter integer CAM_H = 720;
	parameter integer AI_HZ = 121500000;
	input wire clk;
	input wire rst;
	input wire pose_release;
	input wire det_release;
	output wire roi_ack;
	output reg [31:0] pose_capture_ms;
	output reg [31:0] det_capture_ms;
	output reg [31:0] pose_dropped;
	output reg [31:0] det_dropped;
	output reg [31:0] clock_ms;
	output reg [31:0] captured;
	output reg [31:0] clock_gray;
	output reg [31:0] captured_gray;
	output reg [31:0] pose_drop_gray;
	output reg [31:0] det_drop_gray;
	input wire pix_valid;
	input wire [15:0] pix;
	input wire [10:0] x;
	input wire [9:0] y;
	input wire sof;
	input wire eol;
	input wire cam_overflow;
	input wire signed [31:0] roi_x0;
	input wire signed [31:0] roi_y0;
	input wire [31:0] roi_step;
	input wire roi_enable;
	input wire roi_toggle;
	output reg pose_toggle;
	output reg [31:0] pose_frame;
	output reg pose_bank;
	output reg signed [31:0] pose_x0;
	output reg signed [31:0] pose_y0;
	output reg [31:0] pose_step;
	output reg det_toggle;
	output reg [31:0] det_frame;
	output reg det_bank;
	output reg frame_toggle;
	output wire [7:0] flags;
	output reg pose_we;
	output reg [11:0] pose_waddr;
	output reg [31:0] pose_wdata;
	output reg det_we;
	output reg [7:0] det_waddr;
	output reg [31:0] det_wdata;
	localparam integer PW = 192;
	localparam integer PH = 288;
	localparam integer PIX = PW * PH;
	localparam integer POH = 18;
	localparam integer POW = 12;
	localparam integer DOH = 6;
	localparam integer DOW = 10;
	reg [31:0] frame_count;
	reg [31:0] ms_div;
	(* async_reg = "true" *) reg [1:0] pa;
	(* async_reg = "true" *) reg [1:0] da;
	reg pose_reserved;
	reg det_reserved;
	// R81: up to two pose frames in flight (pose_inflight); bank, frame number,
	// admission time and ROI of each are kept in a two-entry context FIFO (pc_*).
	reg [1:0] pose_inflight;
	wire pose_active = pose_inflight != 2'd0;
	reg det_active;
	reg [1:0] pc_n;
	reg pc_bank [0:1];
	reg [31:0] pc_frame [0:1];
	reg [31:0] pc_ms [0:1];
	reg signed [31:0] pc_x0 [0:1];
	reg signed [31:0] pc_y0 [0:1];
	reg [31:0] pc_step [0:1];
	reg [1:0] pose_bank_busy;
	wire pose_ack = pose_reserved && (pa[1] == pose_toggle);
	wire [1:0] pose_busy_after_ack = pose_bank_busy & ~(pose_ack ? (pose_bank ? 2'b10 : 2'b01) : 2'b00);
	wire pose_free = !(&pose_busy_after_ack);
	wire pose_alloc_bank = pose_busy_after_ack[0];
	reg pose_pending;
	reg pending_bank;
	reg [31:0] pending_frame;
	reg [31:0] pending_capture_ms;
	reg [31:0] pending_step;
	reg signed [31:0] pending_x0;
	reg signed [31:0] pending_y0;
	reg [31:0] pose_admit_frame;
	reg [31:0] pose_admit_ms;
	reg [31:0] det_admit_ms;
	wire [31:0] clock_ms_next = clock_ms + 32'd1;
	wire [31:0] captured_next = captured + 32'd1;
	wire [31:0] pose_dropped_next = pose_dropped + 32'd1;
	wire [31:0] det_dropped_next = det_dropped + 32'd1;
	always @(posedge clk)
		if (rst) begin
			ms_div <= 0;
			clock_ms <= 0;
			captured <= 0;
			clock_gray <= 0;
			captured_gray <= 0;
			pa <= 0;
			da <= 0;
		end
		else begin
			pa <= {pa[0], pose_release};
			da <= {da[0], det_release};
			if (ms_div == ((AI_HZ / 1000) - 1)) begin
				ms_div <= 0;
				clock_ms <= clock_ms_next;
				clock_gray <= clock_ms_next ^ (clock_ms_next >> 1);
			end
			else
				ms_div <= ms_div + 1'b1;
			if (sof) begin
				captured <= captured_next;
				captured_gray <= captured_next ^ (captured_next >> 1);
			end
		end
	(* async_reg = "true" *) reg roi_t1;
	(* async_reg = "true" *) reg roi_t2;
	reg roi_seen;
	reg roi_armed;
	reg signed [31:0] arm_x0;
	reg signed [31:0] arm_y0;
	reg [31:0] arm_step;
	always @(posedge clk)
		if (rst) begin
			roi_t1 <= 0;
			roi_t2 <= 0;
			roi_seen <= 0;
			roi_armed <= 0;
			arm_x0 <= 0;
			arm_y0 <= 0;
			arm_step <= 0;
		end
		else begin
			roi_t1 <= roi_toggle;
			roi_t2 <= roi_t1;
			if (roi_t2 != roi_seen) begin
				roi_seen <= roi_t2;
				roi_armed <= roi_enable;
				arm_x0 <= roi_x0;
				arm_y0 <= roi_y0;
				arm_step <= roi_step;
			end
		end
	always @(posedge clk)
		if (rst) begin
			frame_count <= 0;
			frame_toggle <= 0;
		end
		else if (sof) begin
			frame_count <= frame_count + 1'b1;
			frame_toggle <= ~frame_toggle;
		end
	wire det_net_ready;
	wire det_sampler_valid;
	// R68: two detection banks. Busy = being written, pending, or published and
	// still leased by the CPU (freed by the CPU release, as for pose banks).
	// R81: up to two detection frames in flight (det_inflight); the bank and the
	// admission time of each are kept in a two-entry context FIFO (dc_*).
	reg [1:0] det_inflight;
	wire det_running = det_inflight != 2'd0;
	reg det_pending;
	reg [1:0] det_bank_busy;
	reg [1:0] dc_n;
	reg dc_bank [0:1];
	reg [31:0] dc_ms [0:1];
	wire det_ack = det_reserved && (da[1] == det_toggle);
	wire [1:0] det_busy_after_ack = det_bank_busy & ~(det_ack ? (det_bank ? 2'b10 : 2'b01) : 2'b00);
	wire det_free = !(&det_busy_after_ack);
	wire det_alloc_bank = det_busy_after_ack[0];
	wire det_block = (det_inflight == 2'd2) || !det_free;
	wire det_start_ready = det_net_ready && !det_block;
	wire det_start_valid = det_sampler_valid && !det_block;
	wire ds_valid;
	wire ds_ready;
	wire ds_last;
	wire [23:0] ds_data;
	wire det_ovf;
	wire det_short;
	wire det_busy;
	p2_det_sampler #(
		.CAM_W(CAM_W),
		.CAM_H(CAM_H)
	) sampler(
		.clk(clk),
		.rst(rst),
		.pix_valid(pix_valid),
		.pix(pix),
		.x(x),
		.y(y),
		.sof(sof),
		.net_start_ready(det_start_ready),
		.net_start_valid(det_sampler_valid),
		.out_valid(ds_valid),
		.out_ready(ds_ready),
		.out_data(ds_data),
		.out_last(ds_last),
		.overflow(det_ovf),
		.frame_short(det_short),
		.busy(det_busy)
	);
	wire dh_valid;
	wire dh_last;
	wire do_valid;
	wire do_last;
	wire det_err;
	reg dh_ready;
	reg do_ready;
	wire [7:0] dh_data;
	wire [31:0] do_data;
	wire [15:0] dh_y;
	wire [15:0] dh_x;
	wire [15:0] do_y;
	wire [15:0] do_x;
	wire [31:0] dh_frame;
	wire [31:0] do_frame;
	p2_net_det det_net(
		.clk(clk),
		.rst(rst),
		.start_valid(det_start_valid),
		.start_ready(det_net_ready),
		.start_frame_id(frame_count),
		.in_valid(ds_valid),
		.in_ready(ds_ready),
		.in_data(ds_data),
		.in_last(ds_last),
		.heat_valid(dh_valid),
		.heat_last(dh_last),
		.heat_ready(dh_ready),
		.heat_data(dh_data),
		.heat_y(dh_y),
		.heat_x(dh_x),
		.heat_frame_id(dh_frame),
		.other_valid(do_valid),
		.other_last(do_last),
		.other_ready(do_ready),
		.other_data(do_data),
		.other_y(do_y),
		.other_x(do_x),
		.other_frame_id(do_frame),
		.error(det_err)
	);
	wire crop_busy;
	wire crop_overrun;
	wire zr_valid;
	wire [8:0] zr_row;
	wire zr_zero;
	// R81: rows the crop skipped as all zero. LUT RAM: the site overlay pins every
	// block RAM of the design, so no new DRM may appear.
	(* syn_ramstyle = "lut_ram" *) reg zrow [0:PH - 1];
	reg zq;
	wire cw_valid;
	wire [15:0] cw_addr;
	wire [23:0] cw_data;
	wire [8:0] rows_ready;
	reg feed_active;
	wire pose_start_ready;
	// R81: admit while the previous frame is still in the network (or still being
	// fed); at most two frames in flight and one queued feed.
	reg feed_next;
	wire pose_admit = (((((sof && roi_armed) && pose_free) && (pose_inflight != 2'd2)) && !crop_busy) && !feed_next) && pose_start_ready;
	reg signed [31:0] use_x0;
	reg signed [31:0] use_y0;
	reg [31:0] use_step;
	p2_crop #(
		.CAM_W(CAM_W),
		.CAM_H(CAM_H),
		.OW(PW),
		.OH(PH)
	) crop(
		.clk(clk),
		.rst(rst),
		.pix_valid(pix_valid),
		.pix(pix),
		.x(x),
		.y(y),
		.sof(sof),
		.eol(eol),
		.start(pose_admit),
		.x0(arm_x0),
		.y0(arm_y0),
		.step(arm_step),
		.wr_valid(cw_valid),
		.wr_addr(cw_addr),
		.wr_data(cw_data),
		.rows_ready(rows_ready),
		.busy(crop_busy),
		.overrun(crop_overrun),
		.zr_valid(zr_valid),
		.zr_row(zr_row),
		.zr_zero(zr_zero)
	);
	reg [23:0] cbuf [0:PIX - 1];
	reg [23:0] cbuf_q;
	wire rd_issue;
	reg [15:0] fk;
	always @(posedge clk) begin
		if (cw_valid)
			cbuf[cw_addr] <= cw_data;
		if (rd_issue)
			cbuf_q <= cbuf[fk];
	end
	reg [8:0] frow;
	reg [7:0] fcol;
	reg rd_pending;
	reg [23:0] sk_data [0:3];
	reg [1:0] sk_wp;
	reg [1:0] sk_rp;
	reg [2:0] sk_count;
	wire pin_ready;
	wire sk_valid = sk_count != 0;
	wire sk_pop = sk_valid && pin_ready;
	// R81: feed_full = every row of the frame being fed is already in cbuf (its crop
	// finished and the crop now serves the next frame, so rows_ready counts that one).
	reg feed_full;
	wire [8:0] feed_rows = (feed_full ? PH : rows_ready);
	// R81: the crop of the next frame must never overwrite a cbuf pixel the running
	// feed has not read yet (sticky, MMIO flags bit 7; expected to stay 0).
	wire cbuf_hazard = (((cw_valid && feed_active) && feed_full) && (cw_addr >= fk)) ||
		(((zr_valid && feed_active) && feed_full) && (zr_row >= frow));
	assign rd_issue = (feed_active && (frow < feed_rows)) && ((sk_count + rd_pending) < 3'd3);
	wire feed_last = rd_issue && (fk == (PIX - 1));
	wire feed_start = (pose_admit && (!feed_active || feed_last)) || (feed_last && feed_next);
	always @(posedge clk) begin
		if (zr_valid)
			zrow[zr_row] <= zr_zero;
		if (rd_issue)
			zq <= zrow[frow];
	end
	always @(posedge clk)
		if (rst) begin
			feed_active <= 0;
			feed_next <= 0;
			feed_full <= 0;
			fk <= 0;
			frow <= 0;
			fcol <= 0;
			rd_pending <= 0;
			sk_wp <= 0;
			sk_rp <= 0;
			sk_count <= 0;
		end
		else begin
			rd_pending <= rd_issue;
			if (rd_issue) begin
				fk <= fk + 1'b1;
				if (fcol == (PW - 1)) begin
					fcol <= 0;
					frow <= frow + 1'b1;
				end
				else
					fcol <= fcol + 1'b1;
				if (fk == (PIX - 1))
					feed_active <= 0;
			end
			if (pose_admit && feed_active && !feed_last) begin
				feed_next <= 1;
				feed_full <= 1;
			end
			if (feed_start) begin
				feed_active <= 1;
				feed_next <= 0;
				feed_full <= 0;
				fk <= 0;
				frow <= 0;
				fcol <= 0;
			end
			if (rd_pending) begin
				sk_data[sk_wp] <= (zq ? 24'd0 : cbuf_q);
				sk_wp <= sk_wp + 1'b1;
			end
			if (sk_pop)
				sk_rp <= sk_rp + 1'b1;
			sk_count <= (sk_count + (rd_pending ? 1'b1 : 1'b0)) - (sk_pop ? 1'b1 : 1'b0);
		end
	reg [16:0] fed;
	always @(posedge clk)
		if (rst)
			fed <= 0;
		else if (sk_pop)
			fed <= (fed == (PIX - 1) ? 17'd0 : fed + 1'b1);   // R81: wraps at each frame end
	wire ph_valid;
	wire ph_last;
	wire po_valid;
	wire po_last;
	wire pose_err;
	reg ph_ready;
	reg po_ready;
	wire [95:0] ph_data;
	wire [191:0] po_data;
	wire [15:0] ph_y;
	wire [15:0] ph_x;
	wire [15:0] po_y;
	wire [15:0] po_x;
	wire [31:0] ph_frame;
	wire [31:0] po_frame;
	p2_net_pose pose_net(
		.clk(clk),
		.rst(rst),
		.start_valid(pose_admit),
		.start_ready(pose_start_ready),
		.start_frame_id(frame_count),
		.in_valid(sk_valid),
		.in_ready(pin_ready),
		.in_data(sk_data[sk_rp]),
		.in_last(fed == (PIX - 1)),
		.heat_valid(ph_valid),
		.heat_last(ph_last),
		.heat_ready(ph_ready),
		.heat_data(ph_data),
		.heat_y(ph_y),
		.heat_x(ph_x),
		.heat_frame_id(ph_frame),
		.other_valid(po_valid),
		.other_last(po_last),
		.other_ready(po_ready),
		.other_data(po_data),
		.other_y(po_y),
		.other_x(po_x),
		.other_frame_id(po_frame),
		.error(pose_err)
	);
	always @(posedge clk)
		if (pose_admit) begin
			use_x0 <= arm_x0;
			use_y0 <= arm_y0;
			use_step <= arm_step;
		end
	// R81: pose frame contexts (pushed at admission, popped when the frame's results
	// are complete) and detection frame contexts (pushed at start, popped at completion).
	wire pose_frame_end;
	always @(posedge clk)
		if (rst)
			pc_n <= 0;
		else begin
			if (pose_frame_end) begin
				pc_bank[0] <= pc_bank[1];
				pc_frame[0] <= pc_frame[1];
				pc_ms[0] <= pc_ms[1];
				pc_x0[0] <= pc_x0[1];
				pc_y0[0] <= pc_y0[1];
				pc_step[0] <= pc_step[1];
			end
			if (pose_admit) begin
				pc_bank[(pc_n == 2'd0) || ((pc_n == 2'd1) && pose_frame_end) ? 0 : 1] <= pose_alloc_bank;
				pc_frame[(pc_n == 2'd0) || ((pc_n == 2'd1) && pose_frame_end) ? 0 : 1] <= frame_count;
				pc_ms[(pc_n == 2'd0) || ((pc_n == 2'd1) && pose_frame_end) ? 0 : 1] <= clock_ms;
				pc_x0[(pc_n == 2'd0) || ((pc_n == 2'd1) && pose_frame_end) ? 0 : 1] <= arm_x0;
				pc_y0[(pc_n == 2'd0) || ((pc_n == 2'd1) && pose_frame_end) ? 0 : 1] <= arm_y0;
				pc_step[(pc_n == 2'd0) || ((pc_n == 2'd1) && pose_frame_end) ? 0 : 1] <= arm_step;
			end
			pc_n <= (pc_n + (pose_admit ? 2'd1 : 2'd0)) - (pose_frame_end ? 2'd1 : 2'd0);
		end
	// R68 fused keypoint decoder, registers only (see generator header).
	reg [95:0] kbv;    // 12 x int8 best logit (joint j at [8j+:8])
	reg [95:0] kbp;    // 12 x best cell index
	reg [95:0] koy;    // 12 x y offset of the best cell
	reg [95:0] kox;    // 12 x x offset of the best cell
	reg [215:0] kseen; // heat cells accepted this frame
	reg kbad;          // an offsets cell arrived before its heat cell
	reg kh_q;          // a heat beat was accepted last cycle (in pw_buf)
	reg ko_q;          // an offsets beat was accepted last cycle (in pw_buf)
	reg [7:0] kcell_q; // that beat's cell index
	reg kgather;
	reg [3:0] kg;
	wire [15:0] ph_cell = (ph_y * POW) + ph_x;
	wire [15:0] po_cell = (po_y * POW) + po_x;
	integer kj;
	reg [2:0] pw_left;
	reg pw_kind;
	reg [191:0] pw_buf;
	reg [10:0] pw_addr;
	reg ph_done;
	reg po_done;
	wire pose_wbank = pc_bank[0];   // R81: bank of the frame whose results are being written
	assign pose_frame_end = ((pw_left == 3'd0) && kgather) && (kg == 4'd12);
	always @(posedge clk) begin
		ph_ready <= 0;
		po_ready <= 0;
		pose_we <= 0;
		if (rst) begin
			pw_left <= 0;
			ph_done <= 0;
			po_done <= 0;
			pose_toggle <= 0;
			pose_inflight <= 0;
			pose_reserved <= 0;
			pose_bank_busy <= 0;
			pose_pending <= 0;
			pending_bank <= 0;
			pending_frame <= 0;
			pending_capture_ms <= 0;
			pending_x0 <= 0;
			pending_y0 <= 0;
			pending_step <= 0;
			pose_admit_frame <= 0;
			pose_capture_ms <= 0;
			pose_frame <= 0;
			pose_bank <= 0;
			pose_x0 <= 0;
			pose_y0 <= 0;
			pose_step <= 0;
			kgather <= 0;
			kg <= 0;
			kh_q <= 0;
			ko_q <= 0;
			kbad <= 0;
			kseen <= 0;
		end
		else begin
			pose_bank_busy <= pose_busy_after_ack | (pose_admit ? (pose_alloc_bank ? 2'b10 : 2'b01) : 2'b00);
			// Beat accepted last cycle; pw_buf still holds it (the next three or
			// six cycles only drain pw_buf, so no new beat is accepted meanwhile).
			kh_q <= 0;
			ko_q <= 0;
			if (kh_q) begin
				kseen[kcell_q] <= 1'b1;
				for (kj = 0; kj < 12; kj = kj + 1)
					if (($signed(pw_buf[8 * kj+:8]) > $signed(kbv[8 * kj+:8])) ||
					    ((pw_buf[8 * kj+:8] == kbv[8 * kj+:8]) && (kcell_q < kbp[8 * kj+:8]))) begin
						kbv[8 * kj+:8] <= pw_buf[8 * kj+:8];
						kbp[8 * kj+:8] <= kcell_q;
					end
			end
			if (ko_q) begin
				if (!kseen[kcell_q])
					kbad <= 1'b1;
				for (kj = 0; kj < 12; kj = kj + 1)
					if (kbp[8 * kj+:8] == kcell_q) begin
						koy[8 * kj+:8] <= pw_buf[8 * kj+:8];
						kox[8 * kj+:8] <= pw_buf[8 * (kj + 12)+:8];
					end
			end
			pose_inflight <= (pose_inflight + (pose_admit ? 2'd1 : 2'd0)) - (pose_frame_end ? 2'd1 : 2'd0);
			// R81: clear the decoder when a frame is admitted into an idle pipeline and
			// when a frame's results are complete (the next frame's results follow).
			if ((pose_admit && (pose_inflight == 2'd0)) || pose_frame_end) begin
				kbv <= {12 {8'h80}};
				kbp <= {12 {8'hff}};
				kseen <= 0;
				kbad <= 0;
			end
			if (pose_ack)
				pose_reserved <= 0;
			if (pose_admit)
				pose_admit_frame <= frame_count;
			if (pose_pending && (!pose_reserved || pose_ack)) begin
				pose_frame <= pending_frame;
				pose_bank <= pending_bank;
				pose_x0 <= pending_x0;
				pose_y0 <= pending_y0;
				pose_step <= pending_step;
				pose_capture_ms <= pending_capture_ms;
				pose_toggle <= ~pose_toggle;
				pose_reserved <= 1;
				pose_pending <= 0;
			end
			if (pw_left != 0) begin
				pose_we <= 1;
				pose_waddr <= {pose_wbank, pw_addr};
				pose_wdata <= pw_buf[31:0];
				pw_buf <= pw_buf >> 32;
				pw_addr <= pw_addr + 1'b1;
				pw_left <= pw_left - 1'b1;
			end
			else if ((ph_valid && !ph_ready) && !ph_done) begin
				ph_ready <= 1;
				pw_left <= 3;
				pw_buf <= {96'b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000, ph_data};
				pw_addr <= ((ph_y * POW) + ph_x) * 3;
				if (ph_last)
					ph_done <= 1;
				kh_q <= 1;
				kcell_q <= ph_cell[7:0];
			end
			else if ((po_valid && !po_ready) && !po_done) begin
				po_ready <= 1;
				pw_left <= 6;
				pw_buf <= po_data;
				pw_addr <= 11'd648 + (((po_y * POW) + po_x) * 6);
				if (po_last)
					po_done <= 1;
				ko_q <= 1;
				kcell_q <= po_cell[7:0];
			end
			else if ((ph_done && po_done) && !kgather) begin
				kgather <= 1;
				kg <= 0;
			end
			else if (kgather && (kg != 4'd12)) begin
				pose_we <= 1;
				pose_waddr <= {pose_wbank, 11'd1944 + {7'd0, kg}};
				pose_wdata <= {kbv[8 * kg+:8], kbp[8 * kg+:8], koy[8 * kg+:8], kox[8 * kg+:8]};
				kg <= kg + 1'b1;
			end
			else if (kgather) begin
				pose_we <= 1;
				pose_waddr <= {pose_wbank, 11'd1956};
				pose_wdata <= {(kbad ? 16'h4b42 : 16'h4b50), pc_frame[0][15:0]};
				kgather <= 0;
				kg <= 0;
				ph_done <= 0;
				po_done <= 0;
				pose_pending <= 1;
				pending_frame <= pc_frame[0];
				pending_bank <= pc_bank[0];
				pending_x0 <= pc_x0[0];
				pending_y0 <= pc_y0[0];
				pending_step <= pc_step[0];
				pending_capture_ms <= pc_ms[0];
			end
		end
	end
	reg dh_done;
	reg do_done;
	wire det_wbank = dc_bank[0];   // R81: bank of the frame whose results are being written
	wire det_frame_end;
	reg [31:0] det_pend_frame;
	reg det_pend_bank;
	reg [31:0] det_pend_ms;
	wire det_fire = det_start_valid && det_start_ready;
	// R81: the writer completes a frame (same condition as its last branch below)
	assign det_frame_end = ((!((dh_valid && !dh_ready) && !dh_done) && !((do_valid && !do_ready) && !do_done)) && dh_done) && do_done;
	wire [5:0] dh_p = (dh_y * DOW) + dh_x;
	wire [5:0] do_p = (do_y * DOW) + do_x;
	always @(posedge clk) begin
		dh_ready <= 0;
		do_ready <= 0;
		det_we <= 0;
		if (rst) begin
			dh_done <= 0;
			do_done <= 0;
			det_toggle <= 0;
			det_frame <= 0;
			det_bank <= 0;
			det_active <= 0;
			det_reserved <= 0;
			det_capture_ms <= 0;
			det_inflight <= 0;
			dc_n <= 0;
			det_pending <= 0;
			det_bank_busy <= 0;
			det_pend_frame <= 0;
			det_pend_bank <= 0;
			det_pend_ms <= 0;
		end
		else begin
			det_bank_busy <= det_busy_after_ack | (det_fire ? (det_alloc_bank ? 2'b10 : 2'b01) : 2'b00);
			if (det_ack)
				det_reserved <= 0;
			det_inflight <= (det_inflight + (det_fire ? 2'd1 : 2'd0)) - (det_frame_end ? 2'd1 : 2'd0);
			dc_n <= (dc_n + (det_fire ? 2'd1 : 2'd0)) - (det_frame_end ? 2'd1 : 2'd0);
			if (det_frame_end) begin
				dc_bank[0] <= dc_bank[1];
				dc_ms[0] <= dc_ms[1];
			end
			if (det_fire) begin
				dc_bank[(dc_n == 2'd0) || ((dc_n == 2'd1) && det_frame_end) ? 0 : 1] <= det_alloc_bank;
				dc_ms[(dc_n == 2'd0) || ((dc_n == 2'd1) && det_frame_end) ? 0 : 1] <= clock_ms;
			end
			if (det_pending && (!det_reserved || det_ack)) begin
				det_pending <= 0;
				det_frame <= det_pend_frame;
				det_bank <= det_pend_bank;
				det_capture_ms <= det_pend_ms;
				det_reserved <= 1;
				det_toggle <= ~det_toggle;
			end
			if ((dh_valid && !dh_ready) && !dh_done) begin
				dh_ready <= 1;
				det_we <= 1;
				det_waddr <= {det_wbank, 1'b0, dh_p};
				det_wdata <= {24'b000000000000000000000000, dh_data};
				if (dh_last)
					dh_done <= 1;
			end
			else if ((do_valid && !do_ready) && !do_done) begin
				do_ready <= 1;
				det_we <= 1;
				det_waddr <= {det_wbank, 1'b1, do_p};
				det_wdata <= do_data;
				if (do_last)
					do_done <= 1;
			end
			else if (dh_done && do_done) begin
				dh_done <= 0;
				do_done <= 0;
				det_pend_frame <= dh_frame;
				det_pend_bank <= dc_bank[0];
				det_pend_ms <= dc_ms[0];
				det_pending <= 1;
			end
		end
	end
	reg [7:0] sticky;
	always @(posedge clk)
		if (rst)
			sticky <= 0;
		else
			sticky <= sticky | {1'b0, cbuf_hazard, pose_err, det_err, det_short, det_ovf, cam_overflow, crop_overrun};
	always @(posedge clk)
		if (rst) begin
			pose_dropped <= 0;
			det_dropped <= 0;
			pose_drop_gray <= 0;
			det_drop_gray <= 0;
			pose_admit_ms <= 0;
			det_admit_ms <= 0;
		end
		else begin
			if ((sof && roi_armed) && !pose_admit) begin
				pose_dropped <= pose_dropped_next;
				pose_drop_gray <= pose_dropped_next ^ (pose_dropped_next >> 1);
			end
			if (sof && !(det_start_valid && det_start_ready)) begin
				det_dropped <= det_dropped_next;
				det_drop_gray <= det_dropped_next ^ (det_dropped_next >> 1);
			end
			if (pose_admit)
				pose_admit_ms <= clock_ms;
			if (det_start_valid && det_start_ready)
				det_admit_ms <= clock_ms;
		end
	assign roi_ack = roi_seen;
	assign flags = {sticky[6:0], roi_armed};
endmodule
module p2_vision_mmio (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_wdata,
	req_write,
	req_be,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	ai_clk,
	roi_ack,
	pose_capture_ms,
	det_capture_ms,
	clock_gray,
	captured_gray,
	pose_drop_gray,
	det_drop_gray,
	pose_release,
	det_release,
	pose_toggle,
	pose_frame,
	pose_bank,
	pose_x0,
	pose_y0,
	pose_step,
	det_toggle,
	det_frame,
	det_bank,
	frame_toggle,
	flags,
	pose_we,
	pose_waddr,
	pose_wdata,
	det_we,
	det_waddr,
	det_wdata,
	roi_x0,
	roi_y0,
	roi_step,
	roi_enable,
	roi_toggle,
	ovl_toggle,
	view_enable, view_hud, view_hud_toggle, view_dot_en, view_seg_en, view_dots, view_segs,
	preview_enable,
	dot_en,
	seg_en,
	box_en,
	box0,
	box1,
	dots,
	segs
);
	parameter [31:0] BASE = 32'h10008000;
	parameter integer NDOT = 12;
	parameter integer NSEG = 12;
	parameter integer DISP_MUL_Q16 = 65536;
	parameter integer DISP_Y0 = 0;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire [31:0] req_wdata;
	input wire req_write;
	input wire [3:0] req_be;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	input wire ai_clk;
	input wire roi_ack;
	input wire [31:0] pose_capture_ms;
	input wire [31:0] det_capture_ms;
	input wire [31:0] clock_gray;
	input wire [31:0] captured_gray;
	input wire [31:0] pose_drop_gray;
	input wire [31:0] det_drop_gray;
	output reg pose_release;
	output reg det_release;
	input wire pose_toggle;
	input wire [31:0] pose_frame;
	input wire pose_bank;
	input wire signed [31:0] pose_x0;
	input wire signed [31:0] pose_y0;
	input wire [31:0] pose_step;
	input wire det_toggle;
	input wire [31:0] det_frame;
	input wire det_bank;
	input wire frame_toggle;
	input wire [7:0] flags;
	input wire pose_we;
	input wire [11:0] pose_waddr;
	input wire [31:0] pose_wdata;
	input wire det_we;
	input wire [7:0] det_waddr;
	input wire [31:0] det_wdata;
	output reg signed [31:0] roi_x0;
	output reg signed [31:0] roi_y0;
	output reg [31:0] roi_step;
	output reg roi_enable;
	output reg roi_toggle;
	output reg ovl_toggle;
	output reg view_enable, view_hud_toggle; output reg [31:0] view_hud;
	output wire [11:0] view_dot_en, view_seg_en;
	output wire [383:0] view_dots; output wire [1919:0] view_segs;
	output reg preview_enable;
	output wire [NDOT - 1:0] dot_en;
	output wire [NSEG - 1:0] seg_en;
	output reg box_en;
	output reg [31:0] box0;
	output reg [31:0] box1;
	output wire [(32 * NDOT) - 1:0] dots;
	output wire [(160 * NSEG) - 1:0] segs;
	reg [31:0] pose_mem [0:4095];
	reg [31:0] det_mem [0:255];
	always @(posedge ai_clk) begin
		if (pose_we)
			pose_mem[pose_waddr] <= pose_wdata;
		if (det_we)
			det_mem[det_waddr] <= det_wdata;
	end
	wire [31:0] off = {17'b00000000000000000, req_addr[14:0]};
	wire hit = (req_addr[31:15] == BASE[31:15]) && (req_addr[1:0] == 0);
	wire is_pose = off >= 32'h00004000;
	wire is_det = (off >= 32'h00001000) && (off < 32'h00001400);
	reg [31:0] pose_q;
	reg [31:0] det_q;
	wire fire = req_valid && req_ready;
	always @(posedge clk) begin
		if (fire && is_pose)
			pose_q <= pose_mem[off[13:2]];
		if (fire && is_det)
			det_q <= det_mem[off[9:2]];
	end
	(* async_reg = "true" *) reg [2:0] s1;
	(* async_reg = "true" *) reg [2:0] s2;
	reg [2:0] seen;
	reg [31:0] frame_count;
	reg [31:0] det_count;
	reg [31:0] pose_count;
	reg [31:0] det_info;
	reg [31:0] pose_info;
	reg pose_available;
	reg det_available;
	reg pose_lease;
	reg det_lease;
	reg [31:0] pcm;
	reg [31:0] dcm;
	reg signed [31:0] stage_x0;
	reg signed [31:0] stage_y0;
	reg [31:0] stage_step;
	(* async_reg = "true" *) reg [1:0] roi_a;
	(* async_reg = "true" *) reg [127:0] g1;
	(* async_reg = "true" *) reg [127:0] g2;
	function [31:0] ungray;
		input [31:0] a;
		integer k;
		begin
			ungray[31] = a[31];
			for (k = 30; k >= 0; k = k - 1)
				ungray[k] = ungray[k + 1] ^ a[k];
		end
	endfunction
	wire [31:0] real_ms = ungray(g2[127:96]);
	wire [31:0] real_captured = ungray(g2[95:64]);
	wire [31:0] real_pose_drop = ungray(g2[63:32]);
	wire [31:0] real_det_drop = ungray(g2[31:0]);
	wire lease_pose_cmd = (((fire && hit) && req_write) && (req_be == 15)) && (off == 32'h00000074);
	wire lease_det_cmd = (((fire && hit) && req_write) && (req_be == 15)) && (off == 32'h0000007c);
	wire release_pose_cmd = (((fire && hit) && req_write) && (req_be == 15)) && (off == 32'h00000078);
	wire release_det_cmd = (((fire && hit) && req_write) && (req_be == 15)) && (off == 32'h00000080);
	always @(posedge clk)
		if (rst) begin
			pose_available <= 0;
			det_available <= 0;
			pose_lease <= 0;
			det_lease <= 0;
			pose_release <= 0;
			det_release <= 0;
			pcm <= 0;
			dcm <= 0;
			g1 <= 0;
			g2 <= 0;
			roi_a <= 0;
		end
		else begin
			g1 <= {clock_gray, captured_gray, pose_drop_gray, det_drop_gray};
			g2 <= g1;
			roi_a <= {roi_a[0], roi_ack};
			if (s2[2] != seen[2]) begin
				pose_available <= 1;
				pcm <= pose_capture_ms;
			end
			if (s2[1] != seen[1]) begin
				det_available <= 1;
				dcm <= det_capture_ms;
			end
			if ((lease_pose_cmd && pose_available) && !pose_lease)
				pose_lease <= 1;
			if ((lease_det_cmd && det_available) && !det_lease)
				det_lease <= 1;
			if (release_pose_cmd && pose_lease) begin
				pose_lease <= 0;
				pose_available <= 0;
				pose_release <= seen[2];
			end
			if (release_det_cmd && det_lease) begin
				det_lease <= 0;
				det_available <= 0;
				det_release <= seen[1];
			end
		end
	reg signed [31:0] info_x0;
	reg signed [31:0] info_y0;
	reg [31:0] info_step;
	(* async_reg = "true" *) reg [7:0] flags1;
	(* async_reg = "true" *) reg [7:0] flags2;
	always @(posedge clk)
		if (rst) begin
			s1 <= 0;
			s2 <= 0;
			seen <= 0;
			frame_count <= 0;
			det_count <= 0;
			pose_count <= 0;
			det_info <= 0;
			pose_info <= 0;
			info_x0 <= 0;
			info_y0 <= 0;
			info_step <= 0;
			flags1 <= 0;
			flags2 <= 0;
		end
		else begin
			s1 <= {pose_toggle, det_toggle, frame_toggle};
			s2 <= s1;
			flags1 <= flags;
			flags2 <= flags1;
			if (s2[0] != seen[0]) begin
				seen[0] <= s2[0];
				frame_count <= frame_count + 1'b1;
			end
			if (s2[1] != seen[1]) begin
				seen[1] <= s2[1];
				det_count <= det_count + 1'b1;
				det_info <= {det_bank, det_frame[30:0]};
			end
			if (s2[2] != seen[2]) begin
				seen[2] <= s2[2];
				pose_count <= pose_count + 1'b1;
				pose_info <= {pose_bank, pose_frame[30:0]};
				info_x0 <= pose_x0;
				info_y0 <= pose_y0;
				info_step <= pose_step;
			end
		end
	reg [(32 * NDOT) - 1:0] raw;
	reg post_start;
	reg post_reset;
	wire post_busy, post_done;
	// R57: post_view was a lockstep duplicate of this filter; one filter now
	// produces both the display (DISP_*) and identity view outputs.
	p2_kp_post #(
		.MUL_Q16(DISP_MUL_Q16),
		.Y0(DISP_Y0),
		.VIEW_MUL_Q16(65536),
		.VIEW_Y0(0),
		.LUT_FILE("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96/p2_oe_lut59.mem")
	) post(
		.clk(clk),
		.rst(rst),
		.start(post_start),
		.reset_state(post_reset),
		.raw(raw),
		.busy(post_busy),
		.done(post_done),
		.dot_en(dot_en),
		.seg_en(seg_en),
		.dots(dots),
		.segs(segs),
		.view_dot_en(view_dot_en),
		.view_seg_en(view_seg_en),
		.view_dots(view_dots),
		.view_segs(view_segs)
	);
	reg pending;
	reg mem_rsp;
	reg mem_pose;
	reg known_reg;
	reg writable;
	always @(*) begin
		known_reg = 0;
		writable = 0;
		case (off)
			32'h00000000, 32'h00000004, 32'h00000008, 32'h0000000c, 32'h00000010, 32'h00000014, 32'h00000018, 32'h0000001c, 32'h00000020, 32'h00000024, 32'h00000044, 32'h00000048, 32'h00000070, 32'h00000084, 32'h00000088, 32'h0000008c, 32'h00000090, 32'h00000094, 32'h00000098: known_reg = 1;
			32'h00000030, 32'h00000034, 32'h00000038, 32'h0000003c, 32'h00000040, 32'h0000004c, 32'h00000050, 32'h00000054, 32'h00000058, 32'h0000005c, 32'h000000a0, 32'h00000060, 32'h00000064, 32'h00000074, 32'h00000078, 32'h0000007c, 32'h00000080: begin
				known_reg = 1;
				writable = 1;
			end
			default:
				if ((off >= 32'h00000300) && (off < 32'h00000330)) begin
					known_reg = 1;
					writable = 1;
				end
		endcase
	end
	wire illegal = ((((((!hit || ((is_pose || is_det) && (req_write || (is_pose ? !pose_lease || (off[13] != pose_info[31]) : !det_lease || (off[9] != det_info[31]))))) || (!(is_pose || is_det) && (!known_reg || (req_write && (!writable || (req_be != 15)))))) || ((req_write && (off == 32'h0000003c)) && (roi_a[1] != roi_toggle))) || (lease_pose_cmd && (!pose_available || pose_lease))) || (lease_det_cmd && (!det_available || det_lease))) || (release_pose_cmd && !pose_lease)) || (release_det_cmd && !det_lease);
	reg wr_go;
	reg [11:0] wr_off;
	reg [31:0] wr_data;
	assign req_ready = (!rst && !rsp_valid) && !pending;
	integer i;
	reg [31:0] reg_q;
	always @(*) begin
		reg_q = 0;
		case (off[11:0])
			12'h000: reg_q = 32'h50325631;
			12'h004: reg_q = real_captured;
			12'h008: reg_q = det_count;
			12'h00c: reg_q = det_info;
			12'h010: reg_q = pose_count;
			12'h014: reg_q = pose_info;
			12'h018: reg_q = info_x0;
			12'h01c: reg_q = info_y0;
			12'h020: reg_q = info_step;
			12'h024: reg_q = {24'b000000000000000000000000, flags2};
			12'h030: reg_q = stage_x0;
			12'h034: reg_q = stage_y0;
			12'h038: reg_q = stage_step;
			12'h03c: reg_q = {31'b0000000000000000000000000000000, roi_enable};
			12'h058: reg_q = {31'd0, preview_enable};
			12'h05c: reg_q={31'd0,view_enable};
			12'h0a0: reg_q=view_hud;
			12'h064: reg_q = {31'd0, post_busy || post_start};
			12'h044: reg_q = dot_en;
			12'h048: reg_q = seg_en;
			12'h04c: reg_q = box_en;
			12'h050: reg_q = box0;
			12'h054: reg_q = box1;
			12'h070: reg_q = {27'b000000000000000000000000000, roi_a[1] != roi_toggle, det_lease, det_available, pose_lease, pose_available};
			12'h084: reg_q = pcm;
			12'h088: reg_q = dcm;
			12'h08c: reg_q = real_pose_drop;
			12'h090: reg_q = real_det_drop;
			12'h094: reg_q = real_ms;
			12'h098: reg_q = 32'h0000000f; // R68 bit 3: keypoint summary words 1944..1956
			12'h074, 12'h078, 12'h07c, 12'h080: reg_q = 0;
			default: reg_q = 0;
		endcase
	end
	always @(posedge clk)
		if (rst) begin
			rsp_valid <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			pending <= 0;
			mem_rsp <= 0;
			mem_pose <= 0;
			wr_go <= 0;
			wr_off <= 0;
			wr_data <= 0;
			stage_x0 <= 0;
			stage_y0 <= 0;
			stage_step <= 0;
			roi_x0 <= 0;
			roi_y0 <= 0;
			roi_step <= 0;
			roi_enable <= 0;
			roi_toggle <= 0;
			ovl_toggle <= 0;
			preview_enable <= 0; view_enable<=0; view_hud<=0; view_hud_toggle<=0;
			box_en <= 0;
			box0 <= 0;
			box1 <= 0;
			raw <= 0;
			post_start <= 0;
			post_reset <= 0;
		end
		else begin
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (pending) begin
				pending <= 0;
				rsp_valid <= 1;
				rsp_rdata <= (mem_pose ? pose_q : det_q);
				rsp_error <= 0;
			end
			wr_go <= 0;
			post_start <= 0;
			if (post_done)
				ovl_toggle <= ~ovl_toggle;
			if (fire) begin
				if (illegal) begin
					rsp_valid <= 1;
					rsp_error <= 1;
					rsp_rdata <= 0;
				end
				else if (!req_write && (is_pose || is_det)) begin
					pending <= 1;
					mem_pose <= is_pose;
				end
				else begin
					rsp_valid <= 1;
					rsp_error <= 0;
					rsp_rdata <= (req_write ? 32'd0 : reg_q);
					wr_go <= req_write && (off < 32'h00001000);
					wr_off <= off[11:0];
					wr_data <= req_wdata;
				end
			end
			if (wr_go) begin
				case (wr_off)
					12'h030: stage_x0 <= wr_data;
					12'h034: stage_y0 <= wr_data;
					12'h038: stage_step <= wr_data;
					12'h03c: begin
						roi_x0 <= stage_x0;
						roi_y0 <= stage_y0;
						roi_step <= stage_step;
						roi_enable <= wr_data[0];
						roi_toggle <= ~roi_toggle;
					end
					12'h040: ovl_toggle <= ~ovl_toggle;
					12'h04c: box_en <= wr_data[0];
					12'h058: preview_enable <= wr_data[0];
					12'h05c: view_enable<=wr_data[0];
					12'h0a0: begin view_hud<=wr_data; view_hud_toggle<=~view_hud_toggle; end
					12'h060:
						if (!post_busy) begin
							post_start <= 1;
							post_reset <= wr_data[0];
						end
					12'h050: box0 <= wr_data;
					12'h054: box1 <= wr_data;
					default:
						;
				endcase
				for (i = 0; i < NDOT; i = i + 1)
					if (wr_off == (12'h300 + (4 * i)))
						raw[32 * i+:32] <= wr_data;
			end
		end
endmodule
module p2_kp_post (
	clk,
	rst,
	start,
	reset_state,
	raw,
	busy,
	done,
	dot_en,
	seg_en,
	dots,
	segs,
	view_dot_en,
	view_seg_en,
	view_dots,
	view_segs
);
	// R57: one One-Euro filter, two output mappings. After the filter pass the
	// mapping/segment sequence runs once with MUL_Q16/Y0 (dots/segs) and once
	// with VIEW_MUL_Q16/VIEW_Y0 (view_*), through the same multiplier.
	parameter integer MC_Q8 = 179;
	parameter integer KB_Q16 = 193566;
	parameter integer MUL_Q16 = 65536;
	parameter integer Y0 = 0;
	parameter integer VIEW_MUL_Q16 = 65536;
	parameter integer VIEW_Y0 = 0;
	parameter LUT_FILE = "p2_oe_lut.mem";
	input wire clk;
	input wire rst;
	input wire start;
	input wire reset_state;
	input wire [383:0] raw;
	output reg busy;
	output reg done;
	output reg [11:0] dot_en;
	output reg [11:0] seg_en;
	output reg [383:0] dots;
	output reg [1919:0] segs;
	output reg [11:0] view_dot_en;
	output reg [11:0] view_seg_en;
	output reg [383:0] view_dots;
	output reg [1919:0] view_segs;
	localparam integer A1 = 6301;
	(* syn_ramstyle = "block_ram" *) reg [16:0] lut [0:1023];
	initial $readmemh(LUT_FILE, lut);
	reg [16:0] lut_q;
	reg [9:0] lut_addr;
	always @(posedge clk) lut_q <= lut[lut_addr];
	reg signed [17:0] ma;
	reg signed [24:0] mb;
	reg signed [42:0] mp;
	always @(posedge clk) mp <= ma * mb;
	reg vw;
	wire signed [31:0] map_mul = (vw ? VIEW_MUL_Q16 : MUL_Q16);
	wire signed [31:0] map_y0 = (vw ? VIEW_Y0 : Y0);
	wire signed [31:0] mp16 = $signed(mp[42:16]);
	wire signed [31:0] my_v = map_y0 + ((mp16 + 128) >>> 8);
	reg signed [31:0] xh [0:11];
	reg signed [31:0] yh [0:11];
	reg signed [31:0] dxh [0:11];
	reg signed [31:0] dyh [0:11];
	reg [11:0] on;
	reg signed [15:0] lx [0:11];
	reg signed [15:0] ly [0:11];
	reg [4:0] state;
	reg [4:0] ret;
	reg [3:0] j;
	reg ax;
	reg v;
	reg signed [31:0] xi;
	reg signed [31:0] h;
	reg signed [31:0] dh;
	reg signed [31:0] t0;
	reg signed [31:0] dd;
	reg signed [31:0] t1;
	reg signed [31:0] t2;
	reg signed [15:0] x1;
	reg signed [15:0] y1;
	reg signed [15:0] x2;
	reg signed [15:0] y2;
	reg signed [15:0] gdx;
	reg signed [15:0] gdy;
	reg [3:0] ea;
	reg [3:0] eb;
	reg [31:0] sq_v;
	reg [31:0] sq_r;
	reg [31:0] sq_bit;
	reg [1:0] wcnt;
	localparam S_IDLE = 0;
	localparam S_LD = 1;
	localparam S_D0 = 2;
	localparam S_D1 = 3;
	localparam S_F0 = 4;
	localparam S_F1 = 5;
	localparam S_L0 = 6;
	localparam S_X0 = 7;
	localparam S_X1 = 8;
	localparam S_ADV = 9;
	localparam S_MX = 10;
	localparam S_MX1 = 11;
	localparam S_MY = 12;
	localparam S_MY1 = 13;
	localparam S_E0 = 14;
	localparam S_E1 = 15;
	localparam S_P1 = 16;
	localparam S_P2 = 17;
	localparam S_P3 = 18;
	localparam S_P4 = 19;
	localparam S_P5 = 20;
	localparam S_P6 = 21;
	localparam S_P7 = 22;
	localparam S_SQ0 = 23;
	localparam S_SQ1 = 24;
	localparam S_DONE = 25;
	localparam S_WAIT = 26;
	localparam S_D0M = 27;
	function automatic [7:0] edge_ab;
		input [3:0] e;
		case (e)
			0: edge_ab = 8'h01;
			1: edge_ab = 8'h02;
			2: edge_ab = 8'h24;
			3: edge_ab = 8'h13;
			4: edge_ab = 8'h35;
			5: edge_ab = 8'h06;
			6: edge_ab = 8'h17;
			7: edge_ab = 8'h67;
			8: edge_ab = 8'h68;
			9: edge_ab = 8'h8a;
			10: edge_ab = 8'h79;
			default: edge_ab = 8'h9b;
		endcase
	endfunction
	task automatic mul;
		input signed [17:0] a;
		input signed [24:0] b;
		input [4:0] r;
		begin
			ma <= a;
			mb <= b;
			ret <= r;
			wcnt <= 2'd1;
			state <= S_WAIT;
		end
	endtask
	integer k;
	always @(posedge clk) begin
		done <= 0;
		if (rst) begin
			// Data outputs (dots/segs/view_*) and multiplier operands are not
			// reset: they are written before use and published only with
			// their enables, which reset here.
			state <= S_IDLE;
			busy <= 0;
			on <= 0;
			dot_en <= 0;
			seg_en <= 0;
			view_dot_en <= 0;
			view_seg_en <= 0;
			j <= 0;
			ax <= 0;
			vw <= 0;
			lut_addr <= 0;
			wcnt <= 0;
			ret <= 0;
			for (k = 0; k < 12; k = k + 1)
				begin
					xh[k] <= 0;
					yh[k] <= 0;
					dxh[k] <= 0;
					dyh[k] <= 0;
					lx[k] <= 0;
					ly[k] <= 0;
				end
		end
		else
			case (state)
				S_IDLE:
					if (start) begin
						busy <= 1;
						j <= 0;
						ax <= 0;
						vw <= 0;
						state <= S_LD;
						if (reset_state)
							on <= 0;
					end
				S_WAIT:
					if (wcnt != 0)
						wcnt <= wcnt - 1'b1;
					else
						state <= ret;
				S_LD: begin
					v <= raw[(32 * j) + 31];
					xi <= (ax ? {13'b0000000000000, raw[(32 * j) + 16+:15], 4'b0000} : {13'b0000000000000, raw[32 * j+:15], 4'b0000});
					h <= (ax ? yh[j] : xh[j]);
					dh <= (ax ? dyh[j] : dxh[j]);
					state <= S_D0;
				end
				S_D0:
					if (!v || !on[j]) begin
						if (ax) begin
							yh[j] <= xi;
							dyh[j] <= 0;
							on[j] <= v;
						end
						else begin
							xh[j] <= xi;
							dxh[j] <= 0;
						end
						state <= S_ADV;
					end
					else begin
						// R59: register the difference; the multiply issues next
						// cycle from a register (APM operand path timing).
						t0 <= xi - h;
						dd <= (xi - h) - dh;
						state <= S_D0M;
					end
				S_D0M:
					mul(A1, dd, S_D1);
				S_D1: begin
					dh <= dh + mp16;
					state <= S_F0;
				end
				S_F0:
					mul(KB_Q16, (dh < 0 ? -dh : dh), S_F1);
				S_F1: begin
					t1 <= MC_Q8 + mp16;
					state <= S_L0;
				end
				S_L0: begin
					lut_addr <= ((t1 >>> 4) > 1023 ? 10'd1023 : t1[13:4]);
					ret <= S_X0;
					wcnt <= 2'd1;
					state <= S_WAIT;
				end
				S_X0:
					mul($signed({1'b0, lut_q}), t0, S_X1);
				S_X1: begin
					if (ax) begin
						yh[j] <= h + mp16;
						dyh[j] <= dh;
					end
					else begin
						xh[j] <= h + mp16;
						dxh[j] <= dh;
					end
					state <= S_ADV;
				end
				S_ADV:
					if (!ax) begin
						ax <= 1;
						state <= S_LD;
					end
					else begin
						ax <= 0;
						if (j == 11) begin
							j <= 0;
							state <= S_MX;
						end
						else begin
							j <= j + 1'b1;
							state <= S_LD;
						end
					end
				S_MX:
					mul(map_mul, xh[j], S_MX1);
				S_MX1: begin
					lx[j] <= (mp16 + 128) >>> 8;
					state <= S_MY;
				end
				S_MY:
					mul(map_mul, yh[j], S_MY1);
				S_MY1: begin
					ly[j] <= my_v;
					if (vw) begin
						view_dots[32 * j+:32] <= {4'b0000, my_v[11:0], 4'b0000, lx[j][11:0]};
						view_dot_en[j] <= dot_en[j];
					end
					else begin
						dots[32 * j+:32] <= {4'b0000, my_v[11:0], 4'b0000, lx[j][11:0]};
						dot_en[j] <= raw[(32 * j) + 31];
					end
					if (j == 11) begin
						j <= 0;
						state <= S_E0;
					end
					else begin
						j <= j + 1'b1;
						state <= S_MX;
					end
				end
				S_E0: begin
					ea <= edge_ab(j) >> 4;
					eb <= edge_ab(j) & 4'hf;
					state <= S_E1;
				end
				S_E1: begin
					x1 <= lx[ea];
					y1 <= ly[ea];
					x2 <= lx[eb];
					y2 <= ly[eb];
					gdx <= lx[eb] - lx[ea];
					gdy <= ly[eb] - ly[ea];
					if (vw)
						view_seg_en[j] <= view_dot_en[ea] && view_dot_en[eb];
					else
						seg_en[j] <= dot_en[ea] && dot_en[eb];
					state <= S_P1;
				end
				S_P1:
					mul(y1, gdx, S_P2);
				S_P2: begin
					t0 <= mp[31:0];
					mul(x1, gdy, S_P3);
				end
				S_P3: begin
					t0 <= t0 - mp[31:0];
					mul(x1, gdx, S_P4);
				end
				S_P4: begin
					t1 <= -mp[31:0];
					mul(y1, gdy, S_P5);
				end
				S_P5: begin
					t1 <= t1 - mp[31:0];
					mul(gdx, gdx, S_P6);
				end
				S_P6: begin
					t2 <= mp[31:0];
					mul(gdy, gdy, S_P7);
				end
				S_P7: begin
					t2 <= t2 + mp[31:0];
					sq_v <= t2 + mp[31:0];
					sq_r <= 0;
					sq_bit <= 32'h40000000;
					state <= S_SQ0;
				end
				S_SQ0:
					if (sq_bit > sq_v)
						sq_bit <= sq_bit >> 2;
					else
						state <= S_SQ1;
				S_SQ1:
					if (sq_bit == 0) begin
						if (vw)
							view_segs[160 * j+:160] <= {t2, sq_r[30:0], 1'b0, gdy, gdx, t1, t0};
						else
							segs[160 * j+:160] <= {t2, sq_r[30:0], 1'b0, gdy, gdx, t1, t0};
						if (j != 11) begin
							j <= j + 1'b1;
							state <= S_E0;
						end
						else if (vw)
							state <= S_DONE;
						else begin
							vw <= 1;
							j <= 0;
							state <= S_MX;
						end
					end
					else begin
						if (sq_v >= (sq_r + sq_bit)) begin
							sq_v <= sq_v - (sq_r + sq_bit);
							sq_r <= (sq_r >> 1) + sq_bit;
						end
						else
							sq_r <= sq_r >> 1;
						sq_bit <= sq_bit >> 2;
					end
				S_DONE: begin
					busy <= 0;
					done <= 1;
					state <= S_IDLE;
				end
				default: state <= S_IDLE;
			endcase
	end
endmodule
module fn_pose_endpoint (
	preview_valid,
	preview_sof,
	preview_rst,
	preview_pix,
	preview_x,
	preview_y,
	cam_half_valid,
	cam_half_sof,
	cam_half_pix,
	ovl_toggle,
	box_en,
	view_enable, view_hud, view_hud_toggle, view_dot_en, view_seg_en, view_dots, view_segs,
	preview_enable,
	dot_en,
	seg_en,
	box0,
	box1,
	dots,
	segs,
	cpu_clk,
	cpu_rst,
	ai_clk,
	cam_clk,
	cam_en,
	cam_vs,
	cam_data,
	req_valid,
	req_ready,
	req_addr,
	req_wdata,
	req_write,
	req_be,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error
);
	parameter AI_HZ = 121500000;
	output wire preview_valid;
	output wire preview_sof;
	output wire preview_rst;
	output wire [15:0] preview_pix;
	output wire [10:0] preview_x;
	output wire [9:0] preview_y;
	// R82: the 640x360 camera stream before the upscaler, for the POSEVIEW full-screen view
	output wire cam_half_valid;
	output wire cam_half_sof;
	output wire [15:0] cam_half_pix;
	output wire ovl_toggle;
	output wire box_en;
	output wire view_enable, view_hud_toggle; output wire [31:0] view_hud;
	output wire [11:0] view_dot_en, view_seg_en;
	output wire [383:0] view_dots; output wire [1919:0] view_segs;
	output wire preview_enable;
	output wire [11:0] dot_en;
	output wire [11:0] seg_en;
	output wire [31:0] box0;
	output wire [31:0] box1;
	output wire [383:0] dots;
	output wire [1919:0] segs;
	input wire cpu_clk;
	input wire cpu_rst;
	input wire ai_clk;
	input wire cam_clk;
	input wire cam_en;
	input wire cam_vs;
	input wire [15:0] cam_data;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire [31:0] req_wdata;
	input wire req_write;
	input wire [3:0] req_be;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	(* async_reg = "true" *) reg [2:0] ars = 7;
	(* async_reg = "true" *) reg [2:0] crs = 7;
	always @(posedge ai_clk or posedge cpu_rst)
		if (cpu_rst)
			ars <= 7;
		else
			ars <= {ars[1:0], 1'b0};
	always @(posedge cam_clk or posedge cpu_rst)
		if (cpu_rst)
			crs <= 7;
		else
			crs <= {crs[1:0], 1'b0};
	(* async_reg = "true" *) reg [1:0] domains_ready = 0;
	always @(posedge cpu_clk or posedge cpu_rst)
		if (cpu_rst)
			domains_ready <= 0;
		else
			// R80: MMIO waits for the AI domain only. The camera domain (crs) holds just
			// the write side of the camera FIFO; without PCLK the FIFO stays empty and
			// the CPU no longer stalls at its first pose register write.
			domains_ready <= {domains_ready[0], !ars[2]};
	wire mmio_rst = cpu_rst || !domains_ready[1];
	wire pix_valid;
	wire sof;
	wire eol;
	wire overflow;
	wire [15:0] pix;
	wire [10:0] x;
	wire [9:0] y;
	// R72: the camera delivers 640x360 at ~62 fps; p2_cam_upx2 replays it as the
	// 1280x720 stream the vision pipeline and previews were built for.
	wire c_valid;
	wire c_sof;
	wire c_eol;
	wire c_overflow;
	wire up_overflow;
	wire [15:0] c_pix;
	p2_cam_stream #(
		.CAM_W(640),
		.CAM_H(360)
	) camera(
		.cam_clk(cam_clk),
		.cam_rst(crs[2]),
		.cam_en(cam_en),
		.cam_vs(cam_vs),
		.cam_data(cam_data),
		.clk(ai_clk),
		.rst(ars[2]),
		.pix_valid(c_valid),
		.pix(c_pix),
		.x(),
		.y(),
		.sof(c_sof),
		.eol(c_eol),
		.overflow(c_overflow)
	);
	p2_cam_upx2 #(
		.IN_W(640)
	) upscale(
		.clk(ai_clk),
		.rst(ars[2]),
		.in_valid(c_valid),
		.in_pix(c_pix),
		.in_sof(c_sof),
		.in_eol(c_eol),
		.pix_valid(pix_valid),
		.pix(pix),
		.x(x),
		.y(y),
		.sof(sof),
		.eol(eol),
		.overflow(up_overflow)
	);
	assign overflow = c_overflow || up_overflow;
	wire signed [31:0] roi_x0;
	wire signed [31:0] roi_y0;
	wire signed [31:0] pose_x0;
	wire signed [31:0] pose_y0;
	wire [31:0] roi_step;
	wire [31:0] pose_step;
	wire [31:0] pose_frame;
	wire [31:0] det_frame;
	wire [31:0] pcm;
	wire [31:0] dcm;
	wire [31:0] cg;
	wire [31:0] fg;
	wire [31:0] pg;
	wire [31:0] dg;
	wire roi_enable;
	wire roi_toggle;
	wire roi_ack;
	wire pt;
	wire pb;
	wire dt;
	wire db;
	wire ft;
	wire pwe;
	wire dwe;
	wire pr;
	wire dr;
	wire [7:0] flags;
	wire [7:0] dwa;
	wire [11:0] pwa;
	wire [31:0] pwd;
	wire [31:0] dwd;
	p2_vision_ai #(.AI_HZ(AI_HZ)) ai(
		.clk(ai_clk),
		.rst(ars[2]),
		.pix_valid(pix_valid),
		.pix(pix),
		.x(x),
		.y(y),
		.sof(sof),
		.eol(eol),
		.cam_overflow(overflow),
		.roi_x0(roi_x0),
		.roi_y0(roi_y0),
		.roi_step(roi_step),
		.roi_enable(roi_enable),
		.roi_toggle(roi_toggle),
		.roi_ack(roi_ack),
		.pose_release(pr),
		.det_release(dr),
		.pose_capture_ms(pcm),
		.det_capture_ms(dcm),
		.clock_gray(cg),
		.captured_gray(fg),
		.pose_drop_gray(pg),
		.det_drop_gray(dg),
		.pose_toggle(pt),
		.pose_frame(pose_frame),
		.pose_bank(pb),
		.pose_x0(pose_x0),
		.pose_y0(pose_y0),
		.pose_step(pose_step),
		.det_toggle(dt),
		.det_frame(det_frame),
		.det_bank(db),
		.frame_toggle(ft),
		.flags(flags),
		.pose_we(pwe),
		.pose_waddr(pwa),
		.pose_wdata(pwd),
		.det_we(dwe),
		.det_waddr(dwa),
		.det_wdata(dwd)
	);
	assign preview_valid = pix_valid;
	assign preview_sof = sof;
	assign preview_rst = ars[2];
	assign preview_pix = pix;
	assign preview_x = x;
	assign preview_y = y;
	assign cam_half_valid = c_valid;
	assign cam_half_sof = c_sof;
	assign cam_half_pix = c_pix;
	// R76: request register slice in front of the vision MMIO (CPU request register ->
	// MMIO decode was a 162 MHz critical family). Gated like the MMIO itself: no push and
	// not ready while mmio_rst. +1 cpu_clk cycle per request.
	wire mq_valid, mq_ready, mq_write, sq_ready;
	wire [31:0] mq_addr, mq_wdata;
	wire [3:0] mq_be;
	assign req_ready = sq_ready && !mmio_rst;
	fn_reg_slice #(.W(69)) pose_req_slice(.clk(cpu_clk), .rst(mmio_rst),
		.s_valid(req_valid && !mmio_rst), .s_ready(sq_ready),
		.s_data({req_write, req_be, req_addr, req_wdata}),
		.m_valid(mq_valid), .m_ready(mq_ready),
		.m_data({mq_write, mq_be, mq_addr, mq_wdata}));
	p2_vision_mmio #(.DISP_MUL_Q16(16384)) mmio(
		.ovl_toggle(ovl_toggle),
		.dot_en(dot_en),
		.seg_en(seg_en),
		.box_en(box_en),
		.box0(box0),
		.box1(box1),
		.dots(dots),
		.segs(segs),
		.preview_enable(preview_enable),
		.view_enable(view_enable),
		.view_hud(view_hud),
		.view_hud_toggle(view_hud_toggle),
		.view_dot_en(view_dot_en),
		.view_seg_en(view_seg_en),
		.view_dots(view_dots),
		.view_segs(view_segs),
		.clk(cpu_clk),
		.rst(mmio_rst),
		.ai_clk(ai_clk),
		.req_valid(mq_valid),
		.req_ready(mq_ready),
		.req_addr(mq_addr),
		.req_wdata(mq_wdata),
		.req_write(mq_write),
		.req_be(mq_be),
		.rsp_valid(rsp_valid),
		.rsp_ready(rsp_ready),
		.rsp_rdata(rsp_rdata),
		.rsp_error(rsp_error),
		.roi_x0(roi_x0),
		.roi_y0(roi_y0),
		.roi_step(roi_step),
		.roi_enable(roi_enable),
		.roi_toggle(roi_toggle),
		.roi_ack(roi_ack),
		.pose_release(pr),
		.det_release(dr),
		.pose_capture_ms(pcm),
		.det_capture_ms(dcm),
		.clock_gray(cg),
		.captured_gray(fg),
		.pose_drop_gray(pg),
		.det_drop_gray(dg),
		.pose_toggle(pt),
		.pose_frame(pose_frame),
		.pose_bank(pb),
		.pose_x0(pose_x0),
		.pose_y0(pose_y0),
		.pose_step(pose_step),
		.det_toggle(dt),
		.det_frame(det_frame),
		.det_bank(db),
		.frame_toggle(ft),
		.flags(flags),
		.pose_we(pwe),
		.pose_waddr(pwa),
		.pose_wdata(pwd),
		.det_we(dwe),
		.det_waddr(dwa),
		.det_wdata(dwd)
	);
endmodule
// rtl/pose/p2_ai_pll.v
// AI clock PLL: copy of p7_board_pll162 with CLKOUT0 divider 8: 27 MHz * 36 / 8 = 121.5 MHz.
module p2_ai_pll (
    
    output wire clkout0,
    
    input wire clkin1,
    
    output wire lock           
    );

    // Parameter
    
    localparam real    CLKIN_FREQ       = 27.0; //@IPC float 10.0,500.0 
    
    localparam         LOCK_MODE        = 0; //@IPC enum 0,1
    
    localparam integer STATIC_RATIOI    = 1; //@IPC int 1,80
    
    localparam integer STATIC_RATIOM    = 1; //@IPC int 1,128 
    
    localparam real    STATIC_RATIO0    = 8.0; //@IPC int 1.0000,128.0000 
        
    localparam integer STATIC_RATIO1    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO2    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO3    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO4    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO5    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO6    = 17; //@IPC int 1,128 
    
    localparam real    STATIC_RATIOF    = 36.0; //@IPC int 1.0000,128.0000 
        
    localparam integer STATIC_RATIOPHY  = 1; //@IPC int 1,128 
    
    localparam integer STATIC_DUTY0     = 8; //@IPC int 2,255
    
    localparam integer STATIC_DUTY1     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY2     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY3     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY4     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY5     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY6     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTYF     = 36; //@IPC int 2,255
    
    localparam integer STATIC_DUTYPHY   = 2; //@IPC int 2,255
    
    localparam integer STATIC_PHASE     = 0; //@IPC int 0,63 
    
    localparam integer STATIC_PHASE0    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE1    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE2    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE3    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE4    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE5    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE6    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASEF    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASEPHY  = 0; //@IPC int 0,7 
    
    localparam integer STATIC_CPHASE0   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE1   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE2   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE3   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE4   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE5   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE6   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASEF   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASEPHY = 0; //@IPC int 0,127 
    
    localparam         CLK_DPS0_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS1_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS2_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS3_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS4_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS5_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS6_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPSF_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_CAS5_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT0_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT1_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT2_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT3_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT4_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT5_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT6_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUTF_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUTPHY_SYN_EN = "FALSE"; //@IPC bool 
    
    localparam         SSC_MODE         = "DISABLE"; //@IPC enum DISABLE, DOWN_LOW, DOWN_HIGH, CENTER_LOW, CENTER_HIGH
    
    localparam real    SSC_FREQ         = 25; //@IPC int 25,250
    
    localparam         INTERNAL_FB      = "CLKOUTF"; //@IPC enum CLKOUT0,CLKOUT1,CLKOUT2,CLKOUT3,CLKOUT4,CLKOUT5,CLKOUT6,DISABLE 
    
    localparam         EXTERNAL_FB      = "DISABLE"; //@IPC enum CLKOUT0,CLKOUT1,CLKOUT2,CLKOUT3,CLKOUT4,CLKOUT5,CLKOUT6,DISABLE 
    
    localparam         BANDWIDTH        = "OPTIMIZED"; //@IPC enum OPTIMIZED,LOW,HIGH 
    
    wire clkin2;
    assign clkin2 = 1'b0;
    
    wire clkfb;
    assign clkfb = 1'b0;
    
    wire clkin_sel;
    assign clkin_sel = 1'b0;
    
    wire dps_clk;
    wire dps_en;
    wire dps_dir;
    assign dps_clk = 1'b0;
    assign dps_en = 1'b0;
    assign dps_dir = 1'b0;
        
    wire clkout0_syn;
    assign clkout0_syn = 1'b0;
    
    wire clkout1_syn;
    assign clkout1_syn = 1'b0;
    
    wire clkout2_syn;
    assign clkout2_syn = 1'b0;
    
    wire clkout3_syn;
    assign clkout3_syn = 1'b0;
    
    wire clkout4_syn;
    assign clkout4_syn = 1'b0;
    
    wire clkout5_syn;
    assign clkout5_syn = 1'b0;
        
    wire clkout6_syn;
    assign clkout6_syn = 1'b0;
        
    wire clkoutf_syn;
    assign clkoutf_syn = 1'b0;
    
    wire pll_pwd;
    assign pll_pwd = 1'b0;
    
    wire rst;
    assign rst = 1'b0;
    
    wire apb_clk;
    wire apb_rst_n;
    wire [4:0] apb_addr;
    wire apb_sel;
    wire apb_en;
    wire apb_write;
    wire [15:0] apb_wdata;

    assign apb_clk = 1'd0;
    assign apb_rst_n = 1'd0;
    assign apb_addr [4:0] = 5'd0;
    assign apb_sel = 1'd0;
    assign apb_en = 1'd0;
    assign apb_write = 1'd0;
    assign apb_wdata [15:0] = 16'd0;
    
    GTP_GPLL #(

    .CLKIN_FREQ      (CLKIN_FREQ    ),   
    .LOCK_MODE       (LOCK_MODE     ),   
    .STATIC_RATIOI   (STATIC_RATIOI ),   
    .STATIC_RATIOM   (STATIC_RATIOM ),   
    
    .STATIC_RATIO0   (STATIC_RATIO0 ),   
    .STATIC_RATIO1   (STATIC_RATIO1 ),   
    .STATIC_RATIO2   (STATIC_RATIO2 ),   
    .STATIC_RATIO3   (STATIC_RATIO3 ),   
    .STATIC_RATIO4   (STATIC_RATIO4 ),   
    
    .STATIC_RATIO5   (STATIC_RATIO5 ),   
    .STATIC_RATIO6   (STATIC_RATIO6 ),   
    
    .STATIC_RATIOF   (STATIC_RATIOF ),   
    
    .STATIC_DUTY0    (STATIC_DUTY0  ),  
    .STATIC_DUTY1    (STATIC_DUTY1  ),  
    .STATIC_DUTY2    (STATIC_DUTY2  ),  
    .STATIC_DUTY3    (STATIC_DUTY3  ),  
    .STATIC_DUTY4    (STATIC_DUTY4  ),  
    
    .STATIC_DUTY5    (STATIC_DUTY5  ),  
    .STATIC_DUTY6    (STATIC_DUTY6  ),  
    
    .STATIC_DUTYF    (STATIC_DUTYF  ),  
    
    .STATIC_PHASE    (STATIC_PHASE  ),
    
    .STATIC_PHASE0   (STATIC_PHASE0 ),
    .STATIC_PHASE1   (STATIC_PHASE1 ),
    .STATIC_PHASE2   (STATIC_PHASE2 ),
    .STATIC_PHASE3   (STATIC_PHASE3 ),
    .STATIC_PHASE4   (STATIC_PHASE4 ),
    
    .STATIC_PHASE5   (STATIC_PHASE5 ),
    .STATIC_PHASE6   (STATIC_PHASE6 ),
    
    .STATIC_PHASEF   (STATIC_PHASEF ),
    
    .STATIC_CPHASE0  (STATIC_CPHASE0),
    .STATIC_CPHASE1  (STATIC_CPHASE1),
    .STATIC_CPHASE2  (STATIC_CPHASE2),
    .STATIC_CPHASE3  (STATIC_CPHASE3),
    .STATIC_CPHASE4  (STATIC_CPHASE4),
    
    .STATIC_CPHASE5  (STATIC_CPHASE5),
    .STATIC_CPHASE6  (STATIC_CPHASE6),
    
    .STATIC_CPHASEF  (STATIC_CPHASEF),
    
    .CLK_DPS0_EN     (CLK_DPS0_EN   ),  
    .CLK_DPS1_EN     (CLK_DPS1_EN   ),  
    .CLK_DPS2_EN     (CLK_DPS2_EN   ),  
    .CLK_DPS3_EN     (CLK_DPS3_EN   ),  
    .CLK_DPS4_EN     (CLK_DPS4_EN   ),  
    .CLK_DPS5_EN     (CLK_DPS5_EN   ),  
    .CLK_DPS6_EN     (CLK_DPS6_EN   ),  
    .CLK_DPSF_EN     (CLK_DPSF_EN   ),  
    .CLK_CAS5_EN     (CLK_CAS5_EN   ),  
    
    .CLKOUT0_SYN_EN  (CLKOUT0_SYN_EN),
    .CLKOUT1_SYN_EN  (CLKOUT1_SYN_EN),
    .CLKOUT2_SYN_EN  (CLKOUT2_SYN_EN),
    .CLKOUT3_SYN_EN  (CLKOUT3_SYN_EN),
    .CLKOUT4_SYN_EN  (CLKOUT4_SYN_EN),
    
    .CLKOUT5_SYN_EN  (CLKOUT5_SYN_EN),
    .CLKOUT6_SYN_EN  (CLKOUT6_SYN_EN),
    
    .CLKOUTF_SYN_EN  (CLKOUTF_SYN_EN),
    
    .SSC_MODE       (SSC_MODE       ),
    .SSC_FREQ       (SSC_FREQ       ),
    
    .INTERNAL_FB    (INTERNAL_FB    ),
    .EXTERNAL_FB    (EXTERNAL_FB    ),
    .BANDWIDTH      (BANDWIDTH      )
    
    ) u_gpll (
    
    .CLKOUT0        (clkout0        ),
        
    .CLKOUT0N       (               ),
    
    .CLKOUT1        (               ),
    
    .CLKOUT1N       (               ),
    
    .CLKOUT2        (               ),
    
    .CLKOUT2N       (               ),
    
    .CLKOUT3        (               ),
    
    .CLKOUT3N       (               ),
    
    .CLKOUT4        (               ),
    
    .CLKOUT5        (               ),
        
    .CLKOUT6        (               ),
        
    .CLKOUTF        (               ),
    
    .CLKOUTFN       (               ),
    
    .LOCK           (lock           ),
    
    .DPS_DONE       (               ),
        
    .DPS_CLK        (dps_clk        ),
    .DPS_EN         (dps_en         ),
    .DPS_DIR        (dps_dir        ),
    
    .CLKIN1         (clkin1         ),
    
    .CLKIN2         (clkin2         ),
    
    .CLKFB          (clkfb          ),
    .CLKIN_SEL      (clkin_sel      ),
    .CLKOUT0_SYN    (clkout0_syn    ),
    .CLKOUT1_SYN    (clkout1_syn    ),
    .CLKOUT2_SYN    (clkout2_syn    ),
    .CLKOUT3_SYN    (clkout3_syn    ),
    .CLKOUT4_SYN    (clkout4_syn    ),
    
    .CLKOUT5_SYN    (clkout5_syn    ),
    .CLKOUT6_SYN    (clkout6_syn    ),
    
    .CLKOUTF_SYN    (clkoutf_syn    ),
    .PLL_PWD        (pll_pwd        ),
    .RST            (rst            ),
    
    .APB_RDATA      (               ),
    .APB_READY      (               ),
    
    .APB_CLK        (apb_clk        ),
    .APB_RST_N      (apb_rst_n      ),
    .APB_ADDR       (apb_addr[4:0]  ),
    .APB_SEL        (apb_sel        ),
    .APB_EN         (apb_en         ),
    .APB_WRITE      (apb_write      ),
    .APB_WDATA      (apb_wdata[15:0])   
);


endmodule


module fn_gpu_ddr_system_async (
	cpu_clk,
	cpu_rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_be,
	req_wdata,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	touch_state,
	touch_xy,
	touch_seq,
	touch_errors,
	touch_xy_extra,
	touch_ids,
	pix_clk,
	lcd_hs,
	lcd_vs,
	lcd_de,
	lcd_r,
	lcd_g,
	lcd_b,
	frame_toggle,
	ddr_clk,
	calibrated,
	cmd_valid,
	cmd_ready,
	cmd_write,
	cmd_addr,
	cmd_len,
	w_valid,
	w_ready,
	w_data,
	w_be,
	w_last,
	r_valid,
	r_ready,
	r_data,
	r_error,
	r_last,
	ddr_ready,
	error_count,
	axi_awaddr,
	axi_awvalid,
	axi_awready,
	axi_wdata,
	axi_wstrb,
	axi_wready,
	axi_araddr,
	axi_arvalid,
	axi_arready,
	axi_rdata,
	axi_rvalid,
	axi_rlast,
	framebuffer_underflow,
	framebuffer_error
);
	parameter FONT_INIT = "font.hex";
	parameter PAL_INIT = "palette.hex";
	parameter [31:0] CLOCK_HZ = 32'd138857143;
	input wire cpu_clk;
	input wire cpu_rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [3:0] req_be;
	input wire [31:0] req_wdata;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	input wire [31:0] touch_state;
	input wire [31:0] touch_xy;
	input wire [31:0] touch_seq;
	input wire [31:0] touch_errors;
	input wire [127:0] touch_xy_extra;
	input wire [39:0] touch_ids;
	input wire pix_clk;
	output wire lcd_hs;
	output wire lcd_vs;
	output wire lcd_de;
	output wire [7:0] lcd_r;
	output wire [7:0] lcd_g;
	output wire [7:0] lcd_b;
	output wire frame_toggle;
	input wire ddr_clk;
	input wire calibrated;
	input wire cmd_valid;
	output wire cmd_ready;
	input wire cmd_write;
	input wire [31:0] cmd_addr;
	input wire [7:0] cmd_len;
	input wire w_valid;
	output wire w_ready;
	input wire [31:0] w_data;
	input wire [3:0] w_be;
	input wire w_last;
	output wire r_valid;
	input wire r_ready;
	output wire [31:0] r_data;
	output wire r_error;
	output wire r_last;
	output wire ddr_ready;
	output wire [15:0] error_count;
	output wire [27:0] axi_awaddr;
	output wire axi_awvalid;
	input wire axi_awready;
	output wire [255:0] axi_wdata;
	output wire [31:0] axi_wstrb;
	input wire axi_wready;
	output wire [27:0] axi_araddr;
	output wire axi_arvalid;
	input wire axi_arready;
	input wire [255:0] axi_rdata;
	input wire axi_rvalid;
	input wire axi_rlast;
	output wire framebuffer_underflow;
	output wire framebuffer_error;
	wire core_reset;
	wire pix_reset;
	wire adapter_reset;
	fn_cdc_epoch_reset gpu_epoch(
		.aclk(pix_clk),
		.bclk(ddr_clk),
		.abort(adapter_reset),
		.arst(pix_reset),
		.brst(core_reset)
	);
	(* ASYNC_REG = "TRUE" *) reg [1:0] pix_up_cpu = 0;
	always @(posedge cpu_clk or posedge pix_reset)
		if (pix_reset)
			pix_up_cpu <= 0;
		else
			pix_up_cpu <= {pix_up_cpu[0], 1'b1};
	wire gpu_ready = ddr_ready && pix_up_cpu[1];
	wire gpu_req_ready;
	assign req_ready = (gpu_ready && !cpu_rst) && gpu_req_ready;
	wire cpu_valid;
	wire cpu_ready;
	wire cpu_write;
	wire cpu_rsp_valid;
	wire cpu_rsp_ready;
	wire cpu_error;
	wire [25:0] cpu_addr;
	wire [255:0] cpu_wdata;
	wire [255:0] cpu_rdata;
	wire [31:0] cpu_wstrb;
	fn_ddr_cpu_adapter adapter(
		.clk(cpu_clk),
		.rst(cpu_rst),
		.cmd_valid(cmd_valid),
		.cmd_ready(cmd_ready),
		.cmd_write(cmd_write),
		.cmd_addr(cmd_addr),
		.cmd_len(cmd_len),
		.w_valid(w_valid),
		.w_ready(w_ready),
		.w_data(w_data),
		.w_be(w_be),
		.w_last(w_last),
		.r_valid(r_valid),
		.r_ready(r_ready),
		.r_data(r_data),
		.r_error(r_error),
		.r_last(r_last),
		.ddr_ready(ddr_ready),
		.error_count(error_count),
		.core_clk(ddr_clk),
		.ddr_init_done(calibrated),
		.core_reset(adapter_reset),
		.cpu_valid(cpu_valid),
		.cpu_ready(cpu_ready),
		.cpu_write(cpu_write),
		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_wstrb(cpu_wstrb),
		.cpu_rsp_valid(cpu_rsp_valid),
		.cpu_rsp_ready(cpu_rsp_ready),
		.cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error)
	);
	fn_gpu_top_ddr_async #(
		.FONT_INIT(FONT_INIT),
		.PAL_INIT(PAL_INIT),
		.CLOCK_HZ(CLOCK_HZ)
	) gpu(
		.cpu_clk(cpu_clk),
		.cpu_rst(cpu_rst || !gpu_ready),
		.req_valid((req_valid && gpu_ready) && !cpu_rst),
		.req_ready(gpu_req_ready),
		.req_addr(req_addr),
		.req_write(req_write),
		.req_be(req_be),
		.req_wdata(req_wdata),
		.rsp_valid(rsp_valid),
		.rsp_ready(rsp_ready),
		.rsp_rdata(rsp_rdata),
		.rsp_error(rsp_error),
		.touch_state(touch_state),
		.touch_xy(touch_xy),
		.touch_seq(touch_seq),
		.touch_errors(touch_errors), .touch_xy_extra(touch_xy_extra), .touch_ids(touch_ids),
		.pix_clk(pix_clk),
		.pix_rst(pix_reset),
		.lcd_hs(lcd_hs),
		.lcd_vs(lcd_vs),
		.lcd_de(lcd_de),
		.lcd_r(lcd_r),
		.lcd_g(lcd_g),
		.lcd_b(lcd_b),
		.frame_toggle(frame_toggle),
		.ddr_clk(ddr_clk),
		.ddr_rst(core_reset),
		.cpu_valid(cpu_valid),
		.cpu_ready(cpu_ready),
		.cpu_write(cpu_write),
		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_wstrb(cpu_wstrb),
		.cpu_rsp_valid(cpu_rsp_valid),
		.cpu_rsp_ready(cpu_rsp_ready),
		.cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error),
		.axi_awaddr(axi_awaddr),
		.axi_awvalid(axi_awvalid),
		.axi_awready(axi_awready),
		.axi_wdata(axi_wdata),
		.axi_wstrb(axi_wstrb),
		.axi_wready(axi_wready),
		.axi_araddr(axi_araddr),
		.axi_arvalid(axi_arvalid),
		.axi_arready(axi_arready),
		.axi_rdata(axi_rdata),
		.axi_rvalid(axi_rvalid),
		.axi_rlast(axi_rlast),
		.framebuffer_underflow(framebuffer_underflow),
		.framebuffer_error(framebuffer_error)
	);
endmodule
module fn_gpu_top_ddr_async (
	cpu_clk,
	cpu_rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_be,
	req_wdata,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	touch_state,
	touch_xy,
	touch_seq,
	touch_errors,
	touch_xy_extra,
	touch_ids,
	pix_clk,
	pix_rst,
	lcd_hs,
	lcd_vs,
	lcd_de,
	lcd_r,
	lcd_g,
	lcd_b,
	frame_toggle,
	ddr_clk,
	ddr_rst,
	cpu_valid,
	cpu_ready,
	cpu_write,
	cpu_addr,
	cpu_wdata,
	cpu_wstrb,
	cpu_rsp_valid,
	cpu_rsp_ready,
	cpu_rdata,
	cpu_error,
	axi_awaddr,
	axi_awvalid,
	axi_awready,
	axi_wdata,
	axi_wstrb,
	axi_wready,
	axi_araddr,
	axi_arvalid,
	axi_arready,
	axi_rdata,
	axi_rvalid,
	axi_rlast,
	framebuffer_underflow,
	framebuffer_error
);
	parameter FONT_INIT = "font.hex";
	parameter PAL_INIT = "palette.hex";
	parameter [31:0] CLOCK_HZ = 32'd138857143;
	input wire cpu_clk;
	input wire cpu_rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [3:0] req_be;
	input wire [31:0] req_wdata;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	input wire [31:0] touch_state;
	input wire [31:0] touch_xy;
	input wire [31:0] touch_seq;
	input wire [31:0] touch_errors;
	input wire [127:0] touch_xy_extra;
	input wire [39:0] touch_ids;
	input wire pix_clk;
	input wire pix_rst;
	output reg lcd_hs;
	output reg lcd_vs;
	output reg lcd_de;
	output reg [7:0] lcd_r;
	output reg [7:0] lcd_g;
	output reg [7:0] lcd_b;
	output wire frame_toggle;
	input wire ddr_clk;
	input wire ddr_rst;
	input wire cpu_valid;
	output wire cpu_ready;
	input wire cpu_write;
	input wire [25:0] cpu_addr;
	input wire [255:0] cpu_wdata;
	input wire [31:0] cpu_wstrb;
	output wire cpu_rsp_valid;
	input wire cpu_rsp_ready;
	output wire [255:0] cpu_rdata;
	output wire cpu_error;
	output wire [27:0] axi_awaddr;
	output wire axi_awvalid;
	input wire axi_awready;
	output wire [255:0] axi_wdata;
	output wire [31:0] axi_wstrb;
	input wire axi_wready;
	output wire [27:0] axi_araddr;
	output wire axi_arvalid;
	input wire axi_arready;
	input wire [255:0] axi_rdata;
	input wire axi_rvalid;
	input wire axi_rlast;
	output wire framebuffer_underflow;
	output wire framebuffer_error;
	localparam FIFO_AW = 10;
	wire cmd_wen;
	wire [37:0] cmd_wdata;
	wire cmd_full;
	wire [FIFO_AW:0] cmd_level;
	wire [15:0] frame_gray;
	wire [15:0] swap_gray;
	wire gpu_idle;
	wire vblank;
	fn_mmio_hub #(
		.CLOCK_HZ(CLOCK_HZ),
		.FIFO_AW(FIFO_AW)
	) u_hub(
		.clk(cpu_clk),
		.rst(cpu_rst),
		.req_valid(req_valid),
		.req_ready(req_ready),
		.req_addr(req_addr),
		.req_write(req_write),
		.req_be(req_be),
		.req_wdata(req_wdata),
		.rsp_valid(rsp_valid),
		.rsp_ready(rsp_ready),
		.rsp_rdata(rsp_rdata),
		.rsp_error(rsp_error),
		.cmd_wen(cmd_wen),
		.cmd_wdata(cmd_wdata),
		.cmd_full(cmd_full),
		.cmd_level(cmd_level),
		.pix_frame_gray(frame_gray),
		.pix_swap_gray(swap_gray),
		.pix_idle(gpu_idle),
		.pix_vblank(vblank),
		.touch_state(touch_state),
		.touch_xy(touch_xy),
		.touch_seq(touch_seq),
		.touch_errors(touch_errors), .touch_xy_extra(touch_xy_extra), .touch_ids(touch_ids)
	);
	wire fifo_empty;
	wire fifo_ren;
	wire [37:0] fifo_rdata;
	fn_async_fifo #(
		.DW(38),
		.AW(FIFO_AW)
	) u_fifo(
		.wclk(cpu_clk),
		.wrst(cpu_rst),
		.wen(cmd_wen),
		.wdata(cmd_wdata),
		.wfull(cmd_full),
		.wlevel(cmd_level),
		.rclk(pix_clk),
		.rrst(pix_rst),
		.ren(fifo_ren),
		.rdata(fifo_rdata),
		.rempty(fifo_empty)
	);
	wire hs0;
	wire vs0;
	wire de0;
	wire frame_latch;
	wire [10:0] tx;
	wire [9:0] ty;
	fn_video_timing u_timing(
		.clk(pix_clk),
		.rst(pix_rst),
		.hs(hs0),
		.vs(vs0),
		.de(de0),
		.x(tx),
		.y(ty),
		.frame_latch(frame_latch),
		.vblank(vblank)
	);
	wire r_start;
	wire r_busy;
	wire [3:0] r_flags;
	wire [2:0] r_mode;
	wire [15:0] r_x0;
	wire [15:0] r_y0;
	wire [9:0] r_w;
	wire [9:0] r_h;
	wire [7:0] r_color;
	wire [31:0] r_u0;
	wire [31:0] r_v0;
	wire [31:0] r_dudx;
	wire [31:0] r_dvdx;
	wire [31:0] r_dudy;
	wire [31:0] r_dvdy;
	wire [6:0] r_src;
	wire [5:0] r_radius;
	wire [3:0] r_variant;
	wire pal_we;
	wire sprite_we;
	wire [17:0] sprite_addr;
	wire [7:0] sprite_data;
	wire [7:0] pal_waddr;
	wire [23:0] pal_wdata;
	wire draw_buf;
	wire disp_buf;
	wire [15:0] frame_count;
	wire swap_request;
	wire swap_done;
	fn_gpu_cmd_ddr u_cmd(
		.clk(pix_clk),
		.rst(pix_rst),
		.fifo_empty(fifo_empty),
		.fifo_ren(fifo_ren),
		.fifo_rdata(fifo_rdata),
		.frame_latch(frame_latch),
		.swap_request(swap_request),
		.swap_done(swap_done),
		.r_start(r_start),
		.r_mode(r_mode),
		.r_x0(r_x0),
		.r_y0(r_y0),
		.r_w(r_w),
		.r_h(r_h),
		.r_color(r_color),
		.r_u0(r_u0),
		.r_v0(r_v0),
		.r_dudx(r_dudx),
		.r_dvdx(r_dvdx),
		.r_dudy(r_dudy),
		.r_dvdy(r_dvdy),
		.r_src(r_src),
		.r_flags(r_flags),
		.r_radius(r_radius),
		.r_variant(r_variant),
		.r_busy(r_busy),
		.pal_we(pal_we),
		.pal_addr(pal_waddr),
		.pal_data(pal_wdata),
		.sprite_we(sprite_we),
		.sprite_addr(sprite_addr),
		.sprite_data(sprite_data),
		.draw_buf(draw_buf),
		.disp_buf(disp_buf),
		.frame_gray(frame_gray),
		.swap_gray(swap_gray),
		.frame_count(frame_count),
		.idle(gpu_idle)
	);
	wire fb_we;
	wire fb_ready;
	wire [8:0] fb_wx;
	wire [8:0] fb_wy;
	wire [7:0] fb_wdata;
	fn_raster #(.FONT_INIT(FONT_INIT)) u_raster(
		.sprite_we(sprite_we),
		.sprite_addr(sprite_addr),
		.sprite_data(sprite_data),
		.clk(pix_clk),
		.rst(pix_rst),
		.start(r_start),
		.mode(r_mode),
		.x0(r_x0),
		.y0(r_y0),
		.w(r_w),
		.h(r_h),
		.color(r_color),
		.u0(r_u0),
		.v0(r_v0),
		.dudx(r_dudx),
		.dvdx(r_dvdx),
		.dudy(r_dudy),
		.dvdy(r_dvdy),
		.src(r_src),
		.flags(r_flags),
		.radius(r_radius),
		.variant(r_variant),
		.busy(r_busy),
		.fb_ready(fb_ready),
		.fb_we(fb_we),
		.fb_x(fb_wx),
		.fb_y(fb_wy),
		.fb_data(fb_wdata)
	);
	wire [7:0] fb_index;
	wire actual_front;
	wire producer_drained;
	wire draw_drained;
	wire swap_pending;
	wire scan_index_hit;
	fn_gpu_ddr_framebuffer_async u_fb(
		.pix_clk(pix_clk),
		.pix_rst(pix_rst),
		.ddr_clk(ddr_clk),
		.ddr_rst(ddr_rst),
		.pixel_valid(fb_we),
		.pixel_ready(fb_ready),
		.draw_buffer(draw_buf),
		.pixel_x(fb_wx),
		.pixel_y(fb_wy),
		.pixel_data(fb_wdata),
		.raster_quiescent((!r_busy && !r_start) && !fb_we),
		.swap_request(swap_request),
		.swap_done(swap_done),
		.frame_latch(frame_latch),
		.vblank(vblank),
		.scan_valid(de0),
		.scan_x(tx[9:1]),
		.scan_y(ty[9:1]),
		.scan_index(fb_index),
		.scan_index_hit(scan_index_hit),
		.front_buffer(actual_front),
		.underflow(framebuffer_underflow),
		.protocol_error(framebuffer_error),
		.producer_drained(producer_drained),
		.draw_drained(draw_drained),
		.swap_pending(swap_pending),
		.cpu_valid(cpu_valid),
		.cpu_ready(cpu_ready),
		.cpu_write(cpu_write),
		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_wstrb(cpu_wstrb),
		.cpu_rsp_valid(cpu_rsp_valid),
		.cpu_rsp_ready(cpu_rsp_ready),
		.cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error),
		.axi_awaddr(axi_awaddr),
		.axi_awvalid(axi_awvalid),
		.axi_awready(axi_awready),
		.axi_wdata(axi_wdata),
		.axi_wstrb(axi_wstrb),
		.axi_wready(axi_wready),
		.axi_araddr(axi_araddr),
		.axi_arvalid(axi_arvalid),
		.axi_arready(axi_arready),
		.axi_rdata(axi_rdata),
		.axi_rvalid(axi_rvalid),
		.axi_rlast(axi_rlast)
	);
	wire [23:0] rgb;
	fn_palette #(.INIT(PAL_INIT)) u_pal(
		.clk(pix_clk),
		.we(pal_we),
		.waddr(pal_waddr),
		.wdata(pal_wdata),
		.raddr(fb_index),
		.rdata(rgb)
	);
	reg [2:0] hs_d;
	reg [2:0] vs_d;
	reg [2:0] de_d;
	always @(posedge pix_clk) begin
		hs_d <= {hs_d[1:0], hs0};
		vs_d <= {vs_d[1:0], vs0};
		de_d <= {de_d[1:0], de0};
		if (pix_rst) begin
			lcd_hs <= 1'b1;
			lcd_vs <= 1'b1;
			lcd_de <= 1'b0;
			lcd_r <= 8'd0;
			lcd_g <= 8'd0;
			lcd_b <= 8'd0;
		end
		else begin
			lcd_hs <= hs_d[2];
			lcd_vs <= vs_d[2];
			lcd_de <= de_d[2];
			lcd_r <= (de_d[2] ? rgb[23:16] : 8'd0);
			lcd_g <= (de_d[2] ? rgb[15:8] : 8'd0);
			lcd_b <= (de_d[2] ? rgb[7:0] : 8'd0);
		end
	end
	assign frame_toggle = frame_count[5];
	wire unused_ddr = &{1'b0, actual_front, producer_drained, draw_drained, swap_pending, scan_index_hit, disp_buf};
endmodule
module fn_cdc_epoch_reset (
	aclk,
	bclk,
	abort,
	arst,
	brst
);
	input wire aclk;
	input wire bclk;
	input wire abort;
	output wire arst;
	output wire brst;
	reg a_hold = 1'b1;
	reg b_hold = 1'b1;
	reg a_observed = 1'b0;
	reg b_observed = 1'b0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] b_observed_a = 2'b00;
	(* ASYNC_REG = "TRUE" *) reg [1:0] a_observed_b = 2'b00;
	assign arst = abort || a_hold;
	assign brst = abort || b_hold;
	always @(posedge aclk or posedge abort)
		if (abort) begin
			a_observed <= 1'b0;
			b_observed_a <= 2'b00;
			a_hold <= 1'b1;
		end
		else begin
			if (arst)
				a_observed <= 1'b1;
			b_observed_a <= {b_observed_a[0], b_observed};
			if (a_observed && b_observed_a[1])
				a_hold <= 1'b0;
		end
	always @(posedge bclk or posedge abort)
		if (abort) begin
			b_observed <= 1'b0;
			a_observed_b <= 2'b00;
			b_hold <= 1'b1;
		end
		else begin
			if (brst)
				b_observed <= 1'b1;
			a_observed_b <= {a_observed_b[0], a_observed};
			if (b_observed && a_observed_b[1])
				b_hold <= 1'b0;
		end
endmodule
module fn_cdc_stream (
	wclk,
	wrst,
	wvalid,
	wdata,
	wready,
	rclk,
	rrst,
	rvalid,
	rdata,
	rready
);
	parameter DW = 32;
	parameter AW = 2;
	input wire wclk;
	input wire wrst;
	input wire wvalid;
	input wire [DW - 1:0] wdata;
	output wire wready;
	input wire rclk;
	input wire rrst;
	output wire rvalid;
	output wire [DW - 1:0] rdata;
	input wire rready;
	wire full;
	wire empty;
	wire [AW:0] unused_level;
	wire [DW - 1:0] fifo_rdata;
	reg pending;
	reg held_valid;
	reg [DW - 1:0] held_data;
	wire fifo_ren = ((!rrst && !held_valid) && !pending) && !empty;
	assign wready = !wrst && !full;
	assign rvalid = !rrst && held_valid;
	assign rdata = held_data;
	fn_async_fifo #(
		.DW(DW),
		.AW(AW)
	) u_fifo(
		.wclk(wclk),
		.wrst(wrst),
		.wen(wvalid && wready),
		.wdata(wdata),
		.wfull(full),
		.wlevel(unused_level),
		.rclk(rclk),
		.rrst(rrst),
		.ren(fifo_ren),
		.rdata(fifo_rdata),
		.rempty(empty)
	);
	always @(posedge rclk)
		if (rrst) begin
			pending <= 1'b0;
			held_valid <= 1'b0;
			held_data <= {DW {1'b0}};
		end
		else begin
			pending <= fifo_ren;
			if (pending) begin
				held_data <= fifo_rdata;
				held_valid <= 1'b1;
			end
			else if (held_valid && rready)
				held_valid <= 1'b0;
		end
endmodule
module fn_ddr_row_cache_pix (
	clk,
	rst,
	calibrated,
	commit,
	commit_tag,
	row_valid,
	row_ready,
	row_slot,
	row_tag,
	row_addr,
	display_lock,
	row_done,
	row_error,
	busy,
	cache_valid,
	cache_tag0,
	cache_tag1,
	front_valid,
	front_ready,
	front_addr,
	front_rsp_valid,
	front_rsp_ready,
	front_rdata,
	front_error,
	scan_valid,
	scan_tag,
	scan_x,
	scan_rsp_valid,
	scan_data,
	scan_hit,
	underflow,
	clear_underflow,
	protocol_error
);
	parameter integer TAG_WIDTH = 17;
	input wire clk;
	input wire rst;
	input wire calibrated;
	input wire commit;
	input wire [TAG_WIDTH - 1:0] commit_tag;
	input wire row_valid;
	output wire row_ready;
	input wire row_slot;
	input wire [TAG_WIDTH - 1:0] row_tag;
	input wire [25:0] row_addr;
	input wire [1:0] display_lock;
	output reg row_done;
	output reg row_error;
	output wire busy;
	output reg [1:0] cache_valid;
	output wire [TAG_WIDTH - 1:0] cache_tag0;
	output wire [TAG_WIDTH - 1:0] cache_tag1;
	output wire front_valid;
	input wire front_ready;
	output wire [25:0] front_addr;
	input wire front_rsp_valid;
	output wire front_rsp_ready;
	input wire [255:0] front_rdata;
	input wire front_error;
	input wire scan_valid;
	input wire [TAG_WIDTH - 1:0] scan_tag;
	input wire [8:0] scan_x;
	output reg scan_rsp_valid;
	output reg [7:0] scan_data;
	output reg scan_hit;
	output reg underflow;
	input wire clear_underflow;
	output reg protocol_error;
	reg filling;
	reg outstanding;
	reg slot_q;
	reg [25:0] base_q;
	reg [3:0] beat;
	reg [TAG_WIDTH - 1:0] tags [0:1];
	reg [255:0] rows [0:31];
	wire run = calibrated && !rst;
	wire duplicate_other = cache_valid[!row_slot] && (tags[!row_slot] == row_tag);
	assign row_ready = ((run && !filling) && !display_lock[row_slot]) && !(duplicate_other && display_lock[!row_slot]);
	assign busy = filling;
	assign cache_tag0 = tags[0];
	assign cache_tag1 = tags[1];
	assign front_valid = (run && filling) && !outstanding;
	assign front_addr = base_q + {17'd0, beat, 5'd0};
	assign front_rsp_ready = (run && filling) && outstanding;
	wire hit0 = cache_valid[0] && (tags[0] == scan_tag);
	wire hit1 = cache_valid[1] && (tags[1] == scan_tag);
	always @(posedge clk)
		if (!run) begin
			filling <= 0;
			outstanding <= 0;
			slot_q <= 0;
			base_q <= 0;
			beat <= 0;
			tags[0] <= 0;
			tags[1] <= 0;
			cache_valid <= 0;
			row_done <= 0;
			row_error <= 0;
			scan_rsp_valid <= 0;
			scan_data <= 0;
			scan_hit <= 0;
			underflow <= 0;
			protocol_error <= 0;
		end
		else begin
			row_done <= 0;
			row_error <= 0;
			scan_rsp_valid <= scan_valid;
			if (clear_underflow)
				underflow <= 0;
			if (scan_valid) begin
				scan_hit <= hit0 || hit1;
				if (hit0 || hit1)
					scan_data <= rows[{!hit0, scan_x[8:5]}][{scan_x[4:0], 3'b000}+:8];
				else begin
					scan_data <= 0;
					underflow <= 1;
				end
			end
			if (row_valid && row_ready) begin
				cache_valid[row_slot] <= 0;
				if (duplicate_other)
					cache_valid[!row_slot] <= 0;
				tags[row_slot] <= row_tag;
				if ((row_addr[4:0] != 0) || (row_addr > 26'h3fffe00)) begin
					row_done <= 1;
					row_error <= 1;
				end
				else begin
					filling <= 1;
					outstanding <= 0;
					slot_q <= row_slot;
					base_q <= row_addr;
					beat <= 0;
				end
			end
			if (front_valid && front_ready)
				outstanding <= 1;
			if (front_rsp_valid && front_rsp_ready) begin
				outstanding <= 0;
				if (front_error) begin
					filling <= 0;
					row_done <= 1;
					row_error <= 1;
				end
				else begin
					rows[{slot_q, beat}] <= front_rdata;
					if (beat == 15) begin
						cache_valid[slot_q] <= 1;
						filling <= 0;
						row_done <= 1;
					end
					else
						beat <= beat + 1'b1;
				end
			end
			if (front_rsp_valid && !outstanding)
				protocol_error <= 1;
			if (commit) begin
				cache_valid[0] <= cache_valid[0] && (tags[0] == commit_tag);
				cache_valid[1] <= cache_valid[1] && (tags[1] == commit_tag);
				if (filling || row_valid)
					protocol_error <= 1;
			end
		end
endmodule
module fn_gpu_ddr_framebuffer_async (
	pix_clk,
	pix_rst,
	ddr_clk,
	ddr_rst,
	pixel_valid,
	pixel_ready,
	draw_buffer,
	pixel_x,
	pixel_y,
	pixel_data,
	raster_quiescent,
	swap_request,
	swap_done,
	frame_latch,
	vblank,
	scan_valid,
	scan_x,
	scan_y,
	scan_index,
	scan_index_hit,
	front_buffer,
	underflow,
	protocol_error,
	producer_drained,
	draw_drained,
	swap_pending,
	cpu_valid,
	cpu_ready,
	cpu_write,
	cpu_addr,
	cpu_wdata,
	cpu_wstrb,
	cpu_rsp_valid,
	cpu_rsp_ready,
	cpu_rdata,
	cpu_error,
	axi_awaddr,
	axi_awvalid,
	axi_awready,
	axi_wdata,
	axi_wstrb,
	axi_wready,
	axi_araddr,
	axi_arvalid,
	axi_arready,
	axi_rdata,
	axi_rvalid,
	axi_rlast
);
	input wire pix_clk;
	input wire pix_rst;
	input wire ddr_clk;
	input wire ddr_rst;
	input wire pixel_valid;
	output wire pixel_ready;
	input wire draw_buffer;
	input wire [8:0] pixel_x;
	input wire [8:0] pixel_y;
	input wire [7:0] pixel_data;
	input wire raster_quiescent;
	input wire swap_request;
	output reg swap_done;
	input wire frame_latch;
	input wire vblank;
	input wire scan_valid;
	input wire [8:0] scan_x;
	input wire [8:0] scan_y;
	output reg [7:0] scan_index;
	output reg scan_index_hit;
	output reg front_buffer;
	output wire underflow;
	output wire protocol_error;
	output wire producer_drained;
	output wire draw_drained;
	output wire swap_pending;
	input wire cpu_valid;
	output wire cpu_ready;
	input wire cpu_write;
	input wire [25:0] cpu_addr;
	input wire [255:0] cpu_wdata;
	input wire [31:0] cpu_wstrb;
	output wire cpu_rsp_valid;
	input wire cpu_rsp_ready;
	output wire [255:0] cpu_rdata;
	output wire cpu_error;
	output wire [27:0] axi_awaddr;
	output wire axi_awvalid;
	input wire axi_awready;
	output wire [255:0] axi_wdata;
	output wire [31:0] axi_wstrb;
	input wire axi_wready;
	output wire [27:0] axi_araddr;
	output wire axi_arvalid;
	input wire axi_arready;
	input wire [255:0] axi_rdata;
	input wire axi_rvalid;
	input wire axi_rlast;
	localparam [31:0] FB0 = 32'h03f00000;
	localparam [31:0] FB1 = 32'h03f25800;
	reg [7:0] generation;
	reg marker_sent;
	reg fence_ack;
	reg pix_error;
	wire source_open = (!pix_rst && !marker_sent) && !swap_done;
	wire [25:0] pixel_address = (draw_buffer ? FB1[25:0] : FB0[25:0]) + {8'd0, pixel_y, pixel_x};
	wire packer_ready;
	wire packed_valid;
	wire packed_ready;
	wire [25:0] packed_addr;
	wire [255:0] packed_data;
	wire [31:0] packed_strb;
	assign pixel_ready = source_open && packer_ready;
	fn_ddr_pixel_packer packer(
		.clk(pix_clk),
		.rst(pix_rst),
		.calibrated(1'b1),
		.pixel_valid(pixel_valid && source_open),
		.pixel_ready(packer_ready),
		.pixel_addr(pixel_address),
		.pixel_data(pixel_data),
		.flush(swap_request),
		.drained(producer_drained),
		.draw_valid(packed_valid),
		.draw_ready(packed_ready),
		.draw_addr(packed_addr),
		.draw_wdata(packed_data),
		.draw_wstrb(packed_strb)
	);
	wire marker_valid = ((((source_open && swap_request) && raster_quiescent) && producer_drained) && !pixel_valid) && !packed_valid;
	wire write_ready;
	wire write_valid = packed_valid || marker_valid;
	wire [322:0] write_data = {marker_valid, generation, packed_addr, packed_data, packed_strb};
	wire native_write_valid;
	wire native_write_ready;
	wire [322:0] native_write_data;
	assign packed_ready = (write_ready && !marker_sent) && !swap_done;
	fn_cdc_stream #(
		.DW(323),
		.AW(3)
	) writes(
		.wclk(pix_clk),
		.wrst(pix_rst),
		.wvalid(write_valid),
		.wready(write_ready),
		.wdata(write_data),
		.rclk(ddr_clk),
		.rrst(ddr_rst),
		.rvalid(native_write_valid),
		.rready(native_write_ready),
		.rdata(native_write_data)
	);
	wire is_marker = native_write_data[322];
	wire [7:0] write_generation = native_write_data[321:314];
	wire arb_draw_ready;
	wire arb_draw_drained;
	wire draw_retired;
	wire draw_error;
	wire arb_error;
	reg fence_wait;
	reg ddr_error;
	reg [7:0] fence_generation;
	reg [7:0] expected_generation;
	wire ack_valid = ((fence_wait && arb_draw_drained) && !ddr_error) && !arb_error;
	wire ack_ready;
	wire ack_pix_valid;
	wire ack_pix_ready;
	wire [7:0] ack_pix_generation;
	assign native_write_ready = (!ddr_error && !fence_wait) && (is_marker || arb_draw_ready);
	fn_cdc_stream #(
		.DW(8),
		.AW(2)
	) acknowledgments(
		.wclk(ddr_clk),
		.wrst(ddr_rst),
		.wvalid(ack_valid),
		.wready(ack_ready),
		.wdata(fence_generation),
		.rclk(pix_clk),
		.rrst(pix_rst),
		.rvalid(ack_pix_valid),
		.rready(ack_pix_ready),
		.rdata(ack_pix_generation)
	);
	assign ack_pix_ready = !pix_rst;
	always @(posedge ddr_clk)
		if (ddr_rst) begin
			fence_wait <= 0;
			fence_generation <= 0;
			expected_generation <= 0;
			ddr_error <= 0;
		end
		else begin
			if (native_write_valid && native_write_ready) begin
				if (write_generation != expected_generation)
					ddr_error <= 1;
				if (is_marker) begin
					fence_wait <= 1;
					fence_generation <= write_generation;
				end
			end
			if (ack_valid && ack_ready) begin
				fence_wait <= 0;
				expected_generation <= expected_generation + 8'd1;
			end
			if (draw_error || arb_error)
				ddr_error <= 1;
		end
	assign draw_drained = fence_ack;
	assign swap_pending = marker_sent;
	wire front_valid;
	wire front_ready;
	wire front_rsp_valid;
	wire front_rsp_ready;
	wire front_error;
	wire [25:0] front_addr;
	wire [255:0] front_data;
	wire dfront_valid;
	wire dfront_ready;
	wire dfront_rsp_valid;
	wire dfront_rsp_ready;
	wire dfront_error;
	wire [26:0] dfront_request;
	wire [255:0] dfront_data;
	wire [256:0] front_response;
	fn_cdc_stream #(
		.DW(27),
		.AW(2)
	) read_requests(
		.wclk(pix_clk),
		.wrst(pix_rst),
		.wvalid(front_valid),
		.wready(front_ready),
		.wdata({!vblank, front_addr}),
		.rclk(ddr_clk),
		.rrst(ddr_rst),
		.rvalid(dfront_valid),
		.rready(dfront_ready),
		.rdata(dfront_request)
	);
	fn_cdc_stream #(
		.DW(257),
		.AW(2)
	) read_responses(
		.wclk(ddr_clk),
		.wrst(ddr_rst),
		.wvalid(dfront_rsp_valid),
		.wready(dfront_rsp_ready),
		.wdata({dfront_error, dfront_data}),
		.rclk(pix_clk),
		.rrst(pix_rst),
		.rvalid(front_rsp_valid),
		.rready(front_rsp_ready),
		.rdata(front_response)
	);
	assign {front_error, front_data} = front_response;
	wire row_busy;
	wire row_done;
	wire row_error;
	wire row_ready;
	reg row_valid;
	reg row_slot;
	reg [16:0] row_tag;
	reg [25:0] row_addr;
	wire [1:0] cache_valid;
	wire [16:0] tag0;
	wire [16:0] tag1;
	wire [16:0] current_tag = {generation, scan_y};
	wire current0 = cache_valid[0] && (tag0 == current_tag);
	wire current1 = cache_valid[1] && (tag1 == current_tag);
	wire [1:0] locks = (vblank ? 2'b00 : {current1, current0});
	wire [16:0] zero_tag = {generation, 9'd0};
	wire zero0 = cache_valid[0] && (tag0 == zero_tag);
	wire zero1 = cache_valid[1] && (tag1 == zero_tag);
	wire [16:0] next_tag = {generation, scan_y + 9'd1};
	wire next_hit = (cache_valid[0] && (tag0 == next_tag)) || (cache_valid[1] && (tag1 == next_tag));
	wire [16:0] new_tag = {(swap_done ? generation : generation + 8'd1), 9'd0};
	wire new_front_ready = (cache_valid[0] && (tag0 == new_tag)) || (cache_valid[1] && (tag1 == new_tag));
	wire [25:0] visible_base = (front_buffer ? FB1[25:0] : FB0[25:0]);
	wire [25:0] pending_base = (front_buffer ? FB0[25:0] : FB1[25:0]);
	always @(*) begin
		row_valid = 0;
		row_slot = 0;
		row_tag = 0;
		row_addr = 0;
		if ((!pix_rst && !frame_latch) && !swap_done) begin
			if (vblank) begin
				if (!zero0 && !zero1) begin
					row_valid = 1;
					row_slot = 0;
					row_tag = zero_tag;
					row_addr = visible_base;
				end
				else if ((swap_pending && draw_drained) && !new_front_ready) begin
					row_valid = 1;
					row_slot = zero0;
					row_tag = new_tag;
					row_addr = pending_base;
				end
			end
			else if (scan_y < 9'd300) begin
				if (!current0 && !current1) begin
					row_valid = 1;
					row_slot = 0;
					row_tag = current_tag;
					row_addr = visible_base + {8'd0, scan_y, 9'd0};
				end
				else if ((scan_y < 9'd299) && !next_hit) begin
					row_valid = 1;
					row_slot = current0;
					row_tag = next_tag;
					row_addr = visible_base + {8'd0, scan_y + 9'd1, 9'd0};
				end
			end
		end
	end
	wire scan_response;
	wire cache_hit;
	wire [7:0] cache_index;
	wire cache_protocol_error;
	wire commit_now = ((((((((((!pix_rst && !protocol_error) && !swap_done) && frame_latch) && swap_request) && raster_quiescent) && producer_drained) && marker_sent) && fence_ack) && new_front_ready) && !row_busy) && !front_valid;
	fn_ddr_row_cache_pix cache(
		.clk(pix_clk),
		.rst(pix_rst),
		.calibrated(1'b1),
		.commit(commit_now),
		.commit_tag(new_tag),
		.row_valid(row_valid),
		.row_ready(row_ready),
		.row_slot(row_slot),
		.row_tag(row_tag),
		.row_addr(row_addr),
		.display_lock(locks),
		.row_done(row_done),
		.row_error(row_error),
		.busy(row_busy),
		.cache_valid(cache_valid),
		.cache_tag0(tag0),
		.cache_tag1(tag1),
		.front_valid(front_valid),
		.front_ready(front_ready),
		.front_addr(front_addr),
		.front_rsp_valid(front_rsp_valid),
		.front_rsp_ready(front_rsp_ready),
		.front_rdata(front_data),
		.front_error(front_error),
		.scan_valid(scan_valid),
		.scan_tag(current_tag),
		.scan_x(scan_x),
		.scan_rsp_valid(scan_response),
		.scan_data(cache_index),
		.scan_hit(cache_hit),
		.underflow(underflow),
		.clear_underflow(1'b0),
		.protocol_error(cache_protocol_error)
	);
	wire unused_swap_ready;
	wire unused_swap_pending;
	wire unused_swap_done;
	wire unused_front_buffer;
	fn_ddr_frame_arbiter #(.CPU_LIMIT_BYTES(FB0[25:0])) arbiter(
		.clk(ddr_clk),
		.rst(ddr_rst),
		.calibrated(1'b1),
		.producer_drained(1'b0),
		.producer_quiescent(1'b0),
		.cpu_valid(cpu_valid),
		.cpu_ready(cpu_ready),
		.cpu_write(cpu_write),
		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_wstrb(cpu_wstrb),
		.cpu_rsp_valid(cpu_rsp_valid),
		.cpu_rsp_ready(cpu_rsp_ready),
		.cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error),
		.front_valid(dfront_valid),
		.front_ready(dfront_ready),
		.front_urgent(dfront_request[26]),
		.front_addr(dfront_request[25:0]),
		.front_rsp_valid(dfront_rsp_valid),
		.front_rsp_ready(dfront_rsp_ready),
		.front_rdata(dfront_data),
		.front_error(dfront_error),
		.draw_valid((((native_write_valid && !is_marker) && !fence_wait) && !ddr_error) && (write_generation == expected_generation)),
		.draw_ready(arb_draw_ready),
		.draw_addr(native_write_data[313:288]),
		.draw_wdata(native_write_data[287:32]),
		.draw_wstrb(native_write_data[31:0]),
		.draw_retired(draw_retired),
		.draw_error(draw_error),
		.draw_drained(arb_draw_drained),
		.swap_valid(1'b0),
		.swap_ready(unused_swap_ready),
		.vblank_latch(1'b0),
		.front_epoch_idle(1'b0),
		.new_front_ready(1'b0),
		.swap_pending(unused_swap_pending),
		.swap_done(unused_swap_done),
		.front_buffer(unused_front_buffer),
		.protocol_error(arb_error),
		.axi_awaddr(axi_awaddr),
		.axi_awvalid(axi_awvalid),
		.axi_awready(axi_awready),
		.axi_wdata(axi_wdata),
		.axi_wstrb(axi_wstrb),
		.axi_wready(axi_wready),
		.axi_araddr(axi_araddr),
		.axi_arvalid(axi_arvalid),
		.axi_arready(axi_arready),
		.axi_rdata(axi_rdata),
		.axi_rvalid(axi_rvalid),
		.axi_rlast(axi_rlast)
	);
	(* ASYNC_REG = "TRUE" *) reg [1:0] ddr_error_pix;
	always @(posedge pix_clk)
		if (pix_rst) begin
			generation <= 0;
			front_buffer <= 0;
			swap_done <= 0;
			marker_sent <= 0;
			fence_ack <= 0;
			scan_index <= 0;
			scan_index_hit <= 0;
			pix_error <= 0;
			ddr_error_pix <= 0;
		end
		else begin
			ddr_error_pix <= {ddr_error_pix[0], ddr_error};
			swap_done <= 0;
			if (marker_valid && write_ready)
				marker_sent <= 1;
			if (ack_pix_valid && ack_pix_ready) begin
				if ((!marker_sent || fence_ack) || (ack_pix_generation != generation))
					pix_error <= 1;
				else
					fence_ack <= 1;
			end
			if (commit_now) begin
				front_buffer <= !front_buffer;
				generation <= generation + 8'd1;
				swap_done <= 1;
			end
			if (swap_done) begin
				marker_sent <= 0;
				fence_ack <= 0;
			end
			scan_index <= cache_index;
			scan_index_hit <= scan_response && cache_hit;
			if (row_error)
				pix_error <= 1;
		end
	assign protocol_error = (pix_error || cache_protocol_error) || ddr_error_pix[1];
	wire unused = &{1'b0, row_done, row_ready, draw_retired, unused_swap_ready, unused_swap_pending, unused_swap_done, unused_front_buffer};
endmodule
module fn_ddr_frame_arbiter (
	clk,
	rst,
	calibrated,
	producer_drained,
	producer_quiescent,
	cpu_valid,
	cpu_ready,
	cpu_write,
	cpu_addr,
	cpu_wdata,
	cpu_wstrb,
	cpu_rsp_valid,
	cpu_rsp_ready,
	cpu_rdata,
	cpu_error,
	front_valid,
	front_ready,
	front_urgent,
	front_addr,
	front_rsp_valid,
	front_rsp_ready,
	front_rdata,
	front_error,
	draw_valid,
	draw_ready,
	draw_addr,
	draw_wdata,
	draw_wstrb,
	draw_retired,
	draw_error,
	draw_drained,
	swap_valid,
	swap_ready,
	vblank_latch,
	front_epoch_idle,
	new_front_ready,
	swap_pending,
	swap_done,
	front_buffer,
	protocol_error,
	axi_awaddr,
	axi_awvalid,
	axi_awready,
	axi_wdata,
	axi_wstrb,
	axi_wready,
	axi_araddr,
	axi_arvalid,
	axi_arready,
	axi_rdata,
	axi_rvalid,
	axi_rlast
);
	parameter integer DRAW_DEPTH = 4;
	parameter integer GUARD_CYCLES = 15;
	parameter integer URGENT_MAX = 2;
	parameter [25:0] CPU_LIMIT_BYTES = 26'h3f00000;
	input wire clk;
	input wire rst;
	input wire calibrated;
	input wire producer_drained;
	input wire producer_quiescent;
	input wire cpu_valid;
	output wire cpu_ready;
	input wire cpu_write;
	input wire [25:0] cpu_addr;
	input wire [255:0] cpu_wdata;
	input wire [31:0] cpu_wstrb;
	output reg cpu_rsp_valid;
	input wire cpu_rsp_ready;
	output reg [255:0] cpu_rdata;
	output reg cpu_error;
	input wire front_valid;
	output wire front_ready;
	input wire front_urgent;
	input wire [25:0] front_addr;
	output reg front_rsp_valid;
	input wire front_rsp_ready;
	output reg [255:0] front_rdata;
	output reg front_error;
	input wire draw_valid;
	output wire draw_ready;
	input wire [25:0] draw_addr;
	input wire [255:0] draw_wdata;
	input wire [31:0] draw_wstrb;
	output reg draw_retired;
	output reg draw_error;
	output wire draw_drained;
	input wire swap_valid;
	output wire swap_ready;
	input wire vblank_latch;
	input wire front_epoch_idle;
	input wire new_front_ready;
	output reg swap_pending;
	output reg swap_done;
	output reg front_buffer;
	output reg protocol_error;
	output wire [27:0] axi_awaddr;
	output wire axi_awvalid;
	input wire axi_awready;
	output wire [255:0] axi_wdata;
	output wire [31:0] axi_wstrb;
	input wire axi_wready;
	output wire [27:0] axi_araddr;
	output wire axi_arvalid;
	input wire axi_arready;
	input wire [255:0] axi_rdata;
	input wire axi_rvalid;
	input wire axi_rlast;
	localparam integer PW = (DRAW_DEPTH <= 1 ? 1 : $clog2(DRAW_DEPTH));
	localparam integer CW = $clog2(DRAW_DEPTH + 1);
	localparam [2:0] IDLE = 0;
	localparam [2:0] WRITE = 1;
	localparam [2:0] GUARD = 2;
	localparam [2:0] RADDR = 3;
	localparam [2:0] RDATA = 4;
	localparam [2:0] VERIFY_ADDR = 5;
	localparam [2:0] VERIFY_DATA = 6;
	localparam [1:0] CPU = 0;
	localparam [1:0] FRONT = 1;
	localparam [1:0] DRAW = 2;
	localparam [1:0] NONE = 3;
	reg [2:0] state;
	reg [1:0] owner;
	reg [1:0] rr;
	reg [1:0] select_owner;
	reg [23:0] dq_address_q;
	reg [255:0] data_q;
	reg [31:0] strb_q;
	reg aw_seen;
	reg w_seen;
	integer guard_left;
	integer urgent_run;
	reg nonfront_turn;
	reg [25:0] draw_addresses [0:DRAW_DEPTH - 1];
	reg [255:0] draw_data [0:DRAW_DEPTH - 1];
	reg [31:0] draw_strb [0:DRAW_DEPTH - 1];
	reg [PW - 1:0] wp;
	reg [PW - 1:0] rp;
	reg [CW - 1:0] count;
	wire active = calibrated && !rst;
	wire run = active && !protocol_error;
	wire cpu_eligible = cpu_valid && !cpu_rsp_valid;
	wire front_eligible = front_valid && !front_rsp_valid;
	reg verify_pending;
	integer verify_wait;
	reg [23:0] verify_address;
	reg [255:0] verify_data;
	reg [31:0] verify_strb;
	wire verify_eligible = verify_pending && (verify_wait == 0);
	wire draw_eligible = verify_eligible || (!verify_pending && (count != 0));
	wire select_verify = (select_owner == DRAW) && verify_eligible;
	always @(*) begin
		select_owner = NONE;
		if ((state == IDLE) && run) begin
			if ((front_eligible && front_urgent) && ((urgent_run < URGENT_MAX) || (!cpu_eligible && !draw_eligible)))
				select_owner = FRONT;
			else if (((front_eligible && !front_urgent) && (urgent_run < URGENT_MAX)) && (((rr == FRONT) || ((rr == CPU) && !cpu_eligible)) || (((rr == DRAW) && !draw_eligible) && !cpu_eligible)))
				select_owner = FRONT;
			else if (cpu_eligible || draw_eligible) begin
				if (cpu_eligible && draw_eligible)
					select_owner = (nonfront_turn ? DRAW : CPU);
				else
					select_owner = (cpu_eligible ? CPU : DRAW);
			end
			else if (front_eligible)
				select_owner = FRONT;
		end
	end
	assign cpu_ready = select_owner == CPU;
	assign front_ready = select_owner == FRONT;
	assign swap_ready = ((run && !swap_pending) && producer_drained) && producer_quiescent;
	function automatic signed [CW - 1:0] sv2v_cast_3D2D3_signed;
		input reg signed [CW - 1:0] inp;
		sv2v_cast_3D2D3_signed = inp;
	endfunction
	assign draw_ready = ((run && !swap_pending) && !(swap_valid && swap_ready)) && (count < sv2v_cast_3D2D3_signed(DRAW_DEPTH));
	wire enqueue = draw_valid && draw_ready;
	wire dequeue = (select_owner == DRAW) && !select_verify;
	assign draw_drained = ((run && (count == 0)) && !verify_pending) && !((state != IDLE) && (owner == DRAW));
	assign axi_awaddr = {4'b0000, dq_address_q};
	assign axi_araddr = {4'b0000, dq_address_q};
	assign axi_awvalid = (run && (state == WRITE)) && !aw_seen;
	assign axi_arvalid = run && ((state == RADDR) || (state == VERIFY_ADDR));
	assign axi_wdata = (run && (state == WRITE) ? data_q : 256'd0);
	assign axi_wstrb = ((run && (state == WRITE)) && !w_seen ? strb_q : 32'd0);
	wire aw_now = axi_awvalid && axi_awready;
	wire w_now = ((run && (state == WRITE)) && !w_seen) && axi_wready;
	wire read_now = (run && axi_rvalid) && (((state == RDATA) || (state == VERIFY_DATA)) || (((state == RADDR) || (state == VERIFY_ADDR)) && axi_arready));
	wire swap_can_commit = (((((producer_drained && producer_quiescent) && draw_drained) && (state == IDLE)) && !front_rsp_valid) && front_epoch_idle) && new_front_ready;
	reg verify_mismatch;
	integer verify_lane;
	always @(*) begin
		verify_mismatch = 0;
		for (verify_lane = 0; verify_lane < 32; verify_lane = verify_lane + 1)
			if (strb_q[verify_lane] && (axi_rdata[verify_lane * 8+:8] !== data_q[verify_lane * 8+:8]))
				verify_mismatch = 1;
	end
	function automatic signed [PW - 1:0] sv2v_cast_D1740_signed;
		input reg signed [PW - 1:0] inp;
		sv2v_cast_D1740_signed = inp;
	endfunction
	function automatic [PW - 1:0] next_ptr;
		input [PW - 1:0] p;
		if (p == sv2v_cast_D1740_signed(DRAW_DEPTH - 1))
			next_ptr = 0;
		else
			next_ptr = p + 1'b1;
	endfunction
	task automatic retire_write;
		begin
			if (owner == CPU) begin
				cpu_rsp_valid <= 1;
				cpu_rdata <= 0;
				cpu_error <= 0;
			end
			else begin
				draw_retired <= 1;
				draw_error <= 0;
			end
			state <= IDLE;
		end
	endtask
	always @(posedge clk)
		if (!active) begin
			state <= IDLE;
			owner <= NONE;
			rr <= CPU;
			dq_address_q <= 0;
			data_q <= 0;
			strb_q <= 0;
			aw_seen <= 0;
			w_seen <= 0;
			guard_left <= 0;
			urgent_run <= 0;
			nonfront_turn <= 0;
			wp <= 0;
			rp <= 0;
			count <= 0;
			verify_pending <= 0;
			verify_wait <= 0;
			verify_address <= 0;
			verify_data <= 0;
			verify_strb <= 0;
			cpu_rsp_valid <= 0;
			cpu_rdata <= 0;
			cpu_error <= 0;
			front_rsp_valid <= 0;
			front_rdata <= 0;
			front_error <= 0;
			draw_retired <= 0;
			draw_error <= 0;
			swap_pending <= 0;
			swap_done <= 0;
			front_buffer <= 0;
			protocol_error <= 0;
		end
		else begin
			draw_retired <= 0;
			draw_error <= 0;
			swap_done <= 0;
			if (verify_pending && (verify_wait > 0))
				verify_wait <= verify_wait - 1;
			if (cpu_rsp_valid && cpu_rsp_ready)
				cpu_rsp_valid <= 0;
			if (front_rsp_valid && front_rsp_ready)
				front_rsp_valid <= 0;
			if (swap_valid && swap_ready)
				swap_pending <= 1;
			if ((((swap_pending && vblank_latch) && swap_can_commit) && (select_owner != FRONT)) && (select_owner != DRAW)) begin
				front_buffer <= !front_buffer;
				swap_done <= 1;
				swap_pending <= 0;
			end
			if (enqueue) begin
				draw_addresses[wp] <= draw_addr;
				draw_data[wp] <= draw_wdata;
				draw_strb[wp] <= draw_wstrb;
				wp <= next_ptr(wp);
			end
			if (dequeue)
				rp <= next_ptr(rp);
			case ({enqueue, dequeue})
				2'b10: count <= count + 1'b1;
				2'b01: count <= count - 1'b1;
				default:
					;
			endcase
			if (axi_rvalid && !read_now)
				protocol_error <= 1;
			if (front_epoch_idle && front_valid)
				protocol_error <= 1;
			if (!protocol_error) begin
				case (state)
					IDLE:
						if (select_owner != NONE) begin
							owner <= select_owner;
							rr <= (select_owner == DRAW ? CPU : select_owner + 1'b1);
							if (select_owner == FRONT) begin
								if (urgent_run < URGENT_MAX)
									urgent_run <= urgent_run + 1;
							end
							else
								urgent_run <= 0;
							if (select_owner != FRONT)
								nonfront_turn <= select_owner == CPU;
							aw_seen <= 0;
							w_seen <= 0;
							if (select_owner == CPU) begin
								dq_address_q <= cpu_addr[25:2];
								data_q <= cpu_wdata;
								strb_q <= cpu_wstrb;
								if ((cpu_addr[4:0] != 0) || (cpu_addr >= CPU_LIMIT_BYTES)) begin
									cpu_rsp_valid <= 1;
									cpu_rdata <= 0;
									cpu_error <= 1;
								end
								else
									state <= (cpu_write ? WRITE : RADDR);
							end
							else if (select_owner == FRONT) begin
								dq_address_q <= front_addr[25:2];
								data_q <= 0;
								strb_q <= 0;
								if (front_addr[4:0] != 0) begin
									front_rsp_valid <= 1;
									front_rdata <= 0;
									front_error <= 1;
								end
								else
									state <= RADDR;
							end
							else if (select_verify) begin
								dq_address_q <= verify_address;
								data_q <= verify_data;
								strb_q <= verify_strb;
								state <= VERIFY_ADDR;
							end
							else begin
								dq_address_q <= draw_addresses[rp][25:2];
								data_q <= draw_data[rp];
								strb_q <= draw_strb[rp];
								if (draw_addresses[rp][4:0] != 0) begin
									draw_retired <= 1;
									draw_error <= 1;
								end
								else
									state <= WRITE;
							end
						end
					WRITE: begin
						if (aw_now)
							aw_seen <= 1;
						if (w_now)
							w_seen <= 1;
						if ((aw_seen || aw_now) && (w_seen || w_now)) begin
							if ((owner == DRAW) && (strb_q != 0)) begin
								verify_pending <= 1;
								verify_wait <= GUARD_CYCLES;
								verify_address <= dq_address_q;
								verify_data <= data_q;
								verify_strb <= strb_q;
								state <= IDLE;
							end
							else begin
								guard_left <= GUARD_CYCLES;
								state <= GUARD;
							end
						end
					end
					GUARD:
						if (guard_left <= 1) begin
							if ((owner == DRAW) && (strb_q != 0))
								state <= VERIFY_ADDR;
							else
								retire_write;
						end
						else
							guard_left <= guard_left - 1;
					VERIFY_ADDR:
						if (axi_arready && !axi_rvalid)
							state <= VERIFY_DATA;
					RADDR:
						if (axi_arready && !axi_rvalid)
							state <= RDATA;
					default:
						;
				endcase
				if (read_now) begin
					if (owner == DRAW) begin
						verify_pending <= 0;
						draw_retired <= 1;
						draw_error <= !axi_rlast || verify_mismatch;
						if (!axi_rlast || verify_mismatch)
							protocol_error <= 1;
					end
					else if (owner == CPU) begin
						cpu_rsp_valid <= 1;
						cpu_rdata <= axi_rdata;
						cpu_error <= !axi_rlast;
					end
					else begin
						front_rsp_valid <= 1;
						front_rdata <= axi_rdata;
						front_error <= !axi_rlast;
					end
					if (!axi_rlast)
						protocol_error <= 1;
					state <= IDLE;
				end
			end
		end
	initial if (((DRAW_DEPTH < 1) || (GUARD_CYCLES < 0)) || (URGENT_MAX < 1)) begin
		$display("Fatal [%0t] F:/Codex_workplace/2026-10-07/task-28/overlap_candidate/rtl/fn_ddr_frame_arbiter.sv:237:13 - fn_ddr_frame_arbiter.<unnamed_block>.<unnamed_block>\n msg: ", $time, "invalid arbiter parameters");
		$finish(1);
	end
endmodule
module fn_ddr_pixel_packer (
	clk,
	rst,
	calibrated,
	pixel_valid,
	pixel_ready,
	pixel_addr,
	pixel_data,
	flush,
	drained,
	draw_valid,
	draw_ready,
	draw_addr,
	draw_wdata,
	draw_wstrb
);
	parameter integer IDLE_FLUSH_CYCLES = 2;
	parameter integer ENTRIES = 8;
	input wire clk;
	input wire rst;
	input wire calibrated;
	input wire pixel_valid;
	output wire pixel_ready;
	input wire [25:0] pixel_addr;
	input wire [7:0] pixel_data;
	input wire flush;
	output wire drained;
	output wire draw_valid;
	input wire draw_ready;
	output wire [25:0] draw_addr;
	output wire [255:0] draw_wdata;
	output wire [31:0] draw_wstrb;
	localparam integer PW = (ENTRIES <= 1 ? 1 : $clog2(ENTRIES));
	reg [ENTRIES - 1:0] occupied;
	reg [20:0] tags [0:ENTRIES - 1];
	reg [255:0] data [0:ENTRIES - 1];
	reg [31:0] strobe [0:ENTRIES - 1];
	reg [PW - 1:0] victim;
	reg emit_pending;
	reg [PW - 1:0] emit_slot;
	reg hit;
	reg free_found;
	reg valid_found;
	reg [PW - 1:0] hit_slot;
	reg [PW - 1:0] free_slot;
	reg [PW - 1:0] flush_slot;
	integer k;
	function automatic signed [PW - 1:0] sv2v_cast_D1740_signed;
		input reg signed [PW - 1:0] inp;
		sv2v_cast_D1740_signed = inp;
	endfunction
	always @(*) begin
		hit = 0;
		free_found = 0;
		valid_found = 0;
		hit_slot = 0;
		free_slot = 0;
		flush_slot = 0;
		for (k = ENTRIES - 1; k >= 0; k = k - 1)
			begin
				if (occupied[k] && (tags[k] == pixel_addr[25:5])) begin
					hit = 1;
					hit_slot = sv2v_cast_D1740_signed(k);
				end
				if (!occupied[k]) begin
					free_found = 1;
					free_slot = sv2v_cast_D1740_signed(k);
				end
				if (occupied[k]) begin
					valid_found = 1;
					flush_slot = sv2v_cast_D1740_signed(k);
				end
			end
	end
	wire run = calibrated && !rst;
	wire need_evict = (pixel_valid && !hit) && !free_found;
	wire [PW - 1:0] output_slot = (emit_pending ? emit_slot : (flush ? flush_slot : victim));
	wire [PW - 1:0] input_slot = (hit ? hit_slot : free_slot);
	assign draw_valid = run && (emit_pending || (valid_found && (flush || need_evict)));
	assign pixel_ready = ((run && !flush) && !draw_valid) && (hit || free_found);
	assign drained = run && !valid_found;
	assign draw_addr = {tags[output_slot], 5'b00000};
	assign draw_wdata = data[output_slot];
	assign draw_wstrb = strobe[output_slot];
	integer j;
	always @(posedge clk)
		if (!run) begin
			occupied <= 0;
			victim <= 0;
			emit_pending <= 0;
			emit_slot <= 0;
			for (j = 0; j < ENTRIES; j = j + 1)
				begin
					tags[j] <= 0;
					data[j] <= 0;
					strobe[j] <= 0;
				end
		end
		else if (draw_valid && draw_ready) begin
			occupied[output_slot] <= 0;
			strobe[output_slot] <= 0;
			emit_pending <= 0;
			victim <= (output_slot == sv2v_cast_D1740_signed(ENTRIES - 1) ? 0 : output_slot + 1'b1);
		end
		else if (draw_valid && !draw_ready) begin
			emit_pending <= 1;
			emit_slot <= output_slot;
		end
		else if (pixel_valid && pixel_ready) begin
			occupied[input_slot] <= 1;
			tags[input_slot] <= pixel_addr[25:5];
			if (!hit) begin
				data[input_slot] <= 0;
				strobe[input_slot] <= 32'b00000000000000000000000000000001 << pixel_addr[4:0];
			end
			else
				strobe[input_slot][pixel_addr[4:0]] <= 1;
			data[input_slot][{pixel_addr[4:0], 3'b000}+:8] <= pixel_data;
		end
	initial if (ENTRIES < 1) begin
		$display("Fatal [%0t] F:/Codex_workplace/2026-10-07/task-28/coalescing_candidate/rtl/fn_ddr_pixel_packer.sv:64:23 - fn_ddr_pixel_packer.<unnamed_block>\n msg: ", $time, "invalid write combiner size");
		$finish(1);
	end
endmodule
module fn_gpu_cmd_ddr (
	clk,
	rst,
	fifo_empty,
	fifo_ren,
	fifo_rdata,
	frame_latch,
	swap_request,
	swap_done,
	r_start,
	r_mode,
	r_x0,
	r_y0,
	r_w,
	r_h,
	r_color,
	r_u0,
	r_v0,
	r_dudx,
	r_dvdx,
	r_dudy,
	r_dvdy,
	r_src,
	r_flags,
	r_radius,
	r_variant,
	r_busy,
	pal_we,
	sprite_we,
	sprite_addr,
	sprite_data,
	pal_addr,
	pal_data,
	draw_buf,
	disp_buf,
	frame_gray,
	swap_gray,
	frame_count,
	idle
);
	input wire clk;
	input wire rst;
	input wire fifo_empty;
	output wire fifo_ren;
	input wire [37:0] fifo_rdata;
	input wire frame_latch;
	output wire swap_request;
	input wire swap_done;
	output reg r_start;
	output reg [2:0] r_mode;
	output reg [15:0] r_x0;
	output reg [15:0] r_y0;
	output reg [9:0] r_w;
	output reg [9:0] r_h;
	output reg [7:0] r_color;
	output reg [31:0] r_u0;
	output reg [31:0] r_v0;
	output reg [31:0] r_dudx;
	output reg [31:0] r_dvdx;
	output reg [31:0] r_dudy;
	output reg [31:0] r_dvdy;
	output reg [6:0] r_src;
	output reg [3:0] r_flags;
	output reg [5:0] r_radius;
	output reg [3:0] r_variant;
	input wire r_busy;
	output reg pal_we;
	output reg sprite_we;
	output reg [17:0] sprite_addr;
	output reg [7:0] sprite_data;
	output reg [7:0] pal_addr;
	output reg [23:0] pal_data;
	output reg draw_buf;
	output reg disp_buf;
	output reg [15:0] frame_gray;
	output reg [15:0] swap_gray;
	output reg [15:0] frame_count;
	output reg idle;
	localparam [2:0] M_FILL = 3'd0;
	localparam [2:0] M_BG = 3'd1;
	localparam [2:0] M_SPRITE = 3'd2;
	localparam [2:0] M_GLYPH = 3'd3;
	localparam [2:0] M_CIRCLE = 3'd4;
	localparam [5:0] R_COLOR = 6'd1;
	localparam [5:0] R_DST = 6'd2;
	localparam [5:0] R_SIZE = 6'd3;
	localparam [5:0] R_U0 = 6'd4;
	localparam [5:0] R_V0 = 6'd5;
	localparam [5:0] R_DUDX = 6'd6;
	localparam [5:0] R_DVDX = 6'd7;
	localparam [5:0] R_DUDY = 6'd8;
	localparam [5:0] R_DVDY = 6'd9;
	localparam [5:0] R_FLAGS = 6'd10;
	localparam [5:0] C_CLEAR = 6'd16;
	localparam [5:0] C_BG = 6'd17;
	localparam [5:0] C_RECT = 6'd18;
	localparam [5:0] C_SPRITE = 6'd19;
	localparam [5:0] C_GLYPH = 6'd20;
	localparam [5:0] C_TEXT = 6'd21;
	localparam [5:0] C_CIRCLE = 6'd22;
	localparam [5:0] C_PSET = 6'd23;
	localparam [5:0] C_PALETTE = 6'd24;
	localparam [5:0] C_SWAP = 6'd25;
	localparam [5:0] C_UPLOAD = 6'd26;
	localparam [1:0] S_IDLE = 2'd0;
	localparam [1:0] S_EXEC = 2'd1;
	localparam [1:0] S_WAIT = 2'd2;
	localparam [1:0] S_SWAP = 2'd3;
	reg [1:0] state;
	reg disp_req;
	reg [15:0] swap_count;
	reg [7:0] p_color;
	reg [15:0] p_x0;
	reg [15:0] p_y0;
	reg [9:0] p_w;
	reg [9:0] p_h;
	reg [31:0] p_u0;
	reg [31:0] p_v0;
	reg [31:0] p_dudx;
	reg [31:0] p_dvdx;
	reg [31:0] p_dudy;
	reg [31:0] p_dvdy;
	reg [3:0] p_flags;
	wire [5:0] idx = fifo_rdata[37:32];
	wire [31:0] d = fifo_rdata[31:0];
	assign swap_request = state == S_SWAP;
	assign fifo_ren = (state == S_IDLE) && !fifo_empty;
	wire [1:0] t_sc = d[26:25];
	wire [2:0] t_sc1 = {1'b0, t_sc} + 3'd1;
	reg [31:0] t_inv;
	always @(*)
		case (t_sc)
			2'd0: t_inv = 32'h00010000;
			2'd1: t_inv = 32'h00008000;
			2'd2: t_inv = 32'h00005556;
			default: t_inv = 32'h00004000;
		endcase
	wire [5:0] c_r = d[23:18];
	wire [15:0] c_x0 = {7'd0, d[8:0]} - {10'd0, c_r};
	wire [15:0] c_y0 = {7'd0, d[17:9]} - {10'd0, c_r};
	wire [9:0] c_w = {3'd0, c_r, 1'b1};
	always @(posedge clk)
		if (rst) begin
			state <= S_IDLE;
			r_start <= 1'b0;
			pal_we <= 1'b0;
			sprite_we <= 1'b0;
			sprite_addr <= 18'd0;
			sprite_data <= 8'd0;
			draw_buf <= 1'b1;
			disp_buf <= 1'b0;
			disp_req <= 1'b0;
			frame_count <= 16'd0;
			swap_count <= 16'd0;
			frame_gray <= 16'd0;
			swap_gray <= 16'd0;
			idle <= 1'b0;
			p_color <= 8'd0;
			p_x0 <= 16'd0;
			p_y0 <= 16'd0;
			p_w <= 10'd0;
			p_h <= 10'd0;
			p_u0 <= 32'd0;
			p_v0 <= 32'd0;
			p_dudx <= 32'h00010000;
			p_dvdx <= 32'd0;
			p_dudy <= 32'd0;
			p_dvdy <= 32'h00010000;
			p_flags <= 4'd0;
			r_mode <= M_FILL;
			r_x0 <= 16'd0;
			r_y0 <= 16'd0;
			r_w <= 10'd0;
			r_h <= 10'd0;
			r_color <= 8'd0;
			r_u0 <= 32'd0;
			r_v0 <= 32'd0;
			r_dudx <= 32'd0;
			r_dvdx <= 32'd0;
			r_dudy <= 32'd0;
			r_dvdy <= 32'd0;
			r_src <= 7'd0;
			r_flags <= 4'd0;
			r_radius <= 6'd0;
			r_variant <= 4'd0;
		end
		else begin
			r_start <= 1'b0;
			pal_we <= 1'b0;
			sprite_we <= 1'b0;
			frame_gray <= frame_count ^ (frame_count >> 1);
			swap_gray <= swap_count ^ (swap_count >> 1);
			idle <= (((state == S_IDLE) && fifo_empty) && !r_busy) && !r_start;
			if (frame_latch)
				frame_count <= frame_count + 16'd1;
			case (state)
				S_IDLE:
					if (!fifo_empty)
						state <= S_EXEC;
				S_EXEC: begin
					state <= S_IDLE;
					case (idx)
						R_COLOR: p_color <= d[7:0];
						R_DST: begin
							p_x0 <= d[15:0];
							p_y0 <= d[31:16];
						end
						R_SIZE: begin
							p_w <= d[9:0];
							p_h <= d[25:16];
						end
						R_U0: p_u0 <= d;
						R_V0: p_v0 <= d;
						R_DUDX: p_dudx <= d;
						R_DVDX: p_dvdx <= d;
						R_DUDY: p_dudy <= d;
						R_DVDY: p_dvdy <= d;
						R_FLAGS: p_flags <= d[3:0];
						C_CLEAR, C_BG: begin
							r_mode <= (idx == C_BG ? M_BG : M_FILL);
							r_x0 <= 16'd0;
							r_y0 <= 16'd0;
							r_w <= 10'd512;
							r_h <= 10'd300;
							r_color <= d[7:0];
							r_variant <= d[3:0];
							r_flags <= 4'd0;
							r_start <= 1'b1;
							state <= S_WAIT;
						end
						C_RECT: begin
							r_mode <= M_FILL;
							r_x0 <= p_x0;
							r_y0 <= p_y0;
							r_w <= p_w;
							r_h <= p_h;
							r_color <= p_color;
							r_flags <= {p_flags[3], 3'b000};
							r_start <= 1'b1;
							state <= S_WAIT;
						end
						C_SPRITE, C_GLYPH: begin
							r_mode <= (idx == C_SPRITE ? M_SPRITE : M_GLYPH);
							r_x0 <= p_x0;
							r_y0 <= p_y0;
							r_w <= p_w;
							r_h <= p_h;
							r_color <= p_color;
							r_u0 <= p_u0;
							r_v0 <= p_v0;
							r_dudx <= p_dudx;
							r_dvdx <= p_dvdx;
							r_dudy <= p_dudy;
							r_dvdy <= p_dvdy;
							r_src <= (idx == C_SPRITE ? {1'b0, d[5:0]} : d[6:0]);
							r_flags <= (idx == C_SPRITE ? p_flags : 4'd0);
							r_start <= 1'b1;
							state <= S_WAIT;
						end
						C_TEXT: begin
							r_mode <= M_GLYPH;
							r_x0 <= {7'd0, d[8:0]};
							r_y0 <= {7'd0, d[17:9]};
							r_w <= {3'd0, t_sc1, 4'd0};
							r_h <= {3'd0, t_sc1, 4'd0};
							r_color <= p_color;
							r_u0 <= 32'd0;
							r_v0 <= 32'd0;
							r_dudx <= t_inv;
							r_dvdx <= 32'd0;
							r_dudy <= 32'd0;
							r_dvdy <= t_inv;
							r_src <= d[24:18];
							r_flags <= 4'd0;
							r_start <= 1'b1;
							state <= S_WAIT;
						end
						C_CIRCLE: begin
							r_mode <= M_CIRCLE;
							r_x0 <= c_x0;
							r_y0 <= c_y0;
							r_w <= c_w;
							r_h <= c_w;
							r_radius <= c_r;
							r_color <= d[31:24];
							r_flags <= 4'd0;
							r_start <= 1'b1;
							state <= S_WAIT;
						end
						C_PSET: begin
							r_mode <= M_FILL;
							r_x0 <= {7'd0, d[8:0]};
							r_y0 <= {7'd0, d[17:9]};
							r_w <= 10'd1;
							r_h <= 10'd1;
							r_color <= d[31:24];
							r_flags <= 4'd0;
							r_start <= 1'b1;
							state <= S_WAIT;
						end
						C_PALETTE: begin
							pal_we <= 1'b1;
							pal_addr <= d[31:24];
							pal_data <= d[23:0];
						end
						C_UPLOAD: begin
							sprite_we <= 1'b1;
							sprite_addr <= d[25:8];
							sprite_data <= d[7:0];
						end
						C_SWAP: begin
							disp_req <= draw_buf;
							state <= S_SWAP;
						end
						default:
							;
					endcase
				end
				S_WAIT:
					if (!r_start && !r_busy)
						state <= S_IDLE;
				S_SWAP:
					if (swap_done) begin
						disp_buf <= disp_req;
						draw_buf <= ~draw_buf;
						swap_count <= swap_count + 16'd1;
						state <= S_IDLE;
					end
				default: state <= S_IDLE;
			endcase
		end
endmodule
module fn_ddr_cpu_adapter (
	clk,
	rst,
	cmd_valid,
	cmd_ready,
	cmd_write,
	cmd_addr,
	cmd_len,
	w_valid,
	w_ready,
	w_data,
	w_be,
	w_last,
	r_valid,
	r_ready,
	r_data,
	r_error,
	r_last,
	ddr_ready,
	error_count,
	core_clk,
	ddr_init_done,
	core_reset,
	cpu_valid,
	cpu_ready,
	cpu_write,
	cpu_addr,
	cpu_wdata,
	cpu_wstrb,
	cpu_rsp_valid,
	cpu_rsp_ready,
	cpu_rdata,
	cpu_error
);
	parameter [31:0] WINDOW_BASE = 32'h80020000;
	parameter [31:0] WINDOW_BYTES = 32'h03ee0000;
	input wire clk;
	input wire rst;
	input wire cmd_valid;
	output wire cmd_ready;
	input wire cmd_write;
	input wire [31:0] cmd_addr;
	input wire [7:0] cmd_len;
	input wire w_valid;
	output wire w_ready;
	input wire [31:0] w_data;
	input wire [3:0] w_be;
	input wire w_last;
	output wire r_valid;
	input wire r_ready;
	output wire [31:0] r_data;
	output wire r_error;
	output wire r_last;
	output wire ddr_ready;
	output reg [15:0] error_count;
	input wire core_clk;
	input wire ddr_init_done;
	output wire core_reset;
	output wire cpu_valid;
	input wire cpu_ready;
	output wire cpu_write;
	output wire [25:0] cpu_addr;
	output wire [255:0] cpu_wdata;
	output wire [31:0] cpu_wstrb;
	input wire cpu_rsp_valid;
	output wire cpu_rsp_ready;
	input wire [255:0] cpu_rdata;
	input wire cpu_error;
	localparam integer REQ_W = 310;
	reg [2:0] cpu_rst_core = 3'b111;
	reg [2:0] core_rst_cpu = 3'b111;
	reg [1:0] init_core = 2'b00;
	always @(posedge core_clk or posedge rst)
		if (rst)
			cpu_rst_core <= 3'b111;
		else
			cpu_rst_core <= {cpu_rst_core[1:0], 1'b0};
	always @(posedge core_clk) init_core <= {init_core[0], ddr_init_done};
	wire reset_request_core = cpu_rst_core[2] || !init_core[1];
	reg reset_observed_cpu = 1'b0;
	reg [1:0] reset_observed_core = 2'b00;
	reg wait_cpu_reset = 1'b1;
	always @(posedge core_clk or posedge reset_request_core)
		if (reset_request_core)
			reset_observed_core <= 2'b00;
		else
			reset_observed_core <= {reset_observed_core[0], reset_observed_cpu};
	always @(posedge core_clk)
		if (reset_request_core)
			wait_cpu_reset <= 1'b1;
		else if (reset_observed_core[1])
			wait_cpu_reset <= 1'b0;
	wire core_rst = reset_request_core || wait_cpu_reset;
	assign core_reset = core_rst;
	always @(posedge clk or posedge core_rst)
		if (core_rst)
			core_rst_cpu <= 3'b111;
		else
			core_rst_cpu <= {core_rst_cpu[1:0], 1'b0};
	wire bridge_rst = rst || core_rst_cpu[2];
	always @(posedge clk or posedge reset_request_core)
		if (reset_request_core)
			reset_observed_cpu <= 1'b0;
		else
			reset_observed_cpu <= bridge_rst;
	assign ddr_ready = !bridge_rst;
	reg req_wen;
	reg [REQ_W - 1:0] req_wdata;
	wire req_full;
	wire req_empty;
	wire req_ren;
	wire [REQ_W - 1:0] req_rdata;
	wire rsp_wen;
	wire [256:0] rsp_wdata;
	wire rsp_full;
	wire rsp_empty;
	wire rsp_ren;
	wire [256:0] rsp_rdata;
	wire [2:0] unused_req_level;
	wire [2:0] unused_rsp_level;
	// R70: u_req read pointer replicated next to its wide LUT-RAM (fn_async_fifo_rfan).
	fn_async_fifo_rfan #(
		.DW(REQ_W),
		.AW(2)
	) u_req(
		.wclk(clk),
		.wrst(bridge_rst),
		.wen(req_wen),
		.wdata(req_wdata),
		.wfull(req_full),
		.wlevel(unused_req_level),
		.rclk(core_clk),
		.rrst(core_rst),
		.ren(req_ren),
		.rdata(req_rdata),
		.rempty(req_empty)
	);
	fn_async_fifo #(
		.DW(257),
		.AW(2)
	) u_rsp(
		.wclk(core_clk),
		.wrst(core_rst),
		.wen(rsp_wen),
		.wdata(rsp_wdata),
		.wfull(rsp_full),
		.wlevel(unused_rsp_level),
		.rclk(clk),
		.rrst(bridge_rst),
		.ren(rsp_ren),
		.rdata(rsp_rdata),
		.rempty(rsp_empty)
	);
	localparam [2:0] C_IDLE = 3'd0;
	localparam [2:0] C_WDATA = 3'd1;
	localparam [2:0] C_WPUSH = 3'd2;
	localparam [2:0] C_ACK = 3'd3;
	localparam [2:0] C_RWAIT = 3'd4;
	localparam [2:0] C_RPOP = 3'd5;
	localparam [2:0] C_RDATA = 3'd6;
	reg [2:0] cstate;
	reg [31:0] addr_q;
	reg [3:0] beat;
	reg [7:0] remaining;
	reg bad;
	reg [255:0] line;
	reg [31:0] strobe;
	reg bad_count;
	wire [32:0] cmd_end = {1'b0, cmd_addr} + {23'd0, cmd_len, 2'b00};
	// A legal burst stays in one 32-byte line. For aligned window bounds,
	// checking the line address is equivalent to checking its burst end.
	// Keep the original arithmetic for arbitrary unaligned/overflowing windows.
	localparam [32:0] WINDOW_END = {1'b0, WINDOW_BASE} + {1'b0, WINDOW_BYTES};
	localparam LINE_WINDOW = (WINDOW_BASE[4:0] == 0) && (WINDOW_END[4:0] == 0) && !WINDOW_END[32];
	wire outside_window = LINE_WINDOW ?
	    ((cmd_addr[31:5] < WINDOW_BASE[31:5]) || (cmd_addr[31:5] >= WINDOW_END[31:5])) :
	    ((cmd_addr < WINDOW_BASE) || (cmd_end > WINDOW_END));
	wire cmd_bad = (cmd_addr[1:0] != 2'd0) || (cmd_len == 8'd0) || (cmd_len > 8'd8) ||
	    (({1'b0, cmd_addr[4:2]} + {1'b0, cmd_len[3:0]}) > 5'd8) || outside_window;
	assign cmd_ready = ((cstate == C_IDLE) && !bridge_rst) && !req_full;
	assign w_ready = (cstate == C_WDATA) && !bridge_rst;
	assign r_valid = ((cstate == C_ACK) || (cstate == C_RDATA)) && !bridge_rst;
	assign r_last = (cstate == C_ACK) || (remaining == 8'd1);
	assign r_error = bad;
	assign r_data = (bad || (cstate != C_RDATA) ? 32'd0 : line[{beat[2:0], 5'd0}+:32]);
	integer lane;
	always @(posedge clk) begin
		req_wen <= 1'b0;
		bad_count <= 1'b0;
		if (bad_count)
			error_count <= error_count + 16'd1;
		if (bridge_rst) begin
			cstate <= C_IDLE;
			bad <= 1'b0;
			remaining <= 8'd0;
			beat <= 4'd0;
			error_count <= 16'd0;
		end
		else
			case (cstate)
				C_IDLE: begin
					// R64: req_wdata is consumed only with req_wen, which is never
					// high in C_IDLE; preloading the read request every idle cycle
					// keeps cmd_bad off its 310 CEs. The rejected-command count is
					// added one cycle later (bad_count).
					req_wdata <= {1'b0, cmd_addr[25:5], 288'h0};
					if (cmd_valid && cmd_ready) begin
						addr_q <= cmd_addr;
						beat <= {1'b0, cmd_addr[4:2]};
						remaining <= (cmd_len == 8'd0 ? 8'd1 : cmd_len);
						bad <= cmd_bad;
						strobe <= 32'd0;
						bad_count <= cmd_bad;
						if (cmd_write)
							cstate <= C_WDATA;
						else if (cmd_bad)
							cstate <= C_RDATA;
						else begin
							req_wen <= 1'b1;
							cstate <= C_RWAIT;
						end
					end
				end
				C_WDATA:
					if (w_valid) begin
						if (!bad) begin
							for (lane = 0; lane < 4; lane = lane + 1)
								if (w_be[lane]) begin
									line[{beat[2:0], lane[1:0], 3'd0}+:8] <= w_data[8 * lane+:8];
									strobe[{beat[2:0], lane[1:0]}] <= 1'b1;
								end
						end
						if (w_last != (remaining == 8'd1))
							bad <= 1'b1;
						beat <= beat + 4'd1;
						remaining <= remaining - 8'd1;
						if ((remaining == 8'd1) || w_last)
							cstate <= C_WPUSH;
					end
				C_WPUSH: begin
					if (!bad) begin
						req_wen <= 1'b1;
						req_wdata <= {1'b1, addr_q[25:5], strobe, line};
					end
					else
						error_count <= error_count + 16'd1;
					cstate <= C_ACK;
				end
				C_ACK:
					if (r_ready)
						cstate <= C_IDLE;
				C_RWAIT:
					if (!rsp_empty)
						cstate <= C_RPOP;
				C_RPOP: begin
					line <= rsp_rdata[255:0];
					bad <= rsp_rdata[256];
					cstate <= C_RDATA;
				end
				C_RDATA:
					if (r_ready) begin
						beat <= beat + 4'd1;
						remaining <= remaining - 8'd1;
						if (remaining == 8'd1)
							cstate <= C_IDLE;
					end
				default: cstate <= C_IDLE;
			endcase
	end
	assign rsp_ren = ((cstate == C_RWAIT) && !rsp_empty) && !bridge_rst;
	localparam [1:0] D_IDLE = 2'd0;
	localparam [1:0] D_LOAD = 2'd1;
	localparam [1:0] D_SEND = 2'd2;
	localparam [1:0] D_WAIT = 2'd3;
	reg [1:0] dstate;
	reg [REQ_W - 1:0] cur;
	assign req_ren = ((dstate == D_IDLE) && !req_empty) && !core_rst;
	wire [REQ_W - 1:0] request_payload = (dstate == D_LOAD ? req_rdata : cur);
	assign cpu_valid = ((dstate == D_LOAD) || (dstate == D_SEND)) && !core_rst;
	assign cpu_write = request_payload[REQ_W - 1];
	assign cpu_addr = {request_payload[308:288], 5'b00000};
	assign cpu_wdata = request_payload[255:0];
	assign cpu_wstrb = request_payload[287:256];
	assign cpu_rsp_ready = ((dstate == D_WAIT) && !core_rst) && (cur[REQ_W - 1] || !rsp_full);
	assign rsp_wen = (cpu_rsp_valid && cpu_rsp_ready) && !cur[REQ_W - 1];
	assign rsp_wdata = {cpu_error, cpu_rdata};
	always @(posedge core_clk)
		if (core_rst) begin
			dstate <= D_IDLE;
			cur <= {REQ_W {1'b0}};
		end
		else
			case (dstate)
				D_IDLE:
					if (!req_empty)
						dstate <= D_LOAD;
				D_LOAD: begin
					cur <= req_rdata;
					dstate <= (cpu_ready ? D_WAIT : D_SEND);
				end
				D_SEND:
					if (cpu_ready)
						dstate <= D_WAIT;
				D_WAIT:
					if (cpu_rsp_valid && cpu_rsp_ready)
						dstate <= D_IDLE;
				default: dstate <= D_IDLE;
			endcase
endmodule

module fn_cdc_three_epoch_reset (
	aclk,
	bclk,
	cclk,
	abort,
	arst,
	brst,
	crst
);
	input wire aclk;
	input wire bclk;
	input wire cclk;
	input wire abort;
	output wire arst;
	output wire brst;
	output wire crst;
	reg ah = 1;
	reg bh = 1;
	reg ch = 1;
	reg ao = 0;
	reg bo = 0;
	reg co = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ba = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ca = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ab = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] cb = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ac = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] bc = 0;
	assign arst = abort || ah;
	assign brst = abort || bh;
	assign crst = abort || ch;
	always @(posedge aclk or posedge abort)
		if (abort) begin
			ah <= 1;
			ao <= 0;
			ba <= 0;
			ca <= 0;
		end
		else begin
			if (arst)
				ao <= 1;
			ba <= {ba[0], bo};
			ca <= {ca[0], co};
			if ((ao && ba[1]) && ca[1])
				ah <= 0;
		end
	always @(posedge bclk or posedge abort)
		if (abort) begin
			bh <= 1;
			bo <= 0;
			ab <= 0;
			cb <= 0;
		end
		else begin
			if (brst)
				bo <= 1;
			ab <= {ab[0], ao};
			cb <= {cb[0], co};
			if ((bo && ab[1]) && cb[1])
				bh <= 0;
		end
	always @(posedge cclk or posedge abort)
		if (abort) begin
			ch <= 1;
			co <= 0;
			ac <= 0;
			bc <= 0;
		end
		else begin
			if (crst)
				co <= 1;
			ac <= {ac[0], ao};
			bc <= {bc[0], bo};
			if ((co && ac[1]) && bc[1])
				ch <= 0;
		end
endmodule
module fn_gpu_ddr_framebuffer_split (
	draw_clk,
	draw_rst,
	pix_clk,
	pix_rst,
	ddr_clk,
	ddr_rst,
	hdmi_clk,
	hdmi_rst,
	hdmi_acquire,
	hdmi_acquire_ready,
	hdmi_grant_valid,
	hdmi_grant_ready,
	hdmi_grant,
	hdmi_front_valid,
	hdmi_front_ready,
	hdmi_front_addr,
	hdmi_front_rsp_valid,
	hdmi_front_rsp_ready,
	hdmi_front_data,
	hdmi_front_error,
	palette_fenced,
	scan_commit,
	scan_generation,
	pixel_valid,
	pixel_ready,
	draw_buffer,
	pixel_x,
	pixel_y,
	pixel_data,
	raster_quiescent,
	swap_request,
	swap_done,
	frame_latch,
	vblank,
	scan_valid,
	scan_x,
	scan_y,
	scan_index,
	scan_index_hit,
	front_buffer,
	underflow,
	protocol_error,
	producer_drained,
	draw_drained,
	swap_pending,
	cpu_valid,
	cpu_ready,
	cpu_write,
	cpu_addr,
	cpu_wdata,
	cpu_wstrb,
	cpu_rsp_valid,
	cpu_rsp_ready,
	cpu_rdata,
	cpu_error,
	axi_awaddr,
	axi_awvalid,
	axi_awready,
	axi_wdata,
	axi_wstrb,
	axi_wready,
	axi_araddr,
	axi_arvalid,
	axi_arready,
	axi_rdata,
	axi_rvalid,
	axi_rlast
);
	input wire draw_clk;
	input wire draw_rst;
	input wire pix_clk;
	input wire pix_rst;
	input wire ddr_clk;
	input wire ddr_rst;
	input wire hdmi_clk;
	input wire hdmi_rst;
	input wire hdmi_acquire;
	output wire hdmi_acquire_ready;
	output wire hdmi_grant_valid;
	input wire hdmi_grant_ready;
	output wire [9:0] hdmi_grant;
	input wire hdmi_front_valid;
	output wire hdmi_front_ready;
	input wire [25:0] hdmi_front_addr;
	output wire hdmi_front_rsp_valid;
	input wire hdmi_front_rsp_ready;
	output wire [255:0] hdmi_front_data;
	output wire hdmi_front_error;
	input wire palette_fenced;
	output reg scan_commit;
	output wire [7:0] scan_generation;
	input wire pixel_valid;
	output wire pixel_ready;
	input wire draw_buffer;
	input wire [8:0] pixel_x;
	input wire [8:0] pixel_y;
	input wire [7:0] pixel_data;
	input wire raster_quiescent;
	input wire swap_request;
	output reg swap_done;
	input wire frame_latch;
	input wire vblank;
	input wire scan_valid;
	input wire [8:0] scan_x;
	input wire [8:0] scan_y;
	output reg [7:0] scan_index;
	output reg scan_index_hit;
	output reg front_buffer;
	output wire underflow;
	output wire protocol_error;
	output wire producer_drained;
	output wire draw_drained;
	output wire swap_pending;
	input wire cpu_valid;
	output wire cpu_ready;
	input wire cpu_write;
	input wire [25:0] cpu_addr;
	input wire [255:0] cpu_wdata;
	input wire [31:0] cpu_wstrb;
	output wire cpu_rsp_valid;
	input wire cpu_rsp_ready;
	output wire [255:0] cpu_rdata;
	output wire cpu_error;
	output wire [27:0] axi_awaddr;
	output wire axi_awvalid;
	input wire axi_awready;
	output wire [255:0] axi_wdata;
	output wire [31:0] axi_wstrb;
	input wire axi_wready;
	output wire [27:0] axi_araddr;
	output wire axi_arvalid;
	input wire axi_arready;
	input wire [255:0] axi_rdata;
	input wire axi_rvalid;
	input wire axi_rlast;
	localparam [31:0] FB0 = 32'h03f00000;
	localparam [31:0] FB1 = 32'h03f25800;
	reg [1:0] display_slot;
	reg [1:0] back_slot;
	reg [1:0] held_slot;
	reg [1:0] draw_slot;
	function automatic [1:0] free_slot;
		input [1:0] front;
		input [1:0] held;
		if ((front != 0) && (held != 0))
			free_slot = 0;
		else if ((front != 1) && (held != 1))
			free_slot = 1;
		else
			free_slot = 2;
	endfunction
	wire [1:0] next_back_slot = free_slot(back_slot, held_slot);
	wire acquire_pix;
	wire acquire_pop;
	wire grant_push;
	wire grant_space;
	fn_cdc_stream #(
		.DW(1),
		.AW(2)
	) hdmi_acquires(
		.wclk(hdmi_clk),
		.wrst(hdmi_rst),
		.wvalid(hdmi_acquire),
		.wready(hdmi_acquire_ready),
		.wdata(1'b1),
		.rclk(pix_clk),
		.rrst(pix_rst),
		.rvalid(acquire_pix),
		.rready(acquire_pop),
		.rdata()
	);
	reg fence_ack;
	wire front_valid;
	reg marker_sent;
	wire [1:0] cache_valid;
	reg [7:0] generation;
	wire [16:0] new_tag = {(scan_commit ? generation : generation + 8'd1), 9'd0};
	wire [16:0] tag0;
	wire [16:0] tag1;
	wire new_front_ready = (cache_valid[0] && (tag0 == new_tag)) || (cache_valid[1] && (tag1 == new_tag));
	wire return_ready;
	wire row_busy;
	wire commit_now = (((((((((!pix_rst && !protocol_error) && !scan_commit) && frame_latch) && palette_fenced) && marker_sent) && fence_ack) && new_front_ready) && !row_busy) && !front_valid) && return_ready;
	assign grant_push = acquire_pix && !commit_now;
	assign acquire_pop = grant_space && !commit_now;
	fn_cdc_stream #(
		.DW(10),
		.AW(2)
	) hdmi_grants(
		.wclk(pix_clk),
		.wrst(pix_rst),
		.wvalid(grant_push),
		.wready(grant_space),
		.wdata({display_slot, generation}),
		.rclk(hdmi_clk),
		.rrst(hdmi_rst),
		.rvalid(hdmi_grant_valid),
		.rready(hdmi_grant_ready),
		.rdata(hdmi_grant)
	);
	always @(posedge pix_clk)
		if (pix_rst) begin
			display_slot <= 0;
			back_slot <= 1;
			held_slot <= 0;
		end
		else begin
			if (grant_push && grant_space)
				held_slot <= display_slot;
			if (commit_now) begin
				display_slot <= back_slot;
				back_slot <= next_back_slot;
			end
		end
	assign scan_generation = generation;
	reg pix_error;
	reg [7:0] draw_generation;
	reg draw_marker_sent;
	reg draw_error_local;
	wire source_open = (!draw_rst && !draw_marker_sent) && !swap_done;
	wire [25:0] pixel_address = (26'h3f00000 + {6'd0, draw_slot, 18'd0}) + {8'd0, pixel_y, pixel_x};
	wire packer_ready;
	wire packed_valid;
	wire packed_ready;
	wire [25:0] packed_addr;
	wire [255:0] packed_data;
	wire [31:0] packed_strb;
	assign pixel_ready = source_open && packer_ready;
	fn_ddr_pixel_packer packer(
		.clk(draw_clk),
		.rst(draw_rst),
		.calibrated(1'b1),
		.pixel_valid(pixel_valid && source_open),
		.pixel_ready(packer_ready),
		.pixel_addr(pixel_address),
		.pixel_data(pixel_data),
		.flush(swap_request),
		.drained(producer_drained),
		.draw_valid(packed_valid),
		.draw_ready(packed_ready),
		.draw_addr(packed_addr),
		.draw_wdata(packed_data),
		.draw_wstrb(packed_strb)
	);
	wire marker_valid = ((((source_open && swap_request) && raster_quiescent) && producer_drained) && !pixel_valid) && !packed_valid;
	wire write_ready;
	wire write_valid = packed_valid || marker_valid;
	wire [322:0] write_data = {marker_valid, draw_generation, packed_addr, packed_data, packed_strb};
	wire native_write_valid;
	wire native_write_ready;
	wire [322:0] native_write_data;
	assign packed_ready = (write_ready && !draw_marker_sent) && !swap_done;
	fn_cdc_stream #(
		.DW(323),
		.AW(3)
	) writes(
		.wclk(draw_clk),
		.wrst(draw_rst),
		.wvalid(write_valid),
		.wready(write_ready),
		.wdata(write_data),
		.rclk(ddr_clk),
		.rrst(ddr_rst),
		.rvalid(native_write_valid),
		.rready(native_write_ready),
		.rdata(native_write_data)
	);
	wire is_marker = native_write_data[322];
	wire [7:0] write_generation = native_write_data[321:314];
	wire arb_draw_ready;
	wire arb_draw_drained;
	wire draw_retired;
	wire draw_error;
	wire arb_error;
	reg fence_wait;
	reg ddr_error;
	reg [7:0] fence_generation;
	reg [7:0] expected_generation;
	wire ack_valid = ((fence_wait && arb_draw_drained) && !ddr_error) && !arb_error;
	wire ack_ready;
	wire ack_pix_valid;
	wire ack_pix_ready;
	wire [7:0] ack_pix_generation;
	assign native_write_ready = (!ddr_error && !fence_wait) && (is_marker || arb_draw_ready);
	fn_cdc_stream #(
		.DW(8),
		.AW(2)
	) acknowledgments(
		.wclk(ddr_clk),
		.wrst(ddr_rst),
		.wvalid(ack_valid),
		.wready(ack_ready),
		.wdata(fence_generation),
		.rclk(pix_clk),
		.rrst(pix_rst),
		.rvalid(ack_pix_valid),
		.rready(ack_pix_ready),
		.rdata(ack_pix_generation)
	);
	assign ack_pix_ready = !pix_rst;
	always @(posedge ddr_clk)
		if (ddr_rst) begin
			fence_wait <= 0;
			fence_generation <= 0;
			expected_generation <= 0;
			ddr_error <= 0;
		end
		else begin
			if (native_write_valid && native_write_ready) begin
				if (write_generation != expected_generation)
					ddr_error <= 1;
				if (is_marker) begin
					fence_wait <= 1;
					fence_generation <= write_generation;
				end
			end
			if (ack_valid && ack_ready) begin
				fence_wait <= 0;
				expected_generation <= expected_generation + 8'd1;
			end
			if (draw_error || arb_error)
				ddr_error <= 1;
		end
	assign draw_drained = fence_ack;
	assign swap_pending = marker_sent;
	wire front_ready;
	wire front_rsp_valid;
	wire front_rsp_ready;
	wire front_error;
	wire [25:0] front_addr;
	wire [255:0] front_data;
	wire dfront_valid;
	wire dfront_ready;
	wire dfront_rsp_valid;
	wire dfront_rsp_ready;
	wire dfront_error;
	wire [26:0] dfront_request;
	wire [255:0] dfront_data;
	wire [256:0] front_response;
	fn_cdc_stream #(
		.DW(27),
		.AW(2)
	) read_requests(
		.wclk(pix_clk),
		.wrst(pix_rst),
		.wvalid(front_valid),
		.wready(front_ready),
		.wdata({!vblank, front_addr}),
		.rclk(ddr_clk),
		.rrst(ddr_rst),
		.rvalid(dfront_valid),
		.rready(dfront_ready),
		.rdata(dfront_request)
	);
	fn_cdc_stream #(
		.DW(257),
		.AW(2)
	) read_responses(
		.wclk(ddr_clk),
		.wrst(ddr_rst),
		.wvalid(dfront_rsp_valid),
		.wready(dfront_rsp_ready),
		.wdata({dfront_error, dfront_data}),
		.rclk(pix_clk),
		.rrst(pix_rst),
		.rvalid(front_rsp_valid),
		.rready(front_rsp_ready),
		.rdata(front_response)
	);
	assign {front_error, front_data} = front_response;
	wire row_done;
	wire row_error;
	wire row_ready;
	reg row_valid;
	reg row_slot;
	reg [16:0] row_tag;
	reg [25:0] row_addr;
	wire [16:0] current_tag = {generation, scan_y};
	wire current0 = cache_valid[0] && (tag0 == current_tag);
	wire current1 = cache_valid[1] && (tag1 == current_tag);
	wire [1:0] locks = (vblank ? 2'b00 : {current1, current0});
	wire [16:0] zero_tag = {generation, 9'd0};
	wire zero0 = cache_valid[0] && (tag0 == zero_tag);
	wire zero1 = cache_valid[1] && (tag1 == zero_tag);
	wire [16:0] next_tag = {generation, scan_y + 9'd1};
	wire next_hit = (cache_valid[0] && (tag0 == next_tag)) || (cache_valid[1] && (tag1 == next_tag));
	wire [25:0] visible_base = 26'h3f00000 + {6'd0, display_slot, 18'd0};
	wire [25:0] pending_base = 26'h3f00000 + {6'd0, back_slot, 18'd0};
	always @(*) begin
		row_valid = 0;
		row_slot = 0;
		row_tag = 0;
		row_addr = 0;
		if ((!pix_rst && !frame_latch) && !scan_commit) begin
			if (vblank) begin
				if (!zero0 && !zero1) begin
					row_valid = 1;
					row_slot = 0;
					row_tag = zero_tag;
					row_addr = visible_base;
				end
				else if ((swap_pending && draw_drained) && !new_front_ready) begin
					row_valid = 1;
					row_slot = zero0;
					row_tag = new_tag;
					row_addr = pending_base;
				end
			end
			else if (scan_y < 9'd300) begin
				if (!current0 && !current1) begin
					row_valid = 1;
					row_slot = 0;
					row_tag = current_tag;
					row_addr = visible_base + {8'd0, scan_y, 9'd0};
				end
				else if ((scan_y < 9'd299) && !next_hit) begin
					row_valid = 1;
					row_slot = current0;
					row_tag = next_tag;
					row_addr = visible_base + {8'd0, scan_y + 9'd1, 9'd0};
				end
			end
		end
	end
	wire scan_response;
	wire cache_hit;
	wire [7:0] cache_index;
	wire cache_protocol_error;
	wire return_valid;
	wire [9:0] return_packet;
	wire [7:0] return_generation = return_packet[7:0];
	fn_cdc_stream #(
		.DW(10),
		.AW(2)
	) commits(
		.wclk(pix_clk),
		.wrst(pix_rst),
		.wvalid(commit_now),
		.wready(return_ready),
		.wdata({next_back_slot, generation + 8'd1}),
		.rclk(draw_clk),
		.rrst(draw_rst),
		.rvalid(return_valid),
		.rready(1'b1),
		.rdata(return_packet)
	);
	always @(posedge draw_clk)
		if (draw_rst) begin
			draw_slot <= 1;
			draw_generation <= 0;
			draw_marker_sent <= 0;
			swap_done <= 0;
			draw_error_local <= 0;
		end
		else begin
			swap_done <= 0;
			if (marker_valid && write_ready)
				draw_marker_sent <= 1;
			if (return_valid) begin
				if (!draw_marker_sent || (return_generation != (draw_generation + 8'd1)))
					draw_error_local <= 1;
				else begin
					draw_slot <= return_packet[9:8];
					draw_generation <= return_generation;
					draw_marker_sent <= 0;
					swap_done <= 1;
				end
			end
		end
	(* ASYNC_REG = "TRUE" *) reg [1:0] draw_error_pix;
	always @(posedge pix_clk)
		if (pix_rst)
			draw_error_pix <= 0;
		else
			draw_error_pix <= {draw_error_pix[0], draw_error_local};
	fn_ddr_row_cache_pix cache(
		.clk(pix_clk),
		.rst(pix_rst),
		.calibrated(1'b1),
		.commit(commit_now),
		.commit_tag(new_tag),
		.row_valid(row_valid),
		.row_ready(row_ready),
		.row_slot(row_slot),
		.row_tag(row_tag),
		.row_addr(row_addr),
		.display_lock(locks),
		.row_done(row_done),
		.row_error(row_error),
		.busy(row_busy),
		.cache_valid(cache_valid),
		.cache_tag0(tag0),
		.cache_tag1(tag1),
		.front_valid(front_valid),
		.front_ready(front_ready),
		.front_addr(front_addr),
		.front_rsp_valid(front_rsp_valid),
		.front_rsp_ready(front_rsp_ready),
		.front_rdata(front_data),
		.front_error(front_error),
		.scan_valid(scan_valid),
		.scan_tag(current_tag),
		.scan_x(scan_x),
		.scan_rsp_valid(scan_response),
		.scan_data(cache_index),
		.scan_hit(cache_hit),
		.underflow(underflow),
		.clear_underflow(1'b0),
		.protocol_error(cache_protocol_error)
	);
	wire hvalid;
	wire hready;
	wire hrvalid;
	wire hrready;
	wire herror;
	wire [25:0] haddr;
	wire [255:0] hdata;
	wire [256:0] hresponse;
	fn_cdc_stream #(
		.DW(26),
		.AW(2)
	) hdmi_reads(
		.wclk(hdmi_clk),
		.wrst(hdmi_rst),
		.wvalid(hdmi_front_valid),
		.wready(hdmi_front_ready),
		.wdata(hdmi_front_addr),
		.rclk(ddr_clk),
		.rrst(ddr_rst),
		.rvalid(hvalid),
		.rready(hready),
		.rdata(haddr)
	);
	fn_cdc_stream #(
		.DW(257),
		.AW(2)
	) hdmi_returns(
		.wclk(ddr_clk),
		.wrst(ddr_rst),
		.wvalid(hrvalid),
		.wready(hrready),
		.wdata({herror, hdata}),
		.rclk(hdmi_clk),
		.rrst(hdmi_rst),
		.rvalid(hdmi_front_rsp_valid),
		.rready(hdmi_front_rsp_ready),
		.rdata(hresponse)
	);
	assign {hdmi_front_error, hdmi_front_data} = hresponse;
	wire arb_front_valid;
	wire arb_front_ready;
	wire arb_front_urgent;
	wire arb_front_rsp_valid;
	wire arb_front_rsp_ready;
	wire arb_front_error;
	wire [25:0] arb_front_addr;
	wire [255:0] arb_front_data;
	fn_front_read_mux readers(
		.clk(ddr_clk),
		.rst(ddr_rst),
		.a_valid(dfront_valid),
		.a_ready(dfront_ready),
		.a_urgent(dfront_request[26]),
		.a_addr(dfront_request[25:0]),
		.a_rsp_valid(dfront_rsp_valid),
		.a_rsp_ready(dfront_rsp_ready),
		.a_data(dfront_data),
		.a_error(dfront_error),
		.b_valid(hvalid),
		.b_ready(hready),
		.b_urgent(1'b0),
		.b_addr(haddr),
		.b_rsp_valid(hrvalid),
		.b_rsp_ready(hrready),
		.b_data(hdata),
		.b_error(herror),
		.valid(arb_front_valid),
		.ready(arb_front_ready),
		.urgent(arb_front_urgent),
		.addr(arb_front_addr),
		.rsp_valid(arb_front_rsp_valid),
		.rsp_ready(arb_front_rsp_ready),
		.data(arb_front_data),
		.error(arb_front_error)
	);
	wire unused_swap_ready;
	wire unused_swap_pending;
	wire unused_swap_done;
	wire unused_front_buffer;
	fn_ddr_frame_arbiter #(.CPU_LIMIT_BYTES(FB0[25:0])) arbiter(
		.clk(ddr_clk),
		.rst(ddr_rst),
		.calibrated(1'b1),
		.producer_drained(1'b0),
		.producer_quiescent(1'b0),
		.cpu_valid(cpu_valid),
		.cpu_ready(cpu_ready),
		.cpu_write(cpu_write),
		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_wstrb(cpu_wstrb),
		.cpu_rsp_valid(cpu_rsp_valid),
		.cpu_rsp_ready(cpu_rsp_ready),
		.cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error),
		.front_valid(arb_front_valid),
		.front_ready(arb_front_ready),
		.front_urgent(arb_front_urgent),
		.front_addr(arb_front_addr),
		.front_rsp_valid(arb_front_rsp_valid),
		.front_rsp_ready(arb_front_rsp_ready),
		.front_rdata(arb_front_data),
		.front_error(arb_front_error),
		.draw_valid((((native_write_valid && !is_marker) && !fence_wait) && !ddr_error) && (write_generation == expected_generation)),
		.draw_ready(arb_draw_ready),
		.draw_addr(native_write_data[313:288]),
		.draw_wdata(native_write_data[287:32]),
		.draw_wstrb(native_write_data[31:0]),
		.draw_retired(draw_retired),
		.draw_error(draw_error),
		.draw_drained(arb_draw_drained),
		.swap_valid(1'b0),
		.swap_ready(unused_swap_ready),
		.vblank_latch(1'b0),
		.front_epoch_idle(1'b0),
		.new_front_ready(1'b0),
		.swap_pending(unused_swap_pending),
		.swap_done(unused_swap_done),
		.front_buffer(unused_front_buffer),
		.protocol_error(arb_error),
		.axi_awaddr(axi_awaddr),
		.axi_awvalid(axi_awvalid),
		.axi_awready(axi_awready),
		.axi_wdata(axi_wdata),
		.axi_wstrb(axi_wstrb),
		.axi_wready(axi_wready),
		.axi_araddr(axi_araddr),
		.axi_arvalid(axi_arvalid),
		.axi_arready(axi_arready),
		.axi_rdata(axi_rdata),
		.axi_rvalid(axi_rvalid),
		.axi_rlast(axi_rlast)
	);
	(* ASYNC_REG = "TRUE" *) reg [1:0] ddr_error_pix;
	always @(posedge pix_clk)
		if (pix_rst) begin
			generation <= 0;
			front_buffer <= 0;
			scan_commit <= 0;
			marker_sent <= 0;
			fence_ack <= 0;
			scan_index <= 0;
			scan_index_hit <= 0;
			pix_error <= 0;
			ddr_error_pix <= 0;
		end
		else begin
			ddr_error_pix <= {ddr_error_pix[0], ddr_error};
			scan_commit <= 0;
			if (ack_pix_valid && ack_pix_ready) begin
				if (fence_ack || (ack_pix_generation != generation))
					pix_error <= 1;
				else begin
					fence_ack <= 1;
					marker_sent <= 1;
				end
			end
			if (commit_now) begin
				front_buffer <= !front_buffer;
				generation <= generation + 8'd1;
				scan_commit <= 1;
			end
			if (scan_commit) begin
				marker_sent <= 0;
				fence_ack <= 0;
			end
			scan_index <= cache_index;
			scan_index_hit <= scan_response && cache_hit;
			if (row_error)
				pix_error <= 1;
		end
	assign protocol_error = ((pix_error || cache_protocol_error) || ddr_error_pix[1]) || draw_error_pix[1];
	wire unused = &{1'b0, row_done, row_ready, draw_retired, unused_swap_ready, unused_swap_pending, unused_swap_done, unused_front_buffer};
endmodule
module fn_gpu_ddr_system_split (
	hdmi_clk,
	hdmi_lock,
	hdmi_reset,
	hdmi_hs,
	hdmi_vs,
	hdmi_de,
	hdmi_x,
	hdmi_y,
	hdmi_rgb,
	cpu_clk,
	cpu_rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_be,
	req_wdata,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	touch_state,
	touch_xy,
	touch_seq,
	touch_errors,
	touch_xy_extra,
	touch_ids,
	draw_clk,
	pix_clk,
	lcd_hs,
	lcd_vs,
	lcd_de,
	lcd_r,
	lcd_g,
	lcd_b,
	frame_toggle,
	ddr_clk,
	calibrated,
	cmd_valid,
	cmd_ready,
	cmd_write,
	cmd_addr,
	cmd_len,
	w_valid,
	w_ready,
	w_data,
	w_be,
	w_last,
	r_valid,
	r_ready,
	r_data,
	r_error,
	r_last,
	ddr_ready,
	error_count,
	axi_awaddr,
	axi_awvalid,
	axi_awready,
	axi_wdata,
	axi_wstrb,
	axi_wready,
	axi_araddr,
	axi_arvalid,
	axi_arready,
	axi_rdata,
	axi_rvalid,
	axi_rlast,
	framebuffer_underflow,
	framebuffer_error
);
	parameter FONT_INIT = "font.hex";
	parameter PAL_INIT = "palette.hex";
	parameter [31:0] CLOCK_HZ = 32'd138857143;
	input wire hdmi_clk;
	input wire hdmi_lock;
	output wire hdmi_reset;
	output wire hdmi_hs;
	output wire hdmi_vs;
	output wire hdmi_de;
	output wire [10:0] hdmi_x;
	output wire [9:0] hdmi_y;
	output wire [23:0] hdmi_rgb;
	input wire cpu_clk;
	input wire cpu_rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [3:0] req_be;
	input wire [31:0] req_wdata;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	input wire [31:0] touch_state;
	input wire [31:0] touch_xy;
	input wire [31:0] touch_seq;
	input wire [31:0] touch_errors;
	input wire [127:0] touch_xy_extra;
	input wire [39:0] touch_ids;
	input wire draw_clk;
	input wire pix_clk;
	output wire lcd_hs;
	output wire lcd_vs;
	output wire lcd_de;
	output wire [7:0] lcd_r;
	output wire [7:0] lcd_g;
	output wire [7:0] lcd_b;
	output wire frame_toggle;
	input wire ddr_clk;
	input wire calibrated;
	input wire cmd_valid;
	output wire cmd_ready;
	input wire cmd_write;
	input wire [31:0] cmd_addr;
	input wire [7:0] cmd_len;
	input wire w_valid;
	output wire w_ready;
	input wire [31:0] w_data;
	input wire [3:0] w_be;
	input wire w_last;
	output wire r_valid;
	input wire r_ready;
	output wire [31:0] r_data;
	output wire r_error;
	output wire r_last;
	output wire ddr_ready;
	output wire [15:0] error_count;
	output wire [27:0] axi_awaddr;
	output wire axi_awvalid;
	input wire axi_awready;
	output wire [255:0] axi_wdata;
	output wire [31:0] axi_wstrb;
	input wire axi_wready;
	output wire [27:0] axi_araddr;
	output wire axi_arvalid;
	input wire axi_arready;
	input wire [255:0] axi_rdata;
	input wire axi_rvalid;
	input wire axi_rlast;
	output wire framebuffer_underflow;
	output wire framebuffer_error;
	wire core_reset;
	wire pix_reset;
	// R73: replicate the draw-domain reset driver (fanout ~2000) for the 74.8 MHz GPU clock.
	wire draw_reset /* synthesis syn_maxfan = 32 */;
	wire adapter_reset;
	wire hdmi_rst;
	assign hdmi_reset = hdmi_rst;
	fn_cdc_four_epoch_reset gpu_epoch(
		.aclk(draw_clk),
		.bclk(pix_clk),
		.cclk(ddr_clk),
		.dclk(hdmi_clk),
		.abort(adapter_reset),
		.arst(draw_reset),
		.brst(pix_reset),
		.crst(core_reset),
		.drst(hdmi_rst)
	);
	// R75: GPU draw-domain reset from a register placed next to its ~2000 loads: asserts with
	// draw_reset (asynchronous preset), releases one draw_clk edge after it. draw_up_cpu follows
	// the registered copy, so the CPU sees the GPU ready only after the draw domain left reset.
	(* syn_maxfan = 64 *) reg draw_reset_q = 1;
	always @(posedge draw_clk or posedge draw_reset)
		if (draw_reset)
			draw_reset_q <= 1;
		else
			draw_reset_q <= 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] pix_up_cpu = 0;
	always @(posedge cpu_clk or posedge pix_reset)
		if (pix_reset)
			pix_up_cpu <= 0;
		else
			pix_up_cpu <= {pix_up_cpu[0], 1'b1};
	(* ASYNC_REG = "TRUE" *) reg [1:0] draw_up_cpu = 0;
	always @(posedge cpu_clk or posedge draw_reset_q)
		if (draw_reset_q)
			draw_up_cpu <= 0;
		else
			draw_up_cpu <= {draw_up_cpu[0], 1'b1};
	wire gpu_ready = (ddr_ready && pix_up_cpu[1]) && draw_up_cpu[1];
	wire gpu_req_ready;
	assign req_ready = (gpu_ready && !cpu_rst) && gpu_req_ready;
	wire cpu_valid;
	wire cpu_ready;
	wire cpu_write;
	wire cpu_rsp_valid;
	wire cpu_rsp_ready;
	wire cpu_error;
	wire [25:0] cpu_addr;
	wire [255:0] cpu_wdata;
	wire [255:0] cpu_rdata;
	wire [31:0] cpu_wstrb;
	fn_ddr_cpu_adapter adapter(
		.clk(cpu_clk),
		.rst(cpu_rst || !hdmi_lock),
		.cmd_valid(cmd_valid),
		.cmd_ready(cmd_ready),
		.cmd_write(cmd_write),
		.cmd_addr(cmd_addr),
		.cmd_len(cmd_len),
		.w_valid(w_valid),
		.w_ready(w_ready),
		.w_data(w_data),
		.w_be(w_be),
		.w_last(w_last),
		.r_valid(r_valid),
		.r_ready(r_ready),
		.r_data(r_data),
		.r_error(r_error),
		.r_last(r_last),
		.ddr_ready(ddr_ready),
		.error_count(error_count),
		.core_clk(ddr_clk),
		.ddr_init_done(calibrated),
		.core_reset(adapter_reset),
		.cpu_valid(cpu_valid),
		.cpu_ready(cpu_ready),
		.cpu_write(cpu_write),
		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_wstrb(cpu_wstrb),
		.cpu_rsp_valid(cpu_rsp_valid),
		.cpu_rsp_ready(cpu_rsp_ready),
		.cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error)
	);
	fn_gpu_top_ddr_split #(
		.FONT_INIT(FONT_INIT),
		.PAL_INIT(PAL_INIT),
		.CLOCK_HZ(CLOCK_HZ)
	) gpu(
		.hdmi_clk(hdmi_clk),
		.hdmi_rst(hdmi_rst),
		.hdmi_hs(hdmi_hs),
		.hdmi_vs(hdmi_vs),
		.hdmi_de(hdmi_de),
		.hdmi_x(hdmi_x),
		.hdmi_y(hdmi_y),
		.hdmi_rgb(hdmi_rgb),
		.cpu_clk(cpu_clk),
		.cpu_rst(cpu_rst || !gpu_ready),
		.req_valid((req_valid && gpu_ready) && !cpu_rst),
		.req_ready(gpu_req_ready),
		.req_addr(req_addr),
		.req_write(req_write),
		.req_be(req_be),
		.req_wdata(req_wdata),
		.rsp_valid(rsp_valid),
		.rsp_ready(rsp_ready),
		.rsp_rdata(rsp_rdata),
		.rsp_error(rsp_error),
		.touch_state(touch_state),
		.touch_xy(touch_xy),
		.touch_seq(touch_seq),
		.touch_errors(touch_errors), .touch_xy_extra(touch_xy_extra), .touch_ids(touch_ids),
		.draw_clk(draw_clk),
		.draw_rst(draw_reset_q),
		.pix_clk(pix_clk),
		.pix_rst(pix_reset),
		.lcd_hs(lcd_hs),
		.lcd_vs(lcd_vs),
		.lcd_de(lcd_de),
		.lcd_r(lcd_r),
		.lcd_g(lcd_g),
		.lcd_b(lcd_b),
		.frame_toggle(frame_toggle),
		.ddr_clk(ddr_clk),
		.ddr_rst(core_reset),
		.cpu_valid(cpu_valid),
		.cpu_ready(cpu_ready),
		.cpu_write(cpu_write),
		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_wstrb(cpu_wstrb),
		.cpu_rsp_valid(cpu_rsp_valid),
		.cpu_rsp_ready(cpu_rsp_ready),
		.cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error),
		.axi_awaddr(axi_awaddr),
		.axi_awvalid(axi_awvalid),
		.axi_awready(axi_awready),
		.axi_wdata(axi_wdata),
		.axi_wstrb(axi_wstrb),
		.axi_wready(axi_wready),
		.axi_araddr(axi_araddr),
		.axi_arvalid(axi_arvalid),
		.axi_arready(axi_arready),
		.axi_rdata(axi_rdata),
		.axi_rvalid(axi_rvalid),
		.axi_rlast(axi_rlast),
		.framebuffer_underflow(framebuffer_underflow),
		.framebuffer_error(framebuffer_error)
	);
endmodule
module fn_gpu_top_ddr_split (
	hdmi_clk,
	hdmi_rst,
	hdmi_hs,
	hdmi_vs,
	hdmi_de,
	hdmi_x,
	hdmi_y,
	hdmi_rgb,
	cpu_clk,
	cpu_rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_be,
	req_wdata,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	touch_state,
	touch_xy,
	touch_seq,
	touch_errors,
	touch_xy_extra,
	touch_ids,
	draw_clk,
	draw_rst,
	pix_clk,
	pix_rst,
	lcd_hs,
	lcd_vs,
	lcd_de,
	lcd_r,
	lcd_g,
	lcd_b,
	frame_toggle,
	ddr_clk,
	ddr_rst,
	cpu_valid,
	cpu_ready,
	cpu_write,
	cpu_addr,
	cpu_wdata,
	cpu_wstrb,
	cpu_rsp_valid,
	cpu_rsp_ready,
	cpu_rdata,
	cpu_error,
	axi_awaddr,
	axi_awvalid,
	axi_awready,
	axi_wdata,
	axi_wstrb,
	axi_wready,
	axi_araddr,
	axi_arvalid,
	axi_arready,
	axi_rdata,
	axi_rvalid,
	axi_rlast,
	framebuffer_underflow,
	framebuffer_error
);
	parameter FONT_INIT = "font.hex";
	parameter PAL_INIT = "palette.hex";
	parameter [31:0] CLOCK_HZ = 32'd138857143;
	input wire hdmi_clk;
	input wire hdmi_rst;
	output wire hdmi_hs;
	output wire hdmi_vs;
	output wire hdmi_de;
	output wire [10:0] hdmi_x;
	output wire [9:0] hdmi_y;
	output wire [23:0] hdmi_rgb;
	input wire cpu_clk;
	input wire cpu_rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [3:0] req_be;
	input wire [31:0] req_wdata;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	input wire [31:0] touch_state;
	input wire [31:0] touch_xy;
	input wire [31:0] touch_seq;
	input wire [31:0] touch_errors;
	input wire [127:0] touch_xy_extra;
	input wire [39:0] touch_ids;
	input wire draw_clk;
	input wire draw_rst;
	input wire pix_clk;
	input wire pix_rst;
	output reg lcd_hs;
	output reg lcd_vs;
	output reg lcd_de;
	output reg [7:0] lcd_r;
	output reg [7:0] lcd_g;
	output reg [7:0] lcd_b;
	output wire frame_toggle;
	input wire ddr_clk;
	input wire ddr_rst;
	input wire cpu_valid;
	output wire cpu_ready;
	input wire cpu_write;
	input wire [25:0] cpu_addr;
	input wire [255:0] cpu_wdata;
	input wire [31:0] cpu_wstrb;
	output wire cpu_rsp_valid;
	input wire cpu_rsp_ready;
	output wire [255:0] cpu_rdata;
	output wire cpu_error;
	output wire [27:0] axi_awaddr;
	output wire axi_awvalid;
	input wire axi_awready;
	output wire [255:0] axi_wdata;
	output wire [31:0] axi_wstrb;
	input wire axi_wready;
	output wire [27:0] axi_araddr;
	output wire axi_arvalid;
	input wire axi_arready;
	input wire [255:0] axi_rdata;
	input wire axi_rvalid;
	input wire axi_rlast;
	output wire framebuffer_underflow;
	output wire framebuffer_error;
	localparam FIFO_AW = 10;
	wire cmd_wen;
	wire [37:0] cmd_wdata;
	wire cmd_full;
	wire [FIFO_AW:0] cmd_level;
	wire [15:0] frame_gray;
	wire [15:0] swap_gray;
	wire gpu_idle;
	wire vblank;
	fn_mmio_hub #(
		.CLOCK_HZ(CLOCK_HZ),
		.FIFO_AW(FIFO_AW)
	) u_hub(
		.clk(cpu_clk),
		.rst(cpu_rst),
		.req_valid(req_valid),
		.req_ready(req_ready),
		.req_addr(req_addr),
		.req_write(req_write),
		.req_be(req_be),
		.req_wdata(req_wdata),
		.rsp_valid(rsp_valid),
		.rsp_ready(rsp_ready),
		.rsp_rdata(rsp_rdata),
		.rsp_error(rsp_error),
		.cmd_wen(cmd_wen),
		.cmd_wdata(cmd_wdata),
		.cmd_full(cmd_full),
		.cmd_level(cmd_level),
		.pix_frame_gray(frame_gray),
		.pix_swap_gray(swap_gray),
		.pix_idle(gpu_idle),
		.pix_vblank(vblank),
		.touch_state(touch_state),
		.touch_xy(touch_xy),
		.touch_seq(touch_seq),
		.touch_errors(touch_errors), .touch_xy_extra(touch_xy_extra), .touch_ids(touch_ids)
	);
	wire fifo_empty;
	wire fifo_ren;
	wire [37:0] fifo_rdata;
	fn_async_fifo #(
		.DW(38),
		.AW(FIFO_AW)
	) u_fifo(
		.wclk(cpu_clk),
		.wrst(cpu_rst),
		.wen(cmd_wen),
		.wdata(cmd_wdata),
		.wfull(cmd_full),
		.wlevel(cmd_level),
		.rclk(draw_clk),
		.rrst(draw_rst),
		.ren(fifo_ren),
		.rdata(fifo_rdata),
		.rempty(fifo_empty)
	);
	wire hs0;
	wire vs0;
	wire de0;
	wire frame_latch;
	wire [10:0] tx;
	wire [9:0] ty;
	fn_video_timing u_timing(
		.clk(pix_clk),
		.rst(pix_rst),
		.hs(hs0),
		.vs(vs0),
		.de(de0),
		.x(tx),
		.y(ty),
		.frame_latch(frame_latch),
		.vblank(vblank)
	);
	wire r_start;
	wire r_busy;
	wire [3:0] r_flags;
	wire [2:0] r_mode;
	wire [15:0] r_x0;
	wire [15:0] r_y0;
	wire [9:0] r_w;
	wire [9:0] r_h;
	wire [7:0] r_color;
	wire [31:0] r_u0;
	wire [31:0] r_v0;
	wire [31:0] r_dudx;
	wire [31:0] r_dvdx;
	wire [31:0] r_dudy;
	wire [31:0] r_dvdy;
	wire [6:0] r_src;
	wire [5:0] r_radius;
	wire [3:0] r_variant;
	wire pal_we;
	wire sprite_we;
	wire [17:0] sprite_addr;
	wire [7:0] sprite_data;
	wire [7:0] pal_waddr;
	wire [23:0] pal_wdata;
	wire draw_buf;
	wire disp_buf;
	wire [15:0] frame_count;
	wire swap_request;
	wire swap_done;
	wire scan_commit;
	wire draw_frame_tick;
	wire frame_event_ready;
	fn_cdc_stream #(
		.DW(1),
		.AW(2)
	) frames(
		.wclk(pix_clk),
		.wrst(pix_rst),
		.wvalid(frame_latch),
		.wready(frame_event_ready),
		.wdata(1'b1),
		.rclk(draw_clk),
		.rrst(draw_rst),
		.rvalid(draw_frame_tick),
		.rready(1'b1),
		.rdata()
	);
	reg pal_pending;
	reg [31:0] pal_packet;
	reg pal_marker_sent;
	reg [7:0] pal_generation;
	wire pal_queue_ready;
	wire pal_scan_valid;
	wire pal_lcd_ready;
	wire pal_hdmi_ready;
	wire [40:0] pal_scan_packet;
	wire pal_marker = ((swap_request && !pal_pending) && !pal_we) && !pal_marker_sent;
	wire [40:0] pal_send = {pal_marker, pal_generation, (pal_pending ? pal_packet : 32'd0)};
	fn_cdc_stream #(
		.DW(41),
		.AW(2)
	) palettes(
		.wclk(draw_clk),
		.wrst(draw_rst),
		.wvalid((pal_pending || pal_marker) && pal_hdmi_ready),
		.wready(pal_lcd_ready),
		.wdata(pal_send),
		.rclk(pix_clk),
		.rrst(pix_rst),
		.rvalid(pal_scan_valid),
		.rready(1'b1),
		.rdata(pal_scan_packet)
	);
	always @(posedge draw_clk)
		if (draw_rst) begin
			pal_pending <= 0;
			pal_packet <= 0;
			pal_marker_sent <= 0;
			pal_generation <= 0;
		end
		else begin
			if (pal_pending && pal_queue_ready)
				pal_pending <= 0;
			if (pal_we) begin
				pal_packet <= {pal_waddr, pal_wdata};
				pal_pending <= 1;
			end
			if (pal_marker && pal_queue_ready)
				pal_marker_sent <= 1;
			if (swap_done) begin
				pal_marker_sent <= 0;
				pal_generation <= pal_generation + 8'd1;
			end
		end
	wire hdmi_palette_valid;
	wire [40:0] hdmi_palette_packet;
	assign pal_queue_ready = pal_lcd_ready && pal_hdmi_ready;
	fn_cdc_stream #(
		.DW(41),
		.AW(3)
	) hdmi_palettes(
		.wclk(draw_clk),
		.wrst(draw_rst),
		.wvalid((pal_pending || pal_marker) && pal_lcd_ready),
		.wready(pal_hdmi_ready),
		.wdata(pal_send),
		.rclk(hdmi_clk),
		.rrst(hdmi_rst),
		.rvalid(hdmi_palette_valid),
		.rready(1'b1),
		.rdata(hdmi_palette_packet)
	);
	reg pal_fence_valid;
	reg [7:0] pal_fence_generation;
	always @(posedge pix_clk)
		if (pix_rst) begin
			pal_fence_valid <= 0;
			pal_fence_generation <= 0;
		end
		else begin
			if (scan_commit)
				pal_fence_valid <= 0;
			if (pal_scan_valid && pal_scan_packet[40]) begin
				pal_fence_valid <= 1;
				pal_fence_generation <= pal_scan_packet[39:32];
			end
		end
	wire [7:0] scan_generation;
	wire palette_fenced = pal_fence_valid && (pal_fence_generation == scan_generation);
	fn_gpu_cmd_ddr u_cmd(
		.clk(draw_clk),
		.rst(draw_rst),
		.fifo_empty(((fifo_empty || pal_pending) || pal_we) || !pal_queue_ready),
		.fifo_ren(fifo_ren),
		.fifo_rdata(fifo_rdata),
		.frame_latch(draw_frame_tick),
		.swap_request(swap_request),
		.swap_done(swap_done),
		.r_start(r_start),
		.r_mode(r_mode),
		.r_x0(r_x0),
		.r_y0(r_y0),
		.r_w(r_w),
		.r_h(r_h),
		.r_color(r_color),
		.r_u0(r_u0),
		.r_v0(r_v0),
		.r_dudx(r_dudx),
		.r_dvdx(r_dvdx),
		.r_dudy(r_dudy),
		.r_dvdy(r_dvdy),
		.r_src(r_src),
		.r_flags(r_flags),
		.r_radius(r_radius),
		.r_variant(r_variant),
		.r_busy(r_busy),
		.pal_we(pal_we),
		.pal_addr(pal_waddr),
		.pal_data(pal_wdata),
		.sprite_we(sprite_we),
		.sprite_addr(sprite_addr),
		.sprite_data(sprite_data),
		.draw_buf(draw_buf),
		.disp_buf(disp_buf),
		.frame_gray(frame_gray),
		.swap_gray(swap_gray),
		.frame_count(frame_count),
		.idle(gpu_idle)
	);
	wire fb_we;
	wire fb_ready;
	wire [8:0] fb_wx;
	wire [8:0] fb_wy;
	wire [7:0] fb_wdata;
	fn_raster #(.FONT_INIT(FONT_INIT)) u_raster(
		.sprite_we(sprite_we),
		.sprite_addr(sprite_addr),
		.sprite_data(sprite_data),
		.clk(draw_clk),
		.rst(draw_rst),
		.start(r_start),
		.mode(r_mode),
		.x0(r_x0),
		.y0(r_y0),
		.w(r_w),
		.h(r_h),
		.color(r_color),
		.u0(r_u0),
		.v0(r_v0),
		.dudx(r_dudx),
		.dvdx(r_dvdx),
		.dudy(r_dudy),
		.dvdy(r_dvdy),
		.src(r_src),
		.flags(r_flags),
		.radius(r_radius),
		.variant(r_variant),
		.busy(r_busy),
		.fb_ready(fb_ready),
		.fb_we(fb_we),
		.fb_x(fb_wx),
		.fb_y(fb_wy),
		.fb_data(fb_wdata)
	);
	wire [7:0] fb_index;
	wire actual_front;
	wire producer_drained;
	wire draw_drained;
	wire swap_pending;
	wire scan_index_hit;
	wire h_acquire;
	wire h_acquire_ready;
	wire h_grant_valid;
	wire h_grant_ready;
	wire h_front_valid;
	wire h_front_ready;
	wire h_rsp_valid;
	wire h_rsp_ready;
	wire h_error;
	wire [9:0] h_grant;
	wire [25:0] h_front_addr;
	wire [255:0] h_data;
	wire h_underflow;
	wire h_protocol_error;
	fn_hdmi_scan #(.PAL_INIT(PAL_INIT)) hdmi(
		.clk(hdmi_clk),
		.rst(hdmi_rst),
		.acquire(h_acquire),
		.acquire_ready(h_acquire_ready),
		.grant_valid(h_grant_valid),
		.grant_ready(h_grant_ready),
		.grant(h_grant),
		.front_valid(h_front_valid),
		.front_ready(h_front_ready),
		.front_addr(h_front_addr),
		.front_rsp_valid(h_rsp_valid),
		.front_rsp_ready(h_rsp_ready),
		.front_data(h_data),
		.front_error(h_error),
		.palette_valid(hdmi_palette_valid && !hdmi_palette_packet[40]),
		.palette_packet(hdmi_palette_packet[31:0]),
		.hs(hdmi_hs),
		.vs(hdmi_vs),
		.de(hdmi_de),
		.x(hdmi_x),
		.y(hdmi_y),
		.rgb(hdmi_rgb),
		.underflow(h_underflow),
		.protocol_error(h_protocol_error)
	);
	fn_gpu_ddr_framebuffer_split u_fb(
		.hdmi_clk(hdmi_clk),
		.hdmi_rst(hdmi_rst),
		.hdmi_acquire(h_acquire),
		.hdmi_acquire_ready(h_acquire_ready),
		.hdmi_grant_valid(h_grant_valid),
		.hdmi_grant_ready(h_grant_ready),
		.hdmi_grant(h_grant),
		.hdmi_front_valid(h_front_valid),
		.hdmi_front_ready(h_front_ready),
		.hdmi_front_addr(h_front_addr),
		.hdmi_front_rsp_valid(h_rsp_valid),
		.hdmi_front_rsp_ready(h_rsp_ready),
		.hdmi_front_data(h_data),
		.hdmi_front_error(h_error),
		.draw_clk(draw_clk),
		.draw_rst(draw_rst),
		.palette_fenced(palette_fenced),
		.scan_commit(scan_commit),
		.scan_generation(scan_generation),
		.pix_clk(pix_clk),
		.pix_rst(pix_rst),
		.ddr_clk(ddr_clk),
		.ddr_rst(ddr_rst),
		.pixel_valid(fb_we),
		.pixel_ready(fb_ready),
		.draw_buffer(draw_buf),
		.pixel_x(fb_wx),
		.pixel_y(fb_wy),
		.pixel_data(fb_wdata),
		.raster_quiescent((!r_busy && !r_start) && !fb_we),
		.swap_request(swap_request),
		.swap_done(swap_done),
		.frame_latch(frame_latch),
		.vblank(vblank),
		.scan_valid(de0),
		.scan_x(tx[9:1]),
		.scan_y(ty[9:1]),
		.scan_index(fb_index),
		.scan_index_hit(scan_index_hit),
		.front_buffer(actual_front),
		.underflow(framebuffer_underflow),
		.protocol_error(framebuffer_error),
		.producer_drained(producer_drained),
		.draw_drained(draw_drained),
		.swap_pending(swap_pending),
		.cpu_valid(cpu_valid),
		.cpu_ready(cpu_ready),
		.cpu_write(cpu_write),
		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_wstrb(cpu_wstrb),
		.cpu_rsp_valid(cpu_rsp_valid),
		.cpu_rsp_ready(cpu_rsp_ready),
		.cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error),
		.axi_awaddr(axi_awaddr),
		.axi_awvalid(axi_awvalid),
		.axi_awready(axi_awready),
		.axi_wdata(axi_wdata),
		.axi_wstrb(axi_wstrb),
		.axi_wready(axi_wready),
		.axi_araddr(axi_araddr),
		.axi_arvalid(axi_arvalid),
		.axi_arready(axi_arready),
		.axi_rdata(axi_rdata),
		.axi_rvalid(axi_rvalid),
		.axi_rlast(axi_rlast)
	);
	wire [23:0] rgb;
	fn_palette #(.INIT(PAL_INIT)) u_pal(
		.clk(pix_clk),
		.we(pal_scan_valid && !pal_scan_packet[40]),
		.waddr(pal_scan_packet[31:24]),
		.wdata(pal_scan_packet[23:0]),
		.raddr(fb_index),
		.rdata(rgb)
	);
	reg [2:0] hs_d;
	reg [2:0] vs_d;
	reg [2:0] de_d;
	always @(posedge pix_clk) begin
		hs_d <= {hs_d[1:0], hs0};
		vs_d <= {vs_d[1:0], vs0};
		de_d <= {de_d[1:0], de0};
		if (pix_rst) begin
			lcd_hs <= 1'b1;
			lcd_vs <= 1'b1;
			lcd_de <= 1'b0;
			lcd_r <= 8'd0;
			lcd_g <= 8'd0;
			lcd_b <= 8'd0;
		end
		else begin
			lcd_hs <= hs_d[2];
			lcd_vs <= vs_d[2];
			lcd_de <= de_d[2];
			lcd_r <= (de_d[2] ? rgb[23:16] : 8'd0);
			lcd_g <= (de_d[2] ? rgb[15:8] : 8'd0);
			lcd_b <= (de_d[2] ? rgb[7:0] : 8'd0);
		end
	end
	assign frame_toggle = frame_count[5];
	wire unused_ddr = &{1'b0, actual_front, producer_drained, draw_drained, swap_pending, scan_index_hit, disp_buf};
endmodule

module fn_front_read_mux (
	clk,
	rst,
	a_valid,
	a_ready,
	a_urgent,
	a_addr,
	a_rsp_valid,
	a_rsp_ready,
	a_data,
	a_error,
	b_valid,
	b_ready,
	b_urgent,
	b_addr,
	b_rsp_valid,
	b_rsp_ready,
	b_data,
	b_error,
	valid,
	ready,
	urgent,
	addr,
	rsp_valid,
	rsp_ready,
	data,
	error
);
	input wire clk;
	input wire rst;
	input wire a_valid;
	output wire a_ready;
	input wire a_urgent;
	input wire [25:0] a_addr;
	output wire a_rsp_valid;
	input wire a_rsp_ready;
	output wire [255:0] a_data;
	output wire a_error;
	input wire b_valid;
	output wire b_ready;
	input wire b_urgent;
	input wire [25:0] b_addr;
	output wire b_rsp_valid;
	input wire b_rsp_ready;
	output wire [255:0] b_data;
	output wire b_error;
	output wire valid;
	input wire ready;
	output wire urgent;
	output wire [25:0] addr;
	input wire rsp_valid;
	output wire rsp_ready;
	input wire [255:0] data;
	input wire error;
	reg busy;
	reg owner;
	reg last;
	wire pick_b = b_valid && (!a_valid || !last);
	assign valid = (!rst && !busy) && (a_valid || b_valid);
	assign urgent = (pick_b ? b_urgent : a_urgent);
	assign addr = (pick_b ? b_addr : a_addr);
	assign a_ready = (valid && ready) && !pick_b;
	assign b_ready = (valid && ready) && pick_b;
	assign a_rsp_valid = (busy && !owner) && rsp_valid;
	assign b_rsp_valid = (busy && owner) && rsp_valid;
	assign rsp_ready = busy && (owner ? b_rsp_ready : a_rsp_ready);
	assign a_data = data;
	assign b_data = data;
	assign a_error = error;
	assign b_error = error;
	always @(posedge clk)
		if (rst) begin
			busy <= 0;
			owner <= 0;
			last <= 1;
		end
		else begin
			if (valid && ready) begin
				busy <= 1;
				owner <= pick_b;
				last <= pick_b;
			end
			if (rsp_valid && rsp_ready)
				busy <= 0;
		end
endmodule

module fn_cdc_four_epoch_reset (
	aclk,
	bclk,
	cclk,
	dclk,
	abort,
	arst,
	brst,
	crst,
	drst
);
	input wire aclk;
	input wire bclk;
	input wire cclk;
	input wire dclk;
	input wire abort;
	output wire arst;
	output wire brst;
	output wire crst;
	output wire drst;
	reg ah = 1;
	reg bh = 1;
	reg ch = 1;
	reg dh = 1;
	reg ao = 0;
	reg bo = 0;
	reg co = 0;
	reg d_o = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ba = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ca = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] da = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ab = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] cb = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] db = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ac = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] bc = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] dc = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ad = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] bd = 0;
	(* ASYNC_REG = "TRUE" *) reg [1:0] cd = 0;
	assign arst = abort || ah;
	assign brst = abort || bh;
	assign crst = abort || ch;
	assign drst = abort || dh;
	always @(posedge aclk or posedge abort)
		if (abort) begin
			ah <= 1;
			ao <= 0;
			ba <= 0;
			ca <= 0;
			da <= 0;
		end
		else begin
			if (arst)
				ao <= 1;
			ba <= {ba[0], bo};
			ca <= {ca[0], co};
			da <= {da[0], d_o};
			if (((ao && ba[1]) && ca[1]) && da[1])
				ah <= 0;
		end
	always @(posedge bclk or posedge abort)
		if (abort) begin
			bh <= 1;
			bo <= 0;
			ab <= 0;
			cb <= 0;
			db <= 0;
		end
		else begin
			if (brst)
				bo <= 1;
			ab <= {ab[0], ao};
			cb <= {cb[0], co};
			db <= {db[0], d_o};
			if (((bo && ab[1]) && cb[1]) && db[1])
				bh <= 0;
		end
	always @(posedge cclk or posedge abort)
		if (abort) begin
			ch <= 1;
			co <= 0;
			ac <= 0;
			bc <= 0;
			dc <= 0;
		end
		else begin
			if (crst)
				co <= 1;
			ac <= {ac[0], ao};
			bc <= {bc[0], bo};
			dc <= {dc[0], d_o};
			if (((co && ac[1]) && bc[1]) && dc[1])
				ch <= 0;
		end
	always @(posedge dclk or posedge abort)
		if (abort) begin
			dh <= 1;
			d_o <= 0;
			ad <= 0;
			bd <= 0;
			cd <= 0;
		end
		else begin
			if (drst)
				d_o <= 1;
			ad <= {ad[0], ao};
			bd <= {bd[0], bo};
			cd <= {cd[0], co};
			if (((d_o && ad[1]) && bd[1]) && cd[1])
				dh <= 0;
		end
endmodule

module fn_hdmi_scan (
	clk,
	rst,
	acquire,
	acquire_ready,
	grant_valid,
	grant_ready,
	grant,
	front_valid,
	front_ready,
	front_addr,
	front_rsp_valid,
	front_rsp_ready,
	front_data,
	front_error,
	palette_valid,
	palette_packet,
	hs,
	vs,
	de,
	x,
	y,
	rgb,
	underflow,
	protocol_error
);
	parameter PAL_INIT = "palette.hex";
	input wire clk;
	input wire rst;
	output wire acquire;
	input wire acquire_ready;
	input wire grant_valid;
	output wire grant_ready;
	input wire [9:0] grant;
	output wire front_valid;
	input wire front_ready;
	output wire [25:0] front_addr;
	input wire front_rsp_valid;
	output wire front_rsp_ready;
	input wire [255:0] front_data;
	input wire front_error;
	input wire palette_valid;
	input wire [31:0] palette_packet;
	output wire hs;
	output wire vs;
	output wire de;
	output wire [10:0] x;
	output wire [9:0] y;
	output wire [23:0] rgb;
	output wire underflow;
	output wire protocol_error;
	wire hs0;
	wire vs0;
	wire de0;
	wire latch;
	wire vblank;
	wire [10:0] tx;
	wire [9:0] ty;
	fn_video_timing #(
		.H_ACTIVE(1280),
		.H_FP(110),
		.H_SYNC(40),
		.H_BP(220),
		.V_ACTIVE(720),
		.V_FP(5),
		.V_SYNC(5),
		.V_BP(20),
		.HS_POL(1),
		.VS_POL(1)
	) timing(
		.clk(clk),
		.rst(rst),
		.hs(hs0),
		.vs(vs0),
		.de(de0),
		.x(tx),
		.y(ty),
		.frame_latch(latch),
		.vblank(vblank)
	);
	reg want;
	reg waiting;
	reg have_frame;
	reg [1:0] slot;
	reg [7:0] generation;
	wire busy;
	wire row_ready;
	wire row_done;
	wire row_error;
	wire [1:0] cache_valid;
	wire [16:0] tag0;
	wire [16:0] tag1;
	wire game = (((de0 && (tx >= 128)) && (tx < 1152)) && (ty >= 60)) && (ty < 660);
	wire [8:0] sy = (ty - 10'd60) >> 1;
	wire [8:0] sx = (tx - 11'd128) >> 1;
	wire [16:0] current_tag = {generation, sy};
	wire [16:0] zero_tag = {generation, 9'd0};
	wire [16:0] next_tag = {generation, sy + 9'd1};
	wire cur0 = cache_valid[0] && (tag0 == current_tag);
	wire cur1 = cache_valid[1] && (tag1 == current_tag);
	wire zero0 = cache_valid[0] && (tag0 == zero_tag);
	wire zero1 = cache_valid[1] && (tag1 == zero_tag);
	wire next_hit = (cache_valid[0] && (tag0 == next_tag)) || (cache_valid[1] && (tag1 == next_tag));
	wire idle = !busy && !front_valid;
	assign acquire = (want && !waiting) && idle;
	assign grant_ready = waiting && idle;
	wire commit = grant_valid && grant_ready;
	always @(posedge clk)
		if (rst) begin
			want <= 0;
			waiting <= 0;
			have_frame <= 0;
			slot <= 0;
			generation <= 0;
		end
		else begin
			if (latch)
				want <= 1;
			if (acquire && acquire_ready) begin
				want <= 0;
				waiting <= 1;
			end
			if (commit) begin
				slot <= grant[9:8];
				generation <= grant[7:0];
				waiting <= 0;
				have_frame <= 1;
			end
		end
	wire [25:0] base = 26'h3f00000 + {6'd0, slot, 18'd0};
	reg row_valid;
	reg row_slot;
	reg [16:0] row_tag;
	reg [25:0] row_addr;
	always @(*) begin
		row_valid = 0;
		row_slot = 0;
		row_tag = 0;
		row_addr = 0;
		if ((((!rst && have_frame) && !want) && !waiting) && !commit) begin
			if ((vblank || (ty < 60)) || (ty >= 660)) begin
				if (!zero0 && !zero1) begin
					row_valid = 1;
					row_slot = 0;
					row_tag = zero_tag;
					row_addr = base;
				end
			end
			else if (sy < 300) begin
				if (!cur0 && !cur1) begin
					row_valid = 1;
					row_slot = 0;
					row_tag = current_tag;
					row_addr = base + {8'd0, sy, 9'd0};
				end
				else if ((sy < 299) && !next_hit) begin
					row_valid = 1;
					row_slot = cur0;
					row_tag = next_tag;
					row_addr = base + {8'd0, sy + 9'd1, 9'd0};
				end
			end
		end
	end
	wire [7:0] index;
	wire scan_rsp;
	wire hit;
	wire cache_error;
	fn_ddr_row_cache_pix cache(
		.clk(clk),
		.rst(rst),
		.calibrated(1'b1),
		.commit(commit),
		.commit_tag({grant[7:0], 9'd0}),
		.row_valid(row_valid),
		.row_ready(row_ready),
		.row_slot(row_slot),
		.row_tag(row_tag),
		.row_addr(row_addr),
		.display_lock((game ? {cur1, cur0} : 2'b00)),
		.row_done(row_done),
		.row_error(row_error),
		.busy(busy),
		.cache_valid(cache_valid),
		.cache_tag0(tag0),
		.cache_tag1(tag1),
		.front_valid(front_valid),
		.front_ready(front_ready),
		.front_addr(front_addr),
		.front_rsp_valid(front_rsp_valid),
		.front_rsp_ready(front_rsp_ready),
		.front_rdata(front_data),
		.front_error(front_error),
		.scan_valid(game && have_frame),
		.scan_tag(current_tag),
		.scan_x(sx),
		.scan_rsp_valid(scan_rsp),
		.scan_data(index),
		.scan_hit(hit),
		.underflow(underflow),
		.clear_underflow(1'b0),
		.protocol_error(cache_error)
	);
	wire [23:0] game_rgb;
	reg [7:0] index_d;
	always @(posedge clk)
		if (rst)
			index_d <= 0;
		else
			index_d <= index;
	fn_palette #(.INIT(PAL_INIT)) palette(
		.clk(clk),
		.we(palette_valid),
		.waddr(palette_packet[31:24]),
		.wdata(palette_packet[23:0]),
		.raddr(index_d),
		.rdata(game_rgb)
	);
	reg [2:0] hd;
	reg [2:0] vd;
	reg [2:0] dd;
	reg [2:0] gd;
	reg [10:0] xd [0:2];
	reg [9:0] yd [0:2];
	integer k;
	always @(posedge clk)
		if (rst) begin
			hd <= 0;
			vd <= 0;
			dd <= 0;
			gd <= 0;
			for (k = 0; k < 3; k = k + 1)
				begin
					xd[k] <= 0;
					yd[k] <= 0;
				end
		end
		else begin
			hd <= {hd[1:0], hs0};
			vd <= {vd[1:0], vs0};
			dd <= {dd[1:0], de0};
			gd <= {gd[1:0], game && have_frame};
			xd[0] <= tx;
			yd[0] <= ty;
			for (k = 1; k < 3; k = k + 1)
				begin
					xd[k] <= xd[k - 1];
					yd[k] <= yd[k - 1];
				end
		end
	assign hs = hd[2];
	assign vs = vd[2];
	assign de = dd[2];
	assign x = xd[2];
	assign y = yd[2];
	assign rgb = (gd[2] ? game_rgb : 24'h080c18);
	assign protocol_error = cache_error || row_error;
endmodule

module fn_camera_preview (
	ai_clk,
	ai_rst,
	pix_valid,
	sof,
	pix,
	cam_x,
	cam_y,
	clk,
	rst,
	frame_start,
	rx,
	ry,
	rgb,
	image_valid
);
	parameter integer WIDTH=160, HEIGHT=90, SAMPLE_LOG=3;
	input wire ai_clk;
	input wire ai_rst;
	input wire pix_valid;
	input wire sof;
	input wire [15:0] pix;
	input wire [10:0] cam_x;
	input wire [9:0] cam_y;
	input wire clk;
	input wire rst;
	input wire frame_start;
	input wire [7:0] rx;
	input wire [6:0] ry;
	output wire [23:0] rgb;
	output reg image_valid;
	(* syn_ramstyle = "block_ram" *) reg [7:0] bank0 [0:WIDTH*HEIGHT-1];
	(* syn_ramstyle = "block_ram" *) reg [7:0] bank1 [0:WIDTH*HEIGHT-1];
	reg writing;
	reg write_bank;
	reg bad;
	reg pending;
	reg sealed;
	reg [13:0] count;
	wire complete_valid;
	wire complete_ready;
	wire complete_bank;
	wire release_valid;
	wire release_ready;
	wire release_bank;
	wire sample = (((pix_valid && (cam_x < 1280)) && (cam_y < 720)) && ((cam_x & ((1 << SAMPLE_LOG)-1)) == 0)) && ((cam_y & ((1 << SAMPLE_LOG)-1)) == 0);
	wire [13:0] address = ((cam_y >> SAMPLE_LOG) * WIDTH) + (cam_x >> SAMPLE_LOG);
	wire [7:0] pixel332 = {pix[15:13], pix[10:8], pix[4:3]};
	fn_cdc_stream #(
		.DW(1),
		.AW(2)
	) complete_frames(
		.wclk(ai_clk),
		.wrst(ai_rst),
		.wvalid(pending),
		.wready(complete_ready),
		.wdata(write_bank),
		.rclk(clk),
		.rrst(rst),
		.rvalid(complete_valid),
		.rready(1'b1),
		.rdata(complete_bank)
	);
	reg read_bank;
	wire release_valid_ai;
	fn_cdc_stream #(
		.DW(1),
		.AW(2)
	) releases(
		.wclk(clk),
		.wrst(rst),
		.wvalid(release_valid),
		.wready(release_ready),
		.wdata(read_bank),
		.rclk(ai_clk),
		.rrst(ai_rst),
		.rvalid(release_valid_ai),
		.rready(1'b1),
		.rdata(release_bank)
	);
	always @(posedge ai_clk)
		if (ai_rst) begin
			writing <= 0;
			write_bank <= 0;
			bad <= 0;
			count <= 0;
			pending <= 0;
			sealed <= 0;
		end
		else begin
			if (pending && complete_ready)
				pending <= 0;
			if (release_valid_ai) begin
				write_bank <= release_bank;
				sealed <= 0;
			end
			if (sof) begin
				writing <= !sealed;
				count <= 0;
				bad <= 0;
			end
			if (sample && (sof ? !sealed : writing)) begin
				if (address != (sof ? 14'd0 : count))
					bad <= 1;
				if (write_bank)
					bank1[address] <= pixel332;
				else
					bank0[address] <= pixel332;
				count <= (sof ? 14'd0 : count) + 1'b1;
				if (address == (WIDTH*HEIGHT-1)) begin
					writing <= 0;
					if (!bad && (count == (WIDTH*HEIGHT-1))) begin
						pending <= 1;
						sealed <= 1;
					end
				end
			end
		end
	reg staged;
	reg staged_bank;
	reg [7:0] q0;
	reg [7:0] q1;
	wire [13:0] read_address = (ry * WIDTH) + rx;
	assign release_valid = frame_start && staged;
	always @(posedge clk) begin
		q0 <= bank0[read_address];
		q1 <= bank1[read_address];
		if (rst) begin
			staged <= 0;
			staged_bank <= 0;
			read_bank <= 1;
			image_valid <= 0;
		end
		else begin
			if (complete_valid) begin
				staged <= 1;
				staged_bank <= complete_bank;
			end
			if (release_valid && release_ready) begin
				staged <= 0;
				read_bank <= staged_bank;
				image_valid <= 1;
			end
		end
	end
	wire [7:0] q = (read_bank ? q1 : q0);
	assign rgb = (image_valid ? {q[7:5], q[7:5], q[7:6], q[4:2], q[4:2], q[4:3], q[1:0], q[1:0], q[1:0], q[1:0]} : 24'h182438);
endmodule

module p2_overlay (
	clk,
	rst,
	de,
	vs,
	rgb_in,
	rgb_out,
	ovl_toggle,
	dot_en,
	seg_en,
	box_en,
	box0,
	box1,
	dots,
	segs
);
	parameter integer NDOT = 12;
	parameter integer NSEG = 12;
	parameter integer R = 5;
	input wire clk;
	input wire rst;
	input wire de;
	input wire vs;
	input wire [23:0] rgb_in;
	output wire [23:0] rgb_out;
	input wire ovl_toggle;
	input wire [NDOT - 1:0] dot_en;
	input wire [NSEG - 1:0] seg_en;
	input wire box_en;
	input wire [31:0] box0;
	input wire [31:0] box1;
	input wire [(32 * NDOT) - 1:0] dots;
	input wire [(160 * NSEG) - 1:0] segs;
	(* async_reg = "true" *) reg t1;
	(* async_reg = "true" *) reg t2;
	reg tseen;
	reg staged;
	reg [5:0] age;
	reg [NDOT - 1:0] st_dot_en;
	reg [NDOT - 1:0] a_dot_en;
	reg [NSEG - 1:0] st_seg_en;
	reg [NSEG - 1:0] a_seg_en;
	reg st_box_en;
	reg a_box_en;
	reg [31:0] st_box0;
	reg [31:0] st_box1;
	reg [31:0] a_box0;
	reg [31:0] a_box1;
	reg [(32 * NDOT) - 1:0] st_dots;
	reg [(32 * NDOT) - 1:0] a_dots;
	reg [(160 * NSEG) - 1:0] st_segs;
	reg [(160 * NSEG) - 1:0] a_segs;
	reg vs_q;
	reg de_q;
	wire frame_start = vs && !vs_q;
	always @(posedge clk)
		if (rst) begin
			age <= 0;
			t1 <= 0;
			t2 <= 0;
			tseen <= 0;
			staged <= 0;
			a_dot_en <= 0;
			a_seg_en <= 0;
			a_box_en <= 0;
		end
		else begin
			t1 <= ovl_toggle;
			t2 <= t1;
			if (frame_start && (age < 63))
				age <= age + 1'b1;
			if (frame_start && (age >= 18)) begin
				a_dot_en <= 0;
				a_seg_en <= 0;
				a_box_en <= 0;
			end
			if (t2 != tseen) begin
				age <= 0;
				tseen <= t2;
				staged <= 1;
				st_dot_en <= dot_en;
				st_seg_en <= seg_en;
				st_box_en <= box_en;
				st_box0 <= box0;
				st_box1 <= box1;
				st_dots <= dots;
				st_segs <= segs;
			end
			else if (frame_start && staged) begin
				staged <= 0;
				a_dot_en <= st_dot_en;
				a_seg_en <= st_seg_en;
				a_box_en <= st_box_en;
				a_box0 <= st_box0;
				a_box1 <= st_box1;
				a_dots <= st_dots;
				a_segs <= st_segs;
			end
		end
	reg signed [12:0] px;
	reg signed [12:0] py;
	always @(posedge clk) begin
		vs_q <= vs;
		de_q <= de;
		if (rst || vs) begin
			px <= 0;
			py <= 0;
		end
		else if (de)
			px <= px + 1'b1;
		else if (de_q) begin
			px <= 0;
			py <= py + 1'b1;
		end
	end
	wire line_end = de_q && !de;
	wire [NSEG - 1:0] seg_hit;
	genvar _gv_s_1;
	generate
		for (_gv_s_1 = 0; _gv_s_1 < NSEG; _gv_s_1 = _gv_s_1 + 1) begin : seg
			localparam s = _gv_s_1;
			wire signed [31:0] c00 = a_segs[160 * s+:32];
			wire signed [31:0] d00 = a_segs[(160 * s) + 32+:32];
			wire signed [15:0] dx = a_segs[(160 * s) + 64+:16];
			wire signed [15:0] dy = a_segs[(160 * s) + 80+:16];
			wire signed [31:0] lim = a_segs[(160 * s) + 96+:32];
			wire signed [31:0] len2 = a_segs[(160 * s) + 128+:32];
			reg signed [31:0] cl;
			reg signed [31:0] dl;
			reg signed [31:0] c;
			reg signed [31:0] d;
			always @(posedge clk)
				if (vs) begin
					cl <= c00;
					dl <= d00;
					c <= c00;
					d <= d00;
				end
				else if (de) begin
					c <= c + dy;
					d <= d + dx;
				end
				else if (line_end) begin
					cl <= cl - dx;
					dl <= dl + dy;
					c <= cl - dx;
					d <= dl + dy;
				end
			wire signed [31:0] ac = (c < 0 ? -c : c);
			assign seg_hit[s] = ((a_seg_en[s] && (ac <= lim)) && (d >= 0)) && (d <= len2);
		end
	endgenerate
	wire [NDOT - 1:0] dot_hit;
	genvar _gv_j_1;
	generate
		for (_gv_j_1 = 0; _gv_j_1 < NDOT; _gv_j_1 = _gv_j_1 + 1) begin : dot
			localparam j = _gv_j_1;
			wire signed [12:0] xd = {a_dots[(32 * j) + 11], a_dots[32 * j+:12]};
			wire signed [12:0] yd = {a_dots[(32 * j) + 27], a_dots[(32 * j) + 16+:12]};
			wire signed [13:0] ex = px - xd;
			wire signed [13:0] ey = py - yd;
			wire [13:0] ax = (ex < 0 ? -ex : ex);
			wire [13:0] ay = (ey < 0 ? -ey : ey);
			assign dot_hit[j] = ((a_dot_en[j] && (ax <= R)) && (ay <= R)) && ((ax + ay) <= ((R * 3) / 2));
		end
	endgenerate
	wire signed [12:0] bx0 = {a_box0[11], a_box0[11:0]};
	wire signed [12:0] by0 = {a_box0[27], a_box0[27:16]};
	wire signed [12:0] bx1 = {a_box1[11], a_box1[11:0]};
	wire signed [12:0] by1 = {a_box1[27], a_box1[27:16]};
	wire in_x = (px >= (bx0 - 1)) && (px <= (bx1 + 1));
	wire in_y = (py >= (by0 - 1)) && (py <= (by1 + 1));
	wire near_x = ((px >= (bx0 - 1)) && (px <= bx0)) || ((px >= bx1) && (px <= (bx1 + 1)));
	wire near_y = ((py >= (by0 - 1)) && (py <= by0)) || ((py >= by1) && (py <= (by1 + 1)));
	wire box_hit = a_box_en && ((in_x && near_y) || (in_y && near_x));
	localparam [11:0] SEG_LEFT = 12'h306;
	localparam [11:0] SEG_RIGHT = 12'hc18;
	wire left_dot = |(dot_hit & {NDOT / 2 {2'b01}});
	wire right_dot = |(dot_hit & {NDOT / 2 {2'b10}});
	wire left_seg = |(seg_hit & SEG_LEFT);
	wire right_seg = |(seg_hit & SEG_RIGHT);
	wire any_seg = |seg_hit;
	assign rgb_out = (!de ? rgb_in : (left_dot ? 24'ha0ffff : (right_dot ? 24'hffd0a0 : (left_seg ? 24'h00e0ff : (right_seg ? 24'hff8000 : (any_seg ? 24'hf0f040 : (box_hit ? 24'h40ff40 : rgb_in)))))));
endmodule


module p2_clmul_pipeline (
	clk,
	rst,
	cancel,
	take,
	consume,
	kind,
	a,
	b,
	ready,
	result
);
	input wire clk;
	input wire rst;
	input wire cancel;
	input wire take;
	input wire consume;
	input wire [2:0] kind;
	input wire [31:0] a;
	input wire [31:0] b;
	output reg ready;
	output wire [31:0] result;
	function automatic [31:0] poly16;
		input [15:0] lhs;
		input [15:0] rhs;
		reg [31:0] term [0:15];
		reg [31:0] pair_term [0:7];
		reg [31:0] quad [0:3];
		reg [31:0] octet [0:1];
		integer i;
		begin
			for (i = 0; i < 16; i = i + 1)
				term[i] = ({16'b0000000000000000, lhs} << i) & {32 {rhs[i]}};
			for (i = 0; i < 8; i = i + 1)
				pair_term[i] = term[2 * i] ^ term[(2 * i) + 1];
			for (i = 0; i < 4; i = i + 1)
				quad[i] = pair_term[2 * i] ^ pair_term[(2 * i) + 1];
			for (i = 0; i < 2; i = i + 1)
				octet[i] = quad[2 * i] ^ quad[(2 * i) + 1];
			poly16 = octet[0] ^ octet[1];
		end
	endfunction
	reg [31:0] ll_q;
	reg [31:0] lh_q;
	reg [31:0] hl_q;
	reg [31:0] hh_q;
	reg [2:0] kind_q;
	wire [63:0] product = ({32'b00000000000000000000000000000000, ll_q} ^ {hh_q, 32'b00000000000000000000000000000000}) ^ ({16'b0000000000000000, lh_q, 16'b0000000000000000} ^ {16'b0000000000000000, hl_q, 16'b0000000000000000});
	assign result = (kind_q == 3'd1 ? product[31:0] : (kind_q == 3'd2 ? product[62:31] : product[63:32]));
	always @(posedge clk)
		if ((rst || cancel) || consume)
			ready <= 0;
		else if (take && !ready) begin
			ll_q <= poly16(a[15:0], b[15:0]);
			lh_q <= poly16(a[15:0], b[31:16]);
			hl_q <= poly16(a[31:16], b[15:0]);
			hh_q <= poly16(a[31:16], b[31:16]);
			kind_q <= kind;
			ready <= 1;
		end
endmodule

module p4_dot_mmio #(
    parameter [31:0] BASE_ADDR = 32'h10003000,
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
    wire in_page = (req_addr >= BASE_ADDR) && (offset < 32'h00001000);
    wire a_access = (offset >= 32'h00000100) &&
                    (offset < (32'h00000100 + 32'd256));
    wire b_access = (offset >= 32'h00000200) &&
                    (offset < (32'h00000200 + 32'd256));
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
    wire control_write = register_write && (offset == 32'h00000008);
    wire start_allowed = !engine_busy && !result_valid && !done_pending &&
                         (length_reg >= 32'd1) && (length_reg <= 32'h00000100);
    assign start_o = control_write && (req_wdata == 32'd1) && start_allowed;
    assign soft_reset_o = control_write && (req_wdata == 32'd2);
    wire software_w1c = register_write && (offset == 32'h00000014) &&
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
                32'h00000000: begin
                    read_snapshot = 32'h50345331;
                    access_error = req_write;
                end
                32'h00000004: begin
                    read_snapshot = 32'h00000100;
                    access_error = req_write;
                end
                32'h00000008: if (req_write) begin
                    case (req_wdata)
                        32'd0, 32'd2: access_error = 1'b0;
                        32'd1: access_error = !start_allowed;
                        default: access_error = 1'b1;
                    endcase
                end
                32'h0000000c: begin
                    read_snapshot = {29'd0, done_pending, result_valid, engine_busy};
                    access_error = req_write;
                end
                32'h00000010: begin
                    read_snapshot = length_reg;
                    access_error = req_write && engine_busy;
                end
                32'h00000014: begin
                    read_snapshot = {31'd0, done_pending};
                    access_error = req_write && (req_wdata[31:1] != 31'd0);
                end
                32'h00000018: begin
                    read_snapshot = {31'd0, intr_enable};
                    access_error = req_write && (req_wdata[31:1] != 31'd0);
                end
                32'h0000001c: begin
                    read_snapshot = result_reg;
                    access_error = req_write;
                end
                32'h00000020: begin
                    read_snapshot = submit_id;
                    access_error = req_write;
                end
                32'h00000024: begin
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
                if (offset == 32'h00000010) length_reg <= req_wdata;
                else if (offset == 32'h00000018) intr_enable <= req_wdata[0];
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

module p4_int8_dot (
	clk,
	rst,
	cancel,
	start,
	length,
	read_index,
	a_data,
	b_data,
	busy,
	complete,
	result
);
	input wire clk;
	input wire rst;
	input wire cancel;
	input wire start;
	input wire [8:0] length;
	output wire [7:0] read_index;
	input wire [7:0] a_data;
	input wire [7:0] b_data;
	output wire busy;
	output wire complete;
	output wire [31:0] result;
	localparam [1:0] IDLE = 2'd0;
	localparam [1:0] READ = 2'd1;
	localparam [1:0] MAC = 2'd2;
	reg [1:0] state;
	reg [8:0] task_length;
	reg [7:0] index;
	reg signed [7:0] a_sample;
	reg signed [7:0] b_sample;
	reg signed [31:0] accumulator;
	wire signed [15:0] product = a_sample * b_sample;
	wire signed [31:0] product_extended = {{16 {product[15]}}, product};
	wire signed [31:0] sum = accumulator + product_extended;
	wire last_item = ({1'b0, index} + 9'd1) == task_length;
	assign read_index = index;
	assign busy = state != IDLE;
	assign complete = (((state == MAC) && last_item) && !rst) && !cancel;
	assign result = sum;
	always @(posedge clk)
		if (rst || cancel) begin
			state <= IDLE;
			task_length <= 9'd0;
			index <= 8'd0;
		end
		else
			case (state)
				IDLE:
					if (start) begin
						state <= READ;
						task_length <= length;
						index <= 8'd0;
					end
				READ: state <= MAC;
				MAC:
					if (last_item)
						state <= IDLE;
					else begin
						index <= index + 8'd1;
						state <= READ;
					end
				default: state <= IDLE;
			endcase
	always @(posedge clk)
		if (rst) begin
			a_sample <= 8'sd0;
			b_sample <= 8'sd0;
			accumulator <= 32'sd0;
		end
		else
			case (state)
				IDLE:
					if (start)
						accumulator <= 32'sd0;
				READ: begin
					a_sample <= $signed(a_data);
					b_sample <= $signed(b_data);
				end
				MAC: accumulator <= sum;
				default:
					;
			endcase
endmodule

module fn_gpu_pll6075 (
    
    output wire clkout0,
    output wire clkout1,
    
    input wire clkin1,
    
    output wire lock           
    );

    // Parameter
    
    localparam real    CLKIN_FREQ       = 27.0; //@IPC float 10.0,500.0 
    
    localparam         LOCK_MODE        = 0; //@IPC enum 0,1
    
    localparam integer STATIC_RATIOI    = 1; //@IPC int 1,80
    
    localparam integer STATIC_RATIOM    = 1; //@IPC int 1,128 
    
    localparam real    STATIC_RATIO0    = 6.0; //@IPC int 1.0000,128.0000 
        
    localparam integer STATIC_RATIO1    = 13; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO2    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO3    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO4    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO5    = 17; //@IPC int 1,128 
    
    localparam integer STATIC_RATIO6    = 17; //@IPC int 1,128 
    
    localparam real    STATIC_RATIOF    = 36.0; //@IPC int 1.0000,128.0000 
        
    localparam integer STATIC_RATIOPHY  = 1; //@IPC int 1,128 
    
    localparam integer STATIC_DUTY0     = 6; //@IPC int 2,255
    
    localparam integer STATIC_DUTY1     = 13; //@IPC int 2,255
    
    localparam integer STATIC_DUTY2     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY3     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY4     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY5     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTY6     = 17; //@IPC int 2,255
    
    localparam integer STATIC_DUTYF     = 36; //@IPC int 2,255
    
    localparam integer STATIC_DUTYPHY   = 2; //@IPC int 2,255
    
    localparam integer STATIC_PHASE     = 0; //@IPC int 0,63 
    
    localparam integer STATIC_PHASE0    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE1    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE2    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE3    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE4    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE5    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASE6    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASEF    = 0; //@IPC int 0,7 
    
    localparam integer STATIC_PHASEPHY  = 0; //@IPC int 0,7 
    
    localparam integer STATIC_CPHASE0   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE1   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE2   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE3   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE4   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE5   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASE6   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASEF   = 0; //@IPC int 0,127 
    
    localparam integer STATIC_CPHASEPHY = 0; //@IPC int 0,127 
    
    localparam         CLK_DPS0_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS1_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS2_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS3_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS4_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS5_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPS6_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_DPSF_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLK_CAS5_EN      = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT0_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT1_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT2_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT3_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT4_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT5_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUT6_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUTF_SYN_EN   = "FALSE"; //@IPC bool 
    
    localparam         CLKOUTPHY_SYN_EN = "FALSE"; //@IPC bool 
    
    localparam         SSC_MODE         = "DISABLE"; //@IPC enum DISABLE, DOWN_LOW, DOWN_HIGH, CENTER_LOW, CENTER_HIGH
    
    localparam real    SSC_FREQ         = 25; //@IPC int 25,250
    
    localparam         INTERNAL_FB      = "CLKOUTF"; //@IPC enum CLKOUT0,CLKOUT1,CLKOUT2,CLKOUT3,CLKOUT4,CLKOUT5,CLKOUT6,DISABLE 
    
    localparam         EXTERNAL_FB      = "DISABLE"; //@IPC enum CLKOUT0,CLKOUT1,CLKOUT2,CLKOUT3,CLKOUT4,CLKOUT5,CLKOUT6,DISABLE 
    
    localparam         BANDWIDTH        = "OPTIMIZED"; //@IPC enum OPTIMIZED,LOW,HIGH 
    
    wire clkin2;
    assign clkin2 = 1'b0;
    
    wire clkfb;
    assign clkfb = 1'b0;
    
    wire clkin_sel;
    assign clkin_sel = 1'b0;
    
    wire dps_clk;
    wire dps_en;
    wire dps_dir;
    assign dps_clk = 1'b0;
    assign dps_en = 1'b0;
    assign dps_dir = 1'b0;
        
    wire clkout0_syn;
    assign clkout0_syn = 1'b0;
    
    wire clkout1_syn;
    assign clkout1_syn = 1'b0;
    
    wire clkout2_syn;
    assign clkout2_syn = 1'b0;
    
    wire clkout3_syn;
    assign clkout3_syn = 1'b0;
    
    wire clkout4_syn;
    assign clkout4_syn = 1'b0;
    
    wire clkout5_syn;
    assign clkout5_syn = 1'b0;
        
    wire clkout6_syn;
    assign clkout6_syn = 1'b0;
        
    wire clkoutf_syn;
    assign clkoutf_syn = 1'b0;
    
    wire pll_pwd;
    assign pll_pwd = 1'b0;
    
    wire rst;
    assign rst = 1'b0;
    
    wire apb_clk;
    wire apb_rst_n;
    wire [4:0] apb_addr;
    wire apb_sel;
    wire apb_en;
    wire apb_write;
    wire [15:0] apb_wdata;

    assign apb_clk = 1'd0;
    assign apb_rst_n = 1'd0;
    assign apb_addr [4:0] = 5'd0;
    assign apb_sel = 1'd0;
    assign apb_en = 1'd0;
    assign apb_write = 1'd0;
    assign apb_wdata [15:0] = 16'd0;
    
    GTP_GPLL #(

    .CLKIN_FREQ      (CLKIN_FREQ    ),   
    .LOCK_MODE       (LOCK_MODE     ),   
    .STATIC_RATIOI   (STATIC_RATIOI ),   
    .STATIC_RATIOM   (STATIC_RATIOM ),   
    
    .STATIC_RATIO0   (STATIC_RATIO0 ),   
    .STATIC_RATIO1   (STATIC_RATIO1 ),   
    .STATIC_RATIO2   (STATIC_RATIO2 ),   
    .STATIC_RATIO3   (STATIC_RATIO3 ),   
    .STATIC_RATIO4   (STATIC_RATIO4 ),   
    
    .STATIC_RATIO5   (STATIC_RATIO5 ),   
    .STATIC_RATIO6   (STATIC_RATIO6 ),   
    
    .STATIC_RATIOF   (STATIC_RATIOF ),   
    
    .STATIC_DUTY0    (STATIC_DUTY0  ),  
    .STATIC_DUTY1    (STATIC_DUTY1  ),  
    .STATIC_DUTY2    (STATIC_DUTY2  ),  
    .STATIC_DUTY3    (STATIC_DUTY3  ),  
    .STATIC_DUTY4    (STATIC_DUTY4  ),  
    
    .STATIC_DUTY5    (STATIC_DUTY5  ),  
    .STATIC_DUTY6    (STATIC_DUTY6  ),  
    
    .STATIC_DUTYF    (STATIC_DUTYF  ),  
    
    .STATIC_PHASE    (STATIC_PHASE  ),
    
    .STATIC_PHASE0   (STATIC_PHASE0 ),
    .STATIC_PHASE1   (STATIC_PHASE1 ),
    .STATIC_PHASE2   (STATIC_PHASE2 ),
    .STATIC_PHASE3   (STATIC_PHASE3 ),
    .STATIC_PHASE4   (STATIC_PHASE4 ),
    
    .STATIC_PHASE5   (STATIC_PHASE5 ),
    .STATIC_PHASE6   (STATIC_PHASE6 ),
    
    .STATIC_PHASEF   (STATIC_PHASEF ),
    
    .STATIC_CPHASE0  (STATIC_CPHASE0),
    .STATIC_CPHASE1  (STATIC_CPHASE1),
    .STATIC_CPHASE2  (STATIC_CPHASE2),
    .STATIC_CPHASE3  (STATIC_CPHASE3),
    .STATIC_CPHASE4  (STATIC_CPHASE4),
    
    .STATIC_CPHASE5  (STATIC_CPHASE5),
    .STATIC_CPHASE6  (STATIC_CPHASE6),
    
    .STATIC_CPHASEF  (STATIC_CPHASEF),
    
    .CLK_DPS0_EN     (CLK_DPS0_EN   ),  
    .CLK_DPS1_EN     (CLK_DPS1_EN   ),  
    .CLK_DPS2_EN     (CLK_DPS2_EN   ),  
    .CLK_DPS3_EN     (CLK_DPS3_EN   ),  
    .CLK_DPS4_EN     (CLK_DPS4_EN   ),  
    .CLK_DPS5_EN     (CLK_DPS5_EN   ),  
    .CLK_DPS6_EN     (CLK_DPS6_EN   ),  
    .CLK_DPSF_EN     (CLK_DPSF_EN   ),  
    .CLK_CAS5_EN     (CLK_CAS5_EN   ),  
    
    .CLKOUT0_SYN_EN  (CLKOUT0_SYN_EN),
    .CLKOUT1_SYN_EN  (CLKOUT1_SYN_EN),
    .CLKOUT2_SYN_EN  (CLKOUT2_SYN_EN),
    .CLKOUT3_SYN_EN  (CLKOUT3_SYN_EN),
    .CLKOUT4_SYN_EN  (CLKOUT4_SYN_EN),
    
    .CLKOUT5_SYN_EN  (CLKOUT5_SYN_EN),
    .CLKOUT6_SYN_EN  (CLKOUT6_SYN_EN),
    
    .CLKOUTF_SYN_EN  (CLKOUTF_SYN_EN),
    
    .SSC_MODE       (SSC_MODE       ),
    .SSC_FREQ       (SSC_FREQ       ),
    
    .INTERNAL_FB    (INTERNAL_FB    ),
    .EXTERNAL_FB    (EXTERNAL_FB    ),
    .BANDWIDTH      (BANDWIDTH      )
    
    ) u_gpll (
    
    .CLKOUT0        (clkout0        ),
        
    .CLKOUT0N       (               ),
    
    .CLKOUT1        (clkout1        ),
    
    .CLKOUT1N       (               ),
    
    .CLKOUT2        (               ),
    
    .CLKOUT2N       (               ),
    
    .CLKOUT3        (               ),
    
    .CLKOUT3N       (               ),
    
    .CLKOUT4        (               ),
    
    .CLKOUT5        (               ),
        
    .CLKOUT6        (               ),
        
    .CLKOUTF        (               ),
    
    .CLKOUTFN       (               ),
    
    .LOCK           (lock           ),
    
    .DPS_DONE       (               ),
        
    .DPS_CLK        (dps_clk        ),
    .DPS_EN         (dps_en         ),
    .DPS_DIR        (dps_dir        ),
    
    .CLKIN1         (clkin1         ),
    
    .CLKIN2         (clkin2         ),
    
    .CLKFB          (clkfb          ),
    .CLKIN_SEL      (clkin_sel      ),
    .CLKOUT0_SYN    (clkout0_syn    ),
    .CLKOUT1_SYN    (clkout1_syn    ),
    .CLKOUT2_SYN    (clkout2_syn    ),
    .CLKOUT3_SYN    (clkout3_syn    ),
    .CLKOUT4_SYN    (clkout4_syn    ),
    
    .CLKOUT5_SYN    (clkout5_syn    ),
    .CLKOUT6_SYN    (clkout6_syn    ),
    
    .CLKOUTF_SYN    (clkoutf_syn    ),
    .PLL_PWD        (pll_pwd        ),
    .RST            (rst            ),
    
    .APB_RDATA      (               ),
    .APB_READY      (               ),
    
    .APB_CLK        (apb_clk        ),
    .APB_RST_N      (apb_rst_n      ),
    .APB_ADDR       (apb_addr[4:0]  ),
    .APB_SEL        (apb_sel        ),
    .APB_EN         (apb_en         ),
    .APB_WRITE      (apb_write      ),
    .APB_WDATA      (apb_wdata[15:0])   
);


endmodule

`timescale 1ns / 1ps
// Full-throughput valid/ready register slice (two-entry skid buffer).
// Every output (m_valid, m_data, s_ready) is a flip-flop, so no combinational
// path crosses the slice in either direction. Ordering and every handshake
// are preserved; the only change is one cycle of latency.
//
// Used at the CPU boundary: the dedicated CPU floorplan region sees only its
// own registers, and platform logic (MMIO router, GPU hub, DDR adapter) sees
// only CPU-region registers.
module fn_reg_slice #(
    parameter integer W = 1
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [W-1:0] s_data,
    output wire         m_valid,
    input  wire         m_ready,
    output wire [W-1:0] m_data
);
    reg         full0, full1;      // full0: output register, full1: skid register
    reg [W-1:0] data0, data1;
    wire push = s_valid && !full1;
    wire pop  = full0 && m_ready;
    assign s_ready = !full1;
    assign m_valid = full0;
    assign m_data  = data0;

    always @(posedge clk)
        if (rst) begin
            full0 <= 1'b0;
            full1 <= 1'b0;
        end else if (full1) begin
            // Skid occupied: no push is possible; drain it into the output.
            if (pop) full1 <= 1'b0;
        end else if (push) begin
            if (full0 && !pop) full1 <= 1'b1;
            else               full0 <= 1'b1;
        end else if (pop)
            full0 <= 1'b0;

    // R57: neither data register decodes the handshake. The skid register
    // loads whenever it is empty (CE = registered !full1); the output
    // register whenever it is empty or popped (CE = !full0 | m_ready), from
    // the skid when that is full (full1 implies full0). Contents not marked
    // full are don't-care, so every handshake and output value is unchanged
    // while the platform ready chain drives half the CEs through one LUT.
    always @(posedge clk) begin
        if (!full1) data1 <= s_data;
        if (!full0 || m_ready) data0 <= full1 ? data1 : s_data;
    end
endmodule


// Local scan overlay. Camera storage and drawing never access CPU RAM or DDR.
// LCD sync is active low; p2_overlay uses active high vertical blank.
module fn_lcd_pose_pip (
    input wire ai_clk, ai_rst, pix_valid, sof,
    input wire [15:0] pix,
    input wire [10:0] cam_x,
    input wire [9:0] cam_y,
    input wire clk, rst, enable,
    input wire hs, vs, de,
    input wire [23:0] rgb,
    input wire ovl_toggle,
    input wire [11:0] dot_en, seg_en,
    input wire box_en,
    input wire [31:0] box0, box1,
    input wire [383:0] dots,
    input wire [1919:0] segs,
    output reg out_hs, out_vs, out_de,
    output wire [23:0] out_rgb
);
    reg [10:0] x;
    reg [9:0] y;
    reg de_q, vs_q, armed;
    (* ASYNC_REG="TRUE" *) reg [1:0] mode;
    always @(posedge clk) begin
        if(rst) begin x<=0; y<=0; de_q<=0; vs_q<=1; armed<=0; mode<=0; end
        else begin
            de_q<=de; vs_q<=vs; mode<={mode[0],enable};
            if(!vs) begin x<=0; y<=0; armed<=1; end
            else if(de) x<=x+1'b1;
            else if(de_q) begin x<=0; y<=y+1'b1; end
        end
    end
    wire in_pip=armed&&de&&x>=688&&x<1008&&y>=404&&y<584;
    wire [7:0] rx=in_pip?((x-11'd688)>>2):8'd0;
    wire [6:0] ry=in_pip?((y-10'd404)>>2):7'd0;
    wire [23:0] camera_rgb, skeleton_rgb;
    wire image_valid;
    // 80x45 RGB332, two independent banks (7200 bytes total).
    // A reader in each display domain needs its own frame lease.
    fn_camera_preview #(.WIDTH(80),.HEIGHT(45),.SAMPLE_LOG(4)) preview (
        .ai_clk(ai_clk),.ai_rst(ai_rst),.pix_valid(pix_valid),.sof(sof),
        .pix(pix),.cam_x(cam_x),.cam_y(cam_y),.clk(clk),.rst(rst),
        .frame_start(!vs&&vs_q),.rx(rx),.ry(ry),.rgb(camera_rgb),.image_valid(image_valid));
    reg pip_q;
    reg [23:0] base_q;
    always @(posedge clk) begin
        if(rst) begin out_hs<=1;out_vs<=1;out_de<=0;pip_q<=0;base_q<=0; end
        else begin out_hs<=hs;out_vs<=vs;out_de<=de;
            pip_q<=in_pip&&mode[1];base_q<=rgb;
        end
    end
    // Same 320x180 local coordinates as HDMI; no extra keypoint processing.
    p2_overlay #(.R(3)) overlay (.clk(clk),.rst(rst),.de(pip_q),.vs(!out_vs),
        .rgb_in(camera_rgb),.rgb_out(skeleton_rgb),.ovl_toggle(ovl_toggle),
        .dot_en(dot_en),.seg_en(seg_en),.box_en(box_en),.box0(box0),.box1(box1),.dots(dots),.segs(segs));
    assign out_rgb=pip_q?skeleton_rgb:base_q;
endmodule


`timescale 1ns/1ps
// Shared asynchronous assertion / three-stage serial-clock release source.
// The local fourth stage below releases all four TMDS lanes on the same edge.
module fn_hdmi_serial_reset(input wire clk, input wire reset_n,
                            output wire serial_reset_n);
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [2:0] ready=0;
    always @(posedge clk or negedge reset_n)
        if(!reset_n)ready<=0;
        else ready<={ready[1:0],1'b1};
    assign serial_reset_n=ready[2];
endmodule

module fn_hdmi_lane_reset(input wire clk, input wire reset_n,
                          input wire shared_reset_n, output wire lane_reset_n);
    (* syn_preserve=1 *) reg ready=0;
    always @(negedge clk or negedge reset_n)
        if(!reset_n)ready<=0;
        else ready<=shared_reset_n;
    assign lane_reset_n=ready;
endmodule


module o2_bitram (
	clk,
	we,
	wa,
	wd,
	ra,
	rd
);
	parameter integer DEPTH = 256;
	parameter integer AW = 8;
	parameter integer NR = 2;
	input wire clk;
	input wire we;
	input wire [AW - 1:0] wa;
	input wire wd;
	input wire [(NR * AW) - 1:0] ra;
	output wire [NR - 1:0] rd;
	genvar _gv_r_1;
	generate
		for (_gv_r_1 = 0; _gv_r_1 < NR; _gv_r_1 = _gv_r_1 + 1) begin : c
			localparam r = _gv_r_1;
			(* syn_ramstyle = "lut_ram" *) reg m [0:DEPTH - 1];
			always @(posedge clk)
				if (we)
					m[wa] <= wd;
			assign rd[r] = m[ra[AW * r+:AW]];
		end
	endgenerate
endmodule
module o2_decode (
	pc,
	insn,
	fetch_fault,
	fu,
	op,
	rs1,
	rs2,
	rd,
	use1,
	use2,
	wr,
	src2_imm,
	imm,
	is_jalr,
	exc,
	cause
);
	reg _sv2v_0;
	input wire [31:0] pc;
	input wire [31:0] insn;
	input wire fetch_fault;
	output reg [2:0] fu;
	output reg [3:0] op;
	output reg [4:0] rs1;
	output reg [4:0] rs2;
	output reg [4:0] rd;
	output reg use1;
	output reg use2;
	output reg wr;
	output reg src2_imm;
	output reg [31:0] imm;
	output reg is_jalr;
	output reg exc;
	output reg [3:0] cause;
	reg [6:0] opc;
	reg [2:0] f3;
	reg [6:0] f7;
	reg [31:0] imm_i;
	reg [31:0] imm_s;
	reg [31:0] imm_b;
	reg [31:0] imm_u;
	reg [31:0] imm_j;
	always @(*) begin
		if (_sv2v_0)
			;
		opc = insn[6:0];
		f3 = insn[14:12];
		f7 = insn[31:25];
		imm_i = {{20 {insn[31]}}, insn[31:20]};
		imm_s = {{20 {insn[31]}}, insn[31:25], insn[11:7]};
		imm_b = {{19 {insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
		imm_u = {insn[31:12], 12'b000000000000};
		imm_j = {{11 {insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
		rs1 = insn[19:15];
		rs2 = insn[24:20];
		rd = insn[11:7];
		fu = 3'd0;
		op = 4'd0;
		use1 = 1'b0;
		use2 = 1'b0;
		wr = 1'b0;
		src2_imm = 1'b1;
		imm = 32'b00000000000000000000000000000000;
		is_jalr = 1'b0;
		exc = 1'b0;
		cause = 4'd2;
		case (opc)
			7'h37: begin
				wr = 1'b1;
				op = 4'd10;
				imm = imm_u;
			end
			7'h17: begin
				wr = 1'b1;
				op = 4'd10;
				imm = pc + imm_u;
			end
			7'h6f: begin
				wr = 1'b1;
				op = 4'd10;
				imm = pc + 32'd4;
				if (imm_j[1]) begin
					exc = 1'b1;
					cause = 4'd0;
				end
			end
			7'h67: begin
				if (f3 != 3'd0)
					exc = 1'b1;
				fu = 3'd1;
				is_jalr = 1'b1;
				use1 = 1'b1;
				wr = 1'b1;
				imm = imm_i;
				op = 4'd2;
			end
			7'h63: begin
				fu = 3'd1;
				use1 = 1'b1;
				use2 = 1'b1;
				imm = pc + imm_b;
				op = {1'b0, f3};
				src2_imm = 1'b0;
				if ((f3 == 3'd2) || (f3 == 3'd3))
					exc = 1'b1;
			end
			7'h03: begin
				fu = 3'd2;
				use1 = 1'b1;
				wr = 1'b1;
				imm = imm_i;
				op = {1'b0, f3};
				if (((f3 == 3'd3) || (f3 == 3'd6)) || (f3 == 3'd7))
					exc = 1'b1;
			end
			7'h23: begin
				fu = 3'd3;
				use1 = 1'b1;
				use2 = 1'b1;
				imm = imm_s;
				op = {1'b1, f3};
				if (f3 > 3'd2)
					exc = 1'b1;
			end
			7'h13: begin
				use1 = 1'b1;
				wr = 1'b1;
				imm = imm_i;
				case (f3)
					3'd0: op = 4'd0;
					3'd1: begin
						op = 4'd2;
						if (f7 != 7'd0)
							exc = 1'b1;
					end
					3'd2: op = 4'd3;
					3'd3: op = 4'd4;
					3'd4: op = 4'd5;
					3'd5: begin
						op = (f7[5] ? 4'd7 : 4'd6);
						if ((f7 != 7'd0) && (f7 != 7'h20))
							exc = 1'b1;
					end
					3'd6: op = 4'd8;
					default: op = 4'd9;
				endcase
			end
			7'h33: begin
				use1 = 1'b1;
				use2 = 1'b1;
				wr = 1'b1;
				src2_imm = 1'b0;
				if (f7 == 7'h01) begin
					fu = 3'd4;
					op = {1'b0, f3};
					if (f3[2])
						exc = 1'b1;
				end
				else if (f7 == 7'h05) begin
					fu = 3'd4;
					case (f3)
						3'd1: op = 4'h4;
						3'd2: op = 4'h5;
						3'd3: op = 4'h6;
						default: exc = 1'b1;
					endcase
				end
				else if ((f7 == 7'h00) || ((f7 == 7'h20) && ((f3 == 3'd0) || (f3 == 3'd5))))
					case (f3)
						3'd0: op = (f7[5] ? 4'd1 : 4'd0);
						3'd1: op = 4'd2;
						3'd2: op = 4'd3;
						3'd3: op = 4'd4;
						3'd4: op = 4'd5;
						3'd5: op = (f7[5] ? 4'd7 : 4'd6);
						3'd6: op = 4'd8;
						default: op = 4'd9;
					endcase
				else
					exc = 1'b1;
			end
			7'h0f: begin
				fu = 3'd5;
				if (f3 == 3'd0)
					op = 4'h4;
				else if (f3 == 3'd1)
					op = 4'h5;
				else
					exc = 1'b1;
			end
			7'h73: begin
				fu = 3'd5;
				if (f3 == 3'd0) begin
					if (insn == 32'h00000073)
						op = 4'h1;
					else if (insn == 32'h00100073)
						op = 4'h2;
					else if (insn == 32'h30200073)
						op = 4'h3;
					else if (insn == 32'h10500073)
						op = 4'h4;
					else
						exc = 1'b1;
				end
				else if (f3 == 3'd4)
					exc = 1'b1;
				else begin
					op = 4'h0;
					use1 = !f3[2];
					wr = 1'b1;
				end
			end
			default: exc = 1'b1;
		endcase
		if (fetch_fault) begin
			exc = 1'b1;
			cause = 4'd1;
		end
		if (exc) begin
			fu = 3'd5;
			op = 4'h6;
			use1 = 1'b0;
			use2 = 1'b0;
			wr = 1'b0;
		end
		if (rd == 5'd0)
			wr = 1'b0;
		if (!use1)
			rs1 = 5'd0;
		if (!use2)
			rs2 = 5'd0;
	end
	initial _sv2v_0 = 0;
endmodule
module o2_icache (
	clk,
	rst,
	f1_pc,
	f1_hold,
	f2_pc,
	f2_hit,
	f2_cacheable,
	f2_fault,
	f2_block,
	refill_req,
	busy,
	invalidate,
	cmd_valid,
	cmd_ready,
	cmd_write,
	cmd_addr,
	cmd_len,
	w_valid,
	w_ready,
	w_data,
	w_be,
	w_last,
	r_valid,
	r_ready,
	r_data,
	r_error,
	r_last,
	perf_fill
);
	reg _sv2v_0;
	parameter integer SETS = 256;
	parameter [31:0] RAM_BASE = 32'h80000000;
	parameter integer RAM_BYTES = 131072;
	input wire clk;
	input wire rst;
	input wire [31:0] f1_pc;
	input wire f1_hold;
	output reg [31:0] f2_pc;
	output wire f2_hit;
	output wire f2_cacheable;
	output wire f2_fault;
	output wire [127:0] f2_block;
	input wire refill_req;
	output wire busy;
	input wire invalidate;
	output wire cmd_valid;
	input wire cmd_ready;
	output wire cmd_write;
	output wire [31:0] cmd_addr;
	output wire [7:0] cmd_len;
	output wire w_valid;
	input wire w_ready;
	output wire [31:0] w_data;
	output wire [3:0] w_be;
	output wire w_last;
	input wire r_valid;
	output wire r_ready;
	input wire [31:0] r_data;
	input wire r_error;
	input wire r_last;
	output wire perf_fill;
	localparam integer SB = $clog2(SETS);
	localparam integer RAB = $clog2(RAM_BYTES);
	localparam integer TB = (RAB - 5) - SB;
	localparam integer ROWS = SETS * 2;
	function automatic in_ram;
		input reg [31:0] a;
		in_ram = (a & ~(RAM_BYTES - 1)) == RAM_BASE;
	endfunction
	(* syn_ramstyle = "lut_ram" *) reg [TB - 1:0] tag0 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg [TB - 1:0] tag1 [0:SETS - 1];
	reg we_v0;
	reg we_v1;
	reg we_vt;
	reg wd_v;
	reg wd_vt;
	reg [SB - 1:0] wa_m;
	wire [1:0] rv0;
	wire [1:0] rv1;
	wire [1:0] rvt;
	reg [31:0] d0_0 [0:ROWS - 1];
	reg [31:0] d0_1 [0:ROWS - 1];
	reg [31:0] d0_2 [0:ROWS - 1];
	reg [31:0] d0_3 [0:ROWS - 1];
	reg [31:0] d1_0 [0:ROWS - 1];
	reg [31:0] d1_1 [0:ROWS - 1];
	reg [31:0] d1_2 [0:ROWS - 1];
	reg [31:0] d1_3 [0:ROWS - 1];
	reg [31:0] q0_0;
	reg [31:0] q0_1;
	reg [31:0] q0_2;
	reg [31:0] q0_3;
	reg [31:0] q1_0;
	reg [31:0] q1_1;
	reg [31:0] q1_2;
	reg [31:0] q1_3;
	wire [SB - 1:0] f1_set = f1_pc[5+:SB];
	wire [TB - 1:0] f1_tag = f1_pc[5 + SB+:TB];
	wire [SB:0] f1_row = f1_pc[4+:SB + 1];
	localparam [1:0] S_IDLE = 2'd0;
	localparam [1:0] S_CMD = 2'd1;
	localparam [1:0] S_DATA = 2'd2;
	localparam [1:0] S_INV = 2'd3;
	reg [1:0] state;
	reg [31:0] fill_addr;
	reg [2:0] beat;
	reg fill_way;
	reg fill_err;
	wire [SB - 1:0] fill_set = fill_addr[5+:SB];
	wire [SB:0] fill_row = {fill_set, beat[2]};
	wire fill_we = (state == S_DATA) && r_valid;
	wire fill_last = fill_we && (beat == 3'd7);
	wire fill_ok = !fill_err && !r_error;
	reg err_v;
	reg [RAB - 6:0] err_line;
	reg hit0_q;
	reg hit1_q;
	reg err_q;
	reg f2_cacheable_q;
	always @(posedge clk)
		if (rst) begin
			hit0_q <= 1'b0;
			hit1_q <= 1'b0;
			err_q <= 1'b0;
			f2_pc <= 32'b00000000000000000000000000000000;
			f2_cacheable_q <= 1'b0;
		end
		else if (!f1_hold) begin
			f2_pc <= f1_pc;
			f2_cacheable_q <= in_ram(f1_pc);
			hit0_q <= (rv0[0] && (tag0[f1_set] == f1_tag)) && in_ram(f1_pc);
			hit1_q <= (rv1[0] && (tag1[f1_set] == f1_tag)) && in_ram(f1_pc);
			err_q <= (err_v && (f1_pc[RAB - 1:5] == err_line)) && in_ram(f1_pc);
		end
	always @(posedge clk) begin
		if (!f1_hold) begin
			q0_0 <= d0_0[f1_row];
			q0_1 <= d0_1[f1_row];
			q0_2 <= d0_2[f1_row];
			q0_3 <= d0_3[f1_row];
			q1_0 <= d1_0[f1_row];
			q1_1 <= d1_1[f1_row];
			q1_2 <= d1_2[f1_row];
			q1_3 <= d1_3[f1_row];
		end
		if (fill_we && !fill_way)
			case (beat[1:0])
				2'd0: d0_0[fill_row] <= r_data;
				2'd1: d0_1[fill_row] <= r_data;
				2'd2: d0_2[fill_row] <= r_data;
				default: d0_3[fill_row] <= r_data;
			endcase
		if (fill_we && fill_way)
			case (beat[1:0])
				2'd0: d1_0[fill_row] <= r_data;
				2'd1: d1_1[fill_row] <= r_data;
				2'd2: d1_2[fill_row] <= r_data;
				default: d1_3[fill_row] <= r_data;
			endcase
	end
	assign f2_hit = (hit0_q || hit1_q) || err_q;
	assign f2_fault = err_q;
	assign f2_cacheable = f2_cacheable_q;
	assign f2_block = (hit1_q ? {q1_3, q1_2, q1_1, q1_0} : {q0_3, q0_2, q0_1, q0_0});
	always @(posedge clk) begin
		if (fill_last && !fill_way)
			tag0[fill_set] <= fill_addr[5 + SB+:TB];
		if (fill_last && fill_way)
			tag1[fill_set] <= fill_addr[5 + SB+:TB];
	end
	assign busy = state != S_IDLE;
	assign perf_fill = ((state == S_IDLE) && !invalidate) && refill_req;
	assign cmd_valid = state == S_CMD;
	assign cmd_write = 1'b0;
	assign cmd_addr = {fill_addr[31:5], 5'b00000};
	assign cmd_len = 8'd8;
	assign w_valid = 1'b0;
	assign w_data = 32'b00000000000000000000000000000000;
	assign w_be = 4'b0000;
	assign w_last = 1'b0;
	assign r_ready = state == S_DATA;
	reg [SB - 1:0] inv_set;
	function automatic signed [SB - 1:0] sv2v_cast_C2F86_signed;
		input reg signed [SB - 1:0] inp;
		sv2v_cast_C2F86_signed = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			state <= S_INV;
			inv_set <= 1'sb0;
			beat <= 3'd0;
			fill_way <= 1'b0;
			fill_addr <= 32'b00000000000000000000000000000000;
			fill_err <= 1'b0;
			err_v <= 1'b0;
		end
		else
			case (state)
				S_IDLE:
					if (invalidate) begin
						state <= S_INV;
						inv_set <= 1'sb0;
						err_v <= 1'b0;
					end
					else if (refill_req) begin
						fill_addr <= f2_pc;
						fill_way <= (!rv0[1] ? 1'b0 : (!rv1[1] ? 1'b1 : rvt[1]));
						state <= S_CMD;
						err_v <= 1'b0;
					end
				S_CMD:
					if (cmd_ready) begin
						state <= S_DATA;
						beat <= 3'd0;
						fill_err <= 1'b0;
					end
				S_DATA:
					if (r_valid) begin
						beat <= beat + 3'd1;
						fill_err <= fill_err || r_error;
						if (beat == 3'd7) begin
							state <= S_IDLE;
							if (!fill_ok) begin
								err_v <= 1'b1;
								err_line <= fill_addr[RAB - 1:5];
							end
						end
					end
				S_INV: begin
					inv_set <= inv_set + 1'b1;
					if (inv_set == sv2v_cast_C2F86_signed(SETS - 1))
						state <= S_IDLE;
				end
			endcase
	always @(*) begin
		if (_sv2v_0)
			;
		we_v0 = 1'b0;
		we_v1 = 1'b0;
		wd_v = 1'b0;
		wa_m = fill_set;
		we_vt = fill_last;
		wd_vt = !fill_way;
		if (state == S_INV) begin
			we_v0 = 1'b1;
			we_v1 = 1'b1;
			wa_m = inv_set;
			we_vt = 1'b1;
			wd_vt = 1'b0;
		end
		else if (fill_last) begin
			we_v0 = !fill_way;
			we_v1 = fill_way;
			wd_v = fill_ok;
		end
		else if (state == S_CMD) begin
			we_v0 = !fill_way;
			we_v1 = fill_way;
		end
	end
	wire [(2 * SB) - 1:0] mra = {f2_pc[5+:SB], f1_set};
	o2_bitram #(
		.DEPTH(SETS),
		.AW(SB),
		.NR(2)
	) mv0(
		.clk(clk),
		.we(we_v0),
		.wa(wa_m),
		.wd(wd_v),
		.ra(mra),
		.rd(rv0)
	);
	o2_bitram #(
		.DEPTH(SETS),
		.AW(SB),
		.NR(2)
	) mv1(
		.clk(clk),
		.we(we_v1),
		.wa(wa_m),
		.wd(wd_v),
		.ra(mra),
		.rd(rv1)
	);
	o2_bitram #(
		.DEPTH(SETS),
		.AW(SB),
		.NR(2)
	) mvt(
		.clk(clk),
		.we(we_vt),
		.wa(wa_m),
		.wd(wd_vt),
		.ra(mra),
		.rd(rvt)
	);
	initial _sv2v_0 = 0;
endmodule
module o2_frontend (
	clk,
	rst,
	be_flush,
	be_flush_pc,
	be_mispredict,
	be_mis_pc,
	be_mis_biq,
	be_mis_k,
	be_mis_is_cbr,
	be_mis_taken,
	fetch_stop,
	cmt_br_valid,
	cmt_is_cbr,
	cmt_taken,
	cmt_pc,
	cmt_biq,
	ib_train,
	ib_pc,
	ib_target,
	ic_f1_pc,
	ic_f2_pc,
	ic_f2_hit,
	ic_f2_cacheable,
	ic_f2_fault,
	ic_f2_block,
	ic_refill_req,
	ic_busy,
	fq_v0,
	fq_v1,
	fq_pc0,
	fq_pc1,
	fq_insn0,
	fq_insn1,
	fq_pred0,
	fq_pred1,
	fq_fault0,
	fq_fault1,
	fq_biq0,
	fq_biq1,
	fq_k0,
	fq_k1,
	fq_cmt0,
	fq_cmt1,
	fq_br0,
	fq_br1,
	fq_pop
);
	reg _sv2v_0;
	parameter [31:0] RESET_PC = 32'h80000000;
	input wire clk;
	input wire rst;
	input wire be_flush;
	input wire [31:0] be_flush_pc;
	input wire be_mispredict;
	input wire [31:0] be_mis_pc;
	input wire [3:0] be_mis_biq;
	input wire [1:0] be_mis_k;
	input wire be_mis_is_cbr;
	input wire be_mis_taken;
	input wire fetch_stop;
	input wire cmt_br_valid;
	input wire cmt_is_cbr;
	input wire cmt_taken;
	input wire [31:0] cmt_pc;
	input wire [3:0] cmt_biq;
	input wire ib_train;
	input wire [31:0] ib_pc;
	input wire [31:0] ib_target;
	output wire [31:0] ic_f1_pc;
	input wire [31:0] ic_f2_pc;
	input wire ic_f2_hit;
	input wire ic_f2_cacheable;
	input wire ic_f2_fault;
	input wire [127:0] ic_f2_block;
	output wire ic_refill_req;
	input wire ic_busy;
	output wire fq_v0;
	output wire fq_v1;
	output wire [31:0] fq_pc0;
	output wire [31:0] fq_pc1;
	output wire [31:0] fq_insn0;
	output wire [31:0] fq_insn1;
	output wire [31:0] fq_pred0;
	output wire [31:0] fq_pred1;
	output wire fq_fault0;
	output wire fq_fault1;
	output wire [3:0] fq_biq0;
	output wire [3:0] fq_biq1;
	output wire [1:0] fq_k0;
	output wire [1:0] fq_k1;
	output wire fq_cmt0;
	output wire fq_cmt1;
	output wire fq_br0;
	output wire fq_br1;
	input wire [1:0] fq_pop;
	localparam integer NLPW = 13;
	localparam integer NTB = 15;
	localparam integer TI = 10;
	localparam integer TT = 11;
	localparam integer TW = TT + 14;
	localparam integer H0 = 4;
	localparam integer H1 = 10;
	localparam integer H2 = 25;
	localparam integer H3 = 64;
	localparam integer FQN = 32;
	localparam integer RASN = 8;
	function automatic [TI - 1:0] fold9;
		input [63:0] g;
		input integer len;
		integer k;
		reg [TI - 1:0] f;
		begin
			f = 1'sb0;
			for (k = 0; k < 64; k = k + 1)
				if (k < len)
					f[k % TI] = f[k % TI] ^ g[k];
			fold9 = f;
		end
	endfunction
	function automatic [TT - 1:0] foldt;
		input [63:0] g;
		input integer len;
		integer k;
		reg [TT - 1:0] f;
		begin
			f = 1'sb0;
			for (k = 0; k < 64; k = k + 1)
				if (k < len)
					f[k % TT] = f[k % TT] ^ g[k];
			foldt = f;
		end
	endfunction
	function automatic [TT - 2:0] fold8;
		input [63:0] g;
		input integer len;
		integer k;
		reg [TT - 2:0] f;
		begin
			f = 1'sb0;
			for (k = 0; k < 64; k = k + 1)
				if (k < len)
					f[k % (TT - 1)] = f[k % (TT - 1)] ^ g[k];
			fold8 = f;
		end
	endfunction
	function automatic [TI - 1:0] tidx;
		input [31:0] pc;
		input [63:0] g;
		input integer len;
		reg [27:0] bp;
		begin
			bp = pc[31:4];
			tidx = (bp[TI - 1:0] ^ bp[(2 * TI) - 1:TI]) ^ fold9(g, len);
		end
	endfunction
	function automatic [TT - 1:0] ttag;
		input [31:0] pc;
		input [63:0] g;
		input integer len;
		reg [27:0] bp;
		begin
			bp = pc[31:4];
			ttag = (bp[TT - 1:0] ^ foldt(g, len)) ^ {fold8(g, len), 1'b0};
		end
	endfunction
	function automatic [1:0] sat2;
		input [1:0] c;
		input t;
		sat2 = (t ? (c == 2'd3 ? 2'd3 : c + 2'd1) : (c == 2'd0 ? 2'd0 : c - 2'd1));
	endfunction
	reg [31:0] pc1;
	reg v1;
	reg [63:0] ghr_spec;
	reg [63:0] ghr_commit;
	reg refetch_wait;
	reg [TI:0] tinit;
	wire nlp_ready = 1'b1;
	wire tinit_busy = !tinit[TI];
	wire kill_f4;
	wire [31:0] f4_redirect_pc;
	wire f2_miss;
	wire be_any = be_flush || be_mispredict;
	reg [NTB + 1:0] nlp [0:(1 << NLPW) - 1];
	reg [NTB + 1:0] nlp_q;
	wire [31:0] pc1_next;
	always @(posedge clk) nlp_q <= nlp[(rst ? RESET_PC[NLPW + 1:2] : pc1_next[NLPW + 1:2])];
	wire [31:0] seq_next1 = {pc1[31:4] + 28'd1, 4'b0000};
	wire [31:0] nlp_next = (nlp_q[NTB] ? {pc1[31:NTB + 2], nlp_q[NTB - 1:0], 2'b00} : seq_next1);
	wire nlp_c1 = nlp_q[NTB + 1];
	reg nlp_we;
	reg [NLPW - 1:0] nlp_widx;
	reg [NTB + 1:0] nlp_wdata;
	always @(posedge clk)
		if (nlp_we)
			nlp[nlp_widx] <= nlp_wdata;
	reg [TW - 1:0] tp0 [0:(1 << TI) - 1];
	reg [TW - 1:0] tp1 [0:(1 << TI) - 1];
	reg [TW - 1:0] tp2 [0:(1 << TI) - 1];
	reg [TW - 1:0] tp3 [0:(1 << TI) - 1];
	reg [TW - 1:0] tu0 [0:(1 << TI) - 1];
	reg [TW - 1:0] tu1 [0:(1 << TI) - 1];
	reg [TW - 1:0] tu2 [0:(1 << TI) - 1];
	reg [TW - 1:0] tu3 [0:(1 << TI) - 1];
	reg [TI - 1:0] f1_idx0;
	reg [TI - 1:0] f1_idx1;
	reg [TI - 1:0] f1_idx2;
	reg [TI - 1:0] f1_idx3;
	reg [TT - 1:0] f1_tag0;
	reg [TT - 1:0] f1_tag1;
	reg [TT - 1:0] f1_tag2;
	reg [TT - 1:0] f1_tag3;
	always @(*) begin
		if (_sv2v_0)
			;
		f1_idx0 = tidx(pc1, ghr_spec, H0);
		f1_tag0 = ttag(pc1, ghr_spec, H0);
		f1_idx1 = tidx(pc1, ghr_spec, H1);
		f1_tag1 = ttag(pc1, ghr_spec, H1);
		f1_idx2 = tidx(pc1, ghr_spec, H2);
		f1_tag2 = ttag(pc1, ghr_spec, H2);
		f1_idx3 = tidx(pc1, ghr_spec, H3);
		f1_tag3 = ttag(pc1, ghr_spec, H3);
	end
	reg [TW - 1:0] te2_0;
	reg [TW - 1:0] te2_1;
	reg [TW - 1:0] te2_2;
	reg [TW - 1:0] te2_3;
	reg [3:0] tw_en;
	reg [TI - 1:0] tw_idx0;
	reg [TI - 1:0] tw_idx1;
	reg [TI - 1:0] tw_idx2;
	reg [TI - 1:0] tw_idx3;
	reg [TW - 1:0] tw_d0;
	reg [TW - 1:0] tw_d1;
	reg [TW - 1:0] tw_d2;
	reg [TW - 1:0] tw_d3;
	reg [TI - 1:0] tr_idx0;
	reg [TI - 1:0] tr_idx1;
	reg [TI - 1:0] tr_idx2;
	reg [TI - 1:0] tr_idx3;
	reg [TW - 1:0] tue0;
	reg [TW - 1:0] tue1;
	reg [TW - 1:0] tue2;
	reg [TW - 1:0] tue3;
	always @(posedge clk) begin
		te2_0 <= tp0[f1_idx0];
		te2_1 <= tp1[f1_idx1];
		te2_2 <= tp2[f1_idx2];
		te2_3 <= tp3[f1_idx3];
		tue0 <= tu0[tr_idx0];
		tue1 <= tu1[tr_idx1];
		tue2 <= tu2[tr_idx2];
		tue3 <= tu3[tr_idx3];
		if (tinit_busy) begin
			tp0[tinit[TI - 1:0]] <= 1'sb0;
			tp1[tinit[TI - 1:0]] <= 1'sb0;
			tp2[tinit[TI - 1:0]] <= 1'sb0;
			tp3[tinit[TI - 1:0]] <= 1'sb0;
			tu0[tinit[TI - 1:0]] <= 1'sb0;
			tu1[tinit[TI - 1:0]] <= 1'sb0;
			tu2[tinit[TI - 1:0]] <= 1'sb0;
			tu3[tinit[TI - 1:0]] <= 1'sb0;
		end
		else begin
			if (tw_en[0]) begin
				tp0[tw_idx0] <= tw_d0;
				tu0[tw_idx0] <= tw_d0;
			end
			if (tw_en[1]) begin
				tp1[tw_idx1] <= tw_d1;
				tu1[tw_idx1] <= tw_d1;
			end
			if (tw_en[2]) begin
				tp2[tw_idx2] <= tw_d2;
				tu2[tw_idx2] <= tw_d2;
			end
			if (tw_en[3]) begin
				tp3[tw_idx3] <= tw_d3;
				tu3[tw_idx3] <= tw_d3;
			end
		end
	end
	(* syn_ramstyle = "lut_ram" *) reg [1:0] bs0 [0:511];
	(* syn_ramstyle = "lut_ram" *) reg [1:0] bs1 [0:511];
	(* syn_ramstyle = "lut_ram" *) reg [1:0] bs2 [0:511];
	(* syn_ramstyle = "lut_ram" *) reg [1:0] bs3 [0:511];
	reg bw_en;
	reg [10:0] bw_idx;
	reg [1:0] bw_data;
	always @(posedge clk)
		if (tinit_busy) begin
			bs0[tinit[8:0]] <= 2'b01;
			bs1[tinit[8:0]] <= 2'b01;
			bs2[tinit[8:0]] <= 2'b01;
			bs3[tinit[8:0]] <= 2'b01;
		end
		else if (bw_en)
			case (bw_idx[1:0])
				2'd0: bs0[bw_idx[10:2]] <= bw_data;
				2'd1: bs1[bw_idx[10:2]] <= bw_data;
				2'd2: bs2[bw_idx[10:2]] <= bw_data;
				default: bs3[bw_idx[10:2]] <= bw_data;
			endcase
	(* syn_ramstyle = "lut_ram" *) reg [38:0] ib0 [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [38:0] ib1 [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [38:0] ib2 [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [38:0] ib3 [0:15];
	wire [38:0] ib_wdata = {1'b1, ib_pc[15:8], ib_target[31:2]};
	always @(posedge clk)
		if (tinit_busy) begin
			ib0[tinit[3:0]] <= 1'sb0;
			ib1[tinit[3:0]] <= 1'sb0;
			ib2[tinit[3:0]] <= 1'sb0;
			ib3[tinit[3:0]] <= 1'sb0;
		end
		else if (ib_train)
			case (ib_pc[3:2])
				2'd0: ib0[ib_pc[7:4]] <= ib_wdata;
				2'd1: ib1[ib_pc[7:4]] <= ib_wdata;
				2'd2: ib2[ib_pc[7:4]] <= ib_wdata;
				default: ib3[ib_pc[7:4]] <= ib_wdata;
			endcase
	reg v2;
	reg [31:0] nlp2;
	reg nlpc2;
	reg nlpc3;
	reg nlpc3b;
	reg nlpc4;
	reg [TT - 1:0] tag2_0;
	reg [TT - 1:0] tag2_1;
	reg [TT - 1:0] tag2_2;
	reg [TT - 1:0] tag2_3;
	reg [TI - 1:0] idx2_0;
	reg [TI - 1:0] idx2_1;
	reg [TI - 1:0] idx2_2;
	reg [TI - 1:0] idx2_3;
	always @(posedge clk) begin
		if (rst)
			v2 <= 1'b0;
		else
			v2 <= ((v1 && !be_any) && !kill_f4) && !f2_miss;
		nlp2 <= nlp_next;
		nlpc2 <= nlp_c1;
		tag2_0 <= f1_tag0;
		tag2_1 <= f1_tag1;
		tag2_2 <= f1_tag2;
		tag2_3 <= f1_tag3;
		idx2_0 <= f1_idx0;
		idx2_1 <= f1_idx1;
		idx2_2 <= f1_idx2;
		idx2_3 <= f1_idx3;
	end
	assign f2_miss = (((v2 && ic_f2_cacheable) && !ic_f2_hit) && !be_any) && !kill_f4;
	assign ic_refill_req = f2_miss && !ic_busy;
	wire f2_good = ((v2 && !f2_miss) && !be_any) && !kill_f4;
	wire [1:0] base2_0 = bs0[ic_f2_pc[12:4]];
	wire [1:0] base2_1 = bs1[ic_f2_pc[12:4]];
	wire [1:0] base2_2 = bs2[ic_f2_pc[12:4]];
	wire [1:0] base2_3 = bs3[ic_f2_pc[12:4]];
	wire [38:0] ibe2_0 = ib0[ic_f2_pc[7:4]];
	wire [38:0] ibe2_1 = ib1[ic_f2_pc[7:4]];
	wire [38:0] ibe2_2 = ib2[ic_f2_pc[7:4]];
	wire [38:0] ibe2_3 = ib3[ic_f2_pc[7:4]];
	reg v3;
	reg fault3;
	reg [31:0] pc3;
	reg [31:0] nlp3;
	reg [127:0] blk3;
	reg [(4 * TW) - 1:0] te3;
	reg [(4 * TT) - 1:0] tag3;
	reg [(4 * TI) - 1:0] idx3;
	reg [7:0] base3;
	reg [155:0] ibe3;
	reg [3:0] hit3;
	always @(posedge clk) begin
		if (rst)
			v3 <= 1'b0;
		else
			v3 <= f2_good;
		pc3 <= ic_f2_pc;
		nlp3 <= nlp2;
		nlpc3 <= nlpc2;
		fault3 <= !ic_f2_cacheable || ic_f2_fault;
		blk3 <= ic_f2_block;
		te3 <= {te2_3, te2_2, te2_1, te2_0};
		hit3 <= {te2_3[TW - 1-:TT] == tag2_3, te2_2[TW - 1-:TT] == tag2_2, te2_1[TW - 1-:TT] == tag2_1, te2_0[TW - 1-:TT] == tag2_0};
		tag3 <= {tag2_3, tag2_2, tag2_1, tag2_0};
		idx3 <= {idx2_3, idx2_2, idx2_1, idx2_0};
		base3 <= {base2_3, base2_2, base2_1, base2_0};
		ibe3 <= {ibe2_3, ibe2_2, ibe2_1, ibe2_0};
	end
	wire f3_live = (v3 && !be_any) && !kill_f4;
	reg prov_v;
	reg alt_v;
	reg [1:0] prov_i;
	reg [1:0] alt_i;
	always @(*) begin
		if (_sv2v_0)
			;
		prov_v = |hit3;
		prov_i = (hit3[3] ? 2'd3 : (hit3[2] ? 2'd2 : (hit3[1] ? 2'd1 : 2'd0)));
		alt_v = 1'b0;
		alt_i = 2'd0;
		case (prov_i)
			2'd3: begin
				alt_v = |hit3[2:0];
				alt_i = (hit3[2] ? 2'd2 : (hit3[1] ? 2'd1 : 2'd0));
			end
			2'd2: begin
				alt_v = |hit3[1:0];
				alt_i = (hit3[1] ? 2'd1 : 2'd0);
			end
			2'd1: begin
				alt_v = hit3[0];
				alt_i = 2'd0;
			end
			default: begin
				alt_v = 1'b0;
				alt_i = 2'd0;
			end
		endcase
	end
	wire [TW - 1:0] prov_e = te3[TW * prov_i+:TW];
	wire [TW - 1:0] alt_e = te3[TW * alt_i+:TW];
	wire prov_u0 = prov_e[13:12] == 2'd0;
	reg [3:0] s_valid;
	reg [3:0] s_cbr;
	reg [3:0] s_jal;
	reg [3:0] s_jalr;
	reg [3:0] s_call;
	reg [3:0] s_ret;
	reg [3:0] s_pred;
	reg [3:0] s_taken;
	reg [31:0] s_target [0:3];
	function automatic signed [1:0] sv2v_cast_2_signed;
		input reg signed [1:0] inp;
		sv2v_cast_2_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				begin : sv2v_autoblock_2
					reg [31:0] ins;
					reg [6:0] o;
					reg [4:0] rd;
					reg [4:0] rs1;
					reg rdl;
					reg rs1l;
					reg [31:0] spc;
					reg [31:0] imm;
					reg [2:0] cp;
					reg [2:0] ca;
					reg pp;
					reg ap;
					reg bp;
					reg wk;
					ins = blk3[32 * i+:32];
					o = ins[6:0];
					rd = ins[11:7];
					rs1 = ins[19:15];
					rdl = (rd == 5'd1) || (rd == 5'd5);
					rs1l = (rs1 == 5'd1) || (rs1 == 5'd5);
					s_valid[i] = (sv2v_cast_2_signed(i) >= pc3[3:2]) && !fault3;
					s_cbr[i] = o == 7'h63;
					s_jal[i] = o == 7'h6f;
					s_jalr[i] = o == 7'h67;
					s_call[i] = (s_jal[i] || s_jalr[i]) && rdl;
					s_ret[i] = (s_jalr[i] && rs1l) && (!rdl || (rd != rs1));
					spc = {pc3[31:4], sv2v_cast_2_signed(i), 2'b00};
					imm = (s_jal[i] ? {{11 {ins[31]}}, ins[31], ins[19:12], ins[20], ins[30:21], 1'b0} : {{19 {ins[31]}}, ins[31], ins[7], ins[30:25], ins[11:8], 1'b0});
					s_target[i] = spc + imm;
					bp = base3[(2 * i) + 1];
					cp = prov_e[3 * i+:3];
					ca = alt_e[3 * i+:3];
					pp = (prov_v ? !cp[2] : bp);
					ap = (alt_v ? !ca[2] : bp);
					wk = (prov_v && ((cp == 3'd0) || (cp == 3'b111))) && prov_u0;
					s_pred[i] = (prov_v ? (wk ? ap : pp) : bp);
					s_taken[i] = s_valid[i] && (((s_cbr[i] && s_pred[i]) || s_jal[i]) || s_jalr[i]);
				end
		end
	end
	reg v3b;
	reg fault3b;
	reg [31:0] pc3b;
	reg [31:0] nlp3b;
	reg [127:0] blk3b;
	reg [3:0] tks3b;
	reg [3:0] valid3b;
	reg [3:0] cbr3b;
	reg [3:0] jalr3b;
	reg [3:0] call3b;
	reg [3:0] ret3b;
	reg [31:0] tgt3b [0:3];
	reg [155:0] ibe3b;
	reg [(4 * TI) - 1:0] idx3b;
	reg [(4 * TT) - 1:0] tag3b;
	always @(posedge clk) begin
		if (rst)
			v3b <= 1'b0;
		else
			v3b <= f3_live;
		pc3b <= pc3;
		nlp3b <= nlp3;
		nlpc3b <= nlpc3;
		fault3b <= fault3;
		blk3b <= blk3;
		tks3b <= s_taken;
		valid3b <= s_valid;
		cbr3b <= s_cbr;
		jalr3b <= s_jalr;
		call3b <= s_call;
		ret3b <= s_ret;
		begin : sv2v_autoblock_3
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				tgt3b[i] <= s_target[i];
		end
		ibe3b <= ibe3;
		idx3b <= idx3;
		tag3b <= tag3;
	end
	wire f3b_live = (v3b && !be_any) && !kill_f4;
	wire [3:0] toh = tks3b & (~tks3b + 4'd1);
	wire tk3 = |tks3b;
	wire [1:0] end3 = (tk3 ? {toh[2] | toh[3], toh[1] | toh[3]} : 2'd3);
	wire [3:0] s_upto = (tk3 ? (toh - 4'd1) | toh : 4'b1111);
	reg [31:0] tgt_sel;
	reg [38:0] ib_sel;
	always @(*) begin
		if (_sv2v_0)
			;
		tgt_sel = 32'b00000000000000000000000000000000;
		ib_sel = 39'b000000000000000000000000000000000000000;
		begin : sv2v_autoblock_4
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				begin
					tgt_sel = tgt_sel | ({32 {toh[i]}} & tgt3b[i]);
					ib_sel = ib_sel | ({39 {toh[i]}} & ibe3b[39 * i+:39]);
				end
		end
	end
	wire [31:0] seq3b = {pc3b[31:4] + 28'd1, 4'b0000};
	wire [31:0] jpc3b = (end3 == 2'd3 ? seq3b : {pc3b[31:4], end3 + 2'd1, 2'b00});
	wire e_ret3 = |(toh & ret3b);
	wire e_jalr3 = |(toh & jalr3b);
	wire e_call3 = |(toh & call3b);
	wire e_cbr3 = |(toh & cbr3b);
	wire ibh3 = ib_sel[38] && (ib_sel[37:30] == pc3b[15:8]);
	reg v4;
	reg fault4;
	reg tk4;
	reg [31:0] pc4;
	reg [31:0] nlp4;
	reg [127:0] blk4;
	reg [1:0] end4;
	reg [3:0] valid4;
	reg [3:0] cbr4;
	reg [3:0] jalr4;
	reg [31:0] tgt4;
	reg [31:0] seq4;
	reg [31:0] jpc4;
	reg [29:0] ib_tgt4;
	reg s4_seq;
	reg s4_ret;
	reg s4_ib;
	reg s4_jpc;
	reg s4_tgt;
	reg eq4_seq;
	reg eq4_ib;
	reg eq4_jpc;
	reg eq4_tgt;
	reg end_ret;
	reg end_call;
	reg last_cbr_taken;
	reg [(4 * TI) - 1:0] idx4;
	reg [(4 * TT) - 1:0] tag4;
	always @(posedge clk) begin
		if (rst)
			v4 <= 1'b0;
		else
			v4 <= f3b_live;
		pc4 <= pc3b;
		nlp4 <= nlp3b;
		nlpc4 <= nlpc3b;
		fault4 <= fault3b;
		tk4 <= tk3;
		end4 <= end3;
		blk4 <= blk3b;
		valid4 <= valid3b & s_upto;
		idx4 <= idx3b;
		tag4 <= tag3b;
		cbr4 <= cbr3b;
		jalr4 <= jalr3b;
		tgt4 <= tgt_sel;
		seq4 <= seq3b;
		jpc4 <= jpc3b;
		ib_tgt4 <= ib_sel[29:0];
		s4_seq <= !tk3;
		s4_ret <= e_ret3;
		s4_ib <= (e_jalr3 && !e_ret3) && ibh3;
		s4_jpc <= (e_jalr3 && !e_ret3) && !ibh3;
		s4_tgt <= tk3 && !e_jalr3;
		eq4_seq <= seq3b == nlp3b;
		eq4_ib <= (ib_sel[29:0] == nlp3b[31:2]) && (nlp3b[1:0] == 2'b00);
		eq4_jpc <= jpc3b == nlp3b;
		eq4_tgt <= tgt_sel == nlp3b;
		end_ret <= e_ret3;
		end_call <= e_call3;
		last_cbr_taken <= e_cbr3;
	end
	reg [31:0] ras [0:RASN - 1];
	reg [2:0] ras_ptr;
	reg [31:0] ras_top;
	wire [31:0] next4 = (((({32 {s4_seq}} & seq4) | ({32 {s4_ret}} & ras_top)) | ({32 {s4_ib}} & {ib_tgt4, 2'b00})) | ({32 {s4_jpc}} & jpc4)) | ({32 {s4_tgt}} & tgt4);
	wire nlp_eq4 = ((((s4_seq && eq4_seq) || (s4_ret && (ras_top == nlp4))) || (s4_ib && eq4_ib)) || (s4_jpc && eq4_jpc)) || (s4_tgt && eq4_tgt);
	reg [5:0] fq_count;
	function automatic signed [5:0] sv2v_cast_6_signed;
		input reg signed [5:0] inp;
		sv2v_cast_6_signed = inp;
	endfunction
	wire fq_space = fq_count <= sv2v_cast_6_signed(FQN - 4);
	reg [4:0] biq_head;
	reg [4:0] biq_tail;
	wire [4:0] biq_count = biq_tail - biq_head;
	wire grp_has_br = !fault4 && |(valid4 & (cbr4 | jalr4));
	wire biq_space = biq_count < 5'd15;
	wire f4_live = v4 && !be_any;
	wire f4_accept = (f4_live && fq_space) && (!grp_has_br || biq_space);
	wire f4_self = f4_live && !f4_accept;
	wire f4_override = (f4_accept && !fault4) && !nlp_eq4;
	assign kill_f4 = f4_override || f4_self;
	assign f4_redirect_pc = (f4_self ? pc4 : next4);
	wire [3:0] cbv = valid4 & cbr4;
	reg [1:0] kcnt [0:3];
	wire [2:0] ncbr = (({2'b00, cbv[0]} + {2'b00, cbv[1]}) + {2'b00, cbv[2]}) + {2'b00, cbv[3]};
	always @(*) begin
		if (_sv2v_0)
			;
		kcnt[0] = 2'd0;
		kcnt[1] = {1'b0, cbv[0]};
		kcnt[2] = {1'b0, cbv[0]} + {1'b0, cbv[1]};
		kcnt[3] = ({1'b0, cbv[0]} + {1'b0, cbv[1]}) + {1'b0, cbv[2]};
	end
	(* syn_ramstyle = "lut_ram" *) reg [63:0] biq_ghr [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [(4 * TI) - 1:0] biq_idx [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [(4 * TT) - 1:0] biq_tag [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [2:0] biq_ras [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [1:0] biq_rasop [0:15];
	wire [3:0] biq_wptr = biq_tail[3:0];
	always @(posedge clk)
		if (f4_accept && grp_has_br) begin
			biq_ghr[biq_wptr] <= ghr_spec;
			biq_idx[biq_wptr] <= idx4;
			biq_tag[biq_wptr] <= tag4;
			biq_ras[biq_wptr] <= ras_ptr;
			biq_rasop[biq_wptr] <= {end_call, end_ret};
		end
	wire [63:0] mis_ghr = biq_ghr[be_mis_biq];
	wire [2:0] mis_rp = (be_mis_is_cbr ? biq_ras[be_mis_biq] : (biq_ras[be_mis_biq] - {2'b00, biq_rasop[be_mis_biq][0]}) + {2'b00, biq_rasop[be_mis_biq][1]});
	assign pc1_next = (be_flush ? be_flush_pc : (be_mispredict ? be_mis_pc : (kill_f4 ? f4_redirect_pc : (f2_miss ? ic_f2_pc : (v1 ? nlp_next : pc1)))));
	wire refetch_next = (be_any || kill_f4 ? 1'b0 : (f2_miss ? 1'b1 : (refetch_wait && !ic_busy ? 1'b0 : refetch_wait)));
	always @(posedge clk)
		if (rst) begin
			pc1 <= RESET_PC;
			v1 <= 1'b0;
			ghr_spec <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
			ghr_commit <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
			ras_ptr <= 3'd0;
			ras_top <= 32'b00000000000000000000000000000000;
			refetch_wait <= 1'b0;
			tinit <= 1'sb0;
			biq_head <= 5'd0;
			biq_tail <= 5'd0;
			begin : sv2v_autoblock_5
				reg signed [31:0] i;
				for (i = 0; i < RASN; i = i + 1)
					ras[i] <= 32'b00000000000000000000000000000000;
			end
		end
		else begin
			if (tinit_busy)
				tinit <= tinit + 1'b1;
			if (cmt_br_valid && cmt_is_cbr)
				ghr_commit <= {ghr_commit[62:0], cmt_taken};
			pc1 <= pc1_next;
			refetch_wait <= refetch_next;
			v1 <= !(((fetch_stop || !nlp_ready) || tinit_busy) || refetch_next);
			if (be_flush)
				ghr_spec <= ghr_commit;
			else if (be_mispredict) begin
				ghr_spec <= (be_mis_is_cbr ? ((mis_ghr << be_mis_k) << 1) | {63'b000000000000000000000000000000000000000000000000000000000000000, be_mis_taken} : mis_ghr << be_mis_k);
				ras_ptr <= mis_rp;
				ras_top <= ras[mis_rp];
			end
			else if (f4_accept) begin
				ghr_spec <= (ghr_spec << ncbr) | {63'b000000000000000000000000000000000000000000000000000000000000000, last_cbr_taken};
				if (end_ret && end_call) begin
					ras[ras_ptr] <= jpc4;
					ras_top <= jpc4;
				end
				else if (end_ret) begin
					ras_ptr <= ras_ptr - 3'd1;
					ras_top <= ras[ras_ptr - 3'd1];
				end
				else if (end_call) begin
					ras_ptr <= ras_ptr + 3'd1;
					ras[ras_ptr + 3'd1] <= jpc4;
					ras_top <= jpc4;
				end
			end
			begin : sv2v_autoblock_6
				reg [4:0] nt;
				reg [4:0] nh;
				nt = biq_tail;
				nh = biq_head;
				if (cmt_br_valid)
					nh = biq_head + {1'b0, cmt_biq - biq_head[3:0]};
				if (be_flush)
					nt = nh;
				else if (be_mispredict)
					nt = (biq_head + {1'b0, be_mis_biq - biq_head[3:0]}) + 5'd1;
				else if (f4_accept && grp_has_br)
					nt = biq_tail + 5'd1;
				biq_tail <= nt;
				biq_head <= nh;
			end
		end
	assign ic_f1_pc = pc1;
	always @(*) begin
		if (_sv2v_0)
			;
		nlp_we = f4_accept && !fault4;
		nlp_widx = pc4[NLPW + 1:2];
		nlp_wdata = {nlp_eq4, 1'b1, (nlpc4 && !nlp_eq4 ? nlp4[NTB + 1:2] : next4[NTB + 1:2])};
	end
	localparam integer QW = 105;
	(* syn_ramstyle = "lut_ram" *) reg [QW - 1:0] qb0 [0:(FQN / 4) - 1];
	(* syn_ramstyle = "lut_ram" *) reg [QW - 1:0] qb1 [0:(FQN / 4) - 1];
	(* syn_ramstyle = "lut_ram" *) reg [QW - 1:0] qb2 [0:(FQN / 4) - 1];
	(* syn_ramstyle = "lut_ram" *) reg [QW - 1:0] qb3 [0:(FQN / 4) - 1];
	reg [4:0] fq_head;
	reg [4:0] fq_tail;
	reg [4:0] fq_h1;
	wire [1:0] gs0 = pc4[3:2];
	wire [2:0] gcount = (fault4 ? 3'd1 : ({1'b0, end4} - {1'b0, gs0}) + 3'd1);
	wire [1:0] gslot0 = gs0;
	wire [1:0] gslot1 = gs0 + 2'd1;
	wire [1:0] gslot2 = gs0 + 2'd2;
	wire [1:0] gslot3 = gs0 + 2'd3;
	wire do_enq = f4_accept;
	wire [2:0] pfu [0:3];
	genvar _gv_gp_1;
	generate
		for (_gv_gp_1 = 0; _gv_gp_1 < 4; _gv_gp_1 = _gv_gp_1 + 1) begin : g_pd
			localparam gp = _gv_gp_1;
			o2_decode pdec(
				.pc(32'b00000000000000000000000000000000),
				.insn(blk4[32 * gp+:32]),
				.fetch_fault(fault4),
				.fu(pfu[gp]),
				.op(),
				.rs1(),
				.rs2(),
				.rd(),
				.use1(),
				.use2(),
				.wr(),
				.src2_imm(),
				.imm(),
				.is_jalr(),
				.exc(),
				.cause()
			);
		end
	endgenerate
	reg [QW - 1:0] gdat [0:3];
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_7
			reg signed [31:0] j;
			for (j = 0; j < 4; j = j + 1)
				begin : sv2v_autoblock_8
					reg [1:0] sl;
					reg [31:0] spc;
					reg [31:0] snext;
					sl = gs0 + sv2v_cast_2_signed(j);
					spc = {pc4[31:4], sl, 2'b00};
					snext = (sl == 2'd3 ? seq4 : {pc4[31:4], sl + 2'd1, 2'b00});
					gdat[j] = {spc, blk4[32 * sl+:32], (sl == end4 ? next4 : snext), fault4, biq_wptr, kcnt[sl], pfu[sl] == 3'd5, pfu[sl] == 3'd1};
				end
		end
	end
	reg [3:0] bwe;
	reg [2:0] bwa [0:3];
	reg [QW - 1:0] bwd [0:3];
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_9
			reg signed [31:0] b;
			for (b = 0; b < 4; b = b + 1)
				begin : sv2v_autoblock_10
					reg [1:0] j;
					reg [4:0] idx;
					j = sv2v_cast_2_signed(b) - fq_tail[1:0];
					idx = fq_tail + {3'b000, j};
					bwe[b] = do_enq && ({1'b0, j} < gcount);
					bwa[b] = idx[4:2];
					bwd[b] = gdat[j];
				end
		end
	end
	always @(posedge clk) begin
		if (bwe[0])
			qb0[bwa[0]] <= bwd[0];
		if (bwe[1])
			qb1[bwa[1]] <= bwd[1];
		if (bwe[2])
			qb2[bwa[2]] <= bwd[2];
		if (bwe[3])
			qb3[bwa[3]] <= bwd[3];
	end
	always @(posedge clk)
		if (rst || be_any) begin
			fq_head <= 5'd0;
			fq_h1 <= 5'd1;
			fq_tail <= 5'd0;
			fq_count <= 6'd0;
		end
		else begin
			fq_head <= fq_head + {3'b000, fq_pop};
			fq_h1 <= fq_h1 + {3'b000, fq_pop};
			fq_tail <= fq_tail + (do_enq ? {2'b00, gcount} : 5'd0);
			fq_count <= (fq_count + (do_enq ? {3'b000, gcount} : 6'd0)) - {4'b0000, fq_pop};
		end
	wire [4:0] fh1 = fq_h1;
	reg [QW - 1:0] brd [0:3];
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_11
			reg signed [31:0] b;
			for (b = 0; b < 4; b = b + 1)
				begin : sv2v_autoblock_12
					reg [2:0] ra;
					ra = (fq_head[1:0] == sv2v_cast_2_signed(b) ? fq_head[4:2] : fh1[4:2]);
					case (b)
						0: brd[b] = qb0[ra];
						1: brd[b] = qb1[ra];
						2: brd[b] = qb2[ra];
						default: brd[b] = qb3[ra];
					endcase
				end
		end
	end
	wire [QW - 1:0] h0d = brd[fq_head[1:0]];
	wire [QW - 1:0] h1d = brd[fh1[1:0]];
	assign fq_v0 = fq_count >= 6'd1;
	assign fq_v1 = fq_count >= 6'd2;
	assign {fq_pc0, fq_insn0, fq_pred0, fq_fault0, fq_biq0, fq_k0, fq_cmt0, fq_br0} = h0d;
	assign {fq_pc1, fq_insn1, fq_pred1, fq_fault1, fq_biq1, fq_k1, fq_cmt1, fq_br1} = h1d;
	reg u1_v;
	reg u1_taken;
	reg [31:0] u1_pc;
	reg [(4 * TI) - 1:0] u1_idx;
	reg [(4 * TT) - 1:0] u1_tag;
	reg [1:0] u1_base;
	reg [3:0] p_en;
	reg [(4 * TI) - 1:0] p_idx;
	reg [(4 * TW) - 1:0] p_data;
	wire [(4 * TI) - 1:0] cmt_idx = biq_idx[cmt_biq];
	always @(*) begin
		if (_sv2v_0)
			;
		tr_idx0 = cmt_idx[0+:TI];
		tr_idx1 = cmt_idx[TI+:TI];
		tr_idx2 = cmt_idx[2 * TI+:TI];
		tr_idx3 = cmt_idx[3 * TI+:TI];
	end
	always @(posedge clk) begin
		if (rst)
			u1_v <= 1'b0;
		else
			u1_v <= (cmt_br_valid && cmt_is_cbr) && !tinit_busy;
		u1_taken <= cmt_taken;
		u1_pc <= cmt_pc;
		u1_idx <= cmt_idx;
		u1_tag <= biq_tag[cmt_biq];
		case (cmt_pc[3:2])
			2'd0: u1_base <= bs0[cmt_pc[12:4]];
			2'd1: u1_base <= bs1[cmt_pc[12:4]];
			2'd2: u1_base <= bs2[cmt_pc[12:4]];
			default: u1_base <= bs3[cmt_pc[12:4]];
		endcase
	end
	reg u2_v;
	reg u2_taken;
	reg u2_pv_v;
	reg u2_al_v;
	reg [1:0] u2_pv;
	reg [1:0] u2_al;
	reg [1:0] u2_base;
	reg [31:0] u2_pc;
	reg [(4 * TI) - 1:0] u2_idx;
	reg [(4 * TT) - 1:0] u2_tag;
	reg [(4 * TW) - 1:0] u2_e;
	reg [(4 * TW) - 1:0] u1_e;
	reg [3:0] u1_h;
	reg u1_pv_v;
	reg u1_al_v;
	reg [1:0] u1_pv;
	reg [1:0] u1_al;
	reg p_ben;
	reg [10:0] p_bidx;
	reg [1:0] p_bdata;
	wire [1:0] u1_basef = (p_ben && (p_bidx == u1_pc[12:2]) ? p_bdata : u1_base);
	always @(*) begin : sv2v_autoblock_13
		reg [TW - 1:0] tu [0:3];
		if (_sv2v_0)
			;
		tu[0] = tue0;
		tu[1] = tue1;
		tu[2] = tue2;
		tu[3] = tue3;
		begin : sv2v_autoblock_14
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				begin
					u1_e[TW * i+:TW] = (p_en[i] && (p_idx[TI * i+:TI] == u1_idx[TI * i+:TI]) ? p_data[TW * i+:TW] : tu[i]);
					u1_h[i] = u1_e[((TW * i) + TW) - 1-:TT] == u1_tag[TT * i+:TT];
				end
		end
		u1_pv_v = |u1_h;
		u1_pv = (u1_h[3] ? 2'd3 : (u1_h[2] ? 2'd2 : (u1_h[1] ? 2'd1 : 2'd0)));
		u1_al_v = 1'b0;
		u1_al = 2'd0;
		case (u1_pv)
			2'd3: begin
				u1_al_v = |u1_h[2:0];
				u1_al = (u1_h[2] ? 2'd2 : (u1_h[1] ? 2'd1 : 2'd0));
			end
			2'd2: begin
				u1_al_v = |u1_h[1:0];
				u1_al = (u1_h[1] ? 2'd1 : 2'd0);
			end
			2'd1: begin
				u1_al_v = u1_h[0];
				u1_al = 2'd0;
			end
			default: begin
				u1_al_v = 1'b0;
				u1_al = 2'd0;
			end
		endcase
	end
	reg [(4 * TW) - 1:0] uw;
	always @(posedge clk) begin
		if (rst)
			u2_v <= 1'b0;
		else
			u2_v <= u1_v;
		u2_taken <= u1_taken;
		u2_pc <= u1_pc;
		u2_idx <= u1_idx;
		u2_tag <= u1_tag;
		u2_base <= (bw_en && (bw_idx == u1_pc[12:2]) ? bw_data : u1_basef);
		begin : sv2v_autoblock_15
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				u2_e[TW * i+:TW] <= (tw_en[i] && (u2_idx[TI * i+:TI] == u1_idx[TI * i+:TI]) ? uw[TW * i+:TW] : u1_e[TW * i+:TW]);
		end
		u2_pv_v <= u1_pv_v;
		u2_pv <= u1_pv;
		u2_al_v <= u1_al_v;
		u2_al <= u1_al;
		p_en <= (u2_v ? tw_en : 4'b0000);
		p_idx <= {tw_idx3, tw_idx2, tw_idx1, tw_idx0};
		p_data <= {tw_d3, tw_d2, tw_d1, tw_d0};
		p_ben <= bw_en && !tinit_busy;
		p_bidx <= bw_idx;
		p_bdata <= bw_data;
	end
	always @(*) begin : sv2v_autoblock_16
		reg [TW - 1:0] e [0:3];
		reg [1:0] pv;
		reg [1:0] al;
		reg [1:0] sl;
		reg pv_v;
		reg al_v;
		reg [2:0] pc_;
		reg [2:0] ac_;
		reg ppred;
		reg apred;
		reg bpred;
		reg wkp;
		reg fpred;
		reg mis;
		reg done_a;
		reg [TW - 1:0] ne;
		reg [2:0] c;
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_17
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				e[i] = u2_e[TW * i+:TW];
		end
		pv = u2_pv;
		al = u2_al;
		pv_v = u2_pv_v;
		al_v = u2_al_v;
		sl = u2_pc[3:2];
		bpred = u2_base[1];
		pc_ = e[pv][3 * sl+:3];
		ac_ = e[al][3 * sl+:3];
		ppred = (pv_v ? !pc_[2] : bpred);
		apred = (al_v ? !ac_[2] : bpred);
		wkp = (pv_v && ((pc_ == 3'd0) || (pc_ == 3'b111))) && (e[pv][13:12] == 2'd0);
		fpred = (pv_v ? (wkp ? apred : ppred) : bpred);
		mis = fpred != u2_taken;
		begin : sv2v_autoblock_18
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				uw[TW * i+:TW] = e[i];
		end
		tw_en = 4'b0000;
		bw_en = 1'b0;
		bw_idx = u2_pc[12:2];
		bw_data = sat2(u2_base, u2_taken);
		ne = e[pv];
		if (ppred != apred)
			ne[13:12] = sat2(ne[13:12], ppred == u2_taken);
		c = pc_;
		if (u2_taken)
			c = (c == 3'd3 ? 3'd3 : c + 3'd1);
		else
			c = (c == 3'b100 ? 3'b100 : c - 3'd1);
		ne[3 * sl+:3] = c;
		done_a = 1'b0;
		if (u2_v) begin
			if (pv_v) begin
				tw_en[pv] = 1'b1;
				uw[TW * pv+:TW] = ne;
				if (!al_v && (ne[13:12] == 2'd0))
					bw_en = 1'b1;
			end
			else
				bw_en = 1'b1;
			if (mis && !(pv_v && (pv == 2'd3))) begin
				begin : sv2v_autoblock_19
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						if (((!pv_v || (sv2v_cast_2_signed(i) > pv)) && !done_a) && (e[i][13:12] == 2'd0)) begin : sv2v_autoblock_20
							reg [TW - 1:0] na;
							na = 1'sb0;
							na[TW - 1-:TT] = u2_tag[TT * i+:TT];
							na[3 * sl+:3] = (u2_taken ? 3'd0 : 3'b111);
							tw_en[i] = 1'b1;
							uw[TW * i+:TW] = na;
							done_a = 1'b1;
						end
				end
				if (!done_a) begin : sv2v_autoblock_21
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						if ((!pv_v || (sv2v_cast_2_signed(i) > pv)) && (e[i][13:12] != 2'd0)) begin : sv2v_autoblock_22
							reg [TW - 1:0] nd;
							nd = e[i];
							nd[13:12] = nd[13:12] - 2'd1;
							tw_en[i] = 1'b1;
							uw[TW * i+:TW] = nd;
						end
				end
			end
		end
		tw_idx0 = u2_idx[0+:TI];
		tw_idx1 = u2_idx[TI+:TI];
		tw_idx2 = u2_idx[2 * TI+:TI];
		tw_idx3 = u2_idx[3 * TI+:TI];
		tw_d0 = uw[0+:TW];
		tw_d1 = uw[TW+:TW];
		tw_d2 = uw[2 * TW+:TW];
		tw_d3 = uw[3 * TW+:TW];
	end
	initial _sv2v_0 = 0;
endmodule
module o2_iq (
	clk,
	rst,
	d_v,
	d_pay0,
	d_pay1,
	d_dep0,
	d_dep1,
	d_lat0,
	d_lat1,
	d_brm0,
	d_brm1,
	d_sqm0,
	d_sqm1,
	d_store0,
	d_store1,
	d_head0,
	d_head1,
	d_rob0,
	d_rob1,
	a_slot0,
	a_slot1,
	free_cnt,
	wake_in,
	wake_out,
	issue_en,
	blk_lat,
	blk_l0,
	iss_v,
	iss_slot,
	iss_pay,
	iss_brm,
	iss_sqm,
	iss_rob,
	iss_lat,
	ext_done,
	sq_issued,
	sq_free,
	spec_ok,
	rob_head,
	br_ok,
	br_ok_tag,
	br_kill,
	br_kill_tag,
	flush
);
	reg _sv2v_0;
	parameter integer N = 8;
	parameter integer NC = 24;
	parameter integer BASE = 0;
	parameter integer PW = 64;
	parameter integer MEM = 0;
	input wire clk;
	input wire rst;
	input wire [1:0] d_v;
	input wire [PW - 1:0] d_pay0;
	input wire [PW - 1:0] d_pay1;
	input wire [NC - 1:0] d_dep0;
	input wire [NC - 1:0] d_dep1;
	input wire [1:0] d_lat0;
	input wire [1:0] d_lat1;
	input wire [7:0] d_brm0;
	input wire [7:0] d_brm1;
	input wire [7:0] d_sqm0;
	input wire [7:0] d_sqm1;
	input wire d_store0;
	input wire d_store1;
	input wire d_head0;
	input wire d_head1;
	input wire [4:0] d_rob0;
	input wire [4:0] d_rob1;
	output wire [2:0] a_slot0;
	output wire [2:0] a_slot1;
	output reg [3:0] free_cnt;
	input wire [NC - 1:0] wake_in;
	output wire [N - 1:0] wake_out;
	input wire issue_en;
	input wire blk_lat;
	input wire blk_l0;
	output wire iss_v;
	output reg [2:0] iss_slot;
	output reg [PW - 1:0] iss_pay;
	output reg [7:0] iss_brm;
	output reg [7:0] iss_sqm;
	output reg [4:0] iss_rob;
	output reg [1:0] iss_lat;
	input wire [N - 1:0] ext_done;
	input wire [7:0] sq_issued;
	input wire [7:0] sq_free;
	input wire spec_ok;
	input wire [4:0] rob_head;
	input wire br_ok;
	input wire [2:0] br_ok_tag;
	input wire br_kill;
	input wire [2:0] br_kill_tag;
	input wire flush;
	function automatic [7:0] oh_lo8;
		input [7:0] v;
		oh_lo8 = v & (~v + 8'd1);
	endfunction
	function automatic [7:0] rev8;
		input [7:0] v;
		rev8 = {v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]};
	endfunction
	function automatic [2:0] enc8;
		input [7:0] oh;
		enc8 = {((oh[4] | oh[5]) | oh[6]) | oh[7], ((oh[2] | oh[3]) | oh[6]) | oh[7], ((oh[1] | oh[3]) | oh[5]) | oh[7]};
	endfunction
	function automatic [7:0] oh_hi8;
		input [7:0] v;
		oh_hi8 = rev8(oh_lo8(rev8(v)));
	endfunction
	function automatic [2:0] pe_lo8;
		input [7:0] v;
		pe_lo8 = enc8(oh_lo8(v));
	endfunction
	function automatic [2:0] pe_hi8;
		input [7:0] v;
		pe_hi8 = enc8(oh_hi8(v));
	endfunction
	function automatic [3:0] popc8;
		input [7:0] v;
		popc8 = (((((({3'b000, v[0]} + {3'b000, v[1]}) + {3'b000, v[2]}) + {3'b000, v[3]}) + {3'b000, v[4]}) + {3'b000, v[5]}) + {3'b000, v[6]}) + {3'b000, v[7]};
	endfunction
	wire [N - 1:0] valid;
	wire [N - 1:0] resv;
	reg [N - 1:0] req;
	reg [N - 1:0] grant;
	reg [N - 1:0] ready;
	wire [(N * PW) - 1:0] pay_f;
	wire [(N * 8) - 1:0] brm_f;
	wire [(N * 8) - 1:0] sqm_f;
	wire [(N * 5) - 1:0] rob_f;
	wire [(N * 2) - 1:0] lat_f;
	wire [(N * N) - 1:0] older_f;
	wire [N - 1:0] freem = ~(valid | resv);
	wire [7:0] oh0 = oh_lo8(freem);
	wire [7:0] oh1 = oh_hi8(freem);
	assign a_slot0 = enc8(oh0);
	assign a_slot1 = enc8(oh1);
	wire alloc0_ok = d_v[0] && !flush;
	wire alloc1_ok = d_v[1] && !flush;
	wire [7:0] s1oh = (d_v[0] ? oh1 : oh0);
	wire [7:0] amask = (alloc0_ok ? oh0 : 8'b00000000) | (alloc1_ok ? s1oh : 8'b00000000);
	function automatic signed [3:0] sv2v_cast_4_signed;
		input reg signed [3:0] inp;
		sv2v_cast_4_signed = inp;
	endfunction
	always @(posedge clk)
		if (rst)
			free_cnt <= sv2v_cast_4_signed(N);
		else
			free_cnt <= (popc8(freem) - {3'b000, alloc0_ok}) - {3'b000, alloc1_ok};
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < N; i = i + 1)
				req[i] = ((ready[i] && issue_en) && !(blk_lat && (lat_f[2 * i+:2] != 2'd0))) && !(blk_l0 && (lat_f[2 * i+:2] == 2'd0));
		end
		begin : sv2v_autoblock_2
			reg signed [31:0] i;
			for (i = 0; i < N; i = i + 1)
				grant[i] = req[i] && !(|(req & older_f[N * i+:N]));
		end
	end
	assign iss_v = |grant;
	always @(*) begin
		if (_sv2v_0)
			;
		iss_slot = enc8(grant);
		iss_pay = 1'sb0;
		iss_brm = 8'b00000000;
		iss_sqm = 8'b00000000;
		iss_rob = 5'b00000;
		iss_lat = 2'b00;
		begin : sv2v_autoblock_3
			reg signed [31:0] i;
			for (i = 0; i < N; i = i + 1)
				begin
					iss_pay = iss_pay | ({PW {grant[i]}} & pay_f[PW * i+:PW]);
					iss_brm = iss_brm | ({8 {grant[i]}} & brm_f[8 * i+:8]);
					iss_sqm = iss_sqm | ({8 {grant[i]}} & sqm_f[8 * i+:8]);
					iss_rob = iss_rob | ({5 {grant[i]}} & rob_f[5 * i+:5]);
					iss_lat = iss_lat | ({2 {grant[i]}} & lat_f[2 * i+:2]);
				end
		end
	end
	genvar _gv_g_1;
	generate
		for (_gv_g_1 = 0; _gv_g_1 < N; _gv_g_1 = _gv_g_1 + 1) begin : e
			localparam g = _gv_g_1;
			reg v;
			reg rv;
			reg p1;
			reg p2a;
			reg p2b;
			reg ex;
			reg [NC - 1:0] dep;
			reg [N - 1:0] old;
			reg [PW - 1:0] pay;
			reg [1:0] lat;
			reg [7:0] brm;
			reg [7:0] sqm;
			reg st;
			reg hd;
			reg [4:0] rob;
			wire a0 = alloc0_ok && oh0[g];
			wire a1 = alloc1_ok && s1oh[g];
			wire kill = flush || (br_kill && brm[br_kill_tag]);
			wire gr = grant[g];
			always @(*) begin : sv2v_autoblock_4
				reg rdy;
				if (_sv2v_0)
					;
				rdy = v && (dep == {NC {1'sb0}});
				if (((MEM != 0) && !st) && (pay[0] || !spec_ok))
					rdy = rdy && ((sqm & ~sq_issued) == 8'b00000000);
				if ((MEM != 0) && hd)
					rdy = rdy && (rob == rob_head);
				ready[g] = rdy;
			end
			assign wake_out[g] = (((gr && (lat == 2'd0)) || p1) || p2b) || (ex && ext_done[g]);
			assign valid[g] = v;
			assign resv[g] = rv;
			assign pay_f[PW * g+:PW] = pay;
			assign brm_f[8 * g+:8] = brm;
			assign sqm_f[8 * g+:8] = sqm;
			assign rob_f[5 * g+:5] = rob;
			assign lat_f[2 * g+:2] = lat;
			assign older_f[N * g+:N] = old;
			always @(posedge clk)
				if (rst) begin
					v <= 1'b0;
					rv <= 1'b0;
					p1 <= 1'b0;
					p2a <= 1'b0;
					p2b <= 1'b0;
					ex <= 1'b0;
				end
				else if (a0 || a1) begin
					v <= 1'b1;
					rv <= 1'b0;
					p1 <= 1'b0;
					p2a <= 1'b0;
					p2b <= 1'b0;
					ex <= 1'b0;
				end
				else begin
					p2b <= p2a && !flush;
					if (gr) begin
						v <= 1'b0;
						rv <= lat != 2'd0;
						p1 <= lat == 2'd1;
						p2a <= lat == 2'd2;
						ex <= lat == 2'd3;
					end
					else begin
						p1 <= 1'b0;
						p2a <= 1'b0;
						if ((p1 || p2b) || (ex && ext_done[g])) begin
							rv <= 1'b0;
							ex <= 1'b0;
						end
					end
					if (kill) begin
						v <= 1'b0;
						if (flush || ex) begin
							rv <= 1'b0;
							ex <= 1'b0;
						end
						if (flush) begin
							p1 <= 1'b0;
							p2a <= 1'b0;
							p2b <= 1'b0;
						end
					end
				end
			always @(posedge clk)
				if (a0) begin
					dep <= d_dep0 & ~wake_in;
					pay <= d_pay0;
					lat <= d_lat0;
					brm <= (br_ok ? d_brm0 & ~(8'b00000001 << br_ok_tag) : d_brm0);
					sqm <= d_sqm0 & ~sq_free;
					st <= d_store0;
					hd <= d_head0;
					rob <= d_rob0;
					old <= valid & ~grant;
				end
				else if (a1) begin
					dep <= d_dep1 & ~wake_in;
					pay <= d_pay1;
					lat <= d_lat1;
					brm <= (br_ok ? d_brm1 & ~(8'b00000001 << br_ok_tag) : d_brm1);
					sqm <= d_sqm1 & ~sq_free;
					st <= d_store1;
					hd <= d_head1;
					rob <= d_rob1;
					old <= (valid & ~grant) | (alloc0_ok ? oh0 : 8'b00000000);
				end
				else begin
					dep <= dep & ~wake_in;
					if (br_ok)
						brm[br_ok_tag] <= 1'b0;
					sqm <= sqm & ~sq_free;
					old <= old & ~amask;
				end
		end
	endgenerate
	initial _sv2v_0 = 0;
endmodule
module o2_prf (
	clk,
	rst,
	we,
	waddr,
	wdata,
	raddr_b,
	rsel,
	rdata
);
	reg _sv2v_0;
	parameter integer NW = 3;
	parameter integer NR = 7;
	input wire clk;
	input wire rst;
	input wire [NW - 1:0] we;
	input wire [(NW * 6) - 1:0] waddr;
	input wire [(NW * 32) - 1:0] wdata;
	input wire [((NW * NR) * 6) - 1:0] raddr_b;
	input wire [(NR * 2) - 1:0] rsel;
	output wire [(NR * 32) - 1:0] rdata;
	genvar _gv_w_1;
	genvar _gv_r_2;
	wire [31:0] q_all [0:(NW * NR) - 1];
	generate
		for (_gv_w_1 = 0; _gv_w_1 < NW; _gv_w_1 = _gv_w_1 + 1) begin : g_w
			localparam w = _gv_w_1;
			for (_gv_r_2 = 0; _gv_r_2 < NR; _gv_r_2 = _gv_r_2 + 1) begin : g_r
				localparam r = _gv_r_2;
				(* syn_ramstyle = "lut_ram" *) reg [31:0] bank [0:63];
				always @(posedge clk)
					if (we[w])
						bank[waddr[6 * w+:6]] <= wdata[32 * w+:32];
				assign q_all[(w * NR) + r] = bank[raddr_b[6 * ((w * NR) + r)+:6]];
			end
		end
		for (_gv_r_2 = 0; _gv_r_2 < NR; _gv_r_2 = _gv_r_2 + 1) begin : g_rd
			localparam r = _gv_r_2;
			reg [31:0] v;
			always @(*) begin
				if (_sv2v_0)
					;
				case (rsel[2 * r+:2])
					2'd1: v = q_all[0 + r];
					2'd2: v = q_all[(1 * NR) + r];
					2'd3: v = q_all[(2 * NR) + r];
					default: v = 32'b00000000000000000000000000000000;
				endcase
			end
			assign rdata[32 * r+:32] = v;
		end
	endgenerate
	initial _sv2v_0 = 0;
endmodule
module o2_rename (
	clk,
	rst,
	fq_v0,
	fq_v1,
	fq_pc0,
	fq_pc1,
	fq_insn0,
	fq_insn1,
	fq_pred0,
	fq_pred1,
	fq_fault0,
	fq_fault1,
	fq_biq0,
	fq_biq1,
	fq_k0,
	fq_k1,
	fq_cmt0,
	fq_cmt1,
	fq_br0,
	fq_br1,
	fq_pop,
	flush,
	br_kill,
	br_kill_tag,
	br_ok,
	br_ok_tag,
	cm_wr,
	cm_rd0,
	cm_rd1,
	cm_pdst0,
	cm_pdst1,
	cm_pold0,
	cm_pold1,
	rob_empty,
	replay_set,
	replay_pc,
	md_set,
	rob_tail,
	rob_room,
	sq_room,
	iq0_free,
	iq1_free,
	iqm_free,
	iq0_a0,
	iq0_a1,
	iq1_a0,
	iq1_a1,
	iqm_a0,
	iqm_a1,
	wake,
	sq_tail,
	sq_count,
	sq_valid,
	iq0_dv,
	iq1_dv,
	iqm_dv,
	s0_pay,
	s1_pay,
	s0_imm,
	s1_imm,
	s0_dep,
	s1_dep,
	s0_lat,
	s1_lat,
	s0_brm,
	s1_brm,
	s0_sqm,
	s1_sqm,
	s0_st,
	s1_st,
	s0_head,
	s1_head,
	s0_rob,
	s1_rob,
	rob_dv,
	rob_e0,
	rob_e1,
	sq_alloc,
	brt_we,
	brt_tag,
	brt_data,
	ckpt_sq_tail,
	perf_fe_stall,
	perf_be_stall
);
	reg _sv2v_0;
	input wire clk;
	input wire rst;
	input wire fq_v0;
	input wire fq_v1;
	input wire [31:0] fq_pc0;
	input wire [31:0] fq_pc1;
	input wire [31:0] fq_insn0;
	input wire [31:0] fq_insn1;
	input wire [31:0] fq_pred0;
	input wire [31:0] fq_pred1;
	input wire fq_fault0;
	input wire fq_fault1;
	input wire [3:0] fq_biq0;
	input wire [3:0] fq_biq1;
	input wire [1:0] fq_k0;
	input wire [1:0] fq_k1;
	input wire fq_cmt0;
	input wire fq_cmt1;
	input wire fq_br0;
	input wire fq_br1;
	output wire [1:0] fq_pop;
	input wire flush;
	input wire br_kill;
	input wire [2:0] br_kill_tag;
	input wire br_ok;
	input wire [2:0] br_ok_tag;
	input wire [1:0] cm_wr;
	input wire [4:0] cm_rd0;
	input wire [4:0] cm_rd1;
	input wire [5:0] cm_pdst0;
	input wire [5:0] cm_pdst1;
	input wire [5:0] cm_pold0;
	input wire [5:0] cm_pold1;
	input wire rob_empty;
	input wire replay_set;
	input wire [31:0] replay_pc;
	input wire md_set;
	input wire [5:0] rob_tail;
	input wire [1:0] rob_room;
	input wire [1:0] sq_room;
	input wire [3:0] iq0_free;
	input wire [3:0] iq1_free;
	input wire [3:0] iqm_free;
	input wire [2:0] iq0_a0;
	input wire [2:0] iq0_a1;
	input wire [2:0] iq1_a0;
	input wire [2:0] iq1_a1;
	input wire [2:0] iqm_a0;
	input wire [2:0] iqm_a1;
	input wire [23:0] wake;
	input wire [3:0] sq_tail;
	input wire [3:0] sq_count;
	input wire [7:0] sq_valid;
	output reg [1:0] iq0_dv;
	output reg [1:0] iq1_dv;
	output reg [1:0] iqm_dv;
	output reg [38:0] s0_pay;
	output reg [38:0] s1_pay;
	output wire [31:0] s0_imm;
	output wire [31:0] s1_imm;
	output reg [23:0] s0_dep;
	output reg [23:0] s1_dep;
	output reg [1:0] s0_lat;
	output reg [1:0] s1_lat;
	output reg [7:0] s0_brm;
	output reg [7:0] s1_brm;
	output reg [7:0] s0_sqm;
	output reg [7:0] s1_sqm;
	output reg s0_st;
	output reg s1_st;
	output reg s0_head;
	output reg s1_head;
	output reg [4:0] s0_rob;
	output reg [4:0] s1_rob;
	output reg [1:0] rob_dv;
	output reg [127:0] rob_e0;
	output reg [127:0] rob_e1;
	output reg [1:0] sq_alloc;
	output reg brt_we;
	output reg [2:0] brt_tag;
	output reg [107:0] brt_data;
	output reg [3:0] ckpt_sq_tail;
	output wire perf_fe_stall;
	output wire perf_be_stall;
	function automatic [7:0] oh_lo8;
		input [7:0] v;
		oh_lo8 = v & (~v + 8'd1);
	endfunction
	function automatic [7:0] rev8;
		input [7:0] v;
		rev8 = {v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]};
	endfunction
	function automatic [2:0] enc8;
		input [7:0] oh;
		enc8 = {((oh[4] | oh[5]) | oh[6]) | oh[7], ((oh[2] | oh[3]) | oh[6]) | oh[7], ((oh[1] | oh[3]) | oh[5]) | oh[7]};
	endfunction
	function automatic [7:0] oh_hi8;
		input [7:0] v;
		oh_hi8 = rev8(oh_lo8(rev8(v)));
	endfunction
	function automatic [2:0] pe_lo8;
		input [7:0] v;
		pe_lo8 = enc8(oh_lo8(v));
	endfunction
	function automatic [2:0] pe_hi8;
		input [7:0] v;
		pe_hi8 = enc8(oh_hi8(v));
	endfunction
	function automatic [3:0] popc8;
		input [7:0] v;
		popc8 = (((((({3'b000, v[0]} + {3'b000, v[1]}) + {3'b000, v[2]}) + {3'b000, v[3]}) + {3'b000, v[4]}) + {3'b000, v[5]}) + {3'b000, v[6]}) + {3'b000, v[7]};
	endfunction
	wire [2:0] fu0;
	wire [2:0] fu1;
	wire [3:0] op0;
	wire [3:0] op1;
	wire [4:0] rs1_0;
	wire [4:0] rs2_0;
	wire [4:0] rd_0;
	wire [4:0] rs1_1;
	wire [4:0] rs2_1;
	wire [4:0] rd_1;
	wire use1_0;
	wire use2_0;
	wire wr_0;
	wire use1_1;
	wire use2_1;
	wire wr_1;
	wire si_0;
	wire si_1;
	wire jalr_0;
	wire jalr_1;
	wire ex_0;
	wire ex_1;
	wire [31:0] imm_0;
	wire [31:0] imm_1;
	wire [3:0] ca_0;
	wire [3:0] ca_1;
	o2_decode dec0(
		.pc(fq_pc0),
		.insn(fq_insn0),
		.fetch_fault(fq_fault0),
		.fu(fu0),
		.op(op0),
		.rs1(rs1_0),
		.rs2(rs2_0),
		.rd(rd_0),
		.use1(use1_0),
		.use2(use2_0),
		.wr(wr_0),
		.src2_imm(si_0),
		.imm(imm_0),
		.is_jalr(jalr_0),
		.exc(ex_0),
		.cause(ca_0)
	);
	o2_decode dec1(
		.pc(fq_pc1),
		.insn(fq_insn1),
		.fetch_fault(fq_fault1),
		.fu(fu1),
		.op(op1),
		.rs1(rs1_1),
		.rs2(rs2_1),
		.rd(rd_1),
		.use1(use1_1),
		.use2(use2_1),
		.wr(wr_1),
		.src2_imm(si_1),
		.imm(imm_1),
		.is_jalr(jalr_1),
		.exc(ex_1),
		.cause(ca_1)
	);
	wire take0 = fq_v0;
	wire take1 = ((fq_v1 && !fq_cmt0) && !fq_cmt1) && !(fq_br0 && fq_br1);
	reg r_v0;
	reg r_v1;
	reg [31:0] r_pc0;
	reg [31:0] r_pc1;
	reg [31:0] r_insn0;
	reg [31:0] r_insn1;
	reg [31:0] r_pred0;
	reg [31:0] r_pred1;
	reg [31:0] r_imm0;
	reg [31:0] r_imm1;
	reg [2:0] r_fu0;
	reg [2:0] r_fu1;
	reg [3:0] r_op0;
	reg [3:0] r_op1;
	reg [4:0] r_rs1_0;
	reg [4:0] r_rs2_0;
	reg [4:0] r_rs1_1;
	reg [4:0] r_rs2_1;
	(* syn_preserve = 1 *) reg [4:0] r_rd0;
	(* syn_preserve = 1 *) reg [4:0] r_rd1;
	reg r_wr0;
	reg r_wr1;
	reg r_si0;
	reg r_si1;
	reg r_jalr0;
	reg r_jalr1;
	reg [3:0] r_ca0;
	reg [3:0] r_ca1;
	reg [3:0] r_biq0;
	reg [3:0] r_biq1;
	reg [1:0] r_k0;
	reg [1:0] r_k1;
	wire ren_stall;
	wire ren_take = !ren_stall;
	assign fq_pop = ((ren_take && !flush) && !br_kill ? {1'b0, take0} + {1'b0, take0 && take1} : 2'd0);
	reg [5:0] rat [0:31];
	reg [5:0] crat [0:31];
	reg [5:0] fl [0:31];
	reg [5:0] fl_head;
	reg [5:0] fl_tail;
	reg [5:0] fl_chead;
	reg [7:0] tag_free;
	(* syn_ramstyle = "lut_ram" *) reg [191:0] ck_rat [0:7];
	reg [5:0] ck_head [0:7];
	reg [7:0] ck_young [0:7];
	wire [5:0] fl_count = fl_tail - fl_head;
	wire need_fl0 = r_v0 && r_wr0;
	wire need_fl1 = r_v1 && r_wr1;
	wire [1:0] need_fl = {1'b0, need_fl0} + {1'b0, need_fl1};
	wire [5:0] new0 = fl[fl_head[4:0]];
	wire [5:0] new1 = fl[(need_fl0 ? fl_head[4:0] + 5'd1 : fl_head[4:0])];
	wire br_in_grp = (r_v0 && (r_fu0 == 3'd1)) || (r_v1 && (r_fu1 == 3'd1));
	reg [2:0] new_tag;
	reg tag_avail;
	always @(*) begin
		if (_sv2v_0)
			;
		new_tag = pe_lo8(tag_free);
		tag_avail = |tag_free;
	end
	wire [5:0] ps1_0 = rat[r_rs1_0];
	wire [5:0] ps2_0 = rat[r_rs2_0];
	wire [5:0] po_0 = rat[r_rd0];
	wire s1_from0 = (r_wr0 && (r_rs1_1 == r_rd0)) && (r_rs1_1 != 5'd0);
	wire s2_from0 = (r_wr0 && (r_rs2_1 == r_rd0)) && (r_rs2_1 != 5'd0);
	wire [5:0] ps1_1 = (s1_from0 ? new0 : rat[r_rs1_1]);
	wire [5:0] ps2_1 = (s2_from0 ? new0 : rat[r_rs2_1]);
	wire [5:0] po_1 = (r_wr0 && (r_rd1 == r_rd0) ? new0 : rat[r_rd1]);
	wire [7:0] active_mask = ~tag_free;
	wire br0 = r_v0 && (r_fu0 == 3'd1);
	wire [7:0] brm_0 = active_mask;
	wire [7:0] brm_1 = active_mask | (br0 ? 8'b00000001 << new_tag : 8'b00000000);
	reg d_v0;
	reg d_v1;
	reg [31:0] d_pc0;
	reg [31:0] d_pc1;
	reg [31:0] d_insn0;
	reg [31:0] d_insn1;
	reg [31:0] d_pred0;
	reg [31:0] d_pred1;
	reg [31:0] d_imm0;
	reg [31:0] d_imm1;
	reg [2:0] d_fu0;
	reg [2:0] d_fu1;
	reg [3:0] d_op0;
	reg [3:0] d_op1;
	reg [4:0] d_rd0;
	reg [4:0] d_rd1;
	reg d_wr0;
	reg d_wr1;
	reg d_si0;
	reg d_si1;
	reg d_jalr0;
	reg d_jalr1;
	reg [3:0] d_ca0;
	reg [3:0] d_ca1;
	reg [3:0] d_biq0;
	reg [3:0] d_biq1;
	reg [1:0] d_k0;
	reg [1:0] d_k1;
	reg [5:0] d_ps1_0;
	reg [5:0] d_ps2_0;
	reg [5:0] d_pd0;
	reg [5:0] d_po0;
	reg [5:0] d_ps1_1;
	reg [5:0] d_ps2_1;
	reg [5:0] d_pd1;
	reg [5:0] d_po1;
	reg d_s1from0;
	reg d_s2from0;
	reg [7:0] d_brm0;
	reg [7:0] d_brm1;
	reg [2:0] d_tag;
	reg [1:0] d_q0;
	reg [1:0] d_q1;
	reg [1:0] fl_room;
	wire dis_stall;
	assign ren_stall = r_v0 && (((dis_stall || ((need_fl == 2'd2) && !fl_room[1])) || ((need_fl == 2'd1) && !fl_room[0])) || (br_in_grp && !tag_avail));
	reg [1:0] rq0;
	reg [1:0] rq1;
	always @(*) begin
		if (_sv2v_0)
			;
		case (r_fu0)
			3'd1: rq0 = 2'd0;
			3'd4: rq0 = 2'd1;
			3'd2, 3'd3: rq0 = 2'd2;
			3'd5: rq0 = 2'd3;
			default: rq0 = (iq0_free >= iq1_free ? 2'd0 : 2'd1);
		endcase
		case (r_fu1)
			3'd1: rq1 = 2'd0;
			3'd4: rq1 = 2'd1;
			3'd2, 3'd3: rq1 = 2'd2;
			3'd5: rq1 = 2'd3;
			default: rq1 = (rq0 == 2'd0 ? 2'd1 : (rq0 == 2'd1 ? 2'd0 : (iq0_free >= iq1_free ? 2'd0 : 2'd1)));
		endcase
	end
	(* syn_maxfan = 24 *) wire ren_go = ((r_v0 && !ren_stall) && !flush) && !br_kill;
	reg [191:0] ck_wd;
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 32; i = i + 1)
				begin : sv2v_autoblock_2
					reg [5:0] v;
					v = rat[i];
					if (need_fl0 && (r_rd0 == sv2v_cast_5_signed(i)))
						v = new0;
					if ((!br0 && need_fl1) && (r_rd1 == sv2v_cast_5_signed(i)))
						v = new1;
					ck_wd[6 * i+:6] = v;
				end
		end
	end
	wire ck_we = ((ren_go && br_in_grp) && !flush) && !br_kill;
	always @(posedge clk)
		if (ck_we)
			ck_rat[new_tag] <= ck_wd;
	wire [191:0] ck_rd = ck_rat[br_kill_tag];
	reg [63:0] pt_v;
	reg [4:0] pt_col [0:63];
	function automatic [23:0] col1h;
		input [4:0] c;
		col1h = 24'b000000000000000000000001 << c;
	endfunction
	reg [13:0] hpc [0:3];
	reg [3:0] hpc_v;
	reg [1:0] hpc_rr;
	wire mem0 = (d_fu0 == 3'd2) || (d_fu0 == 3'd3);
	wire mem1 = (d_fu1 == 3'd2) || (d_fu1 == 3'd3);
	wire hd0 = mem0 && ((((hpc_v[0] && (hpc[0] == d_pc0[15:2])) || (hpc_v[1] && (hpc[1] == d_pc0[15:2]))) || (hpc_v[2] && (hpc[2] == d_pc0[15:2]))) || (hpc_v[3] && (hpc[3] == d_pc0[15:2])));
	wire hd1 = mem1 && ((((hpc_v[0] && (hpc[0] == d_pc1[15:2])) || (hpc_v[1] && (hpc[1] == d_pc1[15:2]))) || (hpc_v[2] && (hpc[2] == d_pc1[15:2]))) || (hpc_v[3] && (hpc[3] == d_pc1[15:2])));
	wire [1:0] q0;
	wire [1:0] q1;
	assign q0 = d_q0;
	assign q1 = d_q1;
	wire [1:0] nq0 = {1'b0, d_v0 && (q0 == 2'd0)} + {1'b0, d_v1 && (q1 == 2'd0)};
	wire [1:0] nq1 = {1'b0, d_v0 && (q0 == 2'd1)} + {1'b0, d_v1 && (q1 == 2'd1)};
	wire [1:0] nqm = {1'b0, d_v0 && (q0 == 2'd2)} + {1'b0, d_v1 && (q1 == 2'd2)};
	wire st0 = d_v0 && (d_fu0 == 3'd3);
	wire st1 = d_v1 && (d_fu1 == 3'd3);
	wire [1:0] nst = {1'b0, st0} + {1'b0, st1};
	wire [1:0] nrob = {1'b0, d_v0} + {1'b0, d_v1};
	reg serial_pend;
	wire cmt_wait = (d_v0 && (d_fu0 == 3'd5)) && !rob_empty;
	assign dis_stall = d_v0 && (((((((({2'b00, nq0} > iq0_free) || ({2'b00, nq1} > iq1_free)) || ({2'b00, nqm} > iqm_free)) || !(d_v1 ? rob_room[1] : rob_room[0])) || ((nst == 2'd2) && !sq_room[1])) || ((nst == 2'd1) && !sq_room[0])) || cmt_wait) || serial_pend);
	(* syn_maxfan = 24 *) wire dis_go = ((d_v0 && !dis_stall) && !flush) && !br_kill;
	assign perf_fe_stall = !d_v0;
	assign perf_be_stall = dis_stall;
	wire [2:0] sl0 = (q0 == 2'd0 ? iq0_a0 : (q0 == 2'd1 ? iq1_a0 : iqm_a0));
	wire same_q = d_v0 && (q0 == q1);
	wire [2:0] sl1 = (q1 == 2'd0 ? (same_q ? iq0_a1 : iq0_a0) : (q1 == 2'd1 ? (same_q ? iq1_a1 : iq1_a0) : (same_q ? iqm_a1 : iqm_a0)));
	wire [4:0] col0 = (q0 == 2'd0 ? 5'd0 : (q0 == 2'd1 ? 5'd8 : 5'd16)) + {2'b00, sl0};
	wire [4:0] col1 = (q1 == 2'd0 ? 5'd0 : (q1 == 2'd1 ? 5'd8 : 5'd16)) + {2'b00, sl1};
	function automatic [23:0] depv;
		input [5:0] p;
		depv = ((p != 6'd0) && pt_v[p] ? col1h(pt_col[p]) : 24'b000000000000000000000000);
	endfunction
	function automatic [1:0] pbank;
		input [5:0] p;
		reg [1:0] c;
		begin
			c = pt_col[p][4:3];
			pbank = ((p == 6'd0) || (c == 2'b11) ? 2'b00 : c + 2'b01);
		end
	endfunction
	function automatic [1:0] qbank;
		input [1:0] q;
		qbank = (q == 2'd0 ? 2'b01 : (q == 2'd1 ? 2'b10 : 2'b11));
	endfunction
	wire [1:0] sb1_0 = pbank(d_ps1_0);
	wire [1:0] sb2_0 = pbank(d_ps2_0);
	wire [1:0] sb1_1 = (d_s1from0 ? qbank(q0) : pbank(d_ps1_1));
	wire [1:0] sb2_1 = (d_s2from0 ? qbank(q0) : pbank(d_ps2_1));
	reg [23:0] wake_q;
	wire [23:0] dep0 = (depv(d_ps1_0) | depv(d_ps2_0)) & ~wake_q;
	wire [23:0] dep1 = (d_s1from0 ? col1h(col0) : depv(d_ps1_1) & ~wake_q) | (d_s2from0 ? col1h(col0) : depv(d_ps2_1) & ~wake_q);
	function automatic [1:0] latc;
		input [2:0] fu;
		input [3:0] op;
		input hd;
		if (fu == 3'd2)
			latc = (hd ? 2'd3 : 2'd1);
		else if (fu == 3'd3)
			latc = (hd ? 2'd3 : 2'd0);
		else if (fu == 3'd4)
			latc = 2'd2;
		else
			latc = 2'd0;
	endfunction
	wire [5:0] rob_i0 = rob_tail;
	wire [5:0] rob_i1 = rob_tail + 6'd1;
	wire [3:0] sq_i0 = sq_tail;
	wire [3:0] sq_i1 = sq_tail + {3'b000, st0};
	wire [7:0] sqm_0 = sq_valid;
	wire [7:0] sqm_1 = sq_valid | (st0 ? 8'b00000001 << sq_i0[2:0] : 8'b00000000);
	function automatic [38:0] mkpay;
		input [1:0] b1;
		input [1:0] b2;
		input [3:0] op;
		input si;
		input [5:0] s1;
		input [5:0] s2;
		input [5:0] pd;
		input wr;
		input [2:0] tag;
		input [2:0] sqi;
		input jalr;
		input [2:0] fu;
		input wt;
		mkpay = {b1, b2, op, si, s1, s2, pd, wr, tag, sqi, jalr, fu, wt};
	endfunction
	reg [63:0] lwt;
	reg [15:0] lwt_age;
	wire wt0 = lwt[d_pc0[7:2]];
	wire wt1 = lwt[d_pc1[7:2]];
	wire [38:0] pay0 = mkpay(sb1_0, sb2_0, d_op0, d_si0, d_ps1_0, d_ps2_0, d_pd0, d_wr0, d_tag, sq_i0[2:0], d_jalr0, d_fu0, wt0);
	wire [38:0] pay1 = mkpay(sb1_1, sb2_1, d_op1, d_si1, d_ps1_1, d_ps2_1, d_pd1, d_wr1, d_tag, sq_i1[2:0], d_jalr1, d_fu1, wt1);
	assign s0_imm = d_imm0;
	assign s1_imm = d_imm1;
	always @(*) begin : sv2v_autoblock_3
		reg a0;
		reg b0;
		reg a1;
		reg b1;
		reg am;
		reg bm;
		if (_sv2v_0)
			;
		a0 = d_v0 && (q0 == 2'd0);
		b0 = d_v1 && (q1 == 2'd0);
		a1 = d_v0 && (q0 == 2'd1);
		b1 = d_v1 && (q1 == 2'd1);
		am = d_v0 && (q0 == 2'd2);
		bm = d_v1 && (q1 == 2'd2);
		iq0_dv = {dis_go && b0, dis_go && a0};
		iq1_dv = {dis_go && b1, dis_go && a1};
		iqm_dv = {dis_go && bm, dis_go && am};
		s0_pay = pay0;
		s1_pay = pay1;
		s0_dep = dep0;
		s1_dep = dep1;
		s0_lat = latc(d_fu0, d_op0, hd0);
		s1_lat = latc(d_fu1, d_op1, hd1);
		s0_brm = (br_ok ? d_brm0 & ~(8'b00000001 << br_ok_tag) : d_brm0);
		s1_brm = (br_ok ? d_brm1 & ~(8'b00000001 << br_ok_tag) : d_brm1);
		s0_rob = rob_i0[4:0];
		s1_rob = rob_i1[4:0];
		s0_sqm = sqm_0;
		s1_sqm = sqm_1;
		s0_st = st0;
		s1_st = st1;
		s0_head = hd0;
		s1_head = hd1;
	end
	function automatic [127:0] mkrob;
		input [31:0] pc;
		input [31:0] insn;
		input [4:0] rd;
		input wr;
		input [5:0] pd;
		input [5:0] po;
		input [2:0] fu;
		input [3:0] op;
		input [3:0] ca;
		input [2:0] sqi;
		input [3:0] biq;
		input [2:0] tag;
		input [5:0] ps1;
		input [1:0] sb1;
		mkrob = {pc, insn, rd, wr, pd, po, fu, op, ca, sqi, biq, tag, ps1, sb1, 17'b00000000000000000};
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		rob_dv = {dis_go && d_v1, dis_go};
		rob_e0 = mkrob(d_pc0, d_insn0, d_rd0, d_wr0, d_pd0, d_po0, d_fu0, d_op0, d_ca0, sq_i0[2:0], d_biq0, d_tag, d_ps1_0, sb1_0);
		rob_e1 = mkrob(d_pc1, d_insn1, d_rd1, d_wr1, d_pd1, d_po1, d_fu1, d_op1, d_ca1, sq_i1[2:0], d_biq1, d_tag, d_ps1_1, sb1_1);
		sq_alloc = (dis_go ? nst : 2'd0);
		brt_we = dis_go && ((d_fu0 == 3'd1) || (d_v1 && (d_fu1 == 3'd1)));
		brt_tag = d_tag;
		if (d_fu0 == 3'd1)
			brt_data = {d_pc0, d_pred0, d_imm0, d_biq0, d_k0, d_jalr0, rob_i0[4:0]};
		else
			brt_data = {d_pc1, d_pred1, d_imm1, d_biq1, d_k1, d_jalr1, rob_i1[4:0]};
		ckpt_sq_tail = sq_tail + (d_fu0 == 3'd1 ? 4'd0 : {3'b000, st0});
	end
	always @(posedge clk)
		if ((rst || flush) || br_kill) begin
			r_v0 <= 1'b0;
			r_v1 <= 1'b0;
		end
		else if (ren_take) begin
			r_v0 <= take0;
			r_v1 <= take0 && take1;
			r_pc0 <= fq_pc0;
			r_pc1 <= fq_pc1;
			r_insn0 <= fq_insn0;
			r_insn1 <= fq_insn1;
			r_pred0 <= fq_pred0;
			r_pred1 <= fq_pred1;
			r_imm0 <= imm_0;
			r_imm1 <= imm_1;
			r_fu0 <= fu0;
			r_fu1 <= fu1;
			r_op0 <= op0;
			r_op1 <= op1;
			r_rs1_0 <= rs1_0;
			r_rs2_0 <= rs2_0;
			r_rd0 <= rd_0;
			r_rs1_1 <= rs1_1;
			r_rs2_1 <= rs2_1;
			r_rd1 <= rd_1;
			r_wr0 <= wr_0;
			r_wr1 <= wr_1;
			r_si0 <= si_0;
			r_si1 <= si_1;
			r_jalr0 <= jalr_0;
			r_jalr1 <= jalr_1;
			r_ca0 <= ca_0;
			r_ca1 <= ca_1;
			r_biq0 <= fq_biq0;
			r_biq1 <= fq_biq1;
			r_k0 <= fq_k0;
			r_k1 <= fq_k1;
		end
	function automatic signed [5:0] sv2v_cast_6_signed;
		input reg signed [5:0] inp;
		sv2v_cast_6_signed = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			begin : sv2v_autoblock_4
				reg signed [31:0] i;
				for (i = 0; i < 32; i = i + 1)
					begin
						rat[i] <= sv2v_cast_6_signed(i);
						crat[i] <= sv2v_cast_6_signed(i);
						fl[i] <= sv2v_cast_6_signed(32 + i);
					end
			end
			fl_head <= 6'd0;
			fl_tail <= 6'd32;
			fl_chead <= 6'd0;
			fl_room <= 2'b11;
			tag_free <= 8'hff;
		end
		else begin : sv2v_autoblock_5
			reg [5:0] nt;
			reg [5:0] nch;
			nt = fl_tail;
			nch = fl_chead;
			if (cm_wr[0]) begin
				crat[cm_rd0] <= cm_pdst0;
				fl[nt[4:0]] <= cm_pold0;
				nt = nt + 6'd1;
				nch = nch + 6'd1;
			end
			if (cm_wr[1]) begin
				crat[cm_rd1] <= cm_pdst1;
				fl[nt[4:0]] <= cm_pold1;
				nt = nt + 6'd1;
				nch = nch + 6'd1;
			end
			if ((cm_wr[0] && cm_wr[1]) && (cm_rd0 == cm_rd1))
				crat[cm_rd1] <= cm_pdst1;
			fl_tail <= nt;
			fl_chead <= nch;
			begin : sv2v_autoblock_6
				reg [5:0] fc;
				fc = fl_tail - (fl_head + (ren_go ? {4'b0000, need_fl} : 6'd0));
				fl_room <= {fc >= 6'd2, fc >= 6'd1};
			end
			if (flush) begin
				fl_head <= nch;
				begin : sv2v_autoblock_7
					reg signed [31:0] i;
					for (i = 0; i < 32; i = i + 1)
						rat[i] <= crat[i];
				end
				if (cm_wr[0])
					rat[cm_rd0] <= cm_pdst0;
				if (cm_wr[1])
					rat[cm_rd1] <= cm_pdst1;
				tag_free <= 8'hff;
			end
			else if (br_kill) begin
				fl_head <= ck_head[br_kill_tag];
				begin : sv2v_autoblock_8
					reg signed [31:0] i;
					for (i = 0; i < 32; i = i + 1)
						rat[i] <= ck_rd[6 * i+:6];
				end
				tag_free <= (tag_free | ck_young[br_kill_tag]) | (8'b00000001 << br_kill_tag);
			end
			else begin : sv2v_autoblock_9
				reg [7:0] tf;
				tf = tag_free;
				if (br_ok)
					tf[br_ok_tag] = 1'b1;
				if (ren_go) begin
					fl_head <= fl_head + {4'b0000, need_fl};
					if (need_fl0)
						rat[r_rd0] <= new0;
					if (need_fl1)
						rat[r_rd1] <= new1;
					if (br_in_grp) begin
						tf[new_tag] = 1'b0;
						ck_head[new_tag] <= (fl_head + {5'b00000, need_fl0}) + {5'b00000, !br0 && need_fl1};
						ck_young[new_tag] <= 8'b00000000;
						begin : sv2v_autoblock_10
							reg signed [31:0] t;
							for (t = 0; t < 8; t = t + 1)
								if (!tag_free[t])
									ck_young[t][new_tag] <= 1'b1;
						end
					end
				end
				tag_free <= tf;
			end
		end
	always @(posedge clk)
		if ((rst || flush) || br_kill) begin
			d_v0 <= 1'b0;
			d_v1 <= 1'b0;
		end
		else if (!dis_stall) begin
			d_v0 <= ren_go;
			d_v1 <= ren_go && r_v1;
			d_pc0 <= r_pc0;
			d_pc1 <= r_pc1;
			d_insn0 <= r_insn0;
			d_insn1 <= r_insn1;
			d_pred0 <= r_pred0;
			d_pred1 <= r_pred1;
			d_imm0 <= r_imm0;
			d_imm1 <= r_imm1;
			d_fu0 <= r_fu0;
			d_fu1 <= r_fu1;
			d_op0 <= r_op0;
			d_op1 <= r_op1;
			d_rd0 <= r_rd0;
			d_rd1 <= r_rd1;
			d_wr0 <= r_wr0;
			d_wr1 <= r_wr1;
			d_si0 <= r_si0;
			d_si1 <= r_si1;
			d_jalr0 <= r_jalr0;
			d_jalr1 <= r_jalr1;
			d_ca0 <= r_ca0;
			d_ca1 <= r_ca1;
			d_biq0 <= r_biq0;
			d_biq1 <= r_biq1;
			d_k0 <= r_k0;
			d_k1 <= r_k1;
			d_ps1_0 <= ps1_0;
			d_ps2_0 <= ps2_0;
			d_pd0 <= (need_fl0 ? new0 : 6'd0);
			d_po0 <= po_0;
			d_ps1_1 <= ps1_1;
			d_ps2_1 <= ps2_1;
			d_pd1 <= (need_fl1 ? new1 : 6'd0);
			d_po1 <= po_1;
			d_s1from0 <= s1_from0;
			d_s2from0 <= s2_from0;
			d_brm0 <= (br_ok ? brm_0 & ~(8'b00000001 << br_ok_tag) : brm_0);
			d_brm1 <= (br_ok ? brm_1 & ~(8'b00000001 << br_ok_tag) : brm_1);
			d_tag <= new_tag;
			d_q0 <= rq0;
			d_q1 <= rq1;
		end
		else if (br_ok) begin
			d_brm0[br_ok_tag] <= 1'b0;
			d_brm1[br_ok_tag] <= 1'b0;
		end
	always @(posedge clk)
		if (rst || flush) begin
			pt_v <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
			wake_q <= 24'b000000000000000000000000;
			if (rst) begin : sv2v_autoblock_11
				reg signed [31:0] p;
				for (p = 0; p < 64; p = p + 1)
					pt_col[p] <= 5'b11000;
			end
		end
		else begin : sv2v_autoblock_12
			reg [63:0] nv;
			wake_q <= wake;
			begin : sv2v_autoblock_13
				reg signed [31:0] p;
				for (p = 0; p < 64; p = p + 1)
					nv[p] = pt_v[p] && !wake_q[pt_col[p]];
			end
			if (d_v0 && d_wr0) begin
				nv[d_pd0] = q0 != 2'd3;
				pt_col[d_pd0] <= (q0 == 2'd3 ? 5'b10000 : col0);
			end
			if (d_v1 && d_wr1) begin
				nv[d_pd1] = q1 != 2'd3;
				pt_col[d_pd1] <= (q1 == 2'd3 ? 5'b10000 : col1);
			end
			pt_v <= nv;
		end
	always @(posedge clk)
		if (rst) begin
			serial_pend <= 1'b0;
			hpc_v <= 4'b0000;
			hpc_rr <= 2'd0;
			lwt <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
			lwt_age <= 16'b0000000000000000;
		end
		else begin
			if (flush || rob_empty)
				serial_pend <= 1'b0;
			if (dis_go && (d_fu0 == 3'd5))
				serial_pend <= 1'b1;
			lwt_age <= lwt_age + 16'd1;
			if (lwt_age == 16'hffff)
				lwt <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
			else if (md_set)
				lwt[replay_pc[7:2]] <= 1'b1;
			if (replay_set) begin
				hpc[hpc_rr] <= replay_pc[15:2];
				hpc_v[hpc_rr] <= 1'b1;
				hpc_rr <= hpc_rr + 2'd1;
			end
		end
	initial _sv2v_0 = 0;
endmodule
module o2_lsu (
	clk,
	rst,
	sq_alloc,
	sq_tail,
	sq_count,
	sq_valid,
	sq_issued,
	sq_free,
	sq_room,
	spec_ok,
	md_viol,
	perf_ld_acc,
	perf_ld_miss,
	sq_empty,
	ex_v,
	ex_store,
	ex_op,
	ex_base,
	ex_base_t,
	ex_base_t1,
	ex_sdata,
	ex_imm,
	ex_pd,
	ex_rob,
	ex_sqidx,
	ex_sqm,
	ex_brm,
	ex_head,
	ex_slot,
	st_done_v,
	st_done_rob,
	st_exc,
	st_cause,
	st_tval,
	st_replay,
	bus_err_v,
	bus_err_wb,
	bus_err_addr,
	ld_wb_v,
	ld_wb_pd,
	ld_wb_data,
	ld_done_v,
	ld_done_rob,
	ld_exc,
	ld_cause,
	ld_tval,
	ld_replay,
	ld_replay_io,
	ld_m_v,
	ld_m_pd,
	ext_done,
	slow_busy,
	sq_commit,
	flush,
	br_kill,
	br_kill_tag,
	br_kill_sqtail,
	br_ok,
	br_ok_tag,
	clean_req,
	clean_done,
	io_req_v,
	io_req_rdy,
	io_addr,
	io_write,
	io_be,
	io_wdata,
	io_rsp_v,
	io_rdata,
	io_rsp_err,
	cmd_valid,
	cmd_ready,
	cmd_write,
	cmd_addr,
	cmd_len,
	w_valid,
	w_ready,
	w_data,
	w_be,
	w_last,
	r_valid,
	r_ready,
	r_data,
	r_error,
	r_last
);
	reg _sv2v_0;
	parameter integer SETS = 256;
	parameter [31:0] RAM_BASE = 32'h80000000;
	parameter integer RAM_BYTES = 131072;
	input wire clk;
	input wire rst;
	input wire [1:0] sq_alloc;
	output wire [3:0] sq_tail;
	output wire [3:0] sq_count;
	output wire [7:0] sq_valid;
	output wire [7:0] sq_issued;
	output wire [7:0] sq_free;
	output reg [1:0] sq_room;
	output reg spec_ok;
	output reg [31:0] md_viol;
	output wire perf_ld_acc;
	output wire perf_ld_miss;
	output wire sq_empty;
	input wire ex_v;
	input wire ex_store;
	input wire [2:0] ex_op;
	input wire [31:0] ex_base;
	input wire [31:0] ex_base_t;
	input wire [31:0] ex_base_t1;
	input wire [31:0] ex_sdata;
	input wire [11:0] ex_imm;
	input wire [5:0] ex_pd;
	input wire [4:0] ex_rob;
	input wire [2:0] ex_sqidx;
	input wire [7:0] ex_sqm;
	input wire [7:0] ex_brm;
	input wire ex_head;
	input wire [2:0] ex_slot;
	output reg st_done_v;
	output reg [4:0] st_done_rob;
	output reg st_exc;
	output reg [3:0] st_cause;
	output reg [31:0] st_tval;
	output reg st_replay;
	output reg bus_err_v;
	output reg bus_err_wb;
	output reg [31:0] bus_err_addr;
	output reg ld_wb_v;
	output reg [5:0] ld_wb_pd;
	output reg [31:0] ld_wb_data;
	output reg ld_done_v;
	output reg [4:0] ld_done_rob;
	output reg ld_exc;
	output reg [3:0] ld_cause;
	output reg [31:0] ld_tval;
	output reg ld_replay;
	output reg ld_replay_io;
	output wire ld_m_v;
	output wire [5:0] ld_m_pd;
	output reg [7:0] ext_done;
	output wire slow_busy;
	input wire [1:0] sq_commit;
	input wire flush;
	input wire br_kill;
	input wire [2:0] br_kill_tag;
	input wire [3:0] br_kill_sqtail;
	input wire br_ok;
	input wire [2:0] br_ok_tag;
	input wire clean_req;
	output reg clean_done;
	output wire io_req_v;
	input wire io_req_rdy;
	output wire [31:0] io_addr;
	output wire io_write;
	output wire [3:0] io_be;
	output wire [31:0] io_wdata;
	input wire io_rsp_v;
	input wire [31:0] io_rdata;
	input wire io_rsp_err;
	output wire cmd_valid;
	input wire cmd_ready;
	output wire cmd_write;
	output wire [31:0] cmd_addr;
	output wire [7:0] cmd_len;
	output wire w_valid;
	input wire w_ready;
	output wire [31:0] w_data;
	output wire [3:0] w_be;
	output wire w_last;
	input wire r_valid;
	output wire r_ready;
	input wire [31:0] r_data;
	input wire r_error;
	input wire r_last;
	function automatic [7:0] oh_lo8;
		input [7:0] v;
		oh_lo8 = v & (~v + 8'd1);
	endfunction
	function automatic [7:0] rev8;
		input [7:0] v;
		rev8 = {v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]};
	endfunction
	function automatic [2:0] enc8;
		input [7:0] oh;
		enc8 = {((oh[4] | oh[5]) | oh[6]) | oh[7], ((oh[2] | oh[3]) | oh[6]) | oh[7], ((oh[1] | oh[3]) | oh[5]) | oh[7]};
	endfunction
	function automatic [7:0] oh_hi8;
		input [7:0] v;
		oh_hi8 = rev8(oh_lo8(rev8(v)));
	endfunction
	function automatic [2:0] pe_lo8;
		input [7:0] v;
		pe_lo8 = enc8(oh_lo8(v));
	endfunction
	function automatic [2:0] pe_hi8;
		input [7:0] v;
		pe_hi8 = enc8(oh_hi8(v));
	endfunction
	function automatic [3:0] popc8;
		input [7:0] v;
		popc8 = (((((({3'b000, v[0]} + {3'b000, v[1]}) + {3'b000, v[2]}) + {3'b000, v[3]}) + {3'b000, v[4]}) + {3'b000, v[5]}) + {3'b000, v[6]}) + {3'b000, v[7]};
	endfunction
	localparam integer SB = $clog2(SETS);
	localparam integer RAB = $clog2(RAM_BYTES);
	localparam integer TB = (RAB - 5) - SB;
	localparam integer WB = SB + 3;
	function automatic in_ram;
		input reg [31:0] a;
		in_ram = (a & ~(RAM_BYTES - 1)) == RAM_BASE;
	endfunction
	(* syn_ramstyle = "lut_ram" *) reg [TB - 1:0] tagL0 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg [TB - 1:0] tagL1 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg [TB - 1:0] tagS0 [0:SETS - 1];
	(* syn_ramstyle = "lut_ram" *) reg [TB - 1:0] tagS1 [0:SETS - 1];
	reg m_we_v0;
	reg m_we_v1;
	reg m_we_d0;
	reg m_we_d1;
	reg m_we_vt;
	reg m_wd_v0;
	reg m_wd_v1;
	reg m_wd_d0;
	reg m_wd_d1;
	reg m_wd_vt;
	reg [SB - 1:0] m_wa_v;
	reg [SB - 1:0] m_wa_d;
	reg [SB - 1:0] m_wa_vt;
	reg [(4 * SB) - 1:0] m_ra;
	wire [3:0] rv0;
	wire [3:0] rv1;
	wire [3:0] rd0;
	wire [3:0] rd1;
	wire [3:0] rvt;
	o2_bitram #(
		.DEPTH(SETS),
		.AW(SB),
		.NR(4)
	) mv0(
		.clk(clk),
		.we(m_we_v0),
		.wa(m_wa_v),
		.wd(m_wd_v0),
		.ra(m_ra),
		.rd(rv0)
	);
	o2_bitram #(
		.DEPTH(SETS),
		.AW(SB),
		.NR(4)
	) mv1(
		.clk(clk),
		.we(m_we_v1),
		.wa(m_wa_v),
		.wd(m_wd_v1),
		.ra(m_ra),
		.rd(rv1)
	);
	o2_bitram #(
		.DEPTH(SETS),
		.AW(SB),
		.NR(4)
	) md0(
		.clk(clk),
		.we(m_we_d0),
		.wa(m_wa_d),
		.wd(m_wd_d0),
		.ra(m_ra),
		.rd(rd0)
	);
	o2_bitram #(
		.DEPTH(SETS),
		.AW(SB),
		.NR(4)
	) md1(
		.clk(clk),
		.we(m_we_d1),
		.wa(m_wa_d),
		.wd(m_wd_d1),
		.ra(m_ra),
		.rd(rd1)
	);
	o2_bitram #(
		.DEPTH(SETS),
		.AW(SB),
		.NR(4)
	) mvt(
		.clk(clk),
		.we(m_we_vt),
		.wa(m_wa_vt),
		.wd(m_wd_vt),
		.ra(m_ra),
		.rd(rvt)
	);
	reg [SB:0] init_set;
	wire init_busy = !init_set[SB];
	reg [31:0] dat0 [0:(SETS * 8) - 1];
	reg [31:0] dat1 [0:(SETS * 8) - 1];
	wire [WB - 1:0] pa_addr;
	reg [31:0] qa0;
	reg [31:0] qa1;
	always @(posedge clk) begin
		qa0 <= dat0[pa_addr];
		qa1 <= dat1[pa_addr];
	end
	reg pb_we0;
	reg pb_we1;
	reg [WB - 1:0] pb_addr;
	reg [31:0] pb_wdata;
	reg [3:0] pb_be;
	reg [31:0] qb0;
	reg [31:0] qb1;
	always @(posedge clk) begin
		begin : sv2v_autoblock_1
			reg signed [31:0] b;
			for (b = 0; b < 4; b = b + 1)
				begin
					if (pb_we0 && pb_be[b])
						dat0[pb_addr][8 * b+:8] <= pb_wdata[8 * b+:8];
					if (pb_we1 && pb_be[b])
						dat1[pb_addr][8 * b+:8] <= pb_wdata[8 * b+:8];
				end
		end
		qb0 <= dat0[pb_addr];
		qb1 <= dat1[pb_addr];
	end
	reg tag_we0;
	reg tag_we1;
	reg [SB - 1:0] tag_wset;
	reg [TB - 1:0] tag_wdata;
	always @(posedge clk) begin
		if (tag_we0) begin
			tagL0[tag_wset] <= tag_wdata;
			tagS0[tag_wset] <= tag_wdata;
		end
		if (tag_we1) begin
			tagL1[tag_wset] <= tag_wdata;
			tagS1[tag_wset] <= tag_wdata;
		end
	end
	reg [7:0] sv;
	reg [7:0] sa;
	reg [7:0] scm;
	reg [31:0] s_addr [0:7];
	reg [31:0] s_data [0:7];
	reg [3:0] s_be [0:7];
	reg [7:0] s_io;
	reg [3:0] s_head;
	reg [3:0] s_tail;
	reg [3:0] s_cmt;
	assign sq_tail = s_tail;
	assign sq_count = s_tail - s_head;
	assign sq_valid = sv;
	assign sq_issued = sa;
	assign sq_empty = sq_count == 4'd0;
	wire [3:0] sq_cnt_n = (s_tail + {2'b00, sq_alloc}) - s_head;
	always @(posedge clk)
		if (rst)
			sq_room <= 2'b11;
		else
			sq_room <= {sq_cnt_n <= 4'd6, sq_cnt_n <= 4'd7};
	localparam [2:0] R_IDLE = 3'd0;
	localparam [2:0] R_WBCMD = 3'd1;
	localparam [2:0] R_WBDATA = 3'd2;
	localparam [2:0] R_WBACK = 3'd3;
	localparam [2:0] R_FCMD = 3'd4;
	localparam [2:0] R_FDATA = 3'd5;
	localparam [2:0] R_CLEAN = 3'd6;
	reg [2:0] rstate;
	reg [31:0] r_line;
	reg r_way;
	reg [3:0] r_beat;
	reg [31:0] r_wbaddr;
	reg r_fill_req;
	reg [31:0] r_fill_addr;
	reg r_clean_mode;
	reg [SB:0] r_cset;
	reg r_cway;
	reg r_ferr;
	wire rbusy = (rstate != R_IDLE) || !init_set[SB];
	reg fe_v;
	reg [RAB - 6:0] fe_line;
	wire [31:0] ex_addr = ex_base + {{20 {ex_imm[11]}}, ex_imm};
	wire [1:0] ex_sz = ex_op[1:0];
	wire ex_mis = ((ex_sz == 2'd1) && ex_addr[0]) || ((ex_sz == 2'd2) && (ex_addr[1:0] != 2'b00));
	wire ex_ram = in_ram(ex_addr);
	wire ex_io = !ex_addr[31];
	wire ex_acc = !ex_ram && !ex_io;
	wire ex_kill = flush || (br_kill && ex_brm[br_kill_tag]);
	wire [WB + 1:0] ex_lidx = ex_base[WB + 1:0] + {{WB - 10 {ex_imm[11]}}, ex_imm};
	wire [SB - 1:0] ex_set = ex_lidx[5+:SB];
	wire [TB - 1:0] ex_tag = ex_addr[5 + SB+:TB];
	wire [3:0] ex_lbe = (ex_sz == 2'd0 ? 4'b0001 << ex_addr[1:0] : (ex_sz == 2'd1 ? 4'b0011 << ex_addr[1:0] : 4'b1111));
	wire ex_st = (ex_v && ex_store) && !ex_kill;
	wire ex_ld = ((ex_v && !ex_store) && !ex_kill) && !ex_head;
	wire ex_slow = (ex_v && !ex_kill) && ex_head;
	reg [7:0] e_vm;
	reg [7:0] e_cov;
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_2
			reg signed [31:0] i;
			for (i = 0; i < 8; i = i + 1)
				begin
					e_vm[i] = (((ex_sqm[i] && sv[i]) && sa[i]) && (s_addr[i][31:2] == ex_addr[31:2])) && |(s_be[i] & ex_lbe);
					e_cov[i] = (s_be[i] & ex_lbe) == ex_lbe;
				end
		end
	end
	// R69b: tag index/tag from a private copy of the base operand (ex_base_t ==
	// ex_base every cycle); [5+:SB] == ex_set and [5+SB+:TB] == ex_tag.
	// R70: one tag adder per way (ex_base_t1 == ex_base_t == ex_base every cycle).
	wire [RAB - 1:0] ex_tsum0 = ex_base_t[RAB - 1:0] + {{RAB - 12 {ex_imm[11]}}, ex_imm};
	wire [RAB - 1:0] ex_tsum1 = ex_base_t1[RAB - 1:0] + {{RAB - 12 {ex_imm[11]}}, ex_imm};
	reg m_v;
	reg m_hit0;
	reg m_hit1;
	reg m_exc;
	reg m_replay;
	reg m_sign;
	reg m_io;
	reg [3:0] m_cause;
	reg [31:0] m_addr;
	reg [1:0] m_sz;
	reg [3:0] m_lbe;
	reg [5:0] m_pd;
	reg [4:0] m_rob;
	reg [7:0] m_sqm;
	reg [2:0] m_sqpos;
	reg [7:0] m_brm;
	reg [7:0] m_vm;
	reg [7:0] m_cov;
	always @(posedge clk) begin
		if (rst)
			m_v <= 1'b0;
		else
			m_v <= ex_ld;
		m_hit0 <= rv0[0] && (tagL0[ex_tsum0[5+:SB]] == ex_tsum0[5 + SB+:TB]);
		m_hit1 <= rv1[0] && (tagL1[ex_tsum1[5+:SB]] == ex_tsum1[5 + SB+:TB]);
		m_exc <= ex_mis || ex_acc;
		m_cause <= (ex_mis ? 4'd4 : 4'd5);
		m_replay <= ex_io || rbusy;
		m_io <= ex_io;
		m_addr <= ex_addr;
		m_sz <= ex_sz;
		m_sign <= !ex_op[2];
		m_lbe <= ex_lbe;
		m_pd <= ex_pd;
		m_rob <= ex_rob;
		m_sqm <= ex_sqm & ~sq_free;
		m_sqpos <= ex_sqidx;
		m_brm <= (br_ok ? ex_brm & ~(8'b00000001 << br_ok_tag) : ex_brm);
		m_vm <= e_vm & ~sq_free;
		m_cov <= e_cov;
	end
	localparam [2:0] L_LOOK = 3'd4;
	reg [31:0] l_addr;
	reg [2:0] lstate;
	assign pa_addr = (lstate == L_LOOK ? l_addr[2+:WB] : ex_lidx[2+:WB]);
	wire m_kill = flush || (br_kill && m_brm[br_kill_tag]);
	wire m_ferr = fe_v && (m_addr[RAB - 1:5] == fe_line);
	reg fwd_any;
	reg fwd_hit;
	reg fwd_partial;
	reg [31:0] fwd_data;
	always @(*) begin
		if (_sv2v_0)
			;
		fwd_data = 32'b00000000000000000000000000000000;
		begin : sv2v_autoblock_3
			reg signed [31:0] e;
			for (e = 0; e < 8; e = e + 1)
				fwd_data = fwd_data | ({32 {m_vm[e]}} & s_data[e]);
		end
		fwd_any = |m_vm;
		fwd_hit = |(m_vm & m_cov);
		fwd_partial = |(m_vm & ~m_cov) || ((m_vm & (m_vm - 8'd1)) != 8'b00000000);
	end
	reg [7:0] lq_v;
	reg [4:0] lq_rob [0:7];
	reg [29:0] lq_addr [0:7];
	reg [3:0] lq_be [0:7];
	reg [7:0] lq_sqm [0:7];
	reg [7:0] lq_brm [0:7];
	wire m_spec = |(m_sqm & ~sa);
	wire [7:0] lq_free = ~lq_v;
	wire [7:0] lq_aoh = lq_free & (~lq_free + 8'd1);
	wire m_live = m_v && !m_kill;
	wire m_hit = m_hit0 || m_hit1;
	wire m_ok = (((!m_exc && !m_replay) && !fwd_partial) && (fwd_hit || m_hit)) && !(m_spec && (lq_v == 8'hff));
	wire lq_alloc = ((m_live && m_spec) && !m_exc) && m_ok;
	reg [7:0] lq_hit;
	reg m_hit_st;
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_4
			reg signed [31:0] i;
			for (i = 0; i < 8; i = i + 1)
				lq_hit[i] = (((ex_st && lq_v[i]) && lq_sqm[i][ex_sqidx]) && (lq_addr[i] == ex_addr[31:2])) && |(lq_be[i] & ex_lbe);
		end
		m_hit_st = ((((ex_st && m_v) && !m_kill) && m_sqm[ex_sqidx]) && (m_addr[31:2] == ex_addr[31:2])) && |(m_lbe & ex_lbe);
	end
	always @(posedge clk)
		if (rst) begin
			lq_v <= 8'b00000000;
			md_viol <= 32'b00000000000000000000000000000000;
			spec_ok <= 1'b1;
		end
		else begin : sv2v_autoblock_5
			reg [31:0] vm;
			vm = 32'b00000000000000000000000000000000;
			begin : sv2v_autoblock_6
				reg signed [31:0] i;
				for (i = 0; i < 8; i = i + 1)
					if (lq_hit[i])
						vm[lq_rob[i]] = 1'b1;
			end
			if (m_hit_st)
				vm[m_rob] = 1'b1;
			md_viol <= (flush ? 32'b00000000000000000000000000000000 : vm);
			begin : sv2v_autoblock_7
				reg signed [31:0] i;
				for (i = 0; i < 8; i = i + 1)
					begin : sv2v_autoblock_8
						reg [7:0] nsq;
						nsq = lq_sqm[i] & ~sq_free;
						lq_sqm[i] <= nsq;
						if (br_ok)
							lq_brm[i][br_ok_tag] <= 1'b0;
						if ((flush || (br_kill && lq_brm[i][br_kill_tag])) || ((nsq & ~sa) == 8'b00000000))
							lq_v[i] <= 1'b0;
						if (((lq_alloc && lq_aoh[i]) && !flush) && !(br_kill && m_brm[br_kill_tag])) begin
							lq_v[i] <= 1'b1;
							lq_rob[i] <= m_rob;
							lq_addr[i] <= m_addr[31:2];
							lq_be[i] <= m_lbe;
							lq_sqm[i] <= m_sqm & ~sq_free;
							lq_brm[i] <= (br_ok ? m_brm & ~(8'b00000001 << br_ok_tag) : m_brm);
						end
					end
			end
			spec_ok <= popc8(lq_free) >= 4'd4;
		end
	wire [31:0] m_word = (fwd_any ? fwd_data : (m_hit1 ? qa1 : qa0));
	wire [31:0] m_shift = m_word >> {m_addr[1:0], 3'b000};
	wire [31:0] m_val = (m_sz == 2'd0 ? {{24 {m_sign && m_shift[7]}}, m_shift[7:0]} : (m_sz == 2'd1 ? {{16 {m_sign && m_shift[15]}}, m_shift[15:0]} : m_shift));
	reg m_miss_q;
	reg [31:0] m_miss_addr_q;
	always @(posedge clk) begin
		m_miss_q <= ((((!rst && m_v) && !m_kill) && !m_exc) && !m_replay) && !m_hit;
		m_miss_addr_q <= m_addr;
	end
	wire m_miss_req = m_miss_q && !flush;
	assign ld_m_v = m_v;
	assign ld_m_pd = m_pd;
	assign perf_ld_acc = m_live && !m_io;
	assign perf_ld_miss = m_miss_q;
	localparam [2:0] L_IDLE = 3'd0;
	localparam [2:0] L_WAIT = 3'd1;
	localparam [2:0] L_IOREQ = 3'd2;
	localparam [2:0] L_IORSP = 3'd3;
	localparam [2:0] L_CHK = 3'd5;
	localparam [2:0] L_DONE = 3'd6;
	reg [1:0] l_sz;
	reg l_sign;
	reg [5:0] l_pd;
	reg [4:0] l_rob;
	reg [2:0] l_slot;
	reg l_exc;
	reg [3:0] l_cause;
	reg [31:0] l_data;
	reg l_store;
	reg [2:0] l_sq;
	reg l_hit0;
	reg l_hit1;
	assign slow_busy = lstate != L_IDLE;
	wire l_ram = in_ram(l_addr);
	wire [31:0] l_shift = l_data >> {l_addr[1:0], 3'b000};
	wire [31:0] l_val = (l_sz == 2'd0 ? {{24 {l_sign && l_shift[7]}}, l_shift[7:0]} : (l_sz == 2'd1 ? {{16 {l_sign && l_shift[15]}}, l_shift[15:0]} : l_shift));
	reg d1_v;
	reg d1_hit0;
	reg d1_hit1;
	reg d1_ferr;
	reg [2:0] d1_idx;
	wire [2:0] sh = s_head[2:0];
	reg [2:0] dptr;
	wire drain_cand = (sv[dptr] && scm[dptr]) && !s_io[dptr];
	wire [SB - 1:0] dset = s_addr[dptr][5+:SB];
	wire [TB - 1:0] dtag = s_addr[dptr][5 + SB+:TB];
	reg d_free_pend;
	reg [2:0] d_free_idx;
	assign sq_free = (d_free_pend ? 8'b00000001 << d_free_idx : 8'b00000000);
	wire drain_go = (((drain_cand && ((!d1_v || d1_hit0) || d1_hit1)) && !rbusy) && !r_fill_req) && ((lstate == L_IDLE) || (lstate == L_WAIT));
	wire io_skip = ((((sv[sh] && scm[sh]) && s_io[sh]) && (dptr == sh)) && !d1_v) && !d_free_pend;
	wire [SB - 1:0] fs_set = r_fill_addr[5+:SB];
	wire [SB - 1:0] rl_set = r_line[5+:SB];
	wire [SB - 1:0] d1_set = s_addr[d1_idx][5+:SB];
	wire refill_start = ((((rstate == R_IDLE) && !(clean_req && !r_clean_mode)) && r_fill_req) && !d1_v) && !((rv0[2] && (tagS0[fs_set] == r_fill_addr[5 + SB+:TB])) || (rv1[2] && (tagS1[fs_set] == r_fill_addr[5 + SB+:TB])));
	wire refill_way = (!rv0[2] ? 1'b0 : (!rv1[2] ? 1'b1 : rvt[2]));
	wire fill_last = ((rstate == R_FDATA) && r_valid) && (r_beat == 4'd7);
	wire fill_ok = !r_ferr && !r_error;
	always @(*) begin
		if (_sv2v_0)
			;
		m_ra = {l_addr[5+:SB], (rstate == R_CLEAN ? r_cset[SB - 1:0] : fs_set), dset, ex_set};
		m_we_v0 = 1'b0;
		m_we_v1 = 1'b0;
		m_wd_v0 = 1'b0;
		m_wd_v1 = 1'b0;
		m_wa_v = fs_set;
		if (init_busy) begin
			m_we_v0 = 1'b1;
			m_we_v1 = 1'b1;
			m_wa_v = init_set[SB - 1:0];
		end
		else if (fill_last) begin
			m_wa_v = rl_set;
			m_we_v0 = !r_way;
			m_we_v1 = r_way;
			m_wd_v0 = fill_ok;
			m_wd_v1 = fill_ok;
		end
		else if (refill_start) begin
			m_wa_v = fs_set;
			m_we_v0 = !refill_way;
			m_we_v1 = refill_way;
		end
		m_we_d0 = 1'b0;
		m_we_d1 = 1'b0;
		m_wd_d0 = 1'b0;
		m_wd_d1 = 1'b0;
		m_wa_d = rl_set;
		if (init_busy) begin
			m_we_d0 = 1'b1;
			m_we_d1 = 1'b1;
			m_wa_d = init_set[SB - 1:0];
		end
		else if (fill_last || ((rstate == R_WBACK) && r_valid)) begin
			m_wa_d = rl_set;
			m_we_d0 = !r_way;
			m_we_d1 = r_way;
		end
		else if (d1_v && (d1_hit0 || d1_hit1)) begin
			m_wa_d = d1_set;
			m_we_d0 = d1_hit0;
			m_we_d1 = d1_hit1;
			m_wd_d0 = 1'b1;
			m_wd_d1 = 1'b1;
		end
		m_we_vt = init_busy || fill_last;
		m_wa_vt = (init_busy ? init_set[SB - 1:0] : rl_set);
		m_wd_vt = (init_busy ? 1'b0 : !r_way);
	end
	always @(*) begin
		if (_sv2v_0)
			;
		st_done_v = ex_st && !ex_head;
		st_done_rob = ex_rob;
		st_exc = ex_mis || ex_acc;
		st_cause = (ex_mis ? 4'd6 : 4'd7);
		st_tval = ex_addr;
		st_replay = ex_io && !ex_mis;
		ld_done_v = 1'b0;
		ld_done_rob = m_rob;
		ld_exc = 1'b0;
		ld_cause = m_cause;
		ld_tval = m_addr;
		ld_replay = 1'b0;
		ld_wb_v = 1'b0;
		ld_wb_pd = m_pd;
		ld_wb_data = m_val;
		ld_replay_io = m_io || m_ferr;
		ext_done = 8'b00000000;
		if (m_live) begin
			ld_done_v = 1'b1;
			ld_exc = m_exc;
			ld_replay = !m_exc && !m_ok;
			ld_wb_v = 1'b1;
		end
		else if ((lstate == L_DONE) && !m_live) begin
			ld_done_v = 1'b1;
			ld_done_rob = l_rob;
			ld_exc = l_exc;
			ld_cause = l_cause;
			ld_tval = l_addr;
			ld_wb_v = !l_exc && !l_store;
			ld_wb_pd = l_pd;
			ld_wb_data = l_val;
			ext_done[l_slot] = 1'b1;
		end
	end
	assign io_req_v = lstate == L_IOREQ;
	assign io_addr = {l_addr[31:2], 2'b00};
	assign io_write = l_store;
	assign io_be = (l_store ? s_be[l_sq] : 4'hf);
	assign io_wdata = s_data[l_sq];
	always @(*) begin
		if (_sv2v_0)
			;
		pb_we0 = 1'b0;
		pb_we1 = 1'b0;
		pb_addr = {s_addr[d1_idx][5+:SB], s_addr[d1_idx][4:2]};
		pb_wdata = s_data[d1_idx];
		pb_be = s_be[d1_idx];
		tag_we0 = 1'b0;
		tag_we1 = 1'b0;
		tag_wset = r_line[5+:SB];
		tag_wdata = r_line[5 + SB+:TB];
		if (rstate == R_FDATA) begin
			pb_addr = {r_line[5+:SB], r_beat[2:0]};
			pb_wdata = r_data;
			pb_be = 4'hf;
			pb_we0 = r_valid && !r_way;
			pb_we1 = r_valid && r_way;
			if (r_valid && (r_beat == 4'd7)) begin
				tag_we0 = !r_way;
				tag_we1 = r_way;
			end
		end
		else if (rstate == R_WBCMD)
			pb_addr = {r_line[5+:SB], 3'd0};
		else if (rstate == R_WBDATA)
			pb_addr = {r_line[5+:SB], (w_ready ? r_beat[2:0] : r_beat[2:0] - 3'd1)};
		else if (rstate == R_CLEAN)
			pb_addr = {r_cset[SB - 1:0], 3'b000};
		else if (d1_v && (d1_hit0 || d1_hit1)) begin
			pb_we0 = d1_hit0;
			pb_we1 = d1_hit1;
		end
	end
	assign cmd_valid = (rstate == R_WBCMD) || (rstate == R_FCMD);
	assign cmd_write = rstate == R_WBCMD;
	assign cmd_addr = (rstate == R_WBCMD ? r_wbaddr : {r_line[31:5], 5'b00000});
	assign cmd_len = 8'd8;
	assign w_valid = rstate == R_WBDATA;
	assign w_data = (r_way ? qb1 : qb0);
	assign w_be = 4'hf;
	assign w_last = r_beat == 4'd8;
	assign r_ready = (rstate == R_FDATA) || (rstate == R_WBACK);
	wire [3:0] kill_tail = br_kill_sqtail;
	function automatic signed [2:0] sv2v_cast_3_signed;
		input reg signed [2:0] inp;
		sv2v_cast_3_signed = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			sv <= 8'b00000000;
			sa <= 8'b00000000;
			scm <= 8'b00000000;
			s_head <= 4'd0;
			s_tail <= 4'd0;
			s_cmt <= 4'd0;
			d1_v <= 1'b0;
			d_free_pend <= 1'b0;
			dptr <= 3'd0;
			rstate <= R_CLEAN;
			r_clean_mode <= 1'b0;
			r_cset <= 1'sb0;
			r_cway <= 1'b0;
			r_beat <= 4'd0;
			r_ferr <= 1'b0;
			fe_v <= 1'b0;
			bus_err_v <= 1'b0;
			lstate <= L_IDLE;
			init_set <= 1'sb0;
			r_fill_req <= 1'b0;
			clean_done <= 1'b0;
		end
		else begin
			clean_done <= 1'b0;
			bus_err_v <= 1'b0;
			if (init_busy)
				init_set <= init_set + 1'b1;
			begin : sv2v_autoblock_9
				reg [3:0] nt;
				reg [7:0] nv;
				nt = s_tail;
				nv = sv;
				if (flush) begin
					begin : sv2v_autoblock_10
						reg signed [31:0] i;
						for (i = 0; i < 8; i = i + 1)
							if (!scm[i])
								nv[i] = 1'b0;
					end
					nt = s_cmt;
				end
				else if (br_kill) begin
					begin : sv2v_autoblock_11
						reg signed [31:0] i;
						for (i = 0; i < 8; i = i + 1)
							begin : sv2v_autoblock_12
								reg [2:0] off;
								reg [3:0] cnt;
								off = sv2v_cast_3_signed(i) - kill_tail[2:0];
								cnt = s_tail - kill_tail;
								if (({1'b0, off} < cnt) && !scm[i])
									nv[i] = 1'b0;
							end
					end
					nt = kill_tail;
				end
				else if (sq_alloc != 2'd0) begin
					nv[s_tail[2:0]] = 1'b1;
					if (sq_alloc == 2'd2)
						nv[s_tail[2:0] + 3'd1] = 1'b1;
					nt = s_tail + {2'b00, sq_alloc};
				end
				if (d_free_pend)
					nv[d_free_idx] = 1'b0;
				sv <= nv;
				s_tail <= nt;
				begin : sv2v_autoblock_13
					reg signed [31:0] i;
					for (i = 0; i < 8; i = i + 1)
						if (!nv[i]) begin
							sa[i] <= 1'b0;
							scm[i] <= 1'b0;
						end
				end
			end
			if (d_free_pend) begin
				s_head <= s_head + 4'd1;
				d_free_pend <= 1'b0;
			end
			if (ex_st) begin
				sa[ex_sqidx] <= 1'b1;
				s_addr[ex_sqidx] <= ex_addr;
				s_data[ex_sqidx] <= ex_sdata << {ex_addr[1:0], 3'b000};
				s_be[ex_sqidx] <= ex_lbe;
				s_io[ex_sqidx] <= ex_io;
			end
			if (sq_commit != 2'd0) begin
				scm[s_cmt[2:0]] <= 1'b1;
				if (sq_commit == 2'd2)
					scm[s_cmt[2:0] + 3'd1] <= 1'b1;
				s_cmt <= s_cmt + {2'b00, sq_commit};
			end
			d1_v <= 1'b0;
			if (drain_go) begin
				d1_v <= 1'b1;
				d1_idx <= dptr;
				dptr <= dptr + 3'd1;
				d1_hit0 <= rv0[1] && (tagS0[dset] == dtag);
				d1_hit1 <= rv1[1] && (tagS1[dset] == dtag);
				d1_ferr <= fe_v && ({dtag, dset} == fe_line);
			end
			if (d1_v) begin
				if (d1_hit0 || d1_hit1) begin
					d_free_pend <= 1'b1;
					d_free_idx <= d1_idx;
				end
				else if (d1_ferr) begin
					d_free_pend <= 1'b1;
					d_free_idx <= d1_idx;
					fe_v <= 1'b0;
					bus_err_v <= 1'b1;
					bus_err_wb <= 1'b0;
					bus_err_addr <= s_addr[d1_idx];
				end
				else begin
					dptr <= d1_idx;
					if (!r_fill_req && !rbusy) begin
						r_fill_req <= 1'b1;
						r_fill_addr <= s_addr[d1_idx];
					end
				end
			end
			if (io_skip) begin
				d_free_pend <= 1'b1;
				d_free_idx <= sh;
				dptr <= sh + 3'd1;
			end
			if ((m_miss_req && !r_fill_req) && !rbusy) begin
				r_fill_req <= 1'b1;
				r_fill_addr <= m_miss_addr_q;
			end
			case (rstate)
				R_IDLE:
					if (clean_req && !r_clean_mode) begin
						rstate <= R_CLEAN;
						r_clean_mode <= 1'b1;
						r_cset <= 1'sb0;
						r_cway <= 1'b0;
					end
					else if (r_fill_req && !d1_v) begin : sv2v_autoblock_14
						reg [SB - 1:0] fs;
						reg w;
						fs = r_fill_addr[5+:SB];
						r_fill_req <= 1'b0;
						if (!((rv0[2] && (tagS0[fs] == r_fill_addr[5 + SB+:TB])) || (rv1[2] && (tagS1[fs] == r_fill_addr[5 + SB+:TB])))) begin
							w = (!rv0[2] ? 1'b0 : (!rv1[2] ? 1'b1 : rvt[2]));
							r_line <= {r_fill_addr[31:5], 5'b00000};
							r_way <= w;
							r_beat <= 4'd0;
							r_wbaddr <= {RAM_BASE[31:RAB], (w ? tagS1[fs] : tagS0[fs]), fs, 5'b00000};
							if ((w ? rv1[2] && rd1[2] : rv0[2] && rd0[2]))
								rstate <= R_WBCMD;
							else
								rstate <= R_FCMD;
						end
					end
				R_WBCMD:
					if (cmd_ready) begin
						rstate <= R_WBDATA;
						r_beat <= 4'd1;
					end
				R_WBDATA:
					if (w_ready) begin
						if (r_beat == 4'd8)
							rstate <= R_WBACK;
						r_beat <= r_beat + 4'd1;
					end
				R_WBACK:
					if (r_valid) begin
						if (r_error) begin
							bus_err_v <= 1'b1;
							bus_err_wb <= 1'b1;
							bus_err_addr <= r_wbaddr;
						end
						if (r_clean_mode)
							rstate <= R_CLEAN;
						else begin
							rstate <= R_FCMD;
							r_beat <= 4'd0;
						end
					end
				R_FCMD:
					if (cmd_ready) begin
						rstate <= R_FDATA;
						r_beat <= 4'd0;
						r_ferr <= 1'b0;
					end
				R_FDATA:
					if (r_valid) begin
						r_beat <= r_beat + 4'd1;
						r_ferr <= r_ferr || r_error;
						if (r_beat == 4'd7) begin
							rstate <= R_IDLE;
							if (!fill_ok) begin
								fe_v <= 1'b1;
								fe_line <= r_line[RAB - 1:5];
							end
							else if (r_line[RAB - 1:5] == fe_line)
								fe_v <= 1'b0;
						end
					end
				R_CLEAN: begin : sv2v_autoblock_15
					reg [SB - 1:0] cs;
					cs = r_cset[SB - 1:0];
					if (!r_clean_mode)
						rstate <= R_IDLE;
					else if (r_cset[SB]) begin
						rstate <= R_IDLE;
						r_clean_mode <= 1'b0;
						clean_done <= 1'b1;
					end
					else if ((r_cway ? rv1[2] && rd1[2] : rv0[2] && rd0[2])) begin
						r_way <= r_cway;
						r_line <= {RAM_BASE[31:RAB], (r_cway ? tagS1[cs] : tagS0[cs]), cs, 5'b00000};
						r_wbaddr <= {RAM_BASE[31:RAB], (r_cway ? tagS1[cs] : tagS0[cs]), cs, 5'b00000};
						r_beat <= 4'd0;
						rstate <= R_WBCMD;
						r_cway <= !r_cway;
						if (r_cway)
							r_cset <= r_cset + 1'b1;
					end
					else begin
						r_cway <= !r_cway;
						if (r_cway)
							r_cset <= r_cset + 1'b1;
					end
				end
				default: rstate <= R_IDLE;
			endcase
			if (((((fill_last && !fill_ok) && (lstate == L_WAIT)) && !l_store) && l_ram) && (r_line[RAB - 1:5] == l_addr[RAB - 1:5])) begin
				l_exc <= 1'b1;
				l_cause <= 4'd5;
			end
			case (lstate)
				L_IDLE:
					if (ex_slow) begin
						lstate <= L_WAIT;
						l_addr <= ex_addr;
						l_sz <= ex_sz;
						l_sign <= !ex_op[2];
						l_pd <= ex_pd;
						l_rob <= ex_rob;
						l_slot <= ex_slot;
						l_store <= ex_store;
						l_sq <= ex_sqidx;
						l_exc <= ex_mis || ex_acc;
						l_cause <= (ex_store ? (ex_mis ? 4'd6 : 4'd7) : (ex_mis ? 4'd4 : 4'd5));
					end
				L_WAIT:
					if (l_exc || (l_store && l_ram))
						lstate <= L_DONE;
					else if ((((((sv & scm) == 8'b00000000) && !rbusy) && !d1_v) && !d_free_pend) && !r_fill_req)
						lstate <= (l_ram ? L_LOOK : L_IOREQ);
				L_IOREQ:
					if (io_req_rdy)
						lstate <= L_IORSP;
				L_IORSP:
					if (io_rsp_v) begin
						l_data <= io_rdata;
						l_exc <= io_rsp_err;
						l_cause <= (l_store ? 4'd7 : 4'd5);
						lstate <= L_DONE;
					end
				L_LOOK: begin
					l_hit0 <= rv0[3] && (tagL0[l_addr[5+:SB]] == l_addr[5 + SB+:TB]);
					l_hit1 <= rv1[3] && (tagL1[l_addr[5+:SB]] == l_addr[5 + SB+:TB]);
					lstate <= L_CHK;
				end
				L_CHK:
					if (l_hit0 || l_hit1) begin
						l_data <= (l_hit1 ? qa1 : qa0);
						lstate <= L_DONE;
					end
					else begin
						if (!r_fill_req && !rbusy) begin
							r_fill_req <= 1'b1;
							r_fill_addr <= l_addr;
						end
						lstate <= L_WAIT;
					end
				L_DONE:
					if (!m_live)
						lstate <= L_IDLE;
				default: lstate <= L_IDLE;
			endcase
			if ((flush && (lstate != L_IORSP)) && (lstate != L_IOREQ))
				lstate <= L_IDLE;
		end
	initial _sv2v_0 = 0;
endmodule
module o2_rob (
	clk,
	rst,
	dv,
	e0,
	e1,
	tail,
	count,
	room,
	empty,
	head_idx,
	c0_v,
	c0_rob,
	c5_v,
	c5_rob,
	c5_exc,
	c5_tval,
	c5_taken,
	c1_v,
	c1_rob,
	c2_v,
	c2_rob,
	c3_v,
	c3_rob,
	c3_exc,
	c3_cause,
	c3_tval,
	c3_replay,
	c4_v,
	c4_rob,
	c4_exc,
	c4_cause,
	c4_tval,
	c4_replay,
	c4_replay_io,
	br_kill,
	br_kill_rob,
	cm_wr,
	cm_rd0,
	cm_rd1,
	cm_pdst0,
	cm_pdst1,
	cm_pold0,
	cm_pold1,
	sq_commit,
	cmt_br_valid,
	cmt_is_cbr,
	cmt_taken,
	cmt_pc,
	cmt_biq,
	flush,
	flush_pc,
	replay_set,
	replay_pc,
	md_set,
	md_viol,
	fetch_stop,
	csr_rs1_preg,
	csr_rs1_preg_n,
	csr_rs1_bank,
	csr_rd_a,
	csr_rd_b,
	csr_rs1_value,
	csr_wb_v,
	csr_wb_pd,
	csr_wb_data,
	irq_software,
	irq_timer,
	irq_external,
	sq_empty,
	slow_busy,
	dc_clean_req,
	dc_clean_done,
	ic_inv,
	ic_busy,
	tr_v,
	tr_pc0,
	tr_pc1,
	tr_insn0,
	tr_insn1,
	tr_wr0,
	tr_wr1,
	tr_rd0,
	tr_rd1,
	tr_pd0,
	tr_pd1,
	tr_trap,
	tr_irq,
	tr_cause,
	tr_epc,
	tr_csr_old,
	minstret_o,
	mcycle_o
);
	reg _sv2v_0;
	parameter [31:0] RESET_PC = 32'h80000000;
	input wire clk;
	input wire rst;
	input wire [1:0] dv;
	input wire [127:0] e0;
	input wire [127:0] e1;
	output reg [5:0] tail;
	output wire [5:0] count;
	output reg [1:0] room;
	output reg empty;
	output wire [4:0] head_idx;
	input wire c0_v;
	input wire [4:0] c0_rob;
	input wire c5_v;
	input wire [4:0] c5_rob;
	input wire c5_exc;
	input wire [31:0] c5_tval;
	input wire c5_taken;
	input wire c1_v;
	input wire [4:0] c1_rob;
	input wire c2_v;
	input wire [4:0] c2_rob;
	input wire c3_v;
	input wire [4:0] c3_rob;
	input wire c3_exc;
	input wire [3:0] c3_cause;
	input wire [31:0] c3_tval;
	input wire c3_replay;
	input wire c4_v;
	input wire [4:0] c4_rob;
	input wire c4_exc;
	input wire [3:0] c4_cause;
	input wire [31:0] c4_tval;
	input wire c4_replay;
	input wire c4_replay_io;
	input wire br_kill;
	input wire [4:0] br_kill_rob;
	output reg [1:0] cm_wr;
	output reg [4:0] cm_rd0;
	output reg [4:0] cm_rd1;
	output reg [5:0] cm_pdst0;
	output reg [5:0] cm_pdst1;
	output reg [5:0] cm_pold0;
	output reg [5:0] cm_pold1;
	output reg [1:0] sq_commit;
	output reg cmt_br_valid;
	output reg cmt_is_cbr;
	output reg cmt_taken;
	output reg [31:0] cmt_pc;
	output reg [3:0] cmt_biq;
	output wire flush;
	output wire [31:0] flush_pc;
	output reg replay_set;
	output reg [31:0] replay_pc;
	output reg md_set;
	input wire [31:0] md_viol;
	output wire fetch_stop;
	output wire [5:0] csr_rs1_preg;
	output wire [5:0] csr_rs1_preg_n;
	output wire [1:0] csr_rs1_bank;
	output wire csr_rd_a;
	output wire csr_rd_b;
	input wire [31:0] csr_rs1_value;
	output reg csr_wb_v;
	output reg [5:0] csr_wb_pd;
	output reg [31:0] csr_wb_data;
	input wire irq_software;
	input wire irq_timer;
	input wire irq_external;
	input wire sq_empty;
	input wire slow_busy;
	output wire dc_clean_req;
	input wire dc_clean_done;
	output wire ic_inv;
	input wire ic_busy;
	output reg [1:0] tr_v;
	output reg [31:0] tr_pc0;
	output reg [31:0] tr_pc1;
	output reg [31:0] tr_insn0;
	output reg [31:0] tr_insn1;
	output reg tr_wr0;
	output reg tr_wr1;
	output reg [4:0] tr_rd0;
	output reg [4:0] tr_rd1;
	output reg [5:0] tr_pd0;
	output reg [5:0] tr_pd1;
	output reg tr_trap;
	output reg tr_irq;
	output reg [31:0] tr_cause;
	output reg [31:0] tr_epc;
	output reg [31:0] tr_csr_old;
	output wire [63:0] minstret_o;
	output wire [63:0] mcycle_o;
	(* syn_ramstyle = "lut_ram" *) reg [61:0] pa0 [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [61:0] pa1 [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [46:0] pb0 [0:15];
	(* syn_ramstyle = "lut_ram" *) reg [46:0] pb1 [0:15];
	reg [31:0] done;
	reg [31:0] exc;
	reg [31:0] rpl;
	reg [31:0] rpl_io;
	reg [31:0] rpl_md;
	reg [31:0] tkn;
	reg xv;
	reg [4:0] xrob;
	reg [3:0] xcause;
	reg [31:0] xtval;
	reg e0_v;
	reg e3_v;
	reg e3_exc;
	reg e4_v;
	reg e4_exc;
	reg e4_rio;
	reg [4:0] e0_rob;
	reg [4:0] e3_rob;
	reg [4:0] e4_rob;
	reg [3:0] e3_cause;
	reg [3:0] e4_cause;
	reg [31:0] e0_tval;
	reg [31:0] e3_tval;
	reg [31:0] e4_tval;
	reg [5:0] head;
	wire [5:0] t0 = tail;
	wire [5:0] t1 = tail + 6'd1;
	function automatic [61:0] fa;
		input [127:0] e;
		fa = {e[127:98], e[95:64]};
	endfunction
	function automatic [46:0] fb;
		input [127:0] e;
		fb = e[63:17];
	endfunction
	wire w0_e = !t0[0];
	wire we_even = (dv[0] && w0_e) || (dv[1] && !w0_e);
	wire we_odd = (dv[0] && !w0_e) || (dv[1] && w0_e);
	wire [3:0] wa_even = (w0_e ? t0[4:1] : t1[4:1]);
	wire [3:0] wa_odd = (w0_e ? t1[4:1] : t0[4:1]);
	wire [127:0] wd_even = (w0_e ? e0 : e1);
	wire [127:0] wd_odd = (w0_e ? e1 : e0);
	always @(posedge clk) begin
		if (we_even) begin
			pa0[wa_even] <= fa(wd_even);
			pb0[wa_even] <= fb(wd_even);
		end
		if (we_odd) begin
			pa1[wa_odd] <= fa(wd_odd);
			pb1[wa_odd] <= fb(wd_odd);
		end
	end
	wire [5:0] h0 = head;
	wire [5:0] h1 = head + 6'd1;
	wire [61:0] ra0 = (h0[0] ? pa1[h0[4:1]] : pa0[h0[4:1]]);
	wire [46:0] rb0 = (h0[0] ? pb1[h0[4:1]] : pb0[h0[4:1]]);
	wire [61:0] ra1 = (h1[0] ? pa1[h1[4:1]] : pa0[h1[4:1]]);
	wire [46:0] rb1 = (h1[0] ? pb1[h1[4:1]] : pb0[h1[4:1]]);
	wire [31:0] pc0 = {ra0[61:32], 2'b00};
	wire [31:0] insn0 = ra0[31:0];
	wire [31:0] pc1 = {ra1[61:32], 2'b00};
	wire [31:0] insn1 = ra1[31:0];
	wire [4:0] rd0 = rb0[46:42];
	wire [4:0] rd1 = rb1[46:42];
	wire wr0 = rb0[41];
	wire wr1 = rb1[41];
	wire [5:0] pd0 = rb0[40:35];
	wire [5:0] po0 = rb0[34:29];
	wire [5:0] pd1 = rb1[40:35];
	wire [5:0] po1 = rb1[34:29];
	wire [2:0] fu0 = rb0[28:26];
	wire [2:0] fu1 = rb1[28:26];
	wire [3:0] op0 = rb0[25:22];
	wire [3:0] dca0 = rb0[21:18];
	wire [3:0] biq0 = rb0[14:11];
	wire [3:0] biq1 = rb1[14:11];
	wire st0 = fu0 == 3'd3;
	wire st1 = fu1 == 3'd3;
	wire br0 = fu0 == 3'd1;
	wire br1 = fu1 == 3'd1;
	wire cbr0 = br0 && (insn0[6:0] == 7'h63);
	wire cbr1 = br1 && (insn1[6:0] == 7'h63);
	reg [5:0] csr_preg_q;
	reg [1:0] csr_bank_q;
	assign csr_rs1_preg = csr_preg_q;
	assign csr_rs1_preg_n = rb0[7:2];
	reg [1:0] csr_bank_q2;
	assign csr_rs1_bank = csr_bank_q2;
	reg csr_arm1;
	assign csr_rd_a = csr_arm1;
	reg csr_arm2;
	assign csr_rd_b = csr_arm2;
	function automatic [4:0] age;
		input [4:0] r;
		age = r - head[4:0];
	endfunction
	function automatic older;
		input [4:0] a;
		input [4:0] b;
		reg ah;
		reg bh;
		begin
			ah = a >= head[4:0];
			bh = b >= head[4:0];
			older = (ah == bh ? a < b : ah);
		end
	endfunction
	assign count = tail - head;
	wire [5:0] cnt_n = ((tail + {5'b00000, dv[0]}) + {5'b00000, dv[1]}) - head;
	always @(posedge clk)
		if (rst)
			room <= 2'b11;
		else
			room <= {cnt_n <= 6'd30, cnt_n <= 6'd31};
	reg flush_q;
	always @(posedge clk)
		if (rst)
			empty <= 1'b1;
		else
			empty <= (cnt_n == 6'd0) && !flush_q;
	assign head_idx = head[4:0];
	reg [31:0] mstatus;
	reg [31:0] mie;
	reg [31:0] mtvec;
	reg [31:0] mscratch;
	reg [31:0] mepc;
	reg [31:0] mcause;
	reg [31:0] mtval;
	reg [63:0] mcycle;
	reg [63:0] minstret;
	wire [31:0] mip = {20'b00000000000000000000, irq_external, 3'b000, irq_timer, 3'b000, irq_software, 3'b000};
	assign minstret_o = minstret;
	assign mcycle_o = mcycle;
	function automatic csr_known;
		input [11:0] a;
		case (a)
			12'h300, 12'h301, 12'h304, 12'h305, 12'h340, 12'h341, 12'h342, 12'h343, 12'h344, 12'hb00, 12'hb80, 12'hb02, 12'hb82, 12'hc00, 12'hc80, 12'hc02, 12'hc82, 12'hf11, 12'hf12, 12'hf13, 12'hf14: csr_known = 1'b1;
			default: csr_known = 1'b0;
		endcase
	endfunction
	reg [31:0] csr_old;
	always @(*) begin
		if (_sv2v_0)
			;
		case (insn0[31:20])
			12'h300: csr_old = mstatus;
			12'h301: csr_old = 32'h40000100;
			12'h304: csr_old = mie;
			12'h305: csr_old = mtvec;
			12'h340: csr_old = mscratch;
			12'h341: csr_old = mepc;
			12'h342: csr_old = mcause;
			12'h343: csr_old = mtval;
			12'h344: csr_old = mip;
			12'hb00, 12'hc00: csr_old = mcycle[31:0];
			12'hb80, 12'hc80: csr_old = mcycle[63:32];
			12'hb02, 12'hc02: csr_old = minstret[31:0];
			12'hb82, 12'hc82: csr_old = minstret[63:32];
			default: csr_old = 32'b00000000000000000000000000000000;
		endcase
	end
	wire [2:0] cf3 = insn0[14:12];
	reg [31:0] csr_rs1_q;
	reg csr_arm;
	wire csr_wr_en = (cf3[1:0] == 2'b01) || (insn0[19:15] != 5'd0);
	wire csr_illegal = !csr_known(insn0[31:20]) || (csr_wr_en && (insn0[31:30] == 2'b11));
	reg [31:0] csr_old_q;
	reg csr_ill_q;
	reg csr_wen_q;
	reg [2:0] csr_f3_q;
	reg [4:0] csr_zimm_q;
	reg [6:0] csr_wsel_q;
	reg [3:0] csr_counter_wsel_q;
	reg minstret_write_q;
	always @(posedge clk) begin
		csr_old_q <= csr_old;
		csr_ill_q <= csr_illegal;
		csr_wen_q <= csr_wr_en;
		csr_f3_q <= cf3;
		csr_zimm_q <= insn0[19:15];
		csr_wsel_q <= {insn0[31:20] == 12'h343, insn0[31:20] == 12'h342, insn0[31:20] == 12'h341, insn0[31:20] == 12'h340, insn0[31:20] == 12'h305, insn0[31:20] == 12'h304, insn0[31:20] == 12'h300};
		csr_counter_wsel_q <= {insn0[31:20] == 12'hb82, insn0[31:20] == 12'hb02, insn0[31:20] == 12'hb80, insn0[31:20] == 12'hb00};
	end
	wire [31:0] csr_src = (csr_f3_q[2] ? {27'b000000000000000000000000000, csr_zimm_q} : csr_rs1_q);
	wire [31:0] csr_new = (csr_f3_q[1:0] == 2'b01 ? csr_src : (csr_f3_q[1:0] == 2'b10 ? csr_old_q | csr_src : csr_old_q & ~csr_src));
	localparam [2:0] F_IDLE = 3'd0;
	localparam [2:0] F_SQ = 3'd1;
	localparam [2:0] F_DC = 3'd2;
	localparam [2:0] F_IW0 = 3'd3;
	localparam [2:0] F_IP = 3'd4;
	localparam [2:0] F_IW1 = 3'd5;
	reg [2:0] fstate;
	reg [31:0] flush_pc_q;
	reg rd_pend;
	reg rd_trap;
	reg rd_irq;
	reg rd_mret;
	reg rd_rpl;
	reg rd_rset;
	reg rd_md;
	reg [31:0] rd_pc;
	reg [31:0] rd_insn;
	reg [31:0] rd_icause;
	reg [31:0] fi_pc;
	reg [3:0] rd_dca;
	reg [2:0] rd_tk;
	reg [31:0] rd_cause;
	reg [31:0] rd_tval;
	wire v0 = count >= 6'd1;
	wire v1 = count >= 6'd2;
	wire irq_pend = mstatus[3] && |((mie & mip) & 32'h00000888);
	reg [31:0] irq_cause;
	always @(*) begin
		if (_sv2v_0)
			;
		if (mie[11] && mip[11])
			irq_cause = 32'h8000000b;
		else if (mie[3] && mip[3])
			irq_cause = 32'h80000003;
		else
			irq_cause = 32'h80000007;
	end
	wire h0_done = done[h0[4:0]];
	wire h0_exc = exc[h0[4:0]];
	wire h0_rpl = rpl[h0[4:0]];
	wire h0_mem_done = (h0_done && !h0_rpl) && (st0 || (fu0 == 3'd2));
	wire irq_ok = (!slow_busy && !h0_mem_done) && !e4_v;
	wire csr_at_head = ((((((((!flush_q && !br_kill) && v0) && (fstate == F_IDLE)) && !rd_pend) && h0_done) && !h0_exc) && !h0_rpl) && (fu0 == 3'd5)) && (op0[2:0] == 3'd0);
	reg do_c0;
	reg do_c1;
	reg do_trap;
	reg do_irq;
	reg do_replay;
	reg do_mret;
	reg do_csr;
	reg start_fencei;
	reg [2:0] trap_kind;
	always @(*) begin
		if (_sv2v_0)
			;
		do_c0 = 1'b0;
		do_c1 = 1'b0;
		do_trap = 1'b0;
		do_irq = 1'b0;
		do_replay = 1'b0;
		do_mret = 1'b0;
		do_csr = 1'b0;
		start_fencei = 1'b0;
		trap_kind = (h0_exc ? 3'd0 : (op0[2:0] == 3'd0 ? 3'd1 : (op0[2:0] == 3'd1 ? 3'd2 : (op0[2:0] == 3'd2 ? 3'd3 : 3'd4))));
		if ((((!flush_q && !br_kill) && v0) && (fstate == F_IDLE)) && !rd_pend) begin
			if (irq_pend && irq_ok)
				do_irq = 1'b1;
			else if (h0_done) begin
				if (h0_exc)
					do_trap = 1'b1;
				else if (h0_rpl)
					do_replay = 1'b1;
				else if (fu0 == 3'd5)
					case (op0[2:0])
						3'd0:
							if (csr_arm) begin
								if (csr_ill_q)
									do_trap = 1'b1;
								else begin
									do_csr = 1'b1;
									do_c0 = 1'b1;
								end
							end
						3'd1, 3'd2: do_trap = 1'b1;
						3'd3: begin
							do_mret = 1'b1;
							do_c0 = 1'b1;
						end
						3'd4: do_c0 = 1'b1;
						3'd5: start_fencei = 1'b1;
						default: do_trap = 1'b1;
					endcase
				else begin
					do_c0 = 1'b1;
					if (((((v1 && done[h1[4:0]]) && !exc[h1[4:0]]) && !rpl[h1[4:0]]) && (fu1 != 3'd5)) && !(br0 && br1))
						do_c1 = 1'b1;
				end
			end
		end
		if ((fstate == F_IW1) && !ic_busy)
			do_c0 = 1'b1;
	end
	always @(*) begin
		if (_sv2v_0)
			;
		cm_wr = {do_c1 && wr1, do_c0 && wr0};
		cm_rd0 = rd0;
		cm_rd1 = rd1;
		cm_pdst0 = pd0;
		cm_pdst1 = pd1;
		cm_pold0 = po0;
		cm_pold1 = po1;
		sq_commit = {1'b0, do_c0 && st0} + {1'b0, do_c1 && st1};
		cmt_br_valid = (do_c0 && br0) || (do_c1 && br1);
		cmt_is_cbr = (do_c0 && br0 ? cbr0 : cbr1);
		cmt_taken = (do_c0 && br0 ? tkn[h0[4:0]] : tkn[h1[4:0]]);
		cmt_pc = (do_c0 && br0 ? pc0 : pc1);
		cmt_biq = (do_c0 && br0 ? biq0 : biq1);
	end
	assign flush = flush_q;
	assign flush_pc = flush_pc_q;
	assign fetch_stop = fstate != F_IDLE;
	assign dc_clean_req = fstate == F_DC;
	assign ic_inv = fstate == F_IP;
	wire [4:0] kill_off = br_kill_rob - head[4:0];
	wire [5:0] kill_tail = (head + {1'b0, kill_off}) + 6'd1;
	always @(posedge clk)
		if (rst) begin
			head <= 6'd0;
			tail <= 6'd0;
			done <= 32'b00000000000000000000000000000000;
			exc <= 32'b00000000000000000000000000000000;
			rpl <= 32'b00000000000000000000000000000000;
			tkn <= 32'b00000000000000000000000000000000;
			xv <= 1'b0;
			flush_q <= 1'b0;
			flush_pc_q <= RESET_PC;
			fstate <= F_IDLE;
			mstatus <= 32'h00001800;
			mie <= 32'b00000000000000000000000000000000;
			mtvec <= 32'b00000000000000000000000000000000;
			mscratch <= 32'b00000000000000000000000000000000;
			mepc <= 32'b00000000000000000000000000000000;
			mcause <= 32'b00000000000000000000000000000000;
			mtval <= 32'b00000000000000000000000000000000;
			mcycle <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
			minstret <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
			minstret_write_q <= 1'b0;
			replay_set <= 1'b0;
			md_set <= 1'b0;
			csr_wb_v <= 1'b0;
			replay_pc <= 32'b00000000000000000000000000000000;
			csr_arm <= 1'b0;
			csr_arm1 <= 1'b0;
			csr_arm2 <= 1'b0;
			rd_pend <= 1'b0;
			e0_v <= 1'b0;
			e3_v <= 1'b0;
			e4_v <= 1'b0;
			tr_v <= 2'b00;
			tr_trap <= 1'b0;
			tr_irq <= 1'b0;
		end
		else begin
			mcycle <= mcycle + 64'd1;
			csr_preg_q <= rb0[7:2];
			csr_bank_q <= rb0[1:0];
			csr_bank_q2 <= csr_bank_q;
			csr_rs1_q <= csr_rs1_value;
			csr_arm1 <= ((csr_at_head && !do_c0) && !do_trap) && !do_irq;
			csr_arm2 <= (((csr_arm1 && csr_at_head) && !do_c0) && !do_trap) && !do_irq;
			csr_arm <= (((csr_arm2 && csr_at_head) && !do_c0) && !do_trap) && !do_irq;
			flush_q <= 1'b0;
			replay_set <= 1'b0;
			md_set <= 1'b0;
			csr_wb_v <= 1'b0;
			tr_v <= 2'b00;
			tr_trap <= 1'b0;
			tr_irq <= 1'b0;
			if (c0_v)
				done[c0_rob] <= 1'b1;
			if (c5_v)
				tkn[c5_rob] <= c5_taken;
			if (c5_v && !c5_exc)
				done[c5_rob] <= 1'b1;
			if (c1_v)
				done[c1_rob] <= 1'b1;
			if (c2_v)
				done[c2_rob] <= 1'b1;
			if ((c3_v && !c3_exc) && !c3_replay)
				done[c3_rob] <= 1'b1;
			if ((c4_v && !c4_exc) && !c4_replay)
				done[c4_rob] <= 1'b1;
			e0_v <= (c5_v && c5_exc) && !flush_q;
			e0_rob <= c5_rob;
			e0_tval <= c5_tval;
			e3_v <= (c3_v && (c3_exc || c3_replay)) && !flush_q;
			e3_rob <= c3_rob;
			e3_exc <= c3_exc;
			e3_cause <= c3_cause;
			e3_tval <= c3_tval;
			e4_v <= (c4_v && (c4_exc || c4_replay)) && !flush_q;
			e4_rob <= c4_rob;
			e4_exc <= c4_exc;
			e4_cause <= c4_cause;
			e4_tval <= c4_tval;
			e4_rio <= c4_replay_io;
			begin : sv2v_autoblock_1
				reg a0;
				reg a3;
				reg a4;
				a0 = (e0_v && !flush_q) && !(br_kill && older(br_kill_rob, e0_rob));
				a3 = (e3_v && !flush_q) && !(br_kill && older(br_kill_rob, e3_rob));
				a4 = (e4_v && !flush_q) && !(br_kill && older(br_kill_rob, e4_rob));
				if (a0) begin
					done[e0_rob] <= 1'b1;
					exc[e0_rob] <= 1'b1;
				end
				if (a3) begin
					done[e3_rob] <= 1'b1;
					if (e3_exc)
						exc[e3_rob] <= 1'b1;
					else begin
						rpl[e3_rob] <= 1'b1;
						rpl_io[e3_rob] <= 1'b1;
					end
				end
				if (a4) begin
					done[e4_rob] <= 1'b1;
					if (e4_exc)
						exc[e4_rob] <= 1'b1;
					else begin
						rpl[e4_rob] <= 1'b1;
						rpl_io[e4_rob] <= e4_rio;
					end
				end
				if (flush_q)
					xv <= 1'b0;
				else begin : sv2v_autoblock_2
					reg xk;
					reg a3x;
					reg a4x;
					reg w0;
					reg w3;
					reg w4;
					reg o0x;
					reg o3x;
					reg o4x;
					reg o03;
					reg o04;
					reg o34;
					xk = xv && !(br_kill && older(br_kill_rob, xrob));
					a3x = a3 && e3_exc;
					a4x = a4 && e4_exc;
					o0x = older(e0_rob, xrob);
					o3x = older(e3_rob, xrob);
					o4x = older(e4_rob, xrob);
					o03 = older(e0_rob, e3_rob);
					o04 = older(e0_rob, e4_rob);
					o34 = older(e3_rob, e4_rob);
					w0 = ((a0 && (!xk || o0x)) && (!a3x || o03)) && (!a4x || o04);
					w3 = ((a3x && (!xk || o3x)) && (!a0 || !o03)) && (!a4x || o34);
					w4 = ((a4x && (!xk || o4x)) && (!a0 || !o04)) && (!a3x || !o34);
					xv <= ((xk || a0) || a3x) || a4x;
					if (w0) begin
						xrob <= e0_rob;
						xcause <= 4'd0;
						xtval <= e0_tval;
					end
					else if (w3) begin
						xrob <= e3_rob;
						xcause <= e3_cause;
						xtval <= e3_tval;
					end
					else if (w4) begin
						xrob <= e4_rob;
						xcause <= e4_cause;
						xtval <= e4_tval;
					end
				end
			end
			begin : sv2v_autoblock_3
				reg signed [31:0] i;
				for (i = 0; i < 32; i = i + 1)
					if (md_viol[i]) begin
						rpl[i] <= 1'b1;
						rpl_md[i] <= 1'b1;
						rpl_io[i] <= 1'b0;
					end
			end
			if (dv[0]) begin
				done[t0[4:0]] <= e0[45:43] == 3'd5;
				exc[t0[4:0]] <= 1'b0;
				rpl[t0[4:0]] <= 1'b0;
				rpl_md[t0[4:0]] <= 1'b0;
			end
			if (dv[1]) begin
				done[t1[4:0]] <= e1[45:43] == 3'd5;
				exc[t1[4:0]] <= 1'b0;
				rpl[t1[4:0]] <= 1'b0;
				rpl_md[t1[4:0]] <= 1'b0;
			end
			if (br_kill)
				tail <= kill_tail;
			else
				tail <= (tail + {5'b00000, dv[0]}) + {5'b00000, dv[1]};
			head <= (head + {5'b00000, do_c0}) + {5'b00000, do_c1};
			minstret <= minstret + (minstret_write_q ? 64'd0 : {63'b000000000000000000000000000000000000000000000000000000000000000, tr_v[0]} + {63'b000000000000000000000000000000000000000000000000000000000000000, tr_v[1]});
			minstret_write_q <= (do_csr && csr_wen_q) && |csr_counter_wsel_q[3:2];
			tr_v <= {do_c1, do_c0};
			tr_pc0 <= pc0;
			tr_pc1 <= pc1;
			tr_insn0 <= insn0;
			tr_insn1 <= insn1;
			tr_wr0 <= wr0;
			tr_wr1 <= wr1;
			tr_rd0 <= rd0;
			tr_rd1 <= rd1;
			tr_pd0 <= pd0;
			tr_pd1 <= pd1;
			tr_csr_old <= csr_old_q;
			if (do_csr) begin
				csr_wb_v <= wr0;
				csr_wb_pd <= pd0;
				csr_wb_data <= csr_old_q;
				if (csr_wen_q) begin
					if (csr_wsel_q[0])
						mstatus <= (csr_new & 32'h00000088) | 32'h00001800;
					if (csr_wsel_q[1])
						mie <= csr_new & 32'h00000888;
					if (csr_wsel_q[2])
						mtvec <= {csr_new[31:2], 2'b00};
					if (csr_wsel_q[3])
						mscratch <= csr_new;
					if (csr_wsel_q[4])
						mepc <= {csr_new[31:2], 2'b00};
					if (csr_wsel_q[5])
						mcause <= csr_new;
					if (csr_wsel_q[6])
						mtval <= csr_new;
					if (csr_counter_wsel_q[0])
						mcycle <= {mcycle[63:32], csr_new};
					if (csr_counter_wsel_q[1])
						mcycle <= {csr_new, mcycle[31:0]};
					if (csr_counter_wsel_q[2])
						minstret <= {minstret[63:32], csr_new};
					if (csr_counter_wsel_q[3])
						minstret <= {csr_new, minstret[31:0]};
				end
			end
			if (!rd_pend) begin
				rd_pend <= ((do_trap || do_irq) || do_mret) || do_replay;
				rd_trap <= do_trap || do_irq;
				rd_irq <= do_irq;
				rd_mret <= do_mret;
				rd_rpl <= do_replay;
				rd_rset <= ((fu0 == 3'd2) || st0) && rpl_io[h0[4:0]];
				rd_md <= rpl_md[h0[4:0]];
				rd_pc <= pc0;
				rd_insn <= insn0;
				rd_dca <= dca0;
				rd_icause <= irq_cause;
				rd_tk <= trap_kind;
			end
			if (rd_pend) begin : sv2v_autoblock_4
				reg [31:0] cz;
				reg [31:0] tz;
				case (rd_tk)
					3'd0: begin
						cz = {28'b0000000000000000000000000000, xcause};
						tz = xtval;
					end
					3'd1: begin
						cz = 32'd2;
						tz = rd_insn;
					end
					3'd2: begin
						cz = 32'd11;
						tz = 32'b00000000000000000000000000000000;
					end
					3'd3: begin
						cz = 32'd3;
						tz = rd_pc;
					end
					default: begin
						cz = {28'b0000000000000000000000000000, rd_dca};
						tz = (rd_dca == 4'd1 ? rd_pc : (rd_dca == 4'd0 ? rd_pc + {{11 {rd_insn[31]}}, rd_insn[31], rd_insn[19:12], rd_insn[20], rd_insn[30:21], 1'b0} : rd_insn));
					end
				endcase
				if (rd_irq) begin
					cz = rd_icause;
					tz = 32'b00000000000000000000000000000000;
				end
				rd_cause <= cz;
				rd_tval <= tz;
				rd_pend <= 1'b0;
				flush_q <= 1'b1;
				if (rd_trap) begin
					mepc <= rd_pc;
					mcause <= cz;
					mtval <= tz;
					mstatus <= ((mstatus & ~32'h00000088) | {24'b000000000000000000000000, mstatus[3], 7'b0000000}) | 32'h00001800;
					flush_pc_q <= mtvec;
					tr_trap <= 1'b1;
					tr_irq <= rd_irq;
					tr_cause <= cz;
					tr_epc <= rd_pc;
				end
				if (rd_mret) begin
					mstatus <= ((mstatus & ~32'h00000008) | {28'b0000000000000000000000000000, mstatus[7], 3'b000}) | 32'h00001880;
					flush_pc_q <= mepc;
				end
				if (rd_rpl) begin
					flush_pc_q <= rd_pc;
					replay_set <= rd_rset;
					md_set <= rd_md;
					replay_pc <= rd_pc;
				end
			end
			case (fstate)
				F_IDLE:
					if (start_fencei) begin
						fstate <= F_SQ;
						fi_pc <= pc0 + 32'd4;
					end
				F_SQ:
					if (sq_empty)
						fstate <= F_DC;
				F_DC:
					if (dc_clean_done)
						fstate <= F_IW0;
				F_IW0:
					if (!ic_busy)
						fstate <= F_IP;
				F_IP: fstate <= F_IW1;
				F_IW1:
					if (!ic_busy) begin
						fstate <= F_IDLE;
						flush_q <= 1'b1;
						flush_pc_q <= fi_pc;
					end
				default: fstate <= F_IDLE;
			endcase
			if (flush_q)
				tail <= head;
		end
	initial _sv2v_0 = 0;
endmodule
module o2_core (
	clk,
	rst,
	irq_software,
	irq_timer,
	irq_external,
	ext_clean_req,
	ext_clean_done,
	data_idle,
	io_req_v,
	io_req_rdy,
	io_addr,
	io_write,
	io_be,
	io_wdata,
	io_rsp_v,
	io_rdata,
	io_rsp_err,
	ic_cmd_valid,
	ic_cmd_ready,
	ic_cmd_write,
	ic_cmd_addr,
	ic_cmd_len,
	ic_w_valid,
	ic_w_ready,
	ic_w_data,
	ic_w_be,
	ic_w_last,
	ic_r_valid,
	ic_r_ready,
	ic_r_data,
	ic_r_error,
	ic_r_last,
	dc_cmd_valid,
	dc_cmd_ready,
	dc_cmd_write,
	dc_cmd_addr,
	dc_cmd_len,
	dc_w_valid,
	dc_w_ready,
	dc_w_data,
	dc_w_be,
	dc_w_last,
	dc_r_valid,
	dc_r_ready,
	dc_r_data,
	dc_r_error,
	dc_r_last,
	tr_v,
	tr_pc0,
	tr_pc1,
	tr_insn0,
	tr_insn1,
	tr_wr0,
	tr_wr1,
	tr_rd0,
	tr_rd1,
	tr_pd0,
	tr_pd1,
	tr_trap,
	tr_irq,
	tr_cause,
	tr_epc,
	tr_csr_old,
	prf_we_o,
	prf_wa_o,
	prf_wd_o,
	minstret,
	mcycle,
	perf_ev,
	bus_err_v,
	bus_err_wb,
	bus_err_addr
);
	reg _sv2v_0;
	parameter [31:0] RESET_PC = 32'h80000000;
	parameter [31:0] RAM_BASE = 32'h80000000;
	parameter integer RAM_BYTES = 131072;
	input wire clk;
	input wire rst;
	input wire irq_software;
	input wire irq_timer;
	input wire irq_external;
	input wire ext_clean_req;
	output wire ext_clean_done;
	output wire data_idle;
	output wire io_req_v;
	input wire io_req_rdy;
	output wire [31:0] io_addr;
	output wire io_write;
	output wire [3:0] io_be;
	output wire [31:0] io_wdata;
	input wire io_rsp_v;
	input wire [31:0] io_rdata;
	input wire io_rsp_err;
	output wire ic_cmd_valid;
	input wire ic_cmd_ready;
	output wire ic_cmd_write;
	output wire [31:0] ic_cmd_addr;
	output wire [7:0] ic_cmd_len;
	output wire ic_w_valid;
	input wire ic_w_ready;
	output wire [31:0] ic_w_data;
	output wire [3:0] ic_w_be;
	output wire ic_w_last;
	input wire ic_r_valid;
	output wire ic_r_ready;
	input wire [31:0] ic_r_data;
	input wire ic_r_error;
	input wire ic_r_last;
	output wire dc_cmd_valid;
	input wire dc_cmd_ready;
	output wire dc_cmd_write;
	output wire [31:0] dc_cmd_addr;
	output wire [7:0] dc_cmd_len;
	output wire dc_w_valid;
	input wire dc_w_ready;
	output wire [31:0] dc_w_data;
	output wire [3:0] dc_w_be;
	output wire dc_w_last;
	input wire dc_r_valid;
	output wire dc_r_ready;
	input wire [31:0] dc_r_data;
	input wire dc_r_error;
	input wire dc_r_last;
	output wire [1:0] tr_v;
	output wire [31:0] tr_pc0;
	output wire [31:0] tr_pc1;
	output wire [31:0] tr_insn0;
	output wire [31:0] tr_insn1;
	output wire tr_wr0;
	output wire tr_wr1;
	output wire [4:0] tr_rd0;
	output wire [4:0] tr_rd1;
	output wire [5:0] tr_pd0;
	output wire [5:0] tr_pd1;
	output wire tr_trap;
	output wire tr_irq;
	output wire [31:0] tr_cause;
	output wire [31:0] tr_epc;
	output wire [31:0] tr_csr_old;
	output wire [3:0] prf_we_o;
	output wire [23:0] prf_wa_o;
	output wire [127:0] prf_wd_o;
	output wire [63:0] minstret;
	output wire [63:0] mcycle;
	output reg [4:0] perf_ev;
	output wire bus_err_v;
	output wire bus_err_wb;
	output wire [31:0] bus_err_addr;
	wire flush;
	wire [31:0] flush_pc;
	wire br_kill;
	wire br_ok;
	wire [2:0] br_kill_tag;
	wire [2:0] br_ok_tag;
	wire fetch_stop;
	wire pf_ic;
	wire pf_lda;
	wire pf_ldm;
	wire pf_fe;
	wire pf_be;
	always @(posedge clk) perf_ev <= {pf_be, pf_fe, pf_ldm, pf_lda, pf_ic};
	wire [31:0] ic_f1_pc;
	wire [31:0] ic_f2_pc;
	wire ic_f2_hit;
	wire ic_f2_cacheable;
	wire ic_f2_fault;
	wire ic_refill_req;
	wire ic_busy;
	wire ic_inv;
	wire [127:0] ic_f2_block;
	o2_icache #(
		.SETS(256),
		.RAM_BASE(RAM_BASE),
		.RAM_BYTES(RAM_BYTES)
	) icache(
		.clk(clk),
		.rst(rst),
		.f1_pc(ic_f1_pc),
		.f1_hold(1'b0),
		.f2_pc(ic_f2_pc),
		.f2_hit(ic_f2_hit),
		.f2_cacheable(ic_f2_cacheable),
		.f2_fault(ic_f2_fault),
		.f2_block(ic_f2_block),
		.refill_req(ic_refill_req),
		.busy(ic_busy),
		.invalidate(ic_inv),
		.cmd_valid(ic_cmd_valid),
		.cmd_ready(ic_cmd_ready),
		.cmd_write(ic_cmd_write),
		.cmd_addr(ic_cmd_addr),
		.cmd_len(ic_cmd_len),
		.w_valid(ic_w_valid),
		.w_ready(ic_w_ready),
		.w_data(ic_w_data),
		.w_be(ic_w_be),
		.w_last(ic_w_last),
		.r_valid(ic_r_valid),
		.r_ready(ic_r_ready),
		.r_data(ic_r_data),
		.r_error(ic_r_error),
		.r_last(ic_r_last),
		.perf_fill(pf_ic)
	);
	wire fq_v0;
	wire fq_v1;
	wire fq_fault0;
	wire fq_fault1;
	wire [31:0] fq_pc0;
	wire [31:0] fq_pc1;
	wire [31:0] fq_insn0;
	wire [31:0] fq_insn1;
	wire [31:0] fq_pred0;
	wire [31:0] fq_pred1;
	wire [3:0] fq_biq0;
	wire [3:0] fq_biq1;
	wire [1:0] fq_k0;
	wire [1:0] fq_k1;
	wire [1:0] fq_pop;
	wire fq_cmt0;
	wire fq_cmt1;
	wire fq_br0;
	wire fq_br1;
	wire mis_v;
	wire [31:0] mis_pc;
	wire [3:0] mis_biq;
	wire [1:0] mis_k;
	wire mis_cbr;
	wire mis_taken;
	reg cmt_br_valid;
	reg cmt_is_cbr;
	reg cmt_taken;
	reg [31:0] cmt_pc;
	reg [3:0] cmt_biq;
	wire ib_train;
	wire [31:0] ib_pc;
	wire [31:0] ib_target;
	o2_frontend #(.RESET_PC(RESET_PC)) frontend(
		.clk(clk),
		.rst(rst),
		.be_flush(flush),
		.be_flush_pc(flush_pc),
		.be_mispredict(mis_v),
		.be_mis_pc(mis_pc),
		.be_mis_biq(mis_biq),
		.be_mis_k(mis_k),
		.be_mis_is_cbr(mis_cbr),
		.be_mis_taken(mis_taken),
		.fetch_stop(fetch_stop),
		.cmt_br_valid(cmt_br_valid),
		.cmt_is_cbr(cmt_is_cbr),
		.cmt_taken(cmt_taken),
		.cmt_pc(cmt_pc),
		.cmt_biq(cmt_biq),
		.ib_train(ib_train),
		.ib_pc(ib_pc),
		.ib_target(ib_target),
		.ic_f1_pc(ic_f1_pc),
		.ic_f2_pc(ic_f2_pc),
		.ic_f2_hit(ic_f2_hit),
		.ic_f2_cacheable(ic_f2_cacheable),
		.ic_f2_fault(ic_f2_fault),
		.ic_f2_block(ic_f2_block),
		.ic_refill_req(ic_refill_req),
		.ic_busy(ic_busy),
		.fq_v0(fq_v0),
		.fq_v1(fq_v1),
		.fq_pc0(fq_pc0),
		.fq_pc1(fq_pc1),
		.fq_insn0(fq_insn0),
		.fq_insn1(fq_insn1),
		.fq_pred0(fq_pred0),
		.fq_pred1(fq_pred1),
		.fq_fault0(fq_fault0),
		.fq_fault1(fq_fault1),
		.fq_biq0(fq_biq0),
		.fq_biq1(fq_biq1),
		.fq_k0(fq_k0),
		.fq_k1(fq_k1),
		.fq_cmt0(fq_cmt0),
		.fq_cmt1(fq_cmt1),
		.fq_br0(fq_br0),
		.fq_br1(fq_br1),
		.fq_pop(fq_pop)
	);
	reg [1:0] cm_wr;
	reg [4:0] cm_rd0;
	reg [4:0] cm_rd1;
	reg [5:0] cm_pdst0;
	reg [5:0] cm_pdst1;
	reg [5:0] cm_pold0;
	reg [5:0] cm_pold1;
	wire rob_empty;
	wire replay_set;
	wire [31:0] replay_pc;
	wire [5:0] rob_tail;
	wire [5:0] rob_count;
	wire [4:0] rob_head;
	wire [1:0] rob_room;
	wire [1:0] sq_room;
	wire [3:0] iq0_free;
	wire [3:0] iq1_free;
	wire [3:0] iqm_free;
	wire [2:0] iq0_a0;
	wire [2:0] iq0_a1;
	wire [2:0] iq1_a0;
	wire [2:0] iq1_a1;
	wire [2:0] iqm_a0;
	wire [2:0] iqm_a1;
	wire [23:0] wake;
	wire [3:0] sq_tail;
	wire [3:0] sq_count;
	wire [7:0] sq_valid;
	wire [7:0] sq_issued;
	wire [7:0] sq_free;
	wire sq_empty;
	wire [1:0] iq0_dv;
	wire [1:0] iq1_dv;
	wire [1:0] iqm_dv;
	wire [38:0] s0_pay;
	wire [38:0] s1_pay;
	wire [31:0] s0_imm;
	wire [31:0] s1_imm;
	wire [23:0] s0_dep;
	wire [23:0] s1_dep;
	wire [1:0] s0_lat;
	wire [1:0] s1_lat;
	wire [7:0] s0_brm;
	wire [7:0] s1_brm;
	wire [7:0] s0_sqm;
	wire [7:0] s1_sqm;
	wire s0_st;
	wire s1_st;
	wire s0_head;
	wire s1_head;
	wire [4:0] s0_rob;
	wire [4:0] s1_rob;
	wire [1:0] rob_dv;
	wire [127:0] rob_e0;
	wire [127:0] rob_e1;
	wire [1:0] sq_alloc;
	wire brt_we;
	wire [2:0] brt_tag;
	wire [107:0] brt_data;
	wire [3:0] ckpt_sq_tail;
	wire md_set;
	o2_rename rename(
		.clk(clk),
		.rst(rst),
		.fq_v0(fq_v0),
		.fq_v1(fq_v1),
		.fq_pc0(fq_pc0),
		.fq_pc1(fq_pc1),
		.fq_insn0(fq_insn0),
		.fq_insn1(fq_insn1),
		.fq_pred0(fq_pred0),
		.fq_pred1(fq_pred1),
		.fq_fault0(fq_fault0),
		.fq_fault1(fq_fault1),
		.fq_biq0(fq_biq0),
		.fq_biq1(fq_biq1),
		.fq_k0(fq_k0),
		.fq_k1(fq_k1),
		.fq_cmt0(fq_cmt0),
		.fq_cmt1(fq_cmt1),
		.fq_br0(fq_br0),
		.fq_br1(fq_br1),
		.fq_pop(fq_pop),
		.flush(flush),
		.br_kill(br_kill),
		.br_kill_tag(br_kill_tag),
		.br_ok(br_ok),
		.br_ok_tag(br_ok_tag),
		.cm_wr(cm_wr),
		.cm_rd0(cm_rd0),
		.cm_rd1(cm_rd1),
		.cm_pdst0(cm_pdst0),
		.cm_pdst1(cm_pdst1),
		.cm_pold0(cm_pold0),
		.cm_pold1(cm_pold1),
		.rob_empty(rob_empty),
		.replay_set(replay_set),
		.replay_pc(replay_pc),
		.md_set(md_set),
		.rob_tail(rob_tail),
		.rob_room(rob_room),
		.sq_room(sq_room),
		.iq0_free(iq0_free),
		.iq1_free(iq1_free),
		.iqm_free(iqm_free),
		.iq0_a0(iq0_a0),
		.iq0_a1(iq0_a1),
		.iq1_a0(iq1_a0),
		.iq1_a1(iq1_a1),
		.iqm_a0(iqm_a0),
		.iqm_a1(iqm_a1),
		.wake(wake),
		.sq_tail(sq_tail),
		.sq_count(sq_count),
		.sq_valid(sq_valid),
		.iq0_dv(iq0_dv),
		.iq1_dv(iq1_dv),
		.iqm_dv(iqm_dv),
		.s0_pay(s0_pay),
		.s1_pay(s1_pay),
		.s0_imm(s0_imm),
		.s1_imm(s1_imm),
		.s0_dep(s0_dep),
		.s1_dep(s1_dep),
		.s0_lat(s0_lat),
		.s1_lat(s1_lat),
		.s0_brm(s0_brm),
		.s1_brm(s1_brm),
		.s0_sqm(s0_sqm),
		.s1_sqm(s1_sqm),
		.s0_st(s0_st),
		.s1_st(s1_st),
		.s0_head(s0_head),
		.s1_head(s1_head),
		.s0_rob(s0_rob),
		.s1_rob(s1_rob),
		.rob_dv(rob_dv),
		.rob_e0(rob_e0),
		.rob_e1(rob_e1),
		.sq_alloc(sq_alloc),
		.brt_we(brt_we),
		.brt_tag(brt_tag),
		.brt_data(brt_data),
		.ckpt_sq_tail(ckpt_sq_tail),
		.perf_fe_stall(pf_fe),
		.perf_be_stall(pf_be)
	);
	reg [107:0] brt [0:7];
	reg [3:0] ckpt_sq [0:7];
	always @(posedge clk)
		if (brt_we) begin
			brt[brt_tag] <= brt_data;
			ckpt_sq[brt_tag] <= ckpt_sq_tail;
		end
	wire [31:0] imm_rd [0:2];
	wire imm_s0e = !s0_rob[0];
	wire imm_we_e = (rob_dv[0] && imm_s0e) || (rob_dv[1] && !imm_s0e);
	wire imm_we_o = (rob_dv[0] && !imm_s0e) || (rob_dv[1] && imm_s0e);
	wire [3:0] imm_wa_e = (imm_s0e ? s0_rob[4:1] : s1_rob[4:1]);
	wire [3:0] imm_wa_o = (imm_s0e ? s1_rob[4:1] : s0_rob[4:1]);
	wire [31:0] imm_wd_e = (imm_s0e ? s0_imm : s1_imm);
	wire [31:0] imm_wd_o = (imm_s0e ? s1_imm : s0_imm);
	genvar _gv_gi_1;
	reg [4:0] rr0_rob;
	reg [4:0] rr1_rob;
	reg [4:0] rrm_rob;
	generate
		for (_gv_gi_1 = 0; _gv_gi_1 < 3; _gv_gi_1 = _gv_gi_1 + 1) begin : g_imm
			localparam gi = _gv_gi_1;
			(* syn_ramstyle = "lut_ram" *) reg [31:0] te [0:15];
			(* syn_ramstyle = "lut_ram" *) reg [31:0] to [0:15];
			always @(posedge clk) begin
				if (imm_we_e)
					te[imm_wa_e] <= imm_wd_e;
				if (imm_we_o)
					to[imm_wa_o] <= imm_wd_o;
			end
			wire [4:0] ri = (gi == 0 ? rr0_rob : (gi == 1 ? rr1_rob : rrm_rob));
			assign imm_rd[gi] = (ri[0] ? to[ri[4:1]] : te[ri[4:1]]);
		end
	endgenerate
	wire [7:0] wake0;
	wire [7:0] wake1;
	wire [7:0] wakem;
	assign wake = {wakem, wake1, wake0};
	wire iss0_v;
	wire iss1_v;
	wire issm_v;
	wire [2:0] iss0_slot;
	wire [2:0] iss1_slot;
	wire [2:0] issm_slot;
	wire [38:0] iss0_pay;
	wire [38:0] iss1_pay;
	wire [38:0] issm_pay;
	wire [7:0] iss0_brm;
	wire [7:0] iss1_brm;
	wire [7:0] issm_brm;
	wire [7:0] issm_sqm;
	wire [7:0] unused_sqm0;
	wire [7:0] unused_sqm1;
	wire [4:0] iss0_rob;
	wire [4:0] iss1_rob;
	wire [4:0] issm_rob;
	wire [1:0] iss0_lat;
	wire [1:0] iss1_lat;
	wire [1:0] issm_lat;
	wire [7:0] ext_done;
	wire slow_busy;
	wire slow_pend;
	wire spec_ok;
	wire [31:0] md_viol;
	reg mi1;
	reg mi2;
	always @(posedge clk)
		if (rst) begin
			mi1 <= 1'b0;
			mi2 <= 1'b0;
		end
		else begin
			mi1 <= iss1_v && (iss1_lat == 2'd2);
			mi2 <= mi1;
		end
	o2_iq #(
		.N(8),
		.NC(24),
		.BASE(0),
		.PW(39),
		.MEM(0)
	) iq0(
		.clk(clk),
		.rst(rst),
		.d_v(iq0_dv),
		.d_pay0(s0_pay),
		.d_pay1(s1_pay),
		.d_dep0(s0_dep),
		.d_dep1(s1_dep),
		.d_lat0(s0_lat),
		.d_lat1(s1_lat),
		.d_brm0(s0_brm),
		.d_brm1(s1_brm),
		.d_sqm0(s0_sqm),
		.d_sqm1(s1_sqm),
		.d_store0(s0_st),
		.d_store1(s1_st),
		.d_head0(s0_head),
		.d_head1(s1_head),
		.d_rob0(s0_rob),
		.d_rob1(s1_rob),
		.a_slot0(iq0_a0),
		.a_slot1(iq0_a1),
		.free_cnt(iq0_free),
		.wake_in(wake),
		.wake_out(wake0),
		.issue_en(1'b1),
		.blk_lat(1'b0),
		.blk_l0(1'b0),
		.iss_v(iss0_v),
		.iss_slot(iss0_slot),
		.iss_pay(iss0_pay),
		.iss_brm(iss0_brm),
		.iss_sqm(unused_sqm0),
		.iss_rob(iss0_rob),
		.iss_lat(iss0_lat),
		.ext_done(8'b00000000),
		.sq_issued(8'b00000000),
		.sq_free(8'b00000000),
		.rob_head(rob_head),
		.br_ok(br_ok),
		.br_ok_tag(br_ok_tag),
		.br_kill(br_kill),
		.br_kill_tag(br_kill_tag),
		.flush(flush)
	);
	o2_iq #(
		.N(8),
		.NC(24),
		.BASE(8),
		.PW(39),
		.MEM(0)
	) iq1(
		.clk(clk),
		.rst(rst),
		.d_v(iq1_dv),
		.d_pay0(s0_pay),
		.d_pay1(s1_pay),
		.d_dep0(s0_dep),
		.d_dep1(s1_dep),
		.d_lat0(s0_lat),
		.d_lat1(s1_lat),
		.d_brm0(s0_brm),
		.d_brm1(s1_brm),
		.d_sqm0(s0_sqm),
		.d_sqm1(s1_sqm),
		.d_store0(s0_st),
		.d_store1(s1_st),
		.d_head0(s0_head),
		.d_head1(s1_head),
		.d_rob0(s0_rob),
		.d_rob1(s1_rob),
		.a_slot0(iq1_a0),
		.a_slot1(iq1_a1),
		.free_cnt(iq1_free),
		.wake_in(wake),
		.wake_out(wake1),
		.issue_en(1'b1),
		.blk_lat(1'b0),
		.blk_l0(mi2),
		.iss_v(iss1_v),
		.iss_slot(iss1_slot),
		.iss_pay(iss1_pay),
		.iss_brm(iss1_brm),
		.iss_sqm(unused_sqm1),
		.iss_rob(iss1_rob),
		.iss_lat(iss1_lat),
		.ext_done(8'b00000000),
		.sq_issued(8'b00000000),
		.sq_free(8'b00000000),
		.rob_head(rob_head),
		.br_ok(br_ok),
		.br_ok_tag(br_ok_tag),
		.br_kill(br_kill),
		.br_kill_tag(br_kill_tag),
		.flush(flush)
	);
	o2_iq #(
		.N(8),
		.NC(24),
		.BASE(16),
		.PW(39),
		.MEM(1)
	) iqm(
		.clk(clk),
		.rst(rst),
		.d_v(iqm_dv),
		.d_pay0(s0_pay),
		.d_pay1(s1_pay),
		.d_dep0(s0_dep),
		.d_dep1(s1_dep),
		.d_lat0(s0_lat),
		.d_lat1(s1_lat),
		.d_brm0(s0_brm),
		.d_brm1(s1_brm),
		.d_sqm0(s0_sqm),
		.d_sqm1(s1_sqm),
		.d_store0(s0_st),
		.d_store1(s1_st),
		.d_head0(s0_head),
		.d_head1(s1_head),
		.d_rob0(s0_rob),
		.d_rob1(s1_rob),
		.a_slot0(iqm_a0),
		.a_slot1(iqm_a1),
		.free_cnt(iqm_free),
		.wake_in(wake),
		.wake_out(wakem),
		.issue_en(!slow_pend),
		.blk_lat(1'b0),
		.blk_l0(1'b0),
		.iss_v(issm_v),
		.iss_slot(issm_slot),
		.iss_pay(issm_pay),
		.iss_brm(issm_brm),
		.iss_sqm(issm_sqm),
		.iss_rob(issm_rob),
		.iss_lat(issm_lat),
		.ext_done(ext_done),
		.sq_issued(sq_issued),
		.sq_free(sq_free),
		.spec_ok(spec_ok),
		.rob_head(rob_head),
		.br_ok(br_ok),
		.br_ok_tag(br_ok_tag),
		.br_kill(br_kill),
		.br_kill_tag(br_kill_tag),
		.flush(flush)
	);
	reg [2:0] prf_we;
	reg [17:0] prf_wa;
	reg [95:0] prf_wd;
	wire [35:0] prf_ra;
	wire [191:0] prf_rd;
	wire [35:0] prf_ra_n;
	wire [107:0] prf_ra_b;
	genvar _gv_gw_1;
	generate
		for (_gv_gw_1 = 0; _gv_gw_1 < 3; _gv_gw_1 = _gv_gw_1 + 1) begin : g_rac
			localparam gw = _gv_gw_1;
			(* syn_preserve = 1 *) reg [35:0] c;
			always @(posedge clk) c <= prf_ra_n;
			assign prf_ra_b[36 * gw+:36] = c;
		end
	endgenerate
	wire [11:0] prf_rsel;
	wire csr_rd_b;
	wire [1:0] csr_rs1_bank;
	reg [38:0] rr0_pay;
	reg [38:0] rr1_pay;
	reg [38:0] rrm_pay;
	assign prf_rsel = {rrm_pay[36:35], rrm_pay[38:37] | (csr_rd_b ? csr_rs1_bank : 2'b00), rr1_pay[36:35], rr1_pay[38:37], rr0_pay[36:35], rr0_pay[38:37]};
	o2_prf #(
		.NW(3),
		.NR(6)
	) prf(
		.clk(clk),
		.rst(rst),
		.we(prf_we),
		.waddr(prf_wa),
		.wdata(prf_wd),
		.raddr_b(prf_ra_b),
		.rsel(prf_rsel),
		.rdata(prf_rd)
	);
	reg wb_v [0:2];
	reg [5:0] wb_pd [0:2];
	reg [31:0] wb_d [0:2];
	// R65: LSU-local copies of wb_d (same D, same clock) for the address
	// base bypass only, so the LSU operand is not pinned beside the ALU.
	(* syn_preserve = 1 *) reg [31:0] wb_dm0;
	(* syn_preserve = 1 *) reg [31:0] wb_dm1;
	(* syn_preserve = 1 *) reg [31:0] wb_dm2;
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 3; i = i + 1)
				begin
					prf_we[i] = wb_v[i];
					prf_wa[6 * i+:6] = wb_pd[i];
					prf_wd[32 * i+:32] = wb_d[i];
				end
		end
	end
	assign prf_we_o = {1'b0, prf_we};
	assign prf_wa_o = {6'b000000, prf_wa};
	assign prf_wd_o = {32'b00000000000000000000000000000000, prf_wd};
	function automatic killed;
		input [7:0] brm;
		killed = flush || (br_kill && brm[br_kill_tag]);
	endfunction
	function automatic [7:0] okclr;
		input [7:0] brm;
		okclr = (br_ok ? brm & ~(8'b00000001 << br_ok_tag) : brm);
	endfunction
	function automatic [31:0] rrval;
		input [5:0] p;
		input [31:0] prfv;
		reg [2:0] m;
		reg [31:0] bv;
		begin
			bv = 32'b00000000000000000000000000000000;
			begin : sv2v_autoblock_2
				reg signed [31:0] i;
				for (i = 0; i < 3; i = i + 1)
					begin
						m[i] = (wb_v[i] && (wb_pd[i] == p)) && (p != 6'd0);
						bv = bv | ({32 {m[i]}} & wb_d[i]);
					end
			end
			rrval = (|m ? bv : prfv);
		end
	endfunction
	wire ex0_prod;
	wire ex1_prod;
	wire ld_prod;
	wire mul_prod;
	wire [5:0] ex0_ppd;
	wire [5:0] ex1_ppd;
	wire [5:0] ld_ppd;
	wire [5:0] mul_ppd;
	function automatic [1:0] latesel;
		input [5:0] p;
		reg m0;
		reg m1;
		reg m2;
		begin
			m0 = ex0_prod && (ex0_ppd == p);
			m1 = (ex1_prod && (ex1_ppd == p)) || (mul_prod && (mul_ppd == p));
			m2 = ld_prod && (ld_ppd == p);
			latesel = (p == 6'd0 ? 2'd0 : {m1 | m2, m0 | m2});
		end
	endfunction
	function automatic [31:0] exvalm;
		input [1:0] sel;
		input [31:0] v;
		case (sel)
			2'd0: exvalm = v;
			2'd1: exvalm = wb_dm0;
			2'd2: exvalm = wb_dm1;
			default: exvalm = wb_dm2;
		endcase
	endfunction
	function automatic [31:0] exval;
		input [1:0] sel;
		input [31:0] v;
		case (sel)
			2'd0: exval = v;
			2'd1: exval = wb_d[0];
			2'd2: exval = wb_d[1];
			default: exval = wb_d[2];
		endcase
	endfunction
	function automatic [10:0] aludec;
		input [3:0] op;
		reg [9:0] oh;
		begin
			case (op)
				4'd0, 4'd1: oh = 10'b0000000001;
				4'd3: oh = 10'b0000000010;
				4'd4: oh = 10'b0000000100;
				4'd2: oh = 10'b0000001000;
				4'd6: oh = 10'b0000010000;
				4'd7: oh = 10'b0000100000;
				4'd5: oh = 10'b0001000000;
				4'd8: oh = 10'b0010000000;
				4'd9: oh = 10'b0100000000;
				default: oh = 10'b1000000000;
			endcase
			aludec = {((op == 4'd1) || (op == 4'd3)) || (op == 4'd4), oh};
		end
	endfunction
	function automatic [31:0] alu;
		input [10:0] d;
		input [31:0] a;
		input [31:0] b;
		reg [32:0] s;
		reg lts;
		reg ltu;
		reg [31:0] sr;
		begin
			s = ({1'b0, a} + {1'b0, (d[10] ? ~b : b)}) + {32'b00000000000000000000000000000000, d[10]};
			ltu = !s[32];
			lts = (a[31] ^ b[31] ? a[31] : s[31]);
			sr = (d[5] ? $unsigned($signed(a) >>> b[4:0]) : a >> b[4:0]);
			alu = (((((((({32 {d[0]}} & s[31:0]) | ({32 {d[1]}} & {31'b0000000000000000000000000000000, lts})) | ({32 {d[2]}} & {31'b0000000000000000000000000000000, ltu})) | ({32 {d[3]}} & (a << b[4:0]))) | ({32 {d[4] | d[5]}} & sr)) | ({32 {d[6]}} & (a ^ b))) | ({32 {d[7]}} & (a | b))) | ({32 {d[8]}} & (a & b))) | ({32 {d[9]}} & b);
		end
	endfunction
	reg rr0_v;
	reg [7:0] rr0_brm;
	always @(posedge clk) begin
		if (rst)
			rr0_v <= 1'b0;
		else
			rr0_v <= iss0_v && !killed(iss0_brm);
		rr0_pay <= iss0_pay;
		rr0_brm <= okclr(iss0_brm);
		rr0_rob <= iss0_rob;
	end
	assign prf_ra[0+:6] = rr0_pay[29:24];
	assign prf_ra[6+:6] = rr0_pay[23:18];
	assign prf_ra_n[0+:6] = iss0_pay[29:24];
	assign prf_ra_n[6+:6] = iss0_pay[23:18];
	wire [107:0] rr0_brt = brt[rr0_pay[10:8]];
	reg ex0_v;
	reg [38:0] ex0_pay;
	reg [7:0] ex0_brm;
	reg [4:0] ex0_rob;
	reg [31:0] ex0_a;
	reg [31:0] ex0_b;
	reg [1:0] ex0_sa;
	reg [1:0] ex0_sb;
	reg [107:0] ex0_brt;
	reg [31:0] ex0_pc4;
	reg [10:0] ex0_d;
	// R69b: preserved copy of ex0_d; gives wb_dm0 its own ALU result logic.
	(* syn_preserve = 1 *) reg [10:0] ex0_dm;
	reg ex0_ne_seq;
	reg ex0_ne_tgt;
	wire [31:0] rr0_pc4 = rr0_brt[107:76] + 32'd4;
	always @(posedge clk) begin
		if (rst)
			ex0_v <= 1'b0;
		else
			ex0_v <= rr0_v && !killed(rr0_brm);
		ex0_pay <= rr0_pay;
		ex0_brm <= okclr(rr0_brm);
		ex0_rob <= rr0_rob;
		ex0_a <= rrval(rr0_pay[29:24], prf_rd[0+:32]);
		ex0_b <= (rr0_pay[30] ? imm_rd[0] : rrval(rr0_pay[23:18], prf_rd[32+:32]));
		ex0_sa <= latesel(rr0_pay[29:24]);
		ex0_sb <= (rr0_pay[30] ? 2'b00 : latesel(rr0_pay[23:18]));
		ex0_d <= aludec(rr0_pay[34:31]);
		ex0_dm <= aludec(rr0_pay[34:31]);
		ex0_brt <= rr0_brt;
		ex0_pc4 <= rr0_pc4;
		ex0_ne_seq <= rr0_brt[75:44] != rr0_pc4;
		ex0_ne_tgt <= rr0_brt[75:44] != rr0_brt[43:12];
	end
	wire ex0_live = ex0_v && !killed(ex0_brm);
	wire [31:0] a0 = exval(ex0_sa, ex0_a);
	wire [31:0] b0 = exval(ex0_sb, ex0_b);
	wire ex0_isbr = ex0_pay[3:1] == 3'd1;
	wire ex0_jalr = ex0_pay[4];
	wire [2:0] bf3 = ex0_pay[33:31];
	reg btaken;
	always @(*) begin
		if (_sv2v_0)
			;
		case (bf3)
			3'd0: btaken = a0 == b0;
			3'd1: btaken = a0 != b0;
			3'd4: btaken = $signed(a0) < $signed(b0);
			3'd5: btaken = $signed(a0) >= $signed(b0);
			3'd6: btaken = a0 < b0;
			default: btaken = a0 >= b0;
		endcase
	end
	wire [31:0] jtgt = (a0 + ex0_brt[43:12]) & ~32'd1;
	wire [31:0] btgt = (ex0_jalr ? jtgt : ex0_brt[43:12]);
	wire br_taken = ex0_jalr || btaken;
	wire [31:0] br_next = (br_taken ? btgt : ex0_pc4);
	wire br_mis_align = br_taken && btgt[1];
	wire br_mis = !br_mis_align && (ex0_jalr ? jtgt != ex0_brt[75:44] : (btaken ? ex0_ne_tgt : ex0_ne_seq));
	wire [31:0] alu0 = alu(ex0_d, a0, b0);
	assign ex0_prod = ex0_live && ex0_pay[11];
	assign ex0_ppd = ex0_pay[17:12];
	reg res_v;
	reg res_mis;
	reg res_cbr;
	reg res_taken;
	reg [2:0] res_tag;
	reg [31:0] res_next;
	reg [31:0] res_pc;
	reg [3:0] res_biq;
	reg [1:0] res_k;
	reg [4:0] res_rob;
	reg res_jalr;
	reg res_exc;
	always @(posedge clk) begin
		if (rst)
			res_v <= 1'b0;
		else
			res_v <= ex0_live && ex0_isbr;
		res_mis <= br_mis;
		res_cbr <= !ex0_jalr;
		res_taken <= br_taken;
		res_tag <= ex0_pay[10:8];
		res_next <= br_next;
		res_pc <= ex0_brt[107:76];
		res_biq <= ex0_brt[11:8];
		res_k <= ex0_brt[7:6];
		res_rob <= ex0_brt[4:0];
		res_jalr <= ex0_jalr;
		res_exc <= br_mis_align;
	end
	assign br_kill = (res_v && res_mis) && !flush;
	assign br_kill_tag = res_tag;
	assign br_ok = (res_v && !res_mis) && !flush;
	assign br_ok_tag = res_tag;
	assign mis_v = br_kill;
	assign mis_pc = res_next;
	assign mis_biq = res_biq;
	assign mis_k = res_k;
	assign mis_cbr = res_cbr;
	assign mis_taken = res_taken;
	assign ib_train = (res_v && res_jalr) && !flush;
	assign ib_pc = res_pc;
	assign ib_target = res_next;
	reg rr1_v;
	reg [7:0] rr1_brm;
	always @(posedge clk) begin
		if (rst)
			rr1_v <= 1'b0;
		else
			rr1_v <= iss1_v && !killed(iss1_brm);
		rr1_pay <= iss1_pay;
		rr1_brm <= okclr(iss1_brm);
		rr1_rob <= iss1_rob;
	end
	assign prf_ra[12+:6] = rr1_pay[29:24];
	assign prf_ra[18+:6] = rr1_pay[23:18];
	assign prf_ra_n[12+:6] = iss1_pay[29:24];
	assign prf_ra_n[18+:6] = iss1_pay[23:18];
	reg ex1_v;
	reg [38:0] ex1_pay;
	reg [7:0] ex1_brm;
	reg [4:0] ex1_rob;
	reg [31:0] ex1_a;
	reg [31:0] ex1_b;
	reg [1:0] ex1_sa;
	reg [1:0] ex1_sb;
	reg [10:0] ex1_d;
	// R69b: preserved copy of ex1_d; gives wb_dm1 its own ALU result logic.
	(* syn_preserve = 1 *) reg [10:0] ex1_dm;
	always @(posedge clk) begin
		if (rst)
			ex1_v <= 1'b0;
		else
			ex1_v <= rr1_v && !killed(rr1_brm);
		ex1_pay <= rr1_pay;
		ex1_brm <= okclr(rr1_brm);
		ex1_rob <= rr1_rob;
		ex1_a <= rrval(rr1_pay[29:24], prf_rd[64+:32]);
		ex1_b <= (rr1_pay[30] ? imm_rd[1] : rrval(rr1_pay[23:18], prf_rd[96+:32]));
		ex1_sa <= latesel(rr1_pay[29:24]);
		ex1_sb <= (rr1_pay[30] ? 2'b00 : latesel(rr1_pay[23:18]));
		ex1_d <= (rr1_v && (rr1_pay[3:1] != 3'd4) ? aludec(rr1_pay[34:31]) : 11'b00000000000);
		ex1_dm <= (rr1_v && (rr1_pay[3:1] != 3'd4) ? aludec(rr1_pay[34:31]) : 11'b00000000000);
	end
	wire ex1_live = ex1_v && !killed(ex1_brm);
	wire [31:0] a1 = exval(ex1_sa, ex1_a);
	wire [31:0] b1 = exval(ex1_sb, ex1_b);
	wire ex1_ismul = ex1_pay[3:1] == 3'd4;
	wire [31:0] alu1 = alu(ex1_d, a1, b1);
	assign ex1_prod = (ex1_live && !ex1_ismul) && ex1_pay[11];
	assign ex1_ppd = ex1_pay[17:12];
	function automatic [31:0] poly16;
		input [15:0] x;
		input [15:0] y;
		reg [31:0] acc;
		begin
			acc = 32'b00000000000000000000000000000000;
			begin : sv2v_autoblock_3
				reg signed [31:0] i;
				for (i = 0; i < 16; i = i + 1)
					if (y[i])
						acc = acc ^ ({16'b0000000000000000, x} << i);
			end
			poly16 = acc;
		end
	endfunction
	wire mul_go = ex1_live && ex1_ismul;
	reg mo_v;
	reg mo_wr;
	reg [2:0] mo_op;
	reg [5:0] mo_pd;
	reg [4:0] mo_rob;
	reg [7:0] mo_brm;
	reg [31:0] mo_a;
	reg [31:0] mo_b;
	always @(posedge clk) begin
		if (rst)
			mo_v <= 1'b0;
		else
			mo_v <= mul_go;
		mo_op <= ex1_pay[33:31];
		mo_pd <= ex1_pay[17:12];
		mo_wr <= ex1_pay[11];
		mo_rob <= ex1_rob;
		mo_brm <= okclr(ex1_brm);
		mo_a <= a1;
		mo_b <= b1;
	end
	wire mo_live = mo_v && !killed(mo_brm);
	wire mo_sa = (mo_op == 3'd1) || (mo_op == 3'd2);
	wire mo_sb = mo_op == 3'd1;
	wire signed [16:0] mah = {mo_sa & mo_a[31], mo_a[31:16]};
	wire signed [16:0] mbh = {mo_sb & mo_b[31], mo_b[31:16]};
	wire signed [16:0] mal = {1'b0, mo_a[15:0]};
	wire signed [16:0] mbl = {1'b0, mo_b[15:0]};
	reg m2_v;
	reg m2_wr;
	reg m2_cl;
	reg m2_hi;
	reg [2:0] m2_op;
	reg [5:0] m2_pd;
	reg [4:0] m2_rob;
	reg [7:0] m2_brm;
	reg signed [33:0] m2_ll;
	reg signed [33:0] m2_lh;
	reg signed [33:0] m2_hl;
	reg signed [33:0] m2_hh;
	reg [31:0] m2_cll;
	reg [31:0] m2_clh;
	reg [31:0] m2_chl;
	reg [31:0] m2_chh;
	always @(posedge clk) begin
		if (rst)
			m2_v <= 1'b0;
		else
			m2_v <= mo_live;
		m2_op <= mo_op;
		m2_cl <= mo_op[2];
		m2_hi <= !mo_op[2] && (mo_op != 3'd0);
		m2_pd <= mo_pd;
		m2_wr <= mo_wr;
		m2_rob <= mo_rob;
		m2_brm <= okclr(mo_brm);
		m2_ll <= mal * mbl;
		m2_lh <= mal * mbh;
		m2_hl <= mah * mbl;
		m2_hh <= mah * mbh;
		m2_cll <= poly16(mo_a[15:0], mo_b[15:0]);
		m2_clh <= poly16(mo_a[15:0], mo_b[31:16]);
		m2_chl <= poly16(mo_a[31:16], mo_b[15:0]);
		m2_chh <= poly16(mo_a[31:16], mo_b[31:16]);
	end
	wire m2_live = m2_v && !killed(m2_brm);
	wire [63:0] mx1 = {{14 {m2_lh[33]}}, m2_lh, 16'b0000000000000000};
	wire [63:0] mx2 = {{14 {m2_hl[33]}}, m2_hl, 16'b0000000000000000};
	wire [63:0] my = {m2_hh[31:0], m2_ll[31:0]};
	wire [63:0] mcs_s = (my ^ mx1) ^ mx2;
	wire [63:0] mcs_c = (((my & mx1) | (my & mx2)) | (mx1 & mx2)) << 1;
	wire [63:0] mprod = mcs_s + mcs_c;
	wire [63:0] clprod = (({32'b00000000000000000000000000000000, m2_cll} ^ {16'b0000000000000000, m2_clh, 16'b0000000000000000}) ^ {16'b0000000000000000, m2_chl, 16'b0000000000000000}) ^ {m2_chh, 32'b00000000000000000000000000000000};
	wire [31:0] m2_res = (m2_cl ? (m2_op == 3'd4 ? clprod[31:0] : (m2_op == 3'd5 ? clprod[62:31] : clprod[63:32])) : (m2_hi ? mprod[63:32] : mprod[31:0]));
	assign mul_prod = m2_live && m2_wr;
	assign mul_ppd = m2_pd;
	reg rrm_v;
	reg [7:0] rrm_brm;
	reg [7:0] rrm_sqm;
	reg [1:0] rrm_lat;
	reg [2:0] rrm_slot;
	always @(posedge clk) begin
		if (rst)
			rrm_v <= 1'b0;
		else
			rrm_v <= issm_v && !killed(issm_brm);
		rrm_pay <= issm_pay;
		rrm_brm <= okclr(issm_brm);
		rrm_rob <= issm_rob;
		rrm_lat <= issm_lat;
		rrm_sqm <= issm_sqm & ~sq_free;
		rrm_slot <= issm_slot;
	end
	assign prf_ra[24+:6] = rrm_pay[29:24];
	assign prf_ra[30+:6] = rrm_pay[23:18];
	wire csr_rd_a;
	wire [5:0] csr_rs1_preg;
	assign prf_ra_n[24+:6] = issm_pay[29:24] | (csr_rd_a ? csr_rs1_preg : 6'b000000);
	assign prf_ra_n[30+:6] = issm_pay[23:18];
	reg exm_v;
	reg [38:0] exm_pay;
	reg [7:0] exm_brm;
	reg [7:0] exm_sqm;
	reg [4:0] exm_rob;
	reg [1:0] exm_lat;
	reg [31:0] exm_a;
	// R69b: preserved copies of the LSU base operand for the tag adder only.
	(* syn_preserve = 1 *) reg [31:0] exm_a_t;
	// R70: second preserved copy, tag adder of way 1.
	(* syn_preserve = 1 *) reg [31:0] exm_a_t1;
	reg [31:0] exm_b;
	reg [1:0] exm_sa;
	(* syn_preserve = 1 *) reg [1:0] exm_sa_t;
	(* syn_preserve = 1 *) reg [1:0] exm_sa_t1;
	reg [1:0] exm_sb;
	reg [2:0] exm_slot;
	reg [11:0] exm_imm;
	always @(posedge clk) begin
		if (rst)
			exm_v <= 1'b0;
		else
			exm_v <= rrm_v && !killed(rrm_brm);
		exm_pay <= rrm_pay;
		exm_brm <= okclr(rrm_brm);
		exm_rob <= rrm_rob;
		exm_lat <= rrm_lat;
		exm_sqm <= rrm_sqm & ~sq_free;
		exm_slot <= rrm_slot;
		exm_a <= rrval(rrm_pay[29:24], prf_rd[128+:32]);
		exm_a_t <= rrval(rrm_pay[29:24], prf_rd[128+:32]);
		exm_a_t1 <= rrval(rrm_pay[29:24], prf_rd[128+:32]);
		exm_b <= rrval(rrm_pay[23:18], prf_rd[160+:32]);
		exm_sa <= latesel(rrm_pay[29:24]);
		exm_sa_t <= latesel(rrm_pay[29:24]);
		exm_sa_t1 <= latesel(rrm_pay[29:24]);
		exm_sb <= latesel(rrm_pay[23:18]);
		exm_imm <= imm_rd[2][11:0];
	end
	wire [31:0] am = exvalm(exm_sa, exm_a);
	wire [31:0] am_t = exvalm(exm_sa_t, exm_a_t);
	wire [31:0] am_t1 = exvalm(exm_sa_t1, exm_a_t1);
	wire [31:0] bm = exval(exm_sb, exm_b);
	wire st_done_v;
	wire st_exc;
	wire st_rpl;
	wire ld_wb_v;
	wire ld_done_v;
	wire ld_exc;
	wire ld_replay;
	wire ld_replay_io;
	wire ld_m_v;
	reg st_v_q;
	reg st_exc_q;
	reg st_rpl_q;
	reg [4:0] st_rob_q;
	reg [3:0] st_cause_q;
	reg [31:0] st_tval_q;
	wire [4:0] st_done_rob;
	wire [4:0] ld_done_rob;
	wire [3:0] st_cause;
	wire [3:0] ld_cause;
	wire [31:0] st_tval;
	wire [31:0] ld_tval;
	wire [31:0] ld_wb_data;
	wire [5:0] ld_wb_pd;
	wire [5:0] ld_m_pd;
	reg [1:0] sq_commit;
	wire dc_clean_req;
	wire dc_clean_done;
	wire lsu_clean_req;
	wire lsu_clean_done;
	o2_lsu #(
		.SETS(256),
		.RAM_BASE(RAM_BASE),
		.RAM_BYTES(RAM_BYTES)
	) lsu(
		.clk(clk),
		.rst(rst),
		.sq_alloc(sq_alloc),
		.sq_tail(sq_tail),
		.sq_count(sq_count),
		.sq_valid(sq_valid),
		.sq_issued(sq_issued),
		.sq_free(sq_free),
		.sq_empty(sq_empty),
		.sq_room(sq_room),
		.spec_ok(spec_ok),
		.md_viol(md_viol),
		.perf_ld_acc(pf_lda),
		.perf_ld_miss(pf_ldm),
		.ex_v(exm_v),
		.ex_store(exm_pay[3:1] == 3'd3),
		.ex_op(exm_pay[33:31]),
		.ex_base(am),
		.ex_base_t(am_t),
		.ex_base_t1(am_t1),
		.ex_sdata(bm),
		.ex_imm(exm_imm),
		.ex_pd(exm_pay[17:12]),
		.ex_rob(exm_rob),
		.ex_sqidx(exm_pay[7:5]),
		.ex_sqm(exm_sqm),
		.ex_brm(exm_brm),
		.ex_head(exm_lat == 2'd3),
		.ex_slot(exm_slot),
		.st_done_v(st_done_v),
		.st_done_rob(st_done_rob),
		.st_exc(st_exc),
		.st_cause(st_cause),
		.st_tval(st_tval),
		.st_replay(st_rpl),
		.bus_err_v(bus_err_v),
		.bus_err_wb(bus_err_wb),
		.bus_err_addr(bus_err_addr),
		.ld_wb_v(ld_wb_v),
		.ld_wb_pd(ld_wb_pd),
		.ld_wb_data(ld_wb_data),
		.ld_done_v(ld_done_v),
		.ld_done_rob(ld_done_rob),
		.ld_exc(ld_exc),
		.ld_cause(ld_cause),
		.ld_tval(ld_tval),
		.ld_replay(ld_replay),
		.ld_replay_io(ld_replay_io),
		.ld_m_v(ld_m_v),
		.ld_m_pd(ld_m_pd),
		.ext_done(ext_done),
		.slow_busy(slow_busy),
		.sq_commit(sq_commit),
		.flush(flush),
		.br_kill(br_kill),
		.br_kill_tag(br_kill_tag),
		.br_kill_sqtail(ckpt_sq[br_kill_tag]),
		.br_ok(br_ok),
		.br_ok_tag(br_ok_tag),
		.clean_req(lsu_clean_req),
		.clean_done(lsu_clean_done),
		.io_req_v(io_req_v),
		.io_req_rdy(io_req_rdy),
		.io_addr(io_addr),
		.io_write(io_write),
		.io_be(io_be),
		.io_wdata(io_wdata),
		.io_rsp_v(io_rsp_v),
		.io_rdata(io_rdata),
		.io_rsp_err(io_rsp_err),
		.cmd_valid(dc_cmd_valid),
		.cmd_ready(dc_cmd_ready),
		.cmd_write(dc_cmd_write),
		.cmd_addr(dc_cmd_addr),
		.cmd_len(dc_cmd_len),
		.w_valid(dc_w_valid),
		.w_ready(dc_w_ready),
		.w_data(dc_w_data),
		.w_be(dc_w_be),
		.w_last(dc_w_last),
		.r_valid(dc_r_valid),
		.r_ready(dc_r_ready),
		.r_data(dc_r_data),
		.r_error(dc_r_error),
		.r_last(dc_r_last)
	);
	assign lsu_clean_req = dc_clean_req || ext_clean_req;
	assign dc_clean_done = lsu_clean_done;
	assign ext_clean_done = lsu_clean_done;
	assign ld_prod = ld_m_v && ld_wb_v;
	always @(posedge clk) begin
		if (rst)
			st_v_q <= 1'b0;
		else
			st_v_q <= st_done_v && !flush;
		st_rob_q <= st_done_rob;
		st_exc_q <= st_exc;
		st_rpl_q <= st_rpl;
		st_cause_q <= st_cause;
		st_tval_q <= st_tval;
	end
	assign ld_ppd = ld_m_pd;
	assign slow_pend = (slow_busy || (rrm_v && (rrm_lat == 2'd3))) || (exm_v && (exm_lat == 2'd3));
	assign data_idle = sq_empty && !slow_busy;
	wire csr_wb_v;
	wire [5:0] csr_wb_pd;
	wire [31:0] csr_wb_data;
	always @(posedge clk) begin
		if (rst) begin : sv2v_autoblock_4
			reg signed [31:0] i;
			for (i = 0; i < 3; i = i + 1)
				wb_v[i] <= 1'b0;
		end
		else begin
			wb_v[0] <= ex0_prod;
			wb_v[1] <= ex1_prod || (mul_prod && !flush);
			wb_v[2] <= (ld_wb_v && !flush) || csr_wb_v;
		end
		wb_pd[0] <= ex0_ppd;
		wb_d[0] <= (ex0_isbr ? ex0_pc4 : alu0);
		wb_pd[1] <= (mul_prod ? mul_ppd : ex1_ppd);
		wb_d[1] <= alu1 | ({32 {mul_prod}} & m2_res);
		wb_pd[2] <= (csr_wb_v ? csr_wb_pd : ld_wb_pd);
		wb_d[2] <= (csr_wb_v ? csr_wb_data : ld_wb_data);
		wb_dm0 <= (ex0_isbr ? ex0_pc4 : alu(ex0_dm, a0, b0));
		wb_dm1 <= alu(ex1_dm, a1, b1) | ({32 {mul_prod}} & m2_res);
		wb_dm2 <= (csr_wb_v ? csr_wb_data : ld_wb_data);
	end
	wire [1:0] cm_wr_r;
	wire [1:0] sq_commit_r;
	wire [4:0] cm_rd0_r;
	wire [4:0] cm_rd1_r;
	wire [5:0] cm_pdst0_r;
	wire [5:0] cm_pdst1_r;
	wire [5:0] cm_pold0_r;
	wire [5:0] cm_pold1_r;
	wire cmt_br_valid_r;
	wire cmt_is_cbr_r;
	wire cmt_taken_r;
	wire [31:0] cmt_pc_r;
	wire [3:0] cmt_biq_r;
	always @(posedge clk) begin
		if (rst) begin
			cm_wr <= 2'b00;
			sq_commit <= 2'b00;
			cmt_br_valid <= 1'b0;
		end
		else begin
			cm_wr <= cm_wr_r;
			sq_commit <= sq_commit_r;
			cmt_br_valid <= cmt_br_valid_r;
		end
		cm_rd0 <= cm_rd0_r;
		cm_rd1 <= cm_rd1_r;
		cm_pdst0 <= cm_pdst0_r;
		cm_pdst1 <= cm_pdst1_r;
		cm_pold0 <= cm_pold0_r;
		cm_pold1 <= cm_pold1_r;
		cmt_is_cbr <= cmt_is_cbr_r;
		cmt_taken <= cmt_taken_r;
		cmt_pc <= cmt_pc_r;
		cmt_biq <= cmt_biq_r;
	end
	wire [5:0] csr_rs1_preg_n;
	o2_rob #(.RESET_PC(RESET_PC)) rob(
		.clk(clk),
		.rst(rst),
		.dv(rob_dv),
		.e0(rob_e0),
		.e1(rob_e1),
		.tail(rob_tail),
		.count(rob_count),
		.room(rob_room),
		.empty(rob_empty),
		.head_idx(rob_head),
		.c0_v(ex0_live && !ex0_isbr),
		.c0_rob(ex0_rob),
		.c5_v(res_v),
		.c5_rob(res_rob),
		.c5_exc(res_exc),
		.c5_tval(res_next),
		.c5_taken(res_taken),
		.c1_v(ex1_live && !ex1_ismul),
		.c1_rob(ex1_rob),
		.c2_v(m2_live),
		.c2_rob(m2_rob),
		.c3_v(st_v_q),
		.c3_rob(st_rob_q),
		.c3_exc(st_exc_q),
		.c3_cause(st_cause_q),
		.c3_tval(st_tval_q),
		.c3_replay(st_rpl_q),
		.c4_v(ld_done_v),
		.c4_rob(ld_done_rob),
		.c4_exc(ld_exc),
		.c4_cause(ld_cause),
		.c4_tval(ld_tval),
		.c4_replay(ld_replay),
		.c4_replay_io(ld_replay_io),
		.br_kill(br_kill),
		.br_kill_rob(res_rob),
		.cm_wr(cm_wr_r),
		.cm_rd0(cm_rd0_r),
		.cm_rd1(cm_rd1_r),
		.cm_pdst0(cm_pdst0_r),
		.cm_pdst1(cm_pdst1_r),
		.cm_pold0(cm_pold0_r),
		.cm_pold1(cm_pold1_r),
		.sq_commit(sq_commit_r),
		.cmt_br_valid(cmt_br_valid_r),
		.cmt_is_cbr(cmt_is_cbr_r),
		.cmt_taken(cmt_taken_r),
		.cmt_pc(cmt_pc_r),
		.cmt_biq(cmt_biq_r),
		.flush(flush),
		.flush_pc(flush_pc),
		.replay_set(replay_set),
		.replay_pc(replay_pc),
		.fetch_stop(fetch_stop),
		.md_set(md_set),
		.md_viol(md_viol),
		.csr_rs1_preg(csr_rs1_preg),
		.csr_rs1_preg_n(csr_rs1_preg_n),
		.csr_rs1_bank(csr_rs1_bank),
		.csr_rd_a(csr_rd_a),
		.csr_rd_b(csr_rd_b),
		.csr_rs1_value(prf_rd[128+:32]),
		.csr_wb_v(csr_wb_v),
		.csr_wb_pd(csr_wb_pd),
		.csr_wb_data(csr_wb_data),
		.irq_software(irq_software),
		.irq_timer(irq_timer),
		.irq_external(irq_external),
		.sq_empty(sq_empty),
		.slow_busy(slow_pend),
		.dc_clean_req(dc_clean_req),
		.dc_clean_done(dc_clean_done),
		.ic_inv(ic_inv),
		.ic_busy(ic_busy),
		.tr_v(tr_v),
		.tr_pc0(tr_pc0),
		.tr_pc1(tr_pc1),
		.tr_insn0(tr_insn0),
		.tr_insn1(tr_insn1),
		.tr_wr0(tr_wr0),
		.tr_wr1(tr_wr1),
		.tr_rd0(tr_rd0),
		.tr_rd1(tr_rd1),
		.tr_pd0(tr_pd0),
		.tr_pd1(tr_pd1),
		.tr_trap(tr_trap),
		.tr_irq(tr_irq),
		.tr_cause(tr_cause),
		.tr_epc(tr_epc),
		.tr_csr_old(tr_csr_old),
		.minstret_o(minstret),
		.mcycle_o(mcycle)
	);
	initial _sv2v_0 = 0;
endmodule
module o2_soc (
	clk,
	rst,
	irq_external_in,
	clean_req,
	clean_done,
	data_idle,
	uart_tx,
	gpio_out,
	exit_valid,
	exit_code,
	m_cmd_valid,
	m_cmd_ready,
	m_cmd_write,
	m_cmd_addr,
	m_cmd_len,
	m_w_valid,
	m_w_ready,
	m_w_data,
	m_w_be,
	m_w_last,
	m_r_valid,
	m_r_ready,
	m_r_data,
	m_r_error,
	m_r_last,
	ext_req_valid,
	ext_req_ready,
	ext_req_addr,
	ext_req_write,
	ext_req_be,
	ext_req_wdata,
	ext_rsp_valid,
	ext_rsp_ready,
	ext_rsp_rdata,
	ext_rsp_error,
	tr_v,
	tr_pc0,
	tr_pc1,
	tr_insn0,
	tr_insn1,
	tr_wr0,
	tr_wr1,
	tr_rd0,
	tr_rd1,
	tr_pd0,
	tr_pd1,
	tr_trap,
	tr_irq,
	tr_cause,
	tr_epc,
	tr_csr_old,
	prf_we,
	prf_wa,
	prf_wd,
	mon_io_rd_v,
	mon_io_addr
);
	parameter integer UART_DIVISOR = 32'h0000057e;
	parameter [31:0] RESET_PC = 32'h80000000;
	parameter [31:0] RAM_BASE = 32'h80000000;
	parameter integer RAM_BYTES = 131072;
	parameter integer EXT_MMIO = 0;
	parameter integer PERF = 1;
	input wire clk;
	input wire rst;
	input wire irq_external_in;
	input wire clean_req;
	output wire clean_done;
	output wire data_idle;
	output wire uart_tx;
	output wire [31:0] gpio_out;
	output reg exit_valid;
	output reg [31:0] exit_code;
	output wire m_cmd_valid;
	input wire m_cmd_ready;
	output wire m_cmd_write;
	output wire [31:0] m_cmd_addr;
	output wire [7:0] m_cmd_len;
	output wire m_w_valid;
	input wire m_w_ready;
	output wire [31:0] m_w_data;
	output wire [3:0] m_w_be;
	output wire m_w_last;
	input wire m_r_valid;
	output wire m_r_ready;
	input wire [31:0] m_r_data;
	input wire m_r_error;
	input wire m_r_last;
	output wire ext_req_valid;
	input wire ext_req_ready;
	output wire [31:0] ext_req_addr;
	output wire ext_req_write;
	output wire [3:0] ext_req_be;
	output wire [31:0] ext_req_wdata;
	input wire ext_rsp_valid;
	output wire ext_rsp_ready;
	input wire [31:0] ext_rsp_rdata;
	input wire ext_rsp_error;
	output wire [1:0] tr_v;
	output wire [31:0] tr_pc0;
	output wire [31:0] tr_pc1;
	output wire [31:0] tr_insn0;
	output wire [31:0] tr_insn1;
	output wire tr_wr0;
	output wire tr_wr1;
	output wire [4:0] tr_rd0;
	output wire [4:0] tr_rd1;
	output wire [5:0] tr_pd0;
	output wire [5:0] tr_pd1;
	output wire tr_trap;
	output wire tr_irq;
	output wire [31:0] tr_cause;
	output wire [31:0] tr_epc;
	output wire [31:0] tr_csr_old;
	output wire [3:0] prf_we;
	output wire [23:0] prf_wa;
	output wire [127:0] prf_wd;
	output wire mon_io_rd_v;
	output wire [31:0] mon_io_addr;
	wire irq_sw;
	wire irq_tm;
	wire irq_ex;
	wire c_req_v;
	wire c_req_rdy;
	wire c_write;
	wire io_rsp_v;
	wire io_rsp_err;
	wire [31:0] c_addr;
	wire [31:0] c_wdata;
	wire [31:0] io_rdata;
	wire [3:0] c_be;
	reg io_req_v;
	reg io_write;
	reg [31:0] io_addr;
	reg [31:0] io_wdata;
	reg [3:0] io_be;
	wire io_req_rdy;
	assign c_req_rdy = !io_req_v;
	always @(posedge clk) begin
		if (rst)
			io_req_v <= 1'b0;
		else if (!io_req_v && c_req_v)
			io_req_v <= 1'b1;
		else if (io_req_v && io_req_rdy)
			io_req_v <= 1'b0;
		if (!io_req_v) begin
			io_addr <= c_addr;
			io_write <= c_write;
			io_be <= c_be;
			io_wdata <= c_wdata;
		end
	end
	wire ic_cmd_valid;
	wire ic_cmd_ready;
	wire ic_cmd_write;
	wire ic_w_valid;
	wire ic_w_ready;
	wire ic_w_last;
	wire ic_r_valid;
	wire ic_r_ready;
	wire ic_r_error;
	wire ic_r_last;
	wire [31:0] ic_cmd_addr;
	wire [31:0] ic_w_data;
	wire [31:0] ic_r_data;
	wire [7:0] ic_cmd_len;
	wire [3:0] ic_w_be;
	wire dc_cmd_valid;
	wire dc_cmd_ready;
	wire dc_cmd_write;
	wire dc_w_valid;
	wire dc_w_ready;
	wire dc_w_last;
	wire dc_r_valid;
	wire dc_r_ready;
	wire dc_r_error;
	wire dc_r_last;
	wire [31:0] dc_cmd_addr;
	wire [31:0] dc_w_data;
	wire [31:0] dc_r_data;
	wire [7:0] dc_cmd_len;
	wire [3:0] dc_w_be;
	wire [63:0] minstret;
	wire [63:0] mcycle;
	wire [4:0] perf_ev;
	wire bus_err_v;
	wire bus_err_wb;
	wire [31:0] bus_err_addr;
	o2_core #(
		.RESET_PC(RESET_PC),
		.RAM_BASE(RAM_BASE),
		.RAM_BYTES(RAM_BYTES)
	) core(
		.clk(clk),
		.rst(rst),
		.irq_software(irq_sw),
		.irq_timer(irq_tm),
		.irq_external(irq_ex),
		.ext_clean_req(clean_req),
		.ext_clean_done(clean_done),
		.data_idle(data_idle),
		.io_req_v(c_req_v),
		.io_req_rdy(c_req_rdy),
		.io_addr(c_addr),
		.io_write(c_write),
		.io_be(c_be),
		.io_wdata(c_wdata),
		.io_rsp_v(io_rsp_v),
		.io_rdata(io_rdata),
		.io_rsp_err(io_rsp_err),
		.ic_cmd_valid(ic_cmd_valid),
		.ic_cmd_ready(ic_cmd_ready),
		.ic_cmd_write(ic_cmd_write),
		.ic_cmd_addr(ic_cmd_addr),
		.ic_cmd_len(ic_cmd_len),
		.ic_w_valid(ic_w_valid),
		.ic_w_ready(ic_w_ready),
		.ic_w_data(ic_w_data),
		.ic_w_be(ic_w_be),
		.ic_w_last(ic_w_last),
		.ic_r_valid(ic_r_valid),
		.ic_r_ready(ic_r_ready),
		.ic_r_data(ic_r_data),
		.ic_r_error(ic_r_error),
		.ic_r_last(ic_r_last),
		.dc_cmd_valid(dc_cmd_valid),
		.dc_cmd_ready(dc_cmd_ready),
		.dc_cmd_write(dc_cmd_write),
		.dc_cmd_addr(dc_cmd_addr),
		.dc_cmd_len(dc_cmd_len),
		.dc_w_valid(dc_w_valid),
		.dc_w_ready(dc_w_ready),
		.dc_w_data(dc_w_data),
		.dc_w_be(dc_w_be),
		.dc_w_last(dc_w_last),
		.dc_r_valid(dc_r_valid),
		.dc_r_ready(dc_r_ready),
		.dc_r_data(dc_r_data),
		.dc_r_error(dc_r_error),
		.dc_r_last(dc_r_last),
		.tr_v(tr_v),
		.tr_pc0(tr_pc0),
		.tr_pc1(tr_pc1),
		.tr_insn0(tr_insn0),
		.tr_insn1(tr_insn1),
		.tr_wr0(tr_wr0),
		.tr_wr1(tr_wr1),
		.tr_rd0(tr_rd0),
		.tr_rd1(tr_rd1),
		.tr_pd0(tr_pd0),
		.tr_pd1(tr_pd1),
		.tr_trap(tr_trap),
		.tr_irq(tr_irq),
		.tr_cause(tr_cause),
		.tr_epc(tr_epc),
		.tr_csr_old(tr_csr_old),
		.prf_we_o(prf_we),
		.prf_wa_o(prf_wa),
		.prf_wd_o(prf_wd),
		.minstret(minstret),
		.mcycle(mcycle),
		.perf_ev(perf_ev),
		.bus_err_v(bus_err_v),
		.bus_err_wb(bus_err_wb),
		.bus_err_addr(bus_err_addr)
	);
	localparam [31:0] BEU_BASE = 32'h10006000;
	wire sel_beu = (io_addr & 32'hfffff000) == BEU_BASE;
	reg beu_pend;
	reg beu_wb;
	reg beu_ovf;
	reg [31:0] beu_addr;
	reg [31:0] beu_rd;
	always @(posedge clk) begin
		if (rst) begin
			beu_pend <= 1'b0;
			beu_ovf <= 1'b0;
			beu_wb <= 1'b0;
			beu_addr <= 32'b00000000000000000000000000000000;
		end
		else begin : sv2v_autoblock_1
			reg clr;
			clr = (((io_req_v && io_req_rdy) && sel_beu) && io_write) && !io_addr[2];
			if (clr) begin
				beu_pend <= 1'b0;
				beu_ovf <= 1'b0;
			end
			if (bus_err_v) begin
				if (!beu_pend || clr) begin
					beu_pend <= 1'b1;
					beu_wb <= bus_err_wb;
					beu_addr <= bus_err_addr;
				end
				else
					beu_ovf <= 1'b1;
			end
		end
		if (io_req_v && io_req_rdy)
			beu_rd <= (io_addr[2] ? beu_addr : {29'b00000000000000000000000000000, beu_ovf, beu_wb, beu_pend});
	end
	localparam [31:0] PERF_BASE = 32'h10003000;
	reg [63:0] pc_cnt [0:6];
	reg perf_en;
	reg [31:0] perf_rd;
	wire sel_perf = (PERF != 0) && ((io_addr & 32'hfffff000) == PERF_BASE);
	generate
		if (PERF != 0) begin : g_perf
			always @(posedge clk) begin
				if (rst) begin
					perf_en <= 1'b1;
					begin : sv2v_autoblock_2
						reg signed [31:0] i;
						for (i = 0; i < 7; i = i + 1)
							pc_cnt[i] <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
					end
				end
				else begin
					if ((((io_req_v && io_req_rdy) && sel_perf) && io_write) && (io_addr[5:2] == 4'd0))
						perf_en <= io_wdata[0];
					if (perf_en) begin
						pc_cnt[0] <= pc_cnt[0] + 64'd1;
						pc_cnt[1] <= (pc_cnt[1] + {63'b000000000000000000000000000000000000000000000000000000000000000, tr_v[0]}) + {63'b000000000000000000000000000000000000000000000000000000000000000, tr_v[1]};
						begin : sv2v_autoblock_3
							reg signed [31:0] i;
							for (i = 0; i < 5; i = i + 1)
								if (perf_ev[i])
									pc_cnt[2 + i] <= pc_cnt[2 + i] + 64'd1;
						end
					end
				end
				if (io_req_v && io_req_rdy) begin
					if (io_addr[5:3] == 3'd0)
						perf_rd <= {31'b0000000000000000000000000000000, perf_en};
					else
						perf_rd <= (io_addr[2] ? pc_cnt[io_addr[5:3] - 3'd1][63:32] : pc_cnt[io_addr[5:3] - 3'd1][31:0]);
				end
			end
		end
		else begin : g_noperf
			wire [32:1] sv2v_tmp_CFB3A;
			assign sv2v_tmp_CFB3A = 32'b00000000000000000000000000000000;
			always @(*) perf_rd = sv2v_tmp_CFB3A;
			wire [1:1] sv2v_tmp_0D297;
			assign sv2v_tmp_0D297 = 1'b0;
			always @(*) perf_en = sv2v_tmp_0D297;
		end
	endgenerate
	p2_burst_arbiter2 arbiter(
		.clk(clk),
		.rst(rst),
		.a_cmd_valid(ic_cmd_valid),
		.a_cmd_ready(ic_cmd_ready),
		.a_cmd_write(ic_cmd_write),
		.a_cmd_addr(ic_cmd_addr),
		.a_cmd_len(ic_cmd_len),
		.a_w_valid(ic_w_valid),
		.a_w_ready(ic_w_ready),
		.a_w_data(ic_w_data),
		.a_w_be(ic_w_be),
		.a_w_last(ic_w_last),
		.a_r_valid(ic_r_valid),
		.a_r_ready(ic_r_ready),
		.a_r_data(ic_r_data),
		.a_r_error(ic_r_error),
		.a_r_last(ic_r_last),
		.b_cmd_valid(dc_cmd_valid),
		.b_cmd_ready(dc_cmd_ready),
		.b_cmd_write(dc_cmd_write),
		.b_cmd_addr(dc_cmd_addr),
		.b_cmd_len(dc_cmd_len),
		.b_w_valid(dc_w_valid),
		.b_w_ready(dc_w_ready),
		.b_w_data(dc_w_data),
		.b_w_be(dc_w_be),
		.b_w_last(dc_w_last),
		.b_r_valid(dc_r_valid),
		.b_r_ready(dc_r_ready),
		.b_r_data(dc_r_data),
		.b_r_error(dc_r_error),
		.b_r_last(dc_r_last),
		.m_cmd_valid(m_cmd_valid),
		.m_cmd_ready(m_cmd_ready),
		.m_cmd_write(m_cmd_write),
		.m_cmd_addr(m_cmd_addr),
		.m_cmd_len(m_cmd_len),
		.m_w_valid(m_w_valid),
		.m_w_ready(m_w_ready),
		.m_w_data(m_w_data),
		.m_w_be(m_w_be),
		.m_w_last(m_w_last),
		.m_r_valid(m_r_valid),
		.m_r_ready(m_r_ready),
		.m_r_data(m_r_data),
		.m_r_error(m_r_error),
		.m_r_last(m_r_last)
	);
	wire sel_periph = (((io_addr & 32'hfffff000) == 32'h10000000) || ((io_addr & 32'hfffff000) == 32'h10001000)) || ((io_addr & 32'hfffff000) == 32'h10002000);
	wire sel_exit = io_addr == 32'h20000000;
	wire p_req_v;
	wire p_req_rdy;
	wire p_rsp_v;
	wire p_rsp_err;
	wire [31:0] p_rdata;
	reg pend;
	reg pend_periph;
	reg pend_err;
	reg pend_perf;
	reg pend_beu;
	reg pend_ext;
	wire sel_ext = ((((EXT_MMIO != 0) && !sel_periph) && !sel_exit) && !sel_perf) && !sel_beu;
	assign ext_req_valid = (io_req_v && sel_ext) && !pend;
	assign ext_req_addr = io_addr;
	assign ext_req_write = io_write;
	assign ext_req_be = io_be;
	assign ext_req_wdata = io_wdata;
	assign ext_rsp_ready = pend && pend_ext;
	assign p_req_v = (io_req_v && sel_periph) && !pend;
	assign io_req_rdy = !pend && (sel_periph ? p_req_rdy : (sel_ext ? ext_req_ready : 1'b1));
	assign io_rsp_v = pend && (pend_periph ? p_rsp_v : (pend_ext ? ext_rsp_valid : 1'b1));
	assign io_rdata = (pend_periph ? p_rdata : (pend_perf ? perf_rd : (pend_beu ? beu_rd : (pend_ext ? ext_rsp_rdata : 32'b00000000000000000000000000000000))));
	assign io_rsp_err = (pend_periph ? p_rsp_err : (pend_ext ? ext_rsp_error : pend_err));
	always @(posedge clk)
		if (rst) begin
			pend <= 1'b0;
			pend_periph <= 1'b0;
			pend_err <= 1'b0;
			pend_perf <= 1'b0;
			pend_beu <= 1'b0;
			pend_ext <= 1'b0;
			exit_valid <= 1'b0;
			exit_code <= 32'b00000000000000000000000000000000;
		end
		else begin
			if (io_rsp_v)
				pend <= 1'b0;
			if (io_req_v && io_req_rdy) begin
				pend <= 1'b1;
				pend_periph <= sel_periph;
				pend_perf <= sel_perf;
				pend_beu <= sel_beu;
				pend_ext <= sel_ext;
				pend_err <= (((!sel_periph && !sel_perf) && !sel_beu) && !sel_ext) && !((sel_exit && io_write) && (io_be == 4'hf));
				if ((sel_exit && io_write) && (io_be == 4'hf)) begin
					exit_valid <= 1'b1;
					exit_code <= io_wdata;
				end
			end
		end
	assign mon_io_rd_v = (io_req_v && io_req_rdy) && !io_write;
	assign mon_io_addr = io_addr;
	p2_peripherals #(
		.UART_BASE(32'h10000000),
		.GPIO_BASE(32'h10001000),
		.TIMER_BASE(32'h10002000),
		.UART_DIVISOR(UART_DIVISOR)
	) peripherals(
		.clk(clk),
		.rst(rst),
		.req_valid(p_req_v),
		.req_ready(p_req_rdy),
		.req_addr(io_addr),
		.req_write(io_write),
		.req_be(io_be),
		.req_wdata(io_wdata),
		.rsp_valid(p_rsp_v),
		.rsp_ready(1'b1),
		.rsp_rdata(p_rdata),
		.rsp_error(p_rsp_err),
		.uart_tx(uart_tx),
		.gpio_out(gpio_out),
		.external_irq(irq_external_in || beu_pend),
		.irq_software(irq_sw),
		.irq_timer(irq_tm),
		.irq_external(irq_ex)
	);
endmodule




`timescale 1ns/1ps
// The bridge acknowledges posted writes before DDR completes them. Delay each
// DDR write acknowledgement until an ordered read of its final line returns.
// This preserves the unchanged O2 FENCE.I/clean state machines' completion rule.
module fn_ddr_write_order(
    input wire clk, rst, output reg failed,
    input wire s_cmd_valid, output wire s_cmd_ready, input wire s_cmd_write,
    input wire [31:0] s_cmd_addr, input wire [7:0] s_cmd_len,
    input wire s_w_valid, output wire s_w_ready, input wire [31:0] s_w_data,
    input wire [3:0] s_w_be, input wire s_w_last,
    output wire s_r_valid, input wire s_r_ready, output wire [31:0] s_r_data,
    output wire s_r_error, s_r_last,
    output wire m_cmd_valid, input wire m_cmd_ready, output wire m_cmd_write,
    output wire [31:0] m_cmd_addr, output wire [7:0] m_cmd_len,
    output wire m_w_valid, input wire m_w_ready, output wire [31:0] m_w_data,
    output wire [3:0] m_w_be, output wire m_w_last,
    input wire m_r_valid, output wire m_r_ready, input wire [31:0] m_r_data,
    input wire m_r_error, m_r_last
);
    localparam IDLE=0, PASS=1, WRITE_ACK=2, DRAIN_CMD=3, DRAIN_RSP=4, ACK=5;
    reg [2:0] state;
    reg [31:0] last_addr;
    reg ack_error;
    assign s_cmd_ready = state == IDLE && m_cmd_ready;
    assign m_cmd_valid = state == DRAIN_CMD || (state == IDLE && s_cmd_valid);
    assign m_cmd_write = state == IDLE && s_cmd_write;
    assign m_cmd_addr = state == DRAIN_CMD ? last_addr : s_cmd_addr;
    assign m_cmd_len = state == DRAIN_CMD ? 8'd1 : s_cmd_len;
    assign m_w_valid = (state == PASS || state == WRITE_ACK) && s_w_valid;
    assign s_w_ready = (state == PASS || state == WRITE_ACK) && m_w_ready;
    assign m_w_data = s_w_data; assign m_w_be = s_w_be; assign m_w_last = s_w_last;
    assign s_r_valid = state == ACK || (state == PASS && m_r_valid);
    assign s_r_data = state == ACK ? 32'b0 : m_r_data;
    assign s_r_error = state == ACK ? ack_error : m_r_error;
    assign s_r_last = state == ACK || m_r_last;
    assign m_r_ready = state == WRITE_ACK || state == DRAIN_RSP || (state == PASS && s_r_ready);
    always @(posedge clk) begin
        if (rst) begin state <= IDLE; failed <= 0; ack_error <= 0; last_addr <= 0; end
        else case (state)
            IDLE: if (s_cmd_valid && m_cmd_ready) begin
                state <= s_cmd_write && s_cmd_addr >= 32'h80020000 ? WRITE_ACK : PASS;
                last_addr <= (s_cmd_addr + (({24'b0,s_cmd_len} - 1) << 2)) & 32'hffffffe0;
                ack_error <= 0;
            end
            PASS: if (m_r_valid && s_r_ready && m_r_last) state <= IDLE;
            WRITE_ACK: if (m_r_valid) begin
                ack_error <= m_r_error;
                if (!m_r_last) failed <= 1;
                if (m_r_last) state <= DRAIN_CMD;
            end
            DRAIN_CMD: if (m_cmd_ready) state <= DRAIN_RSP;
            DRAIN_RSP: if (m_r_valid) begin
                ack_error <= ack_error || m_r_error;
                if (m_r_error) failed <= 1;
                if (m_r_last) state <= ACK;
            end
            ACK: if (s_r_ready) state <= IDLE;
            default: begin state <= IDLE; failed <= 1; end
        endcase
    end
endmodule

module fn_view_fifo #(
    parameter DW = 38,
    parameter AW = 10
) (
    input  wire          wclk,
    input  wire          wrst,
    input  wire          wen,
    input  wire [DW-1:0] wdata,
    output reg           wfull,
    output reg  [AW:0]   wlevel,

    input  wire          rclk,
    input  wire          rrst,
    input  wire          ren,
    output reg  [DW-1:0] rdata,
    output reg           rempty
);
    function [AW:0] gray2bin;
        input [AW:0] g;
        integer k;
        begin
            gray2bin[AW] = g[AW];
            for (k = AW - 1; k >= 0; k = k - 1)
                gray2bin[k] = gray2bin[k + 1] ^ g[k];
        end
    endfunction

    (* syn_ramstyle="lut_ram" *) reg [DW-1:0] mem [0:(1 << AW) - 1];

    // ------------------------------------------------------------ write side
    reg  [AW:0] wbin, wgray;
    reg  [AW:0] rgray_s1, rgray_s2;
    reg  [AW:0] rbin_w;
    reg  [AW:0] rgray;
    wire        wpush   = wen & ~wfull;
    wire [AW:0] wbin_n  = wbin + {{AW{1'b0}}, wpush};
    wire [AW:0] wgray_n = (wbin_n >> 1) ^ wbin_n;

    always @(posedge wclk)
        if (wpush) mem[wbin[AW-1:0]] <= wdata;

    always @(posedge wclk) begin
        if (wrst) begin
            wbin     <= {(AW + 1){1'b0}};
            wgray    <= {(AW + 1){1'b0}};
            rgray_s1 <= {(AW + 1){1'b0}};
            rgray_s2 <= {(AW + 1){1'b0}};
            rbin_w   <= {(AW + 1){1'b0}};
            wfull    <= 1'b0;
            wlevel   <= {(AW + 1){1'b0}};
        end else begin
            wbin     <= wbin_n;
            wgray    <= wgray_n;
            rgray_s1 <= rgray;
            rgray_s2 <= rgray_s1;
            rbin_w   <= gray2bin(rgray_s2);
            wfull    <= (wgray_n == {~rgray_s2[AW:AW-1], rgray_s2[AW-2:0]});
            wlevel   <= wbin - rbin_w;
        end
    end

    // ------------------------------------------------------------ read side
    reg  [AW:0] rbin;
    reg  [AW:0] wgray_s1, wgray_s2;
    wire        rpop    = ren & ~rempty;
    wire [AW:0] rbin_n  = rbin + {{AW{1'b0}}, rpop};
    wire [AW:0] rgray_n = (rbin_n >> 1) ^ rbin_n;

    always @(posedge rclk)
        if (rpop) rdata <= mem[rbin[AW-1:0]];

    always @(posedge rclk) begin
        if (rrst) begin
            rbin     <= {(AW + 1){1'b0}};
            rgray    <= {(AW + 1){1'b0}};
            wgray_s1 <= {(AW + 1){1'b0}};
            wgray_s2 <= {(AW + 1){1'b0}};
            rempty   <= 1'b1;
        end else begin
            rbin     <= rbin_n;
            rgray    <= rgray_n;
            wgray_s1 <= wgray;
            wgray_s2 <= wgray_s1;
            rempty   <= (rgray_n == wgray_s2);
        end
    end
endmodule
module fn_view_overlay (
	clk,
	rst,
	de,
	vs,
	rgb_in,
	rgb_out,
	ovl_toggle,
	dot_en,
	seg_en,
	box_en,
	box0,
	box1,
	dots,
	segs
);
	parameter integer NDOT = 12;
	parameter integer NSEG = 12;
	parameter integer R = 5;
	input wire clk;
	input wire rst;
	input wire de;
	input wire vs;
	input wire [23:0] rgb_in;
	output wire [23:0] rgb_out;
	input wire ovl_toggle;
	input wire [NDOT - 1:0] dot_en;
	input wire [NSEG - 1:0] seg_en;
	input wire box_en;
	input wire [31:0] box0;
	input wire [31:0] box1;
	input wire [(32 * NDOT) - 1:0] dots;
	input wire [(160 * NSEG) - 1:0] segs;
	(* async_reg = "true" *) reg t1;
	(* async_reg = "true" *) reg t2;
	reg tseen;
	reg staged;
	reg [5:0] age;
	reg [NDOT - 1:0] st_dot_en;
	reg [NDOT - 1:0] a_dot_en;
	reg [NSEG - 1:0] st_seg_en;
	reg [NSEG - 1:0] a_seg_en;
	reg st_box_en;
	reg a_box_en;
	reg [31:0] st_box0;
	reg [31:0] st_box1;
	reg [31:0] a_box0;
	reg [31:0] a_box1;
	reg [(32 * NDOT) - 1:0] st_dots;
	reg [(32 * NDOT) - 1:0] a_dots;
	reg [(160 * NSEG) - 1:0] st_segs;
	reg [(160 * NSEG) - 1:0] a_segs;
	reg vs_q;
	reg de_q;
	wire frame_start = vs && !vs_q;
	always @(posedge clk)
		if (rst) begin
			age <= 0;
			t1 <= 0;
			t2 <= 0;
			tseen <= 0;
			staged <= 0;
			a_dot_en <= 0;
			a_seg_en <= 0;
			a_box_en <= 0;
		end
		else begin
			t1 <= ovl_toggle;
			t2 <= t1;
			if (frame_start && (age < 63))
				age <= age + 1'b1;
			if (frame_start && (age >= 18)) begin
				a_dot_en <= 0;
				a_seg_en <= 0;
				a_box_en <= 0;
			end
			if (t2 != tseen) begin
				age <= 0;
				tseen <= t2;
				staged <= 1;
				st_dot_en <= dot_en;
				st_seg_en <= seg_en;
				st_box_en <= box_en;
				st_box0 <= box0;
				st_box1 <= box1;
				st_dots <= dots;
				st_segs <= segs;
			end
			else if (frame_start && staged) begin
				staged <= 0;
				a_dot_en <= st_dot_en;
				a_seg_en <= st_seg_en;
				a_box_en <= st_box_en;
				a_box0 <= st_box0;
				a_box1 <= st_box1;
				a_dots <= st_dots;
				a_segs <= st_segs;
			end
		end
	reg signed [12:0] px;
	reg signed [12:0] py;
	always @(posedge clk) begin
		vs_q <= vs;
		de_q <= de;
		if (rst || vs) begin
			px <= 0;
			py <= 0;
		end
		else if (de)
			px <= px + 1'b1;
		else if (de_q) begin
			px <= 0;
			py <= py + 1'b1;
		end
	end
	wire line_end = de_q && !de;
	wire [NSEG - 1:0] seg_hit;
	genvar _gv_s_1;
	generate
		for (_gv_s_1 = 0; _gv_s_1 < NSEG; _gv_s_1 = _gv_s_1 + 1) begin : seg
			localparam s = _gv_s_1;
			wire signed [31:0] c00 = a_segs[160 * s+:32];
			wire signed [31:0] d00 = a_segs[(160 * s) + 32+:32];
			wire signed [15:0] dx = a_segs[(160 * s) + 64+:16];
			wire signed [15:0] dy = a_segs[(160 * s) + 80+:16];
			wire signed [31:0] lim = a_segs[(160 * s) + 96+:32];
			wire signed [31:0] len2 = a_segs[(160 * s) + 128+:32];
			reg signed [31:0] cl;
			reg signed [31:0] dl;
			reg signed [31:0] c;
			reg signed [31:0] d;
			always @(posedge clk)
				if (vs) begin
					cl <= c00;
					dl <= d00;
					c <= c00;
					d <= d00;
				end
				else if (de) begin
					c <= c + dy;
					d <= d + dx;
				end
				else if (line_end) begin
					cl <= cl - dx;
					dl <= dl + dy;
					c <= cl - dx;
					d <= dl + dy;
				end
			wire signed [31:0] ac = (c < 0 ? -c : c);
			wire signed [31:0] lim_half = lim >> 1;
			wire signed [31:0] lim_thick = lim_half + (lim_half << 1);
			assign seg_hit[s] = ((a_seg_en[s] && (ac <= lim_thick)) && (d >= 0)) && (d <= len2);
		end
	endgenerate

	function [7:0] square4; input [3:0] a; begin case(a)
	4'd0:square4=8'd0;
	4'd1:square4=8'd1;
	4'd2:square4=8'd4;
	4'd3:square4=8'd9;
	4'd4:square4=8'd16;
	4'd5:square4=8'd25;
	4'd6:square4=8'd36;
	4'd7:square4=8'd49;
	4'd8:square4=8'd64;
	4'd9:square4=8'd81;
	4'd10:square4=8'd100;
	4'd11:square4=8'd121;
	4'd12:square4=8'd144;
	4'd13:square4=8'd169;
	4'd14:square4=8'd196;
	4'd15:square4=8'd225;
	endcase end endfunction
	wire [NDOT - 1:0] dot_hit;
	genvar _gv_j_1;
	generate
		for (_gv_j_1 = 0; _gv_j_1 < NDOT; _gv_j_1 = _gv_j_1 + 1) begin : dot
			localparam j = _gv_j_1;
			wire signed [12:0] xd = {a_dots[(32 * j) + 11], a_dots[32 * j+:12]};
			wire signed [12:0] yd = {a_dots[(32 * j) + 27], a_dots[(32 * j) + 16+:12]};
			wire signed [13:0] ex = px - xd;
			wire signed [13:0] ey = py - yd;
			wire [13:0] ax = (ex < 0 ? -ex : ex);
			wire [13:0] ay = (ey < 0 ? -ey : ey);
			assign dot_hit[j] = ((a_dot_en[j] && (ax <= R)) && (ay <= R)) && (({1'b0,square4(ax[3:0])} + {1'b0,square4(ay[3:0])}) <= (R*R));
		end
	endgenerate
	wire signed [12:0] bx0 = {a_box0[11], a_box0[11:0]};
	wire signed [12:0] by0 = {a_box0[27], a_box0[27:16]};
	wire signed [12:0] bx1 = {a_box1[11], a_box1[11:0]};
	wire signed [12:0] by1 = {a_box1[27], a_box1[27:16]};
	wire in_x = (px >= (bx0 - 1)) && (px <= (bx1 + 1));
	wire in_y = (py >= (by0 - 1)) && (py <= (by1 + 1));
	wire near_x = ((px >= (bx0 - 1)) && (px <= bx0)) || ((px >= bx1) && (px <= (bx1 + 1)));
	wire near_y = ((py >= (by0 - 1)) && (py <= by0)) || ((py >= by1) && (py <= (by1 + 1)));
	wire box_hit = a_box_en && ((in_x && near_y) || (in_y && near_x));
	localparam [11:0] SEG_LEFT = 12'h306;
	localparam [11:0] SEG_RIGHT = 12'hc18;
	wire left_dot = |(dot_hit & {NDOT / 2 {2'b01}});
	wire right_dot = |(dot_hit & {NDOT / 2 {2'b10}});
	wire left_seg = |(seg_hit & SEG_LEFT);
	wire right_seg = |(seg_hit & SEG_RIGHT);
	wire any_seg = |seg_hit;
	assign rgb_out = (!de ? rgb_in : (left_dot ? 24'ha0ffff : (right_dot ? 24'hffd0a0 : (left_seg ? 24'h00e0ff : (right_seg ? 24'hff8000 : (any_seg ? 24'hf0f040 : (box_hit ? 24'h40ff40 : rgb_in)))))));
endmodule
module fn_camera_ddr_view (
	cam_clk,
	cam_rst,
	cam_valid,
	cam_sof,
	cam_pixel,
	pix_clk,
	pix_rst,
	mode,
	hs,
	vs,
	de,
	x,
	y,
	rgb,
	frame_valid,
	underflow,
	ddr_clk,
	ddr_rst,
	g_awaddr,
	g_araddr,
	g_awvalid,
	g_arvalid,
	g_awready,
	g_wready,
	g_arready,
	g_rvalid,
	g_wdata,
	g_rdata,
	g_wstrb,
	g_rlast,
	m_awaddr,
	m_araddr,
	m_arlen,
	m_awvalid,
	m_arvalid,
	m_awready,
	m_wready,
	m_arready,
	m_rvalid,
	m_rlast,
	m_wdata,
	m_rdata,
	m_wstrb,
	camera_drop,
	protocol_error
);
	parameter W = 1280;
	parameter H = 720;
	parameter FIFO_AW = 6;
	input wire cam_clk;
	input wire cam_rst;
	input wire cam_valid;
	input wire cam_sof;
	input wire [15:0] cam_pixel;
	input wire pix_clk;
	input wire pix_rst;
	input wire mode;
	input wire hs;
	input wire vs;
	input wire de;
	input wire [10:0] x;
	input wire [9:0] y;
	output wire [23:0] rgb;
	output reg frame_valid;
	output reg underflow;
	input wire ddr_clk;
	input wire ddr_rst;
	input wire [27:0] g_awaddr;
	input wire [27:0] g_araddr;
	input wire g_awvalid;
	input wire g_arvalid;
	output wire g_awready;
	output wire g_wready;
	output wire g_arready;
	output wire g_rvalid;
	input wire [255:0] g_wdata;
	output wire [255:0] g_rdata;
	input wire [31:0] g_wstrb;
	output wire g_rlast;
	output wire [27:0] m_awaddr;
	output wire [27:0] m_araddr;
	output wire [3:0] m_arlen;
	output wire m_awvalid;
	output wire m_arvalid;
	input wire m_awready;
	input wire m_wready;
	input wire m_arready;
	input wire m_rvalid;
	input wire m_rlast;
	output wire [255:0] m_wdata;
	input wire [255:0] m_rdata;
	output wire [31:0] m_wstrb;
	output reg camera_drop;
	output reg protocol_error;
	// R82: frames are stored at the camera's 640x360 (SW x SH, 14 400 blocks) and doubled on
	// display: display line y reads source line y/2, one block covers 32 display pixels. The
	// display fetches VBLOCKS = H x (SW/16) virtual blocks (each source line twice) in 8-beat bursts.
	localparam SW = W / 2;
	localparam SH = H / 2;
	localparam SBLOCKS = (SW * SH) / 16;
	localparam VBLOCKS = H * (SW / 16);
	localparam [27:0] BASE = 28'h1000000;
	reg [1:0] write_bank;
	reg poisoned;
	reg in_frame;
	reg [19:0] pixels;
	reg [255:0] pack;
	reg [3:0] lane;
	reg [15:0] block;
	(* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync;
	(* ASYNC_REG = "TRUE" *) reg [1:0] capture_sync;
	reg display_ack;
	reg ack_go;
	reg [1:0] display_taken;
	reg ack_seen;
	reg [2:0] maybe;
	reg [1:0] pub_last;
	reg [1:0] pub_prev;
	reg pub_last_v;
	reg pub_prev_v;
	reg pending_take;
	wire wf_full;
	wire wf_empty;
	wire [FIFO_AW:0] wf_level;
	reg wf_push;
	reg [274:0] wf_data;
	wire [274:0] wf_q;
	wire wf_pop;
	function [2:0] onehot3;
		input [1:0] b;
		onehot3 = (b == 2'd0 ? 3'b001 : (b == 2'd1 ? 3'b010 : 3'b100));
	endfunction
	// Banks the display may show after this cycle: an acknowledged take narrows
	// the set to the taken bank plus a later publication; a publication adds its
	// bank. The bank written by an unpublished frame is never in the set.
	wire ack_now = ack_sync[1] != ack_seen;
	wire [2:0] taken_set = onehot3(display_taken) |
		((pub_last_v && pub_prev_v && (display_taken == pub_prev)) ? onehot3(pub_last) : 3'b000);
	wire [2:0] maybe_acked = (ack_now ? taken_set : maybe);
	wire frame_end = (cam_valid && in_frame) && !cam_sof && (pixels == ((SW * SH) - 1));
	wire latest_taken = ack_now && (display_taken == pub_last);
	wire pub_allowed = !pending_take || latest_taken;
	// R82: also publish a frame that lost a few blocks (live view instead of a frozen or dark
	// screen when DDR is oversubscribed); a lost block keeps the bank's older content.
	wire publish_now = (frame_end && !wf_full) && pub_allowed;
	wire [2:0] maybe_next = maybe_acked | (publish_now ? onehot3(write_bank) : 3'b000);
	// Frame-start choice from the registered set: an acknowledgement in the same
	// cycle can only shrink it and a publication never coincides with a start.
	wire [2:0] free_banks = ~maybe;
	wire can_start = free_banks != 3'b000;
	wire [1:0] start_bank = (free_banks[0] ? 2'd0 : (free_banks[1] ? 2'd1 : 2'd2));
	always @(posedge cam_clk)
		if (cam_rst) begin
			write_bank <= 0;
			poisoned <= 0;
			in_frame <= 0;
			pixels <= 0;
			pack <= 0;
			lane <= 0;
			block <= 0;
			ack_sync <= 0;
			ack_seen <= 0;
			maybe <= 0;
			pub_last <= 0;
			pub_prev <= 0;
			pub_last_v <= 0;
			pub_prev_v <= 0;
			pending_take <= 0;
			capture_sync <= 0;
			wf_push <= 0;
			camera_drop <= 0;
		end
		else begin
			ack_sync <= {ack_sync[0], display_ack};
			capture_sync <= {capture_sync[0], mode};
			wf_push <= 0;
			maybe <= maybe_next;
			if (ack_now) begin
				ack_seen <= ack_sync[1];
				if (display_taken == pub_last)
					pub_prev_v <= 0;
			end
			if (latest_taken)
				pending_take <= 0;
			if (frame_end && !publish_now)
				camera_drop <= 1;
			if (publish_now) begin
				pending_take <= 1;
				pub_prev <= pub_last;
				pub_prev_v <= pub_last_v && !(ack_now && (display_taken == pub_last));
				pub_last <= write_bank;
				pub_last_v <= 1;
			end
			if (cam_sof) begin
				in_frame <= can_start && capture_sync[1];
				poisoned <= 0;
				pixels <= 0;
				lane <= 0;
				block <= 0;
				if (can_start)
					write_bank <= start_bank;
				if (!can_start && capture_sync[1])
					camera_drop <= 1;
			end
			if (cam_valid && (in_frame || ((cam_sof && can_start) && capture_sync[1]))) begin
				pack[16 * (cam_sof ? 0 : lane)+:16] <= cam_pixel;
				lane <= (cam_sof ? 1 : lane + 1'b1);
				pixels <= (cam_sof ? 1 : pixels + 1'b1);
				if (!cam_sof && (lane == 15)) begin
					if (wf_full) begin
						poisoned <= 1;
						camera_drop <= 1;
					end
					else begin
						wf_push <= 1;
						wf_data <= {(pixels == ((SW * SH) - 1)) && pub_allowed, write_bank, block, cam_pixel, pack[239:0]};
					end
					block <= block + 1'b1;
				end
				if (!cam_sof && (pixels == ((SW * SH) - 1)))
					in_frame <= 0;
			end
		end
	fn_view_fifo #(
		.DW(275),
		.AW(FIFO_AW)
	) write_fifo(
		.wclk(cam_clk),
		.wrst(cam_rst),
		.wen(wf_push),
		.wdata(wf_data),
		.wfull(wf_full),
		.wlevel(wf_level),
		.rclk(ddr_clk),
		.rrst(ddr_rst),
		.ren(wf_pop),
		.rdata(wf_q),
		.rempty(wf_empty)
	);
	reg published;
	reg pub_go;
	reg [1:0] published_bank;
	(* ASYNC_REG = "TRUE" *) reg [1:0] pub_sync;
	reg pub_seen;
	reg [1:0] front_bank;
	reg vs_q;
	reg [7:0] epoch;
	reg [15:0] fetch_block;
	wire frame_start = vs && !vs_q;
	wire req_full;
	wire req_empty;
	wire [3:0] req_level;
	wire [51:0] req_q;
	reg [9:0] fetch_line;
	reg [5:0] fetch_b;
	// source block of the next burst: (display line / 2) x 40 + block in line (shifts, no multiplier)
	wire [15:0] fetch_src = (({7'd0, fetch_line[9:1]} << 5) + ({7'd0, fetch_line[9:1]} << 3)) + {10'd0, fetch_b};
	wire req_push = ((mode && frame_valid) && (fetch_block < VBLOCKS)) && !req_full;
	wire req_pop;
	always @(posedge pix_clk)
		if (pix_rst) begin
			pub_sync <= 0;
			pub_seen <= 0;
			front_bank <= 0;
			vs_q <= 0;
			epoch <= 0;
			fetch_block <= VBLOCKS;
			fetch_line <= 0;
			fetch_b <= 0;
			display_ack <= 0;
			ack_go <= 0;
			display_taken <= 0;
			frame_valid <= 0;
		end
		else begin
			pub_sync <= {pub_sync[0], published};
			vs_q <= vs;
			if (ack_go) begin
				display_ack <= ~display_ack;
				ack_go <= 0;
			end
			if (frame_start) begin
				epoch <= epoch + 1'b1;
				fetch_block <= (mode && (frame_valid || (pub_sync[1] != pub_seen)) ? 0 : VBLOCKS);
				fetch_line <= 0;
				fetch_b <= 0;
				if (pub_sync[1] != pub_seen) begin
					pub_seen <= pub_sync[1];
					front_bank <= published_bank;
					display_taken <= published_bank;
					ack_go <= 1;
					frame_valid <= 1;
				end
			end
			else if (req_push) begin
				fetch_block <= fetch_block + 16'd8;
				if (fetch_b == 6'd32) begin
					fetch_b <= 0;
					fetch_line <= fetch_line + 1'b1;
				end
				else
					fetch_b <= fetch_b + 6'd8;
			end
		end
	fn_view_fifo #(
		.DW(52),
		.AW(3)
	) request_fifo(
		.wclk(pix_clk),
		.wrst(pix_rst),
		.wen(req_push && !frame_start),
		.wdata({epoch, fetch_block, (BASE + {7'd0, front_bank, 19'd0}) + {9'd0, fetch_src, 3'd0}}),
		.wfull(req_full),
		.wlevel(req_level),
		.rclk(ddr_clk),
		.rrst(ddr_rst),
		.ren(req_pop),
		.rdata(req_q),
		.rempty(req_empty)
	);
	wire rsp_full;
	wire rsp_empty;
	wire [7:0] rsp_level;
	wire rsp_push;
	wire rsp_pop;
	wire [279:0] rsp_q;
	reg [23:0] read_tag;
	reg [3:0] beat;
	fn_view_fifo #(
		.DW(280),
		.AW(7)
	) response_fifo(
		.wclk(ddr_clk),
		.wrst(ddr_rst),
		.wen(rsp_push),
		.wdata({read_tag[23:16], read_tag[15:0] + {12'd0, beat}, m_rdata}),
		.wfull(rsp_full),
		.wlevel(rsp_level),
		.rclk(pix_clk),
		.rrst(pix_rst),
		.ren(rsp_pop),
		.rdata(rsp_q),
		.rempty(rsp_empty)
	);
	reg [279:0] q0;
	reg [279:0] q1;
	reg [1:0] queued;
	reg rsp_pending;
	wire [15:0] expected_block = (({6'd0, y} << 5) + ({6'd0, y} << 3)) + {11'd0, x[10:5]};   // y x 40 + x/32
	wire match_pixel = ((queued != 0) && (q0[279:272] == epoch)) && (q0[271:256] == expected_block);
	wire stale = (queued != 0) && ((q0[279:272] != epoch) || (de && (q0[271:256] < expected_block)));
	wire pop = stale || ((de && match_pixel) && (x[4:0] == 31));
	wire push = (rsp_pending && (rsp_q[279:272] == epoch)) && !frame_start;
	assign rsp_pop = ((!rsp_empty && !rsp_pending) && (queued < 2)) && !frame_start;
	wire [15:0] rgb565 = q0[16 * x[4:1]+:16];
	assign rgb = (match_pixel && frame_valid ? {rgb565[15:11], rgb565[15:13], rgb565[10:5], rgb565[10:9], rgb565[4:0], rgb565[4:2]} : 24'h080c18);
	always @(posedge pix_clk)
		if (pix_rst) begin
			queued <= 0;
			rsp_pending <= 0;
			underflow <= 0;
			q0 <= 0;
			q1 <= 0;
		end
		else begin
			rsp_pending <= rsp_pop;
			if (frame_start) begin
				queued <= 0;
				underflow <= 0;
			end
			else begin
				case ({push, pop})
					2'b10: begin
						if (queued == 0)
							q0 <= rsp_q;
						else
							q1 <= rsp_q;
						queued <= queued + 1'b1;
					end
					2'b01: begin
						q0 <= q1;
						queued <= queued - 1'b1;
					end
					2'b11:
						if (queued == 1)
							q0 <= rsp_q;
						else begin
							q0 <= q1;
							q1 <= rsp_q;
						end
				endcase
				if (((mode && de) && frame_valid) && !match_pixel)
					underflow <= 1;
			end
		end
	localparam IDLE = 0;
	localparam GWRITE = 1;
	localparam GREAD = 2;
	localparam GRSP = 3;
	localparam WFETCH = 4;
	localparam CWRITE = 5;
	localparam GUARD = 6;
	localparam VFETCH = 7;
	localparam VREAD = 8;
	localparam VRSP = 9;
	localparam DREAD = 10;
	localparam DRSP = 11;
	reg [3:0] state;
	reg [3:0] after_guard;
	reg aw_done;
	reg w_done;
	reg [1:0] guard_count;
	reg [274:0] write_packet;
	reg [27:0] read_addr;
	reg prefer_write;
	wire camera_eof = write_packet[274];
	wire [1:0] camera_bank = write_packet[273:272];
	wire [27:0] camera_addr = (BASE + {7'd0, camera_bank, 19'd0}) + {9'd0, write_packet[271:256], 3'd0};
	wire read_can_go = !req_empty && (rsp_level <= 8'd96);
	// R82 arbitration (POSEVIEW only: the write FIFO fills only while the view captures):
	//  * camera writes go in batches: once a batch started it continues for up to 8 blocks while
	//    the FIFO has data, so the DDR controller turns between reads and writes once per batch
	//    instead of around every 16-pixel block (a game access waits at most one batch);
	//  * after two game-port accesses in a row while view work waits, the view goes first once.
	//    A batch starts once the oldest waiting block has waited 255 cycles (about six blocks
	//    collect at the camera's pace), so batches really group blocks.
	reg [1:0] g_streak;
	reg [3:0] w_run;   // camera writes in the current batch (0: no batch)
	reg [7:0] wf_age;  // cycles the write FIFO has held data since the last camera write
	wire w_ready = !wf_empty && (wf_age == 8'd255);
	wire w_hold = ((w_run != 4'd0) && (w_run != 4'd8)) && !wf_empty;
	wire view_waiting = w_ready || read_can_go;
	wire g_go = ((g_awvalid || g_arvalid) && !w_hold) && !((g_streak == 2'd2) && view_waiting);
	assign wf_pop = (state == IDLE) && (w_hold || ((w_ready && !g_go) && (prefer_write || !read_can_go)));
	assign req_pop = (((state == IDLE) && !g_go) && read_can_go) && !wf_pop;
	assign m_awvalid = ((state == GWRITE) || (state == CWRITE)) && !aw_done;
	assign m_awaddr = (state == GWRITE ? g_awaddr : camera_addr);
	assign m_wdata = (state == GWRITE ? g_wdata : write_packet[255:0]);
	assign m_wstrb = ((state == GWRITE) && !w_done ? g_wstrb : ((state == CWRITE) && !w_done ? 32'hffffffff : 32'd0));
	assign g_awready = ((state == GWRITE) && !aw_done) && m_awready;
	assign g_wready = ((state == GWRITE) && !w_done) && m_wready;
	assign m_arvalid = ((state == GREAD) || (state == VREAD)) || (state == DREAD);
	assign m_arlen = (state == VREAD ? 4'd7 : 4'd0);
	assign m_araddr = (state == GREAD ? g_araddr : (state == DREAD ? camera_addr : read_addr));
	assign g_arready = (state == GREAD) && m_arready;
	assign g_rvalid = (state == GRSP) && m_rvalid;
	assign g_rdata = m_rdata;
	assign g_rlast = m_rlast;
	assign rsp_push = ((state == VRSP) && m_rvalid) && !protocol_error;
	always @(posedge ddr_clk)
		if (ddr_rst) begin
			state <= IDLE;
			aw_done <= 0;
			w_done <= 0;
			guard_count <= 0;
			after_guard <= IDLE;
			published <= 0;
			pub_go <= 0;
			published_bank <= 0;
			write_packet <= 0;
			read_addr <= 0;
			read_tag <= 0;
			beat <= 0;
			prefer_write <= 1;
			protocol_error <= 0;
			g_streak <= 0;
			w_run <= 0;
			wf_age <= 0;
		end
		else begin
			if (wf_empty || ((state == IDLE) && wf_pop))
				wf_age <= 0;
			else if (wf_age != 8'd255)
				wf_age <= wf_age + 8'd1;
			if (pub_go) begin
				published <= ~published;
				pub_go <= 0;
			end
			if (((m_rvalid && (state != GRSP)) && (state != VRSP)) && (state != DRSP))
				protocol_error <= 1;
			case (state)
				IDLE: begin
					aw_done <= 0;
					w_done <= 0;
					if (wf_pop) begin
						state <= WFETCH;
						g_streak <= 0;
						w_run <= (w_hold ? w_run + 4'd1 : 4'd1);
					end
					else if (g_go) begin
						state <= (g_arvalid ? GREAD : GWRITE);
						g_streak <= (!view_waiting ? 2'd0 : (g_streak == 2'd2 ? 2'd2 : g_streak + 2'd1));
						w_run <= 0;
					end
					else if (req_pop) begin
						state <= VFETCH;
						g_streak <= 0;
						w_run <= 0;
					end
				end
				WFETCH: begin
					write_packet <= wf_q;
					state <= CWRITE;
					prefer_write <= 0;
				end
				VFETCH: begin
					read_addr <= req_q[27:0];
					read_tag <= req_q[51:28];
					beat <= 0;
					state <= VREAD;
					prefer_write <= 1;
				end
				GWRITE, CWRITE: begin
					if (m_awvalid && m_awready)
						aw_done <= 1;
					if (!w_done && m_wready)
						w_done <= 1;
					if ((aw_done || m_awready) && (w_done || m_wready)) begin
						guard_count <= 2;
						after_guard <= ((state == CWRITE) && camera_eof ? DREAD : IDLE);
						state <= GUARD;
					end
				end
				GUARD:
					if (guard_count == 0)
						state <= after_guard;
					else
						guard_count <= guard_count - 1'b1;
				GREAD:
					if (m_arready)
						state <= GRSP;
				VREAD:
					if (m_arready)
						state <= VRSP;
				DREAD:
					if (m_arready)
						state <= DRSP;
				VRSP:
					if (m_rvalid) begin
						if ((m_rlast != (beat == 4'd7)) || rsp_full)
							protocol_error <= 1;
						beat <= beat + 1'b1;
						if (m_rlast)
							state <= IDLE;
					end
				GRSP, DRSP:
					if (m_rvalid) begin
						if (!m_rlast)
							protocol_error <= 1;
						if (((state == DRSP) && m_rlast) && !protocol_error) begin
							pub_go <= 1;
							published_bank <= camera_bank;
						end
						state <= IDLE;
					end
				default: begin
					state <= IDLE;
					protocol_error <= 1;
				end
			endcase
		end
	wire unused = &{1'b0, hs, wf_level, req_level, rsp_level};
endmodule

`timescale 1ns/1ps
// Bundled status changes once per CPU publication, then stays stable. Capture
// three pixel clocks after the toggle synchronizer and apply at vertical blank.
module fn_pose_view_hud(
    input wire clk,rst,vs,de,
    input wire [10:0] x,input wire [9:0] y,
    input wire [31:0] status,input wire status_toggle,
    input wire [23:0] rgb_in,output wire [23:0] rgb_out
);
    (* ASYNC_REG="TRUE" *) reg [1:0] toggle_sync;
    reg seen,vs_q;reg [2:0] settle;
    reg [31:0] staged,active;
    always @(posedge clk) begin
        if(rst) begin toggle_sync<=0;seen<=0;settle<=0;staged<=0;active<=0;vs_q<=0;end
        else begin
            toggle_sync<={toggle_sync[0],status_toggle};vs_q<=vs;
            if(toggle_sync[1]!=seen)begin seen<=toggle_sync[1];settle<=3;end
            else if(settle!=0)begin
                settle<=settle-1'b1;if(settle==1)staged<=status;
            end
            if(vs&&!vs_q)active<=staged;
        end
    end
    function [34:0] glyph;
        input [7:0] ch;
        begin
            case(ch)
                "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "K":glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "M":glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N":glyph={5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
                "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                ":":glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
                "/":glyph={5'b00001,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b10000};
                default:glyph=0;
            endcase
        end
    endfunction
    wire in_hud=de&&x>=12&&x<360&&y>=12&&y<50;
    wire line2=y>=32;
    wire [8:0] dx=(x-12)>>1;
    wire [4:0] col=dx/6;
    wire [2:0] gx=dx%6;
    wire [3:0] gy=(y-(line2?32:12))>>1;
    reg [7:0] ch;
    reg [7:0] rate;
    always @* begin
        ch=" ";rate=col<6?active[7:0]:col<15?active[15:8]:active[23:16];
        if(rate>99)rate=99;
        if(line2)case(col)
            0:ch="T";1:ch="R";2:ch="A";3:ch="C";4:ch="K";5:ch=":";
            7:ch="O";8:ch=active[24]?"N":"F";9:ch=active[24]?" ":"F";
            default:ch=" ";
        endcase
        else case(col)
            0:ch="C";1:ch="A";2:ch="M";4,13,23:ch="0"+rate/10;
            5,14,24:ch="0"+rate%10;7,16:ch="/";
            9:ch="D";10:ch="E";11:ch="T";
            18:ch="P";19:ch="O";20:ch="S";21:ch="E";
            default:ch=" ";
        endcase
    end
    wire [34:0] bits=glyph(ch);
    wire ink=gx<5&&gy<7&&bits[34-(gy*5+gx)];
    assign rgb_out=in_hud?(ink?(line2?(active[24]?24'h40ff90:24'hff8050):24'hffffff):24'h080c18):rgb_in;
endmodule
module p2_cam_upx2 #(
    parameter integer IN_W = 640,
    parameter integer GAP  = 600
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        in_valid,
    input  wire [15:0] in_pix,
    input  wire        in_sof,
    input  wire        in_eol,
    output reg         pix_valid,
    output reg  [15:0] pix,
    output reg  [10:0] x,
    output reg  [9:0]  y,
    output reg         sof,
    output reg         eol,
    output reg         overflow
);
    localparam integer OUT_W = 2 * IN_W;
    (* syn_ramstyle = "lut_ram" *) reg [15:0] mem [0:3 * IN_W - 1];
    function [11:0] base;
        input [1:0] s;
        base = (s == 2'd0) ? 12'd0 : (s == 2'd1) ? IN_W : 2 * IN_W;
    endfunction
    function [1:0] next_slot;
        input [1:0] s;
        next_slot = (s == 2'd2) ? 2'd0 : s + 2'd1;
    endfunction

    // ---------------------------------------------------------------- write side
    reg  [1:0] wslot;
    reg  [9:0] wx;             // next write column (saturates at IN_W)
    reg  [2:0] first;          // per slot: line carries the frame start
    reg        wfirst;         // current input line started with in_sof
    reg        wdrop;          // current input line lost a pixel (slots full / too long)
    reg  [1:0] count;          // complete lines waiting (0..3)
    reg        pop;            // read side finished a slot this cycle
    wire       full = count == 2'd3;
    wire [9:0] wa = in_sof ? 10'd0 : wx;            // a frame start restarts the line at x = 0
    wire       wbad = full || wa >= IN_W;
    wire       line_done = in_valid && in_eol;
    wire       line_bad = (wdrop && !in_sof) || wbad; // any pixel of this line was not stored
    wire       commit = line_done && !line_bad;
    always @(posedge clk) begin
        if (in_valid && !wbad)
            mem[base(wslot) + wa] <= in_pix;
    end
    always @(posedge clk) begin
        if (rst) begin
            wslot <= 0; wx <= 0; wfirst <= 0; wdrop <= 0; first <= 0; count <= 0; overflow <= 0;
        end else begin
            if (in_valid) begin
                if (wbad) overflow <= 1'b1;
                if (line_done) begin
                    wx <= 0;
                    wfirst <= 1'b0;
                    wdrop <= 1'b0;
                    if (commit) begin
                        first[wslot] <= wfirst || in_sof;
                        wslot <= next_slot(wslot);
                    end
                end else begin
                    wx <= (wa < IN_W) ? wa + 1'b1 : wa;
                    wfirst <= wfirst || in_sof;
                    wdrop <= (wdrop && !in_sof) || wbad;
                end
            end
            count <= count + (commit ? 2'd1 : 2'd0) - (pop ? 2'd1 : 2'd0);
        end
    end

    // ---------------------------------------------------------------- read side
    reg        busy;
    reg        copy;           // 0: output line 2y, 1: line 2y+1
    reg  [1:0] rslot;
    reg [10:0] ox;
    reg [11:0] gap;
    reg  [9:0] oy;
    reg        rd_v, rd_sof, rd_eol;
    reg [10:0] rd_x;
    reg  [9:0] rd_y;
    reg [15:0] q;
    always @(posedge clk) q <= mem[base(rslot) + ox[10:1]];
    always @(posedge clk) begin
        if (rst) begin
            busy <= 0; copy <= 0; rslot <= 0; ox <= 0; gap <= 0; oy <= 0; pop <= 0;
            rd_v <= 0; rd_sof <= 0; rd_eol <= 0; rd_x <= 0; rd_y <= 0;
        end else begin
            pop <= 1'b0;
            rd_v <= 1'b0; rd_sof <= 1'b0; rd_eol <= 1'b0;
            if (gap != 0) gap <= gap - 1'b1;
            else if (!busy) begin
                if (count != 0 && !pop) begin
                    busy <= 1'b1; copy <= 1'b0; ox <= 0;
                    if (first[rslot]) oy <= 0;
                end
            end else begin
                rd_v <= 1'b1;
                rd_x <= ox;
                rd_y <= copy ? oy + 1'b1 : oy;
                rd_sof <= first[rslot] && !copy && ox == 0;
                rd_eol <= ox == OUT_W - 1;
                if (ox == OUT_W - 1) begin
                    ox <= 0;
                    gap <= GAP;
                    if (copy) begin
                        busy <= 1'b0;
                        pop <= 1'b1;
                        rslot <= next_slot(rslot);
                        oy <= oy + 2'd2;
                    end
                    copy <= !copy;
                end else ox <= ox + 1'b1;
            end
        end
    end
    // mem read has one cycle of latency: q belongs to the previous cycle's rd_* stage
    always @(posedge clk) begin
        if (rst) begin
            pix_valid <= 0; pix <= 0; x <= 0; y <= 0; sof <= 0; eol <= 0;
        end else begin
            pix_valid <= rd_v;
            sof <= rd_sof;
            eol <= rd_eol;
            if (rd_v) begin pix <= q; x <= rd_x; y <= rd_y; end
        end
    end
endmodule

// R81: per-layer start queue. A network accepts the next frame while deeper layers
// still finish the previous one; each layer starts the queued frame as soon as its
// own window is idle. Depth 2 = at most two frames in flight. When empty, a push
// passes straight through (same-cycle start, as the shared start was before).
module p2_start_q (
	clk,
	rst,
	push,
	push_id,
	full,
	empty,
	start_valid,
	start_ready,
	start_id
);
	input wire clk;
	input wire rst;
	input wire push;
	input wire [31:0] push_id;
	output wire full;
	output wire empty;
	output wire start_valid;
	input wire start_ready;
	output wire [31:0] start_id;
	reg [1:0] count;
	reg [31:0] id0;
	reg [31:0] id1;
	assign empty = count == 2'd0;
	assign full = count == 2'd2;
	assign start_valid = !empty || push;
	assign start_id = (empty ? push_id : id0);
	wire pop = start_valid && start_ready;
	always @(posedge clk)
		if (rst) begin
			count <= 0;
			id0 <= 0;
			id1 <= 0;
		end
		else if (push && !pop) begin
			if (empty)
				id0 <= push_id;
			else
				id1 <= push_id;
			count <= count + 1'b1;
		end
		else if (pop && !push) begin
			id0 <= id1;
			count <= count - 1'b1;
		end
		else if (pop && push && !empty) begin
			if (count == 2'd1)
				id0 <= push_id;
			else begin
				id0 <= id1;
				id1 <= push_id;
			end
		end
endmodule
