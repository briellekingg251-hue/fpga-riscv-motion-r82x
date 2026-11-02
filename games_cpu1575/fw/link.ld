/* Generated from config/soc.json by the P1 mainline configuration step. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 0x20000
}

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

    ASSERT(__image_end <= __stack_limit,
           "P1 image leaves less than 4 KiB aligned stack space in RAM")
}
