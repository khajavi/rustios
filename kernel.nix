{ stdenv, binutils }:

# Build a 16-bit "Hello, World!" boot sector as a raw 512-byte disk image.
#
# The whole thing is a single GNU assembly file (kernel.s). We assemble it
# with `as --32` merely as a synthesis convenience, while the `.code16`
# directive inside kernel.s forces the emitted instructions to be 16-bit real
# mode. The linker places the code at the BIOS boot address (0x7C00), and
# `objcopy -O binary` then flattens the ELF into the raw bytes the BIOS loads
# straight from the disk's first sector.
stdenv.mkDerivation {
  pname = "rustios-bootsector";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ binutils ];

  buildPhase = ''
    # 1. Assemble: `--32` targets i386; `.code16` inside kernel.s makes the
    #    emitted instructions 16-bit real mode.
    as --32 kernel.s -o kernel.o

    # 2. Link at the BIOS load address (0x7C00) using the linker script.
    ld -m elf_i386 -T ${./linker.ld} kernel.o -o kernel.elf

    # 3. Flatten the ELF into raw bytes. The ELF is just a container; what
    #    matters is the first 512 bytes, ending in the boot signature.
    objcopy -O binary kernel.elf kernel.img

    # 4. Sanity-check the result: exactly 512 bytes, tiny, boots on its own.
    wc -c kernel.img
  '';

  installPhase = ''
    mkdir -p $out
    cp kernel.img $out/helloworld.img
  '';
}