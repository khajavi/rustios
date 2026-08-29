#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

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
    end_tag_type: u16,
    end_tag_flags: u16,
    end_tag_size: u32,
}

#[used]
#[link_section = ".multiboot"]
static MULTIBOOT_HEADER: Multiboot2Header = Multiboot2Header {
    magic: MAGIC,
    architecture: ARCHITECTURE,
    header_length: HEADER_LENGTH,
    checksum: CHECKSUM,
    end_tag_type: 0,
    end_tag_flags: 0,
    end_tag_size: 8,
};

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
        outb(COM1 + 1, 0x00); // disable interrupts
        outb(COM1 + 3, 0x80); // enable DLAB
        outb(COM1 + 0, 0x03); // divisor low (38400 baud)
        outb(COM1 + 1, 0x00); // divisor high
        outb(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
        outb(COM1 + 2, 0xC7); // enable FIFO
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

#[no_mangle]
pub extern "C" fn _start() -> ! {
    serial_init();
    serial_write(b"Hello, World!\n");
    vga_clear();
    vga_write(b"Hello, World!");

    loop {}
}
