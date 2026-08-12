# SPEC — nix-hk

## §G goal

Nix flake build `hk` v1.55.0 for aarch64-darwin, x86_64-linux, aarch64-linux; push to cachix `pr0d1r2`; consumed prebuilt by Rust repos (`itok`, `microlith`, future), ⊥ local compile.

Ecosystem target: ∀ pr0d1r2 Rust repo → identical underlying deps, bumpable from **one** place.

## §C constraints

### upstream hk

- src: `github:jdx/hk` tag `v1.55.0` (tagged 2026-08-11).
- hk = Rust. `edition = 2024`, `rust-version = 1.88.0` → pinned rustc ! ≥ 1.88.0.
- nixpkgs `pkgs/by-name/hk/hk` = **1.54.0** → ⊥ reuse as-is. Own derivation, template from nixpkgs one.
- build deps (from nixpkgs 1.54.0 recipe): nativeBuildInputs `pkg-config`, `installShellFiles`, `usage`; buildInputs `libgit2`, `openssl`; nativeCheckInputs `gitMinimal`.
- `git2 = "0.21"` w/ feature `vendored-libgit2` → nixpkgs links system `libgit2` instead; keep that path (smaller closure, cachix-friendly).
- build-deps: `codegen 0.3`, `indexmap 2`, `serde 1`, `serde_json 1` (build.rs codegen — runs in sandbox, ⊥ network).

### pin graph

```
nixpkgs-lock ──> nixpkgs-rust-lock ──┬──> nix-hk ──┐
                                     └──> itok, microlith <┘
```

- `github:pr0d1r2/nixpkgs-lock` — exists. Tracks `nixos-25.11`, ~80 consumers, auto-bumped by hallucinogen `pin-refresh` loop. Root pin authority.
- `github:pr0d1r2/nixpkgs-rust-lock` — new. Rust-ecosystem layer: toolchain union + shared crate pins. Inputs nixpkgs-lock only.
- `nix-hk` (this repo) — **1 input**: `nixpkgs-rust-lock`. `nixpkgs.follows = "nixpkgs-rust-lock/nixpkgs"`. Mirrors nixpkgs-lock's anti-path-multiplicity rule (extra inputs → lock > 500KB).
- consumers (`itok`, `microlith`) — 2 inputs: `nixpkgs-rust-lock` + `nix-hk`, latter `follows` former.
- ⊥ re-export of hk by nixpkgs-rust-lock. Would close cycle nix-hk ↔ nixpkgs-rust-lock → eval error. Cost = consumers wire 2 inputs.
- cachix reuse ! same nixpkgs rev ∀ repos. Rev drift = different store path = silent miss.

### nixpkgs-rust-lock scope (handoff — own SPEC.md)

nix pkgs, union of itok + microlith devShells:

`rustc cargo clippy rustfmt cargo-nextest cargo-llvm-cov llvmPackages.llvm cargo-deny cargo-semver-checks typos taplo nixfmt actionlint shellcheck lychee ripsecrets git`

- itok-only today: `shellcheck`. microlith-only: `llvmPackages.llvm`, `cargo-deny`. Union → both get all.
- rust side: shared MSRV + shared crate version pins. ⊥ `rust-toolchain.toml` in any repo → rustc from nixpkgs pin, ⊥ rust-overlay/fenix.
- 1.96 ≥ 1.88.0 → hk MSRV already satisfied by shared pin.

#### crate-pin mechanism — Option B (generate + assert)

Cargo has ⊥ remote `[workspace.dependencies]` inheritance; separate repos ⊥ one workspace → native import impossible. ∴ declare once + sync + gate.

```
lib.rustPins (nixpkgs-rust-lock)          ← sole declaration
  → nix eval …#lib.rustPins --json
  → sync script rewrites Cargo.toml (taplo, in toolchain, keeps formatting)
  → cron auto-PR, auto-merge on green
  → CI runs same script --check  (rustfmt --check pattern)
```

Governed set v1:

| class | keys | policy |
|---|---|---|
| toolchain | `rust-version`, `edition` | exact |
| dev-deps | `assert_cmd`, `predicates`, `proptest`, `vcr-cassette`, `serde_json` | exact `=X.Y.Z` |
| first-party | `microlith`, `itok` | exact `=X.Y.Z` |

- exact `=` pins by decision — lockstep across repos, bumped by autonomous loops, ⊥ hand-chased ranges.
- first-party crates ARE shared deps: microlith + itok land in ∀ repo. Dogfood is the point — integration system consumes itself.
- ollama axis (`ureq`) ∉ governed. Lives in `../blackbox` only so far.
- current state, real drift the gate catches: microlith local `0.6.0`, `blackbox/Cargo.toml` pins `microlith = "0.5"`.
- itok unpublished. `blackbox` takes `itok = { path = "../itok", default-features = false, features = ["bpe"] }` → exact registry pin ⊥ possible until published. `?` govern as path-dep exemption or block on publish.
- itok features: `default = ["bpe","session"]`; `bpe`→`tiktoken-rs`, `session`→`serde_json`, `ollama`→`ureq`.
- editions diverge: itok `2021`, microlith `2024`, both MSRV `1.96`. Unify → `2024`.
- exact-pin hazard: `=1.0.151` ∧ another dep wanting `^1.0.160` = unsatisfiable, hard resolve error. Range pins ⊥ have this. Accepted cost; loop ! bump promptly.
- `=` pins requirement strings, ⊥ resolved graph. Each repo keeps own `Cargo.lock`. Exact pins narrow drift to near-zero for governed crates, ⊥ for their transitives.

### build & CI

- systems tiered:
  - declared = **4**: `aarch64-darwin`, `x86_64-darwin`, `x86_64-linux`, `aarch64-linux`. Matches nixpkgs-lock.
  - tier-1 = **3**: `aarch64-darwin`, `x86_64-linux`, `aarch64-linux`. CI builds, tests, pushes cachix.
  - tier-2 = `x86_64-darwin`. Eval ! pass ∀ CI. Build ⊥ CI-verified, ⊥ cachix. Owner builds locally on Intel Mac.
- tier-2 rationale: GH Intel runner = `macos-13` only, retiring. ⊥ spend CI on it; ⊥ amputate the platform either.
- flake pure eval. ⊥ IFD. `flake.lock` committed.
- cachix push from GitHub Actions on `main` only. Fork PRs have ⊥ secret.
- aarch64-linux built native on `ubuntu-24.04-arm` runner; ⊥ qemu, ⊥ cross.
- cachix cache = `pr0d1r2` (shared ∀ ecosystem repos).

## §I interfaces

- input (this repo): `nixpkgs-rust-lock.url = "github:pr0d1r2/nixpkgs-rust-lock"`, `nixpkgs.follows = "nixpkgs-rust-lock/nixpkgs"`
- flake: `packages.<sys>.hk` → hk 1.55.0 derivation
- flake: `packages.<sys>.default` ≡ `packages.<sys>.hk`
- flake: `overlays.default` → adds `pkgs.hk`
- flake: `checks.<sys>.hk` → build + test suite
- flake: `devShells.<sys>.default` → hk + nix gates from nixpkgs-rust-lock
- consumer (`itok`, `microlith`):
  ```nix
  inputs = {
    nixpkgs-rust-lock.url = "github:pr0d1r2/nixpkgs-rust-lock";
    nixpkgs.follows = "nixpkgs-rust-lock/nixpkgs";
    nix-hk.url = "github:pr0d1r2/nix-hk";
    nix-hk.inputs.nixpkgs-rust-lock.follows = "nixpkgs-rust-lock";
  };
  ```
- cachix: substituter `https://pr0d1r2.cachix.org`, key `pr0d1r2.cachix.org-1:<key>` — literal value read from cache at T11
- env: `CACHIX_AUTH_TOKEN` ! set in repo secrets (write token)
- cmd: `nix build .#hk` → `result/bin/hk`
- cmd: `nix run .#hk -- --version` → stdout `hk 1.55.0`
- cmd: `nix flake check` → exit 0
- ci: `.github/workflows/build.yml` matrix {ubuntu-24.04, ubuntu-24.04-arm, macos-14}

## §V invariants

- V1: `nix run .#hk -- --version` → contains `1.55.0`
- V2: ∀ sys ∈ {aarch64-darwin, x86_64-linux, aarch64-linux} → `packages.<sys>.hk` evals & builds
- V3: `srcHash` & `cargoHash` = real literal sha256. ⊥ `lib.fakeHash` on `main`
- V4: `flake.lock` committed & `nix flake check` pass in CI
- V5: cachix push ∀ sys on `main` push only. PR ⊥ push
- V6: consumer w/ substituter configured → hk fetched, ⊥ `building '/nix/store/...hk...drv'` in log
- V7: derivation asserts version at install (`versionCheckHook`) → mismatch = build fail, ⊥ silent wrong binary
- V8: ⊥ IFD, ⊥ `--impure`, ⊥ network in build phase
- V9: `doCheck = true`. Every skipped test listed in `checkFlags` w/ inline reason
- V10: push filter uploads own paths only; ⊥ mirror whole nixpkgs closure
- V11: ~~own pinned nixpkgs rev~~ superseded by V17, V18
- V12: ~~inputs ≡ {nixpkgs-lock}~~ superseded by V18
- V13: nixpkgs rev ≡ ∀ ecosystem repo (nixpkgs-lock, nixpkgs-rust-lock, nix-hk, consumers). CI assert equality; drift → fail loud, ⊥ silent cache miss
- V14: this repo ships hk only. Toolchain union ∉ here
- V15: ∀ ecosystem repo → push same cache `pr0d1r2`
- V16: ~~bump order lock→nix-hk→rust-lock→consumers~~ superseded by V22
- V17: rustc ∈ pinned nixpkgs ! ≥ 1.88.0. CI assert
- V18: `flake.nix` inputs ≡ {`nixpkgs-rust-lock`}. ⊥ direct nixpkgs URL, ⊥ nixpkgs-lock input, ⊥ 2nd input
- V19: `nixpkgs-rust-lock` ⊥ input nix-hk. Cycle guard. CI assert on both repos
- V20: ∀ pr0d1r2 Rust repo → same nixpkgs rev & same toolchain pkg set. Single bump entry = `nixpkgs-lock`
- V21: shared crate pins + MSRV declared once ∈ nixpkgs-rust-lock `lib.rustPins`; gate asserts ∀ repo `Cargo.toml` matches
- V22: bump order ! `nixpkgs-lock` → `nixpkgs-rust-lock` → `nix-hk` → consumers. Consumer refresh before upstream push = cold cache
- V23: declared systems ≡ 4 (incl `x86_64-darwin`). ≡ nixpkgs-lock set
- V24: `nix flake check`/eval ! pass ∀ 4. CI build+test+push ≡ tier-1 3. `x86_64-darwin` build ⊥ gated, ⊥ pushed — breakage there ⊥ block `main`
- V25: ⊥ silent tier-2 claim. README states `x86_64-darwin` = local-build, uncached
- V26: ∀ governed crate → version string ≡ `=X.Y.Z` exact. ⊥ `^`, ⊥ bare `"3"`, ⊥ range
- V27: sync script has `--check` mode; CI runs it. Drift ⊥ land even via hand-edit
- V28: `lib.rustPins` = sole writer of governed keys. Hand-edit of governed key in a repo `Cargo.toml` → gate fail, ⊥ silent win
- V29: governed set explicit & closed. Ungoverned dep (e.g. `ureq`) ⊥ touched by sync
- V30: exact-pin bump = autonomous loop's job. Stale pin blocking a dependent → loop raises PR, ⊥ human chase

## §T tasks

id|status|task|cites
T1|.|repo skeleton: `flake.nix`, `.gitignore`, `README.md`|V2
T2|.|`pkgs/hk/package.nix` from nixpkgs 1.54.0 recipe, bump tag `v1.55.0`|V1,V3
T3|.|resolve real `srcHash` (nix-prefetch github v1.55.0)|V3
T4|.|resolve real `cargoHash` (fakeHash → build → read expected)|V3
T5|.|darwin build: confirm libgit2/openssl link, fix apple frameworks if fail|V2
T6|.|flake outputs: packages, overlays.default, devShells, checks|I.flake,V2,V8
T7|.|`versionCheckHook` + `versionCheckProgramArg = "--version"`|V1,V7
T8|.|port `checkFlags` skip list (8 tests), revalidate ∀ against 1.55.0 suite|V9
T9|.|shell completions install (bash/fish/zsh) via `installShellFiles`|I.flake
T10|.|single input `nixpkgs-rust-lock` + `nixpkgs.follows`, commit `flake.lock`|V4,V18
T11|.|confirm cachix `pr0d1r2` exists, record pubkey, add `CACHIX_AUTH_TOKEN` secret|I.env,V15
T12|.|`.github/workflows/build.yml` 3-runner matrix, native builds|V2,V5
T13|.|cachix push step: `main` only, filter own paths|V5,V10
T14|.|`nix flake check` job in CI|V4
T15|.|`nixConfig` substituter + pubkey in own `flake.nix`|I.consumer
T16|.|README: pin graph + consumer wiring snippet (2 inputs)|V6,I.consumer
T17|.|verify cachix hit from clean store ∀ sys (`nix build --max-jobs 0`)|V6
T19|.|CI job: detect new hk tag upstream|—
T20|~|`nixpkgs-rust-lock` SPEC.md written → `../nixpkgs-rust-lock/SPEC.md`. Repo not created yet|V14,V20
T21|.|→ owned by nixpkgs-rust-lock §T (toolchain union, lib.rustPins, crons)|V14,V20
T22|.|cycle guard: CI assert nixpkgs-rust-lock ⊥ input nix-hk (both sides)|V19
T23|.|CI assert nixpkgs rev ≡ nixpkgs-lock rev|V13
T24|.|CI assert rustc ≥ 1.88.0 in pinned nixpkgs|V17
T25|.|bump-order runbook; wire into `pin-refresh` loop|V22
T26|.|itok migrate: drop rev `241313f4…`, 2 inputs, hk from nix-hk|V6,I.consumer
T27|.|microlith migrate: same|V6,I.consumer
T28|x|decided: declare 4 sys, CI/cache tier-1 3, `x86_64-darwin` tier-2 eval-only|V23,V24
T33|.|eval-only job: `nix eval .#packages.x86_64-darwin.hk.drvPath` ∀ CI, ⊥ build|V24
T34|.|README tier table: which sys cached, which built local|V25
T29|x|decided: Option B generate+assert, exact `=` pins, governed set v1|V21,V26,V27
T35|.|itok publish decision — exact registry pin blocked while path-dep|V26,?
T36|.|unify edition → `2024` (itok at `2021`)|V21
T37|.|fix drift: `blackbox` `microlith = "0.5"` → `=0.6.0`|V26,V28
T30|.|nix-hk devShell consumes nixpkgs-rust-lock gates, dogfoods own hk|I.flake,V20
T31|.|bootstrap: temp input `nixpkgs-lock` until nixpkgs-rust-lock repo live, then swap|V18,T20
T32|.|`update-pins.yml` cron `50 6 * * *` polling nixpkgs-rust-lock (pull model, ⊥ cross-repo token)|V22

## §B bugs

id|date|cause|fix
