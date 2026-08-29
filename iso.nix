{ lib, stdenv, kernel, grub2, xorriso }:

# Wrap the bare kernel in a GRUB multiboot ISO so QEMU can boot it.
stdenv.mkDerivation {
  pname = "rustios-iso";
  version = "0.1.0";

  nativeBuildInputs = [ grub2 xorriso ];

  src = ./.;

  buildPhase = ''
    runHook preBuild
    mkdir -p isofiles/boot/grub
    cp ${kernel}/kernel isofiles/boot/kernel.bin
    cat > isofiles/boot/grub/grub.cfg <<EOF
    set timeout=0
    set default=0
    set gfxmode=text
    terminal_output console
    menuentry "rustios" {
      multiboot2 /boot/kernel.bin
      boot
    }
    EOF
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    grub-mkrescue -o $out/rustios.iso isofiles
    runHook postInstall
  '';
}
