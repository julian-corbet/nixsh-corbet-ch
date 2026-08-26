{
  description = "nixsh — every shell on every machine, declared, plus the terminal-native tool catalogue: shared environment, per-shell config, shell-integration hooks, and every binary left to the system";

  # nixpkgs is used by this flake's own `checks` and exported `packages` below. The exported
  # modules (homeModules/nixosModules/systemManagerModules) never see this input: they take
  # `pkgs`/`config`/`lib` from whichever evaluation composes them, including for the pinned Crow
  # package. Composing this flake therefore cannot add a second nixpkgs to a consumer's closure.
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

      # Export the two source-backed exceptions in the catalogue. Crow is absent from both normal
      # package sources; termpdf exists in the AUR but not nixpkgs, so this derivation is the NixOS
      # half only. The modules still call these files with the consumer's own `pkgs`; these outputs
      # make each package directly buildable and give checks a first-class target.
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          crowCli = pkgs.callPackage ./packages/crow-cli.nix { };
          termpdf = pkgs.callPackage ./packages/termpdf.nix { };
        in
        {
          crow-cli = crowCli;
          inherit termpdf;
          default = crowCli;
        });

      # `nix flake check` does not evaluate `homeModules`/`nixosModules`/`systemManagerModules` on
      # its own -- see nixmedia's own checks/catalogue-eval.nix header for the exact mechanism
      # this repeats. A green `nix flake check` on this repo without this file would cover nothing
      # but flake syntax.
      checks = forAllSystems (system: {
        tools-eval = import ./checks/tools-eval.nix {
          pkgs = nixpkgs.legacyPackages.${system};
        };
        underlay-eval = import ./checks/underlay-eval.nix {
          pkgs = nixpkgs.legacyPackages.${system};
        };
        # The home backend's systemd-user PATH projection. Its rendered value carries a LITERAL
        # ''${PATH} for environment.d to expand later, and Nix expanding it instead is a silent,
        # session-wide wrong PATH rather than an error -- see that file's own header.
        systemd-user-path-eval = import ./checks/systemd-user-path-eval.nix {
          pkgs = nixpkgs.legacyPackages.${system};
        };
        # The one BUILD check in here. `nixpkgsDesktop` claims something about a file on disk, and
        # every interesting way for that to be false survives an eval -- see that file's header.
        # Takes `nixpkgs` itself, not just a package set: it evaluates a real NixOS system, which
        # is the only way to see what this backend actually installs.
        desktop-entry = import ./checks/desktop-entry.nix {
          inherit nixpkgs;
          pkgs = nixpkgs.legacyPackages.${system};
        };
        crow-cli = import ./checks/crow-cli.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          crowCli = self.packages.${system}.crow-cli;
        };
        crow-cli-backends = import ./checks/crow-cli-backends.nix {
          inherit nixpkgs system;
          pkgs = nixpkgs.legacyPackages.${system};
        };
        termpdf = self.packages.${system}.termpdf;
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
