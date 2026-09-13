# Step 6: Running and testing

---

## Build the image

```bash
nix build .#default
ls -l result/helloworld.img
```

Output should be exactly **512 bytes**.

---

## Verify the boot signature

```bash
xxd result/helloworld.img | tail -1
```

The last two bytes of the file (offset `0x1FE`) must be `55 AA`.

---

## Boot in QEMU

```bash
nix run .#run
```

A QEMU window opens. You should see:

```
SeaBIOS (version ...)
...
Booting from Hard Disk...
Hello, World!
Booted with GNU assembly
```

The first few lines are the SeaBIOS banner. The last two lines are **our
boot sector printing**.

---

## What if it does not work?

**No "Booting from Hard Disk..."**
Check that the image is exactly 512 bytes and ends with `55 AA`.

**Screen stays blank / SeaBIOS loops**
The boot signature may be missing or the image was not built correctly.
Rebuild with `nix build .#default` and re-check.

**"Boot failed: could not read the boot disk"**
QEMU may not be recognizing the raw image format. Ensure the drive
argument is `-drive format=raw,file=...`.

---

## Using the QEMU monitor

You can inspect VGA memory directly:

```bash
qemu-system-x86_64 -drive format=raw,file=result/helloworld.img -nographic -monitor stdio
```

Then at the `(qemu)` prompt:

```
xp /2000bx 0xb8000
```

This dumps the first 2000 bytes of VGA text memory. Every even byte is a
character, every odd byte is an attribute (color). Decode every other
byte to read the on-screen text.

---

## Next steps

Now that you have a working boot sector, you could:

- load a second sector from disk (stage 2);
- switch to 32-bit protected mode;
- load a kernel at a higher address;
- write to VGA memory directly instead of using `int 0x10`.

See the other branches of this repository (`c-i686-vga-text`,
`asm-i686-vga-text`) for examples of these next steps.
