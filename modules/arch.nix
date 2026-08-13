# Arch backend — publishes pacman/AUR names and installs only the exceptional custom Nix package
# whose upstream has no distro package. The host reconciler installs the ordinary names.
#   nixarch.packages.pacman = config.nixsh.archPackages ++ config.nixsh.tools.archPackages;
#   nixarch.packages.aur    = config.nixsh.tools.aurPackages;
# Config comes from the home-manager backend, which runs on the same box.
{ config, lib, pkgs, ... }:
let
  custom = lib.filter (tool: tool ? package) config.nixsh.tools.selected;
  evaluated = map (tool: {
    inherit tool;
    result = builtins.tryEval (builtins.seq (tool.package pkgs) true);
  }) custom;
  installable = lib.filter (entry: entry.result.success) evaluated;
  broken = lib.filter (entry: !entry.result.success) evaluated;
in
{
  imports = [ ./nixsh.nix ./tools.nix ];

  environment.systemPackages = lib.unique (map (entry: entry.tool.package pkgs) installable);
  warnings = map (_: "nixsh: a custom tool package no longer resolves -- inspect lib/tools.nix and its package source") broken;
}
