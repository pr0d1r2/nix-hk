{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  installShellFiles,
  versionCheckHook,
  gitMinimal,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "hk";
  version = "1.55.0";

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "jdx";
    repo = "hk";
    tag = "v${finalAttrs.version}";
    hash = "sha256-2rZhRdEvt5cAC5TrWQocgMIWhuNnCBBpjKIDE5IGNUc=";
  };

  cargoHash = lib.fakeHash;

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
  nativeBuildInputs = [
    installShellFiles
  ];

  # Some tests build fixture repositories by shelling out to git.
  nativeCheckInputs = [ gitMinimal ];

  # Skipped upstream in both the nixpkgs recipe and hk's own default.nix: these
  # detect toolchains on the host or read ambient config, so they are not
  # meaningful in a sandbox.
  checkFlags = [
    "--skip=cli::init::detector::tests::test_detect_builtins_with_cargo_toml"
    "--skip=cli::init::detector::tests::test_detect_builtins_with_package_json"
    "--skip=cli::init::detector::tests::test_detect_eslint_with_contains"
    "--skip=cli::init::detector::tests::test_detect_shell_scripts"
    "--skip=cli::util::python_check_ast::tests::test_invalid_python"
    "--skip=settings::tests::test_settings_builder_fluent_api"
    "--skip=settings::tests::test_settings_from_config"
    "--skip=settings::tests::test_settings_snapshot_caching"
  ];

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
