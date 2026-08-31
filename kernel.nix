{ stdenv, rust, binutils }:

# Build a freestanding x86_64 Rust kernel as an ELF executable.
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
    #    The x86_64-unknown-none target is "bare metal": it has no operating
    #    system underneath, just what our own code provides. Its standard
    #    library portion is the minimal `core` crate, which is exactly what
    #    a no_std kernel needs.
    rustc \
      --edition 2021 \
      --target x86_64-unknown-none \
      --emit=obj \
      -C opt-level=z \
      -C panic=abort \
      src/main.rs \
      -o main.o

    # 2. Assemble the 32-bit -> 64-bit bootstrap stub (boot.s).
    $CC -c boot.s -o boot.o

    # 3. Link everything into a static ELF executable following our linker
    #    script, which places the entry point and the multiboot2 header at
    #    the standard kernel load address of 1 MiB, and produces the final
    #    binary as a 64-bit (elf64-x86-64) executable.
    ld \
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