# Step 7 — The multiboot2 header, for beginners

This chapter is a friendly deep-dive into the **multiboot2 header** — the tiny
block of data that makes GRUB understand your binary is a kernel. We touched
it in Step 1; here is the whole story, slowly.

## The problem: "how do you boot a kernel?"

Your `.c` and `.s` files get turned into a normal ELF file. But a normal ELF
file is just *a file*. If you handed it to a computer and said "boot this,"
the machine wouldn't know what to do with it.

Something has to **load** your file into memory and **start** it. That
something is a *boot loader* — for us, GRUB.

> GRUB's job: look at your file, figure out *where in memory to put it* and
> *where to jump* to begin execution.

The catch: there are lots of different OSes and lots of different kernels.
How can GRUB hope to boot them all? The answer is a **standard contract** — a
common set of rules that GRUB and every kernel agree to follow. That contract
is the **multiboot2 specification**.

## The deal you make with the boot loader

The multiboot2 contract works like a handshake:

1. **You (the kernel)** put a small, well-defined block of bytes at the very
   start of your binary. This is the **multiboot2 header**.
2. **GRUB** scans the first 8 KB of your file for that recognizable pattern.
3. If it finds a valid header, GRUB says *"Oh, you're a multiboot2 kernel —
   I know exactly how to load you!"* and does so: it places your kernel in
   memory at the address you asked for and jumps to your `_start`.

So the header is basically your **name tag and ID card**. Without it, GRUB
refuses to boot you.

## What the header contains (and why each part matters)

The header is just 24 bytes in our kernel — six `u32` (4-byte) words. Here is
the exact layout:

| Byte offset | Field | Value | Meaning |
|---|---|---|---|
| 0 | `magic` | `0xE85250D6` | *"I am a multiboot2 kernel"* — the secret handshake. |
| 4 | `architecture` | `0` | 0 = i386. *"Boot me in 32-bit mode."* |
| 8 | `header_length` | `24` | total size of this header, in bytes. |
| 12 | `checksum` | computed | makes the first 4 words add up to 0 (validity check). |
| 16 | end tag: `type` | `0` | *"that's all the tags I need"* — the marker for "no more requests." |
| 20 | end tag: `size` | `8` | size of this end tag. |

### 1. `magic` — the secret handshake

The value **`0xE85250D6`** is a fixed magic number the multiboot2 spec chose.
When GRUB reads this value at offset 0, it knows *"this file is speaking
multiboot2."* It's like a password that only multiboot2 kernels know.

### 2. `architecture` — "I am 32-bit"

The value `0` tells GRUB *"I am a 32-bit (i386) kernel, please start me in
32-bit protected mode."* That's exactly what our C kernel wants, so this is
easy. (Fun fact: the multiboot2 spec has no "64-bit" value — a 64-bit kernel
still starts as i386 and *switches itself* to 64-bit later. That's what the
sibling `x86_64-*` branches do in their `boot.s`.)

### 3. `header_length` and `checksum` — sanity checks

`header_length` tells GRUB how many bytes the whole header occupies, so it can
walk past it. `checksum` is a **validation**: the four `u32` words
(`magic`, `architecture`, `header_length`, `checksum`) are chosen so that when
you add them together, the result is exactly **0**. If they don't sum to zero,
GRUB knows the header is corrupt and refuses to boot — protecting you from a
silently-broken kernel.

### 4. The end tag — "that's everything"

After the main header come zero or more "tags": small structures where a kernel
can *request* things from GRUB (for example, *"please give me a graphical
framebuffer"* on the `*-framebuffer` branches). Each tag starts with a `type`
and a `size`. We don't ask for anything (we use VGA text, which needs no
request), so we include only the single **mandatory** end tag, whose `type`
is `0` — it means *"no more tags; that's the end."*

## It in our C code

We describe that block of bytes in `src/main.c` as a plain array:

```c
#define MULTIBOOT2_MAGIC  0xe85250d6u
#define MULTIBOOT2_ARCH_I386 0u
#define MULTIBOOT2_HEADER_LENGTH 24u
#define MULTIBOOT2_CHECKSUM \
    ((0u - MULTIBOOT2_MAGIC) - MULTIBOOT2_ARCH_I386 - MULTIBOOT2_HEADER_LENGTH)

__attribute__((section(".multiboot"), used))
static const unsigned int multiboot_header[6] = {
    MULTIBOOT2_MAGIC,          /* offset  0: magic        */
    MULTIBOOT2_ARCH_I386,      /* offset  4: architecture */
    MULTIBOOT2_HEADER_LENGTH,  /* offset  8: header length */
    MULTIBOOT2_CHECKSUM,       /* offset 12: checksum     */
    0,                         /* offset 16: end tag type  */
    8,                         /* offset 20: end tag size  */
};
```

Because it's a `const unsigned int[6]`, the compiler emits exactly those 24
bytes, in exactly that order, into the binary.

## It in our assembly (the pure-assembly branch)

On the `asm-i686-vga-text` branch, the *whole kernel* is one `.s` file — so
the header is written as assembly data directives instead of a C array:

```asm
.section .multiboot, "a"
.balign 8
multiboot_header:
    .long MULTIBOOT2_MAGIC
    .long MULTIBOOT2_ARCH_I386
    .long MULTIBOOT2_HEADER_LEN
    .long MULTIBOOT2_CHECKSUM
    .word 0        # end tag: type
    .word 0        # end tag: flags
    .long 8        # end tag: size
```

Same idea, different language — but inside the file, the bytes are identical.

## Two special things: `.multiboot` section and `used`

Two details make sure the header actually ends up where GRUB can find it:

1. **`__attribute__((section(".multiboot")))`** — this asks the compiler to
   put the array in a section of the object file named `.multiboot` (rather
   than the usual `.data`). Our **linker script** (Step 2) places that section
   at the *very start* of the final binary, so the header is the first thing
   GRUB sees.
2. **`used`** — our C program never *reads* this array (only GRUB, from
   outside, does). Without `used`, the compiler would see it as dead code and
   delete it. `used` whispers to the compiler: *"trust me, something needs
   this — keep it in the binary."*

## Why the header matters for you

Even though you'll rarely touch it again after setting it up, understanding the
multiboot2 header demystifies the very first thing a boot loader does. When you
look at a real kernel (Linux, etc.) you'll see the same idea: a bootstrap
handshake that says "this is a kernel; load me here; jump me there." It's one
of the lightbulb moments of OS development — and now you've built one yourself,
byte by byte.

## Check your progress

You can see the header with GRUB's own tools, or simply boot:

```bash
nix run .#run
```

If GRUB boots your kernel, your header is valid. To *see* the bytes, use
`objdump` on the kernel binary:

```bash
objdump -s --section=.multiboot \
  $(nix build .#default --no-link --print-out-paths)/kernel
```

You should see your 24 bytes beginning with `e8 52 50 d6` — that's the magic
number `0xE85250D6` you wrote, in little-endian byte order.
