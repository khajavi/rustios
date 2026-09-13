# Step 5: Building with Nix

The build system compiles, links, and converts the assembly into a raw
512-byte binary image — all expressed as a Nix derivation.

---

## The build chain

```
kernel.s
    │
    ▼  as --32 -o kernel.o
kernel.o
    │
    ▼  ld -T linker.ld -o kernel.elf
kernel.elf
    │
    ▼  objcopy -O binary kernel.elf helloworld.img
helloworld.img   (512 bytes, raw boot sector)
```

---

## kernel.nix (simplified)

```nix
{ stdenv, nasm, ... }:

stdenv.mkDerivation {
  name = "rustios-bootsector";
  src = ./.;

  nativeBuildInputs = [ nasm ];

  buildPhase = ''
    as --32 -o kernel.o kernel.s
    ld -T linker.ld -o kernel.elf kernel.elf
    objcopy -O binary kernel.elf helloworld.img
  '';

  installPhase = ''
    mkdir -p $out
    cp helloworld.img $out/
  '';
}
```

---

## linker.ld

```ld
OUTPUT_FORMAT(elf32-i386)
ENTRY(_start)
SECTIONS
{
  . = 0x7C00;

  .text : { *(.text) }
  .data : { *(.data) }
  .bss  : { *(.bss) }

  /DISCARD/ : { *(.eh_frame) *(.comment) *(.note*) }
}
```

The key line is `. = 0x7C00` — this tells the linker that the code will be
loaded at address `0x7C00`. All addresses in the resulting ELF are correct
for the BIOS boot environment.

---

## flake.nix

```nix
packages = forAllSystems (pkgs: {
  default = pkgs.callPackage ./kernel.nix { };

  run = pkgs.writeShellScriptBin "rustios-run" ''
    export PATH="${pkgs.qemu}/bin:$PATH"
    img="$(mktemp --suffix=.img)"
    cp ${self.packages.${pkgs.system}.default}/helloworld.img "$img"
    exec qemu-system-x86_64 \
      -drive format=raw,file="$img" \
      -no-reboot -boot d
  '';
});
```

`nix build .#default` produces the 512-byte image. `nix run .#run` boots
it in QEMU immediately.

---

## Why Nix?

The build is **purely declarative**. Anyone with Nix installed gets the
exact same binary, with no manual toolchain setup. The `flake.lock` pins
all inputs.

---

## Next

The final step shows how to verify that everything works.
