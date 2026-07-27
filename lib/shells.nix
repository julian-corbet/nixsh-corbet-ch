#
# The shell catalogue. Three shells, named per platform.
#
# NIX OWNS CONFIG, THE SYSTEM OWNS THE BINARY. On a foreign distro the shell must be the system's
# copy: it is what /etc/shells lists, what login uses, and what everything else on the box links
# against. A nixpkgs copy on PATH shadows it and you end up with two versions of your shell -- the
# login one and the interactive one -- which is exactly what was found on the elitebook
# (see knowledge/coding/pacman-vs-nix.md). So `arch` here is what pacman installs, and the
# home-manager backend deliberately does NOT let home-manager install its own.
{ ... }:
{
  fish = {
    arch = "fish";
    nixpkgs = "fish";
    # fish is not POSIX. Its export syntax, its arrays and its functions all differ, which is why
    # only the ENVIRONMENT layer is shared across shells and aliases/functions are per-shell.
    exportFmt = name: value: ''set -gx ${name} "${value}"'';
    pathFmt = p: ''fish_add_path ${p}'';
    rcPath = ".config/fish/config.fish";
  };

  bash = {
    arch = "bash";
    nixpkgs = "bash";
    exportFmt = name: value: ''export ${name}="${value}"'';
    pathFmt = p: ''export PATH="${p}:$PATH"'';
    rcPath = ".bashrc";
  };

  zsh = {
    arch = "zsh";
    nixpkgs = "zsh";
    exportFmt = name: value: ''export ${name}="${value}"'';
    pathFmt = p: ''export PATH="${p}:$PATH"'';
    rcPath = ".zshrc";
  };
}
