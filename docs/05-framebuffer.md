# Step 5 — The graphical framebuffer

We have a working 64-bit kernel that prints to serial. Now the fun part:
drawing text on the **QEMU window** itself.

## Concept: what a framebuffer is

A **framebuffer** is a rectangular block of memory where each pixel is a few
bytes. To draw, you compute which byte(s) correspond to `(x, y)` and write a
color into them. There is no "window" to draw to from the kernel's point of
view — just a big array of colored cells.

But we don't know where that array is, or how big it is, or how the colors are
encoded. That information is exactly what the **boot loader** gives us via the
multiboot2 information structure.

## Remembering the plan from Step 1

In Step 1 we put a **framebuffer request tag** (type `5`) in our multiboot2
*header*, asking GRUB: *"please give me an 800×600, 32-bit-per-pixel graphical
framebuffer."* GRUB obeyed — it switched the display to 800×600 and reserved a
block of physical memory for it.

Now, in Step 5, we read GRUB's *answer*. GRUB writes a second structure into
memory called the **multiboot2 information** (boot info), and hands us its
address in `ebx` (which the bootstrap forwarded to `kmain` as its first
argument `boot_info`).

## The boot info is a list of "tags"

The boot info is a byte blob: first a `total_size`, then a sequence of
tagged records. Each tag starts with `type` (u32) and `size` (u32), followed
by tag-specific data, then padded to 8 bytes.

We only care about the **framebuffer tag, type `8`**. It tells us:

- physical address of the framebuffer,
- pitch (bytes per row — not always width × bpp!),
- width, height, bits-per-pixel,
- the RGB bit positions (how to encode a color).

## Parsing it in Rust

```rust
struct Framebuffer {
    addr: usize,
    pitch: u32,
    width: u32,
    height: u32,
    bpp: u8,
    red_pos: u8,   red_size: u8,
    green_pos: u8, green_size: u8,
    blue_pos: u8,  blue_size: u8,
}

unsafe fn find_framebuffer(info_ptr: usize) -> Option<Framebuffer> {
    let total_size = core::ptr::read_volatile(info_ptr as *const u32);
    let mut offset = 8;                      // skip total_size field
    while offset + 8 <= total_size as usize {
        let base = info_ptr + offset;
        let tag_type = core::ptr::read_volatile(base as *const u32);
        let tag_size = core::ptr::read_volatile((base + 4) as *const u32) as usize;
        if tag_type == 8 && tag_size >= 24 {
            let addr   = core::ptr::read_volatile((base + 8) as *const u64) as usize;
            let pitch  = core::ptr::read_volatile((base + 16) as *const u32);
            let width  = core::ptr::read_volatile((base + 20) as *const u32);
            let height = core::ptr::read_volatile((base + 24) as *const u32);
            let bpp    = core::ptr::read_volatile((base + 28) as *const u8);
            return Some(Framebuffer { addr, pitch, width, height, bpp, /* ... */ });
        }
        if tag_type == 0 { break; }          // end tag
        offset += (tag_size + 7) & !7;       // advance, keeping 8-byte alignment
    }
    None
}
```

We use `read_volatile` because these are real hardware-provided memory contents
that could change; the compiler must not cache or reorder them.

## Writing one pixel

The formula for a pixel's address:

```
pixel(x, y) = addr + y * pitch + x * (bpp / 8)
```

`pitch` is essential — a row might be padded so `pitch > width * (bpp/8)`.

```rust
fn fb_put_pixel(fb: &Framebuffer, x: u32, y: u32, white: bool) {
    if x >= fb.width || y >= fb.height { return; }   // clip off-screen pixels
    let addr = fb.addr
        + y as usize * fb.pitch as usize
        + x as usize * (fb.bpp / 8) as usize;
    match fb.bpp {
        32 => {
            // Pack 0xFF in each of the red, green, blue bit-positions.
            let color: u32 = if white {
                (0xFF << fb.red_pos) | (0xFF << fb.green_pos) | (0xFF << fb.blue_pos)
            } else { 0 };
            unsafe { core::ptr::write_volatile(addr as *mut u32, color) };
        }
        24 => {
            let color: u32 = if white { 0xFFFFFF } else { 0 };
            unsafe {
                core::ptr::write_volatile(addr as *mut u8, color as u8);
                core::ptr::write_volatile((addr + 1) as *mut u8, (color >> 8) as u8);
                core::ptr::write_volatile((addr + 2) as *mut u8, (color >> 16) as u8);
            }
        }
        _ => {}   // we only asked for 32 or 24 bpp
    }
}
```

Notice the `red_pos`/`green_pos`/`blue_pos` shifting: GRUB tells us *where in
the 32-bit cell* each color channel lives (e.g. typical is red at bit 0, green
at 8, blue at 16). White is "maximum intensity in all three channels."

## Clearing the screen

Loop over every pixel and write black:

```rust
fn fb_clear(fb: &Framebuffer) {
    for y in 0..fb.height {
        for x in 0..fb.width {
            fb_put_pixel(fb, x, y, false);
        }
    }
}
```

(For 800×600 = 480,000 pixels, an unoptimized loop is fine here.)

## Drawing text with a tiny font

Real text comes from fonts. We cheat with a hand-rolled **5×7 bitmap font**:
each glyph is an array of 7 bytes, one per row, where each byte's bottom 5 bits
are 1 where the pixel is white. For example the letter `H`:

```rust
b'H' => [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
```

Row 0 = `0x11` = `10001` → two tall white columns (the H's sides). Row 3 =
`0x1F` = `11111` → a full bar (the middle crossbar). Together that spells `H`.

```rust
fn fb_draw_char(fb: &Framebuffer, c: u8, x: u32, y: u32, scale: u32) -> u32 {
    let glyph = font_glyph(c);
    for (row, bits) in glyph.iter().enumerate() {
        for col in 0..5 {
            if bits & (1 << (4 - col)) != 0 {       // this pixel is "on"
                for sy in 0..scale {
                    for sx in 0..scale {            // expand to `scale` real px
                        fb_put_pixel(fb, x + (col as u32 * scale) + sx,
                                         y + (row as u32 * scale) + sy, true);
                    }
                }
            }
        }
    }
    6 * scale             // return how far to advance for the next character
}
```

The `scale` parameter upscales the 5×7 font into big, readable pixels. The
function returns `6 * scale` — the horizontal advance between characters.

## Wiring it into `kmain`

```rust
if magic == MULTIBOOT2_BOOTLOADER_MAGIC as usize {
    if let Some(fb) = unsafe { find_framebuffer(boot_info) } {
        fb_clear(&fb);
        let scale = core::cmp::max(1, fb.width / 200);   // pick a readable size
        let msg = b"Hello World!";
        let w = (msg.len() as u32) * 6 * scale;
        let x = (fb.width.saturating_sub(w)) / 2;       // center horizontally
        let y = (fb.height / 2) - 4 * scale;            // center vertically
        let mut cx = x;
        for &c in msg {
            cx += fb_draw_char(&fb, c, cx, y, scale);
        }
    }
}

loop {}     // keep the kernel alive
```

Two important checks are baked in:

1. **Check `magic`** — only draw if a real multiboot2 boot loader started us.
2. **`if let Some(fb)`** — only draw if GRUB actually gave us a framebuffer.

## The framebuffer address / page table tie-in

Here's where Step 3 pays off. On QEMU, GRUB placed the 800×600 framebuffer at
physical address **`0xFD000000`** — nearly 4 GiB. When our pixel code writes
there, that's a *virtual* access that the CPU translates through the page
table we built. If we had only mapped the low 1 GiB, that single write would
**page-fault** and the screen would stay black.

Mapping the **top 1 GiB** in `boot.s` (the `pd_high` region from Step 3) is the
reason the framebuffer drawing works at all. This is a great illustration of
why the bootstrap isn't just a formality: the framebuffer and the page tables
must agree.

## Check your progress

```bash
nix run .#run
```

A QEMU window opens and you should see **"Hello World!"** drawn centered on an
800×600 black screen. If the screen is black but serial printed
`Hello, World!\n`, suspect either the magic check or the page-table mapping of
the high framebuffer region.

Next, in [Step 6](06-pit.md), we make it type itself out one character at a
time using a hardware timer.
