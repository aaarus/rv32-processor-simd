OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { IMEM (rx) : ORIGIN = 0, LENGTH = 1024 }
SECTIONS {
    .text : { *(.text.start) *(.text .text.*) } > IMEM
    /DISCARD/ : { *(.eh_frame*) *(.comment) }
}
