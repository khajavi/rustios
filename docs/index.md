# Rust OS Kernel Tutorial (from zero to "Hello World!")

Welcome! This tutorial walks you through **building your very own operating
system kernel in Rust**, from an empty folder to a real "Hello World!" that
you can boot in the QEMU emulator and see on screen.

You do **not** need any prior kernel experience. We assume only that you:

- know a little Rust (variables, functions, `for` loops, structs);
- can open a terminal and run commands;
- have [Nix](https://nixos.org/download) installed (we use it to build and
  run everything, so you never have to fight with toolchain installs).

Everything you will build here is **real** — it is the exact same code that
ships in the `rustios` project you are reading. Every step ends with a working
program you can run, and each later step builds directly on the one before it.

By the end you will have a kernel that:

1. boots via the **multiboot2** boot protocol (a standardized contract that
   boot loaders like GRUB understand);
2. starts in **32-bit mode** and switches itself into **64-bit long mode**
   (this turning point is the single hardest, most interesting part);
3. talks over the **serial port** so you can debug it;
4. writes text directly into the **VGA text buffer** at `0xB8000`;
5. animates `Hello World!` one character at a time using a **hardware timer**.

---

## What is an operating system kernel, really?

An OS kernel is the first program the computer runs. It is loaded into memory
by a *boot loader* (here, GRUB) and then "takes over" the machine. Normally
when you write a program you call the OS (`print!`, `read a file`, etc.). A
**kernel** is the *opposite*: there is no OS below it. It cannot use `println!`,
it cannot allocate memory with `Vec`, it cannot even use the floating-point
units by default. It talks directly to hardware.

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

Every time we tell you to test, the serial console also prints a message. To
capture serial output to a file while running headless:

```bash
qemu-system-x86_64 -cdrom $(nix build .#iso --no-link --print-out-paths)/rustios.iso \
  -no-reboot -boot d -serial file:/tmp/serial.log -display none
tail /tmp/serial.log
```

---

## The plan

The steps are ordered exactly the way we wrote the real kernel, so the order
matters. Each chapter ends with a checkable result.

| Step | Title | What you learn | Result you see |
|------|-------|----------------|----------------|
| 1 | [Your first freestanding kernel](01-freestanding.md) | A Rust program with no OS; the multiboot2 header | QEMU logo / boots a `_start` that halts |
| 2 | [Nix makes it declarative](02-nix.md) | Reproducible builds, a flake, an ISO | `nix build .#iso` produces a bootable ISO |
| 3 | [The 32→64 bootstrap](03-bootstrap.md) | Protected mode, long mode, GDT, paging (PAE) | The CPU successfully enters 64-bit mode |
| 4 | [Talk over the serial port](04-serial.md) | I/O ports, the 16550 UART, debugging | "Hello, World!" appears in `/tmp/serial.log` |
| 5 | [Writing to VGA text](05-vga-text.md) | The VGA text buffer at `0xB8000`, writing characters | "Hello World" shown in the QEMU window |
| 6 | [Animate with the PIT timer](06-pit.md) | The 8254 timer, busy-waiting, measuring time | "Hello World!" types itself, 500 ms per char |

Let's begin with [Step 1](01-freestanding.md).
