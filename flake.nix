{
  description = "nixsh — every shell on every machine, declared: shared environment, per-shell config, and the binary left to the system";

  # NO INPUTS.

  outputs = { self }: {
    homeModules.nixsh = ./modules/home.nix;
    homeModules.default = ./modules/home.nix;

    nixosModules.nixsh = ./modules/nixos.nix;
    nixosModules.default = ./modules/nixos.nix;

    systemManagerModules.nixsh = ./modules/arch.nix;
    systemManagerModules.default = ./modules/arch.nix;

    # Policy alone, for a consumer that wants the computed lists and will wire them itself.
    lib.policy = ./modules/nixsh.nix;
    lib.catalogue = import ./lib/shells.nix { };
  };
}
