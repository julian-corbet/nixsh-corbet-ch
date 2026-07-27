# Arch backend — publishes the pacman names; the host reconciler installs them.
#   nixarch.packages.pacman = config.nixsh.archPackages;
# Config comes from the home-manager backend, which runs on the same box.
{ ... }:
{
  imports = [ ./nixsh.nix ];
}
