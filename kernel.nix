{ lib, stdenv, rust, binutils }:

# Build a freestanding 32-bit x86 Rust kernel as an ELF executable.
stdenv.mkDerivation {
  pname = "rustios";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ rust binutils ];

  buildPhase = ''
    runHook preBuild
    rustc \
      --edition 2021 \
      --target i686-unknown-linux-gnu \
      --emit=obj \
      -C opt-level=z \
      -C relocation-model=static \
      -C prefer-dynamic=no \
      -C panic=abort \
      src/main.rs \
      -o main.o
    $CC -m32 -c boot.s -o boot.o
    ld \
      -m elf_i386 \
      -T ${./linker.ld} \
      -z noexecstack \
      boot.o main.o \
      -o kernel
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp kernel $out/kernel
    runHook postInstall
  '';
}
