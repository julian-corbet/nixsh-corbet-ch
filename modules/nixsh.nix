#
# nixsh — every shell on every machine, declared.
#
# ONE MODULE FOR EVERY SHELL, fish included: the ADOPTION pattern (how to take over a config file
# a vendor package or years of hand-editing already owns) is identical for bash, zsh and fish --
# /etc/bash.bashrc and a hand-edited ~/.bashrc are the same situation fish's fish_variables is --
# so splitting fish into its own module would just mean two homes for the same logic.
#
# WHAT IS SHARED AND WHAT IS NOT. This is the whole design, and getting it wrong is the obvious
# trap. Shared: environment variables and PATH, because the only difference between shells there
# is `set -gx` versus `export`. NOT shared: aliases, functions, completions -- fish is not POSIX,
# so a generic alias DSL rendering to three syntaxes would render to three syntaxes BADLY. Those
# stay per-shell, deliberately unabstracted.
#
# NIX OWNS CONFIG, THE SYSTEM OWNS THE BINARY. See lib/shells.nix.
{ config, lib, ... }:
let
  cfg = config.nixsh;
  catalogue = import ../lib/shells.nix { };
  enabled = lib.filter (s: cfg.${s}.enable) (lib.attrNames catalogue);

  # fish's single-quote escaping: the only two escapes fish recognises inside '...' are \\
  # (literal backslash) and \' (literal single quote) -- everything else, including embedded
  # double quotes or a leading `$`, passes through completely literally. This is NOT POSIX
  # single-quote escaping: bash/zsh have no in-quote escape at all, so `lib.escapeShellArg`'s
  # close-quote/escape/reopen trick (`'\''`) is the POSIX-correct answer there instead, used
  # directly at each bash/zsh call site below rather than through a second helper here.
  escapeFishSingle = v: "'" + builtins.replaceStrings [ "\\" "'" ] [ "\\\\" "\\'" ] v + "'";

  # ── The underlay's own rendering ─────────────────────────────────────────────────────────────
  #
  # See the `underlay` option's own doc below for what the mechanism IS. This is only how a
  # `layer = "shell"` entry turns into text.
  #
  # THE GUARD IS A RUNTIME TEST, NOT AN EVAL-TIME ONE, and that is the whole reason this renders a
  # conditional instead of deciding anything in Nix. `path` names a file the DISTRO owns, outside
  # the store: it appears when a package is installed and disappears when it is removed, both of
  # which happen long after this module was evaluated -- and on a host whose config was built
  # somewhere else entirely, an eval-time `builtins.pathExists` would be answering about the BUILD
  # machine's filesystem, not the target's. So the test is emitted into the shell and asked every
  # time a shell starts, which is the only moment the answer is both current and about the right
  # box. A host with no such package installed, a plain Arch host, or a NixOS host that inherited
  # this declaration from a shared file all take the false branch and lose nothing else.
  #
  # `-r`, not `-f`/`-e`: an unreadable file is as unusable as a missing one, and `source` on it
  # would abort the rc file rather than degrade.
  underlayBlock = u:
    let
      header = ''# nixsh underlay "${u.name}" -- the distro's own base layer, sourced BEFORE anything nixsh declares.'';
    in
    if u.shell == "fish" then
      lib.concatStringsSep "\n"
        (lib.filter (x: x != "") [
          header
          u.before
          ''
            if test -r ${escapeFishSingle u.path}
                source ${escapeFishSingle u.path}
            end''
        ])
    else
      lib.concatStringsSep "\n" (lib.filter (x: x != "") [
        header
        u.before
        ''
          if [ -r ${lib.escapeShellArg u.path} ]; then
            source ${lib.escapeShellArg u.path}
          fi''
      ]);

  # Every declared-and-enabled entry, each carrying its own attribute KEY back out as `name` --
  # the same shape nixagent's own `resolve` uses, and for the same reason: everything downstream
  # (the rendered header comment above, the activation script's own per-entry banner in
  # modules/home.nix) wants to name WHICH entry it is acting on, and re-deriving that by matching
  # on `path` would be a second source of truth. `mapAttrsToList` iterates in attribute-name
  # order, so the rendered order is the declaration's own alphabetical order -- deterministic, and
  # stable across a host adding an unrelated entry.
  underlayList = lib.mapAttrsToList (n: u: u // { name = n; })
    (lib.filterAttrs (_: u: u.enable) cfg.underlay);

  underlayFor = layer: lib.filter (u: u.layer == layer) underlayList;

  # `terminal` folds in here rather than being a second mechanism: it IS an environment variable,
  # it just has a name worth declaring semantically so other modules can read the choice instead
  # of matching on a string. Declared last, so it wins over a hand-set environment.variables
  # TERMINAL -- there is one canonical place to say this, and it is the option, not the raw var.
  effectiveVariables =
    cfg.environment.variables
    // lib.optionalAttrs (cfg.terminal != null) { TERMINAL = cfg.terminal; };

  # The shared layer, rendered into each shell's own syntax.
  envFor = shell:
    let c = catalogue.${shell}; in
    lib.concatStringsSep "\n" (
      (lib.mapAttrsToList c.exportFmt effectiveVariables)
      ++ (map c.pathFmt cfg.environment.path)
    );

  mkShell = name: {
    enable = lib.mkEnableOption "declarative ${name} configuration (config only -- the binary comes from the system)";

    interactiveInit = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Literal ${name} run at interactive startup. Not translated to any other shell; write ${name} syntax.";
    };

    aliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Aliases for ${name}. Per-shell on purpose: alias syntax and semantics differ enough between fish and POSIX shells that sharing them would be a lie.";
    };
  };

  # THE GREETING GUARD, per shell -- the one place this whole feature can silently go wrong, so it
  # is written explicitly per shell rather than copy-pasted or left to positional luck (relying on
  # "this only happens to be sourced interactively" is exactly what broke once already -- see
  # `greeting.command`'s own option doc). Each shell tests its OWN interactive flag in its OWN
  # idiom, wrapped in a real conditional block (not a bare `&&`/`and` chain) so a multi-statement
  # command guards entirely, not just its first statement:
  #   fish  -- `status is-interactive`, fish's own builtin for exactly this.
  #   bash  -- `$-` is the flag-letters parameter every POSIX-family shell exposes; `i` is in it
  #            iff the shell is interactive. `[[ $- == *i* ]]` is bash's own idiomatic test of it.
  #   zsh   -- `[[ -o interactive ]]`, zsh's own extended test for a named shell option, preferred
  #            over pattern-matching `$-` because it asks the shell directly rather than inferring.
  # Proved able to fail AND pass, both directions, all three shells, before trusting any of it:
  # `<shell> -c '<guard-test>'` (no `-i`) prints nothing/false for all three -- this is also
  # exactly what `ssh host '<command>'` invokes, so it is the real failure mode, not a synthetic
  # one -- and `<shell> -i -c '<guard-test>'` (forced interactive) prints true for all three.
  greetingGuard = shell: command:
    if shell == "fish" then ''
      if status is-interactive
        ${command}
      end
    ''
    else if shell == "bash" then ''
      if [[ $- == *i* ]]; then
        ${command}
      fi
    ''
    else ''
      if [[ -o interactive ]]; then
        ${command}
      fi
    '';

  # fastfetch's own upstream default module list (`fastfetch --gen-config`, checked live against
  # 2.66.0 on this machine, not invented) -- which is ALSO exactly what CachyOS's own vendor
  # greeting has been rendering all along: `/usr/share/cachyos-fish-config/cachyos-config.fish`'s
  # `fish_greeting` hook invokes bare `fastfetch`, no `--config`, no flags, so this literal
  # upstream default IS "the Cachy config" -- there is no separate CachyOS-authored config.jsonc
  # anywhere on disk to copy instead (checked: no `cachyos-fastfetch*` package exists, and
  # `/etc/fastfetch`, `/etc/xdg/fastfetch` are both absent).
  #
  # AUDITED for anything host- or distro-specific before shipping it in a PUBLIC repo, not
  # assumed safe because it came from a real machine: no absolute paths, no hardcoded interface
  # or device name, no module that only resolves on Arch. Every module here (`localip`, `battery`,
  # `packages`, ...) computes its VALUE at runtime, unconditionally, on whichever host actually
  # runs it -- fastfetch's own logo selection auto-detects the distro from `/etc/os-release` too
  # (there is no `logo` key in this config at all), so the identical declaration renders a CachyOS
  # look on Arch and a NixOS look on NixOS with no per-platform branch needed here. `packages`
  # itself already breaks its count down by manager -- pacman, nixDefault, nixUser, nixSystem,
  # flatpak, whichever are actually present -- with zero extra config, so one declaration gives a
  # truthful readout on both halves of a mixed fleet already, not something this preset had to add.
  fastfetchPresetConfig = {
    "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json";
    modules = [
      "title"
      "separator"
      "os"
      "host"
      "kernel"
      "uptime"
      "packages"
      "shell"
      "display"
      "de"
      "wm"
      "wmtheme"
      "theme"
      "icons"
      "font"
      "cursor"
      "terminal"
      "terminalfont"
      "cpu"
      "gpu"
      "memory"
      "swap"
      "disk"
      "localip"
      "battery"
      "poweradapter"
      "locale"
      "break"
      "colors"
    ];
  };
in
{
  options.nixsh = {
    fish = mkShell "fish" // {
      # The one piece of fish state home-manager genuinely cannot own, because fish writes it
      # itself at runtime into fish_variables. Declaring it here makes it reproducible instead
      # of a file nobody remembers creating.
      universalVariables = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "fish universal variables (`set -U`). Applied idempotently at shell startup, since fish owns fish_variables itself and home-manager cannot write it.";
      };
    };
    bash = mkShell "bash";
    zsh = mkShell "zsh";

    # greeting: ONE declaration, all three shells, both backends -- a GENERIC "run something once
    # per interactive shell" mechanism, not a fastfetch option that happens to be named something
    # else. nixsh has no opinion on WHICH tool a consumer runs here (fastfetch, macchina, a
    # one-liner, nothing) -- that choice, and any config content the chosen tool reads, is a
    # per-consumer VALUE, same split as `terminal` above: the CONCEPT of a guarded greeting is
    # generic and every consumer wants it: WHICH command is not, and belongs to whoever composes
    # this module. `greetingPresets` below is the one deliberate exception -- see its own doc.
    #
    # `greetingPresets` is a SIBLING of `greeting`, not nested under it (`greeting.presets.*`, the
    # first shape this shipped with) -- deliberately, not a style choice: a consumer's whole point
    # is writing `nixsh.greeting = config.nixsh.greetingPresets.fastfetch;`, assigning the ENTIRE
    # `greeting` attrset in one go. Nesting the preset under `greeting` itself made that exact
    # assignment read its own target while defining it -- resolving `nixsh.greeting` requires
    # resolving `nixsh.greeting.presets.fastfetch` first, which is only reachable THROUGH
    # `nixsh.greeting` -- a real infinite recursion, not a style objection, hit live wiring this
    # into a real consumer's home-manager entry-point (`error: infinite recursion encountered`,
    # `modules.nix:880`, `nixsh.greeting.presets.fastfetch` named directly in the trace). Moving
    # the preset to a sibling option breaks the cycle: reading `greetingPresets` never has to pass
    # through `greeting` to get there.
    greeting = {
      command = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "fastfetch";
        description = ''
          Command run once per interactive shell (fish, bash and zsh alike), guarded so a
          non-interactive/scripted invocation -- SSH command mode
          (`ssh host '<command>'`, which execs the login shell with `-c`, no `-i` -- the shape an
          operator's own automation actually uses against a live host) or any other `<shell> -c
          "..."` -- never sees it. Empty string, the default, disables the greeting outright: no
          conditional block is rendered at all, not even an inert one.

          Generic on purpose. This is not a fastfetch option -- see `greetingPresets` for a
          ready-made value if that is what you want, or name anything else entirely.
        '';
      };

      configFile = {
        path = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "fastfetch/config.jsonc";
          description = ''
            Relative path for a single config file the greeting command reads, if it has one --
            rooted at each backend's own XDG config directory (`~/.config/<path>` on the
            home-manager backend, `/etc/xdg/<path>` on the NixOS backend, so the identical
            relative path resolves correctly on both). null, the default, writes no file -- for
            a command that needs none.
          '';
        };

        text = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            The file's literal content, verbatim. Generic on purpose -- nixsh does not parse,
            validate or otherwise know what format this is; a consumer who wants JSON renders it
            themselves (`builtins.toJSON { ... }`) before assigning it here, exactly as
            `greetingPresets.fastfetch` does for its own value.
          '';
        };
      };
    };

    greetingPresets.fastfetch = lib.mkOption {
      readOnly = true;
      type = lib.types.attrs;
      default = {
        command = "fastfetch";
        configFile = {
          path = "fastfetch/config.jsonc";
          text = builtins.toJSON fastfetchPresetConfig;
        };
      };
      description = ''
        A ready-made fastfetch preset, in `greeting`'s own shape -- based on fastfetch's own
        upstream default config -- see `fastfetchPresetConfig`'s own header comment in this
        module for the full account of what it contains and why it is safe to ship in a public
        repo (config only selects which MODULES render; every actual value is produced at
        runtime on whoever's screen it prints to, never stored here).

        Reference it wholesale (`nixsh.greeting = config.nixsh.greetingPresets.fastfetch;`),
        tweak it (`config.nixsh.greetingPresets.fastfetch // { configFile.text =
        builtins.toJSON (fastfetchAttrs // { modules = [ ... ]; }); }`), or ignore it entirely
        and set `nixsh.greeting` to something else -- `nixsh.greeting.command` still defaults to
        `""` (disabled) regardless of this preset existing; shipping a default value here is not
        the same as turning the greeting on.

        NOT nested under `greeting` itself (`greeting.presets.fastfetch`) -- see `greeting`'s own
        header comment for why that shape is a real infinite recursion, not merely untidy.
      '';
    };

    # ── THE UNDERLAY ──────────────────────────────────────────────────────────────────────────
    #
    # ONE MECHANISM, NAMED ONCE: a tool takes the DISTRO's own config as a base layer, and
    # everything nixsh declares sits on top of it and wins. The distro keeps improving its base;
    # every difference from it stays a deliberate, visible line in a Nix file.
    #
    # WHY THIS HAS TO EXIST AT ALL. The same layering already works natively, with no help from
    # anyone, for `sysctl.d`, `udev/rules.d`, `modprobe.d` and systemd drop-ins: the vendor's file
    # goes in /usr/lib, yours goes in /etc, and yours wins by rule. Shell and editor config has no
    # such rule. A distro ships its base through `/etc/skel`, which is a ONE-SHOT COPY performed
    # at account creation and never again -- not a layer at all. An account created before the
    # package existed never gets it; an account created after gets a frozen copy that no upgrade
    # ever touches; and neither one has any relationship to the file the package actually
    # maintains. This option is the missing layer.
    #
    # TWO WAYS TO LAND A BASE, because tools differ and pretending otherwise would render one of
    # them badly (the same reason this module shares the ENVIRONMENT layer across shells but
    # deliberately does not share aliases):
    #
    #   layer = "shell"  The base is a SCRIPT and the tool is a shell, so the base is `source`d --
    #                    at runtime, first, before anything nixsh writes. Redefinition is the
    #                    winning rule in every shell there is: the last `alias`/`function`/`set`
    #                    for a name is the one that survives, so "ours last" IS "ours wins".
    #   layer = "files"  The base is a DIRECTORY of files for a tool with no include mechanism and
    #                    no source order to exploit. Its children are linked into the tool's own
    #                    config directory, and every name nixsh itself declares is refused from the
    #                    base -- so the merge happens per FILE, and ours is simply the file that
    #                    gets written.
    #
    # NOTHING HERE IS READ AT EVALUATION TIME. `path` is a plain string naming a live system path
    # (`/usr/share/...`, `/etc/skel/...`) that no `builtins.readFile`/`pathExists` ever touches --
    # see `underlayBlock`'s own comment in this module for the full argument, and modules/home.nix
    # for the `files` half. A base is a distro artifact, not a Nix input; asking Nix about it would
    # bake in an answer from the wrong machine at the wrong time.
    #
    # RENDERED BY THE HOME-MANAGER BACKEND ONLY, the same boundary `nixsh.tools.shellHooks`
    # already draws and for the same reason -- it is the one backend that reliably writes shell rc
    # content and owns paths under a real `$HOME`. modules/nixos.nix warns rather than silently
    # doing nothing if a NixOS host declares one.
    underlay = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether this underlay entry applies. Defaults to true: declaring an entry at all is the decision, and a consumer that wants one temporarily out of the way should be able to say so without deleting the declaration (and losing the comment that explains it).";
          };

          path = lib.mkOption {
            type = lib.types.str;
            example = "/usr/share/cachyos-fish-config/cachyos-config.fish";
            description = ''
              Absolute path to the distro's own base, on the TARGET machine. A file for
              `layer = "shell"`, a directory for `layer = "files"`.

              Never read by Nix. Tested at runtime, every time, by whatever actually consumes it --
              so a host where the providing package is absent, removed later, or never existed
              degrades to "no base layer" and keeps everything nixsh declares.
            '';
          };

          layer = lib.mkOption {
            type = lib.types.enum [ "shell" "files" ];
            description = "How the base lands: `shell` sources a script before nixsh's own rc content, `files` links a directory's children into a config directory. See this option's own header for the full account of both.";
          };

          package = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "cachyos-fish-config";
            description = ''
              The pacman package that PROVIDES `path`, surfaced through `underlayPackages` for the
              host's own reconciler. Optional, and null by default, because a base can also come
              from a package the host already installs for another reason entirely.

              Declaring it is what turns "we depend on a distro file" into something a machine can
              actually reproduce -- the alternative is a `path` that happens to exist on the boxes
              it was written on and silently does not on the next one. nixsh installs nothing
              itself here, on any platform: same split it already states for the shells themselves
              (nix owns config, the system owns the binary), so this is a NAME published for
              `nixarch.packages.pacman`, not an installation.
            '';
          };

          shell = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum (lib.attrNames catalogue));
            default = null;
            description = "`layer = \"shell\"` only: which shell sources this base. Required there, and meaningless (asserted against) otherwise.";
          };

          before = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = ''
              `layer = "shell"` only: literal shell run immediately BEFORE the base is sourced,
              in the same file.

              This is not a general escape hatch -- `interactiveInit` already is one, and it lands
              AFTER the base, which is where content belongs by default. `before` exists for the
              narrow case where the BASE ITSELF reads something at load time and would otherwise
              read it wrong: a bundled plugin that probes for a helper binary while it is being
              sourced, for instance, has already decided whether to enable itself by the time
              anything after the source line runs. Content that merely needs to WIN goes after;
              content the base must SEE goes here.
            '';
          };

          into = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "micro";
            description = "`layer = \"files\"` only: the tool's config directory, relative to the XDG config home, that the base's children are linked into. Required there, and meaningless (asserted against) otherwise.";
          };

          ours = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "settings.json" ];
            description = ''
              `layer = "files"` only: names inside `into` that NIXSH's consumer declares itself
              (through `xdg.configFile`, typically). They are never taken from the base, however
              the base's own copy is named.

              This is the merge direction, written down. Everything not listed here comes from the
              distro and tracks it; everything listed here is ours and the base does not get a
              vote. The linker additionally refuses to replace ANY occupied name it did not create
              itself, so a forgotten entry here fails by leaving the declared file alone rather
              than by clobbering it -- but it is still declared, because the pruning half needs to
              know a name became ours, and because the reader of a host's config deserves to see
              which files are the deliberate overrides.
            '';
          };
        };
      });
      description = ''
        Distro-provided base layers, one entry per tool, keyed by any name you like (the key is
        used in generated comments and activation output, so make it the tool's name).

        See this option's own header comment in `modules/nixsh.nix` for the design; the short
        version is: the distro's config goes UNDERNEATH, everything nixsh declares goes on top and
        wins, and nothing is read from an impure path at evaluation time.

        `underlayPresets` carries a ready-made value for CachyOS.
      '';
    };

    # A SIBLING of `underlay`, never nested inside it -- the identical, non-negotiable shape
    # `greetingPresets` already has, for the identical reason: a consumer's whole point is writing
    # `nixsh.underlay = config.nixsh.underlayPresets.cachyos;`, and a preset reachable only THROUGH
    # `nixsh.underlay` would make that assignment read its own target while defining it. That is a
    # real `error: infinite recursion encountered`, hit live once already on `greeting.presets.*`,
    # not a matter of taste. See `greeting`'s own header comment for the full account.
    underlayPresets.cachyos = lib.mkOption {
      readOnly = true;
      type = lib.types.attrs;
      default = {
        fish = {
          layer = "shell";
          shell = "fish";
          path = "/usr/share/cachyos-fish-config/cachyos-config.fish";
          package = "cachyos-fish-config";
        };
        zsh = {
          layer = "shell";
          shell = "zsh";
          path = "/usr/share/cachyos-zsh-config/cachyos-config.zsh";
          package = "cachyos-zsh-config";
        };
        micro = {
          layer = "files";
          into = "micro";
          path = "/etc/skel/.config/micro";
          package = "cachyos-micro-settings";
          ours = [ "settings.json" ];
        };
      };
      description = ''
        A ready-made underlay for CachyOS: fish's and zsh's vendor configs, and micro's
        colorschemes and syntax definitions. Public knowledge about a public distro, in
        `underlay`'s own shape -- reference it wholesale
        (`nixsh.underlay = config.nixsh.underlayPresets.cachyos;`) and then add per-host detail as
        ordinary further definitions of the same option
        (`nixsh.underlay.fish.before = "...";`), which the module system merges per key.

        THE micro ENTRY READS FROM `/etc/skel`, AND THAT IS A MISUSE OF `/etc/skel`. Said plainly
        rather than hidden behind the option: `/etc/skel` is a TEMPLATE directory, whose contract
        is "copy me into a new account once", and reading a live config out of it treats it as
        something it does not claim to be. It is done anyway because the alternative is worse --
        `cachyos-micro-settings` installs its colorschemes and syntax files ONLY under `/etc/skel`
        and ships no `/usr/share` copy at all, so the choice is not between a clean source and a
        dirty one, it is between this and no upstream layer for micro. The risk it carries is
        specific and bounded: `/etc/skel` may gain files intended purely as new-account templates
        that nobody wants layered into a live config, which is exactly what `ours` and the
        linker's refusal to replace an occupied name are there to contain. If upstream ever moves
        these files to `/usr/share`, this preset's `path` changes and nothing else does.

        Nothing here is CachyOS-only in MECHANISM: `underlay` takes any path from any distro. This
        is a value, shipped because it is a correct one for a whole family of hosts, in the same
        spirit as `greetingPresets.fastfetch`.
      '';
    };

    environment = {
      variables = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Environment variables, rendered into every enabled shell's own export syntax. THE shared layer -- if a setting differs per shell, it does not belong here.";
      };
      path = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Directories prepended to PATH in every enabled shell.";
      };
    };

    loginShell = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (lib.attrNames catalogue));
      default = null;
      description = ''
        Which shell is the login shell. null leaves it alone.

        Recorded rather than enforced: changing a login shell is `chsh` against /etc/passwd, which
        is system state this module has no business rewriting from under a running session. What
        this gives you is the declared intent, and something to check drift against.
      '';
    };

    terminal = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "foot";
      description = ''
        The terminal emulator, as its executable name. null leaves `$TERMINAL` unset.

        Rendered into `$TERMINAL` for every enabled shell, so everything that spawns "a terminal"
        agrees without being told separately.

        This is deliberately the DECLARATION, not an installer -- same stance as `loginShell` and
        the same stance nixsh takes on shells themselves: nix owns the config, the system owns the
        binary. A desktop or compositor module should READ this to decide what to install and what
        to bind, rather than carrying its own terminal option. The choice is one fact about a
        machine; every consumer that restates it is a copy that can drift, and the failure mode is
        the quiet one -- a keybinding spawning a terminal the system never installed.
      '';
    };

    # ── Computed ──────────────────────────────────────────────────────────────────────────────
    archPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Enabled shells as pacman names, for the host's reconciler. The BINARIES -- config is written separately by the home-manager backend.";
    };

    rcFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "Generated rc content, keyed by home-relative path. The home-manager backend writes these; a consumer can inspect them without applying anything.";
    };

    greetingInvocations = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = ''
        The greeting command wrapped in each shell's own interactive guard (empty string if
        `greeting.command` is unset). Every backend applies this identically rather than
        re-deriving its own guess at the per-shell guard syntax -- see `greetingGuard`'s own
        comment in this module for the full account of each shell's idiom and how it was tested.
      '';
    };

    underlaySources = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = ''
        Every `layer = "shell"` underlay entry rendered into its shell's own guarded source block,
        keyed per shell exactly as `rcFiles`/`greetingInvocations` already are. Empty string for a
        shell with no entries.

        A backend puts this ABOVE everything `rcFiles` carries for the same shell -- that ordering
        is the entire promise of the mechanism, so it is computed here once rather than left to
        each backend to place correctly.
      '';
    };

    underlayFiles = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      readOnly = true;
      internal = true;
      description = ''
        The resolved `layer = "files"` entries, each carrying its own attribute key back out as
        `name`. Consumed by modules/home.nix's activation scripts -- the file layer has no textual
        representation to hand a backend the way `underlaySources` does, so what crosses this
        boundary is the entries themselves.
      '';
    };

    underlayPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        The `package` of every declared underlay entry that names one, as pacman names, for the
        host's own reconciler:

          nixarch.packages.pacman = config.nixsh.archPackages ++ config.nixsh.tools.archPackages
                                 ++ config.nixsh.underlayPackages;

        A THIRD list rather than a merge into either existing one, on purpose. `archPackages` is
        the shells' own binaries (which must be the SYSTEM's copy -- /etc/shells, login) and
        `tools.archPackages` is the CLI catalogue; these are neither. They are the packages whose
        only job is to put a config file on disk for something else to layer under, and a host
        reading its own package wiring should be able to see that third category rather than
        discover it by following a name back into a catalogue.

        NO DISTRO GATE HERE, deliberately. A name like `cachyos-fish-config` exists in CachyOS's
        own repositories and nowhere else -- not upstream Arch, not the AUR -- and an unresolvable
        name aborts the ENTIRE `pacman -S` transaction, taking every unrelated package with it. The
        gate that prevents that is the DECLARATION itself: an underlay entry names an absolute path
        that only exists on one distro, so a host declares one because it runs that distro. There
        is nothing generic to gate -- a plain Arch host has no reason to declare the entry in the
        first place, and gets an empty list. This is why the option carries no `distro` enum of its
        own to keep in step with the several that already exist elsewhere.
      '';
    };
  };

  config = {
    nixsh.archPackages = map (s: catalogue.${s}.arch) enabled;

    nixsh.greetingInvocations = lib.genAttrs (lib.attrNames catalogue)
      (s: lib.optionalString (cfg.greeting.command != "") (greetingGuard s cfg.greeting.command));

    nixsh.underlaySources = lib.genAttrs (lib.attrNames catalogue)
      (s: lib.concatStringsSep "\n\n"
        (map underlayBlock (lib.filter (u: u.shell == s) (underlayFor "shell"))));

    nixsh.underlayFiles = underlayFor "files";

    nixsh.underlayPackages =
      lib.unique (map (u: u.package) (lib.filter (u: u.package != null) underlayList));

    # Alias values are wrapped in SINGLE quotes, per-shell-escaped, never bare double quotes: a
    # value containing its own embedded `"` -- an SSH remote command is the common real case,
    # `ssh -t host "tmux new -A -s tmux@host"` -- used to render as `alias name="ssh -t host "tmux
    # ..."`, which both fish's `alias` builtin and POSIX `alias name=value` parse as several
    # separate words and reject outright ("Expected exactly one word"/similar). Double quotes are
    # also the wrong default even when they happen not to break syntactically: fish and POSIX
    # shells both interpolate `$variable` and command substitution inside `"..."`, so a value
    # containing a literal `$` would have been silently expanded at RENDER time (nixsh evaluating
    # the alias into rcFiles), not left alone the way a fixed alias value should be. Single quotes
    # close both holes at once -- found live migrating julian-corbet/infra's elitebook host off
    # `programs.fish.shellAliases` onto this option, where five of seven real aliases hit exactly
    # the first failure mode.
    nixsh.rcFiles = lib.listToAttrs (map
      (s: lib.nameValuePair catalogue.${s}.rcPath (lib.concatStringsSep "\n" (lib.filter (x: x != "") [
        "# Generated by nixsh. Do not edit."
        (envFor s)
        (lib.concatStringsSep "\n" (lib.mapAttrsToList
          (n: v:
            if s == "fish"
            then "alias ${n} ${escapeFishSingle v}" # fish's own two-word `alias NAME VALUE` form
            else "alias ${n}=${lib.escapeShellArg v}") # POSIX `alias NAME=VALUE`, one word, no space
          cfg.${s}.aliases))
        (lib.optionalString (s == "fish") (lib.concatStringsSep "\n"
          (lib.mapAttrsToList (n: v: "set -q ${n}; or set -U ${n} ${escapeFishSingle v}") cfg.fish.universalVariables)))
        cfg.${s}.interactiveInit
        cfg.greetingInvocations.${s}
      ])))
      enabled);
  };
}
