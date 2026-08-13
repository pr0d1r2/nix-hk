# nix-hk

[`hk`](https://hk.jdx.dev) 1.55.0 as a Nix flake, built against the same nixpkgs
the rest of the pr0d1r2 fleet pins, and served prebuilt from cachix.

## Why this repo exists

`nixos-26.05` does not ship `hk` at all. The package landed on nixpkgs master as
`hk: init at 1.48.0` on 2026-06-22, after the 26.05 branch-off, so there is no
`hk` to install on a 26.05 system and no backport coming. This repo is the 26.05
`hk` provider.

Building it here rather than in each consumer also means one derivation, one
cache entry, and one place to bump.

## Use it

```nix
inputs = {
  nixpkgs-lock.url = "github:pr0d1r2/nixpkgs-lock";
  nixpkgs.follows = "nixpkgs-lock/nixpkgs";
  nix-hk.url = "github:pr0d1r2/nix-hk";
  nix-hk.inputs.nixpkgs-lock.follows = "nixpkgs-lock";
};
```

The `follows` lines are load-bearing. Cache hits require that every repo resolve
the *same* nixpkgs rev; a second, unfollowed nixpkgs edge forks the rev and you
silently rebuild hk from source instead of substituting it.

Then `pkgs.hk` via `overlays.default`, or `nix-hk.packages.${system}.hk`
directly.

```
nix build github:pr0d1r2/nix-hk#hk
nix run   github:pr0d1r2/nix-hk#hk -- --version   # hk 1.55.0
```

## Binary cache

```
substituter: https://pr0d1r2.cachix.org
public key:  pr0d1r2.cachix.org-1:NfWjbhgAj41byXhCKiaE+av3Vnphm1fTezHXEGsiQIM=
```

**The flake's `nixConfig` is not enough on its own.** If your user is not in
`trusted-users`, nix ignores the substituter and builds hk from source, emitting
only a warning:

```
warning: ignoring untrusted substituter 'https://pr0d1r2.cachix.org', you are not a trusted user
```

That is a warning, not an error, so a machine that is quietly compiling hk on
every update looks identical to one that is getting cache hits. Add yourself
once, in `/etc/nix/nix.conf` or the NixOS/nix-darwin equivalent:

```
trusted-users = root <your-user>
```

To confirm you are actually substituting, `nix build --max-jobs 0` fails rather
than falling back to a local build.

## Platform support

| system           | tier | CI builds | cached | notes                                  |
| ---------------- | ---- | --------- | ------ | -------------------------------------- |
| `aarch64-darwin` | 1    | yes       | yes    | native runner `macos-14`               |
| `x86_64-linux`   | 1    | yes       | yes    | native runner `ubuntu-24.04`           |
| `aarch64-linux`  | 1    | yes       | yes    | native runner `ubuntu-24.04-arm`       |
| `x86_64-darwin`  | 2    | no        | **no** | evaluated in CI, built locally by hand |

Tier-2 is stated rather than implied: `x86_64-darwin` is declared and must
always evaluate, but CI never builds it and nothing is pushed to the cache for
it, so building on an Intel Mac compiles from source. GitHub's only Intel macOS
runner is `macos-13`, which is being retired; the platform is kept, the CI spend
is not. Breakage there does not block `main`.

## Pin graph

```
nixpkgs-lock ──> nix-hk ──┐
             └──> itok, microlith <┘
```

`nixpkgs-lock` is the fleet's sole nixpkgs authority and the only input here.
Bump order matters: `nixpkgs-lock` → `nix-hk` → consumers. Refreshing a consumer
before the upstream push means it resolves a rev nothing has been cached for.

CI asserts the parts that fail silently otherwise: that our nixpkgs rev equals
the one `nixpkgs-lock` publishes, and that the pinned rustc is 1.95.x.

## Notes on the derivation

It is *not* a copy of the nixpkgs recipe. `libgit2`, `openssl` and `pkg-config`
are deliberately absent, each verified by building without it:

- **libgit2** cannot be linked from the system. `libgit2-sys 0.18.7+1.9.6`
  requires `libgit2 >= 1.9.6, < 1.10.0`; the pin ships 1.9.3 and nixpkgs master
  ships 1.9.4. Nothing sets `LIBGIT2_NO_VENDOR`, so upstream already vendors it
  silently and its `libgit2` buildInput is inert. Setting the variable makes the
  build panic rather than link.
- **openssl** is unreferenced. hk is rustls end to end; there is no `openssl-sys`
  in `Cargo.lock` and the built closure holds zero references to either library.
- **pkg-config** then has nothing left to probe.

`usage` *is* required, despite looking droppable: `hk completion <shell>` execs
it during `postInstall`.
