# Evaluates modules/tools.nix for real against `lib.evalModules` and asserts what it resolves —
# the same "Nix inspecting Nix" tier nixmedia's own checks/catalogue-eval.nix is (see that file's
# header for why `nix flake check` needs this at all: it does not evaluate homeModules/
# nixosModules/systemManagerModules on its own, so a green check without a file like this one
# would prove nothing but flake syntax).
#
# Deliberately pkgs-FREE beyond `pkgs.emptyFile` for the derivation shell: this only proves the
# SELECTION/resolution logic (which group a key belongs to, the arch/AUR split, which nixpkgs
# names got named, the shellHooks rendering) is wired correctly. It does NOT prove those nixpkgs
# names still resolve on a real package set — that is experiments/validate-nixpkgs-names.nix's
# job, force-evaluating against one, kept separate for the identical reason nixmedia keeps its own
# two apart (a consumer's own pin decides what a catalogue name resolves to, not this check).
{ pkgs, lib ? pkgs.lib }:
let
  evalWith = selection: (lib.evalModules {
    modules = [ ../modules/tools.nix { nixsh.tools = selection; } ];
  }).config.nixsh.tools;

  full = evalWith {
    core = [ "bat" "eza" "fd" "ripgrep" "fzf" "zoxide" "delta" "dust" "duf" "hexyl" "tokei" "tealdeer" "bc" "pigz" ];
    integrate = [ "starship" "atuin" "direnv" ];
    nav = [ "yazi" "broot" "superfile" "ncdu" ];
    edit = [ "helix" "zellij" "tmux" ];
    git = [ "lazygit" "gitui" ];
    system = [ "btop" "bottom" "nvtop" "s-tui" "isd" "lazydocker" ];
    network = [ "bandwhich" "trippy" "gping" "sniffnet" "termscp" "curl" "wget" ];
    data = [ "jq" "yq" "jless" "visidata" "rainfrog" ];
    media = [ "ffmpeg" "mpv" "yt-dlp" "chafa" "timg" "cmus" ];
    comms = [ "aerc" "gomuks" "newsboat" ];
    record = [ "vhs" "asciinema" ];
    misc = [ "navi" "serpl" "glow" "slumber" "bash-completion" "man-db" "man-pages" ];
  };

  coreOnly = evalWith { core = [ "ripgrep" "fzf" ]; };
  starshipOnly = evalWith { integrate = [ "starship" ]; };
  direnvOnly = evalWith { integrate = [ "direnv" ]; };

  has = list: item: lib.elem item list;

  results = {
    "empty selection resolves to nothing selected" =
      (evalWith { }).selected == [ ];

    "empty selection's shellHooks are all empty strings, not missing keys" =
      let h = (evalWith { }).shellHooks; in
      h.fish == "" && h.bash == "" && h.zsh == "";

    "every group contributes to \`selected\` (14+3+4+3+2+6+7+5+6+3+2+7 = 62)" =
      lib.length full.selected == 62;

    "timg is the sole AUR entry across the whole catalogue" =
      full.aurPackages == [ "timg" ];

    "delta resolves to the pacman name git-delta, not the bare (wrong) name" =
      has full.archPackages "git-delta" && !(has full.archPackages "delta");

    "nvtop resolves to the nested nixpkgs attribute nvtopPackages.full" =
      has full.nixosPackages "nvtopPackages.full" && !(has full.nixosPackages "nvtop");

    "yq resolves to the plain yq nixpkgs attribute, never the unrelated yq-go" =
      has full.nixosPackages "yq" && !(has full.nixosPackages "yq-go");

    "unavailableOnNixos surfaces exactly the three deliberate nixpkgs = null entries -- man-db (shadowed by documentation.man.enable), man-pages and wget (both scoped Arch-only), nothing else" =
      lib.sort (a: b: a < b) full.unavailableOnNixos == [ "man-db" "man-pages" "wget" ];

    "archPackages and aurPackages never share a name -- the pacman transaction footgun this split exists to avoid" =
      lib.intersectLists full.archPackages full.aurPackages == [ ];

    "selecting the same key from two different groups cannot happen -- the enum type is per-group, catching a typo'd cross-group reference at eval time" =
      # `evalModules` is lazy -- `tryEval` alone only forces WHNF (the attrset exists), not the
      # type-checked VALUE inside it. `deepSeq` forces all the way through, which is what actually
      # runs the listOf-enum merge/check that rejects "starship" from the `core` group.
      (builtins.tryEval (builtins.deepSeq (evalWith { core = [ "starship" ]; }).core true)).success == false;

    # ── shellHooks: the whole reason `integrate` is its own group ──────────────────────────────
    "starship's fish hook uses the pipe-source form, not eval" =
      lib.hasInfix "starship init fish | source" starshipOnly.shellHooks.fish
      && !(lib.hasInfix "eval" starshipOnly.shellHooks.fish);

    "starship's bash/zsh hooks use eval \$(starship init <shell>)" =
      lib.hasInfix ''eval "$(starship init bash)"'' starshipOnly.shellHooks.bash
      && lib.hasInfix ''eval "$(starship init zsh)"'' starshipOnly.shellHooks.zsh;

    "direnv's verb is hook, not init -- in every shell's rendering" =
      lib.hasInfix "direnv hook fish | source" direnvOnly.shellHooks.fish
      && lib.hasInfix ''eval "$(direnv hook bash)"'' direnvOnly.shellHooks.bash
      && lib.hasInfix ''eval "$(direnv hook zsh)"'' direnvOnly.shellHooks.zsh
      && !(lib.hasInfix "direnv init" (direnvOnly.shellHooks.fish + direnvOnly.shellHooks.bash + direnvOnly.shellHooks.zsh));

    "a core-only selection produces no shell hooks at all" =
      let h = coreOnly.shellHooks; in
      h.fish == "" && h.bash == "" && h.zsh == "";

    "selecting all three integrate tools stacks all three hooks in one shell's rendering, newline-joined" =
      let f = full.shellHooks.fish; in
      lib.hasInfix "starship init fish" f
      && lib.hasInfix "atuin init fish" f
      && lib.hasInfix "direnv hook fish" f;
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else throw ''
  nixsh: tools-eval check failed. Failing assertions:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
''
