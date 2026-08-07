#!/usr/bin/env bash
set -u

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

cd "$ROOT_DIR" || exit 1

status=0

section() {
  printf '\n== %s ==\n' "$*"
}

pass() {
  printf 'ok - %s\n' "$*"
}

fail() {
  printf 'not ok - %s\n' "$*" >&2
  status=1
}

require_executable() {
  local path=$1

  if [[ -x "$path" ]]; then
    pass "$path is executable"
  else
    fail "$path is not executable"
  fi
}

run_cmd() {
  local name=$1

  shift
  if "$@" >/dev/null; then
    pass "$name"
  else
    fail "$name"
  fi
}

section "Sanity"
require_executable bin/review-commits
require_executable bin/upload-gerrit-reviews
require_executable bin/respond-gerrit-reviews
require_executable tests/check_all.sh
require_executable tests/test_all.sh
run_cmd "review-commits --help" bin/review-commits --help
run_cmd "upload-gerrit-reviews --help" bin/upload-gerrit-reviews --help
run_cmd "upload-gerrit-reviews --self-test" \
  bin/upload-gerrit-reviews --self-test
run_cmd "respond-gerrit-reviews --help" bin/respond-gerrit-reviews --help
run_cmd "respond-gerrit-reviews --self-test" \
  bin/respond-gerrit-reviews --self-test

if (( status == 0 )); then
  printf '\nAll tests passed.\n'
else
  printf '\nTests failed.\n' >&2
fi

exit "$status"
