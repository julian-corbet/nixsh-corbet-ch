# NixOS backend — here the system IS nix, so installing the shells is correct rather than a
# duplication. environment.systemPackages puts them in /run/current-system/sw/bin, which is the
# system path on this platform; /etc/shells picks them up the usual way.
#
# fastfetch: the one piece of CONFIG this backend renders at all. Every other shell option
# (interactiveInit/aliases/environment/universalVariables -- everything `nixsh.rcFiles` carries)
# stays unrendered here on purpose: this backend has never turned on NixOS's own
# `programs.<shell>.enable` for the shells it installs, so `programs.<shell>.interactiveShellInit`
# (which IS how NixOS's own fish/zsh modules would consume that content -- verified against
# nixpkgs' `nixos/modules/programs/fish.nix`/`zsh/zsh.nix`, both `config = lib.mkIf cfg.enable
# { ... }` gated, the identical shape as home-manager's own module this repo already routes
# around) has stayed a wider, pre-existing gap this pass does not close. fastfetch alone needs
# JUST ENOUGH of that machinery -- one guarded line, not a whole rc file -- to satisfy a real,
# named requirement (a NixOS host must show the same unmistakable-hostname greeting the Arch
# hosts do, since "which box am I on" does not care which config backend rendered the answer),
# so it is turned on here, narrowly, gated on `cfg.fastfetch.enable` itself rather than on
# `cfg.<shell>.enable` alone -- a host that merely wants the shell BINARIES (nixsh's original,
# unconditional NixOS behaviour, still true for every mkHost/mkNixnas consumer that has not
# opted into fastfetch) sees no change at all.
{ config, lib, pkgs, ... }:
let
  cfg = config.nixsh;
  catalogue = import ../lib/shells.nix { };
  enabled = lib.filter (s: cfg.${s}.enable) (lib.attrNames catalogue);
in
{
  imports = [ ./nixsh.nix ];
  config = lib.mkMerge [
    {
      environment.systemPackages = (map (s: pkgs.${catalogue.${s}.nixpkgs}) enabled)
        ++ lib.optional cfg.fastfetch.enable pkgs.fastfetch;
      environment.shells = map (s: pkgs.${catalogue.${s}.nixpkgs}) enabled;
    }

    # `/etc/xdg/fastfetch/config.jsonc`, not `/etc/fastfetch/` -- both are on fastfetch's own
    # config-path list (`fastfetch --list-config-paths`), but `/etc/xdg/...` is the one that
    # mirrors the per-user XDG layout the home-manager backend writes into
    # (`~/.config/fastfetch/...`), so the same relative shape holds on both backends rather than
    # one platform getting a bespoke top-level `/etc/fastfetch/`.
    (lib.mkIf cfg.fastfetch.enable {
      environment.etc."xdg/fastfetch/config.jsonc".text = cfg.fastfetchConfigJSON;
    })

    (lib.mkIf (cfg.fastfetch.enable && cfg.fish.enable) {
      # Only `programs.fish.enable` this backend has ever set -- narrowly, for fastfetch's own
      # sake, not a general "NixOS now owns fish config" switch. See this file's own header.
      programs.fish.enable = true;
      programs.fish.interactiveShellInit = cfg.fastfetchInvocations.fish;
    })

    (lib.mkIf (cfg.fastfetch.enable && cfg.zsh.enable) {
      programs.zsh.enable = true;
      programs.zsh.interactiveShellInit = cfg.fastfetchInvocations.zsh;
    })

    (lib.mkIf (cfg.fastfetch.enable && cfg.bash.enable) {
      # No `programs.bash.enable = true` needed -- NixOS defaults it to true already (unlike fish
      # and zsh above), and this backend has no reason to touch that default either way.
      programs.bash.interactiveShellInit = cfg.fastfetchInvocations.bash;
    })
  ];
}
