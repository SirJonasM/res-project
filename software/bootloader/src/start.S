.section .text._start
.global _start
.global trap_handler   # Ensure assembly knows trap_handler exists elsewhere

_start:
    # 1. Enable Zicsr dynamically and disable global interrupts
    .option push
    .option arch, +zicsr
    csrci mstatus, 8

    # 3. Initialize the stack pointer safely without allowing the linker
    # to rewrite or relax instructions around this address.
    .option push
    .option norelax
    auipc sp, 0x4
    addi  sp, sp, -4     # Target 0x4000 safely
    
    # Clear out global and thread pointers so they are explicitly zeroed 
    # instead of containing power-on hardware noise.
    li gp, 0
    li tp, 0
    .option pop

    # 4. Jump to main
    jal zero, main

# Catch-all safety loop
_loop_forever:
    j _loop_forever
