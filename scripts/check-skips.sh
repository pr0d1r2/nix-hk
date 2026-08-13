#!/usr/bin/env bash
# Assert every checkFlags skip still names a test that exists upstream.
#
# `cargo test -- --skip=does_not_exist` is silently accepted. So a skip whose
# test was renamed or deleted upstream stops matching and simply skips nothing:
# no error, no warning, and a test we deliberately excluded quietly starts
# running (or a rename means we skip a test that no longer needs skipping and
# never notice). The bump script cannot catch this -- it only resolves hashes.
#
# The skip entries are Rust module paths ending in the function name, e.g.
#   cli::init::detector::tests::test_detect_shell_scripts
# so the observable is `fn <name>` somewhere in the fetched source.
set -euo pipefail

cd "$(dirname "$0")/.."
pkg=pkgs/hk/package.nix

# Use the same src the derivation uses, so this checks the version we actually
# build rather than whatever upstream's default branch happens to be today.
src="$(nix build --no-link --print-out-paths ".#hk.src")"
echo "source: $src" >&2

# No mapfile here: macOS ships bash 3.2, where it does not exist. This script
# has to run on a developer's Mac as well as on the Linux runner.
skips=""
while IFS= read -r line; do
  skips="$skips$line
"
done < <(sed -n 's/^    "--skip=\(.*\)"$/\1/p' "$pkg")
count="$(printf '%s' "$skips" | grep -c . || true)"
[ "$count" -gt 0 ] || { echo "no --skip entries found in $pkg" >&2; exit 1; }
echo "checking $count skip entries" >&2

rc=0
for skip in $skips; do
  fn="${skip##*::}"
  if grep -rqF "fn $fn" "$src"; then
    echo "  ok      $skip"
  else
    echo "  MISSING $skip  (no 'fn $fn' in source)" >&2
    rc=1
  fi
done

if [ "$rc" -ne 0 ]; then
  cat >&2 <<'EOF'

A skipped test no longer exists upstream. Either it was renamed -- update the
entry -- or it was fixed and the skip should be dropped. Leaving it is not
harmless: the skip matches nothing, so the test it was meant to exclude is
running again with no one having decided that.
EOF
  exit 1
fi
echo "all skips resolve to real tests" >&2
