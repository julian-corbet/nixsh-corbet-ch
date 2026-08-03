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

  # THE TRAP: a consumer moves a host onto `nixsh.fish.enable = true`, but leaves earlier
  # `programs.fish.{shellInit,interactiveShellInit,shellAliases,functions}` content in place from
  # before the move -- easy to do, since this backend deliberately COMPOSES with whatever a host
  # already has rather than forcing a rewrite (this file's own header, "Clobbering"). That leftover
  # content renders NOTHING: home-manager's own fish module gates its ENTIRE config block --
  # config.fish itself included -- behind `programs.fish.enable`, and this backend deliberately
  # never sets that option (this file's own header, "A second shell binary": setting it would
  # install a second fish ahead of the system's on PATH). So the exact combination below is
  # SILENT: no eval error, no output difference, a value that looks live in the source and
  # renders to nothing at all.
  #
  # Measured live, not hypothetical: a real consumer host carried this exact combination for five
  # days (2026-07-27 to 2026-08-01) after a migration onto `nixsh.fish` left the old
  # `programs.fish.*` block sitting there unconverted -- unnoticed until the next `home-manager
  # switch` on that host finally applied it and quietly dropped a working shell config (aliases,
  # functions, a per-tty session launcher, and a greeting sourced transitively through it) with no
  # error at any point.
  fishProgramsOrphaned =
    cfg.fish.enable
    && !config.programs.fish.enable
    && (config.programs.fish.shellInit != ""
        || config.programs.fish.interactiveShellInit != ""
        || config.programs.fish.shellAliases != { }
        || config.programs.fish.functions != { });
in
{
  imports = [ ./nixsh.nix ];

  config = lib.mkMerge [
    # An ASSERTION, not `lib.warn`: the bash/zsh half of this same class of trap (nixsh's own
    # config rendering to nothing under a different combination of options) already went through
    # a soft-warning attempt before this backend's bash/zsh branches below were fixed to compose
    # correctly regardless -- the warning fired on every single switch and nobody caught it. A
    # failed build cannot be scrolled past the same way.
    {
      assertions = [
        {
          assertion = !fishProgramsOrphaned;
          message = ''
            nixsh.fish.enable is true, but programs.fish.{shellInit,interactiveShellInit,shellAliases,functions}
            also has content while programs.fish.enable is not true. That content will never render:
            home-manager's own fish module (and everything it implies, including ~/.config/fish/config.fish
            itself) is gated entirely behind programs.fish.enable, and nixsh's home-manager backend
            deliberately never sets it -- see modules/home.nix's own header for why.

            Either move this content into nixsh.fish.interactiveInit / nixsh.fish.aliases (nixsh's own escape
            hatch for content outside its typed primitives), or set programs.fish.enable = true yourself if you
            actually want home-manager's own fish module active alongside nixsh (accepting a second fish binary
            ahead of the system's on PATH -- see this backend's own header for why nixsh itself never does this).
          '';
        }
      ];
    }
    # fish: a numbered conf.d drop-in. 00- so it lands before anything a host adds there itself.
    (lib.mkIf cfg.fish.enable {
      xdg.configFile."fish/conf.d/00-nixsh.fish".text = body "fish";
    })

    # The greeting's own config file, if it declared one -- independent of which shells are
    # enabled, since the file is read by whatever BINARY `greeting.command` names, not sourced by
    # a shell. `~/.config/<path>` is the home-manager half of the XDG-relative shape
    # `greeting.configFile.path`'s own option doc promises (the NixOS backend writes the same
    # relative path under `/etc/xdg/` instead) -- for fastfetch specifically this lands on its own
    # first-listed config path (`fastfetch --list-config-paths`), so no `--config` flag is needed
    # at any of the per-shell call sites `greetingInvocations` feeds, but nixsh does not know or
    # care that the command happens to be fastfetch here.
    (lib.mkIf (cfg.greeting.configFile.path != null) {
      xdg.configFile.${cfg.greeting.configFile.path}.text = cfg.greeting.configFile.text;
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
