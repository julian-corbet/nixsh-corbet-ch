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
| `p7zip-arch-name-is-7zip.md` | Neither plane calls 7-Zip what the other does, and the obvious name is wrong on each for a different reason: Arch retired `p7zip` (no official repo, no AUR — `aur = true` would not have saved it) in favour of `7zip`, which `Provides`/`Replaces` it; nixpkgs' `_7zz` is the closer project match by version but ships its binary as `7zz` only, where Arch's package and every caller use `7z`. Decided `lib/tools.nix`'s `archive.p7zip` entry to carry `arch = "7zip"` with `nixpkgs = "p7zip"` — command surface over version parity. |
| `yq-nixpkgs-namespace-collision.md` | nixpkgs ships TWO unrelated packages that both plausibly answer to "yq": `pkgs.yq` (kislyuk/yq, a Python jq-wrapper, the SAME upstream as Arch's own `yq`) and `pkgs.yq-go` (mikefarah/yq, a Go tool with its own query language) — the modern-sounding name is the wrong one. Decided `lib/tools.nix`'s `data.yq` entry to carry the plain `nixpkgs = "yq"`, confirmed by cross-checking `meta.homepage` against pacman's own `URL` field for both platforms, not by name alone. |
