# Step 2 — Nix makes the build declarative

## Why not just `rustc`?

To turn `src/main.rs` + `boot.s` into something GRUB can boot, you hand-run a
fragile chain:

```bash
rustc --edition 2021 --target x86_64-unknown-none --emit=obj \
  -C opt-level=z -C relocation-model=static -C prefer-dynamic=no \
  -C panic=abort src/main.rs -o main.o
gcc -c boot.s -o boot.o
ld -T linker.ld -z noexecstack boot.o main.o -o kernel
```

That works — but it's:

- **Not reproducible**: `rustc`, `gcc`, `ld`, and the *Rust target* must be
  the exact right versions, installed by hand.
- **Easy to get wrong**: three separate tools, many flags, and a linker
  script. Miss one flag and the kernel silently fails to boot.
- **Not shareable**: a teammate has to set up the same toolchain.

[Nix](https://nixos.org/download) fixes all of this. A **Nix flake** describes
_exactly_ how to build the project, down to the compiler version. Everyone who
runs `nix build` gets the same bytes.

## Concept: a Nix derivation

A **derivation** is a recipe Nix runs to produce a build output. Our build
happens through two files:

- `kernel.nix` — compiles and links the bare kernel (`kernel` ELF binary).
- `iso.nix` — wraps that kernel in a bootable GRUB ISO.

`flake.nix` is the top-level file that ties them together and exposes
convenient commands.

## The linker script (`linker.ld`) — deciding where code lives

Before reading the build recipe, you need to see the **linker script**, because
it's what makes a "kernel" out of ordinary object files. It tells the linker
*which memory addresses* to place each section at:

```ld
OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)                 /* execution starts at the assembly symbol _start */

SECTIONS
{
  . = 1M;                     /* place the kernel at physical address 1 MiB */

  .text :                     /* executable code */
  {
    *(.multiboot)             /* multiboot2 header FIRST  */
    *(.bootstrap)             /* then the 32->64 bootstrap */
    *(.text*)                 /* then the Rust code        */
  }

  .rodata : { *(.rodata*) }   /* read-only data (constants) */
  .data   : { *(.data*)   }   /* read-write data             */
  .bss    : { *(COMMON) *(.bss*) } /* zero-initialized data   */
}
```

Two crucial lines:

1. **`. = 1M;`** — GRUB loads kernels at physical address **1 MiB** (the
   conventional low memory is reserved for BIOS, the hardware, and the boot
   loader). So we ask the linker to place our code starting at `0x100000`.
2. **`*(.multiboot)` first** — the multiboot2 header must be the *very first
   bytes* of the binary so the boot loader can find it instantly.

(By the way: the address `1M` is why, when we later read serial log symbols,
entry points looked like `0x10004e`, `0x1000ce`, etc.)

## `kernel.nix` — the "compile it" recipe

```nix
{ lib, stdenv, rust, binutils }:

stdenv.mkDerivation {
  pname = "rustios";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ rust binutils ];   # tools available during build

  buildPhase = ''
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
    $CC -c boot.s -o boot.o          # assemble the bootstrap
    ld                             # link everything together
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
```

The interesting flags:

| Flag | Meaning |
|------|---------|
| `--target x86_64-unknown-none` | "freestanding 64-bit x86; there is no OS." |
| `--emit=obj` | produce an object file, not a final executable (we link ourselves). |
| `-C opt-level=z` | optimize for small size (a kernel should be tiny). |
| `-C relocation-model=static` | no position-independent code; the kernel must be linked to its fixed address. |
| `-C panic=abort` | on panic, just abort (don't unwind the stack — we have no unwinder). |

## `iso.nix` — making it bootable

A raw kernel ELF is not bootable by itself. GRUB needs it inside a *disk image*
(an ISO) with a menu entry. This is exactly what an ISO for a real OS has:
a boot directory and a GRUB config file.

```nix
{ lib, stdenv, kernel, grub2, xorriso }:

stdenv.mkDerivation {
  pname = "rustios-iso";
  version = "0.1.0";
  nativeBuildInputs = [ grub2 xorriso ];
  src = ./.;

  buildPhase = ''
    mkdir -p isofiles/boot/grub
    cp ${kernel}/kernel isofiles/boot/kernel.bin
    cat > isofiles/boot/grub/grub.cfg <<EOF
    set timeout=0                 # don't pause at the menu
    set default=0
    set gfxmode=text              # ask GRUB to use a text console for ITS menu
    terminal_output console
    menuentry "rustios" {
      multiboot2 /boot/kernel.bin # GRUB: boot this file as a multiboot2 kernel
      boot
    }
    EOF
  '';

  installPhase = ''
    mkdir -p $out
    grub-mkrescue -o $out/rustios.iso isofiles   # pack it into a bootable CD image
  '';
}
```

Key line: **`multiboot2 /boot/kernel.bin`**. This tells GRUB "the file at
`/boot/kernel.bin` is a multiboot2 kernel — load it and start it." GRUB then
*reads the multiboot2 header* our Rust code defined in Step 1 to decide where
and how to load it.

## `flake.nix` — one command to rule them all

The flake is the public face. If you never touch `kernel.nix` or `iso.nix`
again, you use the commands that the flake exposes:

```nix
outputs = { self, nixpkgs, rust-overlay }: {
  packages = forAllSystems (pkgs: {
    default = pkgs.callPackage ./kernel.nix { ... };  # raw kernel
    iso     = pkgs.callPackage ./iso.nix   { ... };  # bootable ISO
    run     = pkgs.writeShellScriptBin "rustios-run" ''
      exec qemu-system-x86_64 -cdrom ${...iso...}/rustios.iso -no-reboot -boot d
    '';
  });
};
```

This gives us the three commands you'll use all tutorial long:

```bash
nix build .#default   # just the kernel
nix build .#iso       # the bootable ISO
nix run .#run         # build everything and boot it in QEMU
```

The `rust-overlay` input pins a known Rust toolchain (declared in
`rust-toolchain.toml`), so the compiler version never secretly changes.

## Check your progress

```bash
nix build .#iso --no-link --print-out-paths
```

You should see a Nix store path ending in ..., and inside it `rustios.iso`.
If that works, you have a **reproducible kernel build**. Next we make the CPU
actually switch into 64-bit mode in [Step 3](03-bootstrap.md).
