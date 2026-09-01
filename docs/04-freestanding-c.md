# Step 4 — Freestanding C and the build pipeline

We have `boot.s` giving us a stack and `src/main.c` holding the kernel logic.
Now let's understand how the C compiler turns that `.c` file into bare kernel
code — and how `as` + `ld` stitch everything into one bootable binary.

## Concept: freestanding C

When `gcc` builds a normal program, it links in the C standard library and a
start-up file (`crt0.o`) that calls `main()` on the OS's behalf. A kernel has
no OS, so we build in **freestanding** mode:

```bash
gcc -m32 -ffreestanding -nostdlib -fno-builtin -fno-stack-protector -O2 \
  -c src/main.c -o main.o
```

What each flag does:

- **`-m32`** — emit 32-bit i386 instructions (we are an i686 kernel).
- **`-ffreestanding`** — the compiler may not assume a hosted environment.
  For example, it won't implicitly declare `printf` or other libc functions.
- **`-nostdlib`** — don't link the C runtime or standard library. We provide
  everything ourselves.
- **`-fno-builtin`** — stop the compiler from "optimizing" our code into calls
  to libc functions like `memcpy` (which we don't have).
- **`-fno-stack-protector`** — kernels don't have the OS support that stack
  canaries rely on, so turn that off.
- **`-O2`** — a normal optimization level; fine (and safe here) for a kernel.

In return, our C code is restricted to what bare machine code can do: integer
arithmetic, pointers, and `volatile` memory access. No `printf`, no `malloc`.
That's the whole deal — and it's exactly what a kernel needs.

## Assembling the bootstrap

`boot.s` is plain GNU assembly. We assemble it to its own object file:

```bash
as --32 boot.s -o boot.o   # --32 = 32-bit x86
```

`as` produces machine code directly; it needs no runtime and pulls in no
libraries — perfect for bare metal.

## Linking: from objects to a kernel

Two object files are not yet a kernel. We must place them at the right memory
address and make `_start` the entry point. The **linker script** (`linker.ld`)
tells `ld` to do exactly that:

```
OUTPUT_FORMAT(elf32-i386)     /* the final binary is a 32-bit ELF   */
ENTRY(_start)                 /* execution starts at _start (boot.s) */

SECTIONS {
  . = 1M;                     /* load the kernel at physical 1 MiB  */
  .text : { *(.multiboot) *(.text*) }   /* header first, then code  */
  .rodata : { *(.rodata*) }             /* read-only data           */
  .data   : { *(.data*)   }             /* read-write data          */
  .bss    : { *(COMMON) *(.bss*) }      /* zero-initialized data    */
}
```

Two crucial ideas:

1. **`. = 1M`** — GRUB loads kernels at physical address **1 MiB** (the low
   1 MiB is reserved for BIOS and hardware). So the linker places our code
   starting at `0x100000`.
2. **`*(.multiboot)` first** — the multiboot2 header (from Step 1) must be the
   very first bytes of the binary so GRUB can find it instantly. It comes from
   the `.multiboot` section we put our header array in.

Then:

```bash
ld -m elf_i386 -T linker.ld -z noexecstack boot.o main.o -o kernel
```

The two object files are combined, relocations resolved, placed per the
script, and the result is the `kernel` ELF.

## Putting it together

The whole pipeline, end to end:

```text
src/main.c  --gcc -m32 -ffreestanding-->  main.o  ┐
boot.s      --as --32------------------->  boot.o  ┴--ld -T linker.ld-->  kernel
```

In Step 2, all of this is wrapped up in `kernel.nix` so a single
`nix build .#iso` runs the whole chain reproducibly.

## Check your progress

```bash
nix build .#default
file $(nix build .#default --no-link --print-out-paths)/kernel
```

The `file` output should say something like *ELF 32-bit LSB executable, Intel
80386* — proof that our C and assembly really produced a 32-bit kernel.

> Ever wondered what an ELF actually is — what's inside that `kernel` file and
> how GRUB reads it? See [Appendix A — What is an ELF file?](appendix-elf.md).

Next, [Step 5](05-vga-text.md) finally puts text on the screen.
