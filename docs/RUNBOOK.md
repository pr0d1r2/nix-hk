# Runbook

Operational procedures for nix-hk. Everything here is either automated by a
workflow or needs a human; each section says which.

## Bump order

```
nixpkgs-lock  ->  nix-hk  ->  itok, microlith
```

Three hops, and the order is not cosmetic. Each repo's cache hits depend on
resolving the same nixpkgs rev as the one hk was *built* against. Refresh a
consumer before this repo has published against the new pin and it resolves a
rev nothing has been cached for, so it compiles hk from source — quietly, since
that is a slow success rather than an error.

| step | who | what |
| ---- | --- | ---- |
| 1 | `nixpkgs-lock` | its own `pin-refresh` loop moves the rev |
| 2 | `nix-hk` | `update-pins.yml` (06:50 daily) opens a PR; merge it |
| 3 | consumers | pick up the new `nixpkgs-lock` **and** `nix-hk` together |

Step 3 needs both inputs moved in one commit. Moving only `nixpkgs-lock` leaves
`nix-hk` pinned to an older rev, and the `follows` edge then resolves two
different nixpkgs — the exact path multiplication the single-input rule exists
to prevent.

## A new hk release appears

Automated. `upstream.yml` polls `jdx/hk` at 06:20 daily, and
`scripts/bump-hk.sh` resolves both hashes and builds before a PR is opened. CI
on that PR is confirmation, not discovery.

Three things the script cannot check, worth doing by hand on the PR:

- **The eight `checkFlags` skips.** If upstream renamed or fixed one, the skip
  silently stops matching. Nothing fails — you just start skipping a test that
  no longer exists, or running one that was skipped for a reason.
- **Version in prose.** `README.md` and `SPEC.md` §G carry the version as text.
- **New system dependencies.** This derivation carries no `buildInputs` on
  purpose. A `Cargo.lock` that gains an `-sys` crate may need one, and the build
  will say so.

To exercise the machinery without waiting for a release:

```sh
scripts/bump-hk.sh --force   # re-resolve hashes for the current version
```

Clean tree afterwards means the hashes still reproduce. A diff means something
moved that should not have — investigate before assuming the script is wrong.

## rustc moves

The toolchain is whatever the pinned nixpkgs ships; there is no rust-overlay and
no `rust-toolchain.toml` anywhere in the fleet. So a rustc change arrives as a
nixpkgs bump, and `assert-pins` in CI pins the expected minor.

When the minor changes, `.github/workflows/build.yml` needs its `1.95.*` case
updated in the same PR — otherwise the assert fails, which is the point. Then
`itok` and `microlith` need matching `rust-version` values (V32), in bump order.

A consumer sitting on a `rust-version` higher than the pinned rustc is the
failure this fleet already had once: it is not a build error, it is a manifest
claim nobody was checking.

## The cache is empty or consumers are rebuilding

Symptoms are quiet by nature — a slow build looks like a normal build.

1. **Is the path in the cache?**
   ```sh
   nix eval --raw .#packages.aarch64-darwin.hk        # -> /nix/store/<hash>-hk-...
   curl -s -o /dev/null -w '%{http_code}\n' https://pr0d1r2.cachix.org/<hash>.narinfo
   ```
   404 means the push failed. Check the `verify-cache` job on the last main run,
   then the cachix push log — a 403 there means `CACHIX_AUTH_TOKEN` is not a
   per-cache token with **write** access to `pr0d1r2`. Note that cachix logs
   push failures without failing its own step, so the push step being green
   proves nothing; `verify-cache` is what actually catches this.

2. **Is the consumer allowed to use the substituter?**
   A flake's `nixConfig` is ignored for users outside `trusted-users`:
   ```
   warning: ignoring untrusted substituter 'https://pr0d1r2.cachix.org', you are not a trusted user
   ```
   That is a warning, and the build then proceeds from source. Add the user to
   `trusted-users` in `/etc/nix/nix.conf` or the nix-darwin/NixOS equivalent.

3. **Prove it, do not assume it.**
   ```sh
   nix build --max-jobs 0 github:pr0d1r2/nix-hk#hk
   ```
   `--max-jobs 0` forbids local building, so this either substitutes or fails.
   There is no ambiguous middle, which is the only reason it is a useful test.

4. **Revs match?** Different nixpkgs rev means a different store path, so the
   cache is not missing — you are asking it for something it was never given.
   `assert-pins` covers this repo against nixpkgs-lock; consumers need the same
   check or the same discipline.

## Releasing

There is no release process. `main` is the artifact: consumers track the branch,
and every merge that passes `verify-cache` has already put all three tier-1
paths in the cache.

## x86_64-darwin

Declared, evaluated in CI, never built by CI and never cached. Building on an
Intel Mac compiles from source. If that platform ever needs cache coverage, it
needs a runner that is not `macos-13`.
