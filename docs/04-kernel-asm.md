# Step 4: The assembly source (kernel.s)

Here is the full source with annotations.

---

## Code section

```asm
    .code16              # emit 16-bit code (for real mode)
    .text                # start of code section

    # --- Segment setup ---
    xor   %ax, %ax       # AX = 0
    mov   %ax, %ds       # DS = 0 (data segment)
    mov   %ax, %es       # ES = 0 (extra segment)
    mov   %ax, %ss       # SS = 0 (stack segment)
    mov   $0x7C00, %sp   # SP = 0x7C00 (stack grows down from here)
```

The CPU starts with unknown segment values. We zero them all and set the
stack pointer to `0x7C00` — the stack grows downward, so it will use the
area just below our code.

---

## Loading the string address

```asm
    mov   $message, %si   # SI = address of the NUL-terminated string
```

With `DS=0`, the effective address is `0x0000:SI`. The linker places
`message` at file offset `0x20`, which becomes physical address `0x7C20`
(`0x7C00 + 0x20`).

---

## Calling the print routine

```asm
    call  print           # call print routine
    hlt                   # stop the CPU
    jmp   .               # infinite loop (safety net)
```

After printing, we halt. The `hlt` instruction stops the CPU until the
next interrupt (which we do not enable), so the CPU sits idle.

---

## The print routine

```asm
print:
    lodsb                 # AL = [DS:SI]; SI++
    testb %al, %al        # is AL == 0?
    je    .done            # yes → string finished
    movb  $0x0E, %ah      # AH = 0x0E (teletype)
    int   $0x10            # call BIOS video
    jmp   print            # next character
.done:
    ret                   # return to caller
```

`lodsb` reads one byte and advances `SI`. The loop continues until it
hits the NUL terminator.

---

## The string

```asm
message:
    .asciz "Hello, World!\r\nBooted with GNU assembly"
```

`.asciz` emits the string followed by a NUL byte (`0x00`). The `\r\n`
gives a proper Windows-style line ending on the VGA console.

---

## Boot sector padding and signature

```asm
    .org 510              # advance to byte 510 (0x1FE)
    .word 0xAA55          # boot signature (little-endian: 55 AA)
```

Whatever comes before byte 510 is padding (zeros). The `.word 0xAA55`
places the magic bytes the BIOS expects.

---

## Next

The next step explains the build system: how Nix compiles, links, and
packages this into a raw 512-byte image.
