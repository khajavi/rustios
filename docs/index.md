# C OS Kernel Tutorial (from zero to "Hello World!")

Welcome! This tutorial walks you through **building your very own operating
system kernel in C**, from an empty folder to a real "Hello World!" that you
can boot in the QEMU emulator and see on screen.

You do **not** need any prior kernel experience. We assume only that you:

- know a little C (variables, functions, `for` loops, pointers);
- can open a terminal and run commands;
- have [Nix](https://nixos.org/download) installed (we use it to build and
  run everything, so you never have to fight with toolchain installs).

**If you've never seen assembly language before**, don't worry! Before you hit the `boot.s` file in Step 3, we've included [Step 3a — Assembly language primer](03a-assembly-primer.md), which teaches you everything from scratch: registers, the call stack, x86-32 syntax, and how to read assembly code. Come back to it if assembly looks alien at first.

Everything you will build here is **real** — it is the exact same code that
ships in the `rustios` project you are reading. Every step ends with a working
program you can run, and each later step builds directly on the one before it.

By the end you will have a kernel that:

1. boots via the **multiboot2** boot protocol (a standardized contract that
   boot loaders like GRUB understand);
2. runs in **32-bit protected mode** — the mode the boot loader hands us, so
   we never have to fight with a 32→64 mode switch;
3. gives itself a **call stack** with a tiny assembly prologue;
4. prints `Hello, World!` directly into the **VGA text buffer** at `0xB8000`.

---

## What is an operating system kernel, really?

An OS kernel is the first program the computer runs. It is loaded into memory
by a *boot loader* (here, GRUB) and then "takes over" the machine. Normally
when you write a program you call the OS (`printf`, `read a file`, etc.). A
**kernel** is the *opposite*: there is no OS below it. It cannot use `printf`,
it cannot call `malloc`, it cannot even use the standard library at all. It
talks directly to hardware.

That is exactly why it is both scary and magical. And why it is so instructive.

---

## How to follow along

The project lives in this repository. At each step you can either:

- **read** the explanation and the real code, or
- **build and run** it yourself (we will show you the Nix commands).

To run the finished kernel:

```bash
nix run .#run
```

A QEMU window opens that boots your kernel. (If you are in a headless/SSH
environment, an alternative is `nix build .#iso` and then boot the produced
`.iso`.)

To build just the ISO file:

```bash
nix build .#iso
ls result/            # -> rustios.iso
```

---

## The plan

The steps are ordered exactly the way we wrote the real kernel, so the order
matters. Each chapter ends with a checkable result.

| Step | Title | What you learn | Result you see |
|------|-------|----------------|----------------|
| 1 | [Your first freestanding kernel](01-freestanding.md) | A C program with no OS; the multiboot2 header | boots a `_start` that halts |
| 2 | [Nix makes it declarative](02-nix.md) | Reproducible builds, a flake, an ISO | `nix build .#iso` produces a bootable ISO |
| 3a | [Assembly language primer](03a-assembly-primer.md) | **Registers, the stack, calling conventions, x86-32 syntax — everything you need to read `boot.s`** | understand every line of assembly |
| 3 | [The stack and entry point](03-bootstrap.md) | 32-bit protected mode, the call stack, `boot.s` | the CPU reaches `kmain` |
| 4 | [How the build works](04-freestanding-c.md) | Freestanding C, assembling and linking the kernel | a coherent `kernel` ELF |
| 5 | [Writing to VGA text](05-vga-text.md) | The VGA text buffer at `0xB8000`, writing characters | "Hello World" shown in the QEMU window |
| 6 | [Putting it all together / next steps](06-next-steps.md) | Review what you built and where to go next | a working, bootable kernel |
| 7 | [The multiboot2 header, for beginners](07-multiboot.md) | A deep dive into the boot-loader handshake | see your `e8 52 50 d6` magic bytes |

## Appendix

- [Appendix A — What is an ELF file?](appendix-elf.md) — the standard "box"
  that holds your machine code plus the metadata GRUB needs to load it.

Let's begin with [Step 1](01-freestanding.md).
