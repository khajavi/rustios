{ stdenv, kernel, grub2, xorriso }:

# Wrap the bare kernel in a bootable GRUB ISO so QEMU can start it.
stdenv.mkDerivation {
  pname = "rustios-iso";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ grub2 xorriso ];

  buildPhase = ''
    # A bootable ISO for GRUB is a special directory layout that gets turned
    # into the disc image. `/boot/grub/grub.cfg` tells GRUB which kernel to
    # load; everything else is derived from that:
    #
    #   set timeout=0, set default=0      -> boot without showing a menu
    #   set gfxmode=text                  -> stay in text mode, no graphics
    #   terminal_output console           -> use the text console
    #   menuentry "rustios"              -> a single boot entry that
    #     multiboot2 /boot/kernel.bin     ->   loads our kernel via
    #     boot                             ->   the multiboot2 protocol
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
  '';

  installPhase = ''
    mkdir -p $out
    grub-mkrescue -o $out/rustios.iso isofiles
  '';
}