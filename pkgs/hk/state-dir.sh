#!/usr/bin/env bash
# hk wrapper: keep hk's state in the repository's git dir (SPEC V36, V37).
#
# Upstream hk keeps all state in one global ~/.local/state/hk, shared by every
# repository on the machine: output.log is overwritten by whichever repo ran
# hk last, and stash backup patches rotate by cwd basename, so one repo can
# delete another's backups. Until upstream changes the default (jdx/hk#1703):
#
#   HK_STATE_DIR   -> <git-common-dir>/hk           patches, shared by worktrees
#   HK_OUTPUT_FILE -> <git-dir>/hk/output.log       one per checkout
#   HK_LOG_FILE    -> <git-dir>/hk/hk.log           one per checkout
#
# A non-empty value already in the environment wins. Outside a repository, or
# without git on PATH, nothing is set and hk keeps its own default. hk creates
# the directories itself.
set -euo pipefail

if dirs="$(git rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)"; then
  {
    read -r git_dir
    read -r common_dir
  } <<<"$dirs"
  export HK_STATE_DIR="${HK_STATE_DIR:-$common_dir/hk}"
  export HK_OUTPUT_FILE="${HK_OUTPUT_FILE:-$git_dir/hk/output.log}"
  export HK_LOG_FILE="${HK_LOG_FILE:-$git_dir/hk/hk.log}"
fi

exec "@hk@" "$@"
