# delta: the pacman package is `git-delta`, not `delta`

**Finding:** `pacman -Si delta` finds nothing. The syntax-highlighting git/diff pager everyone
calls "delta" (dandavison/delta) is packaged on Arch as `git-delta`. The bare name `delta` is not
free on Arch either — it resolves to a completely unrelated family of packages: `deltachat-rpc-
server` and its GNOME client, `xdelta3`, and `perl-test-number-delta`. None of those is the tool
this catalogue's `core.delta` entry means.

**Why this is worth a study rather than just a catalogue line:** getting an Arch package name
wrong does not fail loudly the way a stale nixpkgs mapping does (nixpkgs at least converts a
rename to a `throw`, caught by `tryEval` — see `nvtop-nixpkgs-attribute-is-nvtopPackages-full.md`
and `experiments/validate-nixpkgs-names.nix`'s own header for that class of bug). A wrong pacman
name just fails the whole transaction outright with "target not found" the moment it is actually
installed — a real host's converge breaks, not a `nix eval`. Confirming this ahead of time, rather
than discovering it against a live host, is the entire point of `experiments/verify-package-
names.sh`.

**Evidence:**

```
$ pacman -Si delta
error: package 'delta' was not found

$ pacman -Si git-delta
Repository      : cachyos-extra-v3
Name            : git-delta
Version         : 0.19.2-2.1
Description     : Syntax-highlighting pager for git and diff output

$ pacman -Ss delta
cachyos-extra-v3/deltachat-rpc-server ...   A JSON-RPC 2.0 interface to DeltaChat over standard I/O
cachyos-extra-v3/git-delta ... [installed]  Syntax-highlighting pager for git and diff output
cachyos-extra-v3/xdelta3 ...                A file format designed for highly efficient deltas ...
```

nixpkgs, by contrast, names the same tool `delta` with no ambiguity — confirmed by cross-checking
`meta.homepage` (`https://github.com/dandavison/delta`) against pacman's own `git-delta` `URL`
field (`https://dandavison.github.io/delta/`, the project's docs site, same author/project):

```
$ nix eval --impure --json --expr '(import (fetchTarball ".../1d4e0f865...tar.gz") {}).delta.meta.homepage'
"https://github.com/dandavison/delta"
```

**Decision this drove:** `lib/tools.nix`'s `core.delta` entry carries `arch = "git-delta"` and
`nixpkgs = "delta"` — a genuine platform divergence in the pacman name alone, with the catalogue
KEY (`delta`, what a consumer writes in `nixsh.tools.core`) and the nixpkgs attribute both staying
the tool's own common name. The entry's own inline note in `lib/tools.nix` states the divergence
directly so a future reader auditing "why does `archPackages` say `git-delta`" does not go looking
for a bug in the resolution logic instead.

**Method:** `pacman -Si`/`pacman -Ss` against a live CachyOS host for the Arch side; a force-
evaluating `nix eval --impure` against the nixpkgs revision infra's own `flake.lock` had pinned at
the time for the nixpkgs side and the homepage cross-check. Reproducible via
`../experiments/verify-package-names.sh`.
