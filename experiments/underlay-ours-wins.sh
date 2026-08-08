#!/usr/bin/env bash
# Proves the ONE claim `nixsh.underlay`'s shell layer rests on, against real shell binaries rather
# than against documentation: a distro base sourced FIRST loses every name collision to nixsh's own
# content sourced after it.
#
# WHY THIS SCRIPT EXISTS AT ALL. The claim looks too obvious to test -- "the last definition wins"
# is true in every shell -- but the interesting half is not the redefinition rule, it is whether
# the two files are actually reached in the order the design assumes. For fish that is a question
# about how conf.d directories are traversed, and the answer is NOT what fish's own documentation
# implies. Running it is how that was found; see studies/fish-conf-d-order-is-per-directory.md.
#
# Nothing here touches the invoking user's real config: every shell is run with an isolated HOME,
# XDG_CONFIG_HOME, XDG_DATA_DIRS and ZDOTDIR under a temporary directory, through `env -i`.
#
# Usage: ./experiments/underlay-ours-wins.sh
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

# ── fish ──────────────────────────────────────────────────────────────────────────────────────
#
# The layout mirrors what modules/home.nix actually writes -- `00-nixsh-underlay.fish` for the
# distro base and `50-nixsh.fish` for nixsh -- plus two files that are NOT nixsh's, to answer the
# two questions the numbering scheme depends on: where an unprefixed drop-in from a sibling module
# lands, and whether a file in a LATER conf.d directory can interleave by name.
mkdir -p "$work/fish/home" "$work/fish/config/fish/conf.d" "$work/fish/share/fish/vendor_conf.d"

cat >"$work/fish/config/fish/conf.d/00-nixsh-underlay.fish" <<'EOF'
set -g ORDER $ORDER 00-underlay
set -g COLLIDE base
alias ls 'eza-from-the-distro-base'
function fish_greeting; echo BASE-GREETING; end
EOF

cat >"$work/fish/config/fish/conf.d/50-nixsh.fish" <<'EOF'
set -g ORDER $ORDER 50-nixsh
set -g COLLIDE nixsh
alias ls 'ls-from-nixsh'
function fish_greeting; end
EOF

# No numeric prefix: a sibling module's own drop-in (nixremote's fish_command_not_found dispatcher
# is the real instance). Digits sort before letters, so this must land after both numbered files.
cat >"$work/fish/config/fish/conf.d/sibling-module.fish" <<'EOF'
set -g ORDER $ORDER sibling-module
EOF

# A vendor conf.d directory -- LATER in fish's search list, but with a number that would place it
# between the two user files if fish sorted globally by filename. It does not.
cat >"$work/fish/share/fish/vendor_conf.d/10-vendor.fish" <<'EOF'
set -g ORDER $ORDER 10-vendor
EOF

# Same basename in both directories: the user's copy must shadow the vendor's entirely.
echo 'set -g SHADOW user' >"$work/fish/config/fish/conf.d/40-shadow.fish"
printf 'set -g SHADOW vendor\nset -g ORDER $ORDER 40-shadow-VENDOR\n' \
  >"$work/fish/share/fish/vendor_conf.d/40-shadow.fish"

fish_out="$(env -i \
  HOME="$work/fish/home" \
  XDG_CONFIG_HOME="$work/fish/config" \
  XDG_DATA_DIRS="$work/fish/share" \
  PATH=/usr/bin:/bin TERM=dumb \
  fish -c 'echo "ORDER=$ORDER"; echo "COLLIDE=$COLLIDE"; echo "SHADOW=$SHADOW"; echo "ALIAS="(functions ls | string join " "); set -l g (fish_greeting | string collect); echo "GREETLEN="(string length -- "$g")')"

get() { sed -n "s/^$1=//p" <<<"$fish_out"; }

# The load-bearing one: nixsh's file is sourced after the base's, INSIDE ~/.config/fish/conf.d.
check "fish: 00-underlay is sourced before 50-nixsh" \
  "yes" \
  "$(grep -q '00-underlay 50-nixsh' <<<"$(get ORDER)" && echo yes || echo no)"

check "fish: an unprefixed drop-in sorts after both numbered files" \
  "yes" \
  "$([[ "$(get ORDER)" == *"50-nixsh sibling-module"* ]] && echo yes || echo no)"

# THE FINDING. fish's own config.fish iterates
#   $__fish_config_dir/conf.d/*.fish $__fish_sysconf_dir/conf.d/*.fish $__fish_vendor_confdirs/*.fish
# so the glob of EACH directory is expanded (and sorted) separately and the directories are visited
# in that order. A `10-` file in a vendor directory therefore runs after a `50-` file in the user's
# -- filename order is only ever WITHIN one directory.
check "fish: conf.d order is per-directory, NOT a global filename sort" \
  "00-underlay 50-nixsh sibling-module 10-vendor" \
  "$(get ORDER)"

check "fish: a same-named file in an earlier directory shadows the later one entirely" \
  "user" "$(get SHADOW)"

check "fish: nixsh's alias wins the collision with the base's" \
  "yes" \
  "$([[ "$(get ALIAS)" == *"ls-from-nixsh"* ]] && echo yes || echo no)"

# The real instance of this: a distro base that defines fish_greeting to run a fetch tool, and
# nixsh's own greeting mechanism replacing it with an empty one so the greeting is not printed
# twice. Only works if nixsh's definition is the later one.
check "fish: nixsh's empty fish_greeting wins over the base's" \
  "0" "$(get GREETLEN)"

# ── zsh ───────────────────────────────────────────────────────────────────────────────────────
#
# zsh has no conf.d, so the layering is positional inside the one rc file nixsh writes. The
# fixture is that file's shape: the guarded source of the distro base first, everything nixsh
# declares after.
mkdir -p "$work/zsh/home" "$work/zsh/dot"

cat >"$work/zsh/base.zsh" <<'EOF'
alias update='sudo pacman -Syu'
COLLIDE=base
EOF

cat >"$work/zsh/dot/.zshrc" <<'EOF'
if [ -r BASEPATH ]; then
  source BASEPATH
fi
alias update='the-nixsh-updater'
COLLIDE=nixsh
EOF
sed -i "s|BASEPATH|$work/zsh/base.zsh|g" "$work/zsh/dot/.zshrc"

zsh_out="$(env -i HOME="$work/zsh/home" ZDOTDIR="$work/zsh/dot" PATH=/usr/bin:/bin TERM=dumb \
  zsh -i -c 'echo "COLLIDE=$COLLIDE"; echo "ALIAS=$(alias update)"' 2>/dev/null)"

check "zsh: nixsh's value wins over the base's" \
  "nixsh" "$(sed -n 's/^COLLIDE=//p' <<<"$zsh_out")"

check "zsh: nixsh's alias wins over the base's" \
  "yes" \
  "$([[ "$(sed -n 's/^ALIAS=//p' <<<"$zsh_out")" == *"the-nixsh-updater"* ]] && echo yes || echo no)"

# The degrade path: the same rc file with a base that is not there must still apply everything
# nixsh declares, and must not fail the shell.
rm "$work/zsh/base.zsh"
zsh_missing="$(env -i HOME="$work/zsh/home" ZDOTDIR="$work/zsh/dot" PATH=/usr/bin:/bin TERM=dumb \
  zsh -i -c 'echo "COLLIDE=$COLLIDE"' 2>/dev/null)"

check "zsh: a missing base degrades to no base layer, not to a broken shell" \
  "nixsh" "$(sed -n 's/^COLLIDE=//p' <<<"$zsh_missing")"

echo
if [[ $fail -eq 0 ]]; then
  echo "All underlay ordering claims hold against real fish and zsh."
else
  echo "One or more claims FAILED -- see above." >&2
  exit 1
fi
