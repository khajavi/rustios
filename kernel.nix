{ lib, stdenv, rust }:

# Build a freestanding x86_64 Rust kernel as an ELF executable.
stdenv.mkDerivation {
  pname = "rustios";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ rust ];

  buildPhase = ''
    runHook preBuild
    rustc \
      --edition 2021 \
      --target x86_64-unknown-none \
      -C link-arg=-T${./linker.ld} \
      -C link-arg=-no-pie \
      -C opt-level=z \
      -C relocation-model=static \
      -C prefer-dynamic=no \
      src/main.rs \
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
