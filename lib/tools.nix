#
# The tool catalogue: shells, TUIs, CLI tools, and their configs -- everything that lives in a
# terminal. Every host has a shell, so unlike nixmedia/nixdesktop/nixrecord this catalogue has no
# per-host story to build: it is universal.
#
# THE PLACEMENT RULE, stated as a boundary rather than a list (same test nixmedia draws against
# nixrecord/nixremote, and nixoffice draws for documents):
#
#   Does the tool have a display mode at all, and is that its DEFAULT?
#     yes -> it belongs to a display-substrate repo (nixdesktop / nixmedia / nixrecord)
#     no  -> it belongs here
#
# "Can it be coaxed into a terminal" is NOT the test. mpv ships `--vo=sixel` and OBS cannot run
# headless at all -- a test built on CAPABILITY rather than DEFAULT would misfile both of those,
# in opposite directions. Worked examples, so a future addition is decidable rather than argued:
#
#   - cmus has no display mode at all (an ncurses music library browser, full stop) -> here.
#   - zathura is GTK4 -- a windowed document viewer with a keyboard-driven UI, not a TUI at all --
#     considered and DROPPED, not filed anywhere in this family. "Keyboard-driven" is not
#     "terminal-native"; zathura never runs inside one.
#   - OBS's default AND only mode is a window; it cannot run headless -> nixrecord, never here.
#   - asciinema and vhs RECORD a terminal -- no display server involved on either end, capture or
#     playback -- so both are here, not nixrecord. This is also what keeps nixrecord single-
#     purpose (screen/window/region capture via OBS, nothing else) rather than accreting "record"
#     as a generic verb it now owns regardless of what is being recorded.
#
# THE MPV EXCEPTION. mpv's default IS a graphical window -- by the rule alone it belongs to
# nixmedia. It is catalogued HERE instead, filed by stated USE rather than default: the operator
# runs mpv as the TERMINAL video/audio player (piped into a `--vo` that stays inside the terminal,
# or audio-only with no video output at all) and reserves vlc, the graphical fallback, for whatever
# mpv genuinely won't open. Say this plainly rather than let a reader conclude the rule above was
# applied loosely -- it was not applied to mpv at all. mpv is the one named exception to it.
#
# ONE PACKAGE, ONE CATALOGUE. nixmedia's lib/media.nix carries vlc and nothing else; ffmpeg, mpv,
# yt-dlp, chafa, timg and cmus are declared here and only here. That is worth stating because the
# rule above could be read as permitting two repos to catalogue the same package under their own
# reasoning -- it does not. Both catalogues feed `environment.systemPackages` on a NixOS host, and
# two entries resolving to the same attribute is a collision there, not a redundancy. The rule
# decides which repo owns a package; it does not license a copy in the other.
#
# `arch` is the pacman package, `nixpkgs` the attribute (dotted path for a nested one). `aur`
# (default false) marks a pacman name that lives in the AUR rather than an official repo -- see
# nixfont's own lib/fonts.nix header, or nixmedia's lib/media.nix header, for why that distinction
# is load-bearing: `pacman -S` fails the WHOLE transaction on an AUR name with "target not found",
# taking every other package in the same converge down with it.
#
# Every (arch, nixpkgs) pair below was verified against a REAL system, not guessed: `pacman -Si
# <name>` against a live CachyOS host for the Arch side, and a force-evaluating `nix-instantiate
# --eval` (not `hasAttrByPath` alone -- see experiments/validate-nixpkgs-names.nix's own header
# for the exact class of stale-alias-to-throw rename that check alone would miss) against the
# nixpkgs revision infra's own flake.lock had pinned at the time
# (1d4e0f865d68258aada31e68e6d79c8c463f3b34) for the nixpkgs side -- both sides also cross-checked
# by `meta.homepage`/pacman `URL` against each other, so a name that resolves on both platforms but
# points at two DIFFERENT projects (this family's own history: `pkgs.zoom` is a Z-code story
# player, not zoom-us; `pkgs.ark` is a Jupyter R kernel, not KDE's archive manager; `pkgs.qt6ct` is
# a throwing alias) gets caught rather than assumed safe because both names merely exist. Three
# names in this table needed more than a plain 1:1 mapping and are written up properly rather than
# left as a terse comment -- see studies/delta-pacman-name-is-git-delta.md,
# studies/nvtop-nixpkgs-attribute-is-nvtopPackages-full.md and
# studies/yq-nixpkgs-namespace-collision.md.
{ ... }:
{
  # ── Core CLI: search, list, view -- the everyday reach-fors ────────────────────────────────
  core = {
    bat = { arch = "bat"; nixpkgs = "bat"; note = "cat with syntax highlighting and git-gutter integration."; };
    eza = { arch = "eza"; nixpkgs = "eza"; note = "ls replacement -- git status, tree view, icons."; };
    fd = { arch = "fd"; nixpkgs = "fd"; note = "find replacement -- sane defaults, respects .gitignore."; };
    ripgrep = { arch = "ripgrep"; nixpkgs = "ripgrep"; note = "grep replacement -- what fzf/helix/yazi's own file search shells out to."; };
    fzf = { arch = "fzf"; nixpkgs = "fzf"; note = "fuzzy finder -- a library other tools embed (zoxide's interactive mode, shell history search) as much as a standalone command."; };
    zoxide = { arch = "zoxide"; nixpkgs = "zoxide"; note = "cd replacement that ranks directories by frecency (frequency + recency); needs a shell hook to work at all, see `integrate` below for the shape that pattern takes when a tool NEEDS one -- zoxide's own hook is simple enough (`zoxide init <shell>`) it is left as a plain `interactiveInit` line for a consumer to write rather than a second generated mechanism for one more tool."; };
    delta = {
      arch = "git-delta";
      nixpkgs = "delta";
      note = "syntax-highlighting pager for git/diff output. Pacman's own package is named `git-delta`, NOT `delta` -- that bare name belongs to an unrelated family on Arch (deltachat-rpc-server, xdelta3). See studies/delta-pacman-name-is-git-delta.md.";
    };
    dust = { arch = "dust"; nixpkgs = "dust"; note = "du replacement -- a tree of what is actually using disk, sorted, without piping into sort yourself. nixpkgs' own derivation name is `du-dust` (the attribute path stays `dust`)."; };
    duf = { arch = "duf"; nixpkgs = "duf"; note = "df replacement -- a readable table of mounted filesystems."; };
    hexyl = { arch = "hexyl"; nixpkgs = "hexyl"; note = "hex viewer with colored byte-class highlighting."; };
    tokei = { arch = "tokei"; nixpkgs = "tokei"; note = "lines-of-code counter, by language, per directory."; };
    tealdeer = { arch = "tealdeer"; nixpkgs = "tealdeer"; note = "tldr client -- community-maintained example-first command summaries, for the `--help` a tool didn't write."; };
    bc = { arch = "bc"; nixpkgs = "bc"; note = "arbitrary-precision calculator -- the decimal/floating-point escape hatch bash's own `$(( ))` cannot provide at all (bash arithmetic is integer-only)."; };
    pigz = { arch = "pigz"; nixpkgs = "pigz"; note = "gzip replacement, parallel across every core instead of one -- the same reach-for upgrade `dust`/`duf` above already are for `du`/`df`."; };
  };

  # ── Shell integration: need an rc HOOK, not just a binary ──────────────────────────────────
  #
  # Why these three are their own group rather than sitting in `core`: home-manager's OWN
  # upstream modules for all three (`programs.starship`, `programs.atuin`, `programs.direnv`)
  # already render both config AND the shell hook -- but the hook half is gated behind
  # `programs.<shell>.enable`, exactly like every other piece of shell config those modules touch.
  # nixsh's whole home-manager backend (modules/home.nix) deliberately never sets
  # `programs.<shell>.enable` -- that is the second-binary trap that module's own header documents
  # at length -- so on a foreign distro, home-manager's own starship/atuin/direnv modules would
  # install the binary and render NOTHING into the shell: the exact silent, installed-but-inert
  # failure this group's own entries name in their notes below. nixsh's `interactiveInit` already
  # exists for exactly this shape (arbitrary literal shell startup content, rendered outside
  # `programs.<shell>.enable`); `modules/tools.nix`'s `shellHooks` is that same mechanism, computed
  # generically for whichever of these three a consumer selects. See modules/tools.nix and
  # modules/home.nix for where it is actually wired in.
  #
  # `shellHook` is a function `shell -> string`, one literal line (or block) in THAT shell's own
  # syntax -- written out per tool rather than through one shared formatter, because the three
  # tools do not even agree on a verb: direnv's own command is `direnv hook <shell>`, starship's
  # and atuin's are `<tool> init <shell>`. A shared "just interpolate init" helper would silently
  # mis-render direnv's line; three short, explicit functions cannot drift that way.
  integrate = {
    starship = {
      arch = "starship";
      nixpkgs = "starship";
      note = "cross-shell prompt.";
      shellHook = shell:
        if shell == "fish"
        then "starship init fish | source"
        else ''eval "$(starship init ${shell})"'';
    };
    atuin = {
      arch = "atuin";
      nixpkgs = "atuin";
      note = "shell history, replacing the shell's own -- SQLite-backed, searchable, optionally synced. Sync is a separate `atuin login`/`atuin register`, never something this catalogue renders a value for.";
      shellHook = shell:
        if shell == "fish"
        then "atuin init fish | source"
        else ''eval "$(atuin init ${shell})"'';
    };
    direnv = {
      arch = "direnv";
      nixpkgs = "direnv";
      note = "per-directory environment loader (`.envrc`). The verb is `hook`, not `init` -- see this group's own header for why that is written explicitly rather than generalised.";
      shellHook = shell:
        if shell == "fish"
        then "direnv hook fish | source"
        else ''eval "$(direnv hook ${shell})"'';
    };
  };

  # ── File / navigation TUIs ──────────────────────────────────────────────────────────────────
  nav = {
    yazi = { arch = "yazi"; nixpkgs = "yazi"; note = "terminal file manager with built-in image/video preview (shells out to a renderer such as chafa)."; };
    broot = { arch = "broot"; nixpkgs = "broot"; note = "fuzzy tree navigator -- a directory tree you can search and cd into in one motion, distinct from yazi's file-manager focus (copy/move/preview)."; };
    superfile = { arch = "superfile"; nixpkgs = "superfile"; note = "panel-based terminal file manager -- multi-pane, mouse-friendly; a different UI shape than yazi's single-pane, keyboard-first one, not a duplicate."; };
    ncdu = { arch = "ncdu"; nixpkgs = "ncdu"; note = "ncurses disk usage analyzer -- an interactive drill-down, where `dust` (core) is a one-shot printout."; };
  };

  # ── Editors and multiplexers ────────────────────────────────────────────────────────────────
  edit = {
    helix = { arch = "helix"; nixpkgs = "helix"; note = "modal editor with LSP/tree-sitter built in, no plugin step required."; };
    zellij = { arch = "zellij"; nixpkgs = "zellij"; note = "terminal multiplexer with a discoverable default keybinding layer (on-screen hints) -- tmux's own opposite design choice."; };
    tmux = { arch = "tmux"; nixpkgs = "tmux"; note = "terminal multiplexer -- the older, script/plugin-ecosystem-heavy alternative to zellij; catalogued as a genuine second choice, not superseded by it."; };
  };

  # ── Git ─────────────────────────────────────────────────────────────────────────────────────
  git = {
    lazygit = { arch = "lazygit"; nixpkgs = "lazygit"; note = "full git TUI -- stage, commit, branch, rebase, stash, all from panels."; };
    gitui = { arch = "gitui"; nixpkgs = "gitui"; note = "faster-starting, narrower-scope git TUI than lazygit -- staging/committing/diffing, not every git subcommand's own workflow."; };
  };

  # ── System / process / resource monitors ───────────────────────────────────────────────────
  system = {
    btop = { arch = "btop"; nixpkgs = "btop"; note = "resource monitor -- CPU/mem/disk/net/proc, C++ port of bpytop."; };
    bottom = { arch = "bottom"; nixpkgs = "bottom"; note = "resource monitor, graph-first layout -- a second choice alongside btop, not a replacement for it."; };
    nvtop = {
      arch = "nvtop";
      nixpkgs = "nvtopPackages.full";
      note = "GPU process monitor (AMD/Intel/NVIDIA) -- btop's own blind spot. nixpkgs has no top-level `nvtop` attribute at all; it lives under `nvtopPackages.full`. See studies/nvtop-nixpkgs-attribute-is-nvtopPackages-full.md.";
    };
    s-tui = { arch = "s-tui"; nixpkgs = "s-tui"; note = "stress-test + monitor in one -- frequency/temperature/power under synthetic load, not just idle readout."; };
    isd = { arch = "isd"; nixpkgs = "isd"; note = "interactive systemd TUI -- units, logs, and control (start/stop/restart) from one screen instead of separate systemctl/journalctl calls."; };
    lazydocker = { arch = "lazydocker"; nixpkgs = "lazydocker"; note = "docker/docker-compose TUI, same family as lazygit -- containers, images, volumes, logs."; };
  };

  # ── Network diagnostics ─────────────────────────────────────────────────────────────────────
  network = {
    bandwhich = { arch = "bandwhich"; nixpkgs = "bandwhich"; note = "live per-process bandwidth usage -- which process, which connection, right now."; };
    trippy = { arch = "trippy"; nixpkgs = "trippy"; note = "traceroute + ping in one live view, per-hop loss/latency."; };
    gping = { arch = "gping"; nixpkgs = "gping"; note = "ping with a live graph instead of a scrolling log."; };
    sniffnet = { arch = "sniffnet"; nixpkgs = "sniffnet"; note = "packet/traffic monitor with a friendlier summary view than raw tcpdump/wireshark output."; };
    termscp = { arch = "termscp"; nixpkgs = "termscp"; note = "dual-pane file transfer TUI -- SFTP/FTP/SCP/S3/SMB/WebDAV, a terminal-native alternative to a GUI transfer client."; };
    curl = {
      arch = "curl";
      nixpkgs = "curl";
      note = "the terminal's own most basic HTTP(S)/FTP request tool -- present today on both hosts ONLY as a dependency (appstream, cmake, git, flatpak, fisher, exiv2, and more), the identical accidental-survival shape wget's own note below names explicitly. Declared here for the same reason: the catalogue records what a host is MEANT to have, not what happens to be pulled in by whatever else currently depends on it -- true regardless of curl also being a ubiquitous dependency; that is not a reason to leave the two most fundamental network CLI tools uncatalogued. `nixpkgs` is a real, ordinary attribute here -- verified by force-evaluation against the pinned nixpkgs revision (this file's own header) -- unlike man-db/man-pages/wget's deliberate `nixpkgs = null`.";
    };
    wget = {
      arch = "wget";
      nixpkgs = null;
      note = "the other fundamental fetch tool alongside curl. `nixpkgs = null` keeps this entry scoped to the two Arch hosts, where the actual gap lives -- on archlxc wget is already a deliberate, standalone install; on the laptop it currently survives only as a dependency of `cloud-image-utils`, and would silently vanish the day that package does, with no distro-level signal anything changed. Declaring it here converts that accidental survival into an intentional one on the hosts where it matters; it makes no claim about a nixpkgs side, unlike man-db above.";
    };
  };

  # ── Structured data: JSON / YAML / CSV / SQL ────────────────────────────────────────────────
  data = {
    jq = { arch = "jq"; nixpkgs = "jq"; note = "JSON query/transform -- the tool half the rest of this family's own `nix eval --json` output gets piped through."; };
    yq = {
      arch = "yq";
      nixpkgs = "yq";
      note = "YAML/XML/TOML processor with jq's own syntax (kislyuk/yq -- a Python wrapper AROUND jq, not a reimplementation of it). nixpkgs also ships a completely different, unrelated `yq-go` (mikefarah/yq, Go, its own query language) under a name that reads as the obvious modern choice -- it is not this tool, and selecting it here would be silently wrong rather than loudly missing. See studies/yq-nixpkgs-namespace-collision.md.";
    };
    jless = { arch = "jless"; nixpkgs = "jless"; note = "JSON pager -- browse/collapse/search a large document, where jq is for transforming one."; };
    visidata = { arch = "visidata"; nixpkgs = "visidata"; note = "spreadsheet TUI for CSV/JSON/SQLite/etc -- sort, filter, pivot, plot, without loading a GUI spreadsheet."; };
    rainfrog = { arch = "rainfrog"; nixpkgs = "rainfrog"; note = "database TUI (Postgres, MySQL/MariaDB, SQLite) -- browse schemas and run queries without a GUI client."; };
  };

  # ── Terminal media: play, view, fetch -- no display server needed (mpv is the exception; see
  # this file's own header) ──────────────────────────────────────────────────────────────────
  media = {
    ffmpeg = { arch = "ffmpeg"; nixpkgs = "ffmpeg"; note = "transcode/inspect -- ffprobe answers what a file actually is, not what its container claims."; };
    mpv = {
      arch = "mpv";
      nixpkgs = "mpv";
      note = "THE MPV EXCEPTION -- see this file's own header. mpv's default is a graphical window; it is catalogued here anyway because the operator runs it as the terminal video/audio player specifically, with vlc (nixmedia) reserved as the graphical fallback. Filed by stated use, not by default.";
    };
    yt-dlp = { arch = "yt-dlp"; nixpkgs = "yt-dlp"; note = "video/audio downloader."; };
    chafa = { arch = "chafa"; nixpkgs = "chafa"; note = "renders an image as terminal graphics/ANSI art -- what yazi's own preview pane calls out to."; };
    timg = {
      arch = "timg";
      aur = true;
      nixpkgs = "timg";
      note = "sixel-/kitty-graphics-protocol-aware terminal image and video viewer -- a genuine second choice alongside chafa, not a duplicate. AUR-only on Arch, an ordinary nixpkgs attribute -- already established by nixmedia's own studies/timg-arch-aur-only.md (github.com/julian-corbet/nixmedia-corbet-ch), which catalogues the same package for the same reason and reached the identical finding; not re-derived here.";
    };
    cmus = { arch = "cmus"; nixpkgs = "cmus"; note = "ncurses music library browser and player -- no GUI dependency, no display mode to have. The clean worked example for this file's own placement rule."; };
  };

  # ── Terminal communication clients ──────────────────────────────────────────────────────────
  comms = {
    aerc = { arch = "aerc"; nixpkgs = "aerc"; note = "email client, mutt-successor keybindings, native IMAP/JMAP/SMTP -- no MUA-to-terminal bridge needed."; };
    gomuks = { arch = "gomuks"; nixpkgs = "gomuks"; note = "Matrix client."; };
    newsboat = { arch = "newsboat"; nixpkgs = "newsboat"; note = "RSS/Atom reader."; };
  };

  # ── Terminal session recording -- records a TERMINAL, not the screen. Deliberately not
  # nixrecord's: see this file's own header for why that stays OBS-only and single-purpose. ────
  record = {
    vhs = { arch = "vhs"; nixpkgs = "vhs"; note = "scripted terminal recording -- a `.tape` file describing keystrokes and timing renders to a GIF/MP4/WebM reproducibly, the way a Dockerfile reproduces an image."; };
    asciinema = { arch = "asciinema"; nixpkgs = "asciinema"; note = "live terminal session recording -- captures the actual session as it happens, where vhs scripts one ahead of time."; };
  };

  # ── Misc ─────────────────────────────────────────────────────────────────────────────────────
  misc = {
    navi = { arch = "navi"; nixpkgs = "navi"; note = "interactive cheatsheet -- fzf-driven, fills in command placeholders rather than just displaying a static tldr page."; };
    serpl = { arch = "serpl"; nixpkgs = "serpl"; note = "search-and-replace TUI across a project tree, VS Code's own find-and-replace panel as a terminal tool."; };
    glow = { arch = "glow"; nixpkgs = "glow"; note = "markdown renderer -- README/docs read as formatted text in the terminal instead of raw source."; };
    slumber = { arch = "slumber"; nixpkgs = "slumber"; note = "REST client TUI -- request collections, environments, chained requests; a terminal-native alternative to a GUI client like Postman/Insomnia."; };
    bash-completion = {
      arch = "bash-completion";
      nixpkgs = "bash-completion";
      note = ''
        tab-completion engine for bash. Filed here rather than `integrate` because it needs none
        of that group's own defining trait -- a per-shell `<tool> init <shell>` incantation run at
        startup: presence alone is enough, since both backends' own platform already auto-sources
        it once installed (Arch's stock `/etc/bash.bashrc` has carried the `[[ -r
        /usr/share/bash-completion/bash_completion ]] && .  ...` guard since before nixsh existed;
        NixOS's own `programs.bash.completion.enable`, nixos/modules/programs/bash/bash-completion.nix,
        defaults to true). That NixOS default is worth naming precisely because it looks like a
        shadowing risk and is not one: it references this exact derivation by absolute store path
        inside the rendered interactive-shell init script, never through `environment.systemPackages`,
        so it does not link the package's own bundled completions (or anything else's, via
        `environment.pathsToLink`'s `/share/bash-completion` entry, also gated on that same option)
        into `/run/current-system/sw/` at all. Cataloguing it here is therefore the first thing
        that actually links it on NixOS, not a second copy of one already sitting in
        `environment.systemPackages` -- and on Arch, where no such default exists at all, this
        entry is the only thing that installs it.
      '';
    };
    man-db = {
      arch = "man-db";
      nixpkgs = null;
      note = ''
        the man page reader/formatter itself. `nixpkgs = null` is deliberate, not an unresolved
        lookup: NixOS already provides man-db by default -- `documentation.man.enable`
        (nixos/modules/misc/documentation.nix) defaults to true, which defaults
        `documentation.man.man-db.enable` (nixos/modules/misc/man-db.nix) to true in turn, and that
        module's own `config = mkIf cfg.enable { environment.systemPackages = [ cfg.package ]; ...
        }` with `cfg.package` defaulting to `pkgs.man-db` -- confirmed by force-evaluating a
        minimal `nixos/lib/eval-config.nix` instantiation against the pinned nixpkgs revision (this
        file's own header): both options resolve `true`, and `man-db` is present in the realized
        `environment.systemPackages` list, not merely the option default. Declaring a `nixpkgs`
        attribute here would put a SECOND `pkgs.man-db` into that same list -- the exact collision
        this file's own header already names for two catalogues sharing a package (ONE PACKAGE, ONE
        CATALOGUE), just arriving from one catalogue and one NixOS default instead of two
        catalogues. This is also the opposite shape from `bash-completion` just above: that entry's
        own NixOS default never reaches `environment.systemPackages` at all, so declaring it there
        is additive; man-db's default DOES reach it directly, so declaring it there would be
        duplicative. The Arch hosts have no such built-in option -- the distro package is the only
        way `man` exists there at all, so this entry is Arch-only by design.
      '';
    };
    man-pages = {
      arch = "man-pages";
      nixpkgs = null;
      note = ''
        the actual man PAGE CONTENT for sections 2/3/4/5/7/8/9 -- syscalls, C library calls, kernel
        interfaces -- that individual packages' own bundled `/share/man` output rarely carries;
        man-db above is only the reader, not the library. `nixpkgs = null` here for a DIFFERENT
        reason than man-db's, not the same one restated: the identical force-evaluated NixOS
        instantiation used to verify man-db's claim shows `documentation.man.enable` provisions
        `man-db` automatically but does NOT add `man-pages` to `environment.systemPackages` at all
        -- there is no NixOS default this would shadow. `nixpkgs = null` is used anyway because this
        entry's job is the two Arch hosts specifically, where the gap is real (absent entirely on
        archlxc, present only via man-db's own transitive pull on the laptop) -- giving corbet-server
        a first-ever `man-pages` declaration would be a separate decision this entry does not make.
      '';
    };
  };
}
