# nixsh

**Every shell on every machine, declared — with the binary left to the system.**

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

| Backend | Installs | Writes config |
|---|---|---|
| `homeModules.nixsh` | no | yes |
| `nixosModules.nixsh` | yes (`environment.systemPackages` + `environment.shells`) | no |
| `systemManagerModules.nixsh` | no — publishes `nixsh.archPackages` for the host's reconciler | no |

## loginShell is recorded, not enforced

`nixsh.loginShell` states intent. It does not run `chsh`: the login shell lives in `/etc/passwd`,
which is system state no module should rewrite from under a running session. You get the declared
value and something to check drift against.

## Adoption

Same caution nixfish documented. `~/.bashrc` and `~/.config/fish/config.fish` are almost never
empty — a vendor package may own them, or you may have edited them for years. Back up before first
activation (`home-manager switch -b backup`), as a one-time flag rather than a permanent option.

## License

MIT.
