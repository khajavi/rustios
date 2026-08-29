{
  description = "Declarative Rust hello-world kernel booted with QEMU";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, rust-overlay }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems
        (system: f (import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        }));
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./kernel.nix {
          rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        };

        # A bootable ISO of the kernel, ready for QEMU.
        iso = pkgs.callPackage ./iso.nix {
          kernel = self.packages.${pkgs.system}.default;
        };

        # Build the kernel and boot it immediately in QEMU.
        run = pkgs.writeShellScriptBin "rustios-run" ''
          export PATH="${pkgs.qemu}/bin:$PATH"
          exec qemu-system-x86_64 \
            -cdrom ${self.packages.${pkgs.system}.iso}/rustios.iso \
            -no-reboot -boot d
        '';
      });
    };
}
