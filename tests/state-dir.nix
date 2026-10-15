# Runs tests/state-dir.bats against the wrapper source (SPEC V36, V37).
{
  runCommand,
  bats,
  gitMinimal,
}:

runCommand "hk-state-dir-test"
  {
    nativeBuildInputs = [
      bats
      gitMinimal
    ];
    STATE_DIR_SH = ../pkgs/hk/state-dir.sh;
  }
  ''
    bats ${./state-dir.bats}
    touch $out
  ''
