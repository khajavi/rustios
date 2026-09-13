# 16-bit Boot Sector Kernel (from zero to "Hello World!")

Welcome! This tutorial walks you through **building a 16-bit BIOS boot
sector** in GNU assembly that prints "Hello, World!" directly to the screen.

You do **not** need any prior OS experience. We assume only that you:

- can open a terminal and run commands;
- have [Nix](https://nixos.org/download) installed (we use it to build and
  run everything).

Everything you will build here is **real** — it is the exact same code that
ships in the `gas-boot-sector` branch of this repository.

By the end you will have a boot sector that:

1. boots via the **BIOS** — no GRUB, no boot loader;
2. runs in **16-bit real mode** — the mode the CPU starts in at power-on;
3. prints `Hello, World!` using **BIOS interrupt `0x10`** (teletype output);
4. is exactly **512 bytes** with the boot signature `0xAA55`.

---

## What is a boot sector?

A boot sector is the very first 512 bytes read from a disk when the computer
starts. The BIOS loads it to memory address `0x7C00` and jumps there. Your
code is now running — there is no OS, no file system, no standard library.
You talk directly to hardware.

---

## How to follow along

To build and run the boot sector:

```bash
nix run .#run
```

QEMU starts and boots your sector. You see:

```
Booting from Hard Disk...
Hello, World!
Booted with GNU assembly
```

---

## The plan

| Step | Title | What you learn | Result you see |
|------|-------|----------------|----------------|
| 1 | [What is a boot sector?](01-boot-sector.md) | The 512-byte contract with the BIOS | a diagram of the MBR |
| 2 | [16-bit real mode](02-real-mode.md) | Registers, segmentation, BIOS calls | understand `0x7C00` |
| 3 | [BIOS interrupts](03-interrupts.md) | `int 0x10` teletype, `int 0x13` disk | print characters on screen |
| 4 | [The assembly source](04-kernel-asm.md) | Annotated walkthrough of `kernel.s` | every line explained |
| 5 | [Building with Nix](05-build-nix.md) | GAS, linker, objcopy to raw binary | `nix build .#default` |
| 6 | [Running and testing](06-running.md) | QEMU, VGA memory dump, verification | "Hello, World!" on screen |

Let's begin with [Step 1](01-boot-sector.md).
