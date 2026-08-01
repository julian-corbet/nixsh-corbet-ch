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
    # into julian-corbet/infra's `home/richc/common.nix` (`error: infinite recursion encountered`,
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
  };

  config = {
    nixsh.archPackages = map (s: catalogue.${s}.arch) enabled;

    nixsh.greetingInvocations = lib.genAttrs (lib.attrNames catalogue)
      (s: lib.optionalString (cfg.greeting.command != "") (greetingGuard s cfg.greeting.command));

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
