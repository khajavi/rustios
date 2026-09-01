# Step 1 — Your first freestanding kernel

## The big idea

When you write a normal C program:

```c
int main(void) {
    printf("hi\n");
    return 0;
}
```

...you depend on the **standard library** (glibc, `stdio.h`, etc.). That
library assumes an operating system is already running: `printf` eventually
makes a syscall, `malloc` uses the OS memory manager, and so on.

A kernel has **no OS underneath it**, so it cannot use the C standard library.
Instead it must use only what the C compiler and the CPU give it directly: bare
functions, inline assembly, raw pointers, and integer arithmetic — nothing
more.

We tell the compiler "there is no OS here" with the `-ffreestanding` flag, and
we compile against what amounts to a bare target with no runtime.

## Real example: our `src/main.c`

Here is the top of the actual kernel. Notice: no `printf`, no `main` that the
OS calls — just plain functions and raw pointer writes. There is no `panic`
handler because C has no panics; instead we just loop forever at the end (a
kernel never returns):

```c
#define VGA_BUFFER ((volatile unsigned char *)0xb8000)
#define WHITE_ON_BLACK 0x0f

static void put_char(unsigned index, char c, unsigned char attr) {
    VGA_BUFFER[index * 2]     = (unsigned char)c;   /* the character */
    VGA_BUFFER[index * 2 + 1] = attr;               /* its color     */
}

__attribute__((noreturn))
void kmain(unsigned long boot_info, unsigned long magic) {
    (void)boot_info;
    (void)magic;
    /* ... print "Hello, World!" ... */
    for (;;) { }   /* park the CPU — a kernel never returns */
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

We build that header in C as a plain array, then force it into a special
section (`.multiboot`) and mark it `used` so the linker does not throw it
away:

```c
#define MULTIBOOT2_MAGIC  0xe85250d6u   // the multiboot2 magic number
#define MULTIBOOT2_ARCH_I386 0u         // 0 = 32-bit (i386) kernel
#define MULTIBOOT2_HEADER_LENGTH 24u    // size of the header, in bytes
#define MULTIBOOT2_CHECKSUM \
    ((0u - MULTIBOOT2_MAGIC) - MULTIBOOT2_ARCH_I386 - MULTIBOOT2_HEADER_LENGTH)
                                        // magic + arch + len + checksum == 0

__attribute__((section(".multiboot"), used))
static const unsigned int multiboot_header[6] = {
    MULTIBOOT2_MAGIC,
    MULTIBOOT2_ARCH_I386,
    MULTIBOOT2_HEADER_LENGTH,
    MULTIBOOT2_CHECKSUM,
    0,   /* end tag: type = 0, flags = 0 */
    8,   /* end tag: size  = 8           */
};
```

There are three ideas to absorb:

1. **`__attribute__((section(".multiboot")))`** — places the array into a
   section named `.multiboot`, which our linker script puts at the very front
   of the binary so GRUB finds it first.
2. **`used`** — stops the compiler from removing the array as "dead code"
   (nothing in our program ever reads it; the boot loader does).
3. **The array is `const`** — its bytes are emitted verbatim into the binary,
   laid out exactly as the multiboot2 spec expects: four `u32` words of header,
   then the 8-byte end tag, for a total of 24 bytes.

The end tag (type `0`) is the *only* tag we need. We keep the header as small
as possible, because we print through the **VGA text buffer** in
[Step 5](05-vga-text.md) rather than asking GRUB for a graphical framebuffer.

> Want the full, beginner-friendly story of what each of these 24 bytes does
> and why? Jump ahead to [Step 7 — the multiboot2 header, for
> beginners](07-multiboot.md).

### Where does the "Hello" actually start?

Real kernels do not jump straight into C. There is an **assembly** prologue
that must run first (setting up a stack). We study that in
[Step 3](03-bootstrap.md). For now, know that `boot.s`'s `_start` sets up the
stack and then calls `kmain`, which is where our logical code begins, and
everything before it is machine setup.

## Why do we need Nix to build this?

Writing the `.c` source isn't enough to produce something GRUB can boot. We
must:

- compile for **32-bit** (`-m32`) as a **freestanding** program
  (`-ffreestanding`, `-nostdlib`), so no operating-system runtime is linked;
- assemble the `.s` bootstrap file;
- link everything with a **linker script** that tells the linker "put the
  kernel at address 1 MiB, and place `.multiboot` first."

Doing all of that reliably by hand is error-prone. That's exactly what
[Step 2](02-nix.md) automates.
