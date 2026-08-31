{ stdenv, binutils }:

# Build a freestanding 32-bit x86 assembly kernel as an ELF executable.
#
# The whole kernel is a single assembly file (kernel.s), so the only tools we
# need are the GNU assembler (`as`) and linker (`ld`), both provided by
# binutils. No C or Rust compiler is involved at all.
stdenv.mkDerivation {
  pname = "rustios";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ binutils ];

  buildPhase = ''
    # 1. Assemble the whole kernel into one 32-bit object file.
    #    `--32` makes `as` target the i386 architecture; `as` needs no runtime
    #    and pulls in no libraries, so nothing else is required for a bare
    #    kernel.
    as --32 kernel.s -o kernel.o

    # 2. Link into a static ELF executable following our linker script, which
    #    places the entry point and the multiboot2 header at the standard
    #    kernel load address of 1 MiB.
    ld \
      -m elf_i386 \
      -T ${./linker.ld} \
      -z noexecstack \
      kernel.o \
      -o kernel
  '';

  installPhase = ''
    mkdir -p $out
    cp kernel $out/kernel
  '';
}