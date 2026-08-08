# home-manager backend — composes with whatever already writes the rc files, and installs nothing.
#
# TWO PROBLEMS THIS AVOIDS.
#
# 1. Clobbering. Writing ~/.config/fish/config.fish wholesale fights home-manager's own
#    `programs.fish`, which a host may already use for its own interactiveShellInit (a per-tty
#    session launcher, for instance). Two writers, one file. So fish gets a conf.d DROP-IN, which
#    is fish's native composition point and loads alongside anything else, and bash/zsh feed
#    `initExtra`, which home-manager concatenates rather than replaces.
#
# 2. A second shell binary. home-manager's `programs.fish.enable` installs pkgs.fish. On NixOS that
#    is right; on a foreign distro it lands ahead of /usr/bin/fish on PATH, so the login shell and
#    the interactive shell become different builds. This backend therefore never sets
#    `programs.*.enable` -- the host decides, and on Arch the binary stays pacman's.
#
# THE SAME REASONING EXTENDS TO `nixsh.tools` (modules/tools.nix), not just the three shells: this
# backend renders the selected `integrate` tools' shell HOOKS (`shellHooks`, below) and nothing
# else about the tool catalogue -- it never adds any of `nixsh.tools.selected` to `home.packages`.
# Doing so on Arch would be the identical second-binary trap one layer up (a home-manager `bat`
# ahead of pacman's own on PATH), for tools that have even less reason to need it than a login
# shell does: nothing else on the box links against `ripgrep` the way login itself execs
# `/etc/shells`' own shell. Installing is `nixsh.tools.archPackages`/`.aurPackages`
# (modules/arch.nix, the host's own reconciler) on Arch and `environment.systemPackages`
# (modules/nixos.nix) on NixOS -- this backend's whole job stays config, on both surfaces alike.
#
# THE UNDERLAY IS THIS BACKEND'S TOO (`nixsh.underlay`, declared in modules/nixsh.nix), and it is
# the one place the "compose, never clobber" stance above stops being enough on its own. Composing
# says our content coexists with everyone else's. The underlay says something stronger: the
# DISTRO's own config goes underneath ours, on purpose, and ours wins where they disagree. Both
# halves of that are placement decisions, and they are made here:
#
#   fish    Two conf.d files, not one. `00-nixsh-underlay.fish` sources the distro's base;
#           `50-nixsh.fish` is everything nixsh declares. See the fish branch below for why the
#           numbering had to INVERT from what this backend originally shipped.
#   bash    One rc file each, with the underlay's source block at the TOP -- these shells have no
#   zsh     conf.d convention to express the layering structurally, so it is expressed positionally
#           instead. Same guarantee, weaker mechanism, and the asymmetry is the tools', not a
#           choice made here.
#   files   Two activation-script steps around home-manager's own file linking. See the `files`
#           branch below.
{ config, lib, ... }:
let
  cfg = config.nixsh;

  # `body` now appends `nixsh.tools.shellHooks` (modules/tools.nix) after nixsh's own rendered rc
  # content -- ONE call site, so every backend write (fish's conf.d drop-in, bash/zsh's initExtra
  # or owned rc file below) picks up a selected `nixsh.tools.integrate` tool's init hook without a
  # second edit per branch. See modules/tools.nix's own `shellHooks` option doc for why this
  # backend specifically -- not modules/nixos.nix -- is the one that renders it.
  body = shell:
    let
      rc = cfg.rcFiles.${(import ../lib/shells.nix { }).${shell}.rcPath} or "";
      hook = cfg.tools.shellHooks.${shell} or "";
    in
    lib.concatStringsSep "\n" (lib.filter (x: x != "") [ rc hook ]);

  # bash/zsh only: the underlay's source block, then everything nixsh declares. fish deliberately
  # does NOT go through this -- it gets a separate, lower-numbered conf.d file instead, which is
  # strictly better where the tool offers it (see the fish branch below).
  layered = shell:
    lib.concatStringsSep "\n" (lib.filter (x: x != "") [ cfg.underlaySources.${shell} (body shell) ]);

  underlayFiles = cfg.underlayFiles;

  # ── The `files` layer, as two activation steps ───────────────────────────────────────────────
  #
  # Two, not one, and the split is forced by home-manager's own activation order rather than
  # chosen. `checkLinkTargets` runs before anything is written and ABORTS the whole switch if a
  # path home-manager is about to write is occupied by a symlink that does not point into a
  # home-manager generation -- ours point into the distro's base, so they are exactly that. The
  # moment a name moves from "supplied by the base" to `ours`, the link we created on the previous
  # switch is sitting in the way of the file this switch wants to write. Pruning has to happen
  # before that check; linking has to happen after the files exist. Hence a pair.
  #
  # PRUNING IS SURGICAL, NOT A CLEAN SWEEP. The obvious implementation -- remove every link we
  # own, then recreate them -- leaves the tool with no colorschemes and no syntax files for the
  # duration of a switch, and permanently if activation fails in between. Measured, not
  # hypothetical: micro does not quietly fall back when its configured colorscheme is missing, it
  # stops to print "<name> is not a valid colorscheme / Press enter to continue" on every launch
  # (see experiments/underlay-files-merge.sh). So the prune step removes a link only when it has
  # actually gone wrong -- the name became `ours`, or the base no longer has that child -- and the
  # steady state has no window at all.
  #
  # NOTHING IS READ FROM THE BASE AT EVAL TIME here either: these are shell loops over a path
  # string, run on the target machine at switch time. Nix never learns what is in the directory,
  # which is the point -- it does not have to be told again when the distro adds a file.
  underlayFilesScript = phase: lib.concatMapStringsSep "\n"
    (u: ''
      # ── nixsh underlay "${u.name}" (${phase}) ──
      _nixsh_base=${lib.escapeShellArg u.path}
      _nixsh_into="''${XDG_CONFIG_HOME:-$HOME/.config}"/${lib.escapeShellArg u.into}
      _nixsh_ours=" ${lib.concatStringsSep " " u.ours} "

      ${if phase == "prune" then ''
      # Remove links this mechanism created that must not survive into the new generation: a name
      # the consumer now declares itself, or a child the base no longer has. Identified by where
      # the link POINTS, never by name -- anything under `into` that is not a symlink into this
      # entry's own base belongs to somebody else and is left untouched.
      if [ -d "$_nixsh_into" ]; then
        find "$_nixsh_into" -mindepth 1 -maxdepth 1 -type l -printf '%f\n' | while IFS= read -r _n; do
          case "$(readlink -- "$_nixsh_into/$_n")" in
            "$_nixsh_base"/*) ;;
            *) continue ;;
          esac
          case "$_nixsh_ours" in *" $_n "*) ''${DRY_RUN_CMD:-} rm -f ''${VERBOSE_ARG:-} -- "$_nixsh_into/$_n"; continue ;; esac
          [ -e "$_nixsh_base/$_n" ] || ''${DRY_RUN_CMD:-} rm -f ''${VERBOSE_ARG:-} -- "$_nixsh_into/$_n"
        done
      fi
      '' else ''
      # Link every child of the base that is not ours and not already occupied by something we did
      # not create. The occupancy test is what makes "ours wins" STRUCTURAL rather than merely
      # declared: a file the consumer writes through xdg.configFile is already there by now (this
      # step runs after home-manager's own linking), it is not a link into the base, so it is
      # skipped -- even if `ours` forgot to name it.
      if [ -d "$_nixsh_base" ] && [ -r "$_nixsh_base" ]; then
        ''${DRY_RUN_CMD:-} mkdir -p ''${VERBOSE_ARG:-} -- "$_nixsh_into"
        find "$_nixsh_base" -mindepth 1 -maxdepth 1 -printf '%f\n' | while IFS= read -r _n; do
          case "$_nixsh_ours" in *" $_n "*) continue ;; esac
          if [ -e "$_nixsh_into/$_n" ] || [ -L "$_nixsh_into/$_n" ]; then
            case "$(readlink -- "$_nixsh_into/$_n" 2>/dev/null || true)" in
              "$_nixsh_base"/*) ;;
              *) continue ;;
            esac
          fi
          ''${DRY_RUN_CMD:-} ln -sfn ''${VERBOSE_ARG:-} -- "$_nixsh_base/$_n" "$_nixsh_into/$_n"
        done
      fi
      ''}
      unset _nixsh_base _nixsh_into _nixsh_ours
    '')
    underlayFiles;

  # Cross-field validation. An entry carrying a field its own `layer` never reads is not a
  # harmless extra -- it is content a reader believes is live and that renders to nothing, the
  # exact silent class this backend's `fishProgramsOrphaned` assertion below already exists for.
  underlayProblems = lib.concatMap
    (u:
      let at = "nixsh.underlay.\"${u.name}\""; in
      lib.optional (!lib.hasPrefix "/" u.path)
        "${at}.path is \"${u.path}\", which is not absolute. The underlay names a path on the TARGET machine's filesystem, resolved at runtime; a relative path would be resolved against whatever directory a shell or an activation script happened to be in."
      ++ lib.optional (u.layer == "shell" && u.shell == null)
        "${at}.layer is \"shell\" but ${at}.shell is null. Name the shell that should source this base."
      ++ lib.optional (u.layer == "shell" && (u.into != null || u.ours != [ ]))
        "${at}.layer is \"shell\", so ${at}.into/.ours are never read. They belong to the \"files\" layer; leaving them set here reads as configuration and is not."
      ++ lib.optional (u.layer == "files" && u.into == null)
        "${at}.layer is \"files\" but ${at}.into is null. Name the config directory (relative to the XDG config home) the base's children should be linked into."
      ++ lib.optional (u.layer == "files" && (u.shell != null || u.before != ""))
        "${at}.layer is \"files\", so ${at}.shell/.before are never read. They belong to the \"shell\" layer; leaving them set here reads as configuration and is not."
      ++ lib.optional (u.layer == "shell" && u.shell != null && !cfg.${u.shell}.enable)
        "${at} declares a base for ${u.shell}, but nixsh.${u.shell}.enable is false, so nixsh writes no rc content for that shell at all and the base would never be sourced."
    )
    (lib.mapAttrsToList (n: u: u // { name = n; }) (lib.filterAttrs (_: u: u.enable) cfg.underlay));

  # THE TRAP: a consumer moves a host onto `nixsh.fish.enable = true`, but leaves earlier
  # `programs.fish.{shellInit,interactiveShellInit,shellAliases,functions}` content in place from
  # before the move -- easy to do, since this backend deliberately COMPOSES with whatever a host
  # already has rather than forcing a rewrite (this file's own header, "Clobbering"). That leftover
  # content renders NOTHING: home-manager's own fish module gates its ENTIRE config block --
  # config.fish itself included -- behind `programs.fish.enable`, and this backend deliberately
  # never sets that option (this file's own header, "A second shell binary": setting it would
  # install a second fish ahead of the system's on PATH). So the exact combination below is
  # SILENT: no eval error, no output difference, a value that looks live in the source and
  # renders to nothing at all.
  #
  # Measured live, not hypothetical: a real consumer host carried this exact combination for five
  # days (2026-07-27 to 2026-08-01) after a migration onto `nixsh.fish` left the old
  # `programs.fish.*` block sitting there unconverted -- unnoticed until the next `home-manager
  # switch` on that host finally applied it and quietly dropped a working shell config (aliases,
  # functions, a per-tty session launcher, and a greeting sourced transitively through it) with no
  # error at any point.
  fishProgramsOrphaned =
    cfg.fish.enable
    && !config.programs.fish.enable
    && (config.programs.fish.shellInit != ""
        || config.programs.fish.interactiveShellInit != ""
        || config.programs.fish.shellAliases != { }
        || config.programs.fish.functions != { });
in
{
  imports = [ ./nixsh.nix ./tools.nix ];

  config = lib.mkMerge [
    # An ASSERTION, not `lib.warn`: the bash/zsh half of this same class of trap (nixsh's own
    # config rendering to nothing under a different combination of options) already went through
    # a soft-warning attempt before this backend's bash/zsh branches below were fixed to compose
    # correctly regardless -- the warning fired on every single switch and nobody caught it. A
    # failed build cannot be scrolled past the same way.
    {
      assertions = [
        {
          assertion = !fishProgramsOrphaned;
          message = ''
            nixsh.fish.enable is true, but programs.fish.{shellInit,interactiveShellInit,shellAliases,functions}
            also has content while programs.fish.enable is not true. That content will never render:
            home-manager's own fish module (and everything it implies, including ~/.config/fish/config.fish
            itself) is gated entirely behind programs.fish.enable, and nixsh's home-manager backend
            deliberately never sets it -- see modules/home.nix's own header for why.

            Either move this content into nixsh.fish.interactiveInit / nixsh.fish.aliases (nixsh's own escape
            hatch for content outside its typed primitives), or set programs.fish.enable = true yourself if you
            actually want home-manager's own fish module active alongside nixsh (accepting a second fish binary
            ahead of the system's on PATH -- see this backend's own header for why nixsh itself never does this).
          '';
        }
      ] ++ map (message: { assertion = false; inherit message; }) underlayProblems;
    }
    # fish: numbered conf.d drop-ins, TWO of them, and the numbering is the whole point.
    #
    # THE INVERSION. This backend originally shipped exactly one file, `00-nixsh.fish`, numbered
    # `00-` on the reasoning that nixsh should land before anything a host adds itself. Under the
    # underlay that reasoning is exactly backwards: a base layer added at any higher number would
    # be sourced AFTER nixsh and would therefore OVERRIDE it -- the precise opposite of what the
    # mechanism promises. There is no number below `00-` to give the base, so nixsh's own file
    # moves up and the base takes the bottom. Renaming a generated file is safe here: home-manager
    # removes the previous generation's links before creating the new one's, so no orphaned
    # `00-nixsh.fish` survives the switch that introduces this.
    #
    # THE CONVENTION THIS ESTABLISHES, so a consumer has somewhere to put its own content without
    # guessing: `00-` is the underlay, `50-` is nixsh, and the two gaps mean something --
    # `01-`..`49-` is "below nixsh, above the distro" and `51-`.. is "above nixsh". A file with no
    # numeric prefix at all sorts after every numbered one (digits precede letters), so an
    # unprefixed drop-in from a sibling module lands last and wins over everything here, which is
    # the right default for a module that deliberately overrides a builtin.
    #
    # WHAT THE NUMBERING DOES *NOT* REACH, proved rather than assumed (experiments/
    # underlay-ours-wins.sh, and studies/fish-conf-d-order-is-per-directory.md for the finding):
    # fish does not sort conf.d files globally by name. Its own config.fish iterates
    # `$__fish_config_dir/conf.d/*.fish $__fish_sysconf_dir/conf.d/*.fish $__fish_vendor_confdirs/*.fish`
    # -- DIRECTORY order first, filename order only within each directory -- deduplicating by
    # basename so the first directory wins a name collision. So these numbers order things inside
    # `~/.config/fish/conf.d` and nowhere else, which is all this mechanism needs (both files live
    # there), but it also means `/etc/fish/conf.d` and every vendor conf.d directory are sourced
    # AFTER both of them regardless of what they are called. Those are not the layer this option
    # is about, and no numbering available here could reach them.
    (lib.mkIf (cfg.fish.enable && cfg.underlaySources.fish != "") {
      xdg.configFile."fish/conf.d/00-nixsh-underlay.fish".text = ''
        # Generated by nixsh (nixsh.underlay). Do not edit.
        #
        # Sourced FIRST, before 50-nixsh.fish, so everything nixsh declares lands on top of this
        # and wins. Every block below is guarded on the base still being readable at runtime.
        ${cfg.underlaySources.fish}
      '';
    })

    (lib.mkIf cfg.fish.enable {
      xdg.configFile."fish/conf.d/50-nixsh.fish".text = body "fish";
    })

    # The `files` layer. Both steps are declared together or not at all -- pruning without linking
    # would strip a config directory and leave it stripped.
    (lib.mkIf (underlayFiles != [ ]) {
      home.activation.nixshUnderlayPrune =
        lib.hm.dag.entryBefore [ "checkLinkTargets" ] (underlayFilesScript "prune");
      home.activation.nixshUnderlayLink =
        lib.hm.dag.entryAfter [ "linkGeneration" ] (underlayFilesScript "link");
    })

    # The greeting's own config file, if it declared one -- independent of which shells are
    # enabled, since the file is read by whatever BINARY `greeting.command` names, not sourced by
    # a shell. `~/.config/<path>` is the home-manager half of the XDG-relative shape
    # `greeting.configFile.path`'s own option doc promises (the NixOS backend writes the same
    # relative path under `/etc/xdg/` instead) -- for fastfetch specifically this lands on its own
    # first-listed config path (`fastfetch --list-config-paths`), so no `--config` flag is needed
    # at any of the per-shell call sites `greetingInvocations` feeds, but nixsh does not know or
    # care that the command happens to be fastfetch here.
    (lib.mkIf (cfg.greeting.configFile.path != null) {
      xdg.configFile.${cfg.greeting.configFile.path}.text = cfg.greeting.configFile.text;
    })

    # bash/zsh have no conf.d convention, so there are two routes and the host's own choice picks
    # which one applies. This used to be a catch-22: `initExtra` is only sourced when
    # programs.<shell>.enable is on, but turning that on installs the shell from nixpkgs -- the
    # exact second-binary problem note 2 above exists to avoid. So the config rendered into nothing
    # and a warning fired, which is a diagnosis, not a fix.
    #
    #   programs.<shell>.enable = true  -> COMPOSE via initExtra, as before. The host has accepted
    #                                      home-manager's shell (and its binary); don't fight it.
    #   programs.<shell>.enable = false -> OWN the rc file via home.file. Nothing else is writing
    #                                      it in that case, so there is no clobbering risk, and the
    #                                      config applies with no package pulled in.
    #
    # Net effect on a foreign distro: declared shell config actually applies, and the shell binary
    # still comes from the system. Both, rather than a choice between them.
    #
    # `layered` rather than `body` on both branches: bash and zsh have no conf.d, so the underlay's
    # source block goes at the top of whichever of the two routes below applies. In the `initExtra`
    # route that means the base is sourced at the start of home-manager's own appended block --
    # after home-manager's earlier sections but before every line nixsh contributes, which is the
    # guarantee this mechanism actually makes. In the owned-file route it is the first thing in the
    # file, full stop.
    (lib.mkIf cfg.bash.enable (lib.mkMerge [
      (lib.mkIf config.programs.bash.enable { programs.bash.initExtra = layered "bash"; })
      (lib.mkIf (!config.programs.bash.enable) {
        home.file.".bashrc".text = ''
          # Managed by nixsh (home-manager backend). programs.bash.enable is false on this host, so
          # nixsh owns this file outright rather than appending to home-manager's own.
          ${layered "bash"}
        '';
      })
    ]))

    (lib.mkIf cfg.zsh.enable (lib.mkMerge [
      (lib.mkIf config.programs.zsh.enable { programs.zsh.initExtra = layered "zsh"; })
      (lib.mkIf (!config.programs.zsh.enable) {
        home.file.".zshrc".text = ''
          # Managed by nixsh (home-manager backend). programs.zsh.enable is false on this host, so
          # nixsh owns this file outright rather than appending to home-manager's own.
          ${layered "zsh"}
        '';
      })
    ]))
  ];
}
