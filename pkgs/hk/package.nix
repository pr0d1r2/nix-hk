{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  installShellFiles,
  versionCheckHook,
  gitMinimal,
  cacert,
  usage,
  python3,
  pkl,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "hk";
  version = "2.7.0";

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "jdx";
    repo = "hk";
    tag = "v${finalAttrs.version}";
    hash = "sha256-nhEq3lYgJtI6K/rYSKILNxaBDX8Vu3n8je85iE95UKY=";
  };

  cargoHash = "sha256-jBMBhDUIPHLYMRLY2VBwgEDtXc1GgM4eShWmedS1ghY=";

  # No buildInputs by design (SPEC V33, V34). The upstream recipe carries
  # `libgit2` and `openssl`; both are inert and were measured to be so:
  #
  #   libgit2 -- git2 enables `vendored-libgit2`, and libgit2-sys 0.18.7+1.9.6
  #   requires `libgit2 >= 1.9.6, < 1.10.0`. The pinned nixpkgs ships 1.9.3 and
  #   nixpkgs master ships 1.9.4, so no system libgit2 can satisfy it. Nothing
  #   sets LIBGIT2_NO_VENDOR, so upstream already vendors silently. Setting it
  #   makes the build panic instead of linking.
  #
  #   openssl -- hk is rustls end to end (reqwest 0.13 / hyper-rustls). There is
  #   no openssl-sys in Cargo.lock and the built binary links neither libssl nor
  #   libcrypto.
  #
  # pkg-config goes with them: with nothing to probe it has nothing to do.
  #
  # `usage` is the one upstream input that survives measurement: `hk completion
  # <shell>` shells out to the `usage` binary at postInstall time. A plain
  # `cargo build` never reaches that, which is exactly how it looked droppable.
  #
  # `python3` and `pkl` generate `pkl/Builtins.pkl` and `pkl/builtins_meta.json`
  # before cargo runs. Upstream gitignores both (`mise run pkl:gen` makes them),
  # so the tag tarball has neither. Without them build.rs embeds an empty pkl
  # package, so hk fetches its own config schema over the network at run time,
  # and `BUILTINS_META` has no project indicators, so `hk init` detects nothing.
  # The build still succeeds; HK_REQUIRE_EMBEDDED_PKL makes it fail instead.
  nativeBuildInputs = [
    installShellFiles
    usage
    python3
    pkl
  ];

  env.HK_REQUIRE_EMBEDDED_PKL = "1";

  preBuild = ''
    python3 scripts/gen_builtins.py
  '';

  # Some tests build fixture repositories by shelling out to git. `cacert`
  # because tests that load a config build hk's HTTP client, and on Linux
  # rustls-platform-verifier fails with "failed to build HTTP client: builder
  # error" when the sandbox has no CA bundle (darwin uses the keychain).
  nativeCheckInputs = [
    gitMinimal
    cacert
  ];

  # The sandbox HOME is read-only, and hk's cache tests write under it. The
  # step_context tests call `Git::new()` on the current directory, which in
  # the sandbox is an unpacked tarball, not a repository.
  preCheck = ''
    export HOME="$(mktemp -d)"
    git init -q
  '';

  cargoBuildFlags = [
    "--bin"
    "hk"
  ];

  cargoTestFlags = [ "--all-features" ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd hk \
      --bash <($out/bin/hk completion bash) \
      --fish <($out/bin/hk completion fish) \
      --zsh <($out/bin/hk completion zsh)
  '';

  meta = {
    description = "Tool for managing git hooks";
    homepage = "https://hk.jdx.dev";
    changelog = "https://github.com/jdx/hk/blob/${finalAttrs.src.tag}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "hk";
  };
})
