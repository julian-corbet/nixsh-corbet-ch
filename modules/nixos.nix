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
# opted into a greeting) sees no change at all. The tool catalogue below (`nixsh.tools.*`) is the
# identical narrow stance applied to a second surface: it installs the selected tools' BINARIES,
# nothing about their shell hooks or config files -- see modules/tools.nix's own `shellHooks`
# option doc for why that half stays home-manager's job on every backend, this one included.
#
# THE GREETING'S OWN BINARY IS NOT THIS BACKEND'S JOB, unlike the shells' binaries above: `nixsh`
# has no opinion on what `greeting.command` names (see modules/nixsh.nix's own header on that
# option), so there is no `catalogue`-style package-name table to install FROM here -- a consumer
# who sets `nixsh.greeting.command = "fastfetch";` on this backend still has to add
# `pkgs.fastfetch` to their own `environment.systemPackages`, exactly as they already do for
# `nixsh.terminal` (a declaration, not an installer -- same stance, stated there in full).
#
# TOOLS force-evaluate every nixpkgs attribute rather than trusting `hasAttrByPath` alone -- the
# exact fix nixmedia's own modules/nixos.nix backend carries, forced by the same class of bug:
# `hasAttrByPath` only proves the ATTRIBUTE exists, not that it is a usable package. nixpkgs
# converts a renamed package to `<oldName> = throw "renamed to ...";`, which keeps the key present
# and only breaks when the value is actually forced -- exactly what building
# `environment.systemPackages` does. `tryEval` turns that from a hard failure of the WHOLE system
# evaluation into a skip + a warning: lib/tools.nix is a data table, edited far less carefully
# than code, and a single stale mapping in it should not be able to take a host down.
{ config, lib, pkgs, ... }:
let
  cfg = config.nixsh;
  catalogue = import ../lib/shells.nix { };
  enabled = lib.filter (s: cfg.${s}.enable) (lib.attrNames catalogue);
  greetingOn = cfg.greeting.command != "";

  # Filter `tools.selected` directly -- NOT `tools.nixosPackages` or `tools.archPackages` -- for
  # the same reason nixmedia's own nixos.nix backend does: neither of those two lists is the
  # platform-neutral "what did this host actually ask for" (archPackages is deliberately Arch's
  # own pacman/AUR split, e.g. timg is withheld from it because it needs an AUR helper on Arch;
  # that distinction means nothing on NixOS, which has no AUR at all).
  toolsNamed = lib.filter (t: t.nixpkgs != null) cfg.tools.selected;
  toolsEvaluated = map
    (t: {
      inherit t;
      try = builtins.tryEval (builtins.seq (lib.getAttrFromPath (lib.splitString "." t.nixpkgs) pkgs) true);
    })
    toolsNamed;
  toolsInstallable = map (r: r.t) (lib.filter (r: r.try.success) toolsEvaluated);
  toolsStaleMappings = map
    (r: "nixsh: nixpkgs attribute \"${r.t.nixpkgs}\" (catalogue arch name \"${r.t.arch}\") no longer resolves -- lib/tools.nix's mapping is stale, most likely a nixpkgs rename")
    (lib.filter (r: !r.try.success) toolsEvaluated);
in
{
  imports = [ ./nixsh.nix ./tools.nix ];
  config = lib.mkMerge [
    {
      environment.systemPackages =
        (map (s: pkgs.${catalogue.${s}.nixpkgs}) enabled)
        ++ (lib.unique (map (t: lib.getAttrFromPath (lib.splitString "." t.nixpkgs) pkgs) toolsInstallable));
      environment.shells = map (s: pkgs.${catalogue.${s}.nixpkgs}) enabled;

      warnings =
        lib.optional (cfg.tools.unavailableOnNixos != [ ])
          "nixsh: not installed on NixOS via this catalogue: ${lib.concatStringsSep ", " cfg.tools.unavailableOnNixos} (nixpkgs = null in lib/tools.nix -- either no nixpkgs equivalent exists, or the entry deliberately excludes one; see that entry's own note)"
        ++ toolsStaleMappings;
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

      # generateCompletions defaults to true on `programs.fish.enable`, which is NOT narrow at
      # all: it walks `environment.systemPackages` and builds a completions derivation PER
      # PACKAGE. Measured live wiring this into a real host with a large ops toolchain (~100
      # packages): every one of them gained its own "_fish" completions build, plus `man` (1.9 MiB)
      # and man-db caching pulled in as a further side effect of THAT (fish.nix's own
      # `documentation.man.cache.enable = mkDefault true`) -- tens of new derivations and several
      # MiB of closure for a feature nobody asked for, on a backend whose own header promises
      # "narrowly, for the greeting's own sake". Off, so that promise is actually true rather than
      # merely stated.
      programs.fish.generateCompletions = false;
      documentation.man.cache.enable = false;
      documentation.man.cache.generateAtRuntime = false;
    })

    (lib.mkIf (greetingOn && cfg.zsh.enable) {
      programs.zsh.enable = true;
      programs.zsh.interactiveShellInit = cfg.greetingInvocations.zsh;

      # Same reasoning as `programs.fish.generateCompletions` above, smaller blast radius but the
      # identical class of unrequested default: `enableCompletion` (zsh's own name for it)
      # defaults true and pulls `nix-zsh-completions` into the closure as a side effect nothing
      # about the greeting needed.
      programs.zsh.enableCompletion = false;
    })

    (lib.mkIf (greetingOn && cfg.bash.enable) {
      # No `programs.bash.enable = true` needed -- NixOS defaults it to true already (unlike fish
      # and zsh above), and this backend has no reason to touch that default either way.
      programs.bash.interactiveShellInit = cfg.greetingInvocations.bash;
    })
  ];
}
