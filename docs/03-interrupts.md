# Step 3: BIOS Interrupts

The BIOS provides a library of **interrupt handlers** that talk to hardware
for you. You invoke them with the `int` instruction and a vector number.

---

## The teletype output: INT 0x10, AH=0x0E

This is the simplest way to print a character in real mode:

```asm
mov  $0x0E, %AH    # function: teletype output
mov  $'H', %AL     # character to print
int  $0x10          # call BIOS video services
```

The BIOS:

1. writes the character at the current cursor position in VGA memory;
2. advances the cursor;
3. handles scrolling if the cursor is at the bottom of the screen.

You do not need to know where the cursor is — the BIOS tracks it in the
**BIOS Data Area (BDA)**.

---

## Common BIOS interrupts

| Vector | Service | Example |
|--------|---------|---------|
| `0x10` | Video | `AH=0x0E` teletype, `AH=0x00` set mode |
| `0x13` | Disk | `AH=0x02` read sectors, `AH=0x03` write |
| `0x19` | Reboot | warm reboot |
| `0x15` | Misc | `AH=0x86` wait, memory map |

---

## Why we use interrupts instead of writing VGA directly

Writing to `0xB8000` is faster, but you must manage the cursor yourself.
The BIOS interrupt `0x10` handles:

- cursor advancement;
- line wrapping;
- scrolling when the screen is full.

For a tiny boot sector, this is a convenient trade-off.

---

## The print loop in our kernel

```asm
print:
    lodsb              # load byte at DS:SI into AL, increment SI
    testb  %al, %al   # is it zero?
    je     .done       # yes → done
    movb   $0x0E, %ah  # teletype function
    int    $0x10        # print it
    jmp    print        # next character
.done:
    ret
```

The string is NUL-terminated. `lodsb` auto-increments `SI`, so each
iteration reads the next byte.

---

## Next

The next step walks through the full `kernel.s` source file, line by line.
