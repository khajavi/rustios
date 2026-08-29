OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)

SECTIONS
{
  . = 1M;

  .text :
  {
    *(.multiboot)
    *(.bootstrap)
    *(.text*)
  }

  .rodata :
  {
    *(.rodata*)
  }

  .data :
  {
    *(.data*)
  }

  .bss :
  {
    *(COMMON)
    *(.bss*)
  }
}
