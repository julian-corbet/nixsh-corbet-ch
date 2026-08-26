# Arch backend — publishes pacman/AUR names and installs only an exceptional custom Nix package
# when upstream has no Arch package. An entry may carry `package` as a NixOS fallback while still
# naming an Arch package (termpdf); that entry stays entirely with the host reconciler here and is
# not installed a second time from Nix.
#   nixarch.packages.pacman = config.nixsh.archPackages ++ config.nixsh.tools.archPackages;
#   nixarch.packages.aur    = config.nixsh.tools.aurPackages;
# Config comes from the home-manager backend, which runs on the same box.
{ config, lib, pkgs, ... }:
let
  custom = lib.filter (tool: tool ? package && tool.arch == null) config.nixsh.tools.selected;
  evaluated = map
    (tool: {
      inherit tool;
      result = builtins.tryEval (builtins.seq (tool.package pkgs) true);
    })
    custom;
  installable = lib.filter (entry: entry.result.success) evaluated;
  broken = lib.filter (entry: !entry.result.success) evaluated;
in
{
  imports = [ ./nixsh.nix ./tools.nix ];

  environment.systemPackages = lib.unique (map (entry: entry.tool.package pkgs) installable);
  warnings = map (_: "nixsh: a custom tool package no longer resolves -- inspect lib/tools.nix and its package source") broken;
}
