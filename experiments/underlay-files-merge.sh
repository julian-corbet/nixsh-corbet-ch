#!/usr/bin/env bash
# Proves the `layer = "files"` half of `nixsh.underlay` (modules/nixsh.nix), which is the half with
# no source order to lean on: a tool with no include mechanism and a single settings file, whose
# colorschemes and syntax definitions are separate FILES that can plausibly come from the distro
# while the settings file is declared by nixsh.
#
# TWO SEPARATE QUESTIONS, and both have to be answered on a real system rather than reasoned about:
#
#   1. Does the MERGE go the right way? A base child appears in the config directory; a name the
#      consumer declares is never taken from the base, and never replaced even if the declaration
#      forgets to list it; a link the mechanism made is withdrawn once its base child is gone or
#      the name becomes the consumer's. This part runs the same shell logic modules/home.nix emits
#      into home-manager's activation, against a fixture, and reads the resulting directory back.
#
#   2. Does the TOOL actually read a config directory assembled this way -- specifically, does it
#      resolve files through a SYMLINKED subdirectory rather than only through real ones? That
#      decides symlink-versus-copy, and is answered by running micro itself.
#      See studies/micro-underlay-links-not-copies.md for what the answer settled.
#
# Usage: ./experiments/underlay-files-merge.sh
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

check() { # check <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    echo "OK   $1"
  else
    echo "FAIL $1"
    echo "       expected: $2"
    echo "       actual:   $3"
    fail=1
  fi
}

base="$work/base"
into="$work/config/tool"
ours=" settings.json "

mkdir -p "$base/colorschemes" "$base/syntax" "$into"
echo '{"from": "the distro"}' >"$base/settings.json"   # the base HAS one; ours must still win
echo 'scheme' >"$base/colorschemes/vendor.micro"
echo 'syntax' >"$base/syntax/nix.yaml"
echo 'retired' >"$base/retired.conf"

# The two halves of what modules/home.nix emits, transcribed. Kept as functions so the same code
# can be run twice (a second activation must be idempotent) and in either order.
prune() {
  if [ -d "$into" ]; then
    find "$into" -mindepth 1 -maxdepth 1 -type l -printf '%f\n' | while IFS= read -r n; do
      case "$(readlink -- "$into/$n")" in
        "$base"/*) ;;
        *) continue ;;
      esac
      case "$ours" in *" $n "*) rm -f -- "$into/$n"; continue ;; esac
      [ -e "$base/$n" ] || rm -f -- "$into/$n"
    done
  fi
}

link() {
  if [ -d "$base" ] && [ -r "$base" ]; then
    mkdir -p -- "$into"
    find "$base" -mindepth 1 -maxdepth 1 -printf '%f\n' | while IFS= read -r n; do
      case "$ours" in *" $n "*) continue ;; esac
      if [ -e "$into/$n" ] || [ -L "$into/$n" ]; then
        case "$(readlink -- "$into/$n" 2>/dev/null || true)" in
          "$base"/*) ;;
          *) continue ;;
        esac
      fi
      ln -sfn -- "$base/$n" "$into/$n"
    done
  fi
}

# A switch: prune, then home-manager writes the declared files, then link.
switch() { prune; echo '{"from": "nixsh"}' >"$into/settings.json"; link; }

# ── 1. merge direction ────────────────────────────────────────────────────────────────────────
switch

check "the base's children are linked into the config directory" \
  "yes" \
  "$([[ -L "$into/colorschemes" && -L "$into/syntax" ]] && echo yes || echo no)"

check "a linked child resolves to the base, not to a copy" \
  "$base/colorschemes" "$(readlink "$into/colorschemes")"

check "a name declared as ours is NOT taken from the base" \
  "yes" \
  "$([[ ! -L "$into/settings.json" ]] && echo yes || echo no)"

check "the declared file's content is ours, not the base's" \
  '{"from": "nixsh"}' "$(cat "$into/settings.json")"

# The structural half of "ours wins": occupancy alone protects a file, even when `ours` does not
# name it. This is what stops a base that grows a new child from clobbering something declared.
echo 'declared by the consumer' >"$into/keybindings.json"
echo 'from the distro' >"$base/keybindings.json"
switch
check "an occupied name is never replaced, even when it is absent from \`ours\`" \
  "declared by the consumer" "$(cat "$into/keybindings.json")"

# Idempotence: a second switch with nothing changed must leave the same tree.
before="$(find "$into" -mindepth 1 -maxdepth 1 -printf '%f %y\n' | sort)"
switch
check "a second switch changes nothing" \
  "$before" "$(find "$into" -mindepth 1 -maxdepth 1 -printf '%f %y\n' | sort)"

# Withdrawal: a base child that goes away must take its link with it, not leave a dangling one.
rm "$base/retired.conf"
switch
check "a link is withdrawn once the base no longer supplies that child" \
  "yes" \
  "$([[ ! -e "$into/retired.conf" && ! -L "$into/retired.conf" ]] && echo yes || echo no)"

# The migration this mechanism's two-phase split exists for: a name that WAS supplied by the base
# becomes the consumer's. The stale link must be gone before anything tries to write over it.
ours=" settings.json syntax "
prune
check "a name that becomes ours has its stale base link pruned before the write phase" \
  "yes" \
  "$([[ ! -L "$into/syntax" ]] && echo yes || echo no)"
ours=" settings.json "

# Clean degrade: the whole base disappears (its package removed). Nothing may be left dangling.
switch
mv "$base" "$work/base-gone"
switch
check "an absent base leaves no dangling links behind" \
  "0" \
  "$(find "$into" -mindepth 1 -maxdepth 1 -xtype l | wc -l)"
check "an absent base leaves the consumer's own declared files untouched" \
  '{"from": "nixsh"}' "$(cat "$into/settings.json")"
mv "$work/base-gone" "$base"
switch

# ── 2. does micro read a symlinked subdirectory? ───────────────────────────────────────────────
#
# The decisive question for symlink-versus-copy. micro is driven through a pty (it is a full-screen
# editor and will not start otherwise) and killed by a timeout; what is read back is the terminal
# output, which carries the colorscheme's own RGB values as SGR sequences when the scheme resolved
# and an error message when it did not.
if ! command -v micro >/dev/null 2>&1; then
  echo "SKIP micro is not installed on this host -- the symlink-resolution half is not run"
else
  mkdir -p "$work/micro/base/colorschemes" "$work/micro/cfg"
  # Deliberately unmistakable values: 0xF0/0x10 render as 240 and 16 in a truecolor SGR sequence.
  printf 'color-link default "#F0F0F0,#101010"\n' \
    >"$work/micro/base/colorschemes/underlayproof.micro"
  ln -s "$work/micro/base/colorschemes" "$work/micro/cfg/colorschemes"

  printf '{"colorscheme": "underlayproof"}\n' >"$work/micro/cfg/settings.json"
  timeout 8 script -qec "micro -config-dir $work/micro/cfg $work/micro/file.txt" /dev/null \
    </dev/null >"$work/micro/good.out" 2>&1 || true

  check "micro resolves a colorscheme through a SYMLINKED colorschemes directory" \
    "yes" \
    "$(grep -q '240;240;240' "$work/micro/good.out" && grep -q '16;16;16' "$work/micro/good.out" \
       && echo yes || echo no)"

  # The control: without the base, the same settings.json produces a named failure rather than a
  # silent fallback. This is why the prune phase must not blank the directory during a switch.
  printf '{"colorscheme": "nosuchscheme"}\n' >"$work/micro/cfg/settings.json"
  timeout 8 script -qec "micro -config-dir $work/micro/cfg $work/micro/file.txt" /dev/null \
    </dev/null >"$work/micro/bad.out" 2>&1 || true

  check "a missing colorscheme is a visible error in micro, not a quiet fallback" \
    "yes" \
    "$(grep -q 'is not a valid colorscheme' "$work/micro/bad.out" && echo yes || echo no)"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "The files layer merges in the declared direction, and micro reads it through symlinks."
else
  echo "One or more claims FAILED -- see above." >&2
  exit 1
fi
