.section .text.start
.globl _start
_start:
    li sp, DMEM_BYTES
    call main
1:  j 1b
