# Renders all three shells from one declaration and checks the SHARED layer really did come out in
# three different syntaxes -- which is the only thing in this module worth abstracting, and the
# thing most likely to be silently wrong.
#
#   nix-instantiate --eval --strict experiments/render-smoke-test.nix -A fishUsesSetGx   # => true
{ nixpkgs ? <nixpkgs> }:
let
  lib = (import nixpkgs { }).lib;

  # Bootstrap eval, no overrides at all -- just to pull out the shipped fastfetch preset as a
  # plain value, the way a real consumer's `config.nixsh.greeting.presets.fastfetch` read would.
  presetEval = lib.evalModules { modules = [ ../modules/nixsh.nix ]; };
  fastfetchPreset = presetEval.config.nixsh.greeting.presets.fastfetch;

  eval = lib.evalModules {
    modules = [
      ../modules/nixsh.nix
      {
        nixsh = {
          fish.enable = true;
          bash.enable = true;
          zsh.enable = true;
          environment.variables.EDITOR = "hx";
          environment.path = [ "/opt/tools/bin" ];
          fish.universalVariables.fish_greeting = "";
          bash.aliases.ll = "ls -alh";
          # The regression case: an alias value with its OWN embedded double quotes -- an SSH
          # remote command is the real one that broke (julian-corbet/infra's elitebook host,
          # 2026-08-01). Naive `alias name="value"` rendering used to mangle this into several
          # words; both fish's `alias` builtin and POSIX `alias name=value` reject that outright.
          fish.aliases."tmux@x" = ''ssh -t x "tmux new -A -s tmux@x"'';
          bash.aliases."tmux@x" = ''ssh -t x "tmux new -A -s tmux@x"'';

          # The generic mechanism, fed the shipped fastfetch preset wholesale -- exercises both
          # "a consumer opts in at all" and "the preset is actually usable as documented" in one
          # declaration, same as a real consumer would write.
          greeting = fastfetchPreset;
        };
      }
    ];
  };
  rc = eval.config.nixsh.rcFiles;

  # A second, otherwise-identical evaluation with `greeting` left untouched -- proves the
  # mechanism is OFF by default even though the fastfetch preset exists and is fully computed
  # (`presets.fastfetch` is a plain readOnly value, not something merely existing turns on).
  evalNoGreeting = lib.evalModules {
    modules = [
      ../modules/nixsh.nix
      { nixsh.fish.enable = true; }
    ];
  };
in
{
  shells = builtins.attrNames rc;
  # fish must use `set -gx`, the POSIX shells `export` -- from the SAME declaration.
  fishUsesSetGx = lib.hasInfix ''set -gx EDITOR "hx"'' rc.".config/fish/config.fish";
  bashUsesExport = lib.hasInfix ''export EDITOR="hx"'' rc.".bashrc";
  zshUsesExport = lib.hasInfix ''export EDITOR="hx"'' rc.".zshrc";
  # fish PATH is its own builtin, not a PATH assignment.
  fishPathIsBuiltin = lib.hasInfix "fish_add_path /opt/tools/bin" rc.".config/fish/config.fish";
  # universal variables are fish-only and idempotent.
  fishUniversal = lib.hasInfix "set -q fish_greeting; or set -U" rc.".config/fish/config.fish";
  # per-shell aliases must NOT leak into other shells.
  aliasStaysInBash = (lib.hasInfix "alias ll=" rc.".bashrc") && !(lib.hasInfix "alias ll=" rc.".zshrc");
  # An embedded double quote in an alias value must render as ONE token in each shell's own
  # alias syntax -- fish's two-word `alias NAME 'value'`, POSIX's one-word `alias NAME='value'`
  # -- with the value's own quotes passed through literally, not merged into the wrapper quoting.
  fishAliasSurvivesEmbeddedQuotes =
    lib.hasInfix "alias tmux@x 'ssh -t x \"tmux new -A -s tmux@x\"'" rc.".config/fish/config.fish";
  bashAliasSurvivesEmbeddedQuotes =
    lib.hasInfix "alias tmux@x='ssh -t x \"tmux new -A -s tmux@x\"'" rc.".bashrc";
  # The greeting: each shell must get its OWN idiomatic interactive test, not a copy-pasted one --
  # this is the whole point of the feature, so it gets one check per shell rather than a shared
  # "guarded somehow" assertion that could pass on the wrong idiom.
  greetingFishGuard = lib.hasInfix "if status is-interactive" rc.".config/fish/config.fish"
    && lib.hasInfix "fastfetch" rc.".config/fish/config.fish";
  greetingBashGuard = lib.hasInfix "if [[ $- == *i* ]]; then" rc.".bashrc"
    && lib.hasInfix "fastfetch" rc.".bashrc";
  greetingZshGuard = lib.hasInfix "if [[ -o interactive ]]; then" rc.".zshrc"
    && lib.hasInfix "fastfetch" rc.".zshrc";
  # Nothing else's guard idiom leaked into the wrong shell's file.
  fishGuardStaysInFish = !(lib.hasInfix "$- ==" rc.".config/fish/config.fish")
    && !(lib.hasInfix "-o interactive" rc.".config/fish/config.fish");
  bashGuardStaysInBash = !(lib.hasInfix "is-interactive" rc.".bashrc")
    && !(lib.hasInfix "-o interactive" rc.".bashrc");

  # The mechanism is generic -- nixsh's OWN rendering never names "fastfetch" anywhere; the string
  # only appears here because the TEST fed it the fastfetch preset. A consumer naming a different
  # command would see that command instead, with the identical guard shape.
  greetingCommandIsWhatConsumerSet = eval.config.nixsh.greeting.command == "fastfetch";

  # The shipped preset itself: usable wholesale (already proved above, `rc` was rendered FROM it),
  # and its content is fastfetch's own real upstream default -- not invented, not curated down.
  presetCommandIsFastfetch = fastfetchPreset.command == "fastfetch";
  presetConfigPathIsXdgRelative = fastfetchPreset.configFile.path == "fastfetch/config.jsonc";
  presetConfigHasPackagesModule =
    lib.hasInfix "\"packages\"" fastfetchPreset.configFile.text;
  presetConfigCarriesNoLogoOverride = !(lib.hasInfix "\"logo\"" fastfetchPreset.configFile.text);

  # OFF BY DEFAULT: the preset existing and being fully computed must not, by itself, turn
  # anything on. No guard block anywhere, no config file written, in a tree that never touched
  # `nixsh.greeting` at all.
  greetingOffByDefaultCommand = evalNoGreeting.config.nixsh.greeting.command == "";
  greetingOffByDefaultNoFishBlock = !(lib.hasInfix "is-interactive"
    evalNoGreeting.config.nixsh.rcFiles.".config/fish/config.fish");

  # nixsh itself installs nothing for the greeting -- no auto-added package name of any kind,
  # unlike the shells (which DO publish `archPackages`). A consumer wires up their own command's
  # binary, on whichever backend they use.
  archPackagesHasOnlyShells =
    eval.config.nixsh.archPackages == [ "bash" "fish" "zsh" ]; # lib.attrNames sorts alphabetically

  archPackages = eval.config.nixsh.archPackages;
}
