{ stdenv, rust, binutils }:

# Build a freestanding 32-bit x86 Rust kernel as an ELF executable.
#
# We avoid Cargo entirely and call rustc directly: the project has no
# dependencies, so the whole Cargo machinery would only add complexity.
stdenv.mkDerivation {
  pname = "rustios";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ rust binutils ];

  buildPhase = ''
    # 1. Turn the Rust source into one CPU object file.
    rustc \
      --edition 2021 \
      --target i686-unknown-linux-gnu \
      --emit=obj \
      -C opt-level=z \
      -C panic=abort \
      src/main.rs \
      -o main.o

    # 2. Assemble the tiny 32-bit bootstrap stub (boot.s).
    $CC -m32 -c boot.s -o boot.o

    # 3. Link everything into a static ELF executable following our linker
    #    script, which places the entry point and the multiboot2 header at
    #    the standard kernel load address of 1 MiB.
    ld \
      -m elf_i386 \
      -T ${./linker.ld} \
      -z noexecstack \
      boot.o main.o \
      -o kernel
  '';

  installPhase = ''
    mkdir -p $out
    cp kernel $out/kernel
  '';
}