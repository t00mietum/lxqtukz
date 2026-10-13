{
  description = "LXQtukz: LXQt on Wayfire, tracking upstream with our own patches";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      version = lib.removeSuffix "\n" (builtins.readFile ./version);
      commit = self.rev or self.dirtyRev or "unknown";
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = f: lib.genAttrs systems (system:
        f (import nixpkgs { inherit system; overlays = [ self.overlays.default ]; }));
    in {
      ## Pins and patch queues come from upstream/ and patches/, the same files
      ## the Debian build reads, so one change goes into both.
      overlays.default = import ./nix/overlay.nix { src = self; inherit version commit; };

      packages = forEachSystem (pkgs: {
        default = pkgs.lxqtukz;
        lxqtukz = pkgs.lxqtukz;
      });

      nixosModules.default = import ./nix/module.nix { inherit self; };
    };
}
