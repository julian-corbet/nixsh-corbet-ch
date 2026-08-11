# Evaluates the home backend's systemd-user PATH projection (`nixsh.environment.systemdUserPath`)
# and asserts what it renders -- the same "Nix inspecting Nix" tier as its two siblings, and needed
# for the reason checks/tools-eval.nix's own header states: `nix flake check` does not evaluate
# `homeModules` on its own, so a green check without a file like this proves only flake syntax.
#
# WHY THIS ONE EXISTS AT ALL. The value it renders contains `''${PATH}` as a LITERAL, for
# environment.d to expand later at manager-start time (`man 5 environment.d`). Nix interpolating it
# instead is a one-character mistake that does not fail: the rendered file gets whatever PATH the
# BUILDER had baked in as a constant, and the session silently runs with a frozen, wrong PATH --
# or, if the builder's PATH was empty, with the four characters `$PATH` sitting in the list as
# though they named a directory. Nothing logs either outcome. The literal is therefore the single
# most important thing here, and it is asserted twice: once for the exact substring, once for the
# absence of any expanded store path that would prove Nix had eaten it.
#
# WHAT THIS CANNOT PROVE. That systemd actually re-reads environment.d and applies it -- that is
# the manager's behaviour, not this module's rendering, and it belongs to a live session rather
# than an eval. It also cannot prove PRECEDENCE against a real shell; the assertion here is only
# that the shell projection and this one agree about prepending, which is the property whose
# absence would rebuild the original bug in a subtler form.
#
# UNLIKE its two siblings this one is NOT pkgs-free, and cannot be: the projection lives in the
# home BACKEND (modules/home.nix), which is what has to be evaluated for anything to render, and
# that file uses `pkgs.runCommandLocal` for its babelfish translation. Composing only
# modules/nixsh.nix here would evaluate the option surface and none of the rendering -- the first
# draft of this check did exactly that, and every assertion read `null`.
{ pkgs, lib ? pkgs.lib }:
let
  # The home backend needs the option surface AND a stand-in for the home-manager options it
  # writes into. Same shape as a real home-manager tree in the two attributes this touches.
  stubs = { lib, ... }: {
    options = {
      home = lib.mkOption { type = lib.types.anything; default = { }; };
      xdg.configFile = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
      systemd.user = lib.mkOption { type = lib.types.anything; default = { }; };
      programs = lib.mkOption { type = lib.types.anything; default = { }; };
      assertions = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      warnings = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    };
  };

  evalWith = settings: (lib.evalModules {
    modules = [
      stubs
      ../modules/nixsh.nix
      ../modules/home.nix
      { nixsh = settings; }
    ];
    specialArgs = { inherit pkgs; };
  }).config;

  paths = [ "/home/u/.local/bin" "/home/u/.nix-profile/bin" ];

  on = evalWith {
    fish.enable = true;
    environment.path = paths;
    environment.systemdUserPath = true;
  };

  off = evalWith {
    fish.enable = true;
    environment.path = paths;
  };

  noPaths = evalWith {
    fish.enable = true;
    environment.systemdUserPath = true;
  };

  rendered = on.systemd.user.sessionVariables.PATH or null;

  results = {
    # ── the literal, which is the whole point ─────────────────────────────────────────────────
    "the value ends in a LITERAL \${PATH} for environment.d to expand, not one Nix expanded" =
      rendered != null && lib.hasSuffix ":\${PATH}" rendered;
    "...and Nix did not eat it: no builder PATH leaked into the value" =
      rendered != null
      && !(lib.hasInfix "/nix/store" rendered)
      && !(lib.hasInfix ":/usr/bin" rendered);

    # ── composition ───────────────────────────────────────────────────────────────────────────
    "every declared directory reaches the value, in declaration order" =
      rendered == "/home/u/.local/bin:/home/u/.nix-profile/bin:\${PATH}";
    "declared directories PREPEND, matching the shell projection -- the two must not disagree" =
      rendered != null && lib.hasPrefix (lib.head paths) rendered;

    # ── the switch ────────────────────────────────────────────────────────────────────────────
    # Off is the DEFAULT, and the state in which shells and services disagree. Pinned so the
    # default can never drift silently into rewriting a stranger's session PATH.
    "it is off by default -- nothing is written for a consumer who did not ask" =
      !(off.systemd.user ? sessionVariables);
    "an empty path list writes nothing even when switched on -- no bare \${PATH} assignment" =
      !(noPaths.systemd.user ? sessionVariables);
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixsh: systemd-user-path-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
  ''
