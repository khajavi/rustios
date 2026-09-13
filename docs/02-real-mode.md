# Step 2: 16-bit Real Mode

When the CPU powers on, it starts in **16-bit real mode**. This is a legacy
of the Intel 8086 from 1978 — every x86 CPU begins here, even modern 64-bit
processors.

---

## What real mode looks like

| Feature | Value |
|---------|-------|
| Register width | 16 bits (`AX`, `BX`, …) |
| Address space | 20 bits (1 MiB) |
| Memory model | Segmented (`segment:offset`) |
| Privileges | ring 0 (everything) |
| Instructions | 8086 subset |

---

## Registers

The general-purpose registers are:

```
 15      8 7       0
┌─────────┬─────────┐
│ AH      │ AL      │  → AX (accumulator)
├─────────┼─────────┤
│ BH      │ BL      │  → BX (base)
├─────────┼─────────┤
│ CH      │ CL      │  → CX (counter)
├─────────┼─────────┤
│ DH      │ DL      │  → DX (data)
└─────────┴─────────┘
```

Segment registers: `CS` (code), `DS` (data), `SS` (stack), `ES` (extra).

---

## Address calculation

A 20-bit physical address is formed as:

```
physical = segment × 16 + offset
```

So when the BIOS jumps to `0x7C00`, the actual execution address is
`CS:IP = 0x0000:0x7C00` (or `0x07C0:0x0000` — the BIOS typically sets
`CS=0x07C0` or `CS=0x0000` depending on the implementation).

In our kernel we explicitly set `DS=0`, `SS=0`, and `SP=0x7C00`, so
`DS:SI = 0x0000:SI` gives a clean linear address.

---

## Why this matters

In real mode you can access only the first 1 MiB of memory. The VGA text
buffer is at `0xB8000` — safely within range. You can also call BIOS
interrupts (`int 0x10`, `int 0x13`, …) which provide built-in routines for
I/O, disk access, and more.

There is no memory protection. If you write to the wrong address, nothing
stops you — the CPU happily overwrites whatever is there.

---

## Next

The next step covers the BIOS interrupts we use to print characters on
screen.
