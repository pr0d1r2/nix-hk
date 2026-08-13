# SPEC — nix-hk

## §G goal

Deliver current `hk` (v1.55.0) to **nixos 26.05** systems. 26.05 ships ⊥ hk (init landed master after branch-off) ∴ this repo IS the 26.05 hk provider.

Nix flake build for aarch64-darwin, x86_64-linux, aarch64-linux; push to cachix `pr0d1r2`; consumed prebuilt (`itok`, `microlith`, future, any 26.05 host), ⊥ local compile.

Built w/ rustc from same 26.05 pin (1.95.0) ∴ ∀ pr0d1r2 Rust repo → identical underlying deps, bumpable from **one** place (`nixpkgs-lock`).

## §C constraints

### upstream hk

- src: `github:jdx/hk` tag `v1.55.0` (tagged 2026-08-11).
- hk = Rust. `edition = 2024`, `rust-version = 1.88.0` → pinned rustc ! ≥ 1.88.0.
- pinned nixpkgs has **⊥ hk at all**. `hk: init at 1.48.0` landed nixpkgs master 2026-06-22, after `nixos-26.05` branch-off (~2026-05). `pkgs/by-name/hk/hk/package.nix` = 404 @ rev `9f78f44a`. Master recipe (1.54.0) = **template only**, ⊥ importable.
- build deps (master 1.54.0 recipe): nativeBuildInputs `pkg-config`, `installShellFiles`, `usage`; buildInputs `libgit2`, `openssl`; nativeCheckInputs `gitMinimal`. Two of those inert — see below.
- **libgit2 ! vendored.** `git2 = "0.21"` w/ feature `vendored-libgit2`; `libgit2-sys 0.18.7+1.9.6` demands `libgit2 >= 1.9.6, < 1.10.0`. Pin ships **1.9.3**, nixpkgs master **1.9.4** → system link IMPOSSIBLE both places. Upstream recipe's `buildInputs.libgit2` = vestigial; nothing sets `LIBGIT2_NO_VENDOR` ∴ nixpkgs already vendors, silently. Measured: `LIBGIT2_NO_VENDOR=1` → hard panic `no compatible system libgit2 could be found`.
- **openssl inert too.** hk `Cargo.lock` has ⊥ `openssl-sys`, ⊥ `native-tls`. TLS = rustls (`rustls-platform-verifier`, `hyper-rustls`, `reqwest 0.13`). Built binary: ⊥ dynamic `libgit2`/`libssl`/`libcrypto` (otool). `buildInputs.openssl` = cargo-cult, drop.
- **measured minimal build** (T40, aarch64-darwin): `cargo` + `rustc` alone → `cargo build --release --bin hk` succeeds, 2m30s. ⊥ `pkg-config`, ⊥ `cmake`, ⊥ `libgit2`, ⊥ `openssl`, ⊥ `usage` needed. `aws-lc-sys` (rustls provider, pulls `cmake 0.1.58` crate) builds via its `cc` path, ⊥ cmake binary.
- ∴ derivation inputs, settled by sandbox build: nativeBuildInputs `installShellFiles` + **`usage`**; nativeInstallCheckInputs `versionCheckHook`; nativeCheckInputs `gitMinimal`; buildInputs **∅**.
- `usage` looked droppable, is NOT. `hk completion bash|fish|zsh` execs `usage` binary @ postInstall → `installShellCompletion` wrote 3 zero-size files & aborted. Plain `cargo build` ⊥ reach postInstall ∴ minimal-build measurement missed it. Lesson: measure the phase, ⊥ the compile.
- build script = `build = "build/mod.rs"` (⊥ root `build.rs`). build-deps `codegen 0.3`, `indexmap 2`, `serde 1`, `serde_json 1`, `toml 1`. Ran offline ✓. Vendored libgit2 C source ships inside crate ∴ V8 holds.
- upstream hk ships own `default.nix` + `flake.nix` (unstable + flake-utils). Same 8-test skip list as nixpkgs recipe → T8 list corroborated by 2 sources. Same inert `libgit2`/`openssl`. ⊥ consume upstream flake: 2 extra inputs, unstable nixpkgs, breaks V18.

### pin graph

```
nixpkgs-lock ──> nix-hk ──┐
             └──> itok, microlith <┘
```

- `github:pr0d1r2/nixpkgs-lock` — exists. Tracks `nixos-26.05`, rev `9f78f44a87948854445dae0b6bf82b2e87e4efb5`, ~80 consumers, auto-bumped by hallucinogen `pin-refresh` loop. **Sole** pin authority.
- nixpkgs-lock = provider ∴ LEAF (its rule #17: provider ⊥ consume graph it feeds). 1 input, vendored guardrails.
- `nix-hk` (this repo) — **1 input**: `nixpkgs-lock`. `nixpkgs.follows = "nixpkgs-lock/nixpkgs"`. Mirrors nixpkgs-lock's anti-path-multiplicity rule (extra inputs → lock > 500KB).
- nix-hk ⊥ provider of nixpkgs ∴ leaf rule ⊥ apply here; consuming nixpkgs-lock is the intended edge.
- consumers (`itok`, `microlith`) — 2 inputs: `nixpkgs-lock` + `nix-hk`, latter `follows` former.
- ⊥ re-export of hk by nixpkgs-lock. Would close cycle nix-hk ↔ nixpkgs-lock → eval error + break leaf rule. Cost = consumers wire 2 inputs.
- cachix reuse ! same nixpkgs rev ∀ repos. Rev drift = different store path = silent miss.
- ~~`nixpkgs-rust-lock` intermediate layer~~ dead. ⊥ repo, ⊥ needed: 26.05 ships the toolchain directly.

### rust toolchain

- rustc ∈ pinned nixpkgs = **1.95.0** (`compilers/rust/1_95.nix` @ rev `9f78f44a`). Sole toolchain source ∀ fleet.
- ⊥ rust-overlay, ⊥ fenix, ⊥ `rust-toolchain.toml`, ⊥ 2nd nixpkgs input. One input, one closure.
- 1.95.0 ≥ 1.88.0 → hk MSRV satisfied (V17 holds).
- escape hatch, ⊥ paid now: if future rustc genuinely lands ahead of stable → rust-overlay as 2nd input w/ `nixpkgs.follows`.

### consumer toolchain drift (out-of-repo, tracked)

- `itok` & `microlith` declare `rust-version = "1.96"` today. Accident of old pin `241313f4` (rustc 1.96.1), ⊥ real floor — itok's own manifest cites evidenced floor `Option::is_none_or` = **1.82**.
- ∴ both → `rust-version = "1.95"`. Editions diverge: itok `2021`, microlith `2024` → unify `2024`.
- ⊥ push 1.96 into nixos-26.05: stable branch freezes major versions; 1.95→1.96 = mass rebuild, rejected outside security fixes.
- V20 fails loud until consumers move. Intended.
- crate-pin drift (`blackbox/Cargo.toml` pins `microlith = "0.5"`, local `0.6.0`) ∉ this repo. Governed pins → `set-and-setting` or accepted. Died with nixpkgs-rust-lock; problem outlives its mechanism.

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
- **`nixConfig` inert for untrusted users.** Measured: `nix build` warns `ignoring untrusted substituter 'https://pr0d1r2.cachix.org', you are not a trusted user` → builds from source, ⊥ error. Flake `nixConfig` ⊥ enough; consumer ! ∈ `trusted-users` ∈ `/etc/nix/nix.conf` (or substituter set system-wide). README ! say so, else V6 "fetched ⊥ built" fails silently on every fresh machine.

## §I interfaces

- input (this repo):
  ```nix
  inputs = {
    nixpkgs-lock.url = "github:pr0d1r2/nixpkgs-lock";
    nixpkgs.follows = "nixpkgs-lock/nixpkgs";
  };
  ```
- flake: `packages.<sys>.hk` → hk 1.55.0 derivation
- flake: `packages.<sys>.default` ≡ `packages.<sys>.hk`
- flake: `overlays.default` → adds `pkgs.hk`
- flake: `checks.<sys>.hk` → build + test suite
- flake: `devShells.<sys>.default` → hk + nix gates from pinned nixpkgs
- consumer (`itok`, `microlith`):
  ```nix
  inputs = {
    nixpkgs-lock.url = "github:pr0d1r2/nixpkgs-lock";
    nixpkgs.follows = "nixpkgs-lock/nixpkgs";
    nix-hk.url = "github:pr0d1r2/nix-hk";
    nix-hk.inputs.nixpkgs-lock.follows = "nixpkgs-lock";
  };
  ```
- cachix: substituter `https://pr0d1r2.cachix.org`, key `pr0d1r2.cachix.org-1:NfWjbhgAj41byXhCKiaE+av3Vnphm1fTezHXEGsiQIM=` (literal, read from nixpkgs-lock `flake.nix` `nixConfig`)
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
- V12: ~~inputs ≡ {nixpkgs-lock}~~ restored as V18
- V13: nixpkgs rev ≡ ∀ ecosystem repo (nixpkgs-lock, nix-hk, consumers). CI assert equality; drift → fail loud, ⊥ silent cache miss
- V14: this repo ships hk only. Toolchain pkgs ∉ here
- V15: ∀ ecosystem repo → push same cache `pr0d1r2`
- V16: ~~bump order lock→nix-hk→rust-lock→consumers~~ superseded by V22
- V17: rustc ∈ pinned nixpkgs ! ≥ 1.88.0. CI assert
- V18: `flake.nix` inputs ≡ {`nixpkgs-lock`}. ⊥ direct nixpkgs URL, ⊥ 2nd input
- V19: ~~nixpkgs-rust-lock ⊥ input nix-hk (cycle guard)~~ dead w/ that repo. Cycle prevention now = nixpkgs-lock's leaf rule #17, enforced there; nix-hk ⊥ provider ∴ ⊥ apply
- V20: ∀ pr0d1r2 Rust repo → same nixpkgs rev ∴ same toolchain. Toolchain = whatever pinned nixpkgs ships, ⊥ union repo. Single bump entry = `nixpkgs-lock`
- V21: ~~shared crate pins + MSRV ∈ lib.rustPins~~ dead w/ nixpkgs-rust-lock
- V22: bump order ! `nixpkgs-lock` → `nix-hk` → consumers (3 hops). Consumer refresh before upstream push = cold cache
- V23: declared systems ≡ 4 (incl `x86_64-darwin`). ≡ nixpkgs-lock set
- V24: `nix flake check`/eval ! pass ∀ 4. CI build+test+push ≡ tier-1 3. `x86_64-darwin` build ⊥ gated, ⊥ pushed — breakage there ⊥ block `main`
- V25: ⊥ silent tier-2 claim. README states `x86_64-darwin` = local-build, uncached
- V26: ~~governed crate → `=X.Y.Z`~~ dead w/ nixpkgs-rust-lock
- V27: ~~sync script `--check` in CI~~ dead w/ nixpkgs-rust-lock
- V28: ~~lib.rustPins sole writer~~ dead w/ nixpkgs-rust-lock
- V29: ~~governed set explicit & closed~~ dead w/ nixpkgs-rust-lock
- V30: ~~exact-pin bump = loop's job~~ dead w/ nixpkgs-rust-lock
- V31: rustc used ≡ rustc ∈ pinned nixpkgs (**1.95.x**). ⊥ rust-overlay, ⊥ fenix, ⊥ `rust-toolchain.toml`, ⊥ 2nd nixpkgs. CI assert exact minor
- V32: ∀ fleet Rust repo → `Cargo.toml` `rust-version` ≡ pinned rustc minor. Drift = gate fail. Nothing checked this before ∴ 1.96-vs-1.91 went unnoticed
- V33: libgit2 vendored. ⊥ `LIBGIT2_NO_VENDOR`, ⊥ `libgit2` ∈ buildInputs. If a future pin ships libgit2 satisfying `libgit2-sys` req, switching = deliberate change + measured, ⊥ assumed
- V34: `buildInputs`/`nativeBuildInputs` ≡ measured need. ∀ entry ! justified by a build failure without it. ⊥ copy upstream recipe unverified

## §T tasks

id|status|task|cites
T1|x|repo skeleton: `flake.nix`, `.gitignore`, `README.md`|V2
T2|x|`pkgs/hk/package.nix` from nixpkgs **master** 1.54.0 recipe (⊥ in pinned nixpkgs), bump tag `v1.55.0`, drop inert `libgit2`+`openssl` buildInputs|V1,V3,V33,V34
T3|x|resolve real `srcHash` (nix-prefetch github v1.55.0)|V3
T4|x|resolve real `cargoHash` (fakeHash → build → read expected)|V3
T5|x|aarch64-darwin builds clean. ⊥ apple frameworks needed, ⊥ libgit2/openssl in closure (0 refs). 65.0 MiB|V2,V33
T6|x|flake outputs: packages, overlays.default, devShells, checks|I.flake,V2,V8
T7|x|`versionCheckHook` + `versionCheckProgramArg = "--version"`|V1,V7
T8|x|skip list ported (corroborated by nixpkgs recipe + upstream `default.nix`). Sandbox run: 244 passed, 0 failed, 8 filtered|V9
T9|x|shell completions install (bash/fish/zsh) via `installShellFiles`|I.flake
T10|x|single input `nixpkgs-lock` + `nixpkgs.follows`, commit `flake.lock`|V4,V18
T11|~|cachix `pr0d1r2` pubkey recorded (§I). Left: confirm cache exists + add `CACHIX_AUTH_TOKEN` secret. `cachix` binary ⊥ installed locally|I.env,V15
T12|.|`.github/workflows/build.yml` 3-runner matrix, native builds|V2,V5
T13|.|cachix push step: `main` only, filter own paths|V5,V10
T14|.|`nix flake check` job in CI|V4
T15|x|`nixConfig` substituter + pubkey in own `flake.nix`|I.consumer
T16|.|README: pin graph + consumer wiring snippet (2 inputs)|V6,I.consumer
T17|.|verify cachix hit from clean store ∀ sys (`nix build --max-jobs 0`). ! consumer ∈ `trusted-users` first, else substituter silently ignored|V6
T19|.|CI job: detect new hk tag upstream|—
T20|x|dead: `nixpkgs-rust-lock` repo never created, layer removed|—
T21|x|dead w/ T20|—
T22|x|dead: cycle guard superseded by nixpkgs-lock leaf rule #17|V19
T23|.|CI assert nixpkgs rev ≡ nixpkgs-lock rev|V13
T24|.|CI assert rustc ≥ 1.88.0 in pinned nixpkgs|V17
T25|.|bump-order runbook (3 hops); wire into `pin-refresh` loop|V22
T26|.|itok migrate: drop rev `241313f4…`, 2 inputs, hk from nix-hk, `rust-version = "1.95"`, edition `2024`|V6,V32,I.consumer
T27|.|microlith migrate: same, `rust-version = "1.95"`|V6,V32,I.consumer
T28|x|decided: declare 4 sys, CI/cache tier-1 3, `x86_64-darwin` tier-2 eval-only|V23,V24
T33|.|eval-only job: `nix eval .#packages.x86_64-darwin.hk.drvPath` ∀ CI, ⊥ build|V24
T34|.|README tier table: which sys cached, which built local|V25
T29|x|decided: crate-pin governance ∉ this repo (→ set-and-setting or accepted drift)|—
T30|x|nix-hk devShell consumes pinned-nixpkgs gates, dogfoods own hk|I.flake,V20
T31|x|dead: bootstrap swap unneeded, `nixpkgs-lock` is the final input|V18
T32|.|`update-pins.yml` cron `50 6 * * *` polling nixpkgs-lock (pull model, ⊥ cross-repo token)|V22
T35|x|dead: itok publish decision was crate-pin governance|—
T36|x|dead as standalone; edition unify folded into T26|—
T37|x|dead: `blackbox` microlith drift ∉ this repo|—
T38|.|CI assert pinned rustc minor ≡ `1.95` exact|V31
T39|x|proved hk 1.55.0 + itok (`--all-features`) + microlith compile on rustc 1.95.0 (aarch64-darwin). `hk --version` → `hk 1.55.0`|V31,V32
T40|x|measured: cargo+rustc alone build hk. ⊥ cmake, ⊥ pkg-config, ⊥ libgit2, ⊥ openssl. Encoded §C|V34

## §B bugs

id|date|cause|fix
B1|2026-08-13|§C claimed "nixpkgs links system `libgit2`, keep that path". False: `libgit2-sys 0.18.7+1.9.6` needs `>= 1.9.6`, pin has 1.9.3, master 1.9.4 → vendored is only path. Would have shipped a derivation that ⊥ build|V33
B2|2026-08-13|§C listed `openssl` buildInput copied from upstream recipe. hk = rustls, ⊥ `openssl-sys` ∈ lock, binary links neither. Dead closure weight|V34
