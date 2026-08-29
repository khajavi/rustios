#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

const MAGIC: u32 = 0xe85250d6;
const ARCHITECTURE: u32 = 0;
const HEADER_LENGTH: u32 = 44;
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

#[derive(Clone, Copy)]
struct Framebuffer {
    addr: usize,
    pitch: u32,
    width: u32,
    height: u32,
    bpp: u8,
    red_pos: u8,
    green_pos: u8,
    blue_pos: u8,
}

// Parse the multiboot2 boot info structure for the framebuffer tag (type 8).
unsafe fn find_framebuffer(info_ptr: usize) -> Option<Framebuffer> {
    let total_size = core::ptr::read_volatile(info_ptr as *const u32);
    let mut offset = 8;
    while offset + 8 <= total_size as usize {
        let base = info_ptr + offset;
        let tag_type = core::ptr::read_volatile(base as *const u32);
        let tag_size = core::ptr::read_volatile((base + 4) as *const u32) as usize;
        if tag_type == 8 && tag_size >= 32 {
            let addr = core::ptr::read_volatile((base + 8) as *const u64) as usize;
            let pitch = core::ptr::read_volatile((base + 16) as *const u32);
            let width = core::ptr::read_volatile((base + 20) as *const u32);
            let height = core::ptr::read_volatile((base + 24) as *const u32);
            let bpp = core::ptr::read_volatile((base + 28) as *const u8);
            if tag_size >= 38 {
                return Some(Framebuffer {
                    addr,
                    pitch,
                    width,
                    height,
                    bpp,
                    red_pos: core::ptr::read_volatile((base + 31) as *const u8),
                    green_pos: core::ptr::read_volatile((base + 33) as *const u8),
                    blue_pos: core::ptr::read_volatile((base + 35) as *const u8),
                });
            }
            return Some(Framebuffer {
                addr,
                pitch,
                width,
                height,
                bpp,
                red_pos: 16,
                green_pos: 8,
                blue_pos: 0,
            });
        }
        if tag_type == 0 {
            break;
        }
        offset += (tag_size + 7) & !7;
    }
    None
}

fn green(fb: &Framebuffer) -> u32 {
    (0xFFu32 << fb.green_pos)
}

fn fb_put_pixel(fb: &Framebuffer, x: u32, y: u32, color: u32) {
    if x >= fb.width || y >= fb.height {
        return;
    }
    let addr = fb.addr + y as usize * fb.pitch as usize + x as usize * (fb.bpp / 8) as usize;
    match fb.bpp {
        32 => unsafe { core::ptr::write_volatile(addr as *mut u32, color) },
        24 => unsafe {
            core::ptr::write_volatile(addr as *mut u8, color as u8);
            core::ptr::write_volatile((addr + 1) as *mut u8, (color >> 8) as u8);
            core::ptr::write_volatile((addr + 2) as *mut u8, (color >> 16) as u8);
        },
        _ => {}
    }
}

fn fb_clear(fb: &Framebuffer, color: u32) {
    for y in 0..fb.height {
        for x in 0..fb.width {
            fb_put_pixel(fb, x, y, color);
        }
    }
}

// 5x7 bitmap font, only the glyphs needed for "Hello, World!"
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

fn fb_draw_char(fb: &Framebuffer, c: u8, x: u32, y: u32, scale: u32, color: u32) -> u32 {
    let glyph = font_glyph(c);
    for (row, bits) in glyph.iter().enumerate() {
        for col in 0..5 {
            if bits & (1 << (4 - col)) != 0 {
                for sy in 0..scale {
                    for sx in 0..scale {
                        fb_put_pixel(
                            fb,
                            x + (col as u32 * scale) + sx,
                            y + (row as u32 * scale) + sy,
                            color,
                        );
                    }
                }
            }
        }
    }
    6 * scale
}

#[no_mangle]
pub extern "C" fn kmain(boot_info: usize, magic: usize) -> ! {
    if magic == MULTIBOOT2_BOOTLOADER_MAGIC as usize {
        if let Some(fb) = unsafe { find_framebuffer(boot_info) } {
            let green = green(&fb);
            fb_clear(&fb, 0);

            let scale = FRAMEBUFFER_WIDTH / 100; // large font: 800 / 100 = 8
            let msg = b"Hello, World!";
            let w = (msg.len() as u32) * 6 * scale;
            let h = 7 * scale;
            let x = (fb.width.saturating_sub(w)) / 2;
            let y = (fb.height.saturating_sub(h)) / 2;
            let mut cx = x;
            for &c in msg {
                cx += fb_draw_char(&fb, c, cx, y, scale, green);
            }
        }
    }
    loop {}
}