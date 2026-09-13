# Assembly Language Primer: Understanding boot.s from Zero

Welcome! If you've never seen assembly language before, the `boot.s` file might look like cryptic gibberish. This guide teaches you everything you need to understand it — starting from absolute basics.

## What is assembly language?

Assembly is a human-readable way to write machine code — the actual instructions the CPU understands. Every program you run, whether written in C, Python, or Rust, is eventually translated down to assembly by a compiler.

Think of it like this:

- **High-level languages** (C): `int result = a + b;` (tells the _what_)
- **Assembly**: `addl %eax, %ebx` (tells the CPU exactly _how_)

The CPU physically executes assembly instructions. Assembly is the closest thing to talking directly to the hardware.

### Why do we need assembly?

The CPU's behavior at boot time is controlled by the _hardware_, not the operating system. At the exact moment GRUB hands control to our kernel, the CPU is in a specific state with specific registers holding specific values. To work with that hardware state — to set up a stack, jump to our C code, and halt cleanly — we _must_ use assembly. There's no C to do it for us yet (C is still "above" hardware at this point).

---

## The CPU: registers and memory

Before we read `boot.s`, you need to understand how the CPU stores data.

### Registers: tiny, fast memory inside the CPU

A register is a small storage location _inside_ the CPU itself. Registers are:

- **blazingly fast** (no memory access needed)
- **limited in number** (the 32-bit x86 CPU has only a handful)
- **each has a name and purpose**

On the 32-bit x86 CPU, the main registers are:

| Register | Name              | Purpose                                                    |
| -------- | ----------------- | ---------------------------------------------------------- |
| `eax`    | accumulator       | general purpose; return value; often used for arithmetic   |
| `ebx`    | base              | general purpose; often used to hold addresses              |
| `ecx`    | counter           | general purpose; used in loops                             |
| `edx`    | data              | general purpose; used for arithmetic (especially division) |
| `esp`    | stack pointer     | **points to the top of the call stack**                    |
| `ebp`    | base pointer      | **points to the current function's stack frame**           |
| `esi`    | source index      | often used to point to memory addresses                    |
| `edi`    | destination index | often used to point to memory addresses                    |

The key ones for `boot.s` are **`eax`**, **`ebx`**, and **`esp`**.

### The stack: a region of memory for function calls

The **stack** is a special region of memory used for:

- storing function arguments
- storing return addresses (so the CPU knows where to jump back)
- storing local variables

The stack grows **downwards** in memory (from high addresses to low addresses). The register `esp` (stack pointer) always points to the _top_ of the stack — the address of the last thing pushed.

When you `push` a value:

```
esp -= 4              (move esp down 4 bytes, because we're on 32-bit where ints are 4 bytes)
memory[esp] = value   (write the value)
```

When you `pop` a value:

```
value = memory[esp]   (read the value)
esp += 4              (move esp up)
```

---

## How GRUB starts your kernel

When GRUB loads our kernel and transfers control, here's what happens:

1. **GRUB loads the kernel into memory** at address `0x100000` (1 MiB)
2. **GRUB jumps to the `_start` label**, handing control to our assembly code
3. **GRUB passes two values in registers**:
   - `eax = 0x36d76289` (the "magic number" — proof we were booted by a real multiboot2 bootloader)
   - `ebx = address of the multiboot2 information structure` (data about the boot environment)
4. **`esp` is undefined** — the CPU's stack pointer points to garbage

Our job in `boot.s` is to:

1. Set up `esp` to point to real memory
2. Pass those two register values to our C function `kmain()`
3. Stop the CPU if anything goes wrong

---

## Reading x86-32 assembly syntax

Assembly has a specific syntax. There are two main flavors; we use **AT&T syntax** (the default on Unix/Linux).

### Instruction format

```
instruction source, destination
```

**Important: the direction is backwards from what you might think!** The value moves _from_ source _to_ destination.

```asm
movl $100, %eax    # Move the number 100 INTO eax
                   # NOT "move eax into 100"
```

### Prefixes in AT&T syntax

- **`%`** before a register name: `%eax`, `%ebx`, `%esp`
- **`$`** before a number: `$100`, `$16384`
- No prefix for memory addresses like labels

Examples:

```asm
movl  $100, %eax       # Move literal number 100 into eax
movl  %ebx, %eax       # Move the *value* in ebx into eax
movl  stack_top, %esp  # Move the *address* of stack_top into esp
```

### Instruction size suffix

Instructions have a suffix indicating the size of data:

- **`b`** = byte (8 bits)
- **`w`** = word (16 bits)
- **`l`** = long (32 bits, the default on 32-bit x86)
- **`q`** = quad (64 bits, only on 64-bit x86-64)

For 32-bit code, you'll almost always see `l`:

```asm
movl %eax, %ebx    # Move 32-bit value
pushl %eax         # Push 32-bit value
addl $1, %ecx      # Add 32-bit value
```

---

## Assembly directives (not instructions)

Assembly files contain both **instructions** (which the CPU executes) and **directives** (which tell the assembler how to organize the code). Directives start with a dot (`.`).

Common directives:

| Directive       | Meaning                                       |
| --------------- | --------------------------------------------- |
| `.section NAME` | Start a named section of code/data            |
| `.bss`          | Uninitialized data (zeroed by the bootloader) |
| `.text`         | Code (executable)                             |
| `.data`         | Initialized data                              |
| `.code32`       | This code is 32-bit (not 16-bit or 64-bit)    |
| `.global LABEL` | Make a label visible to the linker            |
| `.balign N`     | Align the next data to an N-byte boundary     |
| `.skip N`       | Reserve N bytes of memory (padding)           |

---

## Walking through boot.s line by line

Now let's understand the actual code!

### Part 1: Setting up the stack (lines 15-19)

```asm
.section .bss, "", "nobits"
.balign 16
stack_bottom:
    .skip 16384
stack_top:
```

**What does this do?**

- **`.section .bss`**: Start a section called `.bss` (uninitialized data). The bootloader will zero-fill this region.
- **`.balign 16`**: Align the next data to a 16-byte boundary. This is just good practice; some CPUs work better with aligned memory.
- **`stack_bottom:`**: A _label_ marking the start of our stack region. Labels are just names for memory addresses.
- **`.skip 16384`**: Reserve 16,384 bytes (16 KiB) of uninitialized memory. This is our stack.
- **`stack_top:`**: A label marking the end of our stack region.

**Why two labels?**
They're bookends. `stack_bottom` marks where the stack _starts_, and `stack_top` marks where it _ends_ (and where we'll point `esp`). We remember: the stack grows downward, so `stack_top` is actually at the highest address, and that's where we initialize `esp`.

**Mental model**: Think of a physical stack of plates. You add plates to the _top_. In memory, "top" means the highest address. We start at `stack_top` (high address) and the stack grows downward to `stack_bottom` (low address) as we push values.

### Part 2: Code setup and entry point (lines 21-24)

```asm
.section .text
.code32
.global _start
_start:
```

**What does this do?**

- **`.section .text`**: Switch to the `.text` section (executable code), not `.bss`.
- **`.code32`**: Tell the assembler "the following code is 32-bit" (not 16-bit real mode or 64-bit).
- **`.global _start`**: Make the label `_start` visible to the linker. The bootloader will jump here.
- **`_start:`**: The actual label. This is the entry point — where execution begins.

### Part 3: Set up the stack (line 25)

```asm
movl $stack_top, %esp
```

**What does this do?**

- **`movl`**: Move a 32-bit value
- **`$stack_top`**: The _address_ of the label `stack_top`. The `$` means it's a literal number (the address), not a register.
- **`%esp`**: Load it into the stack pointer register

**Why?**
Without this line, `esp` contains garbage. Any attempt to `push` or `call` would corrupt random memory. This line initializes the stack so we can safely make function calls.

**Mental model**: We're saying "CPU, the stack is now at this address. When you need to push values, put them here and work your way down."

### Part 4: Pass arguments to kmain (lines 26-27)

```asm
pushl %eax
pushl %ebx
```

**What does this do?**

- `pushl %eax`: Push the value in `eax` (the magic number) onto the stack
- `pushl %ebx`: Push the value in `ebx` (the boot info address) onto the stack

**Why does the order matter?**

In the **cdecl calling convention** (the 32-bit C convention), function arguments are pushed right-to-left. So for a C function call:

```c
kmain(boot_info, magic)
```

We push:

1. `magic` last (so it's deepest in the stack)
2. `boot_info` first (so it's shallowest in the stack)

But GRUB gives us:

- `eax = magic`
- `ebx = boot_info`

So we push in the opposite order of how GRUB gives them to us:

```asm
pushl %eax       # Push magic second (so it ends up deeper)
pushl %ebx       # Push boot_info first (so it ends up shallower)
```

Wait, that looks backwards! Let's trace through the stack visually:

**After `pushl %eax` (pushing the magic number):**

```
esp -> [magic]        <- stack pointer points here
       [garbage]
```

**After `pushl %ebx` (pushing the boot info):**

```
esp -> [boot_info]    <- stack pointer points here (moved down)
       [magic]
       [garbage]
```

When the CPU executes `call kmain`, the return address is pushed:

```
esp -> [return address]
       [boot_info]    <- first argument (offset +4 from esp after call)
       [magic]        <- second argument (offset +8 from esp after call)
       [garbage]
```

Inside `kmain`, the C code reads:

- first parameter (`boot_info`) from `esp+4`
- second parameter (`magic`) from `esp+8`

**Memory layout is confusing.** The key insight: we push in the order `eax` then `ebx` because that's how cdecl works. The CPU and C compiler know the convention; we just follow it.

### Part 5: Call the C function (line 28)

```asm
call kmain
```

**What does this do?**

- **`call kmain`**: Jump to the `kmain` function
- Automatically push the _return address_ (the address of the next instruction) onto the stack

The CPU:

1. Pushes the address of the next instruction (`halt:`) onto the stack
2. Jumps to `kmain`

The stack now looks like:

```
esp -> [return address (address of halt:)]
       [boot_info]
       [magic]
```

Inside `kmain`, the C code can:

- Access its two arguments from the stack
- Use local variables on the stack
- Eventually execute `return` to pop the return address and jump back to `halt:`

But wait — our `kmain` is declared `__attribute__((noreturn))`. It never returns. It just loops forever at the end. So the next lines (`halt:` and beyond) will never execute in normal operation.

### Part 6: Halt the CPU (lines 29-32)

```asm
halt:
    cli
    hlt
    jmp halt
```

**What does this do?**

- **`halt:`**: A label (unreachable in normal operation, but safe if something goes wrong)
- **`cli`**: "Clear interrupts" — disable hardware interrupts
- **`hlt`**: "Halt" — put the CPU in a low-power state, waiting for an interrupt
- **`jmp halt`**: Jump back to `halt:` (paranoia — in case an interrupt somehow wakes us up)

**Why?**
A kernel never returns. If something unexpectedly causes `kmain` to return, we land here and shut down cleanly instead of crashing into undefined behavior.

---

## The calling convention in detail

This deserves its own section because it's the trickiest part.

### cdecl (32-bit C calling convention)

When you call a function in 32-bit C, these rules apply:

1. **Arguments are pushed right-to-left** (rightmost first)
2. **Caller cleans up the stack** (caller adds to esp after return)
3. **Return value is in `eax`**
4. **Caller must preserve** `esi`, `edi`, `ebp`, `esp` (callee can trash the others)

### Example: calling `printf("hello %d", 42)` in assembly

```c
printf("hello %d", 42);  // Rightmost arg (42) pushed first
```

In assembly:

```asm
pushl $42           # Push rightmost arg first
pushl $0x...        # Push address of "hello %d" string
call printf         # Jump to printf; CPU pushes return address
addl $8, %esp       # Caller cleans up: remove 2 args (2 * 4 bytes)
```

### Example: calling `kmain(boot_info, magic)` in assembly

```c
// This never happens (it's called from boot.s, not from C)
// But if it did in C:
kmain(boot_info, magic);
```

In assembly (what we do):

```asm
pushl %eax          # Push magic (rightmost arg)
pushl %ebx          # Push boot_info (leftmost arg)
call kmain          # CPU pushes return address
# No cleanup needed because kmain never returns
```

**The key insight**: The order of arguments in C determines the order we push them. Rightmost first. `boot_info` is leftmost, so it gets pushed second (and ends up shallower in the stack). `magic` is rightmost, so it gets pushed first (and ends up deeper).

---

## Common assembly instructions for boot.s

You don't need to memorize all x86 instructions. Here are the ones in `boot.s`:

| Instruction | Syntax              | What it does                                                  |
| ----------- | ------------------- | ------------------------------------------------------------- |
| `movl`      | `movl source, dest` | Copy a 32-bit value from source to dest                       |
| `pushl`     | `pushl value`       | Push a 32-bit value onto the stack (esp -= 4, then write)     |
| `popl`      | `popl dest`         | Pop a 32-bit value from stack into dest (read, then esp += 4) |
| `call`      | `call label`        | Jump to a label and push the return address                   |
| `ret`       | `ret`               | Pop the return address and jump to it                         |
| `jmp`       | `jmp label`         | Unconditional jump to a label                                 |
| `cli`       | (no args)           | Clear interrupts (disable hardware interrupts)                |
| `hlt`       | (no args)           | Halt the CPU (wait for interrupt)                             |

---

## What happens at runtime

Let's trace through the entire execution:

1. **GRUB boots**: Loads our kernel into memory at `0x100000`, sets `eax = 0x36d76289`, sets `ebx = boot_info_address`
2. **GRUB jumps to `_start`**: Execution begins at the `_start` label
3. **`movl $stack_top, %esp`**: Initialize the stack pointer to point to our reserved stack memory
4. **`pushl %eax`**: Push the magic number onto the stack
5. **`pushl %ebx`**: Push the boot info address onto the stack
6. **`call kmain`**:
   - CPU pushes return address (`halt:`)
   - CPU jumps to `kmain`
7. **Inside `kmain`**: C code runs, prints "Hello, World!", loops forever
8. **CPU runs forever** in the loop inside `kmain`
9. **(If `kmain` somehow returned)**: Execution would land at `halt:`, disable interrupts, and halt the CPU

---

## Why this is important

You might think: "Why learn assembly? Why not just let the compiler handle it?"

Three reasons:

1. **The bootloader-kernel interface is a hardware boundary**. At boot time, there's no C runtime yet. Only assembly can speak the hardware's language.
2. **Understanding assembly demystifies what the CPU actually does**. C abstracts hardware away; assembly shows you the truth.
3. **It's educational**. The 32 lines of `boot.s` teach you more about how computers work than hundreds of lines of C could.

Congratulations! You now understand `boot.s`. The next section, [03-bootstrap.md](03-bootstrap.md), dives into the conceptual side (why no GDT, why no long-mode switch, etc.). But you now have the _how_. The CPU understands this code, line by line.

---

## Summary: cheat sheet

| Concept         | What it is                                                                 |
| --------------- | -------------------------------------------------------------------------- |
| **Register**    | Fast storage inside the CPU (e.g., `%eax`)                                 |
| **Stack**       | Memory region for function calls, grows downward                           |
| **Label**       | Name for a memory address                                                  |
| **Directive**   | Assembler instruction (starts with `.`), not CPU instruction               |
| **AT&T syntax** | Unix assembly syntax (register prefix `%`, immediate prefix `$`)           |
| **`movl`**      | Copy a 32-bit value                                                        |
| **`pushl`**     | Push a value onto the stack                                                |
| **`call`**      | Jump to a function, save return address                                    |
| **`cli`**       | Disable interrupts                                                         |
| **`hlt`**       | Halt the CPU                                                               |
| **cdecl**       | 32-bit C calling convention (arguments right-to-left, caller cleans stack) |

---

## Next: Why does boot.s look like that?

Now read [Step 3 — The stack and entry point](03-bootstrap.md) to understand the _reasoning_ behind the design: why we don't need a GDT, why 32-bit mode is enough, and how all the pieces fit together.
