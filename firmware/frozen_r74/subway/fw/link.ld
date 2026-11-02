/* Generated from config/soc.json by the P1 mainline configuration step. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 0x17c00
}

MEMORY { HANDOFF (rw) : ORIGIN = 0x80017c00, LENGTH = 0x80 }
SECTIONS
{
    . = ORIGIN(RAM);

    .text : ALIGN(4)
    {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > RAM

    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.*)
    } > RAM

    /* The simulator preloads this section from the ELF PT_LOAD bytes. */
    .data : ALIGN(4)
    {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > RAM

    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    . = ALIGN(16);
    __image_end = .;
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    __stack_limit = __stack_top - 4096;

    PROVIDE(_end = __image_end);

    ASSERT(__stack_top<=__boot_info_addr,"game stack overlaps handoff")
 ASSERT(__image_end <= __stack_limit,
           "P1 image leaves less than 4 KiB aligned stack space in RAM")
 __boot_info_addr = 0x80017c00;
 __control_boot_addr = 0x80017c40;
 __control_boot_end = 0x80017c80;
 .boot_contract (NOLOAD) : { . = . + 0x80; } > HANDOFF
 ASSERT(ADDR(.boot_contract)==__boot_info_addr, "handoff base moved")
 ASSERT(__boot_info_addr+28<=__control_boot_addr, "ABI overlaps mode extension")
 ASSERT(__control_boot_end<=0x80018000, "mode extension overlaps loader")
}
