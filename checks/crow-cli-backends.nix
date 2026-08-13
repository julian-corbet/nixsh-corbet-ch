{ nixpkgs, system, pkgs, lib ? pkgs.lib }:

let
  arch = (lib.evalModules {
    modules = [
      {
        options = {
          environment.systemPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
          };
          warnings = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      }
      ../modules/arch.nix
      { nixsh.tools.misc = [ "crow" ]; }
    ];
    specialArgs = { inherit pkgs; };
  }).config;

  nixos = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      ../modules/nixos.nix
      {
        nixsh.tools.misc = [ "crow" ];
        system.stateVersion = "26.05";
      }
    ];
  };

  isCrow = package: (package.pname or "") == "crow-cli";
  results = {
    "Arch installs the custom package through system-manager, not a nonexistent pacman/AUR name" =
      lib.length (lib.filter isCrow arch.environment.systemPackages) == 1
      && arch.nixsh.tools.archPackages == [ ]
      && arch.nixsh.tools.aurPackages == [ ];
    "NixOS installs the same custom Crow package" =
      lib.length (lib.filter isCrow nixos.config.environment.systemPackages) == 1;
  };
  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixsh: crow-cli backend check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (failure: "  - ${failure}") failed}
  ''
