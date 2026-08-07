#!/usr/bin/env bash
# Reproduces the verification every (arch, nixpkgs) pair in lib/tools.nix was checked against
# before being committed: `pacman -Si` (and, for the AUR-only names, the AUR RPC) for the Arch
# side; a force-evaluating `nix-instantiate --eval` for the nixpkgs side. This is the manual,
# human-readable half — experiments/validate-nixpkgs-names.nix is the machine-checkable half for
# the nixpkgs side alone (wire it into CI; this script is for re-running the FULL verification by
# hand after touching lib/tools.nix, the way it was actually done to build this catalogue in the
# first place, against a live CachyOS host's pacman and a pinned nixpkgs rev).
#
# BOTH NAME LISTS ARE READ OUT OF lib/tools.nix, never hand-maintained here. They used to be
# hardcoded and went stale exactly the way a duplicated list does: entries added to the catalogue
# were never checked by this script, and entries REMOVED from it were still "verified" here long
# after they stopped existing. The catalogue is the one place a tool is named.
#
# Usage: ./experiments/verify-package-names.sh [nixpkgs-rev]
#   Defaults to the revision this repo's own flake.lock pins — the same one `nix flake check`
#   evaluates checks/tools-eval.nix against.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
rev="${1:-$(sed -n 's/.*"rev": "\([0-9a-f]\{40\}\)".*/\1/p' flake.lock | head -1)}"

# Every `arch` name in lib/tools.nix, split by the `aur` flag. Pure builtins on purpose: this must
# work on a host with no <nixpkgs> channel at all, since it is only reading an attrset of strings.
catalogue_arch_names() {
  local aur="$1"
  nix-instantiate --eval --strict --expr "
    let
      cat = import ./lib/tools.nix { };
      entries = builtins.concatLists (map builtins.attrValues (builtins.attrValues cat));
      want = builtins.filter (t: (t.aur or false) == ${aur}) entries;
    in builtins.concatStringsSep \" \" (map (t: t.arch) want)
  " | sed 's/^"//; s/"$//'
}

read -r -a official_names <<<"$(catalogue_arch_names false)"
read -r -a aur_names <<<"$(catalogue_arch_names true)"

echo "== Arch official repos (pacman -Si) — ${#official_names[@]} names =="
official_status=0
for pkg in "${official_names[@]}"; do
  if pacman -Si "$pkg" >/dev/null 2>&1; then
    echo "OK   $pkg"
  else
    echo "MISS $pkg -- not in an official repo on this host; check whether lib/tools.nix still marks it aur = false"
    official_status=1
  fi
done

echo
echo "== AUR-only names (aur.archlinux.org RPC v5 -- pacman -Si never sees these) — ${#aur_names[@]} names =="
aur_status=0
for pkg in "${aur_names[@]}"; do
  if curl -sf "https://aur.archlinux.org/rpc/v5/info?arg[]=$pkg" | grep -q '"resultcount":1'; then
    echo "OK   $pkg (AUR)"
  else
    echo "MISS $pkg -- not found in the AUR either; lib/tools.nix's arch name is wrong"
    aur_status=1
  fi
done

echo
echo "== nixpkgs, force-evaluated against rev $rev (delegates to validate-nixpkgs-names.nix) =="
result="$(nix-instantiate --eval --strict \
  --arg nixpkgs "(fetchTarball \"https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz\")" \
  experiments/validate-nixpkgs-names.nix)"
echo "$result"
nixpkgs_status=0
if [[ "$result" != *"missing = [ ]"* ]]; then
  nixpkgs_status=1
fi

echo
if [[ $official_status -eq 0 && $aur_status -eq 0 && $nixpkgs_status -eq 0 ]]; then
  echo "All names verified against real repositories."
else
  echo "One or more names failed verification -- see MISS/missing lines above." >&2
  exit 1
fi
