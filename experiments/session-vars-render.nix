# Renders modules/home.nix against a REAL home-manager evaluation and reads back whether
# home-manager's own session variables actually reached each shell.
#
#   nix eval --impure --file experiments/session-vars-render.nix \
#     --arg home-manager /path/to/home-manager --apply 'r: r.results'
#
# Kept here rather than in `checks/` for the reason experiments/README.md gives for its neighbours:
# this one needs a real home-manager, and adding that as a flake input would push it into every
# consumer's lock file to serve nothing but a test. `checks/` stays pkgs-light and policy-only.
#
# WHAT IT PROVES. `home.sessionVariables`/`home.sessionPath` are rendered by home-manager into
# `hm-session-vars.sh` and sourced only from modules gated behind `programs.<shell>.enable` -- the
# option nixsh deliberately leaves false. So the interesting host is the one below: nixsh enabled
# for all three shells, home-manager's own shell modules all off. Before modules/home.nix sourced
# the file itself, `bashrcSourcesSessionVars` and its two siblings were false, and every declared
# variable on such a host existed nowhere.
{ nixpkgs ? <nixpkgs>
, home-manager
, system ? builtins.currentSystem
}:
let
  pkgs = import nixpkgs { inherit system; };
  lib = pkgs.lib;

  hm = configuration: (import (home-manager + "/modules") {
    inherit pkgs lib configuration;
  }).config;

  base = {
    home.username = "tester";
    home.homeDirectory = "/home/tester";
    home.stateVersion = "24.05";

    # The values whose disappearance is the whole bug. `sessionPath` is the one that bit a real
    # host: three CLIs installed by home-manager, on disk, unreachable by name.
    home.sessionPath = [ "/home/tester/.local/bin" ];
    home.sessionVariables.NIXSH_RENDER_PROBE = "session-vars-reached-the-shell";
  };

  # The nixsh posture: config from nixsh, binaries from the system, so no programs.<shell>.enable.
  owned = hm {
    imports = [ ../modules/home.nix base ];
    nixsh = {
      bash.enable = true;
      zsh.enable = true;
      fish.enable = true;
      environment.variables.EDITOR = "hx";
    };
  };

  # The other route, where home-manager's own modules are present and write the login-side files.
  composed = hm {
    imports = [ ../modules/home.nix base ];
    programs.bash.enable = true;
    programs.zsh.enable = true;
    nixsh = {
      bash.enable = true;
      zsh.enable = true;
      environment.variables.EDITOR = "hx";
    };
  };

  # `unsafeDiscardStringContext`, because this string is used as a NEEDLE: `lib.hasInfix` and
  # `lib.splitString` build a regex out of it, and Nix refuses a regex that carries a store-path
  # context ("is not allowed to refer to a store path"). The context is exactly what makes the same
  # string correct in the rc file -- it is what turns the interpolation into a reference of the
  # generation -- so it is dropped here, in the test, and nowhere near modules/home.nix.
  sessionVars = builtins.unsafeDiscardStringContext
    "${owned.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";

  bashrc = owned.home.file.".bashrc".text;
  zshrc = owned.home.file.".zshrc".text;
  fishVars = owned.xdg.configFile."fish/conf.d/00-nixsh-session-vars.fish".source;

  results = {
    # The line exists, and it names the store path rather than a profile directory that depends on
    # how home-manager was installed.
    bashrcSourcesSessionVars = lib.hasInfix ''. "${sessionVars}"'' bashrc;
    zshrcSourcesSessionVars = lib.hasInfix ''. "${sessionVars}"'' zshrc;
    pathIsStoreNotProfile =
      lib.hasInfix "/nix/store/" sessionVars && !(lib.hasInfix ".nix-profile" bashrc);

    # ORDER: the environment has to be in place before any config that might read it. Everything
    # nixsh renders lives after the source line, so splitting on it must leave nothing of nixsh's
    # own content in the first half.
    sourcedBeforeNixshContent =
      !(lib.hasInfix "EDITOR" (lib.head (lib.splitString ''. "${sessionVars}"'' bashrc)));

    # fish gets the babelfish translation as its own conf.d file, sorting below both the underlay
    # and nixsh's own drop-in.
    fishGetsATranslatedFile = lib.hasInfix "hm-session-vars.fish" (toString fishVars);

    # The composed route is left to home-manager: no second source line in the interactive rc.
    composedRouteDoesNotDuplicate =
      !(lib.hasInfix "hm-session-vars.sh" composed.programs.bash.initExtra)
      && !(lib.hasInfix "hm-session-vars.sh" composed.programs.zsh.initExtra);
  };
in
{
  inherit results bashrc zshrc;
  fishSessionVarsPath = toString fishVars;
  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
}
