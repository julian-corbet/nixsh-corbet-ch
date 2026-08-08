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

The rule decides display, not subject, so one boundary is worth stating outright: **no database
tool is catalogued here.** Wire-protocol shells, multi-engine command lines and the inspectors that
open a database file on disk all pass the terminal test and all belong to
[nixdb](https://github.com/julian-corbet/nixdb-corbet-ch) instead, because subject beats substrate
when a repository exists for the subject. `visidata` is the near miss and stays: SQLite is one of
two dozen formats it opens, so reading a database is something it *can* do rather than what it is
*for*.

Groups: `core` (bat, eza, tree, fd, ripgrep, repgrep, fzf, delta, dust, duf, hexyl, file, tokei,
cloc, tealdeer, bc, pigz),
`integrate` (starship, atuin, direnv, zoxide — see below), `nav` (yazi, broot, superfile, ncdu), `edit`
(helix, neovim, nano, nano-syntax-highlighting, micro, zellij, tmux), `git` (lazygit, gitui, github-cli,
gh-dash), `system` (btop, bottom, s-tui, isd, lazydocker, lsof, hwinfo, wev), `network` (bandwhich, trippy,
gping, termscp), `data` (jq, yq, jless,
visidata), `media` (ffmpeg, mpv, yt-dlp, chafa, timg, cmus, exiftool, mediainfo,
imagemagick), `archive` (p7zip, unzip, zip, unar, cabextract), `integrity` (mp3val, flac, shntool,
hashdeep, rhash, par2cmdline), `comms` (aerc, gomuks,
newsboat), `record` (vhs, asciinema — terminal *session* recording, not screen recording; that
stays nixrecord's), `misc` (navi, serpl, glow, slumber).

Two of those groups answer questions the others don't, and are worth naming separately. `archive`
is how you *get at* arbitrary incoming data — tar/gzip/bzip2/xz/zstd/cpio are deliberately absent,
because both platforms ship those in the base system and a second copy on PATH would shadow the one
everything else resolves to; `zip`/`unzip` are in neither base set, which is why they *are* here.
`integrity` asks whether a payload still **decodes** — a question a checksumming filesystem does not
answer (ZFS guarantees the bytes it was handed come back unchanged, never that they were correct on
arrival), content-addressed dedup does not answer (a corrupt and a clean copy are just "two
versions"), and `file`/`exiftool` do not answer either, since headers survive the damage. Only a
decoder, a stored manifest, or stored parity does — and `par2cmdline` is the one tool in the family
that puts content *back* rather than merely reporting its loss.

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

## The underlay: the distro's config goes underneath yours

`nixsh.underlay` names one idea and applies it to every tool that needs it: **a distro-provided
base layer, with everything nixsh declares sitting on top of it and winning.** The distro keeps
improving its base; every difference from it stays a deliberate, visible line in a Nix file.

That layering already works natively — with no help from anyone — for `sysctl.d`, `udev/rules.d`,
`modprobe.d` and systemd drop-ins: the vendor's file goes in `/usr/lib`, yours goes in `/etc`, and
yours wins by rule. Shell and editor config has no such rule. A distro ships its base through
`/etc/skel`, which is a **one-shot copy at account creation** and never a layer: an account made
before the package existed never gets it, an account made after gets a frozen copy no upgrade
touches, and neither has any relationship to the file the package actually maintains.

```nix
nixsh.underlay = lib.mkMerge [
  config.nixsh.underlayPresets.cachyos            # fish + zsh vendor configs, micro's schemes
  { fish.before = "…"; }                          # per-host refinement, merged not replaced
];
nixarch.packages.pacman = config.nixsh.underlayPackages;   # the packages that PROVIDE the bases
```

Two ways to land a base, because the tools genuinely differ:

| `layer` | How it lands | Why ours wins |
|---|---|---|
| `"shell"` | The base is `source`d at runtime, **first**, before anything nixsh writes. | Redefinition. The last `alias`/`function`/`set` for a name survives, so "ours last" *is* "ours wins". For fish that means two `conf.d` files: `00-nixsh-underlay.fish` and `50-nixsh.fish`. For bash/zsh, which have no `conf.d`, the base goes at the top of the one rc file. |
| `"files"` | The base's children are symlinked into the tool's own config directory. | Per file. Every name in `ours` is refused from the base, and the linker never replaces a name it did not create itself — so a file nixsh declares simply is the file that gets written. |

Three properties it holds to, none of them optional:

- **Ours always wins**, and it is proved rather than assumed —
  `experiments/underlay-ours-wins.sh` runs a real fish and a real zsh and reads back which
  definition survived; `experiments/underlay-files-merge.sh` runs the file layer's activation
  logic through a full switch cycle and drives micro itself through a pty.
- **It degrades cleanly when the base is absent.** The existence test is emitted *into the shell*
  and *into the activation script*, so it is asked on the target machine at the moment it matters.
  A plain Arch host, a NixOS host, or a host whose package was uninstalled last week takes the
  false branch and keeps everything nixsh declares.
- **No impure path is ever read at evaluation time.** A base is a distro artifact, not a Nix
  input. `builtins.pathExists` on `/usr/share` would answer about whichever machine built the
  config, which is not necessarily the one that runs it.

Rendered by the **home-manager backend only** — the same boundary `nixsh.tools.shellHooks` draws,
for the same reason. `nixosModules.nixsh` warns rather than silently doing nothing if a shared
config file declares one.

## loginShell is recorded, not enforced

`nixsh.loginShell` states intent. It does not run `chsh`: the login shell lives in `/etc/passwd`,
which is system state no module should rewrite from under a running session. You get the declared
value and something to check drift against.

## Adoption

Same caution nixfish documented. `~/.bashrc` and `~/.config/fish/config.fish` are almost never
empty — a vendor package may own them, or you may have edited them for years. Back up before first
activation (`home-manager switch -b backup`), as a one-time flag rather than a permanent option.

**The underlay has its own one-time step, and it is the same problem one layer down.** A
`layer = "files"` entry never replaces a name it did not create — that refusal is what makes "ours
wins" structural rather than merely declared, and it does not distinguish between a file you
deliberately declared and one `/etc/skel` copied into your home years ago at account creation. On
a host where the account predates the underlay, those copies are sitting exactly where the links
want to go, so the first switch silently changes nothing at all.

Check what is actually there before assuming the mechanism is live:

```console
$ ls -ld ~/.config/micro/colorschemes      # a real directory => the stale skel copy, not a link
$ diff -r ~/.config/micro /etc/skel/.config/micro   # identical? then it is safe to remove
```

Remove the stale copies once (after confirming they are the distro's, unedited), and the next
switch links them. Everything named in `ours` stays yours and is never involved.

## Repository layout

| Path | Purpose |
|---|---|
| `flake.nix` | Flake entry point: `homeModules.default`, `nixosModules.default`, `systemManagerModules.default`, `lib.catalogue`/`lib.policy` (shells), `lib.toolsCatalogue`/`lib.toolsPolicy` (tools), and `checks`. |
| `lib/shells.nix` | The shell catalogue — fish/bash/zsh, per-shell export/path/alias syntax. |
| `lib/tools.nix` | The tool catalogue — one entry per selectable tool, platform-specific package names, and the placement-rule header. |
| `modules/nixsh.nix` | Shell policy: environment, per-shell config, greeting, and the distro `underlay`. |
| `modules/tools.nix` | Tool policy: selection groups, resolved package lists, shell-integration hooks. |
| `modules/home.nix`, `modules/nixos.nix`, `modules/arch.nix` | The three backends, each importing both policy modules. |
| `checks/` | `nix flake check`-wired proof that the tool catalogue's selection/resolution/hook logic and the underlay's own resolution are wired correctly (module evaluation, not a real package build). |
| `experiments/` | `render-smoke-test.nix` (shell rendering), `validate-nixpkgs-names.nix` (force-eval every catalogued nixpkgs name), `verify-package-names.sh` (the full Arch + AUR + nixpkgs verification, reproducible), `underlay-ours-wins.sh` and `underlay-files-merge.sh` (the underlay's claims, against real shell and editor binaries). |
| `studies/` | Findings from the experiments above that changed how the tool catalogue or the underlay was shaped. |

## Related projects

Part of the same independently-usable NixOS module family:
[nixmedia](https://github.com/julian-corbet/nixmedia-corbet-ch) (media consumption — the
display-substrate side of the placement rule above), [nixrecord](https://github.com/julian-corbet/nixrecord-corbet-ch)
(declarative screen recording via OBS — where `record`'s screen half lives, as opposed to this
repo's terminal-session half), and [nixarch](https://github.com/julian-corbet/nixarch-corbet-ch)
(the Arch host reconciler every `systemManagerModules` backend in this family publishes into).

## License

MIT.
