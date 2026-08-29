# Step 6 — Animate with the PIT timer

We can draw "Hello World!" on the screen. Now let's make it **animate**: each
character appears one at a time, 500 milliseconds apart, like it's being
typed.

To do that the kernel needs a way to **wait**. We can't call `sleep()` — there's
no OS. We must ask the *hardware* for time. That's the job of the **PIT**
(Programmable Interval Timer, the 8254 chip).

## Concept: the 8254 timer

The PIT is a chip with a counter that counts down at a fixed frequency. Its
input clock is **1,193,182 Hz** (about 1.19 MHz). Think of it as a cheap
stopwatch:

- You program a "reload value" into channel 0.
- The counter counts *down* from that value toward 0.
- When it reaches 0, it reloads and starts counting again.

Crucially, **we can read the current value at any moment**. So to wait 500 ms,
we: read the counter, keep reading until enough *elapsed ticks* have gone by,
and our loop exits.

## Concept: measuring elapsed time with a 16-bit counter

The counter is only **16 bits** (max value 65,535). Since the chip ticks
1.19 million times a second, the counter wraps around ~18 times per second
(65536 ticks ≈ 54.9 ms). So a 500 ms wait must correctly handle **many
wraparounds**.

We pick a "last" reading. Each time we read again, we compute how much the
counter advanced since `last`, being careful when it wraps:

```rust
let elapsed = if now <= last {
    last - now            // normal: counter went down
} else {
    last + 65536 - now    // it wrapped: went from a low value up to a high one
};
```

Add up these deltas until the total reaches our target tick count.

## Programming the PIT the way it is at boot

At the moment our kernel runs, we can't assume the PIT is in a known state. So
we program it ourselves into a known configuration: channel 0, 16-bit, **mode
2** (rate generator). Writing `0x34` to the command port, then a reload value
of 0 (= 65536) low byte then high byte to channel 0:

```rust
const PIT_CMD: u16 = 0x43;   // the command register
const PIT_CH0: u16 = 0x40;   // channel 0's counter/register
const PIT_FREQ: u64 = 1_193_182;

fn pit_init() {
    unsafe {
        outb(PIT_CMD, 0x34);   // channel 0, 16-bit, mode 2, binary
        outb(PIT_CH0, 0x00);   // reload low byte  = 0  (meaning 65536)
        outb(PIT_CH0, 0x00);   // reload high byte = 0
    }
}

fn pit_read() -> u16 {
    unsafe {
        outb(PIT_CMD, 0x00);   // "latch" — freeze the counter so we read it atomically
        let lo = inb(PIT_CH0) as u16;
        let hi = inb(PIT_CH0) as u16;   // must read low then high
        (hi << 8) | lo
    }
}
```

The **latch command** (writing 0 to the command port) matters: it makes the
chip freeze the current count so our two reads (low byte, then high byte) come
from the *same* moment. Without it, the counter could tick between the two
reads and we'd assemble a wrong value.

## The delay function

Now the wait. We convert milliseconds to ticks, then busy-wait:

```rust
fn delay_ms(ms: u32) {
    let mut remaining = ms as u64 * PIT_FREQ / 1000;   // ticks to wait
    let mut last = pit_read() as u64;
    while remaining > 0 {
        let now = pit_read() as u64;
        let elapsed = if now <= last { last - now } else { last + 65536 - now };
        last = now;
        remaining -= elapsed.min(remaining);   // never overshoot below 0
    }
}
```

This is a **busy-wait** (also called *polling*): the CPU spins in a loop instead
of going to sleep. That's fine for a teaching kernel — it's simple and
deterministic. (Real OSes get the PIT to raise an *interrupt* and let the CPU do
other work; that's beyond this tutorial.) With `PIT_FREQ / 1000`, calling
`delay_ms(500)` waits exactly 500 ms.

## Animating: draw one character, wait, repeat

We already have `fb_draw_char` from Step 5, which *advances* the cursor by the
width of the glyph. That's exactly the primitive we need. We rewrite the draw
loop in `kmain` to draw **one** character, then wait half a second, then draw
the next:

```rust
if let Some(fb) = unsafe { find_framebuffer(boot_info) } {
    pit_init();                                // make sure the timer is ready
    fb_clear(&fb);
    let scale = core::cmp::max(1, fb.width / 200);
    let msg = b"Hello World!";
    let w = (msg.len() as u32) * 6 * scale;
    let x = (fb.width.saturating_sub(w)) / 2;  // center it
    let y = (fb.height / 2) - 4 * scale;

    let mut cx = x;
    for &c in msg {
        cx += fb_draw_char(&fb, c, cx, y, scale);  // draw this char
        delay_ms(500);                              // pause half a second
    }
}
```

Because the string starts at a fixed `x` and rows at fixed `y`, each
`delay_ms(500)` shows the partial text, then the next character joins it. The
result: `H`, pause, `He`, pause, `Hel`, pause ... until `Hello World!` is
complete.

## Concept recap: three pieces working together

1. **`fb_draw_char`** returns the advance, so we can lay characters side by
   side from left to right.
2. **`pit_read`/`delay_ms`** give us a real 500 ms pause between characters.
3. **`kmain`** drives the loop: draw → wait → draw → wait.

## Try it yourself

Change the delay to feel the difference:

```rust
delay_ms(100);   // fast typing
```

or reverse it so it *deletes* characters. Or draw a second line. Every change
is an excuse to rebuild and boot:

```bash
nix run .#run
```

## Congratulations 🎉

That's it — you've built a real operating-system kernel:

- a `no_std` freestanding Rust program (`#![no_std]`, `#![no_main]`),
- a **multiboot2** header so GRUB boots it,
- a **32→64 bootstrap** that builds page tables and flips the CPU into long
  mode,
- **serial** output for debugging,
- a **graphical framebuffer** renderer that draws a 5×7 font,
- a **PIT-timer** busy-wait that animates the text.

And you did it all with **Nix**, so the whole project builds reproducibly with
a single command. Welcome to the wonderful, weird world of kernel development.
