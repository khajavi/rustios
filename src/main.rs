#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

// Multiboot2 header (arch = 0 means a 32-bit i386 kernel, kept in 32-bit mode
// by the boot loader, so no long-mode bootstrap is needed).
const MAGIC: u32 = 0xe85250d6;
const ARCHITECTURE: u32 = 0;
const HEADER_LENGTH: u32 = 24;
const CHECKSUM: u32 = (0u32.wrapping_sub(MAGIC))
    .wrapping_sub(ARCHITECTURE)
    .wrapping_sub(HEADER_LENGTH);

#[repr(C)]
#[repr(align(8))]
struct Multiboot2Header {
    magic: u32,
    architecture: u32,
    header_length: u32,
    checksum: u32,
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
    end_type: 0,
    end_flags: 0,
    end_size: 8,
};

// The VGA text buffer: 80 columns x 25 rows of (byte, attribute) pairs.
const VGA_BUFFER: usize = 0xb8000;
const WHITE_ON_BLACK: u8 = 0x0f;

#[no_mangle]
pub extern "C" fn kmain(_boot_info: usize, _magic: usize) -> ! {
    let s = b"Hello, World!";
    for (i, &c) in s.iter().enumerate() {
        let cell = VGA_BUFFER + i * 2;
        unsafe {
            core::ptr::write_volatile(cell as *mut u8, c); // character
            core::ptr::write_volatile((cell + 1) as *mut u8, WHITE_ON_BLACK); // color
        }
    }
    loop {}
}
