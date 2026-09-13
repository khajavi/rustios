// kernel.s — a 16-bit "Hello, World!" boot sector in GNU assembly.
//
// Unlike the other branches (which are multiboot2 kernels loaded by GRUB),
// this is a *boot sector*: the BIOS loads the first 512 bytes of a disk
// image straight into memory at physical address 0x7C00 and jumps to the
// first byte. There is no boot loader, no GRUB, no C, no Rust — just raw
// real-mode machine code, the same model as the classic "hello world" boot
// sector projects (e.g. Sreeju7733/helloworld-os, written there in NASM).
//
// All I/O goes through BIOS interrupt calls instead of hardware ports:
//   int $0x10, AH = 0x0E  ->  print one character (the "teletype" service)
//
// The very last two bytes of the sector must be 0x55 0xAA so the BIOS
// believes this is a bootable disk.

    .code16                        # the CPU starts in 16-bit real mode
    .section .text
    .global _start

_start:
    # Real mode addresses are segment:offset. Zero the data segment registers
    # so an absolute address like 0x7C40 is the physical byte address — by
    # far the simplest way to reason about "where does X live?".
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es

    # Give ourselves a tiny stack just below the boot sector. The BIOS data
    # occupies the very bottom of memory, but the region 0x0500..0x7C00 is
    # free for us to use.
    movw %ax, %ss
    movw $0x7C00, %sp

    # Print the message: point SI at the string and call the helper.
    movw $message, %si
    call  print

    # A boot sector has nothing to return to; park the CPU.
spin:
    hlt
    jmp  spin

# print: writes the NUL-terminated string at %si using BIOS teletype output.
print:
    lodsb                          # AL = *SI++; advance SI by one byte
    testb %al, %al                 # NUL terminator reached?
    jz    done                     # yes -> return to caller
    movb  $0x0e, %ah               # BIOS service: write char in AL to TTY
    int   $0x10
    jmp   print
done:
    ret

# The message must live inside this first 512-byte sector: the BIOS only ever
# loads sector 1 from the disk, so anything at byte offset 512 or later is
# never guaranteed to be in memory. `.ascii` (no automatic NUL) lets us build
# one long message ending in a single explicit terminator.
message:
    .ascii "Hello, World!"
    .byte  '\r', '\n'
    .ascii "Booted with GNU assembly"
    .byte  '\r', '\n', 0

    # Pad the rest of the sector with zeros, then stamp the boot signature on
    # the very last two bytes (offsets 510 and 511).
    .org 510
    .word 0xAA55