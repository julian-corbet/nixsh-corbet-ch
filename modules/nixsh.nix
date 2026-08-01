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

  # fastfetch's own invocation, per shell -- the one place shell syntax genuinely differs for it.
  # fish's `conf.d`/NixOS's own generated config.fish both source their content UNCONDITIONALLY,
  # on every invocation of the shell, interactive or not (confirmed live: a bare `ssh host fish -c
  # ...` sources every conf.d file just like an interactive login does) -- so fish needs an
  # explicit interactive guard or a script invocation dumps a system banner into the stdout of
  # anything parsing it. bash's `.bashrc`/NixOS's `/etc/bashrc` and zsh's `.zshrc` do not have that
  # problem: both shells only read those files for an INTERACTIVE shell by their own native
  # behaviour (a non-interactive `bash -c`/`zsh -c` never sources them at all, confirmed against
  # both shells' own manuals), and NixOS's own `/etc/bashrc` template adds a second, explicit `[ -n
  # "$PS1" ]` guard around interactiveShellInit content on top of that -- so a bare invocation is
  # correct and sufficient for both, on every backend this module has.
  fastfetchInvocationFor = shell: if shell == "fish" then "status is-interactive; and fastfetch" else "fastfetch";
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

    # fastfetch: ONE declaration, all three shells, both backends -- unlike the shells
    # themselves, fastfetch's binary and its config are completely shell-agnostic (one JSONC
    # file, read by whichever shell happens to invoke the binary), so there is no per-shell
    # option surface to speak of here, only an enable flag and the config content. The per-shell
    # part that DOES differ (the invocation line, guarded or not) is computed once, internally
    # (`fastfetchInvocationFor` above), and applied identically by every backend below rather than
    # letting each backend re-derive its own guess at it.
    fastfetch = {
      enable = lib.mkEnableOption "a declarative fastfetch greeting on every enabled shell (config only -- installing the binary is still each backend's own job, same NIX OWNS CONFIG split as the shells)";

      config = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        example = { modules = [ "title" "os" "packages" ]; };
        description = ''
          fastfetch's own config, as a Nix attrset -- rendered with `builtins.toJSON`. Plain JSON
          is valid JSONC, which is what fastfetch actually reads
          (`~/.config/fastfetch/config.jsonc`, or `/etc/xdg/fastfetch/config.jsonc` on a backend
          with no per-user home directory to write into). See fastfetch's own
          `--list-modules`/`--list-config-paths` and the presets under
          `/usr/share/fastfetch/presets/` (or nixpkgs' `fastfetch` output) for the schema this
          feeds.
        '';
      };
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

    fastfetchConfigJSON = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "cfg.fastfetch.config rendered to JSON text. A backend writes this to config.jsonc; a consumer can inspect it without applying anything.";
    };

    fastfetchInvocations = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "The fastfetch invocation line for each shell in the catalogue, guarded where the shell's own composition point needs it. A NixOS-backend consumer with no rcFiles/conf.d mechanism of its own reads this directly.";
    };
  };

  config = {
    nixsh.archPackages = (map (s: catalogue.${s}.arch) enabled)
      ++ lib.optional cfg.fastfetch.enable "fastfetch";

    nixsh.fastfetchConfigJSON = builtins.toJSON cfg.fastfetch.config;

    nixsh.fastfetchInvocations = lib.genAttrs (lib.attrNames catalogue) fastfetchInvocationFor;

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
        (lib.optionalString cfg.fastfetch.enable cfg.fastfetchInvocations.${s})
      ])))
      enabled);
  };
}
