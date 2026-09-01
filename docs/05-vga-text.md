# Step 5 — Writing to VGA text

We have a booting kernel that reaches `kmain`. Now the fun part: putting text
on the **QEMU window** itself.

## Concept: what VGA text mode is

In **text mode** the screen is a fixed grid of cells — 80 columns × 25 rows,
or 2000 cells in total. Unlike graphics mode, where every *pixel* has a color,
each *cell* is just one character slot. The graphics card continuously reads a
4 KiB block of physical memory at address **`0xB8000`** and paints whatever it
finds, on every refresh. That is all there is to it: to show text, the kernel
simply writes bytes into memory. No drivers, no drawing, no frame buffer.

## One cell = two bytes

Each cell on the screen is two bytes:

```
cell = [character] [color attribute]
         ↑             ↑
     which letter   background & foreground color
```

- **1st byte**: the ASCII character (`'H'` = `0x48`), and
- **2nd byte**: the color, split into two nibbles — the high nibble is the
  background color and the low nibble is the foreground color.

The attribute `0x0F` therefore means *bright white text on a black
background*.

```
Address     Byte   Meaning
0xB8000     0x48   'H'
0xB8001     0x0F   white on black
0xB8002     0x65   'e'
0xB8003     0x0F   white on black
...         ...    ...
```

## Writing one character in C

The character at screen position `index` (0 = very top-left cell) lives at
address `VGA_BUFFER + index * 2`:

```c
#define VGA_BUFFER ((volatile unsigned char *)0xb8000)
#define VGA_COLS 80
#define VGA_ROWS 25
#define WHITE_ON_BLACK 0x0f

static void put_char(unsigned index, char c, unsigned char attr) {
    VGA_BUFFER[index * 2]     = (unsigned char)c;   /* the character */
    VGA_BUFFER[index * 2 + 1] = attr;               /* its color     */
}
```

We declare the buffer `volatile` because these writes go to real memory-mapped
hardware that the compiler does not know about; it must not cache or reorder
them away.

## Clearing the screen

Boot loaders leave their own text on the screen, so first we blank every cell
with a space. There are 80 × 25 = 2000 cells:

```c
static void vga_clear(void) {
    for (unsigned i = 0; i < VGA_COLS * VGA_ROWS; i++)
        put_char(i, ' ', WHITE_ON_BLACK);
}
```

(Unlike the 480,000 pixels of an 800×600 frame buffer, 2000 cells clear in a
handful of instructions.)

## Printing a string

Because text mode is just memory, printing is a trivial loop over the
characters of the string, placing each into the next cell:

```c
const char *s = "Hello, World!";
for (unsigned i = 0; s[i] != '\0'; i++)
    put_char(i, s[i], WHITE_ON_BLACK);
```

No font, no scaling, no centering math — the hardware handles all of that for
us.

## Wiring it into `kmain`

```c
__attribute__((noreturn))
void kmain(unsigned long boot_info, unsigned long magic) {
    (void)boot_info;
    (void)magic;
    vga_clear();
    const char *s = "Hello, World!";
    for (unsigned i = 0; s[i] != '\0'; i++)
        put_char(i, s[i], i == 0 ? RED_ON_BLACK : WHITE_ON_BLACK);
    for (;;) { }     /* keep the kernel alive */
}
```

(Here the first letter is drawn in red and the rest in white — a tiny flourish
that shows how easy the color attribute is to vary per character.)

## Why VGA text and not the frame buffer?

The VGA text buffer is the simplest possible output: a fixed grid, no parsing
of boot-info tags, no per-pixel math, no font. It is the ideal first "Hello,
World!" for a kernel. Its only limitation is that it relies on the classic
BIOS boot path with the display left in text mode — which is exactly what GRUB
gives us here. (On the sibling *framebuffer* branches we instead parse the
multiboot2 boot info, ask GRUB for a graphical buffer, and draw a bitmap font
pixel by pixel — a much bigger step.)

## Check your progress

```bash
nix run .#run
```

A QEMU window opens and you should see **"Hello, World!"** — first letter red,
rest white — at the top-left of the screen. If the window is empty or has
leftover boot loader text, suspect your `vga_clear` loop or the
`index * 2` cell addressing.

Next, in [Step 6](06-next-steps.md), we review what we built and where to go next.
