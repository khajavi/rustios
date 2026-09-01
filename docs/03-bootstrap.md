# Step 3 — The stack and entry point

This is where our tiny bit of assembly hands the machine to the C kernel.
It is short, because we stay in **32-bit protected mode** — the mode GRUB
already leaves us in — so there is no long-mode switch to fight.

## The problem: GRUB starts us in 32-bit mode

Remember the multiboot2 header from Step 1 said `architecture = 0` (i386 /
32-bit). The multiboot2 spec therefore starts our kernel in **32-bit
protected mode** with **paging off**.

And our C kernel is *also* 32-bit (we compile with `-m32`). So there is
nothing to reconcile: the mode the boot loader hands us is exactly the mode
our code wants. We just need to give the CPU two things it does not have yet:

1. a **call stack** (`ESP` is undefined at hand-off), and
2. a way to reach the C entry point `kmain`.

Because this happens in assembly, we write it in `boot.s` — the tiny
bootstrap file we assemble with `as --32 boot.s` in Step 2.

## Where our code begins: `_start`

```asm
.section .bss, "", "nobits"
.balign 16
stack_bottom:
    .skip 16384          # 16 KiB of private memory for our stack
stack_top:

.section .text
.code32
.global _start
_start:
    movl $stack_top, %esp   # give the CPU a usable stack
    pushl %eax              # arg1: magic
    pushl %ebx              # arg0: boot_info
    call  kmain             # call our C entry point
halt:
    cli
    hlt                     # if kmain ever returns, halt the CPU
    jmp   halt
```

GRUB calls our `_start` with two gifts in registers:

- **`eax` = `0x36d76289`** — the multiboot2 magic number, proof of a valid boot,
- **`ebx` = address** of the multiboot2 information structure.

## The three things `_start` does

1. **Set up a stack.** The CPU has no working stack until we point `ESP`
   somewhere. We carve out a private 16 KiB region in `.bss` (which GRUB
   zero-fills) and point `ESP` at its top — the stack grows downwards from
   there. Without this, the very first `call`/`push` in our code would write to
   an undefined address.

2. **Forward the boot-loader gifts to `kmain`.** A 32-bit kernel entry point
   uses the **cdecl** calling convention: arguments are pushed on the stack,
   right-to-left. So in C, `kmain(boot_info, magic)` means `boot_info` is the
   first stack argument and `magic` the second:

   ```asm
   pushl %ebx              # last push = first argument (boot_info)
   pushl %eax              # second push = second argument (magic)
   call  kmain
   ```

3. **Halt if we ever come back.** A kernel never returns, but if `kmain`'s
   final `for (;;)` loop were ever bypassed, control would come back here and
   we just `hlt` forever.

## Concept: why no GDT, no pages, no long mode?

On the sibling *64-bit* branches, `boot.s` is long and subtle: it builds a
global descriptor table, a four-level page table, flips CPU control registers
to enable PAE and long mode, and far-jumps into 64-bit code.

None of that is needed here. Because the kernel is **32-bit** and GRUB hands
us **32-bit protected mode with an already-valid flat segmentation model**,
our code can run as-is. The only setup a kernel genuinely must do itself is
give itself a stack. That is the whole "bootstrap" for this project — a
beautifully small amount of assembly.

## Inside the C entry point

```c
__attribute__((noreturn))
void kmain(unsigned long boot_info, unsigned long magic) {
    (void)boot_info;
    (void)magic;
    /* ... print "Hello, World!" ... */
    for (;;) { }         /* park the CPU — a kernel never returns */
}
```

The two parameters arrive in the order we pushed them: `boot_info` from
`ebx`, `magic` from `eax`. We do not use them yet, but they are part of the
multiboot2 contract, so the entry point must accept them.

## How we debugged this (the hard-won lesson)

The one classic failure here: **forgetting to set up the stack.** If `ESP`
is never pointed at our `.bss` region, the first `call` pushes the return
address into whatever memory GRUB left `ESP` at — often garbage or read-only
memory — and the kernel crashes instantly or executes garbage. Symptom:
GRUB loads the kernel, then the screen goes blank or QEMU shows a reset/hang
with no output. Fix: `movl $stack_top, %esp` before any `call` or `push`.

## Check your progress

At this point you should be able to boot and reach `kmain` without crashing.
There's nothing on screen yet. In [Step 4](04-freestanding-c.md) we look at how the
build actually wires `boot.s` and `main.c` into one loadable kernel.
