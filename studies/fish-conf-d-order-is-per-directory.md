# fish sources `conf.d` per DIRECTORY, not by a global filename sort

## The claim this started from

fish's own documentation, and every summary of it, says configuration snippets are collected from
several `conf.d` directories — `$__fish_config_dir/conf.d`, `$__fish_sysconf_dir/conf.d`, and the
vendor directories — and that a file in an earlier directory shadows a same-named file in a later
one. That much is true. What is easy to read into it, and what the first draft of `nixsh.underlay`
was designed against, is that the collected files are then sourced **in filename order**, as if the
directories were merged into one namespace and sorted.

They are not. Getting this wrong would not have broken the underlay — but it would have made this
repo state something false about where a numbered drop-in lands, and a future change built on that
statement would have been wrong.

## What actually happens

fish 4.8.1's `config.fish` (embedded in the binary; recoverable with `strings /usr/bin/fish`) ends
with:

```fish
# As last part of initialization, source the conf directories.
# Implement precedence (User > Admin > Extra (e.g. vendors) > Fish) by basically doing "basename".
set -l sourcelist
for file in $__fish_config_dir/conf.d/*.fish $__fish_sysconf_dir/conf.d/*.fish $__fish_vendor_confdirs/*.fish
    set -l basename (string replace -r '^.*/' '' -- $file)
    contains -- $basename $sourcelist
    and continue
    set sourcelist $sourcelist $basename
    test -f $file -a -r $file
    and source $file
end
```

Three globs, concatenated. Each glob is expanded and sorted **separately**, so the traversal is
directory-major: every file in the user's `conf.d`, in filename order, then every file in the
system one, then the vendor ones. The `sourcelist` dedupe is what implements shadowing, and it is
the only cross-directory interaction there is.

## The measurement

`experiments/underlay-ours-wins.sh` builds an isolated `HOME`/`XDG_CONFIG_HOME`/`XDG_DATA_DIRS`,
drops four files into it, and runs a real `fish -c` to read back the order they ran in:

| file | directory |
|---|---|
| `00-nixsh-underlay.fish` | user `conf.d` |
| `50-nixsh.fish` | user `conf.d` |
| `sibling-module.fish` | user `conf.d` |
| `10-vendor.fish` | a vendor `conf.d` |

Observed order:

```
00-underlay  50-nixsh  sibling-module  10-vendor
```

A global filename sort would have put `10-vendor` second. It ran last, after an unprefixed file in
an earlier directory. A fifth file, `40-shadow.fish`, present in both directories, confirmed the
shadowing half: the user's copy ran, the vendor's never did.

## What this decided

1. **The numbering is a within-directory instrument, and the module says so.** `nixsh.underlay`
   orders a distro base (`00-nixsh-underlay.fish`) against nixsh's own content (`50-nixsh.fish`),
   and both live in `~/.config/fish/conf.d`, so the numbers do exactly what the design needs. They
   would not have reached a base sitting in a vendor directory, and `modules/home.nix` now states
   that limit rather than implying a reach it does not have.

2. **nixsh's own drop-in had to be renumbered, and the reason survives the correction.** It shipped
   as `00-nixsh.fish`, chosen so nixsh would land before anything a host added itself. Under a base
   layer that reasoning inverts: there is no number below `00-`, so the base takes it and nixsh
   moves to `50-`. The gaps are now a stated convention — `01`–`49` is below nixsh, `51`+ is above.

3. **An unprefixed drop-in from a sibling module lands last, and that is the right default.**
   Digits sort before letters, so a file like a `fish_command_not_found` dispatcher written by
   another module wins over both nixsh's file and the distro base without anyone coordinating
   numbers. It is deliberately overriding a builtin; running last is what it wants.

4. **`/etc/fish/conf.d` and the vendor directories are outside what any of this can order.** They
   are sourced after everything in the user's `conf.d`, whatever the filenames. Nothing in the
   underlay tries to pretend otherwise; a conflict there is a different problem with a different
   answer.
