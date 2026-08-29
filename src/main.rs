#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

const MAGIC: u32 = 0xe85250d6;
const ARCHITECTURE: u32 = 0;
const HEADER_LENGTH: u32 = 48;
const CHECKSUM: u32 = (0u32.wrapping_sub(MAGIC))
    .wrapping_sub(ARCHITECTURE)
    .wrapping_sub(HEADER_LENGTH);

const FRAMEBUFFER_WIDTH: u32 = 800;
const FRAMEBUFFER_HEIGHT: u32 = 600;
const FRAMEBUFFER_DEPTH: u32 = 32;

#[repr(C)]
#[repr(align(8))]
struct Multiboot2Header {
    magic: u32,
    architecture: u32,
    header_length: u32,
    checksum: u32,
    // framebuffer request tag: type = 5, flags = 0, size = 20
    fb_type: u16,
    fb_flags: u16,
    fb_size: u32,
    fb_width: u32,
    fb_height: u32,
    fb_depth: u32,
    pad: u32,
    // end tag: type = 0, flags = 0, size = 8
    end_type: u16,
    end_flags: u16,
    end_size: u32,
}

#[used]
#[link_section = ".multiboot"]
static MULTIBOOT_HEADER: Multiboot2Header = Multiboot2Header {
    magic: MAGIC,
    architecture: ARCHITECTURE,
    header_length: HEADER_LENGTH,
    checksum: CHECKSUM,
    fb_type: 5,
    fb_flags: 0,
    fb_size: 20,
    fb_width: FRAMEBUFFER_WIDTH,
    fb_height: FRAMEBUFFER_HEIGHT,
    fb_depth: FRAMEBUFFER_DEPTH,
    pad: 0,
    end_type: 0,
    end_flags: 0,
    end_size: 8,
};

const MULTIBOOT2_BOOTLOADER_MAGIC: u32 = 0x36d76289;

// The 32-bit -> 64-bit bootstrap lives in boot.s (assembled and linked in by
// kernel.nix). GRUB starts an architecture=0 multiboot2 kernel in 32-bit
// protected mode with paging off, so `_start` (in boot.s) sets up a GDT, PAE,
// a 1 GiB identity map and long mode, then calls `kmain` with the boot-info
// pointer (rdi) and magic value (rsi).

const VGA_BUFFER: *mut u8 = 0xb8000 as *mut u8;
const COM1: u16 = 0x3F8;

unsafe fn outb(port: u16, val: u8) {
    core::arch::asm!(
        "out dx, al",
        in("dx") port,
        in("al") val,
        options(nomem, nostack, preserves_flags)
    );
}

unsafe fn inb(port: u16) -> u8 {
    let val: u8;
    core::arch::asm!(
        "in al, dx",
        out("al") val,
        in("dx") port,
        options(nomem, nostack, preserves_flags)
    );
    val
}

fn serial_init() {
    unsafe {
        outb(COM1 + 1, 0x00);
        outb(COM1 + 3, 0x80);
        outb(COM1 + 0, 0x03);
        outb(COM1 + 1, 0x00);
        outb(COM1 + 3, 0x03);
        outb(COM1 + 2, 0xC7);
    }
}

fn serial_write_byte(byte: u8) {
    unsafe {
        while inb(COM1 + 5) & 0x20 == 0 {}
        outb(COM1, byte);
    }
}

fn serial_write(s: &[u8]) {
    for &b in s {
        serial_write_byte(b);
    }
}

fn vga_clear() {
    for i in 0..80 * 25 {
        unsafe {
            *VGA_BUFFER.add(i * 2) = b' ';
            *VGA_BUFFER.add(i * 2 + 1) = 0x0f;
        }
    }
}

fn vga_write(s: &[u8]) {
    for (i, &value) in s.iter().enumerate() {
        unsafe {
            *VGA_BUFFER.add(i * 2) = value;
            *VGA_BUFFER.add(i * 2 + 1) = 0x0f;
        }
    }
}

#[derive(Clone, Copy)]
struct Framebuffer {
    addr: usize,
    pitch: u32,
    width: u32,
    height: u32,
    bpp: u8,
    red_pos: u8,
    red_size: u8,
    green_pos: u8,
    green_size: u8,
    blue_pos: u8,
    blue_size: u8,
}

// Parse the multiboot2 boot info structure for the framebuffer tag (type 8).
unsafe fn find_framebuffer(info_ptr: usize) -> Option<Framebuffer> {
    let total_size = core::ptr::read_volatile(info_ptr as *const u32);
    let mut offset = 8;
    while offset + 8 <= total_size as usize {
        let base = info_ptr + offset;
        let tag_type = core::ptr::read_volatile(base as *const u32);
        let tag_size = core::ptr::read_volatile((base + 4) as *const u32) as usize;
        if tag_type == 8 && tag_size >= 24 {
            let addr = core::ptr::read_volatile((base + 8) as *const u64) as usize;
            let pitch = core::ptr::read_volatile((base + 16) as *const u32);
            let width = core::ptr::read_volatile((base + 20) as *const u32);
            let height = core::ptr::read_volatile((base + 24) as *const u32);
            let bpp = core::ptr::read_volatile((base + 28) as *const u8);
            // color_info (direct RGB) follows at offset 31 within the tag
            let mut red_pos = 0;
            let mut red_size = 0;
            let mut green_pos = 0;
            let mut green_size = 0;
            let mut blue_pos = 0;
            let mut blue_size = 0;
            if tag_size >= 37 {
                red_pos = core::ptr::read_volatile((base + 31) as *const u8);
                red_size = core::ptr::read_volatile((base + 32) as *const u8);
                green_pos = core::ptr::read_volatile((base + 33) as *const u8);
                green_size = core::ptr::read_volatile((base + 34) as *const u8);
                blue_pos = core::ptr::read_volatile((base + 35) as *const u8);
                blue_size = core::ptr::read_volatile((base + 36) as *const u8);
            }
            return Some(Framebuffer {
                addr,
                pitch,
                width,
                height,
                bpp,
                red_pos,
                red_size,
                green_pos,
                green_size,
                blue_pos,
                blue_size,
            });
        }
        if tag_type == 0 {
            break;
        }
        offset += (tag_size + 7) & !7;
    }
    None
}

fn fb_put_pixel(fb: &Framebuffer, x: u32, y: u32, white: bool) {
    if x >= fb.width || y >= fb.height {
        return;
    }
    let addr = fb.addr + y as usize * fb.pitch as usize + x as usize * (fb.bpp / 8) as usize;
    match fb.bpp {
        32 => {
            let color: u32 = if white {
                (0xFF << fb.red_pos) | (0xFF << fb.green_pos) | (0xFF << fb.blue_pos)
            } else {
                0
            };
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
        _ => {}
    }
}

fn fb_clear(fb: &Framebuffer) {
    for y in 0..fb.height {
        for x in 0..fb.width {
            fb_put_pixel(fb, x, y, false);
        }
    }
}

// 5x7 bitmap font, only the glyphs needed for "HELLO, WORLD!"
fn font_glyph(c: u8) -> [u8; 7] {
    let c = c.to_ascii_uppercase();
    match c {
        b' ' => [0, 0, 0, 0, 0, 0, 0],
        b'!' => [0x4, 0x4, 0x4, 0x4, 0x4, 0x0, 0x4],
        b',' => [0x0, 0x0, 0x0, 0x0, 0x0, 0x2, 0x4],
        b'H' => [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        b'E' => [0x1F, 0x10, 0x10, 0x1C, 0x10, 0x10, 0x1F],
        b'L' => [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
        b'O' => [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        b'W' => [0x11, 0x11, 0x11, 0x11, 0x15, 0x15, 0x0A],
        b'R' => [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        b'D' => [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
        _ => [0, 0, 0, 0, 0, 0, 0],
    }
}

fn fb_draw_text(fb: &Framebuffer, msg: &[u8], start_x: u32, start_y: u32, scale: u32) {
    let mut cx = start_x;
    for &c in msg {
        let glyph = font_glyph(c);
        for (row, bits) in glyph.iter().enumerate() {
            for col in 0..5 {
                if bits & (1 << (4 - col)) != 0 {
                    for sy in 0..scale {
                        for sx in 0..scale {
                            fb_put_pixel(
                                fb,
                                cx + (col as u32 * scale) + sx,
                                start_y + (row as u32 * scale) + sy,
                                true,
                            );
                        }
                    }
                }
            }
        }
        cx += 6 * scale;
    }
}

#[no_mangle]
pub extern "C" fn kmain(boot_info: usize, magic: usize) -> ! {
    serial_init();
    serial_write(b"Hello, World!\n");
    vga_clear();
    vga_write(b"Hello, World!");

    if magic == MULTIBOOT2_BOOTLOADER_MAGIC as usize {
        if let Some(fb) = unsafe { find_framebuffer(boot_info) } {
            fb_clear(&fb);
            let scale = core::cmp::max(1, fb.width / 200);
            let w = 13 * 6 * scale;
            let x = (fb.width.saturating_sub(w)) / 2;
            let y = (fb.height / 2) - 4 * scale;
            fb_draw_text(&fb, b"HELLO, WORLD!", x, y, scale);
        }
    }

    loop {}
}
