# Arch backend — publishes the pacman/AUR names; the host reconciler installs them.
#   nixarch.packages.pacman = config.nixsh.archPackages ++ config.nixsh.tools.archPackages;
#   nixarch.packages.aur    = config.nixsh.tools.aurPackages;
# Config comes from the home-manager backend, which runs on the same box.
{ ... }:
{
  imports = [ ./nixsh.nix ./tools.nix ];
}
