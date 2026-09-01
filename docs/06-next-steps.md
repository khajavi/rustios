# Step 6 — Putting it all together and next steps

Congratulations! You have written, built, and booted a real operating-system
kernel. Let's take stock of exactly what it is made of, then look at where a
curious kernel developer goes next.

## What you built

Your kernel, end to end:

- **`boot.s`** — a tiny amount of 32-bit assembly that gives the CPU a call
  stack and hands control to the C entry point:
  ```asm
  movl $stack_top, %esp   # give the CPU a stack
  pushl %eax              # arg1: magic
  pushl %ebx              # arg0: boot_info
  call  kmain             # enter our C code
  ```
- **`src/main.c`** — the freestanding C kernel: a `multiboot2` header so GRUB
  recognizes and loads us, plus the VGA-text code that prints "Hello, World!".
- **`kernel.nix` / `iso.nix` / `flake.nix`** — the Nix build that compiles,
  assembles, links, and packages it all into a bootable ISO.

Three ideas were central:

1. **Freestanding C** (`-ffreestanding -nostdlib`) — a kernel has no OS below
   it, so it cannot use the C standard library; it talks to hardware directly
   through pointers and `volatile` memory.
2. **The multiboot2 header** — the small block of bytes that tells a boot
   loader "I am a kernel; load me at 1 MiB and jump to `_start`."
3. **Memory-mapped output** — writing characters into the VGA text buffer at
   `0xB8000` to make something appear on screen, with no drivers at all.

And you did it all with **Nix**, so the whole project builds reproducibly with
a single command:

```bash
nix build .#iso    # produce the bootable ISO
nix run .#run      # build and boot it in QEMU
```

## Where to go next

This `c-i686-vga-text` branch is deliberately the *simplest possible* kernel:
**C, 32-bit, VGA text output.** The sibling branches in this same repository
build on it, one idea at a time:

| Branch | What it adds |
|--------|--------------|
| `i686-vga-text` | The same 32-bit kernel written in **Rust** instead of C — compare the two languages side by side. |
| `asm-i686-vga-text` | The whole 32-bit kernel written in **pure assembly** — no C or Rust at all. |
| `x86_64-vga-text` | A **64-bit** kernel: a `boot.s` that switches the CPU from 32-bit to long mode, then writes to the same VGA buffer. |
| `i686-framebuffer` | A **graphical framebuffer** renderer: parses the boot info, picks up an 800×600 buffer, and draws a scaled font pixel by pixel (notes the big 32→64 switch and PIT timer work). |
| `x86_64-framebuffer` | The full tour: **64-bit bootstrap + framebuffer + serial debugging + PIT-timer animation**, each documented step by step. |

Good next challenges:

- Switch to the **64-bit** `x86_64-vga-text` branch to see the 32→64
  bootstrap.
- Add a **serial port** driver for debugging output.
- Draw to the **framebuffer** instead of VGA text.
- Animate the output with the **PIT timer** (the 8254 chip), one character
  per 500 ms.

Each of those is exactly what one of the sibling branches demonstrates, so
everything you need is already in this repository.

## Welcome 🎉

You went from nothing to a bootable operating-system kernel that prints its
own "Hello, World!" right on the screen. That's the same path real kernels
take — just with the boot loader's help for the hard parts.

Welcome to the wonderful, weird world of kernel development.
