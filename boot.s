// Minimal 32-bit bootstrap.
//
// The multiboot2 spec needs an architecture=0 (i386) kernel to be started in
// 32-bit protected mode with paging off, which is exactly the mode we want.
// We only need to give the CPU a stack and call the Rust entry point.
//
// GRUB passes us:
//   eax = multiboot2 magic value 0x36d76289
//   ebx = physical address of the multiboot2 information structure
//
// Since we stay in 32-bit mode, no GDT, page tables, or long-mode switch are
// needed. We forward ebx/eax to kmain as its (arg0, arg1) using the i386 C
// calling convention (left-to-right on the stack).

    .section .bss, "", "nobits"
    .balign 16
stack_bottom:
    .skip 16384
stack_top:

    .section .text
    .code32
    .global _start
_start:
    movl $stack_top, %esp   # ESP is undefined at hand-off
    pushl %eax              # arg1: magic
    pushl %ebx              # arg0: boot_info
    call  kmain
halt:
    cli
    hlt
    jmp   halt
