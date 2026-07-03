/* =========================================================================
   RISC-V Bare-Metal Linker Script: APPLICATION
   ========================================================================= */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  /* Application takes the remaining 12KB of BRAM */
  ram (rwx) : ORIGIN = 0x00001000, LENGTH = 28K
}

SECTIONS
{
  .text : {
    . = ALIGN(4);
    KEEP(*(.text._start)) /* Application entry vector sits at 0x00001000 */
    *(.text .text.*)    
    . = ALIGN(4);
    *(.rodata .rodata.*)   
    *(.srodata .srodata.*) 
    . = ALIGN(4);
  } > ram

  .data : {
    . = ALIGN(4);
    *(.data .data.*)
    *(.sdata .sdata.*)
    . = ALIGN(4);
  } > ram

  .bss : {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > ram

  /* Stack top is at the absolute end of the 16KB BRAM (0x00004000) */
  _stack_top = ORIGIN(ram) + LENGTH(ram);

  /DISCARD/ : {
    *(.eh_frame) *(.eh_frame_hdr) *(.interp) *(.note .note.*) 
    *(.riscv.attributes) *(.comment)
  }
}
