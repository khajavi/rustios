{ lib, stdenv, rust, binutils }:

# Build a freestanding x86_64 Rust kernel as an ELF executable.
stdenv.mkDerivation {
  pname = "rustios";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ rust binutils ];

  buildPhase = ''
    runHook preBuild
    rustc \
      --edition 2021 \
      --target x86_64-unknown-none \
      --emit=obj \
      -C opt-level=z \
      -C relocation-model=static \
      -C prefer-dynamic=no \
      -C panic=abort \
      src/main.rs \
      -o main.o
    $CC -c boot.s -o boot.o
    ld \
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
