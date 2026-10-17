#!/usr/bin/env bats
# pkgs/hk/state-dir.sh: hk keeps its state in the repository's git dir.
#
# The wrapper is tested against a stub in place of the real hk binary: the
# stub prints the three variables it was handed and its arguments, which is
# everything the wrapper is responsible for.

setup() {
  wrapper_src="${STATE_DIR_SH:-$BATS_TEST_DIRNAME/../pkgs/hk/state-dir.sh}"
  tmp="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"

  stub="$tmp/hk-real"
  cat >"$stub" <<'EOF'
#!/usr/bin/env bash
echo "state=${HK_STATE_DIR-<unset>}"
echo "output=${HK_OUTPUT_FILE-<unset>}"
echo "log=${HK_LOG_FILE-<unset>}"
echo "args=$*"
exit "${STUB_EXIT:-0}"
EOF
  chmod +x "$stub"

  wrapper="$tmp/hk"
  sed "s|@hk@|$stub|" "$wrapper_src" >"$wrapper"
  chmod +x "$wrapper"

  unset HK_STATE_DIR HK_OUTPUT_FILE HK_LOG_FILE
  export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$HOME"
  git config --global user.name test
  git config --global user.email test@example.invalid
  git config --global init.defaultBranch main

  repo="$tmp/repo"
  git init -q "$repo"
  git -C "$repo" commit -q --allow-empty -m init
}

@test "in a repository root: state, output and log go to .git/hk" {
  cd "$repo"
  run "$wrapper"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "state=$repo/.git/hk" ]
  [ "${lines[1]}" = "output=$repo/.git/hk/output.log" ]
  [ "${lines[2]}" = "log=$repo/.git/hk/hk.log" ]
}

@test "in a subdirectory: same paths as from the root" {
  mkdir -p "$repo/a/b"
  cd "$repo/a/b"
  run "$wrapper"
  [ "${lines[0]}" = "state=$repo/.git/hk" ]
  [ "${lines[1]}" = "output=$repo/.git/hk/output.log" ]
}

@test "in a linked worktree: patches shared with the repo, output and log per worktree" {
  git -C "$repo" worktree add -q "$tmp/wt" -b wt
  cd "$tmp/wt"
  run "$wrapper"
  [ "${lines[0]}" = "state=$repo/.git/hk" ]
  [ "${lines[1]}" = "output=$repo/.git/worktrees/wt/hk/output.log" ]
  [ "${lines[2]}" = "log=$repo/.git/worktrees/wt/hk/hk.log" ]
}

@test "explicit values win, each variable on its own" {
  cd "$repo"
  HK_STATE_DIR=/custom/state run "$wrapper"
  [ "${lines[0]}" = "state=/custom/state" ]
  [ "${lines[1]}" = "output=$repo/.git/hk/output.log" ]
  HK_OUTPUT_FILE=/custom/out.log run "$wrapper"
  [ "${lines[0]}" = "state=$repo/.git/hk" ]
  [ "${lines[1]}" = "output=/custom/out.log" ]
  HK_LOG_FILE=/custom/hk.log run "$wrapper"
  [ "${lines[2]}" = "log=/custom/hk.log" ]
}

@test "an empty value counts as unset" {
  cd "$repo"
  HK_STATE_DIR= run "$wrapper"
  [ "${lines[0]}" = "state=$repo/.git/hk" ]
}

@test "outside a repository: nothing is set, hk keeps its own default" {
  mkdir -p "$tmp/plain"
  cd "$tmp/plain"
  GIT_CEILING_DIRECTORIES="$tmp" run "$wrapper"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "state=<unset>" ]
  [ "${lines[1]}" = "output=<unset>" ]
  [ "${lines[2]}" = "log=<unset>" ]
}

@test "without git on PATH: nothing is set, hk still runs" {
  mkdir -p "$tmp/nogit"
  ln -s "$(command -v bash)" "$tmp/nogit/bash"
  cd "$repo"
  PATH="$tmp/nogit" run "$wrapper"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "state=<unset>" ]
}

@test "arguments pass through verbatim and the exit status comes back" {
  cd "$repo"
  STUB_EXIT=3 run "$wrapper" run pre-push --from-hook "a b"
  [ "$status" -eq 3 ]
  [ "${lines[3]}" = "args=run pre-push --from-hook a b" ]
}
