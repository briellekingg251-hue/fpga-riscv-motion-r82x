`timescale 1ns/1ps
`include "soc_config.vh"
module soc_benchmark_tb;
reg clk=0,rst=1,run_stop=0,clean_valid=0,cmd_allow=1,w_allow=1,r_allow=1;
integer cycle=0,limit=100000000,stall=0,exit_seen=0,exit_cycle=0,clean_started=0,clean_seen=0,drain=0,k;
integer uart_fd,trace_fd,timer_reads=0;
reg [63:0] observed_retired=0;
integer uart_active=0,uart_count=0,uart_bit=0,uart_bytes=0,p4_starts=0,p4_complete=0;
reg uart_prev=1,irq_prev=0;reg [7:0] uart_byte;reg [31:0] random_q=32'h9e3779b9;
reg done_before;
reg [127:0] held_d,held_cmd,held_w,held_r;reg hold_d=0,hold_cmd=0,hold_w=0,hold_r=0;
p2_sim_top #(.MACHINE_MODE(1),.BP_ENABLED(1),.LEGACY_CORE(0),.CACHE_ENABLED(1),
 .CACHE_BYTES(8192),.LINE_BYTES(32),.FIFO_DEPTH(2),.RESPONSE_BYPASS(1),.BTB_ENTRIES(128),
 .BHT_ENTRIES(256),.EARLY_LSU(1),.HW_MUL(1),.ACCEL_ENABLE(1),.DC_LOAD_HIT_TURNOVER(1)) dut(
 .clk(clk),.rst(rst),.run_stop(run_stop),.clean_valid(clean_valid),.dump_ram(1'b0),
 .backend_cmd_allow(cmd_allow),.backend_w_allow(w_allow),.backend_r_allow(r_allow),
 .irq_software_in(1'b0),.irq_timer_in(1'b0),.irq_external_in(1'b0));
initial if(dut.system_soc.soc.improved.core.RAS_DEPTH!=4) $fatal(1,"RAS_DEPTH_MISMATCH");
initial begin
 // BTB geometry observation only: no signal assignment or clock delay.
 if (dut.BTB_ENTRIES != 128) $fatal(1,"BTB_GEOMETRY_PATH_MISMATCH_0");
 if (dut.system_soc.BTB_ENTRIES != 128) $fatal(1,"BTB_GEOMETRY_PATH_MISMATCH_1");
 if (dut.system_soc.soc.BTB_ENTRIES != 128) $fatal(1,"BTB_GEOMETRY_PATH_MISMATCH_2");
 if (dut.system_soc.soc.improved.core.BTB_ENTRIES != 128) $fatal(1,"BTB_GEOMETRY_PATH_MISMATCH_3");
 if (dut.system_soc.soc.improved.core.predictor.BTB_ENTRIES != 128) $fatal(1,"BTB_GEOMETRY_PATH_MISMATCH_4");
 if ($size(dut.system_soc.soc.improved.core.predictor.valid) != 128) $fatal(1,"BTB_GEOMETRY_ARRAY_MISMATCH");
 if ($bits(dut.system_soc.soc.improved.core.predictor.tag[0]) != 23) $fatal(1,"BTB_GEOMETRY_TAG_MISMATCH");
 $display("BTB_GEOMETRY_PASS entries=%0d rows=%0d tag_bits=%0d",dut.system_soc.soc.improved.core.predictor.BTB_ENTRIES,$size(dut.system_soc.soc.improved.core.predictor.valid),$bits(dut.system_soc.soc.improved.core.predictor.tag[0]));
 if($value$plusargs("STALL=%d",stall)) begin end
 uart_fd=$fopen("uart.hex","w");trace_fd=$fopen("windows.txt","w");
 if (`CLOCK_HZ !== 32'd144000000 || `UART_DIVISOR !== 32'd1250)
  $fatal(1,"HEADER_144000000_1250_MISMATCH");
 if (dut.system_soc.soc.machine_peripherals.peripherals.UART_DIVISOR != 1250)
  $fatal(1,"ELABORATED_UART_DIVISOR_MISMATCH");
 $display("SIM_CLOCK_144000000_UART1250_PASS clock=%0d uart=%0d",`CLOCK_HZ,
          dut.system_soc.soc.machine_peripherals.peripherals.UART_DIVISOR);
 repeat(5) begin #3.472;clk=1;#3.472;clk=0;end
 rst=0;
 for(cycle=0;cycle<limit;cycle=cycle+1) begin
  clk=0;
  random_q={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
  cmd_allow=!stall||random_q[0]||random_q[1];w_allow=!stall||random_q[2]||random_q[3];r_allow=!stall||random_q[4]||random_q[5];
  clean_valid=0;
  #1;
  if(exit_seen&&!clean_started&&dut.clean_ready&&dut.data_idle&&dut.fetch_idle&&!dut.mon_cmd_valid) begin clean_valid=1;clean_started=1;end
  #1;
  if(dut.fatal||dut.clean_error) $fatal(1,"FATAL_OR_CLEAN_ERROR");
  if(hold_d&&(!dut.mon_d_req_valid||held_d!=={dut.mon_d_req_addr,dut.mon_d_req_write,dut.mon_d_req_be,dut.mon_d_req_wdata})) $fatal(1,"D_HOLD");
  if(hold_cmd&&(!dut.mon_cmd_valid||held_cmd!=={dut.mon_cmd_addr,dut.mon_cmd_write,dut.mon_cmd_len})) $fatal(1,"CMD_HOLD");
  if(hold_w&&(!dut.mon_w_valid||held_w!=={dut.mon_w_data,dut.mon_w_be,dut.mon_w_last})) $fatal(1,"W_HOLD");
  if(hold_r&&(!dut.mon_r_valid||held_r!=={dut.mon_r_data,dut.mon_r_error,dut.mon_r_last})) $fatal(1,"R_HOLD");
  hold_d=dut.mon_d_req_valid&&!dut.mon_d_req_ready;held_d={dut.mon_d_req_addr,dut.mon_d_req_write,dut.mon_d_req_be,dut.mon_d_req_wdata};
  hold_cmd=dut.mon_cmd_valid&&!dut.mon_cmd_ready;held_cmd={dut.mon_cmd_addr,dut.mon_cmd_write,dut.mon_cmd_len};
  hold_w=dut.mon_w_valid&&!dut.mon_w_ready;held_w={dut.mon_w_data,dut.mon_w_be,dut.mon_w_last};
  hold_r=dut.mon_r_valid&&!dut.mon_r_ready;held_r={dut.mon_r_data,dut.mon_r_error,dut.mon_r_last};
  if(dut.mon_p4_start) p4_starts=p4_starts+1;
  if(dut.mon_p4_complete) p4_complete=p4_complete+1;
  if(dut.mon_d_req_valid&&dut.mon_d_req_ready) begin
   if(exit_seen) $fatal(1,"REQUEST_AFTER_EXIT");
  end
  // Probe actual timer acceptance, including any SoC request buffer.
  if(dut.system_soc.soc.machine_peripherals.peripherals.req_valid&&dut.system_soc.soc.machine_peripherals.peripherals.req_ready&&
     !dut.system_soc.soc.machine_peripherals.peripherals.req_write&&dut.system_soc.soc.machine_peripherals.peripherals.req_addr==32'h10002000) begin
   timer_reads=timer_reads+1;
   $fwrite(trace_fd,"Z %h %h %h",cycle,dut.count_cycle,dut.count_retired);
   for(k=0;k<24;k=k+1) $fwrite(trace_fd," %h",dut.perf_values[k*64+:64]);
   $fwrite(trace_fd,"\n");
  end
  done_before=dut.clean_done;
  #1.472;clk=1;#1;
  if(exit_seen&&(dut.trace_valid||dut.system_soc.trace_valid1||dut.trace_irq_valid)) $fatal(1,"RETIREMENT_AFTER_EXIT");
  if(!exit_seen&&dut.trace_valid) begin
   if(!dut.trace_trap) observed_retired=observed_retired+1;
   if(!dut.trace_trap&&dut.trace_mem_valid&&dut.trace_mem_write&&dut.trace_mem_addr==32'h20000000&&dut.trace_mem_be==15) begin
    if(dut.trace_mem_wdata!=1) $fatal(1,"EXIT_FAILURE");exit_seen=1;exit_cycle=cycle;run_stop=1;
   end
  end
  if(!exit_seen&&dut.system_soc.trace_valid1) begin
   observed_retired=observed_retired+1;
   if(!dut.trace_valid||dut.trace_trap||dut.trace_csr_valid||(dut.system_soc.trace_pc1!=dut.trace_pc+32'd4&&!(dut.trace_insn[6:0]==7'h63&&dut.system_soc.trace_pc1==dut.trace_pc+{{19{dut.trace_insn[31]}},dut.trace_insn[31],dut.trace_insn[7],dut.trace_insn[30:25],dut.trace_insn[11:8],1'b0})))
    $fatal(1,"DUAL_RETIRE_ORDER");
  end
  if(!uart_active&&uart_prev&&!dut.uart_tx) begin uart_active=1;uart_count=(3*`UART_DIVISOR/2)-1;uart_bit=0;uart_byte=0;end
  else if(uart_active) begin
   if(uart_count>0) uart_count=uart_count-1;
   else if(uart_bit<8) begin uart_byte[uart_bit]=dut.uart_tx;uart_bit=uart_bit+1;uart_count=`UART_DIVISOR-1;end
   else begin if(!dut.uart_tx) $fatal(1,"UART_FRAMING");uart_active=0;uart_bytes=uart_bytes+1;$fwrite(uart_fd,"%02x",uart_byte);end
  end
  uart_prev=dut.uart_tx;
  if(done_before) clean_seen=1;
  if(clean_seen&&dut.data_idle&&dut.fetch_idle&&!uart_active&&dut.uart_tx) drain=drain+1;else drain=0;
  if(drain==3000) begin
   if(timer_reads!=2) $fatal(1,"TIMER_READ_COUNT");
   if(observed_retired!=dut.count_retired) $fatal(1,"RETIREMENT_COUNT_MISMATCH");
   $writememh("final_ram.hex",dut.memory.mem);$fclose(uart_fd);$fclose(trace_fd);
   $display("SOC_BENCH_PASS cycles=%0d exit_cycle=%0d retired=%0d uart_bytes=%0d p4_starts=%0d p4_complete=%0d",cycle,exit_cycle,dut.count_retired,uart_bytes,p4_starts,p4_complete);$finish;
  end
  #2.472;
 end
 $fatal(1,"BENCH_TIMEOUT");
end
endmodule