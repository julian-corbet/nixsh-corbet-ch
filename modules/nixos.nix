# NixOS backend — here the system IS nix, so installing the shells is correct rather than a
# duplication. environment.systemPackages puts them in /run/current-system/sw/bin, which is the
# system path on this platform; /etc/shells picks them up the usual way.
#
# greeting: the one piece of shell CONFIG this backend renders at all. Every other shell option
# (interactiveInit/aliases/environment/universalVariables -- everything else `nixsh.rcFiles`
# carries) stays unrendered here on purpose: this backend has never turned on NixOS's own
# `programs.<shell>.enable` for the shells it installs, so `programs.<shell>.interactiveShellInit`
# (which IS how NixOS's own fish/zsh modules would consume that content -- verified against
# nixpkgs' `nixos/modules/programs/fish.nix`/`zsh/zsh.nix`, both `config = lib.mkIf cfg.enable
# { ... }` gated, the identical shape as home-manager's own module this repo already routes
# around) has stayed a wider, pre-existing gap this pass does not close. The greeting alone needs
# JUST ENOUGH of that machinery -- one guarded line, not a whole rc file -- to satisfy a real,
# named requirement (a NixOS host must show the same unmistakable-hostname greeting the Arch
# hosts do, since "which box am I on" does not care which config backend rendered the answer), so
# it is turned on here, narrowly, gated on `cfg.greeting.command != ""` itself rather than on
# `cfg.<shell>.enable` alone -- a host that merely wants the shell BINARIES (nixsh's original,
# unconditional NixOS behaviour, still true for every mkHost/mkNixnas consumer that has not
# opted into a greeting) sees no change at all.
#
# THE GREETING'S OWN BINARY IS NOT THIS BACKEND'S JOB, unlike the shells' binaries above: `nixsh`
# has no opinion on what `greeting.command` names (see modules/nixsh.nix's own header on that
# option), so there is no `catalogue`-style package-name table to install FROM here -- a consumer
# who sets `nixsh.greeting.command = "fastfetch";` on this backend still has to add
# `pkgs.fastfetch` to their own `environment.systemPackages`, exactly as they already do for
# `nixsh.terminal` (a declaration, not an installer -- same stance, stated there in full).
{ config, lib, pkgs, ... }:
let
  cfg = config.nixsh;
  catalogue = import ../lib/shells.nix { };
  enabled = lib.filter (s: cfg.${s}.enable) (lib.attrNames catalogue);
  greetingOn = cfg.greeting.command != "";
in
{
  imports = [ ./nixsh.nix ];
  config = lib.mkMerge [
    {
      environment.systemPackages = map (s: pkgs.${catalogue.${s}.nixpkgs}) enabled;
      environment.shells = map (s: pkgs.${catalogue.${s}.nixpkgs}) enabled;
    }

    # `/etc/xdg/<path>`, mirroring `~/.config/<path>` on the home-manager backend -- see
    # `greeting.configFile.path`'s own option doc in modules/nixsh.nix for why the identical
    # relative path is what makes the two backends interchangeable from a consumer's point of
    # view. Generic: this backend does not know or care whether the file is fastfetch's, or
    # what format it is in.
    (lib.mkIf (greetingOn && cfg.greeting.configFile.path != null) {
      environment.etc."xdg/${cfg.greeting.configFile.path}".text = cfg.greeting.configFile.text;
    })

    (lib.mkIf (greetingOn && cfg.fish.enable) {
      # Only `programs.fish.enable` this backend has ever set -- narrowly, for the greeting's own
      # sake, not a general "NixOS now owns fish config" switch. See this file's own header.
      programs.fish.enable = true;
      programs.fish.interactiveShellInit = cfg.greetingInvocations.fish;
    })

    (lib.mkIf (greetingOn && cfg.zsh.enable) {
      programs.zsh.enable = true;
      programs.zsh.interactiveShellInit = cfg.greetingInvocations.zsh;
    })

    (lib.mkIf (greetingOn && cfg.bash.enable) {
      # No `programs.bash.enable = true` needed -- NixOS defaults it to true already (unlike fish
      # and zsh above), and this backend has no reason to touch that default either way.
      programs.bash.interactiveShellInit = cfg.greetingInvocations.bash;
    })
  ];
}
