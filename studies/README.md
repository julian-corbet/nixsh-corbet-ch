# studies

Written-up findings: things that were tried in [`../experiments/`](../experiments/README.md),
worked (or failed instructively), and are worth recording properly — with the reasoning, not just
the result.

A study earns its place here once it changed a decision in the main project. See the main
[README](../README.md) for the project itself.

| File | Finding |
|---|---|
| `delta-pacman-name-is-git-delta.md` | The pacman package for the `delta` git/diff pager is named `git-delta`; the bare name `delta` belongs to an unrelated Arch package family (deltachat-rpc-server, xdelta3, etc). Decided `lib/tools.nix`'s `core.delta` entry to carry `arch = "git-delta"` while keeping the catalogue key and the nixpkgs attribute both `delta`. |
| `nvtop-nixpkgs-attribute-is-nvtopPackages-full.md` | nixpkgs has no top-level `nvtop` attribute at all — it lives under `nvtopPackages.full` (pname `nvtop`). Decided `lib/tools.nix`'s `system.nvtop` entry to carry `nixpkgs = "nvtopPackages.full"`, a dotted path, rather than a plain name. |
| `yq-nixpkgs-namespace-collision.md` | nixpkgs ships TWO unrelated packages that both plausibly answer to "yq": `pkgs.yq` (kislyuk/yq, a Python jq-wrapper, the SAME upstream as Arch's own `yq`) and `pkgs.yq-go` (mikefarah/yq, a Go tool with its own query language) — the modern-sounding name is the wrong one. Decided `lib/tools.nix`'s `data.yq` entry to carry the plain `nixpkgs = "yq"`, confirmed by cross-checking `meta.homepage` against pacman's own `URL` field for both platforms, not by name alone. |
