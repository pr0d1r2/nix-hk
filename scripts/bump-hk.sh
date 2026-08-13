#!/usr/bin/env bash
# Bump hk to the latest upstream tag and resolve both hashes.
#
# Runs from CI on a schedule, but is written to be run by hand too -- the hash
# resolution is the fiddly part and you want to be able to exercise it without
# waiting for jdx to cut a release. `--force` re-resolves the current version,
# which is a no-op if the hashes on disk are right and a loud diff if they are
# not.
#
#   scripts/bump-hk.sh           # bump if upstream is newer
#   scripts/bump-hk.sh --force   # re-resolve hashes for the current version
#
# Writes pkgs/hk/package.nix in place. Prints NEW_VERSION=... on stdout when
# something changed, so CI can decide whether to open a PR.
set -euo pipefail

cd "$(dirname "$0")/.."
pkg=pkgs/hk/package.nix
force=false
[ "${1:-}" = "--force" ] && force=true

current="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$pkg")"
[ -n "$current" ] || { echo "cannot read current version from $pkg" >&2; exit 1; }

latest="$(gh api repos/jdx/hk/releases/latest --jq .tag_name)"
latest="${latest#v}"
[ -n "$latest" ] || { echo "cannot read latest tag from upstream" >&2; exit 1; }

echo "current=$current latest=$latest force=$force" >&2

if [ "$current" = "$latest" ] && [ "$force" = false ]; then
  echo "already current" >&2
  exit 0
fi

# srcHash first: cheap, and a wrong one fails before we spend a build on it.
raw="$(nix-prefetch-url --unpack --type sha256 \
  "https://github.com/jdx/hk/archive/refs/tags/v$latest.tar.gz" 2>/dev/null | tail -1)"
src="$(nix hash convert --hash-algo sha256 --to sri "$raw")"
echo "srcHash=$src" >&2

fake="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
sed -i.bak \
  -e "s|^  version = \".*\";$|  version = \"$latest\";|" \
  -e "s|^    hash = \".*\";$|    hash = \"$src\";|" \
  -e "s|^  cargoHash = \".*\";$|  cargoHash = \"$fake\";|" \
  "$pkg"
rm -f "$pkg.bak"

# cargoHash can only be learned by being wrong on purpose: build with a
# placeholder and read the hash nix says it wanted. Vendoring is deterministic,
# so the value is stable across machines and platforms.
echo "resolving cargoHash (expect one deliberate failure)" >&2
# The build is *meant* to fail here, so it has to run outside `set -e`. With
# pipefail on, `got=$(nix build ... | awk ...)` aborts the script at the
# assignment and never reaches the check below -- which is exactly what
# happened the first time this was written.
set +e
out="$(nix build .#hk --no-link 2>&1)"
set -e
got="$(printf '%s\n' "$out" | awk '/got:/ {print $2; exit}')"
if [ -z "$got" ]; then
  printf '%s\n' "$out" >&2
  echo "no hash mismatch reported -- vendor hash may already be correct" >&2
  exit 1
fi
echo "cargoHash=$got" >&2
sed -i.bak -e "s|^  cargoHash = \".*\";$|  cargoHash = \"$got\";|" "$pkg"
rm -f "$pkg.bak"

# Prove the result before handing it to anyone.
nix build .#hk --no-link

# Only announce a bump when the version actually moved. --force re-resolves the
# hashes of the current version to check they still reproduce, and must not
# make CI open a PR bumping 1.55.0 to 1.55.0.
if [ "$current" = "$latest" ]; then
  echo "hashes re-resolved for $latest, version unchanged" >&2
else
  echo "NEW_VERSION=$latest"
fi
