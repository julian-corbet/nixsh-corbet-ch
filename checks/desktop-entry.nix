# Proves `nixpkgsDesktop` actually reaches the FILE, not just the Nix expression.
#
# This is deliberately a BUILD check rather than an eval one, unlike its neighbours. What
# lib/tools.nix's field claims is "the menu on a NixOS host says X", and every interesting way for
# that to be false survives an eval: the join could place the file at the wrong path, `rm -f` could
# fail to displace a store symlink and leave the wrapper's own entry in place, the writeText could
# land somewhere `share/applications` is not searched. So the check evaluates a real NixOS system,
# takes the packages it would install, and reads the bytes.
#
# It also asserts the NEGATIVE case -- a tool with no `nixpkgsDesktop` must come through
# untouched. Without that, a bug that wrapped every tool in a join would pass every positive
# assertion here while quietly rebuilding the world.
{ pkgs, nixpkgs, lib ? pkgs.lib }:
let
  sys = nixpkgs.lib.nixosSystem {
    inherit (pkgs) system;
    modules = [
      ../modules/nixos.nix
      {
        # Three tools: two that carry the field for its two different reasons (neovim ships a
        # WRONG entry, zellij ships NONE), and one that carries nothing at all.
        nixsh.tools.edit = [ "neovim" "zellij" "helix" ];

        # The minimum a NixOS evaluation insists on. Nothing here is under test; it exists so
        # `nixosSystem` will evaluate at all.
        boot.loader.grub.enable = false;
        fileSystems."/" = { device = "/dev/null"; fsType = "ext4"; };
        system.stateVersion = "24.05";
      }
    ];
  };

  installed = sys.config.environment.systemPackages;
  named = n: lib.findFirst (p: lib.hasInfix n (lib.getName p)) null installed;

  neovim = named "neovim";
  zellij = named "zellij";
  helix = named "helix";
in
assert lib.assertMsg (neovim != null && zellij != null && helix != null)
  "nixsh: desktop-entry check could not find the tools it selected in environment.systemPackages";

pkgs.runCommand "nixsh-desktop-entry-check" { } ''
  fail() { echo "nixsh: desktop-entry check FAILED: $1" >&2; exit 1; }

  # ── neovim: nixpkgs ships the entry, and it names the wrapper ─────────────────────────────
  nv=${neovim}/share/applications/nvim.desktop
  [ -f "$nv" ] || fail "neovim has no nvim.desktop at all"
  grep -qx 'Name=Neovim' "$nv" || fail "neovim entry is not named Neovim: $(grep '^Name=' "$nv")"
  ! grep -qi 'wrapper' "$nv" || fail "the word 'wrapper' survived into neovim's entry"
  # The corrected entry must still start the same program. A rename that also changed how the
  # editor launches would be a worse bug than the one it fixed.
  grep -qx 'Exec=nvim %F' "$nv" || fail "neovim Exec changed: $(grep '^Exec=' "$nv")"

  # ── zellij: nixpkgs ships nothing ─────────────────────────────────────────────────────────
  zj=${zellij}/share/applications/zellij.desktop
  [ -f "$zj" ] || fail "zellij still has no desktop entry"
  grep -qx 'Name=Zellij' "$zj" || fail "zellij entry is not named Zellij"
  grep -qx 'Terminal=true' "$zj" || fail "zellij entry is not marked Terminal=true"
  # The binary must still be there: a join that replaced the package rather than adding to it
  # would satisfy every assertion above and install no zellij.
  [ -x ${zellij}/bin/zellij ] || fail "zellij binary missing from the corrected package"

  # ── helix: no nixpkgsDesktop, so nothing may have happened to it ──────────────────────────
  case "${helix}" in
    *-desktop) fail "helix was wrapped despite carrying no nixpkgsDesktop" ;;
  esac
  [ -x ${helix}/bin/hx ] || fail "helix binary missing"

  touch $out
''
