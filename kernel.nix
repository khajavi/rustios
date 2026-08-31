{ stdenv, binutils }:

# Build a freestanding 32-bit x86 C kernel as an ELF executable.
#
# We compile with the same C compiler that Nix is built with (stdenv.cc)
# rather than pulling in a whole toolchain, because the only files involved
# are our kernel and the plain GNU assembler.
stdenv.mkDerivation {
  pname = "rustios";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ binutils ];

  buildPhase = ''
    # 1. Compile the C source into one 32-bit freestanding object file.
    #    `-m32` produces i386 code; `-ffreestanding` tells the compiler there
    #    is no host C runtime to fall back on; `-nostdlib` and `-fno-builtin`
    #    stop it from assuming library functions like memcpy exist.
    $CC \
      -m32 \
      -ffreestanding \
      -nostdlib \
      -fno-builtin \
      -fno-stack-protector \
      -O2 \
      -Wall \
      -Wextra \
      -c src/main.c \
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