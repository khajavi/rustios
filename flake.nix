{
  description = "Declarative C hello-world kernel booted with QEMU";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems
        (system: f (import nixpkgs { inherit system; }));
      systems = [ "x86_64-linux" ];
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./kernel.nix { };

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