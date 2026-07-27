# home-manager backend — composes with whatever already writes the rc files, and installs nothing.
#
# TWO PROBLEMS THIS AVOIDS.
#
# 1. Clobbering. Writing ~/.config/fish/config.fish wholesale fights home-manager's own
#    `programs.fish`, which a host may already use for its own interactiveShellInit (a per-tty
#    session launcher, for instance). Two writers, one file. So fish gets a conf.d DROP-IN, which
#    is fish's native composition point and loads alongside anything else, and bash/zsh feed
#    `initExtra`, which home-manager concatenates rather than replaces.
#
# 2. A second shell binary. home-manager's `programs.fish.enable` installs pkgs.fish. On NixOS that
#    is right; on a foreign distro it lands ahead of /usr/bin/fish on PATH, so the login shell and
#    the interactive shell become different builds. This backend therefore never sets
#    `programs.*.enable` -- the host decides, and on Arch the binary stays pacman's.
{ config, lib, ... }:
let
  cfg = config.nixsh;
  body = shell: cfg.rcFiles.${(import ../lib/shells.nix { }).${shell}.rcPath} or "";
in
{
  imports = [ ./nixsh.nix ];

  config = lib.mkMerge [
    # fish: a numbered conf.d drop-in. 00- so it lands before anything a host adds there itself.
    (lib.mkIf cfg.fish.enable {
      xdg.configFile."fish/conf.d/00-nixsh.fish".text = body "fish";
    })

    # bash/zsh have no conf.d convention, so use home-manager's own concatenating hook. If the host
    # does not enable programs.bash/zsh, nothing sources this -- hence the warning rather than
    # silence, because an unsourced shell config looks identical to a wrong one.
    (lib.mkIf cfg.bash.enable {
      programs.bash.initExtra = body "bash";
      warnings = lib.optional (!config.programs.bash.enable)
        "nixsh: bash config generated but programs.bash.enable is false, so nothing sources it.";
    })

    (lib.mkIf cfg.zsh.enable {
      programs.zsh.initExtra = body "zsh";
      warnings = lib.optional (!config.programs.zsh.enable)
        "nixsh: zsh config generated but programs.zsh.enable is false, so nothing sources it.";
    })
  ];
}
