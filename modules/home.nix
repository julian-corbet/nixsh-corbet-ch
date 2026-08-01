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

    # bash/zsh have no conf.d convention, so there are two routes and the host's own choice picks
    # which one applies. This used to be a catch-22: `initExtra` is only sourced when
    # programs.<shell>.enable is on, but turning that on installs the shell from nixpkgs -- the
    # exact second-binary problem note 2 above exists to avoid. So the config rendered into nothing
    # and a warning fired, which is a diagnosis, not a fix.
    #
    #   programs.<shell>.enable = true  -> COMPOSE via initExtra, as before. The host has accepted
    #                                      home-manager's shell (and its binary); don't fight it.
    #   programs.<shell>.enable = false -> OWN the rc file via home.file. Nothing else is writing
    #                                      it in that case, so there is no clobbering risk, and the
    #                                      config applies with no package pulled in.
    #
    # Net effect on a foreign distro: declared shell config actually applies, and the shell binary
    # still comes from the system. Both, rather than a choice between them.
    (lib.mkIf cfg.bash.enable (lib.mkMerge [
      (lib.mkIf config.programs.bash.enable { programs.bash.initExtra = body "bash"; })
      (lib.mkIf (!config.programs.bash.enable) {
        home.file.".bashrc".text = ''
          # Managed by nixsh (home-manager backend). programs.bash.enable is false on this host, so
          # nixsh owns this file outright rather than appending to home-manager's own.
          ${body "bash"}
        '';
      })
    ]))

    (lib.mkIf cfg.zsh.enable (lib.mkMerge [
      (lib.mkIf config.programs.zsh.enable { programs.zsh.initExtra = body "zsh"; })
      (lib.mkIf (!config.programs.zsh.enable) {
        home.file.".zshrc".text = ''
          # Managed by nixsh (home-manager backend). programs.zsh.enable is false on this host, so
          # nixsh owns this file outright rather than appending to home-manager's own.
          ${body "zsh"}
        '';
      })
    ]))
  ];
}
