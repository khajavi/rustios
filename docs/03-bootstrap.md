# Step 3 — The 32 → 64 bootstrap

This is the heart of the whole project, and the single most subtle step. Read
it slowly; every other step is easy by comparison.

## The problem: GRUB starts us in 32-bit mode

Remember the multiboot2 header from Step 1 said `architecture = 0` (i386 /
32-bit). The multiboot2 **spec** therefore requires GRUB to start our kernel
in **32-bit protected mode** with **paging turned off**.

But we are writing a **64-bit** kernel! Our Rust code (`x86_64-unknown-none`)
assumes long mode. How do we reconcile the two?

> The CPU does **not** magically become 64-bit. *We* are responsible for
> switching it there, at the very start, before Rust ever runs.

Because this must happen before Rust runs (Rust is 64-bit code), we write it
in **assembly** in `boot.s`. This file is the tiny bit of "bootstrapping" code
we assemble with `$CC -c boot.s` in Step 2.

## Where our code begins: `_start`

```asm
.code32                       # this code is written for 32-bit mode
.global _start
_start:
    cli                       # disable interrupts while we rearrange the CPU
    movl %ebx, %edi           # save: ebx = pointer to boot info -> arg0 (rdi later)
    movl %eax, %esi           # save: eax = multiboot2 magic     -> arg1 (rsi later)
    movl $stack_top, %esp     # set up a stack; "ESP is undefined at hand-off"
```

GRUB calls our `_start` with two gifts in registers:

- **`eax` = `0x36d76289`** — the multiboot2 magic number, proof of a valid boot,
- **`ebx` = address** of the multiboot2 information structure (we parse this in
  Step 5 to find the framebuffer).

We move them to `edi`/`esi` because, once we are in 64-bit mode and call the
Rust function `kmain`, the **System V calling convention** says the first two
arguments come in `rdi` and `rsi`.

## Goal of the bootstrap

To reach long mode we must, in this order:

1. build an **identity page table** (map the kernel's physical addresses so
   the CPU can translate them once paging turns on);
2. load a **Global Descriptor Table (GDT)** with a 64-bit code segment;
3. enable **PAE** (Physical Address Extension) — required before long mode;
4. load **CR3** with the page-table root;
5. set **EFER.LME** (Long Mode Enable);
6. enable **paging** (CR0.PG);
7. **far-jump** into the 64-bit code segment — *now* we are truly 64-bit.

## Concept 1: the Global Descriptor Table (GDT)

The CPU, in protected and long modes, needs a table of **segment descriptors**.
Think of it as the CPU's "what kinds of segments am I allowed to use" registry.
We define three:

```asm
.balign 8
gdt:
    .quad 0x0000000000000000        # null descriptor (must always be first)
    .quad 0x00AF9A000000FFFF        # 64-bit code segment, selector 0x08
    .quad 0x00CF92000000FFFF        # data         segment, selector 0x10
gdt_desc:                           # the "GDTR" the CPU loads
    .word gdt_end - gdt - 1         # limit = size - 1
    .long  gdt                      # base address
gdt_end:
```

And we load it with one instruction: `lgdt gdt_desc`.

## Concept 2: page tables and PAE

64-bit mode **requires paging to be on**, and paging requires a *page table* —
a tree of entries that tell the CPU "virtual address X maps to physical
address Y."

For a kernel that must run at a fixed low address, the simplest correct choice
is an **identity map**: every virtual address equals physical address. Then
whatever physical address our code is loaded at, the CPU can fetch it.

The 64-bit page table has **four levels**:

```
PML4 -> PDPT -> PD -> PT
```

Because we map huge 2 MiB "pages" (this is the `PS`/"page size" bit), each PD
entry covers 2 MiB, so one PD table maps a full 1 GiB.

We allocate the tables in `.bss` (zero-initialized memory — great, because
empty entries default to "not present", and `0` upper-32 bits of each PAE entry
mean "physical address below 4 GiB"):

```asm
.section .bss, "", "nobits"
.balign 4096
pd0:      .skip 4096     # PML4
pdpt0:    .skip 4096     # PDPT
pd0_low:  .skip 4096     # PD for the low 1 GiB
pd_high:  .skip 4096     # PD for the top 1 GiB
```

Then we wire them together:

```asm
movl $pdpt0, %eax
orl  $0x3, %eax                # present + writable
movl %eax, pd0                 # PML4[0] -> PDPT (VA 0-1 GiB)
movl %eax, pd0 + 24            # PML4[3] -> PDPT (VA 3-4 GiB)
movl $pd0_low, %eax
orl  $0x3, %eax
movl %eax, pdpt0               # PDPT[0] -> PD (low 1 GiB)
movl $pd_high, %eax
orl  $0x3, %eax
movl %eax, pdpt0 + 24          # PDPT[3] -> PD (top 1 GiB)
```

Note `pd0 + 24` and `pdpt0 + 24`: because **PAE entries are 8 bytes**, entry
index 3 is at byte offset `3 * 8 = 24`.

Now fill each PD with 512 identity entries:

```asm
# low 1 GiB, starting at physical address 0
movl $0x83, %eax               # 2 MiB page: present + writable + page-size(PS)
movl $0, %ecx
1:
    movl %eax, pd0_low(, %ecx, 8)   # store at index %ecx, stride 8 bytes
    addl $0x200000, %eax            # next 2 MiB
    incl %ecx
    cmpl $512, %ecx
    jne  1b
```

Why the **stride 8** and not 4? This is a classic PAE bug. In PAE, every page
table entry is 8 bytes (a 64-bit page-table entry). If you mistakenly use
stride 4 (which is correct for non-PAE 32-bit paging), every other entry
overwrites the previous one, the table is garbage, and the CPU **page-faults**
the instant you enable paging. This specific bug bit our real kernel right
here — fixing the stride from `4` to `8` was the difference between a black
screen and a working "Hello World!".

The loop ends with `%eax > ...` after 512 iterations, so the table is complete.

### Why also map the top 1 GiB?

We map `pd_high` (VA 3–4 GiB) as well. That's because the boot loader hands us
a **graphical framebuffer** whose memory lives way up high — on QEMU it landed
at physical `0xFD000000`, around 4 GiB. If we didn't map that region, the
moment Step 5's code writes a pixel to the framebuffer, the CPU would page-fault
and the screen stays black. So we reserve a whole high GiB and identity-map it:

```asm
movl $0xC0000083, %eax         # phys 3 GiB, 2 MiB page, P+RW+PS
movl $0, %ecx
2:
    movl %eax, pd_high(, %ecx, 8)
    addl $0x200000, %eax
    incl %ecx
    cmpl $512, %ecx
    jne  2b
```

## Concept 3: flipping the CPU to long mode

With the page tables ready and `lgdt` done, we execute the four steps that
move the CPU from 32-bit protected mode into 64-bit long mode:

```asm
# 1) Enable PAE (Physical Address Extension)
movl %cr4, %eax
orl  $0x20, %eax               # CR4.PAE
movl %eax, %cr4

# 2) Point CR3 at the page table root (PML4)
movl $pd0, %eax
movl %eax, %cr3

# 3) Enable Long Mode: IA32_EFER.LME
movl $0xC0000080, %ecx         # MSR number of IA32_EFER
rdmsr                          # read the model-specific register
orl  $0x100, %eax              # set bit 8 = LME (Long Mode Enable)
wrmsr                          # write it back

# 4) Enable paging (and keep Protected Mode enabled)
movl %cr0, %eax
orl  $0x80000001, %eax         # CR0.PG | CR0.PE
movl %eax, %cr0
```

CR4, CR3, CR0 are *control registers* — the CPU's master switches. By setting
the exact bits, we tell it "from now on, run in long mode."

## Concept 4: the far jump into 64-bit code

After `CR0.PG` is set, the CPU is *technically* in long mode, but the
instruction stream is still 32-bit until we reload the code segment. In long
mode, code is selected by a 64-bit code descriptor — the one at selector
`0x08` we put in the GDT:

```asm
ljmp $0x08, $long_mode       # far jump: also reload the CS selector
```

The far jump does two things: it jumps to the label `long_mode`, **and** it
loads `CS = 0x08` (our 64-bit code segment). From that instruction onward the
CPU decodes 64-bit instructions.

## Arriving in 64-bit mode

```asm
.code64
long_mode:
    movabs $stack_top, %rsp   # set a full 64-bit stack pointer
    pushq $0
    popfq                     # clear all flags (new mode, clean state)
    call  kmain               # hand control to Rust! (rdi/rsi already set)
halt:
    cli
    hlt                       # if we ever come back, halt the CPU
    jmp halt
```

`call kmain` is the moment Rust takes over. The two registers we carefully
saved back at `_start` (`edi` → boot info pointer, `esi` → magic) are now our
`rdi`/`rsi` arguments, exactly where C's calling convention wants them.

## How we debugged this (the hard-won lesson)

This step produced the most troubleshooting of the whole project. Two symptoms
stand out and are worth knowing:

1. **Pure 64-bit with no bootstrap → garbage.** When we had 64-bit Rust at
   `_start` but GRUB started us in 32-bit mode, the CPU executed 64-bit
   instructions *as if they were 32-bit* — garbage that looked like "black
   screen, no serial output." Fix: the bootstrap above.

2. **Page fault the instant paging turns on → the PAE stride-4 bug.** We'd
   enabled paging but the CPU faulted at once. Reading the physical page table
   memory showed malformed entries caused by writing entries 8-byte-spaced with
   a 4-byte stride. Fix: stride `8`.

## Check your progress

At this point you should be able to boot and see *at least* serial output, and
no crashes. If your QEMU window is black, that's fine for now — the framebuffer
comes in Step 5. In [Step 4](04-serial.md) we add a serial port so we can
actually *see* what the kernel is doing.
