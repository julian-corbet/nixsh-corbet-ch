{
  description = "nixsh — every shell on every machine, declared, plus the terminal-native tool catalogue: shared environment, per-shell config, shell-integration hooks, and every binary left to the system";

  # nixpkgs is used ONLY by this flake's own `checks` below (proving the tools module resolves
  # selections correctly, and separately -- see experiments/validate-nixpkgs-names.nix -- that
  # every catalogued nixpkgs name still force-evaluates on a real package set), exactly the
  # boundary nixmedia's own flake.nix draws. The exported modules (homeModules/nixosModules/
  # systemManagerModules) never see this input: they take `pkgs`/`config`/`lib` from whichever
  # evaluation composes them. Composing this flake can never add a second nixpkgs to a consumer's
  # closure -- still true after this input's addition, since nothing exported reaches into it.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      homeModules.nixsh = ./modules/home.nix;
      homeModules.default = ./modules/home.nix;

      nixosModules.nixsh = ./modules/nixos.nix;
      nixosModules.default = ./modules/nixos.nix;

      systemManagerModules.nixsh = ./modules/arch.nix;
      systemManagerModules.default = ./modules/arch.nix;

      # Policy alone, for a consumer that wants the computed lists and will wire them itself.
      lib.policy = ./modules/nixsh.nix;
      lib.catalogue = import ./lib/shells.nix { };

      # The tool catalogue's own policy module and raw data, same split as the shell pair above.
      lib.toolsPolicy = ./modules/tools.nix;
      lib.toolsCatalogue = import ./lib/tools.nix { };

      # `nix flake check` does not evaluate `homeModules`/`nixosModules`/`systemManagerModules` on
      # its own -- see nixmedia's own checks/catalogue-eval.nix header for the exact mechanism
      # this repeats. A green `nix flake check` on this repo without this file would cover nothing
      # but flake syntax.
      checks = forAllSystems (system: {
        tools-eval = import ./checks/tools-eval.nix {
          pkgs = nixpkgs.legacyPackages.${system};
        };
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
