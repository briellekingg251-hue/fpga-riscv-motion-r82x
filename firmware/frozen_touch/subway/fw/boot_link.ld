OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN  =  0x80018000, LENGTH  =  0x8000 }
MEMORY { HANDOFF (rw) : ORIGIN = 0x80017c00, LENGTH = 0x80 }
SECTIONS {
 .text : ALIGN(4) { KEEP(*(.text.start)) *(.text .text.*) } > RAM
 .rodata : ALIGN(4) { *(.rodata .rodata.*) } > RAM
 .data : ALIGN(4) { *(.data .data.*) *(.sdata .sdata.*) } > RAM
 .bss (NOLOAD) : ALIGN(4) { __bss_start = .; *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) .  =  ALIGN(4); __bss_end = .; } > RAM
 __image_end = .; __stack_top = ORIGIN(RAM)+LENGTH(RAM); __stack_limit = __stack_top-3072; /* measured worst case < 1 KiB (static frames, no recursion) */
 ASSERT(ORIGIN(RAM)>=__control_boot_end,"loader overlaps handoff")
 ASSERT(__image_end<= __stack_limit,"boot image exceeds reserved memory")
 __boot_info_addr = 0x80017c00;
 __control_boot_addr = 0x80017c40;
 __control_boot_end = 0x80017c80;
 .boot_contract (NOLOAD) : { . = . + 0x80; } > HANDOFF
 ASSERT(ADDR(.boot_contract)==__boot_info_addr, "handoff base moved")
 ASSERT(__boot_info_addr+28<=__control_boot_addr, "ABI overlaps mode extension")
 ASSERT(__control_boot_end<=0x80018000, "mode extension overlaps loader")
}
