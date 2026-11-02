/* PAL image in DDR3 (loader ABI 3).  0x80000000..0x8001ffff is the block RAM
 * holding the resident loader; DDR3 is cached from 0x80020000 to 0x83ffffff.
 * The loader copies GAME.BIN to 0x80100000 and jumps to _start. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { DDR (rwx) : ORIGIN = 0x80100000, LENGTH = 0x03e00000 }
SECTIONS {
 .text : ALIGN(64) { KEEP(*(.text.start)) *(.text .text.*) } > DDR
 .rodata : ALIGN(64) { *(.rodata .rodata.*) *(.srodata .srodata.*) } > DDR
 .init_array : ALIGN(4) { PROVIDE_HIDDEN(__init_array_start = .); KEEP(*(SORT(.init_array.*))) KEEP(*(.init_array)) PROVIDE_HIDDEN(__init_array_end = .); } > DDR
 .fini_array : ALIGN(4) { PROVIDE_HIDDEN(__fini_array_start = .); KEEP(*(.fini_array)) PROVIDE_HIDDEN(__fini_array_end = .); } > DDR
 .data : ALIGN(64) { *(.data .data.*) __global_pointer$ = . + 0x800; *(.sdata .sdata.*) } > DDR
 __image_end = .;
 .bss (NOLOAD) : ALIGN(64) { __bss_start = .; *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON) . = ALIGN(64); __bss_end = .; } > DDR
 __heap_start = ALIGN(4096);
 __stack_top = 0x83f00000;
 __heap_end = __stack_top - 0x00100000;
 __stack_bottom = __heap_end;
 ASSERT(ORIGIN(DDR)+LENGTH(DDR) == 0x83f00000, "image crosses framebuffer reservation")
 ASSERT(__bss_end <= __heap_start, "BSS crosses heap")
 ASSERT(__stack_top == 0x83f00000 && __heap_end == 0x83e00000, "reserved framebuffer collision")
 ASSERT(__heap_start + 0x01000000 <= __heap_end, "less than 16 MiB of heap")
 /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
