# micro's underlay links to the base; it does not copy it

## The problem this had to solve

`nixsh.underlay`'s shell layer is easy: a shell `source`s a path, the path is read fresh on every
shell start, and an upstream change to the base is live the moment the package updates. micro has
nothing to lean on. It has no include mechanism, one `settings.json`, and its colorschemes and
syntax definitions are ordinary files it reads out of `<config-dir>/colorschemes` and
`<config-dir>/syntax`. So the base has to be **materialised** into the config directory somehow,
and there are exactly two ways to do it: symlink each child of the base, or copy them at switch
time.

## First, the uncomfortable part

The only copy of these files on a CachyOS host lives under `/etc/skel`. `cachyos-micro-settings`
installs `settings.json`, four colorschemes and ~150 syntax files there and ships **no**
`/usr/share` copy — `pacman -Ql` confirms it, and unlike `cachyos-fish-config` and
`cachyos-zsh-config`, which both put their real base in `/usr/share` and use `/etc/skel` only to
seed a one-line `source`, micro's package has no such split.

`/etc/skel` is a template directory. Its contract is "copy me into a new account, once", and
reading a live configuration out of it treats it as something it does not claim to be. Nothing here
pretends otherwise. It is done because the alternative is not a cleaner source — it is no upstream
layer for micro at all. The specific risk it carries is that `/etc/skel` may gain files meant only
as new-account templates that nobody wants merged into a live config, and that is contained by the
two guards the files layer already has: `ours` names what the consumer declares, and the linker
refuses to replace any occupied name it did not create itself. If upstream ever moves these files
to `/usr/share`, one `path` string changes and nothing else does.

## The two candidates

**Copy at switch time.** Pitched as pinned and reviewable: the config directory holds real files,
they only change when someone runs a switch, and an upstream change cannot arrive unnoticed.

**Symlink each child of the base.** The config directory holds links into the distro's own files,
so an upstream change is live as soon as pacman lands it, with no switch involved.

## What decided it

**1. "Reviewable" does not survive contact with the purity rule.** The whole mechanism refuses to
read impure paths at evaluation time — a distro file is not a Nix input, and asking Nix about it
bakes in an answer from the build machine rather than the target. So the copy can never enter the
store or git either. It would be an unreviewed snapshot taken by an activation script, diffed by
nobody, differing between two hosts depending on when each last switched. The claimed benefit is
not actually purchased; what is purchased is staleness.

**2. A copy makes the word "upstream" false.** The point of the mechanism, in the operator's own
framing, is that the distro's work keeps arriving and every difference from it is a deliberate
line in a Nix file. fish and zsh get that literally: the base is `source`d from its live path at
every shell start. A micro layer that froze at switch time would be a different mechanism wearing
the same name, and the fleet would have two answers to "is the base current?" depending on the
tool.

**3. micro genuinely reads through a symlinked directory** — measured, not assumed, because the
whole choice collapses if it does not. `experiments/underlay-files-merge.sh` runs micro through a
pty against a config directory whose `colorschemes` is a symlink to a base holding one scheme with
deliberately unmistakable colours (`#F0F0F0` on `#101010`), and reads the terminal output back: the
truecolor SGR sequences `38;2;240;240;240` and `48;2;16;16;16` are present. The scheme resolved
through the link. The control run, with the same `settings.json` naming a scheme that does not
exist, produces `nosuchscheme is not a valid colorscheme` instead.

**4. The failure modes are asymmetric in the honest direction.** A removed package leaves a
dangling link, which `ls` shows in red and micro reports by name. A stale copy looks correct
forever. Between a loud wrong answer and a quiet one, the underlay takes the loud one — and the
prune phase removes a link whose base child is gone, so the dangling case only exists between a
package removal and the next switch.

## What the same experiment forced elsewhere

The control run above also settled how the activation is staged. micro does **not** fall back
quietly when its configured colorscheme is missing; it stops and prints an error on every launch.
So the naive "remove every link we own, then recreate them" activation — which would leave the
directory empty for the duration of a switch, and permanently if activation failed in between — was
rejected in favour of a surgical prune that removes a link only when the name has become the
consumer's or the base no longer supplies it. In steady state there is no window at all.

## The decision

Symlink. `nixsh.underlay`'s `layer = "files"` links each child of the base into the tool's config
directory, skipping every name in `ours` and every name already occupied by something it did not
create. Upstream changes arrive without a switch; the consumer's own files are the ones nixsh
writes; and the one thing a copy would have bought — protection from an upstream change nobody
looked at — was never really on offer.
