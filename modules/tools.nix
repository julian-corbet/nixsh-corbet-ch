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
    (map (k: cat.archive.${k}) cfg.archive)
    (map (k: cat.integrity.${k}) cfg.integrity)
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
    data = mkGroup "structured-data (JSON/YAML/CSV) tools -- database clients are nixdb's, not this shelf's" cat.data;
    media = mkGroup "terminal-native media tools (play, view, fetch, inspect -- see lib/tools.nix's own header for the placement rule, and the mpv exception)" cat.media;
    archive = mkGroup "archive extraction and packing (tar/gzip/bzip2/xz/zstd/cpio are deliberately absent -- both platforms ship those in the base system; see lib/tools.nix's own group header)" cat.archive;
    integrity = mkGroup "content-integrity tools -- does the PAYLOAD still decode, a question no filesystem checksum and no header reader answers (see lib/tools.nix's own group header)" cat.integrity;
    comms = mkGroup "terminal communication clients" cat.comms;
    record = mkGroup "terminal SESSION recording -- not screen recording, see lib/tools.nix's own header" cat.record;
    misc = mkGroup "everything else" cat.misc;

    lean = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Opt into a catalogue entry's `nixpkgsOverride` (lib/tools.nix's own header documents the
        field -- today, just visidata, trimmed of nixpkgs' own 37 propagated optional format/API
        deps) wherever the current selection has one, instead of the plain nixpkgs attribute.
        Off by default ON PURPOSE: a host that sets nothing keeps the SAME build it has always
        had -- the full one, every loader present -- because the operator's own call is that
        leanness is a per-host trade a machine opts INTO, not a capability this catalogue quietly
        takes away from whichever host happens to actually use the dropped formats (corbet-server,
        which crunches the data those loaders read, stays on the full build for exactly that
        reason). A tiny host that never opens an xlsx/parquet/hdf5/pdf in visidata -- the nixvps
        class today -- sets `nixsh.tools.lean = true;` once and gets the trimmed derivation for
        every entry that has one, present or future; nothing here re-decides that per entry.

        NixOS-only in EFFECT, not in where it is declared: `resolveTool` in modules/nixos.nix is
        the one place this is actually read. The Arch backend never installs a package off an
        entry's `nixpkgs`/`nixpkgsOverride` side at all (pacman's own visidata is already lean --
        38 MiB, unrelated to this option, see lib/tools.nix's own visidata note) and the
        home-manager backend does not install `nixsh.tools` selections either (see
        `shellHooks`'s own option doc below for that boundary) -- so this option is declared once,
        here, alongside the rest of `nixsh.tools`, and is simply inert on the two backends that
        have nothing to gate.
      '';
    };

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
        Selections with `nixpkgs = null` in the catalogue, surfaced rather than silently dropped
        -- for TWO distinct reasons a reader of this list alone cannot tell apart, so don't assume
        either one from membership here: no nixpkgs equivalent exists at all (the original,
        exhaustive-until-now reason this option was added, matching nixmedia's own identical
        mechanism), or the catalogue entry deliberately declines to install one on NixOS even
        though a real nixpkgs attribute exists -- see that entry's own note in lib/tools.nix (e.g.
        man-db, shadowed by `documentation.man.enable`'s own default). The warning this feeds
        (modules/nixos.nix) is worded to hold under both.
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
