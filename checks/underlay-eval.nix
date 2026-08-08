# Evaluates the underlay (modules/nixsh.nix's `nixsh.underlay`) for real against `lib.evalModules`
# and asserts what it resolves to -- the same "Nix inspecting Nix" tier checks/tools-eval.nix is,
# and needed for the same reason that file's own header states: `nix flake check` does not evaluate
# `homeModules`/`nixosModules`/`systemManagerModules` on its own, so a green check without a file
# like this one would prove nothing but flake syntax.
#
# WHAT THIS CAN AND CANNOT PROVE. It proves the POLICY: which shell a base is rendered for, that
# the guard is a RUNTIME test rather than an eval-time decision, that the path is escaped, that a
# `files` entry never leaks into the shell rendering, that the shipped preset merges with per-host
# refinements instead of being clobbered by them, and that `underlayPackages` surfaces exactly the
# packages declared. It cannot prove the PLACEMENT -- that the rendered block actually lands above
# nixsh's own content in a live shell -- because placement is the home-manager backend's job and
# the ordering rule belongs to the shells themselves. That half is proved empirically instead:
# experiments/underlay-ours-wins.sh runs a real fish and a real zsh and reads back which definition
# survived, and studies/fish-conf-d-order-is-per-directory.md records what that run found (which is
# NOT what fish's own documentation implies, and it changed this design).
#
# Deliberately pkgs-FREE beyond `pkgs.emptyFile` for the derivation shell, exactly like its sibling.
{ pkgs, lib ? pkgs.lib }:
let
  evalNixsh = module: (lib.evalModules {
    modules = [ ../modules/nixsh.nix module ];
  }).config.nixsh;

  empty = evalNixsh { };

  # The exact composition a consumer is meant to write: take the shipped preset wholesale, then
  # refine one entry with a per-host value.
  #
  # `lib.mkMerge`, NOT two sibling attributes. Writing `nixsh.underlay = <preset>;` and
  # `nixsh.underlay.fish.before = "...";` next to each other in ONE attrset is a plain Nix syntax
  # error before the module system is ever reached -- "attribute 'nixsh.underlay' already defined"
  # -- because that is one attrset literal defining the same key twice, not two module definitions.
  # `mkMerge` is what actually produces two definitions of the option, which `attrsOf` then merges
  # per key and the submodule merges per field. Hit while writing this check; pinned here so the
  # documented idiom is the one that is proved to work.
  #
  # Written with a `config`-taking function rather than a literal, because reaching
  # `config.nixsh.underlayPresets` from inside a definition of `config.nixsh.underlay` is the shape
  # that would recurse infinitely if the preset were ever nested under `underlay` -- so this
  # fixture is also a standing regression test for that (see `greeting`'s own header comment in
  # modules/nixsh.nix for the time it actually happened).
  host = evalNixsh ({ config, ... }: {
    nixsh.fish.enable = true;
    nixsh.bash.enable = true;
    nixsh.zsh.enable = true;
    nixsh.underlay = lib.mkMerge [
      config.nixsh.underlayPresets.cachyos
      { fish.before = "function __underlay_check_marker; end"; }
    ];
  });

  # A base whose path needs escaping, and one entry switched off, to prove both are handled.
  awkward = evalNixsh {
    nixsh.zsh.enable = true;
    nixsh.underlay = {
      quoted = {
        layer = "shell";
        shell = "zsh";
        path = "/usr/share/it's here/base.zsh";
        package = "weird-config";
      };
      off = {
        enable = false;
        layer = "shell";
        shell = "zsh";
        path = "/usr/share/disabled/base.zsh";
        package = "disabled-config";
      };
    };
  };

  results = {
    "a host that declares no underlay gets empty strings per shell, not missing keys" =
      empty.underlaySources.fish == ""
      && empty.underlaySources.bash == ""
      && empty.underlaySources.zsh == ""
      && empty.underlayFiles == [ ]
      && empty.underlayPackages == [ ];

    # The preset exists as a VALUE even on a host that never assigns it -- that is what makes
    # `nixsh.underlay = config.nixsh.underlayPresets.cachyos;` writable at all.
    "the CachyOS preset ships three entries and is readable without being assigned" =
      lib.sort (a: b: a < b) (lib.attrNames empty.underlayPresets.cachyos) == [ "fish" "micro" "zsh" ];

    "each shell renders only its OWN base, never another shell's" =
      lib.hasInfix "cachyos-config.fish" host.underlaySources.fish
      && !(lib.hasInfix "cachyos-config.zsh" host.underlaySources.fish)
      && lib.hasInfix "cachyos-config.zsh" host.underlaySources.zsh
      && !(lib.hasInfix "cachyos-config.fish" host.underlaySources.zsh);

    # bash has no CachyOS base -- /etc/skel/.bashrc on such a host is plain Arch's. A shell with no
    # entry must render nothing at all rather than an inert conditional.
    "a shell with no underlay entry renders nothing, even when other shells have one" =
      host.underlaySources.bash == "";

    # THE point of the whole mechanism's third requirement: the existence test is emitted into the
    # shell, so it is asked on the target machine at shell start rather than answered in Nix on
    # whichever machine built the config.
    "the base is guarded by a runtime readability test in each shell's own idiom" =
      lib.hasInfix "if test -r " host.underlaySources.fish
      && lib.hasInfix "source " host.underlaySources.fish
      && lib.hasInfix "if [ -r " host.underlaySources.zsh;

    "a files-layer entry never leaks into any shell's rendering" =
      !(lib.hasInfix "/etc/skel" host.underlaySources.fish)
      && !(lib.hasInfix "/etc/skel" host.underlaySources.bash)
      && !(lib.hasInfix "/etc/skel" host.underlaySources.zsh);

    "the files layer resolves to entries carrying their own key, target and owned names" =
      let f = host.underlayFiles; in
      lib.length f == 1
      && (lib.head f).name == "micro"
      && (lib.head f).into == "micro"
      && (lib.head f).ours == [ "settings.json" ];

    # Assigning the preset and then refining one entry must MERGE. If the module system ever
    # stopped merging these two definitions the refinement would silently vanish, which is the
    # failure mode this fixture exists to catch.
    "a per-host refinement merges into the preset instead of replacing it" =
      lib.hasInfix "__underlay_check_marker" host.underlaySources.fish
      && lib.hasInfix "cachyos-config.fish" host.underlaySources.fish;

    # `before` is for content the base itself must SEE at load time, so it is worthless unless it
    # is rendered above the source line.
    "`before` content is rendered ABOVE the source line, not merely somewhere in the block" =
      let
        f = host.underlaySources.fish;
        parts = lib.splitString "source " f;
      in
      lib.hasInfix "__underlay_check_marker" (lib.head parts);

    "every declared entry's package is surfaced for the host's reconciler" =
      lib.sort (a: b: a < b) host.underlayPackages
      == [ "cachyos-fish-config" "cachyos-micro-settings" "cachyos-zsh-config" ];

    # A path containing a quote is not hypothetical enough to skip: the rendered line is shell
    # source, and an unescaped one would end the string and execute the remainder.
    "a path needing quoting is escaped rather than interpolated raw" =
      lib.hasInfix "'/usr/share/it'\\''s here/base.zsh'" awkward.underlaySources.zsh;

    "a disabled entry renders nothing and contributes no package" =
      !(lib.hasInfix "disabled" awkward.underlaySources.zsh)
      && awkward.underlayPackages == [ "weird-config" ];
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixsh: underlay-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
  ''
