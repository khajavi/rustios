// kernel.s — rustios, the whole kernel in one pure-assembly file.
//
// GRUB loads this program as a multiboot2 kernel and our code writes the
// string "Hello, World!" directly into the VGA text screen's memory. There
// is no C and no Rust here: the raw CPU instructions do everything.

// ---------------------------------------------------------------------------
// Multiboot2 header
// ---------------------------------------------------------------------------
//
// GRUB only boots files that carry a multiboot2 header saying "I am a
// multiboot2 kernel". The header must live inside the first 8192 bytes of the
// file and be 8-byte aligned, and its layout is fixed:
//
//   magic       : u32  = 0xE85250D6   the multiboot2 signature
//   architecture: u32  = 0           0 means "I am a 32-bit i386 kernel",
//                                    so GRUB leaves us in 32-bit protected
//                                    mode — exactly what we want.
//   header_length : u32               total size of the header (24 bytes)
//   checksum      : u32               the three u32s above must add up to 0
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
//
// `section .multiboot` places this at the very start of the file, which the
// linker script (linker.ld) relocates to address 1 MiB. Because 1 MiB is an
// 8-byte-aligned address, the header is automatically aligned correctly.
    .set MULTIBOOT2_MAGIC,       0xe85250d6
    .set MULTIBOOT2_ARCH_I386,   0
    .set MULTIBOOT2_HEADER_LEN,  24
    .set MULTIBOOT2_CHECKSUM,    (0 - MULTIBOOT2_MAGIC - MULTIBOOT2_ARCH_I386 - MULTIBOOT2_HEADER_LEN)

    .section .multiboot, "a"
    .balign 8
multiboot_header:
    .long MULTIBOOT2_MAGIC
    .long MULTIBOOT2_ARCH_I386
    .long MULTIBOOT2_HEADER_LEN
    .long MULTIBOOT2_CHECKSUM
    .word 0                      # end tag: type  = 0
    .word 0                      # end tag: flags = 0
    .long 8                      # end tag: size  = 8
multiboot_header_end:

// ---------------------------------------------------------------------------
// The call stack
// ---------------------------------------------------------------------------
//
// The CPU has no concept of a stack pointer until we tell it where to point
// ESP. GRUB leaves ESP undefined at hand-off, so we carve out a private 4 KiB
// region in .bss (which GRUB zero-fills) and point ESP at its top, where the
// stack grows downwards from.
    .section .bss, "", "nobits"
    .balign 16
stack_bottom:
    .skip 4096
stack_top:

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
    .section .text
    .code32
    .global _start
_start:
    movl $stack_top, %esp        # give the CPU a usable stack

    # ---------------------------------------------------------------------
    # VGA text mode
    # ---------------------------------------------------------------------
    #
    # In text mode the screen is a grid of 80 columns x 25 rows of
    # characters. The graphics card continuously reads a 4 KiB block of
    # memory at physical address 0xB8000 and paints whatever it finds, so
    # writing bytes there shows up on the screen instantly. Each cell is two
    # bytes:
    #
    #   cell = [character] [color attribute]
    #
    # and the attribute byte is split into background (high nibble) and
    # foreground (low nibble). 0x0F means bright white text on a black
    # background.
    .set VGA_BUFFER,      0xb8000
    .set VGA_COLS,        80
    .set VGA_ROWS,        25
    .set WHITE_ON_BLACK,  0x0f

    # --- Blank the whole screen first -----------------------------------
    # Write a space + attribute into every one of the 80*25 = 2000 cells so
    # no leftover boot-loader text shows through behind our message.
    movl $VGA_BUFFER, %edi       # EDI = address of cell 0
    movl $VGA_COLS * VGA_ROWS, %ecx   # ECX = number of cells to clear
clear_loop:
    movb $' ', (%edi)            # character = space
    movb $WHITE_ON_BLACK, 1(%edi)      # color = white on black
    addl $2, %edi                # move to the next cell (2 bytes each)
    loop clear_loop

    # --- Print "Hello, World!" ------------------------------------------
    # We write each character of the string into consecutive cells at the
    # top-left corner of the screen. The string lives in .rodata; we walk a
    # pointer through it until we hit the trailing NUL terminator.
    movl $VGA_BUFFER, %edi       # EDI = where to place the next character
    movl $hello_world, %esi      # ESI = pointer into the string
print_loop:
    lodsb                        # AL = *ESI++ ; load one character
    testb %al, %al               # is it the NUL terminator?
    jz   done                    # yes -> stop printing
    movb %al, (%edi)             # character
    movb $WHITE_ON_BLACK, 1(%edi)      # color
    addl $2, %edi                # advance to the next cell
    jmp  print_loop

done:
    # A kernel never returns; it just parks the CPU here forever.
halt:
    cli                          # disable interrupts (nothing to handle)
    hlt                          # halt the CPU until the next interrupt
    jmp  halt                    # ...and if one ever comes, halt again

// ---------------------------------------------------------------------------
// Read-only data
// ---------------------------------------------------------------------------
    .section .rodata, "a"
hello_world:
    .asciz "Hello, World!"
