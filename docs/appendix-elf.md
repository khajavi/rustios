# Appendix A — What is an ELF file?

Throughout this tutorial we say "ELF", "the kernel object file", "link", and
so on, without stopping to explain what an ELF actually is. If you've ever
wondered *"what exactly is in that `kernel` file, and why is it shaped the
way it is?"* — this appendix is for you.

## The short answer

**ELF** (Executable and Linkable Format) is the standard *file format* that
Linux and most other Unix-like systems use to store programs. When we run
`gcc`/`as`/`ld`, every file they produce — the object files (`main.o`,
`boot.o`) and the final `kernel` — is an ELF file.

Think of ELF as the *container* or *package* that holds machine code, plus a
bunch of metadata about it: which pieces are code, which are data, where each
piece should sit in memory, where execution starts, and so on.

A raw blob of CPU instructions is useless on its own. To load a program, the
loader (GRUB, in our case) needs to know things like:

- *How big is each section of code and data?*
- *At what memory address should each section be placed?*
- *Where is the entry point (the first instruction to run)?*

ELF is the agreed-upon way to encode all of that in one file.

## Problem 0: the toolbox

Let's see an ELF file in action. We have two invaluable tools, both in
`binutils`:

- **`readelf`** — dumps the human-readable metadata of an ELF file.
- **`objdump`** — disassembles it (machine code → assembly) and shows section
  contents.

Run them on our built kernel:

```bash
K=$(nix build .#default --no-link --print-out-paths)/kernel
readelf -h $K      # the ELF header
readelf -S $K      # the section table
objdump -d $K      # the disassembly
```

## The big picture: an ELF file's anatomy

An ELF file is a sequence of parts. The three you'll hear about constantly are
the **ELF header**, the **section header table**, and the **program header
table**:

```
┌──────────────────────────────────────────────┐
│ ELF header  (readelf -h)                     │  ← "what kind of file is this,
│  magic, class, machine, entry point, ...     │     and where is everything?"
├──────────────────────────────────────────────┤
│ Program header table (readelf -l)            │  ← "what should be loaded into
│  segments: PT_LOAD, ...                      │     memory, and where?"
├──────────────────────────────────────────────┤
│ Sections  (readelf -S)                       │  ← "the actual content":
│  .text (code), .data, .rodata, .bss, ...     │     code + data + metadata
├──────────────────────────────────────────────┤
│ Section header table                         │  ← an index that says where
│                                              │     each section begins
└──────────────────────────────────────────────┘
```

Let's go through each.

## 1. The ELF header

The very first bytes of the file. `readelf -h` shows it. The key fields:

- **`Magic`** — the bytes `7f 45 4c 46` (which spell `\x7fELF`). Like the
  multiboot2 magic, it's a marker: *"this is an ELF file."*
- **`Class`** — `ELF32` or `ELF64` (how wide addresses are). Ours is
  `ELF32` because we build a 32-bit kernel.
- **`Machine`** — the CPU architecture (`Intel 80386` for us; `X86-64` for the
  64-bit branches).
- **`Entry point address`** — the virtual address where execution begins.
  For us this is `_start`, at `0x100000` (1 MiB, placed by our linker script).
- **`Type`** — `EXEC` (an executable) vs `REL` (a relocatable object file).
  Our `main.o` is `REL`; the final `kernel` is `EXEC`.

```text
$ readelf -h kernel
ELF Header:
  Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00
  Class:                             ELF32
  Machine:                           Intel 80386
  Entry point address:               0x100000
  ...
```

## 2. Sections — where the content lives

A section is a labeled chunk of the file with a purpose. The ones we care
about match our linker script exactly:

| Section | Contains |
|---------|----------|
| `.multiboot` | our multiboot2 header (the 24 bytes from Step 7) |
| `.text` | the actual CPU instructions (code) |
| `.rodata` | read-only data (e.g. the `"Hello, World!"` string) |
| `.data` | read-write data (initialized global variables) |
| `.bss` | **zero-initialized** data (no bytes stored in the file; just marked "this much space needs zeroing") |

`readelf -S` prints a table of all sections, with their offsets and sizes.

## 3. Program headers / segments — what to load into memory

A *section* is a compile-time concept (what's in the file). A *segment* is a
**runtime** concept (what gets loaded into memory and executed). The **program
header table** lists segments — think of these as *"this chunk of the file
should be loaded at this memory address with these permissions."*

`readelf -l` shows them. You'll typically see a code segment (`LOAD`) and the
data segments. GRUB reads this table to know where in memory to place your
kernel before jumping to the entry point.

## Object files vs. executables: `REL` vs `EXEC`

There are a few "flavors" of ELF. In this tutorial we see two:

- **Relocatable object file** (`.o`, type `REL`) — produced by `gcc -c` and
  `as`. It contains sections, but addresses may still be *symbolic* (e.g.
  `_start`, `kmain`) rather than final. It is not yet runnable on its own.
- **Executable** (type `EXEC`) — produced by `ld`. Every symbol has a fixed
  address, program headers are computed, and it can be loaded and run.

That's why Step 2 is a *link* step, not just a compile step: linking is what
turns two `.o` files (with unresolved symbols) into one `EXEC` with a real
entry point at a real address.

## The role of the linker script

You saw `linker.ld` in Steps 2 and 4. Now its purpose is crystal clear: it
tells `ld` *how to build the ELF file* — specifically,

- what `OUTPUT_FORMAT` to use (`elf32-i386` — so the ELF header says `ELF32`,
  `Intel 80386`),
- `ENTRY(_start)` — the entry point address recorded in the ELF header,
- how to arrange the sections and at what base address (`. = 1M`).

Without the linker script, `ld` uses defaults that wouldn't put `.multiboot`
first or place the kernel at 1 MiB — and GRUB wouldn't boot us.

## Tying it back to booting

Here's how it all comes together when you boot:

1. GRUB opens the `kernel` file and reads the **ELF header** (magic, class,
   machine, entry point).
2. GRUB reads the **program headers** to learn what to load where in memory,
   and places the sections at the addresses your linker script chose.
3. GRUB **jumps to the entry point** (`_start`) — and your kernel begins.

The ELF file is the *messenger* that hands the boot loader all the info it
needs to start your code correctly.

## The bottom line

**ELF is just a well-organized container** for machine code plus metadata.
It's not magic — it's the standard "box" that Linux, our build tools, and GRUB
all agree to use. When you run `readelf`/`objdump` on your tiny kernel, you are
reading the exact same kind of structure that ships in every Linux executable
on your machine — just far smaller.
