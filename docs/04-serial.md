# Step 4 — Talk over the serial port

Now that we're in 64-bit mode and Rust is running, we want to **see** what the
kernel is doing. But we have no monitor output yet (that's Step 5). The classic
kernel-debugger's answer is the **serial port**: a slow, simple, universally
emulated way to send bytes out of the machine that QEMU can redirect to a host
file or console.

Even after we get the graphical framebuffer (Step 5), serial output remains
invaluable — a kernel crash that whites out the screen can still print to
serial.

## Concept: memory-mapped ports vs. I/O ports

Some hardware is controlled by writing to memory addresses (memory-mapped I/O).
But the classic PC **serial port** (and the PIT timer in Step 6) uses *I/O
ports*, a separate address space accessed with the special CPU instructions
`in` (read) and `out` (write).

Rust has no built-in `in`/`out`, so we write them with **inline assembly**:

```rust
unsafe fn outb(port: u16, val: u8) {
    core::arch::asm!(
        "out dx, al",                 // write the byte in al to the port in dx
        in("dx") port,
        in("al") val,
        options(nomem, nostack, preserves_flags)
    );
}

unsafe fn inb(port: u16) -> u8 {
    let val: u8;
    core::arch::asm!(
        "in al, dx",                  // read a byte from port dx into al
        out("al") val,
        in("dx") port,
        options(nomem, nostack, preserves_flags)
    );
    val
}
```

The `options(...)` bits tell the compiler "this assembly doesn't touch memory,
doesn't touch the stack, and doesn't change flags" — which lets it optimize
around these calls safely.

## Concept: the 16550 UART

The PC's first serial port (COM1) is at I/O port base **`0x3F8`**. It is
implemented by a chip called the **16550 UART**. Registers at `base + n`
configure it, and writing to `base + 0` (the "transmit" register) sends a byte
out. The magic line for "send a byte" is: if it's worth doing, it's worth
*busy-waiting* for the hardware to be ready first.

```rust
const COM1: u16 = 0x3F8;

fn serial_init() {
    unsafe {
        outb(COM1 + 1, 0x00);   // disable interrupts
        outb(COM1 + 3, 0x80);   // enable "divisor latch" so we can set baud rate
        outb(COM1 + 0, 0x03);   // baud divisor low  = 3  -> 38400 baud @ 1.8432MHz
        outb(COM1 + 1, 0x00);   // baud divisor high = 0
        outb(COM1 + 3, 0x03);   // 8 bits, no parity, 1 stop bit
        outb(COM1 + 2, 0xC7);   // enable FIFO
    }
}

fn serial_write_byte(byte: u8) {
    unsafe {
        while inb(COM1 + 5) & 0x20 == 0 {}  // busy-wait until transmit empty
        outb(COM1, byte);                    // send the byte
    }
}
```

The kind of thing you don't need to know by heart — you look it up — is what
each register bit means (divisor latch, FIFO enable, etc.). What *matters* to
understand is the pattern:

> To do anything useful with hardware: **configure it once, then check a
> "status" register before each operation** (this is called *polling*/busy-wait).

## A convenience wrapper

We almost always want to print whole strings, not single bytes:

```rust
fn serial_write(s: &[u8]) {
    for &b in s {
        serial_write_byte(b);
    }
}
```

Then in `kmain` (our Rust entry point from Step 3):

```rust
serial_init();
serial_write(b"Hello, World!\n");
```

## Real example: booting and reading the output

Build and boot headless, redirecting serial to a file:

```bash
qemu-system-x86_64 -cdrom $(nix build .#iso --no-link --print-out-paths)/rustios.iso \
  -no-reboot -boot d -serial file:/tmp/serial.log -display none
cat /tmp/serial.log
```

You should see:

```
Hello, World!
```

If you don't, the bootstrap (Step 3) is the first thing to inspect — serial is
the *first* code a healthy kernel reaches, so silence usually means we never got
into 64-bit mode at all.

## Try it yourself

Change the string and rebuild:

```rust
serial_write(b"kernel alive! ticks?\n");
```

Rebuild with `nix build .#iso` and boot again. The new text is proof that your
whole bootstrap → Rust handoff works end to end. Next, [Step 5](05-framebuffer.md)
turns on the graphics.
