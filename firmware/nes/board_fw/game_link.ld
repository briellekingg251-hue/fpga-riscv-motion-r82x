OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN  =  0x80000000, LENGTH  =  0x17c00 }
SECTIONS {
 .text : ALIGN(4) { KEEP(*(.text.start)) *(.text .text.*) } > RAM
 .rodata : ALIGN(4) { *(.rodata .rodata.*) } > RAM
 .data : ALIGN(4) { *(.data .data.*) *(.sdata .sdata.*) } > RAM
 .bss (NOLOAD) : ALIGN(4) { __bss_start = .; *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) .  =  ALIGN(4); __bss_end = .; } > RAM
 __image_end = .; __stack_top = ORIGIN(RAM)+LENGTH(RAM); __stack_limit = __stack_top-8192;
 ASSERT(__image_end<= __stack_limit,"game exceeds RAM below bootloader")
}
