# home-manager backend — writes the rc files, and pointedly does NOT install shells.
#
# home-manager's own `programs.fish.enable` installs pkgs.fish. On NixOS that is right; on a
# foreign distro it puts a second fish on PATH ahead of the system one, so the login shell and the
# interactive shell become different builds. That was live on the elitebook. This backend therefore
# writes config only and leaves the binary to pacman.
{ config, lib, ... }:
{
  imports = [ ./nixsh.nix ];
  config.home.file = lib.mapAttrs' (path: text: lib.nameValuePair path { inherit text; }) config.nixsh.rcFiles;
}
