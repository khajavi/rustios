# Step 1: What is a boot sector?

When the computer powers on, the **BIOS** (Basic Input/Output System) runs
hardware checks, then reads the first **512 bytes** from the boot device
(USB, hard disk, CD-ROM). This is the **Master Boot Record (MBR)**.

The BIOS:

1. loads those 512 bytes to memory address **`0x7C00`**;
2. checks that the last two bytes are **`0x55 0xAA`** (the "boot signature");
3. if valid, jumps to `0x7C00` — your code is now running;
4. if not valid, shows "Operating System not found" or moves to the next
   boot device.

---

## Layout of a boot sector

```
offset 0x000   ┌──────────────────────────────┐
               │    Executable code             │
               │    (your instructions)         │
               │                                │
               │    ...                         │
offset 0x1FE   ├──────────────────────────────┤
               │    0x55        (byte 510)      │
               │    0xAA        (byte 511)      │
offset 0x200   └──────────────────────────────┘
```

That's it — 512 bytes total. The first 510 bytes can be whatever you want
(code, data, strings). The last two bytes **must** be `0x55 0xAA` or the
BIOS will not recognize the sector as bootable.

---

## Why "Hello, World!" is simple in a boot sector

The BIOS has already set up basic hardware. You do not need to:

- configure memory (the BIOS does this);
- set up the display (it starts in 80×25 text mode);
- load a kernel (there is no kernel yet — you *are* the kernel).

All you need to do is:

1. write a string to VGA memory (`0xB8000`), **or**
2. call BIOS interrupt `0x10` (teletype output).

The second approach is simpler and works in real mode. That is what we use
in `kernel.s`.

---

## Next

In the next step we look at **16-bit real mode**: the execution environment
the BIOS hands us, and why it matters that we start with only 16-bit
registers and a tiny address space.
