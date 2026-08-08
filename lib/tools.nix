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
#     playback -- so both are HERE, not nixrecord. nixrecord captures the REAL world (camera,
#     microphone, capture card), never a digital interface; capturing a digital interface is owned
#     by whichever repo already owns that interface. A terminal's owner is this repo -- every host
#     has a console, so console recording (asciinema, vhs) is nixsh's, positively, the same way
#     desktop/game capture is nixremote's/nixdesktop's/nixscroll's rather than nixrecord's.
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
# `nixpkgsOverride` (optional, a function `pkgs -> derivation`) is the escape hatch for an entry
# whose bare nixpkgs attribute is the wrong thing to install as-is -- the identical shape
# `integrate`'s own `shellHook` (`shell -> string`) already establishes for "this needs a function
# of the consuming backend's own value, not a second static field", reused here rather than
# invented twice. `nixpkgs` itself stays a plain string even on an entry that also carries
# `nixpkgsOverride` -- it still decides NixOS-eligibility (`nixpkgs != null`) and is still what
# `nixsh.tools.nixosPackages`'s own introspection and the stale-mapping warning name; only the
# FINAL derivation modules/nixos.nix actually force-evaluates and installs into
# `environment.systemPackages` swaps to `nixpkgsOverride pkgs`, never the plain `pkgs.${nixpkgs}`
# lookup -- and even then ONLY when the host has opted in with `nixsh.tools.lean = true;`
# (modules/tools.nix's own option). Off by default: an entry carrying `nixpkgsOverride` changes
# NOTHING for a host that sets nothing, because leanness is a per-host trade a machine opts INTO,
# not a capability this catalogue quietly takes away from whichever host actually uses what got
# trimmed. Arch is entirely untouched by this field regardless of `lean` -- the Arch backend never
# reads `nixpkgsOverride` at all, only `arch`/`aur`. See the `visidata` entry below for the one
# case that needs it today, and its own note for why.
#
# Every (arch, nixpkgs) pair below was verified against a REAL system, not guessed: `pacman -Si
# <name>` against a live CachyOS host for the Arch side, and a force-evaluating `nix-instantiate
# --eval` (not `hasAttrByPath` alone -- see experiments/validate-nixpkgs-names.nix's own header
# for the exact class of stale-alias-to-throw rename that check alone would miss) against a pinned
# nixpkgs revision for the nixpkgs side -- both sides also cross-checked by `meta.homepage`/pacman
# `URL` against each other, so a name that resolves on both platforms but points at two DIFFERENT
# projects (this family's own history: `pkgs.zoom` is a Z-code story player, not zoom-us;
# `pkgs.ark` is a Jupyter R kernel, not KDE's archive manager; `pkgs.qt6ct` is a throwing alias)
# gets caught rather than assumed safe because both names merely exist.
#
# A THIRD FAILURE CLASS sits underneath those two, and only a cross-check of what actually lands in
# `bin/` finds it: two names for the SAME project that expose DIFFERENT COMMANDS. nixpkgs' `_7zz`
# and Arch's `7zip` are the same 7-Zip at the same version, and one gives `7zz` while the other
# gives `7z`/`7za`/`7zr` -- so the pair that looks most correct by homepage and version is the one
# that installs cleanly and leaves the command every caller types missing. Existence, project
# identity, and command surface are three separate questions; a catalogue spanning two planes has
# to answer all three.
#
# `experiments/verify-package-names.sh` reproduces the whole check -- both platforms, every entry,
# reading the names out of THIS file rather than a second hand-kept list -- against the revision
# this repo's own flake.lock pins. Three names in this table needed more than a plain 1:1 mapping
# and are written up properly rather than left as a terse comment -- see
# studies/delta-pacman-name-is-git-delta.md, studies/yq-nixpkgs-namespace-collision.md and
# studies/p7zip-arch-name-is-7zip.md.
{ ... }:
{
  # ── Core CLI: search, list, view -- the everyday reach-fors ────────────────────────────────
  core = {
    bat = { arch = "bat"; nixpkgs = "bat"; note = "cat with syntax highlighting and git-gutter integration."; };
    eza = { arch = "eza"; nixpkgs = "eza"; note = "ls replacement -- git status, tree view, icons."; };
    tree = { arch = "tree"; nixpkgs = "tree"; note = "prints a directory hierarchy as an indented tree. Catalogued alongside `eza --tree` rather than superseded by it: this is the small, universally-present, script-friendly printout (`-J` emits JSON, `-L` bounds the depth), where eza's tree mode is one display option of a larger ls replacement."; };
    fd = { arch = "fd"; nixpkgs = "fd"; note = "find replacement -- sane defaults, respects .gitignore."; };
    ripgrep = { arch = "ripgrep"; nixpkgs = "ripgrep"; note = "grep replacement -- what fzf/helix/yazi's own file search shells out to."; };
    repgrep = { arch = "repgrep"; nixpkgs = "repgrep"; note = "interactive ripgrep-based search-and-replace for a reviewed replacement workflow."; };
    fzf = { arch = "fzf"; nixpkgs = "fzf"; note = "fuzzy finder -- a library other tools embed (zoxide's interactive mode, shell history search) as much as a standalone command."; };
    delta = {
      arch = "git-delta";
      nixpkgs = "delta";
      note = "syntax-highlighting pager for git/diff output. Pacman's own package is named `git-delta`, NOT `delta` -- that bare name belongs to an unrelated family on Arch (deltachat-rpc-server, xdelta3). See studies/delta-pacman-name-is-git-delta.md.";
    };
    dust = { arch = "dust"; nixpkgs = "dust"; note = "du replacement -- a tree of what is actually using disk, sorted, without piping into sort yourself. nixpkgs' own derivation name is `du-dust` (the attribute path stays `dust`)."; };
    duf = { arch = "duf"; nixpkgs = "duf"; note = "df replacement -- a readable table of mounted filesystems."; };
    hexyl = { arch = "hexyl"; nixpkgs = "hexyl"; note = "hex viewer with colored byte-class highlighting."; };
    file = {
      arch = "file";
      nixpkgs = "file";
      note = ''
        identifies what a file actually IS from its magic bytes rather than its extension -- the
        first question asked of anything arriving from outside.

        IT READS HEADERS ONLY, and that limit is worth stating in the catalogue rather than left
        to be rediscovered: `file` is routinely mistaken for an integrity check and is not one.
        Against an archive whose page content had been overwritten in place -- real bytes replaced
        mid-file, container structure untouched -- it reported the worst-damaged PDFs as "PDF
        document, version 1.4, 2 page(s)" and passed every one of them, because the header it
        reads was still perfectly valid. Identification and validation are different questions;
        the `integrity` group below is where the second one is answered, by tools that actually
        decode the payload.
      '';
    };
    tokei = { arch = "tokei"; nixpkgs = "tokei"; note = "lines-of-code counter, by language, per directory -- the fast Rust implementation. Both it and cloc (below) are catalogued deliberately, not as an accidental duplicate; see cloc's own note for the distinction."; };
    cloc = {
      arch = "cloc";
      nixpkgs = "cloc";
      note = ''
        the older, Perl-based lines-of-code counter -- broad per-language coverage and per-file
        blank/comment/code accounting, plus `--diff`/`--count-and-diff`/`--git` to compare two
        trees or two commits, which tokei (above) does not provide. Both are catalogued on
        purpose: which one an operator reaches for is a genuine preference, not something this
        catalogue decides for them.

        `Architecture: any` on Arch -- a pure Perl script, nothing compiled -- so it does not
        appear in any of the cachyos-v3/v4 optimized repos; `extra` (the official Arch repo,
        confirmed present there too) is the only and correct answer, not a fallback from a
        preferred CachyOS one.
      '';
    };
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
    zoxide = {
      arch = "zoxide";
      nixpkgs = "zoxide";
      note = "cd replacement ranking directories by frecency (frequency + recency). Belongs to THIS group, not `core`: without its hook there is no `z` at all, which is this group's defining trait -- the binary alone provides nothing a person types. It was previously catalogued in `core` with a note deferring the hook to the consumer as 'a plain interactiveInit line'; no consumer ever wrote one, so the package installed and the command did not exist. A tool that cannot work without a hook must ship the hook.";
      shellHook = shell:
        if shell == "fish"
        then "zoxide init fish | source"
        else ''eval "$(zoxide init ${shell})"'';
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
    neovim = { arch = "neovim"; nixpkgs = "neovim"; note = "terminal-first Vim successor with an extensible Lua configuration surface."; };
    nano = { arch = "nano"; nixpkgs = "nano"; note = "small terminal editor, retained as the dependable low-friction edit path."; };
    nano-syntax-highlighting = { arch = "nano-syntax-highlighting"; nixpkgs = "nano-syntax-highlighting"; note = "community syntax definitions for Nano; depends on Nano and extends its highlighting coverage."; };
    emacs-nox = {
      arch = "emacs-nox";
      nixpkgs = "emacs-nox";
      note = ''
        Emacs built with NO window-system support at all -- the `-nox` build is terminal-only, so it
        lands here beside neovim/helix/nano by this file's own placement rule rather than in a
        display-substrate repo. Not "Emacs coaxed into a terminal": the rule's test is whether a
        display mode exists and is the DEFAULT, and this build has no display mode to have a
        default about.

        THE PACKAGE MATTERS, not just the catalogue. Both platforms also ship a plain `emacs` that
        links a graphical toolkit (GTK), and on Arch `emacs` and `emacs-nox` CONFLICT -- they own
        the same paths, so pacman refuses to hold both and installing one replaces the other. This
        entry therefore also documents a REPLACEMENT: nixdev's `editors` group used to catalogue
        the GTK build as `emacs`, and that entry was removed when this one was added, so the family
        never offers a host both names to select at once.
      '';
    };
    micro = {
      arch = "micro";
      nixpkgs = "micro";
      note = ''
        Terminal editor with ORDINARY desktop keybindings -- ctrl-s saves, ctrl-q quits, ctrl-c/v
        copy and paste, and there is no mode to be in the wrong one of. That is a different
        proposition from everything else in this group, not a weaker version of it: neovim and
        helix are modal and configured, nano is the dependable floor with its own idiosyncratic
        control keys, and micro is the one an operator can hand to something -- or someone --
        expecting a text box to behave like a text box. `$EDITOR` for a commit message and a
        five-second config fix are the cases it wins.

        BOTH NAMES ARE PLAIN `micro`, which is exactly the shape this file's own header warns about
        (a name that resolves on both platforms while pointing at two different projects), so it
        was cross-checked rather than assumed: pacman's `URL` is https://micro-editor.github.io/
        and nixpkgs' `meta.homepage` is https://micro-editor.github.io -- the same project, and the
        nixpkgs attribute force-evaluates to a real `micro-2.0.15` derivation rather than a
        rename-to-throw. Arch's copy is in `extra` upstream (verified against archlinux.org's own
        package API, not only against a CachyOS mirror, which rebuilds the same package as
        `cachyos-extra-v3/micro` and would prove nothing about a plain Arch host), and the AUR RPC
        returns nothing for the name -- so `aur` stays false.

        ITS COLORSCHEMES AND SYNTAX FILES ARE A SEPARATE QUESTION from installing it, and one this
        repo now answers elsewhere: micro has no include mechanism and a single settings.json, so a
        distro that ships a curated set of them is layered underneath a host's own settings through
        `nixsh.underlay` (modules/nixsh.nix) rather than by anything in this catalogue entry.
      '';
    };
    zellij = { arch = "zellij"; nixpkgs = "zellij"; note = "terminal multiplexer with a discoverable default keybinding layer (on-screen hints) -- tmux's own opposite design choice."; };
    tmux = { arch = "tmux"; nixpkgs = "tmux"; note = "terminal multiplexer -- the older, script/plugin-ecosystem-heavy alternative to zellij; catalogued as a genuine second choice, not superseded by it."; };
  };

  # ── Git ─────────────────────────────────────────────────────────────────────────────────────
  git = {
    git = { arch = "git"; nixpkgs = "git"; note = "git itself. This group catalogued four ways to DRIVE git before it catalogued git, so every host got the TUIs and dashboards from a package the distro happened to have pulled in as someone else's dependency. Wanted on every machine -- there is no host in this family where the absence of git would be correct."; };
    lazygit = { arch = "lazygit"; nixpkgs = "lazygit"; note = "full git TUI -- stage, commit, branch, rebase, stash, all from panels."; };
    gitui = { arch = "gitui"; nixpkgs = "gitui"; note = "faster-starting, narrower-scope git TUI than lazygit -- staging/committing/diffing, not every git subcommand's own workflow."; };
    github-cli = { arch = "github-cli"; nixpkgs = "gh"; note = "GitHub's terminal client for repositories, pull requests, issues, releases and API calls."; };
    gh-dash = { arch = "gh-dash"; aur = true; nixpkgs = "gh-dash"; note = "interactive GitHub pull-request and issue dashboard; uses the GitHub CLI for authentication and API access."; };
  };

  # ── System / process / resource monitors ───────────────────────────────────────────────────
  system = {
    btop = { arch = "btop"; nixpkgs = "btop"; note = "resource monitor -- CPU/mem/disk/net/proc, C++ port of bpytop."; };
    bottom = { arch = "bottom"; nixpkgs = "bottom"; note = "resource monitor, graph-first layout -- a second choice alongside btop, not a replacement for it."; };
    s-tui = { arch = "s-tui"; nixpkgs = "s-tui"; note = "stress-test + monitor in one -- frequency/temperature/power under synthetic load, not just idle readout."; };
    isd = { arch = "isd"; nixpkgs = "isd"; note = "interactive systemd TUI -- units, logs, and control (start/stop/restart) from one screen instead of separate systemctl/journalctl calls."; };
    lazydocker = { arch = "lazydocker"; nixpkgs = "lazydocker"; note = "docker/docker-compose TUI, same family as lazygit -- containers, images, volumes, logs."; };
    lsof = { arch = "lsof"; nixpkgs = "lsof"; note = "lists open files and the processes holding them -- which process still has a deleted file, a mount point or a socket open. The answer to \"target is busy\" on an unmount or a stuck cleanup, which none of the resource monitors above give: they show what a process is CONSUMING, not what it is HOLDING."; };
    hwinfo = {
      arch = "hwinfo";
      nixpkgs = "hwinfo";
      note = ''
        openSUSE's hardware probing tool -- surveys the physical machine itself (CPU, disks,
        network, USB, PCI, memory, BIOS/UEFI) and reports what is actually THERE, which is a
        different question from everything else in this group: btop/bottom/s-tui/isd/lazydocker
        read what is running RIGHT NOW (processes, load, containers, units), lsof reads what a
        process is HOLDING, and hwinfo reads what hardware EXISTS regardless of any of that. A
        pure CLI with no display mode at all -- this file's own admission test -- the same shape
        as lsof just above it.

        Ships several binaries under the one package: `hwinfo` itself is the one reached for; also
        `check_hd`/`convert_hd` (hardware-database maintenance), `getsysinfo` (a plain-text system
        summary) and `mk_isdnhwdb`.
      '';
    };
  };

  # ── Network diagnostics ─────────────────────────────────────────────────────────────────────
  # `sniffnet` was dropped from this group (2026-08-07) for failing this catalogue's own admission
  # test: it is a GUI application, not a TUI -- an Iced app shipping a .desktop file and depending
  # on fontconfig/freetype/zenity/xdg-desktop-portal. The test is whether the tool has a display
  # mode at all and whether that is its DEFAULT; if yes it belongs to a display-substrate repo, not
  # here. It mattered more than a mis-filing usually does because consumers select this catalogue as
  # ONE list for every host, so a GUI entry here reaches headless servers too.
  network = {
    bind = { arch = "bind"; nixpkgs = "bind"; note = "DNS operator tools (`dig`, `host`, `nslookup`) -- inspect resolution without running a name server."; };
    bandwhich = { arch = "bandwhich"; nixpkgs = "bandwhich"; note = "live per-process bandwidth usage -- which process, which connection, right now."; };
    ethtool = { arch = "ethtool"; nixpkgs = "ethtool"; note = "inspect and tune Ethernet link, driver and offload state."; };
    trippy = { arch = "trippy"; nixpkgs = "trippy"; note = "traceroute + ping in one live view, per-hop loss/latency."; };
    gping = { arch = "gping"; nixpkgs = "gping"; note = "ping with a live graph instead of a scrolling log."; };
    inetutils = { arch = "inetutils"; nixpkgs = "inetutils"; note = "traditional network clients such as `telnet` and `ftp`, retained for protocol-level diagnostics."; };
    nmap = { arch = "nmap"; nixpkgs = "nmap"; note = "network discovery and port/service inspection."; };
    tcpdump = { arch = "tcpdump"; nixpkgs = "tcpdump"; note = "packet capture for protocol-level troubleshooting."; };
    termscp = {
      arch = "termscp";
      nixpkgs = "termscp";
      note = "dual-pane file transfer TUI -- SFTP/FTP/SCP/S3/SMB/WebDAV, a terminal-native alternative to a GUI transfer client.";

      # nixpkgs' own termscp hard-links `buildInputs = [ dbus openssl samba ]`
      # (pkgs/by-name/te/termscp/package.nix) for its SMB support -- no cargo feature flag to build
      # it out, unlike visidata's own optional PYTHON deps above. Confirmed EXCLUSIVE to this entry:
      # `nix-store -q --requisites` against every other tool in the real production selection
      # (infra's modules/shared/shells.nix) shows nothing else pulling samba. Standalone closure
      # 456.8 MiB; the real MARGINAL cost in a deduplicated whole-selection buildEnv is smaller
      # (~136 MiB, measured dropping it from the nixvps-class selection) -- most of samba's own
      # weight (krb5, openssl, ...) is already paid by other tools in the selection regardless, so
      # neither number alone is the whole story; both are recorded so a future reader does not have
      # to re-measure to know which one applies to their question.
      #
      # NOT trimmed here: a compiled Rust `buildInputs` linkage is a materially riskier class of
      # change than visidata's lazy Python imports above -- overridePythonAttrs on a
      # buildPythonApplication only touches what gets IMPORTED at runtime; dropping a Rust
      # buildInput changes what the binary LINKS AGAINST, and termscp's own Cargo feature gates
      # (does it even have an SMB-off build?) were not checked. Left as a named, evidenced
      # candidate for whoever picks it up next, not a TODO to rediscover from scratch.
    };
    curl = {
      arch = "curl";
      nixpkgs = "curl";
      note = "the terminal's basic HTTP(S)/FTP request tool. The catalogue records intended tools, not incidental dependency closures. Unlike man-db's deliberate `nixpkgs = null`, curl names a real nixpkgs attribute on every supported plane.";
    };
    wget = {
      arch = "wget";
      nixpkgs = "wget";
      note = "the other fundamental fetch tool alongside curl. It names ordinary Arch and nixpkgs packages, so a selection declares the same capability on every supported plane.";
    };
    rsync = {
      arch = "rsync";
      nixpkgs = "rsync";
      note = ''
        delta-transfer file copier and synchroniser -- compares source and destination and moves
        only the differing blocks, over ssh or its own daemon protocol.

        FILED IN THIS GROUP RATHER THAN `core`, even though it copies local files perfectly well,
        for the same reason curl/wget/termscp sit here beside the packet-capture and
        path-diagnostic tools: what distinguishes rsync from `cp` is a REMOTE transport and the
        delta algorithm that exists to make one cheap. A purely local copy is what `cp` is for; the
        moment a colon appears in the path this is the tool, and that is a network capability.
        (This group's own header calls itself "network diagnostics"; the transfer clients already
        outnumber the diagnostics in it, which is the honest state of the shelf rather than a
        drift to correct here.)

        NO DISPLAY MODE AT ALL, so it clears this catalogue's admission test outright -- no
        argument needed about defaults, unlike the mpv exception the header documents.

        Verified (2026-08-08): `pacman -Si rsync` resolves in an official repository (`extra`
        upstream, served as a `cachyos-extra-v3` rebuild on a v3 host -- a rebuild of the Arch
        repo, not a derivative-only package), archlinux.org's package search confirms one result
        in `extra`, and the AUR RPC returns zero. So `aur` stays unset, which is the direction
        that cannot abort a pacman transaction. `nixpkgs.rsync` forces to a real derivation.
      '';
    };
  };

  # ── Structured data: JSON / YAML / CSV ──────────────────────────────────────────────────────
  #
  # NO DATABASE TOOL BELONGS HERE, and the boundary is by what a tool addresses rather than by what
  # it can be pointed at. Wire-protocol shells, multi-engine command lines and the inspectors that
  # open a database file on disk are all catalogued by nixdb
  # (github:julian-corbet/nixdb-corbet-ch), the repository whose subject is databases. "Runs in a
  # terminal" and "reads structured data" are both true of them and neither is the test.
  #
  # `visidata` below is the near miss, and it stays: it opens two dozen file formats and SQLite is
  # one of them, so reading a database is something it CAN do rather than what it is FOR. A tool
  # whose entire purpose is a database goes to nixdb; a spreadsheet TUI that happens to have a
  # loader does not.
  data = {
    jq = { arch = "jq"; nixpkgs = "jq"; note = "JSON query/transform -- the tool half the rest of this family's own `nix eval --json` output gets piped through."; };
    yq = {
      arch = "yq";
      nixpkgs = "yq";
      note = "YAML/XML/TOML processor with jq's own syntax (kislyuk/yq -- a Python wrapper AROUND jq, not a reimplementation of it). nixpkgs also ships a completely different, unrelated `yq-go` (mikefarah/yq, Go, its own query language) under a name that reads as the obvious modern choice -- it is not this tool, and selecting it here would be silently wrong rather than loudly missing. See studies/yq-nixpkgs-namespace-collision.md.";
    };
    jless = { arch = "jless"; nixpkgs = "jless"; note = "JSON pager -- browse/collapse/search a large document, where jq is for transforming one."; };
    visidata = {
      arch = "visidata";
      nixpkgs = "visidata";
      note = "spreadsheet TUI for CSV/JSON/SQLite/etc -- sort, filter, pivot, plot, without loading a GUI spreadsheet.";

      # nixpkgs' own visidata propagates all 37 OPTIONAL entries of upstream's requirements.txt
      # (pandas, numpy, pyarrow, matplotlib, seaborn, h5py, psycopg2, boto3, openpyxl/xlrd/xlwt,
      # pdfminer-six, praw, zulip, requests/urllib3/lxml/beautifulsoup4, and more) -- measured at
      # 1.26 GiB of a 2.1 GiB whole-selection closure, 60% of the total, for a tool whose everyday
      # job is opening a CSV in a terminal. Verified against upstream itself (saulpw/visidata, tag
      # v3.3, the src this file's own pinned nixpkgs revision fetches), not assumed from nixpkgs'
      # own comments: `requirements.txt` is the "pip install -r requirements.txt" EVERYTHING-list
      # (every line commented with the one format/API it backs); `setup.py`'s own `install_requires`
      # -- the actual hard dependency pip enforces -- names only `python-dateutil`. Confirmed safe
      # to trim, not merely cheap to: every loader in `visidata/loaders/*.py` that touches one of
      # these imports it LAZILY, inside a function body, via `vd.importExternal(name)`
      # (visidata/settings.py) -- which catches `ModuleNotFoundError` and fails that one command
      # with an "install X" message, never the process. That matters because
      # `visidata/__init__.py`'s own `vd.importSubmodules('visidata.loaders')` DOES eagerly import
      # every loader MODULE at startup with no try/except of its own -- a bare top-level `import
      # pandas` anywhere in that tree would turn a dropped package into a startup crash, not a
      # missing feature. Checked line by line: no loader module has one; the heaviest,
      # `visidata/loaders/_pandas.py`, imports pandas only inside its own `save_dta()` function
      # body.
      #
      # Kept: `python-dateutil` (setup.py's real `install_requires`, backs the `date` column type),
      # `pyyaml` (visidata/loaders/yaml.py -- YAML is an everyday structured-data format, not an
      # API client), `tabulate` + `wcwidth` (~1 MiB combined -- the "tabulate" save format; cheap
      # enough to keep even though guarded the identical lazy way).
      #
      # Dropped -- confirmed by the same per-loader check, none needed to open csv/tsv/json/sqlite:
      # pandas numpy pyarrow (dta/feather/arrow/parquet), matplotlib seaborn (svg/plot save), h5py
      # (hdf5), psycopg2 boto3 (postgres/rds), openpyxl xlrd xlwt (xlsx/xls), pdfminer-six (pdf),
      # praw zulip (reddit/zulip API clients), requests urllib3 lxml beautifulsoup4 (scrape/http
      # loaders), pyshp pypng fonttools odfpy vobject msgpack brotli zstandard dpkt dnslib sh
      # psutil faker setuptools importlib-metadata. A future reader who needs xlsx/parquet/hdf5/pdf
      # back: add that ONE package to `propagatedBuildInputs` below, not the whole list -- naming
      # the trade here is the point.
      #
      # `doCheck = false`: upstream's own checkPhase (`dev/test.sh`) replays visidata's full test
      # corpus, which exercises the very formats/APIs this override drops -- it is a test suite
      # written for the full requirements.txt install, not a regression test for what remains.
      # Correctness for what this build DOES keep is proven out of band, against the built binary,
      # with real csv/tsv/json/sqlite fixtures (see nixsh's own experiments/ for that run).
      #
      # THIS TRIMMED BUILD IS OPT-IN, not the new default -- the operator's own call, not a
      # correction of the analysis above. Whether xlsx/pdf/hdf5/pyarrow etc. are worth 1 GiB
      # depends on what the HOST actually does with visidata, and this catalogue has no way to
      # know that from the package name alone: corbet-server crunches the data those loaders read,
      # so it stays on the full build (sets nothing, `nixsh.tools.lean` defaults false); the
      # nixvps-class hosts (e2-micro, vultr) only ever open a csv/tsv/json/sqlite over SSH, so THEY
      # set `nixsh.tools.lean = true;` and get this derivation instead. See that option's own doc
      # in modules/tools.nix, and `resolveTool` in modules/nixos.nix for where it is actually read.
      nixpkgsOverride = pkgs: pkgs.visidata.overridePythonAttrs (_old: {
        propagatedBuildInputs = with pkgs.python3Packages; [
          python-dateutil
          pyyaml
          tabulate
          wcwidth
        ];
        doCheck = false;
      });
    };
  };

  # ── Terminal media: play, view, fetch, INSPECT -- no display server needed (mpv is the
  # exception; see this file's own header) ────────────────────────────────────────────────────
  #
  # "Inspect" is the fourth verb rather than a fourth group: exiftool/mediainfo/imagemagick answer
  # what a media file IS and what is inside it, from a shell, over a directory. That is not media
  # CONSUMPTION -- nixmedia's own scope test is what a person plays, browses, reads or fetches, and
  # driving `identify` over ten thousand files is none of those -- so those three are not that
  # repo's, and they are not a display-substrate concern by this file's own placement rule either
  # (none of the three has a display mode at all; the GUI builds are separately-named packages, see
  # `mediainfo`'s own note). They are ops tooling for media files, and this is the group that already
  # owns media files. Note the division of labour with the `integrity` group below: everything here
  # reports what a file CLAIMS about itself (ffmpeg excepted -- `ffprobe`/`-f null -` genuinely
  # decode), the integrity group decides whether the payload is still sound.
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
    exiftool = {
      arch = "perl-image-exiftool";
      nixpkgs = "exiftool";
      note = ''
        reads (and writes) the embedded metadata of essentially every image, video and audio format
        there is -- EXIF, IPTC, XMP, maker notes, container tags -- from one command, recursively
        over a tree. The tool reached for when the question is when/where/with-what a file was
        produced, or when a whole archive's timestamps have to be normalised.

        PACMAN'S NAME IS `perl-image-exiftool`, not `exiftool`: upstream ships it as the Perl
        distribution Image::ExifTool and Arch packages it under that name, while nixpkgs exposes
        the same distribution as a top-level `exiftool` attribute. The same shape as `delta`/
        `git-delta` in `core` -- verified by cross-checking both platforms' own homepage field
        (exiftool.org on each), not by assuming the bare name exists on both.

        Header-level, like `file` in `core`: it reports what a file's metadata CLAIMS. It does not
        decode the payload and will pass a file whose actual content has been destroyed.
      '';
    };
    mediainfo = {
      arch = "mediainfo";
      nixpkgs = "mediainfo";
      note = ''
        reports container, track and codec detail for a media file -- per stream: codec, resolution,
        frame rate, bit rate, duration, channel layout -- in a form meant to be read or parsed
        (`--Output=JSON`). Complements ffprobe rather than repeating it: ffprobe is the decoder's
        own view, mediainfo reads the container's declared structure and is the more legible of the
        two for a quick "what am I holding".

        THE CLI SPECIFICALLY. Both platforms ship a separate GUI build under its own name
        (`mediainfo-gui`), which is a windowed application and would fail this file's own placement
        rule; the bare `mediainfo` name is the command-line one on Arch and in nixpkgs alike.
      '';
    };
    imagemagick = {
      arch = "imagemagick";
      nixpkgs = "imagemagick";
      note = ''
        `identify`, `convert`/`magick` and `compare` -- image inspection, batch conversion and
        pixel-level comparison from a shell, over a directory, without a GUI editor.

        `compare` is the reason this is more than a converter: it is what proves two files with
        identical sizes differ in their actual DECODED PIXELS rather than merely in their bytes.
        That is the check that confirmed a personal archive's images had been overwritten in place
        -- same byte count, every header still parsing, `file` and `exiftool` both satisfied, and
        the rendered image provably different from the known-good copy.

        `identify` is a tolerant reader by design: it will report on a file that a format-specific
        validator rejects outright. Useful for triage, not a verdict -- see the `integrity` group
        below for the strict half.
      '';
    };
  };

  # ── Archives: extraction and packing ────────────────────────────────────────────────────────
  #
  # The tools reached for to GET AT the contents of arbitrary incoming data -- an external drive, a
  # download, a decade-old backup written by software nobody runs any more. Kept separate from
  # `integrity` below even though the two visibly overlap (`zip -T` tests, `lsar -t` tests): the
  # question here is "can I open it", there it is "is what I already hold still sound". A host that
  # ingests foreign data wants both; a host that only unpacks releases wants this one alone.
  #
  # tar/gzip/bzip2/xz/zstd/cpio are DELIBERATELY ABSENT, and the absence is the content: both
  # platforms ship them as base system components -- NixOS's `corePackageNames`
  # (nixos/modules/config/system-path.nix) names bzip2, gnutar, gzip, xz, zstd and cpio outright,
  # and Arch's `base` meta-package pulls the same set -- so a catalogue entry would put a SECOND
  # copy on PATH ahead of the one every other program on the box already resolves to. `zip` and
  # `unzip` are in neither base set on either platform, which is exactly why they ARE catalogued
  # here; the line is drawn by what the platform already guarantees, not by how fundamental the
  # format feels.
  archive = {
    p7zip = {
      arch = "7zip";
      nixpkgs = "p7zip";
      note = ''
        the 7-Zip command line: reads and writes .7z, and reads a long tail of other formats
        besides -- the general opener for whatever an incoming drive turns out to be holding.

        BOTH SIDES OF THIS PAIR ARE TRAPS, in opposite directions, and neither is guessable.

        Pacman's name is `7zip`, NOT `p7zip`. Arch retired its p7zip package in favour of upstream
        7-Zip's own Linux port, and that package declares `Provides: p7zip`, `Replaces: p7zip`,
        `Conflicts With: p7zip`. `p7zip` is not in the AUR either, so `aur = true` would not have
        rescued the bare name -- it does not exist on Arch in any repository, and a pacman
        transaction naming it fails whole, taking every unrelated package in the same converge with
        it. Resolving it as a virtual provide would be no better for a reconciler: the declared name
        would never match the installed one, so every run would try to install it again.

        The nixpkgs attribute stays `p7zip` and NOT `_7zz`, which is the less obvious half. `_7zz`
        is the official 7-Zip -- by project and even by version the closer match to what Arch now
        ships -- but it installs its binary as `7zz` and nothing else, while Arch's `7zip` package
        installs `7z`, `7za` and `7zr`, and `7z` is the name scripts and archive front-ends call by
        hand. Picking `_7zz` for project purity resolves perfectly and then silently fails to
        provide the command anyone actually types: the same shape of failure as a throwing alias,
        arriving through a name that is entirely real. nixpkgs' `p7zip` (the p7zip-project fork)
        ships `7z`/`7za`/`7zr` -- the identical command surface as the Arch package, which is what
        a cross-plane catalogue owes its consumer. See studies/p7zip-arch-name-is-7zip.md.
      '';
    };
    unzip = { arch = "unzip"; nixpkgs = "unzip"; note = "extracts zip archives, and `zipinfo` lists one without unpacking it. Also the reader for every zip-container document format (docx/xlsx/pptx/odt), which is often the fastest way to find out what is actually inside one."; };
    zip = { arch = "zip"; nixpkgs = "zip"; note = "creates zip archives -- the separate Info-ZIP half of the pair above, and the one whose absence is only noticed when something needs to be PACKED for a system that reads nothing else. `zip -T` also tests an existing archive's integrity, which is why the zip-container document formats are checkable at all: a failed central directory means a dead Office document."; };
    unar = {
      arch = "unarchiver";
      nixpkgs = "unar";
      note = ''
        `unar` extracts, `lsar` lists (and `lsar -t` tests) -- RAR above all, plus a long tail of
        legacy formats (StuffIt, ARJ, LZH, ISO, and more) that turn up on old external media and
        that nothing else here opens.

        DELIBERATELY NOT `unrar`. nixpkgs marks unrar's licence unfreeRedistributable and refuses
        to evaluate it without an `allowUnfree` carve-out -- a carve-out that applies to the whole
        host configuration, not to one package, and one not worth taking for a single format when a
        free reader for that same format is right here. This is a positive choice about which tool
        gets catalogued, not a gap: the RAR capability is present, it simply arrives through unar.

        Pacman's name is `unarchiver` (the project is MacPaw's XADMaster, shipped as The
        Unarchiver's command-line tools); nixpkgs' attribute is `unar`, after the binary. Neither
        platform uses the other's name.
      '';
    };
    cabextract = { arch = "cabextract"; nixpkgs = "cabextract"; note = "extracts Microsoft .cab archives -- installer payloads and driver bundles on Windows-sourced media, which no general-purpose extractor here reads."; };
  };

  # ── Content integrity: does the payload still decode? ───────────────────────────────────────
  #
  # A different question from every other group in this file, and the one most easily assumed
  # already answered. A checksumming filesystem does not answer it: ZFS guarantees that the bytes
  # handed to it come back unchanged, never that those bytes were correct when they arrived.
  # Content-addressed dedup is equally blind -- a corrupt copy and a clean copy of the same file
  # are simply two different hashes, i.e. "two versions", with nothing to say which is which. And
  # the identification tools (`file`, `exiftool` in their own groups above) read headers, which
  # survive the damage: an archive whose real content had been overwritten in place presented
  # intact headers throughout and passed both. Deciding that content is still sound takes something
  # that reads the whole payload -- a decoder, a stored manifest, or stored parity.
  #
  # WHAT IS HERE AND WHAT IS NOT. Three of these are format-agnostic (`hashdeep`, `rhash`,
  # `par2cmdline` work on any bytes at all) and three cover audio specifically. The general decode
  # test for the video/container population is `ffmpeg` in `media` above -- catalogued once, there,
  # not repeated here. Format-specific decoders beyond audio (PDF engines, raster validators) are
  # not catalogued in nixsh at all; a host that ingests those formats declares them itself.
  #
  # WHERE REDUNDANCY IS DELIBERATE. More than one tool per format is a design choice, not
  # duplication to tidy away: independent implementations fail differently, and this is measured
  # rather than assumed -- across a real damaged-PDF population one engine missed two files that a
  # second engine caught. The audio trio below is the same principle: `flac -t` verifies FLAC's own
  # embedded CRCs, `mp3val` validates MPEG frames, `shntool len` cross-checks stream length against
  # what the container declares.
  integrity = {
    mp3val = {
      arch = "mp3val";
      aur = true;
      nixpkgs = "mp3val";
      note = ''
        validates -- and repairs -- MPEG audio frame by frame. The dedicated tool for the failure
        mode that made this whole group necessary in the first place: an archived MP3 with roughly
        128 KB of audio replaced by zeros in the MIDDLE of the file, container and headers
        untouched.

        THE DIVISION OF LABOUR WITH ffmpeg IS THE POINT, and is why both are catalogued. ffmpeg's
        decode test (`-f null -`) establishes THAT such a file is broken; mp3val reports WHICH
        frames are bad and can rewrite the frame index in place, which is the difference between
        knowing a file is damaged and being able to salvage what is still in it.

        AUR-only on Arch (`aur = true`), an ordinary nixpkgs attribute -- confirmed against
        pacman's own official repositories and the AUR RPC, not assumed from the name.
      '';
    };
    flac = { arch = "flac"; nixpkgs = "flac"; note = "the FLAC encoder/decoder, catalogued for `flac -t`: FLAC is self-verifying, carrying a per-frame CRC and an MD5 of the fully decoded stream in its own header, so a single command gives a real verdict on the payload with nothing stored on the side. The strongest integrity guarantee available for any format here, and it comes free with the format."; };
    shntool = {
      arch = "shntool";
      aur = true;
      nixpkgs = "shntool";
      note = ''
        `shntool len` reports length, size and format consistency across lossless audio formats in
        one table -- the cross-check that catches a stream whose actual duration disagrees with what
        its container declares, which neither a CRC test nor a frame validator is looking for.

        AUR-only on Arch (`aur = true`). nixpkgs' own homepage field points at the Debian package
        page rather than a live upstream site, which is a fact about the project (upstream's own
        site is long dormant) rather than a mismatched pair -- the AUR package builds the same
        shntool 3.0.10.
      '';
    };
    hashdeep = {
      arch = "hashdeep";
      aur = true;
      nixpkgs = "hashdeep";
      note = ''
        recursive hashing with a real AUDIT mode: `hashdeep -r -a -k MANIFEST` compares a tree
        against a stored manifest and reports, in ONE pass, what moved, what is new, what is
        missing and -- the one that matters -- what has the same path and CHANGED content. That set
        arithmetic is what `sha256sum -c` plus a hand-written diff is usually reconstructing under
        pressure; here it is the tool's normal output.

        AUR-only on Arch (`aur = true`), an ordinary nixpkgs attribute.
      '';
    };
    rhash = { arch = "rhash"; nixpkgs = "rhash"; note = "multi-algorithm hashing that also READS and WRITES the digest-file formats found in the wild -- SFV, BSD-style, magnet links -- so an archive that arrived with a .sfv beside it can be verified with the file it came with instead of a hand-rolled comparison. Complements hashdeep: that one audits a tree against its own manifest, this one speaks other people's manifest formats."; };
    par2cmdline = {
      arch = "par2cmdline";
      nixpkgs = "par2cmdline";
      note = ''
        `par2 create` / `verify` / `repair` -- Reed-Solomon parity volumes computed over a set of
        files. THE ONLY TOOL IN THIS GROUP THAT PUTS CONTENT BACK; everything else here can do no
        more than tell you it is gone.

        Worth generating ahead of time for anything irreplaceable: a few percent of extra size
        recovers bit-rot and partial overwrites WITHOUT a second full copy, which is what makes it
        different in kind from a backup rather than a weaker version of one. Detection is not
        recovery, and by the time detection fires the original is usually already gone.
      '';
    };
  };

  # ── Terminal communication clients ──────────────────────────────────────────────────────────
  comms = {
    aerc = { arch = "aerc"; nixpkgs = "aerc"; note = "email client, mutt-successor keybindings, native IMAP/JMAP/SMTP -- no MUA-to-terminal bridge needed."; };
    gomuks = { arch = "gomuks"; nixpkgs = "gomuks"; note = "Matrix client."; };
    newsboat = { arch = "newsboat"; nixpkgs = "newsboat"; note = "RSS/Atom reader."; };
  };

  # ── Terminal session recording -- records a TERMINAL, a digital interface this repo owns.
  # Deliberately not nixrecord's: nixrecord captures the real world (camera, microphone, capture
  # card), never a digital interface -- see this file's own header for the full rule. ──────────
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
      nixpkgs = "man-pages";
      note = ''
        the actual man PAGE CONTENT for sections 2/3/4/5/7/8/9 -- syscalls, C library calls, kernel
        interfaces -- that individual packages' own bundled `/share/man` output rarely carries;
        man-db above is only the reader, not the library. `documentation.man.enable` provides
        `man-db` on NixOS but does not add `man-pages` to `environment.systemPackages`, so this
        entry names the ordinary `man-pages` package on both Arch and NixOS.
      '';
    };
  };
}
