# Renders all three shells from one declaration and checks the SHARED layer really did come out in
# three different syntaxes -- which is the only thing in this module worth abstracting, and the
# thing most likely to be silently wrong.
#
#   nix-instantiate --eval --strict experiments/render-smoke-test.nix -A fishUsesSetGx   # => true
{ nixpkgs ? <nixpkgs> }:
let
  lib = (import nixpkgs { }).lib;
  eval = lib.evalModules {
    modules = [
      ../modules/nixsh.nix
      {
        nixsh = {
          fish.enable = true;
          bash.enable = true;
          zsh.enable = true;
          environment.variables.EDITOR = "hx";
          environment.path = [ "/opt/tools/bin" ];
          fish.universalVariables.fish_greeting = "";
          bash.aliases.ll = "ls -alh";
        };
      }
    ];
  };
  rc = eval.config.nixsh.rcFiles;
in
{
  shells = builtins.attrNames rc;
  # fish must use `set -gx`, the POSIX shells `export` -- from the SAME declaration.
  fishUsesSetGx = lib.hasInfix ''set -gx EDITOR "hx"'' rc.".config/fish/config.fish";
  bashUsesExport = lib.hasInfix ''export EDITOR="hx"'' rc.".bashrc";
  zshUsesExport = lib.hasInfix ''export EDITOR="hx"'' rc.".zshrc";
  # fish PATH is its own builtin, not a PATH assignment.
  fishPathIsBuiltin = lib.hasInfix "fish_add_path /opt/tools/bin" rc.".config/fish/config.fish";
  # universal variables are fish-only and idempotent.
  fishUniversal = lib.hasInfix "set -q fish_greeting; or set -U" rc.".config/fish/config.fish";
  # per-shell aliases must NOT leak into other shells.
  aliasStaysInBash = (lib.hasInfix "alias ll=" rc.".bashrc") && !(lib.hasInfix "alias ll=" rc.".zshrc");
  archPackages = eval.config.nixsh.archPackages;
}
