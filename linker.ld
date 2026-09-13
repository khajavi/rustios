OUTPUT_FORMAT(elf32-i386)

SECTIONS
{
  /* The BIOS loads the first 512 bytes of the disk to physical address
     *0x7C00* and jumps there. Place the entire boot sector at that address. */
  . = 0x7C00;

  .text :
  {
    *(.text)
  }

  /* Drop the assembler's incidental metadata sections so the flattened
     binary is exactly one 512-byte sector. */
  /DISCARD/ : { *(.comment) *(.eh_frame) *(.note*) }
}