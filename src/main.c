/* rustios — the smallest possible kernel for learning, written in C.
 *
 * GRUB loads this program as a multiboot2 kernel and our code writes the
 * string "Hello, World!" directly into the VGA text screen's memory.
 */

/* ---------------------------------------------------------------------------
 * Multiboot2 header
 * ---------------------------------------------------------------------------
 *
 * GRUB only boots files that carry a multiboot2 header saying "I am a
 * multiboot2 kernel". The header must live inside the first 8192 bytes of the
 * file and be 8-byte aligned, and its layout is fixed:
 *
 *   magic       : u32  = 0xE85250D6   the multiboot2 signature
 *   architecture: u32  = 0           0 means "I am a 32-bit i386 kernel",
 *                                    so GRUB leaves us in 32-bit protected
 *                                    mode - exactly what we want.
 *   header_length : u32               total size of the header (24 bytes)
 *   checksum      : u32               the three u32s above must add up to 0
 *
 * followed by one or more "tags". We only need the single mandatory end tag:
 *
 *   u16 type = 0
 *   u16 flags = 0
 *   u32 size = 8
 *
 * The whole header is therefore exactly 24 bytes = six u32 words:
 *
 *   [magic] [architecture] [header_length] [checksum] [type|flags] [size]
 *
 *   |--------- 16-byte header --------|  |------ 8-byte end tag ------|
 */
#define MULTIBOOT2_MAGIC 0xe85250d6u
#define MULTIBOOT2_ARCH_I386 0u
#define MULTIBOOT2_HEADER_LENGTH 24u
#define MULTIBOOT2_CHECKSUM \
    ((0u - MULTIBOOT2_MAGIC) - MULTIBOOT2_ARCH_I386 - MULTIBOOT2_HEADER_LENGTH)

/* `__attribute__((section(".multiboot")))` places the header in a section
 * named `.multiboot`, and our linker script (linker.ld) puts that section at
 * the very start of the binary, at the address 1 MiB. Because 1 MiB is an
 * 8-byte-aligned address, the header is automatically 8-byte aligned and
 * satisfies the multiboot2 requirement. `used` stops the compiler from
 * deleting it as "dead code" (nothing in our program ever reads it). */
__attribute__((section(".multiboot"), used))
static const unsigned int multiboot_header[6] = {
    MULTIBOOT2_MAGIC,
    MULTIBOOT2_ARCH_I386,
    MULTIBOOT2_HEADER_LENGTH,
    MULTIBOOT2_CHECKSUM,
    0, /* end tag: type = 0, flags = 0 */
    8, /* end tag: size  = 8          */
};

/* ---------------------------------------------------------------------------
 * VGA text mode
 * ---------------------------------------------------------------------------
 *
 * In text mode the screen is a grid of 80 columns x 25 rows of characters.
 * The graphics card continuously reads a 4 KiB block of memory at physical
 * address 0xB8000 and paints whatever it finds, so writing bytes there shows
 * up on the screen instantly. Each cell occupies two bytes:
 *
 *   cell = [character] [color attribute]
 *
 * and the attribute byte is split into background (high nibble) and
 * foreground (low nibble). 0x0F therefore means bright white text on a
 * black background.
 */
#define VGA_BUFFER ((volatile unsigned char *)0xb8000)
#define VGA_COLS 80
#define VGA_ROWS 25
#define WHITE_ON_BLACK 0x0f
#define RED_ON_BLACK   0x0c

/* Draw one character at screen position `index` (0 = very top-left cell).
 * The buffer is declared volatile so the compiler cannot "optimize away" our
 * writes to memory that it does not know anyone reads. */
static void put_char(unsigned index, char c, unsigned char attr) {
    VGA_BUFFER[index * 2] = (unsigned char)c;       /* the character    */
    VGA_BUFFER[index * 2 + 1] = attr;               /* its color        */
}

/* Fill every cell of the screen with a space so that no leftover boot-loader
 * text can show through behind our message. */
static void vga_clear(void) {
    for (unsigned i = 0; i < VGA_COLS * VGA_ROWS; i++)
        put_char(i, ' ', WHITE_ON_BLACK);
}

/* ---------------------------------------------------------------------------
 * Entry point
 * ---------------------------------------------------------------------------
 *
 * GRUB passes control to `_start` (see boot.s), which sets up a stack and
 * then calls this function with two arguments:
 *   arg0 = ebx = physical address of the multiboot2 information structure
 *   arg1 = eax = the multiboot2 magic value 0x36D76289, proof we were booted
 *                by a conforming boot loader
 *
 * A kernel never returns from its entry point, so it just loops forever at
 * the end (parking the CPU) instead of returning to main().
 */
__attribute__((noreturn))
void kmain(unsigned long boot_info, unsigned long magic) {
    (void)boot_info;            /* unused for now, but required by the spec */
    (void)magic;
    vga_clear();
    const char *s = "Hello, World!";
    for (unsigned i = 0; s[i] != '\0'; i++)
        /* the first letter is red, the rest are white */
        put_char(i, s[i], i == 0 ? RED_ON_BLACK : WHITE_ON_BLACK);
    for (;;) { }                /* park the CPU: this is the "end"          */
}
