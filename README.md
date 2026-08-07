# nixsh

**Everything that lives in a terminal, declared — with every binary left to the system.**

Two capabilities, one flake: the original shell system (shared environment, per-shell config,
fish universal variables, a guarded greeting) and a terminal-native **tool catalogue** — shells,
TUIs, CLI tools, and their shell-integration hooks, resolved to the right package name on each
platform. Every host has a shell and reaches for a terminal tool, so unlike the display-substrate
family (nixdesktop/nixmedia/nixrecord) neither half of this repo has a per-host story to build.

Absorbs [nixfish](https://github.com/julian-corbet/nixfish-corbet-ch). That module's real
contribution was never fish-specific: it was the *adoption pattern* — how to take over a config
file a vendor package or years of hand-editing already owns — plus a typed primitive for fish
universal variables. The first problem is identical for bash and zsh, so it generalises.

## What is shared, and what is not

This is the entire design, and getting it wrong is the obvious trap.

**Shared** — environment variables and PATH. The only difference between shells is `set -gx`
versus `export`, so one declaration renders into each shell's own syntax:

```nix
nixsh.environment.variables.EDITOR = "hx";
nixsh.environment.path = [ "/opt/tools/bin" ];
```

```fish
set -gx EDITOR "hx"          # fish
fish_add_path /opt/tools/bin
```
```bash
export EDITOR="hx"           # bash + zsh
export PATH="/opt/tools/bin:$PATH"
```

**Not shared** — aliases, functions, completions. fish is not POSIX, and a generic alias DSL
rendering to three syntaxes would render to three syntaxes *badly*. Those stay per-shell,
deliberately unabstracted.

## Nix owns config, the system owns the binary

On a foreign distro the shell must be the **system's** copy: it is what `/etc/shells` lists and
what login actually execs. home-manager's `programs.fish.enable` installs `pkgs.fish`, which on
Arch puts a second fish on PATH *ahead* of the system one — so the login shell and the interactive
shell become different builds. That was live on a real machine before this module existed.

So the home-manager backend writes **config only**. On NixOS the system *is* nix, so
`nixosModules.nixsh` does install them — same declaration, different correct answer.

The tool catalogue (below) extends the identical stance to every other CLI tool, not just the
three shells: nothing else on a box links against `ripgrep` the way login itself execs
`/etc/shells`' own entry, but a home-manager-installed `bat` still lands on PATH *ahead* of
pacman's on a foreign distro, for no benefit — so the home-manager backend never installs a tool
catalogue selection either, only its shell-integration hooks (see below).

| Backend | Installs shells | Installs tools | Writes shell config | Writes tool hooks |
|---|---|---|---|---|
| `homeModules.nixsh` | no | no | yes | yes (`nixsh.tools.integrate` only) |
| `nixosModules.nixsh` | yes (`environment.systemPackages` + `environment.shells`) | yes (`environment.systemPackages`, force-evaluated) | no | no |
| `systemManagerModules.nixsh` | no — publishes `nixsh.archPackages` | no — publishes `nixsh.tools.archPackages`/`.aurPackages` | no | no |

## The tool catalogue

`nixsh.tools.*` — shells, TUIs, CLI tools, and their configs, in one platform-neutral selection
surface, same shape as [nixmedia](https://github.com/julian-corbet/nixmedia-corbet-ch)'s own
catalogue but nested under `nixsh.tools` rather than flattened (nixsh already has a top-level
`nixsh.terminal` — the terminal EMULATOR — so a tools group also named `terminal` would sit
inches away and mean something unrelated).

**The placement rule**, stated in full in `lib/tools.nix`'s own header so a future addition is
decidable rather than argued:

> Does the tool have a display mode at all, and is that its DEFAULT? Yes → it belongs to a
> display-substrate repo (nixdesktop / nixmedia / nixrecord). No → it belongs here.

Capability is not the test — mpv ships `--vo=sixel` and OBS cannot run headless at all, and a test
built on "can it be coaxed into a terminal" would misfile both, in opposite directions. **mpv is
the one deliberate exception**: its default *is* a graphical window, so by the rule alone it would
belong to nixmedia. It is catalogued here instead, filed by stated use rather than default: the
operator runs mpv specifically as the terminal video/audio player, with vlc reserved as the
graphical fallback. Exception, not duplication — nixmedia's catalogue does not carry mpv, so
there is exactly one place it is declared. See `lib/tools.nix`'s
header for the full reasoning and further worked examples (cmus, zathura, OBS, asciinema/vhs).

Groups: `core` (bat, eza, fd, ripgrep, fzf, delta, dust, duf, hexyl, tokei, tealdeer),
`integrate` (starship, atuin, direnv, zoxide — see below), `nav` (yazi, broot, superfile, ncdu), `edit`
(helix, neovim, nano, nano-syntax-highlighting, zellij, tmux), `git` (lazygit, gitui, github-cli,
gh-dash), `system` (btop, bottom, nvtop, s-tui, isd, lazydocker), `network` (bandwhich, trippy,
gping, termscp), `data` (jq, yq, jless,
visidata, rainfrog), `media` (ffmpeg, mpv, yt-dlp, chafa, timg, cmus), `comms` (aerc, gomuks,
newsboat), `record` (vhs, asciinema — terminal *session* recording, not screen recording; that
stays nixrecord's), `misc` (navi, serpl, glow, slumber).

```nix
{
  imports = [ inputs.nixsh.homeModules.default ]; # or .nixosModules.default / .systemManagerModules.default

  nixsh.tools = {
    core = [ "ripgrep" "fzf" "eza" ];
    integrate = [ "starship" "direnv" ];
    nav = [ "yazi" ];
    edit = [ "helix" "tmux" ];
    git = [ "lazygit" ];
  };
}
```

On Arch, wire the resolved lists into your reconciler the same way you already do for the shells
themselves — the two lists stay separate deliberately (see `modules/tools.nix`'s own
`archPackages` option doc):

```nix
{
  imports = [ inputs.nixsh.systemManagerModules.default ];
  nixarch.packages.pacman = config.nixsh.archPackages ++ config.nixsh.tools.archPackages;
  nixarch.packages.aur = config.nixsh.tools.aurPackages;
}
```

### Shell integration: why nixsh renders the hook, not home-manager's own module

`starship`, `atuin` and `direnv` all need an rc **hook**, not just the binary, to do anything —
an installed-but-unhooked starship prints nothing, changes nothing. home-manager already ships
`programs.starship`/`programs.atuin`/`programs.direnv` modules that render exactly this hook — but
every one of them gates it behind `programs.<shell>.enable`, the same option nixsh's own
home-manager backend has never set (see "Nix owns config, the system owns the binary" above: on a
foreign distro, setting it installs a second shell ahead of the system's on PATH). Relying on
home-manager's own modules for these three tools would therefore render nothing at all on exactly
the hosts this repo is for — the identical silent, installed-but-inert failure the fish-adoption
trap earlier in this README already describes for a different option.

`nixsh.tools.integrate`'s selections get their hook rendered through nixsh's own `interactiveInit`-
equivalent mechanism instead (`nixsh.tools.shellHooks`, computed in `modules/tools.nix`, applied
by `modules/home.nix` — the one backend that already renders shell rc content independent of
`programs.<shell>.enable`), so the config actually applies regardless of which binary is on PATH.

### What nixsh does **not** render

Full config files for the tools above — `starship.toml`, `~/.config/yazi/{yazi,keymap,theme}.toml`,
`~/.config/atuin/config.toml`, helix's `config.toml`, and so on — are deliberately **not**
templated here, for two reasons. First, home-manager already ships typed, actively-maintained
`programs.<tool>` modules for nearly every entry in this catalogue that render exactly these files,
independent of any shell's own enable flag (unlike the hook problem above, this is not a gap only
nixsh can fill — reimplementing it here would be a worse, duplicate copy of code the ecosystem
already maintains). Second, unlike a shell rc file — small, near-universal, one adoption problem
this repo already solved once — most of these are large, genuinely personal per-tool surfaces (yazi
alone is three separate files); cataloguing them centrally would turn nixsh into a config-authoring
product for every tool on the list, well past "which package resolves where, and how does its hook
wire in." The one exception is the shell-integration **hook** above — that gap belongs to nixsh
specifically, because it is the one piece home-manager's own modules cannot render without the
second-binary trap this whole repo exists to avoid.

## loginShell is recorded, not enforced

`nixsh.loginShell` states intent. It does not run `chsh`: the login shell lives in `/etc/passwd`,
which is system state no module should rewrite from under a running session. You get the declared
value and something to check drift against.

## Adoption

Same caution nixfish documented. `~/.bashrc` and `~/.config/fish/config.fish` are almost never
empty — a vendor package may own them, or you may have edited them for years. Back up before first
activation (`home-manager switch -b backup`), as a one-time flag rather than a permanent option.

## Repository layout

| Path | Purpose |
|---|---|
| `flake.nix` | Flake entry point: `homeModules.default`, `nixosModules.default`, `systemManagerModules.default`, `lib.catalogue`/`lib.policy` (shells), `lib.toolsCatalogue`/`lib.toolsPolicy` (tools), and `checks`. |
| `lib/shells.nix` | The shell catalogue — fish/bash/zsh, per-shell export/path/alias syntax. |
| `lib/tools.nix` | The tool catalogue — one entry per selectable tool, platform-specific package names, and the placement-rule header. |
| `modules/nixsh.nix` | Shell policy: environment, per-shell config, greeting. |
| `modules/tools.nix` | Tool policy: selection groups, resolved package lists, shell-integration hooks. |
| `modules/home.nix`, `modules/nixos.nix`, `modules/arch.nix` | The three backends, each importing both policy modules. |
| `checks/` | `nix flake check`-wired proof that the tool catalogue's selection/resolution/hook logic is wired correctly (module evaluation, not a real package build). |
| `experiments/` | `render-smoke-test.nix` (shell rendering), `validate-nixpkgs-names.nix` (force-eval every catalogued nixpkgs name), `verify-package-names.sh` (the full Arch + AUR + nixpkgs verification, reproducible). |
| `studies/` | Findings from the experiments above that changed how the tool catalogue was shaped. |

## Related projects

Part of the same independently-usable NixOS module family:
[nixmedia](https://github.com/julian-corbet/nixmedia-corbet-ch) (media consumption — the
display-substrate side of the placement rule above), [nixrecord](https://github.com/julian-corbet/nixrecord-corbet-ch)
(declarative screen recording via OBS — where `record`'s screen half lives, as opposed to this
repo's terminal-session half), and [nixarch](https://github.com/julian-corbet/nixarch-corbet-ch)
(the Arch host reconciler every `systemManagerModules` backend in this family publishes into).

## License

MIT.
