# experiments

Throwaway trials: spikes, one-off scripts, things tried and abandoned or not yet worth writing up.
Nothing here is guaranteed to work, be maintained, or survive the next cleanup pass — except the
three files below.

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

If something in here turns out to matter in a different way, distill the actual finding into
[`../studies/`](../studies/README.md) and let the experiment stay disposable (or delete it).

See the main [README](../README.md) for the project itself.
