//! rustios — a 64-bit kernel that writes "Hello, World!" to the VGA text screen.
//!
//! This is the 64-bit (x86_64) analogue of the i686 VGA-text kernel: instead of
//! painting pixels on a graphical framebuffer, it writes characters straight
//! into the text mode screen's memory at 0xB8000, exactly like the classic
//! simpler kernels do.

#![no_std]   // The standard library needs an operating system; a kernel has
             // none, so we must compile without it.
#![no_main]  // Kernels do not start in a `main` function. GRUB jumps straight
             // into our assembly entry point `_start` (see boot.s), which
             // switches the CPU from 32-bit to 64-bit long mode and then calls
             // the `kmain` function at the bottom of this file.

use core::panic::PanicInfo;

// Every no_std program must provide a panic handler: the function the compiler
// jumps to when something goes wrong. A kernel has no console to report the
// error, so the only sensible thing to do is park the CPU forever.
#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

// ---------------------------------------------------------------------------
// Multiboot2 header
// ---------------------------------------------------------------------------
//
// GRUB only boots files that carry a multiboot2 header saying "I am a
// multiboot2 kernel". The header must live inside the first 8192 bytes of the
// file and be 8-byte aligned, and its layout is fixed:
//
//   magic       : u32 = 0xE85250D6   the multiboot2 signature
//   architecture: u32 = 0            Note that we still declare ourselves an
//                                    i386 (architecture = 0) kernel. The
//                                    multiboot2 spec has no "64-bit" value, so
//                                    a 64-bit kernel starts as if it were
//                                    ️32-bit; `boot.s` switches to long mode.
//   header_length : u32              total size of the header (24 bytes)
//   checksum      : u32              the three u32s above must add up to 0
//
// followed by one or more "tags". We only need the single mandatory end tag:
//
//   u16 type = 0
//   u16 flags = 0
//   u32 size = 8
//
// The whole header is therefore exactly 24 bytes = six u32 words:
//
//   [magic] [architecture] [header_length] [checksum] [type|flags] [size]
//
//   |--------- 16-byte header --------|  |------ 8-byte end tag ------|
const MAGIC: u32 = 0xe85250d6;
const ARCHITECTURE: u32 = 0;
const HEADER_LENGTH: u32 = 24;
const CHECKSUM: u32 = (0u32.wrapping_sub(MAGIC))
    .wrapping_sub(ARCHITECTURE)
    .wrapping_sub(HEADER_LENGTH);

// `#[used]` stops the compiler from deleting this static as "dead code"
// (nothing in our program ever reads it). `#[link_section = ".multiboot"]`
// places the header in a section named `.multiboot`, and our linker script
// (linker.ld) puts that section at the very start of the binary, at the
// address 1 MiB. Because 1 MiB is an 8-byte-aligned address, the header is
// automatically 8-byte aligned and satisfies the multiboot2 requirement.
#[used]
#[link_section = ".multiboot"]
static MULTIBOOT: [u32; 6] = [
    MAGIC,
    ARCHITECTURE,
    HEADER_LENGTH,
    CHECKSUM,
    0, // end tag: type = 0, flags = 0
    8, // end tag: size = 8
];

// ---------------------------------------------------------------------------
// VGA text mode
// ---------------------------------------------------------------------------
//
// In text mode the screen is a grid of 80 columns x 25 rows of characters.
// The graphics card continuously reads a 4 KiB block of memory at physical
// address 0xB8000 and paints whatever it finds, so writing bytes there shows
// up on the screen instantly. Each cell occupies two bytes:
//
//   cell = [character] [color attribute]
//
// and the attribute byte is split into background (high nibble) and
// foreground (low nibble). 0x0F therefore means bright white text on a
// black background.
//
// Because our bootstrap identity-maps the first 1 GiB of physical memory (see
// boot.s), the physical address 0xB8000 is also a valid virtual address, so
// we can address the buffer directly by writing to absolute address 0xB8000.
const VGA_BUFFER: usize = 0xb8000;
const VGA_COLS: usize = 80;
const VGA_ROWS: usize = 25;
const WHITE_ON_BLACK: u8 = 0x0f;

// Draw one character at screen position `index` (0 = very top-left cell).
// `write_volatile` forces a real write to physical memory and stops the
// compiler from "optimizing" it away.
unsafe fn put_char(index: usize, c: u8) {
    core::ptr::write_volatile((VGA_BUFFER + index * 2) as *mut u8, c);
    core::ptr::write_volatile((VGA_BUFFER + index * 2 + 1) as *mut u8, WHITE_ON_BLACK);
}

// Fill every cell of the screen with a space so that no leftover boot-loader
// text can show through behind our message.
fn vga_clear() {
    for i in 0..VGA_COLS * VGA_ROWS {
        unsafe {
            put_char(i, b' ');
        }
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
//
// After boot.s has switched to long mode it calls this function as if it were
// an ordinary C function, so the arguments arrive in the System V AMD64
// registers:
//   arg0 = rdi = physical address of the multiboot2 information structure
//   arg1 = rsi = the multiboot2 magic value 0x36D76289, proof we were booted
//                by a conforming boot loader
//
// A kernel never returns from its entry point, so the return type is `!`.
#[no_mangle]
pub extern "C" fn kmain(_boot_info: usize, _magic: usize) -> ! {
    vga_clear();
    let s = b"Hello, World!";
    for (i, &c) in s.iter().enumerate() {
        unsafe {
            put_char(i, c);
        }
    }
    loop {} // parking the CPU here is the "end of the program"
}