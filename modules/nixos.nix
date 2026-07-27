# NixOS backend — here the system IS nix, so installing the shells is correct rather than a
# duplication. environment.systemPackages puts them in /run/current-system/sw/bin, which is the
# system path on this platform; /etc/shells picks them up the usual way.
{ config, lib, pkgs, ... }:
let
  catalogue = import ../lib/shells.nix { };
  enabled = lib.filter (s: config.nixsh.${s}.enable) (lib.attrNames catalogue);
in
{
  imports = [ ./nixsh.nix ];
  config = {
    environment.systemPackages = map (s: pkgs.${catalogue.${s}.nixpkgs}) enabled;
    environment.shells = map (s: pkgs.${catalogue.${s}.nixpkgs}) enabled;
  };
}
