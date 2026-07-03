/* =========================================================================
   RISC-V Bare-Metal Linker Script: BOOTLOADER
   ========================================================================= */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  /* Bootloader gets the first 4KB of BRAM */
  ram (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
  .text : {
    . = ALIGN(4);
    KEEP(*(.text._start)) /* Reset vector sits at 0x00000000 */
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

  /* Stack top is at the end of the Bootloader's 4KB block (0x00001000) */
  _stack_top = ORIGIN(ram) + LENGTH(ram);

  /DISCARD/ : {
    *(.eh_frame) *(.eh_frame_hdr) *(.interp) *(.note .note.*) 
    *(.riscv.attributes) *(.comment)
  }
}
