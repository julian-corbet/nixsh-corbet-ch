# nvtop: no top-level nixpkgs attribute — it lives under `nvtopPackages.full`

**Finding:** `pkgs.nvtop` does not exist on nixpkgs at all — `hasAttrByPath [ "nvtop" ] pkgs` is
`false`, not a throwing alias (the class of bug `experiments/validate-nixpkgs-names.nix`'s own
header describes; this is a plainer, still-real gap: no attribute, of any kind, under that name).
The package lives under `nvtopPackages.full`, whose own `pname` is `nvtop` — nixpkgs ships nvtop
as a family of build variants (per-GPU-vendor support is compiled in, not runtime-detected) rather
than one derivation, and only exposes the combined build through the nested set.

**Why this is worth a study rather than just a catalogue line:** every other entry in this
catalogue that has a nixpkgs attribute at all uses a single, un-nested name — `nvtop` is the one
place a dotted path (`lib.splitString "." t.nixpkgs`, the mechanism `modules/tools.nix` already
carries for exactly this shape) is actually load-bearing rather than theoretical. Worth confirming
identity too, not just existence, given how differently-shaped the two platforms' packaging is
here: Arch's own `nvtop` (single package, `pacman -Si nvtop`) and nixpkgs' `nvtopPackages.full`
both point at the same upstream project (`github.com/Syllo/nvtop`), confirmed by comparing
pacman's `URL` field against nixpkgs' `meta.homepage` — the packaging SHAPE diverges, the project
identity does not.

**Evidence:**

```
$ pacman -Si nvtop
Repository      : cachyos-extra-v3
Name            : nvtop
Description     : GPUs process monitoring for AMD, Intel and NVIDIA
URL             : https://github.com/Syllo/nvtop

$ nix eval --impure --json --expr \
  '(import (fetchTarball ".../1d4e0f865...tar.gz") {}) ? nvtop'
false

$ nix eval --impure --json --expr \
  '{ pname = (import (fetchTarball ".../1d4e0f865...tar.gz") {}).nvtopPackages.full.pname;
     homepage = (import (fetchTarball ".../1d4e0f865...tar.gz") {}).nvtopPackages.full.meta.homepage; }'
{"homepage":"https://github.com/Syllo/nvtop","pname":"nvtop"}
```

**Decision this drove:** `lib/tools.nix`'s `system.nvtop` entry carries `nixpkgs =
"nvtopPackages.full"` — a dotted path rather than the plain name every other entry in the table
uses — with an inline note stating the gap directly, so a future reader auditing a stale-mapping
warning for `nvtop` does not assume the entry is simply wrong and "fix" it back to a bare `nvtop`
that would resolve to nothing at all (`hasAttrByPath` returning `false`, not a throw, means
`modules/nixos.nix`'s `tryEval` pass would silently skip it with a warning rather than crash —
correct behaviour, but a warning is a worse outcome than never triggering it by writing the right
path in the first place).

**Method:** `pacman -Si` against a live CachyOS host for the Arch side; `nix eval --impure` (both
existence and force-evaluation) against the nixpkgs revision infra's own `flake.lock` had pinned
at the time for the nixpkgs side, plus the homepage cross-check for identity. Reproducible via
`../experiments/verify-package-names.sh`.
