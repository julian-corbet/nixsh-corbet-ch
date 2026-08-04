# Package names drift between distros, and existence alone does not prove a name still WORKS.
# This checks every non-null nixpkgs attribute in lib/tools.nix actually resolves.
#
#   nix-instantiate --eval --strict experiments/validate-nixpkgs-names.nix -A missing   # => [ ]
#
# `resolves` FORCES the attribute, not just checks it exists — `hasAttrByPath` alone would miss a
# real rename. nixmedia's own experiments/validate-nixpkgs-names.nix (and, before it, nixfont's
# lib/fonts.nix) hit exactly this: nixpkgs converted a package to `throw "... renamed to ..."`,
# and the OLD name stayed present as an attribute (the throw IS the value) — so an existence-only
# check said "resolves" right up until a NixOS backend actually built `environment.systemPackages`
# and hit the throw for real. A `mkOption`/attrset key can exist and still not be a package; only
# forcing the value tells you. This file exists in nixsh for the same reason it exists in
# nixmedia — the mistake it catches is generic to any name→package table, not specific to media.
{ nixpkgs ? <nixpkgs> }:
let
  pkgs = import nixpkgs { config.allowUnfree = true; };
  lib = pkgs.lib;
  cat = import ../lib/tools.nix { };
  all = lib.flatten (map lib.attrValues (lib.attrValues cat));
  named = lib.filter (t: t.nixpkgs != null) all;
  resolves = t:
    let path = lib.splitString "." t.nixpkgs; in
    lib.hasAttrByPath path pkgs
    && (builtins.tryEval (builtins.seq (lib.getAttrFromPath path pkgs) true)).success;
in
{
  checked = builtins.length named;
  missing = map (t: t.nixpkgs) (lib.filter (t: !(resolves t)) named);
}
