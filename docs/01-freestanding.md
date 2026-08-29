# Step 1 — Your first freestanding kernel

## The big idea

When you write a normal Rust program:

```rust
fn main() {
    println!("hi");
}
```

...you depend on the **standard library** (`std`). That library assumes an
operating system is already running: `println!` calls a syscall, heap
allocation uses the OS memory manager, and so on.

A kernel has **no OS underneath it**, so it cannot use `std`. Instead it must
use only what the Rust compiler and the CPU give it directly: bare functions,
inline assembly, raw pointers, and the `core` crate (the part of the standard
library that does *not* need an OS, like `u32` arithmetic and `for` loops).

We tell Rust "there is no OS here" with two crate-level attributes at the top
of your source file:

```rust
#![no_std]   // don't link the operating-system-dependent standard library
#![no_main]  // don't expect a `fn main`
```

`#![no_std]` removes `std`. `#![no_main]` tells the compiler "I am not a
normal program with a `main`; I will define my own entry point."

## Real example: our `src/main.rs` header

Here is the top of the actual kernel. Notice: no `main`, no `println!`, and a
`#[panic_handler]` that just halts forever (because with no OS, "reporting an
error" means nothing more than stopping):

```rust
#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}   // stay here forever — there is no OS to call
}
```

## The multiboot2 header — your contract with the boot loader

Before the CPU runs our code, a **boot loader** (we use GRUB) must load our
kernel into memory. But how does GRUB know our binary is actually a kernel?
We must give it a *signature* it recognizes. That signature is a **multiboot2
header**: a fixed block of bytes placed at the very start of the kernel file.

The header says, in effect:

> "Hello boot loader. I am a multiboot2 kernel. If you understand this, load
> me into memory at the address I want, then jump to my entry point."

We build that header in Rust as a `struct`, then force it into a special
section (`.multiboot`) and mark it `#[used]` so the linker does not throw it
away:

```rust
const MAGIC: u32 = 0xe85250d6;       // the multiboot2 magic number
const ARCHITECTURE: u32 = 0;         // 0 = 32-bit (i386) kernel
const HEADER_LENGTH: u32 = 48;       // size of the header, in bytes
const CHECKSUM: u32 = (0u32.wrapping_sub(MAGIC))
    .wrapping_sub(ARCHITECTURE)
    .wrapping_sub(HEADER_LENGTH);    // magic + arch + len + checksum == 0

#[repr(C)]
#[repr(align(8))]
struct Multiboot2Header {
    magic: u32,
    architecture: u32,
    header_length: u32,
    checksum: u32,
    // framebuffer request tag: type = 5, flags = 0, size = 20
    fb_type: u16,
    fb_flags: u16,
    fb_size: u32,
    fb_width: u32,
    fb_height: u32,
    fb_depth: u32,
    pad: u32,
    // end tag: type = 0, flags = 0, size = 8
    end_type: u16,
    end_flags: u16,
    end_size: u32,
}

#[used]
#[link_section = ".multiboot"]
static MULTIBOOT_HEADER: Multiboot2Header = Multiboot2Header { /* ... */ };
```

There are three ideas to absorb:

1. **`#[repr(C)]`** — tells Rust to lay out the struct's fields in the same
   order and sizes C would. That way the bytes in memory exactly match what
   the multiboot2 spec expects (no reordering).
2. **`#[repr(align(8))]`** — the spec requires the header to be 8-byte
   aligned.
3. **`#[link_section = ".multiboot"]`** with `#[used]` — places this static at
   the front of the binary in a dedicated section so GRUB finds it first.

The "framebuffer request tag" you see (type `5`) is how we *ask* the boot
loader, "please start me up with an 800x600 32-bit graphical framebuffer." We
will use that in [Step 5](05-framebuffer.md).

### Where does the "Hello" actually start?

Real kernels do not jump straight into Rust. There is an **assembly** prologue
that must run first (setting up a stack, enabling 64-bit mode, etc.). We study
that in [Step 3](03-bootstrap.md). For now, know that Rust's `kmain` is where
our own logical code begins, and everything before it is machine setup.

## Why do we need Nix to build this?

`#![no_std]` isn't enough to produce something GRUB can boot. We must:

- compile for a special **target** (`x86_64-unknown-none` — "64-bit x86, no
  operating system");
- assemble the `.s` bootstrap file;
- link everything with a **linker script** that tells the linker "put the
  kernel at address 1 MiB, and place `.multiboot` first."

Doing all of that reliably by hand is error-prone. That's exactly what
[Step 2](02-nix.md) automates.
