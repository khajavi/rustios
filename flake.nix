{
  description = "Declarative 16-bit 'Hello, World!' boot sector in GNU assembly, run with QEMU";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems
        (system: f (import nixpkgs { inherit system; }));
    in
    {
      packages = forAllSystems (pkgs: {
        # The raw 512-byte boot sector, ready for QEMU.
        default = pkgs.callPackage ./kernel.nix { };

        # Build the boot sector and boot it immediately in QEMU.
        run = pkgs.writeShellScriptBin "rustios-run" ''
          export PATH="${pkgs.qemu}/bin:$PATH"
          img="$(mktemp --suffix=.img)"
          cp ${self.packages.${pkgs.system}.default}/helloworld.img "$img"
          exec qemu-system-x86_64 \
            -drive format=raw,file="$img" \
            -no-reboot -boot d
        '';
      });
    };
}