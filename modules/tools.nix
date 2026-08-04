#
# nixsh's tool catalogue, as policy: selection groups + the resolved lists a backend consumes --
# same shape as nixmedia's own modules/nixmedia.nix, one flat group per selectable domain.
#
# NESTED under `nixsh.tools` rather than flattened onto nixsh's own top level, unlike nixmedia
# (which has nothing else living in its namespace to collide with). nixsh already has
# `nixsh.terminal` -- the TERMINAL EMULATOR, declared in modules/nixsh.nix, read by a desktop
# module deciding what to install and bind. A top-level tools group named `terminal` for "terminal
# media" would sit inches from that option and mean something unrelated; nesting keeps the two
# capabilities this one flake now carries -- shell CONFIG (fish/bash/zsh/greeting/environment,
# pre-existing) and tool PACKAGES (this) -- textually apart even though they share every backend
# module.
{ config, lib, ... }:
let
  cfg = config.nixsh.tools;
  cat = import ../lib/tools.nix { };
  shells = lib.attrNames (import ../lib/shells.nix { });

  mkGroup = what: table: lib.mkOption {
    type = lib.types.listOf (lib.types.enum (lib.attrNames table));
    default = [ ];
    description = "Which ${what}. Available: ${lib.concatStringsSep ", " (lib.attrNames table)}.";
  };

  selected = lib.flatten [
    (map (k: cat.core.${k}) cfg.core)
    (map (k: cat.integrate.${k}) cfg.integrate)
    (map (k: cat.nav.${k}) cfg.nav)
    (map (k: cat.edit.${k}) cfg.edit)
    (map (k: cat.git.${k}) cfg.git)
    (map (k: cat.system.${k}) cfg.system)
    (map (k: cat.network.${k}) cfg.network)
    (map (k: cat.data.${k}) cfg.data)
    (map (k: cat.media.${k}) cfg.media)
    (map (k: cat.comms.${k}) cfg.comms)
    (map (k: cat.record.${k}) cfg.record)
    (map (k: cat.misc.${k}) cfg.misc)
  ];
in
{
  options.nixsh.tools = {
    core = mkGroup "core CLI tools (search, list, view -- the everyday reach-fors)" cat.core;
    integrate = mkGroup "shell-integration tools (need an rc hook -- see \`shellHooks\` below, and lib/tools.nix's own header)" cat.integrate;
    nav = mkGroup "file/navigation TUIs" cat.nav;
    edit = mkGroup "editors and multiplexers" cat.edit;
    git = mkGroup "git TUIs" cat.git;
    system = mkGroup "system/process/resource monitors" cat.system;
    network = mkGroup "network diagnostic tools" cat.network;
    data = mkGroup "structured-data (JSON/YAML/CSV/SQL) tools" cat.data;
    media = mkGroup "terminal-native media tools (play, view, fetch -- see lib/tools.nix's own header for the placement rule, and the mpv exception)" cat.media;
    comms = mkGroup "terminal communication clients" cat.comms;
    record = mkGroup "terminal SESSION recording -- not screen recording, see lib/tools.nix's own header" cat.record;
    misc = mkGroup "everything else" cat.misc;

    selected = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      readOnly = true;
      internal = true;
      description = ''
        The resolved catalogue entries for every name in the groups above, in one flat list --
        the canonical "what did this host actually ask for" a platform backend consumes. Both
        backends derive their package lists from THIS, not by re-categorizing selections through
        Arch's own AUR/pacman split the way nixfont's own `selected` option's docstring warns
        against -- a package that is AUR-only on Arch is not AUR-only (or missing) on NixOS, and
        filtering by an Arch-only distinction would silently drop it there.
      '';
    };

    archPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        Selections as pacman names, for the host's own reconciler: `nixarch.packages.pacman =
        config.nixsh.archPackages ++ config.nixsh.tools.archPackages;` -- concatenated with
        nixsh's own pre-existing shell list, not replacing it; the two are separate lists on
        purpose (shells' binary requirement -- must be the SYSTEM's copy, /etc/shells, login --
        does not apply to an ordinary CLI tool, so keeping the lists apart keeps that distinction
        visible at the call site rather than merging two different kinds of "must be installed").
      '';
    };

    aurPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        Selections that live in the AUR rather than an official repo, kept SEPARATE because
        `pacman -S` cannot resolve them -- it fails the whole transaction with "target not
        found", taking the rest of the converge down with it. Wire them to the AUR side:
        `nixarch.packages.aur = config.nixsh.tools.aurPackages;`.
      '';
    };

    nixosPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        Selections' nixpkgs attribute names (dotted paths), for introspection. The NixOS backend
        (modules/nixos.nix) does NOT install straight off this list -- it force-evaluates each
        name against the real `pkgs` first, because a name appearing here can still be a STALE
        mapping (nixpkgs converts a renamed attribute to `throw "... renamed to ..."`, which
        keeps the key present and only breaks when the value is actually forced). A name in
        `nixosPackages` is therefore a declared intent, not an install guarantee.
      '';
    };

    unavailableOnNixos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        Selections with no nixpkgs equivalent, surfaced rather than silently dropped. Empty
        today -- every entry in lib/tools.nix currently has nixpkgs coverage -- kept for the same
        reason nixmedia keeps the identical mechanism: a uniform shape across the family, ready
        for a future entry that does not resolve on both platforms.
      '';
    };

    shellHooks = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      readOnly = true;
      description = ''
        Init-hook lines for every selected `integrate` tool, rendered in each shell's own syntax
        via that tool's own `shellHook` function in lib/tools.nix, and keyed the same way
        `nixsh.rcFiles`/`nixsh.greetingInvocations` already are (one entry per shell in
        lib/shells.nix). Empty string for a shell with no `integrate` selections, or none of the
        selected tools' hooks resolving for it.

        Computed here, platform-neutral -- consumed only by modules/home.nix, which is the one
        backend that reliably renders shell rc content independent of `programs.<shell>.enable`
        (see that module's own header). modules/nixos.nix installs the `integrate` tools'
        BINARIES like any other tool selection but does not consume this option: its own header
        already states its render surface is narrow BY DESIGN -- the greeting alone, nothing else
        `nixsh.rcFiles` carries -- and a tool selected under `nixsh.tools.integrate` with no
        home-manager backend present is exactly that same, pre-existing, already-documented gap
        (no shell config renders there today without home-manager either), not a new one.
      '';
    };
  };

  config = {
    nixsh.tools.selected = selected;
    nixsh.tools.archPackages =
      lib.unique (map (t: t.arch) (lib.filter (t: !(t.aur or false)) selected));
    nixsh.tools.aurPackages =
      lib.unique (map (t: t.arch) (lib.filter (t: t.aur or false) selected));
    nixsh.tools.nixosPackages =
      lib.unique (map (t: t.nixpkgs) (lib.filter (t: t.nixpkgs != null) selected));
    nixsh.tools.unavailableOnNixos =
      lib.unique (map (t: t.arch) (lib.filter (t: t.nixpkgs == null) selected));

    nixsh.tools.shellHooks = lib.genAttrs shells (s:
      lib.concatStringsSep "\n" (lib.filter (x: x != "")
        (map (k: (cat.integrate.${k}.shellHook or (_: "")) s) cfg.integrate)));
  };
}
