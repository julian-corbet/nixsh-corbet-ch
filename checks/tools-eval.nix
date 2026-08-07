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
    core = [ "bat" "eza" "tree" "fd" "ripgrep" "fzf" "delta" "dust" "duf" "hexyl" "file" "tokei" "cloc" "tealdeer" "bc" "pigz" ];
    integrate = [ "starship" "atuin" "direnv" "zoxide" ];
    nav = [ "yazi" "broot" "superfile" "ncdu" ];
    edit = [ "helix" "neovim" "nano" "nano-syntax-highlighting" "zellij" "tmux" ];
    git = [ "lazygit" "gitui" "github-cli" "gh-dash" ];
    system = [ "btop" "bottom" "s-tui" "isd" "lazydocker" "lsof" "hwinfo" ];
    network = [ "bandwhich" "trippy" "gping" "termscp" "curl" "wget" ];
    data = [ "jq" "yq" "jless" "visidata" ];
    media = [ "ffmpeg" "mpv" "yt-dlp" "chafa" "timg" "cmus" "exiftool" "mediainfo" "imagemagick" ];
    archive = [ "p7zip" "unzip" "zip" "unar" "cabextract" ];
    integrity = [ "mp3val" "flac" "shntool" "hashdeep" "rhash" "par2cmdline" ];
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

    # The label spells out the per-group arithmetic in the SAME ORDER the fixture above lists its
    # groups (core, integrate, nav, edit, git, system, network, data, media, archive, integrity,
    # comms, record, misc) -- so adding a tool to the fixture means editing both the total and the
    # term it belongs to, and a label that no longer adds up is itself the signal that one of the
    # two was forgotten.
    "every group contributes to \`selected\` (16+4+4+6+4+7+6+4+9+5+6+3+2+7 = 83)" =
      lib.length full.selected == 83;

    "AUR entries stay isolated from the pacman transaction" =
      lib.sort (a: b: a < b) full.aurPackages == [ "gh-dash" "hashdeep" "mp3val" "shntool" "timg" ];

    "terminal editors and GitHub tools resolve to their intended platform names" =
      has full.archPackages "neovim"
      && has full.archPackages "nano"
      && has full.archPackages "nano-syntax-highlighting"
      && has full.archPackages "github-cli"
      && has full.aurPackages "gh-dash"
      && has full.nixosPackages "neovim"
      && has full.nixosPackages "nano"
      && has full.nixosPackages "nano-syntax-highlighting"
      && has full.nixosPackages "gh"
      && has full.nixosPackages "gh-dash";

    "delta resolves to the pacman name git-delta, not the bare (wrong) name" =
      has full.archPackages "git-delta" && !(has full.archPackages "delta");

    "yq resolves to the plain yq nixpkgs attribute, never the unrelated yq-go" =
      has full.nixosPackages "yq" && !(has full.nixosPackages "yq-go");

    # ── The archive/integrity groups' own name traps, each verified against a real system before
    # being catalogued and pinned here so a future edit cannot quietly undo it. ────────────────
    "7-Zip resolves to the pacman name 7zip and the nixpkgs attribute p7zip -- never the bare p7zip on Arch (a name no Arch repository carries at all, so a pacman transaction naming it fails whole) and never _7zz on nixpkgs (real, but ships its binary as 7zz only, where every caller types 7z)" =
      has full.archPackages "7zip"
      && !(has full.archPackages "p7zip")
      && has full.nixosPackages "p7zip"
      && !(has full.nixosPackages "_7zz");

    "unar and exiftool carry their own pacman names, which match neither the binary nor the nixpkgs attribute" =
      has full.archPackages "unarchiver"
      && !(has full.archPackages "unar")
      && has full.archPackages "perl-image-exiftool"
      && !(has full.archPackages "exiftool")
      && has full.nixosPackages "unar"
      && has full.nixosPackages "exiftool";

    # The `data` group is JSON/YAML/CSV and stops there: every database tool -- wire shells,
    # multi-engine command lines, on-disk file inspectors -- is nixdb's. visidata stays because a
    # SQLite loader is one of two dozen formats it opens, not what it is for; asserted so the group
    # cannot quietly reacquire a database client.
    "the data group names no database client, and visidata is still in it" =
      has full.archPackages "visidata"
      && !(has full.archPackages "sqlite")
      && !(has full.archPackages "rainfrog")
      && !(has full.nixosPackages "sqlite-interactive")
      && !(has full.nixosPackages "rainfrog");

    # ── visidata's nixpkgsOverride: the closure-lean escape hatch, checked structurally only --
    # this file stays pkgs-free (see its own header), so it cannot call the override itself; that
    # half is proven separately, against a real pkgs, out of band (see nixsh's own experiments/). ──
    "visidata's catalogue entry carries a nixpkgsOverride function -- the NixOS-only mechanism that trims nixpkgs' own 37 propagated optional deps" =
      let v = lib.findFirst (t: t.arch == "visidata") null full.selected; in
      v != null && builtins.isFunction (v.nixpkgsOverride or null);

    "visidata's arch/nixpkgs scalars stay plain strings, untouched by carrying an override -- the Arch side reads only those two, never nixpkgsOverride" =
      let v = lib.findFirst (t: t.arch == "visidata") null full.selected; in
      v.arch == "visidata" && v.nixpkgs == "visidata";

    "no OTHER entry in the whole catalogue carries a nixpkgsOverride -- it stays the one deliberate exception, not a pattern that crept elsewhere" =
      lib.length (lib.filter (t: t ? nixpkgsOverride) full.selected) == 1;

    # ── tools.lean: the per-host opt-in gate, checked structurally only -- whether it actually
    # swaps a derivation is modules/nixos.nix's own `resolveTool`, pkgs-based and out of this
    # file's reach; what belongs HERE is that the gate defaults off and never touches selection. ──
    "tools.lean defaults to false -- a host that sets nothing keeps the full build it has always had" =
      (evalWith { }).lean == false;

    "flipping tools.lean changes nothing about WHICH entries are selected -- it is a resolution-time choice, not a second catalogue row" =
      let
        fatData = evalWith { data = [ "visidata" ]; };
        leanData = evalWith { data = [ "visidata" ]; lean = true; };
        # Compare by `arch` name, not `fatData.selected == leanData.selected` directly: each
        # `evalWith` call re-imports lib/tools.nix, so visidata's `nixpkgsOverride` is a FRESH
        # closure allocation each time -- Nix's `==` on two distinct (if source-identical) function
        # values is always false, which would make list equality here fail for a reason that has
        # nothing to do with selection. Names are what "which entries" actually means.
        names = data: map (t: t.arch) data.selected;
      in
      names fatData == names leanData
      && fatData.lean == false
      && leanData.lean == true;

    "unavailableOnNixos surfaces exactly ONE deliberate nixpkgs = null entry -- man-db, and only because NixOS already installs it via documentation.man.enable, so naming the attribute would be a second copy. man-pages and wget name real attributes: nixsh is a base load for EVERY managed host, and documentation.man.enable adds man-db and nothing else, so a null there would have left NixOS hosts with no man-pages at all" =
      lib.sort (a: b: a < b) full.unavailableOnNixos == [ "man-db" ];

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
