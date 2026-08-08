# experiments

Throwaway trials: spikes, one-off scripts, things tried and abandoned or not yet worth writing up.
Nothing here is guaranteed to work, be maintained, or survive the next cleanup pass — except the
five files below.

`render-smoke-test.nix` is kept here deliberately rather than promoted into `checks/` (which is
`nix flake check`-wired): it exercises the pre-existing shell-rendering system
(`modules/nixsh.nix`/`modules/home.nix`) end to end and is run by hand, the way it always has been.

`validate-nixpkgs-names.nix` and `verify-package-names.sh` are the tool catalogue's own load-
bearing verification tools, kept here for the identical reason nixmedia keeps its own pair in the
same place rather than in `checks/`: `checks/` is pinned to one nixpkgs revision (this flake's own
`inputs.nixpkgs`), the opposite of what these two want — a CONSUMER's own pin is what actually
decides whether a catalogue name resolves for them.

- `render-smoke-test.nix` — renders all three shells from one `nixsh.nix` declaration and checks
  the shared environment layer really did come out in three different syntaxes.
- `validate-nixpkgs-names.nix` — force-evaluates every nixpkgs attribute in `../lib/tools.nix`
  against a real package set (not just `hasAttrByPath`, which misses a nixpkgs rename-to-throw —
  see the file's own header). Run by hand, against whatever nixpkgs revision you actually care
  about.
- `verify-package-names.sh` — the full verification (Arch official repos, the AUR, and the
  nixpkgs side above) in one script, reproducing exactly how `../lib/tools.nix` was checked
  before being committed.
- `underlay-ours-wins.sh` — runs a REAL fish and a REAL zsh, in isolated homes, to prove that a
  distro base sourced first loses every collision to nixsh's own content sourced after it, and to
  establish where fish actually places a numbered `conf.d` drop-in (which is not where fish's
  documentation implies — see `../studies/fish-conf-d-order-is-per-directory.md`).
- `underlay-files-merge.sh` — the `layer = "files"` half, which has no source order to lean on:
  transcribes the activation logic `../modules/home.nix` emits, runs it against a fixture through
  a full switch cycle, and reads the resulting directory back. Also drives micro itself through a
  pty to confirm it resolves a colorscheme through a symlinked directory, and that a missing one
  is a visible error rather than a quiet fallback.

The last two are kept here rather than promoted into `checks/` for the reason the whole file
split turns on: they need REAL shell and editor BINARIES on the machine running them, which a
`nix flake check` derivation has no business depending on. `../checks/underlay-eval.nix` covers
the half that is pure policy.

If something in here turns out to matter in a different way, distill the actual finding into
[`../studies/`](../studies/README.md) and let the experiment stay disposable (or delete it).

See the main [README](../README.md) for the project itself.
