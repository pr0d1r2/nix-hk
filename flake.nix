{
  description = "hk for nixos 26.05 -- current hk, built from the fleet's pinned nixpkgs";

  nixConfig = {
    extra-substituters = [ "https://pr0d1r2.cachix.org" ];
    extra-trusted-public-keys = [
      "pr0d1r2.cachix.org-1:NfWjbhgAj41byXhCKiaE+av3Vnphm1fTezHXEGsiQIM="
    ];
  };

  # ONE input (SPEC V18). nixpkgs-lock is the fleet's sole nixpkgs authority and
  # nixpkgs follows it, so every repo that consumes hk resolves to the same
  # nixpkgs rev -- which is what makes the cachix binaries hit instead of
  # rebuilding. A second nixpkgs edge here would silently fork that rev.
  inputs = {
    nixpkgs-lock.url = "github:pr0d1r2/nixpkgs-lock";
    nixpkgs.follows = "nixpkgs-lock/nixpkgs";
  };

  outputs =
    { nixpkgs, ... }:
    let
      # Declared: 4. CI builds and caches 3 of them; x86_64-darwin is tier-2 --
      # it must evaluate everywhere but is built locally, not by CI (SPEC V23,
      # V24, V25). GitHub's only Intel macOS runner is macos-13, which is on its
      # way out; the platform is kept, the CI spend is not.
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          hk = pkgs.callPackage ./pkgs/hk/package.nix { };
        in
        {
          inherit hk;
          default = hk;
        }
      );

      overlays.default = final: _prev: {
        hk = final.callPackage ./pkgs/hk/package.nix { };
      };

      checks = forAllSystems (pkgs: {
        hk = pkgs.callPackage ./pkgs/hk/package.nix { };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (pkgs.callPackage ./pkgs/hk/package.nix { })
            pkgs.nixfmt
            pkgs.statix
          ];
        };
      });
    };
}
