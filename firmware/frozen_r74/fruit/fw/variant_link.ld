OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
 STUB (rx) : ORIGIN = 0x80000000, LENGTH = 0x100
 DDR (rwx) : ORIGIN = 0x80020000, LENGTH = 0x10000
}
SECTIONS {
 .stub : { KEEP(*(.text.stub)) } > STUB
 .payload : AT(0x80000100) {
  __payload_start = .;
  KEEP(*(.text.dispatcher_entry)) *(.text .text.*)
  *(.rodata .rodata.*) *(.data .data.*) *(.sdata .sdata.*)
  . = ALIGN(4); __payload_end = .;
 } > DDR
 __payload_load = LOADADDR(.payload);
 .bss (NOLOAD) : ALIGN(4) {
  __bss_start = .; *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
  . = ALIGN(4); __bss_end = .;
 } > DDR
 __stack_top = ORIGIN(DDR)+LENGTH(DDR);
 ASSERT(__bss_end<=__stack_top-8192,"dispatcher exceeds DDR stack reserve")
 ASSERT(SIZEOF(.stub)<=0x100,"dispatcher stub too large")
 ASSERT(SIZEOF(.payload)+0x100<=0x15c00,"dispatcher exceeds RAM loader limit")
}
