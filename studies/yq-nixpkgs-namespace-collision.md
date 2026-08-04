# yq: nixpkgs ships two unrelated tools that both plausibly answer to the name

**Finding:** nixpkgs carries both `pkgs.yq` and `pkgs.yq-go`, and they are not the same project
wearing two names — they are two different tools with the same three-letter name, from two
different authors, with two different query languages:

- `pkgs.yq` — kislyuk/yq, a Python **wrapper around jq**: it converts YAML/XML/TOML to JSON,
  shells out to `jq` for the actual query, then converts back. jq's own syntax, jq's own
  semantics.
- `pkgs.yq-go` — mikefarah/yq, a standalone Go binary with **its own** query language (`jq`-
  *inspired*, not jq itself, and not syntax-compatible with it for anything beyond the simplest
  paths).

Arch's own `yq` package (`pacman -Si yq`) is kislyuk/yq — confirmed by its `URL` field
(`https://github.com/kislyuk/yq`) and its `Conflicts With: go-yq` line, which is Arch's own
maintainers stating the same distinction this study makes: the two tools are considered mutually
exclusive under the name `yq`, and Arch picked kislyuk's.

**Why this is worth a study rather than just a catalogue line:** `yq-go` is the name a search
would surface first for anyone used to mikefarah's tool (it is, by a wide margin, the more
commonly recommended "yq" outside the Arch/Debian ecosystem, and its own README literally opens by
disambiguating itself from kislyuk's for exactly this reason). Picking `nixpkgs = "yq-go"` for
this catalogue's `data.yq` entry would have been the single most tempting wrong answer in the
whole table — it EXISTS, it FORCE-EVALUATES cleanly, `experiments/validate-nixpkgs-names.nix`
would report it as fully resolved, and it would still be silently the wrong tool: a consumer
selecting `yq` here, expecting Arch's own jq-wrapper behaviour, would get a binary with a
different query language installed on NixOS and an entirely correct-looking closure. This is
exactly the class of trap the project's own verification standard exists to catch — existence and
force-evaluation prove a name resolves, never that it resolves to the RIGHT package — and here
neither of those two checks alone would have caught it; only comparing identity (homepage against
`URL`) across the two candidate nixpkgs attributes did.

**Evidence:**

```
$ pacman -Si yq
Repository      : extra
Name            : yq
Description     : Command-line YAML, XML, TOML processor - jq wrapper for YAML/XML/TOML documents
URL             : https://github.com/kislyuk/yq
Conflicts With  : go-yq

$ nix eval --impure --json --expr \
  '{ yq = (import (fetchTarball ".../1d4e0f865...tar.gz") {}).yq.meta.homepage;
     yqgo = (import (fetchTarball ".../1d4e0f865...tar.gz") {}).yq-go.meta.homepage; }'
{"yq":"https://github.com/kislyuk/yq","yqgo":"https://mikefarah.gitbook.io/yq/"}
```

`pkgs.yq`'s homepage matches Arch's own `yq` `URL` field exactly — same project. `pkgs.yq-go`'s
homepage is a different site entirely, for a different project.

**Decision this drove:** `lib/tools.nix`'s `data.yq` entry carries the plain, unqualified
`nixpkgs = "yq"` — deliberately NOT `yq-go` — with an inline note naming the collision directly,
so a future reader who already knows mikefarah's tool as "the real yq" does not "fix" this entry
toward the more famous package.

**Method:** `pacman -Si` against a live CachyOS host for the Arch side (description, URL, and the
`Conflicts With` line, which is itself evidence Arch's maintainers drew the identical boundary);
`nix eval --impure` for both nixpkgs candidates' `meta.homepage`, cross-checked against each other
and against pacman's `URL` field, for the nixpkgs side. Not fully scriptable the way the other two
studies in this directory are — `experiments/verify-package-names.sh` proves `yq` still resolves
on both platforms, but the IDENTITY check (which of two resolving names is correct) needed reading
both projects' own descriptions, which is why it is written up here rather than something the
automated validator alone could have caught.
