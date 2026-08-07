# The 7-Zip entry: the pacman name is `7zip`, the nixpkgs attribute is `p7zip`

Neither plane calls this package what the other calls it, and on each plane the obvious-looking
name is wrong for a *different* reason. Both halves were verified against real repositories before
`lib/tools.nix`'s `archive.p7zip` entry was written.

## Arch: `p7zip` does not exist in any repository

```
$ pacman -Si p7zip
error: package 'p7zip' was not found

$ pacman -Si 7zip
Repository      : extra
Name            : 7zip
Version         : 26.02-1
Description     : File archiver for extremely high compression
URL             : https://www.7-zip.org
Provides        : p7zip
Conflicts With  : p7zip
Replaces        : p7zip
```

Arch retired its p7zip package in favour of upstream 7-Zip's own Linux port, and the replacement
declares the old name as a virtual provide. The AUR does not carry it either:

```
$ curl -s 'https://aur.archlinux.org/rpc/v5/info?arg[]=p7zip' | jq .resultcount
0
```

So `aur = true` would not have rescued the bare name — this is not the pacman/AUR split, it is a
name that exists nowhere. A pacman transaction naming it fails **whole**, taking every unrelated
package in the same converge down with it, which is the failure mode `lib/tools.nix`'s own header
already documents for AUR names in a pacman list.

Resolving it through the virtual provide would not be a fix either. Pacman *can* install `7zip`
when asked for `p7zip`, but the installed package's name is `7zip`, so a reconciler that compares
declared names against installed ones would see the declared package as permanently missing and
try to install it on every run.

## nixpkgs: `_7zz` is the closer project match and the wrong choice

nixpkgs carries both, and both force-evaluate:

| attribute | name | homepage | binaries |
|---|---|---|---|
| `p7zip` | `p7zip-17.06` | `github.com/p7zip-project/p7zip` | `7z`, `7za`, `7zr` |
| `_7zz` | `7zz-26.02` | `7-zip.org` | `7zz` |

By project and even by version, `_7zz` is what Arch now ships — same upstream, same 26.02. By
**command surface** it is not: Arch's `7zip` package installs `/usr/bin/7z`, `/usr/bin/7za` and
`/usr/bin/7zr`, and `7z` is the name scripts and archive front-ends call by hand. `_7zz` installs
`7zz` and nothing else.

```
$ pacman -Ql 7zip | grep /usr/bin/
7zip /usr/bin/7z
7zip /usr/bin/7za
7zip /usr/bin/7zr

$ ls $(nix build --no-link --print-out-paths nixpkgs#_7zz)/bin/
7zz
```

Choosing `_7zz` for project purity resolves cleanly, installs successfully, and then silently fails
to provide the command anyone actually types — the same *shape* of failure as a throwing alias,
arriving through a name that is entirely real. A catalogue whose whole promise is "the same
capability on every supported plane" has to weigh the command surface above the version number.

## Decision

`lib/tools.nix`'s `archive.p7zip` entry carries `arch = "7zip"` and `nixpkgs = "p7zip"`, with the
catalogue key left as the common name — the same three-way shape as `core.delta` (key `delta`, arch
`git-delta`, nixpkgs `delta`; see `delta-pacman-name-is-git-delta.md`).

The sibling repo nixdesktop reached the identical conclusion on the nixpkgs half independently, for
its own reason: its `fileManagerExtras` role installs `pkgs.p7zip` because engrampa's archive
backends exec `7z` by bare name out of an unwrapped binary, so `_7zz` would leave the format simply
missing from the UI. Two different consumers, the same finding.
