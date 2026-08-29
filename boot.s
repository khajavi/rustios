// 32-bit -> 64-bit bootstrap for a multiboot2 kernel.
//
// The multiboot2 spec (section 3.3) requires an architecture=0 (i386) kernel
// to be started in 32-bit protected mode with paging off (CS = flat 32-bit
// code segment, CR0.PE=1, CR0.PG=0). Because the kernel proper is 64-bit, we
// must switch to long mode ourselves before handing off to Rust.
//
// The boot loader passes:
//   eax = multiboot2 magic value 0x36d76289
//   ebx = physical address of the multiboot2 information structure
//
// We forward those to `kmain` as its first two arguments (rdi, rsi) using the
// System V AMD64 calling convention.

    .section .bootstrap, "ax"


# --------------------------------------------------------------------------
# Global Descriptor Table (loaded before entering long mode)
# --------------------------------------------------------------------------
    .balign 8
gdt:
    .quad 0x0000000000000000        # null descriptor
    .quad 0x00AF9A000000FFFF        # 64-bit code, selector 0x08
    .quad 0x00CF92000000FFFF        # data, selector 0x10
gdt_desc:
    .word gdt_end - gdt - 1
    .long  gdt
gdt_end:

    .section .bss, "", "nobits"
    .balign 4096
pd0:                                # PML4 (page-map level-4)
    .skip 4096
pdpt0:                              # PDPT
    .skip 4096
pd0_low:                            # PDEs for the first 1 GiB (2 MiB pages)
    .skip 4096
pd_high:                            # PDEs for the top 1 GiB (VA 3-4 GiB)
    .skip 4096
    .balign 16
stack_bottom:
    .skip 16384
stack_top:

    .section .bootstrap, "ax"

# --------------------------------------------------------------------------
# Entry point (32-bit protected mode, paging off)
# --------------------------------------------------------------------------
    .code32
    .global _start
_start:
    cli
    movl %ebx, %edi                 # boot_info -> arg0 (preserved)
    movl %eax, %esi                 # magic      -> arg1 (preserved)
    movl $stack_top, %esp           # ESP is undefined at hand-off

    # Build the 1 GiB identity map with 2 MiB pages.
    # Note: with PAE every table entry is 8 bytes. The upper 4 bytes of each
    # entry are already 0 (the loader zero-fills .bss), so a 4-byte store at
    # each 8-byte-aligned slot is sufficient.
    movl $pdpt0, %eax
    orl  $0x3, %eax                 # present + writable
    movl %eax, pd0                  # PML4[0] -> PDPT (VA 0-1 GiB)
    movl %eax, pd0 + 24             # PML4[3] -> PDPT (VA 3-4 GiB)
    movl $pd0_low, %eax
    orl  $0x3, %eax
    movl %eax, pdpt0                # PDPT[0] -> PDE table (low 1 GiB)
    movl $pd_high, %eax
    orl  $0x3, %eax
    movl %eax, pdpt0 + 24           # PDPT[3] -> PDE table (top 1 GiB)

    # Fill low 1 GiB: identity map, starting at physical 0.
    movl $0x83, %eax                # 2 MiB page: present + writable + PS
    movl $0, %ecx
1:
    movl %eax, pd0_low(, %ecx, 8)
    addl $0x200000, %eax
    incl %ecx
    cmpl $512, %ecx
    jne  1b

    # Fill top 1 GiB (VA 3-4 GiB): identity map. This covers the high
    # physical region (e.g. 0xFD000000) where GRUB places the framebuffer.
    movl $0xC0000083, %eax          # phys 3 GiB, 2 MiB page, P+RW+PS
    movl $0, %ecx
2:
    movl %eax, pd_high(, %ecx, 8)
    addl $0x200000, %eax
    incl %ecx
    cmpl $512, %ecx
    jne  2b

    lgdt gdt_desc

    # Enable PAE.
    movl %cr4, %eax
    orl  $0x20, %eax                # CR4.PAE
    movl %eax, %cr4

    # Point CR3 at the PML4.
    movl $pd0, %eax
    movl %eax, %cr3

    # Enable Long Mode via IA32_EFER.LME.
    movl $0xC0000080, %ecx
    rdmsr
    orl  $0x100, %eax               # EFER.LME
    wrmsr

    # Enable paging (and keep PE set).
    movl %cr0, %eax
    orl  $0x80000001, %eax          # CR0.PG | CR0.PE
    movl %eax, %cr0

    # Far jump into the 64-bit code segment.
    ljmp $0x08, $long_mode

# --------------------------------------------------------------------------
# 64-bit long mode
# --------------------------------------------------------------------------
    .code64
long_mode:
    movabs $stack_top, %rsp
    pushq $0
    popfq
    call  kmain
halt:
    cli
    hlt
    jmp   halt


