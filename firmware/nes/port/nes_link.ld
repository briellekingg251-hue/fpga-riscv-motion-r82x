/* SPDX-License-Identifier: GPL-2.0-or-later
 * NES image in DDR3 (loader ABI 3).  The loader copies GAME.BIN to 0x80100000
 * and jumps there.  0x80000000..0x8001ffff is block RAM (resident loader and
 * its handoff block); CPU-visible DDR ends at 0x83f00000, the top 1 MiB of
 * the 64 MiB window belongs to the GPU framebuffers. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { DDR (rwx) : ORIGIN = 0x80100000, LENGTH = 0x03e00000 }
SECTIONS {
 .text : ALIGN(64) { KEEP(*(.text.start)) *(.text .text.*) } > DDR
 .rodata : ALIGN(64) { *(.rodata .rodata.*) *(.srodata .srodata.*) } > DDR
 .data : ALIGN(64) { *(.data .data.*) __global_pointer$ = . + 0x800; *(.sdata .sdata.*) } > DDR
 __image_end = .;
 .bss (NOLOAD) : ALIGN(64) { __bss_start = .; *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON) . = ALIGN(64); __bss_end = .; } > DDR
 __stack_top = ORIGIN(DDR) + LENGTH(DDR);
 __stack_limit = __stack_top - 0x00100000;
 ASSERT(__stack_top == 0x83f00000, "stack overlaps the GPU framebuffers")
 ASSERT(__bss_end <= __stack_limit, "image overlaps the 1 MiB stack reserve")
 /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.init_array*) *(.fini_array*) *(.ctors*) *(.dtors*) }
}
