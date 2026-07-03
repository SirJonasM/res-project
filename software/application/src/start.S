.section .text._start
.global _start

_start:
    # 1. Disable interrupts globally during boot setup
    csrci mstatus, 8

    # 2. Load the stack pointer from the linker script symbol
    .option push
    .option norelax
    la sp, _stack_top
    .option pop

    j main

    # Safety catch-all latch if Rust ever returns
inf_loop:
    wfi
    j inf_loop
