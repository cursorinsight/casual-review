#!/usr/bin/env bash
set -u

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

cd "$ROOT_DIR" || exit 1

status=0
tmp=

# shellcheck disable=SC2317,SC2329
cleanup() {
  if [[ -n "$tmp" ]]; then
    rm -rf -- "$tmp"
  fi
}

trap cleanup EXIT

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

require_readable() {
  local path=$1

  if [[ -r "$path" ]]; then
    pass "$path is readable"
  else
    fail "$path is not readable"
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
tmp=$(mktemp -d) || exit 1
ln -s "$ROOT_DIR/bin/upload-gerrit-reviews" "$tmp/upload-gerrit-reviews"
ln -s "$ROOT_DIR/bin/respond-gerrit-reviews" "$tmp/respond-gerrit-reviews"
ln -s "$ROOT_DIR/bin/process-reviews" "$tmp/process-reviews"
require_readable bin/tui.sh
require_executable bin/review-commits
require_executable bin/process-reviews
require_executable bin/upload-gerrit-reviews
require_executable bin/respond-gerrit-reviews
require_executable tests/check_all.sh
require_executable tests/test_all.sh
require_executable tests/tui_test.sh
require_executable tests/process_reviews_test.sh
require_executable tests/upload_gerrit_reviews_test.sh
require_executable tests/respond_gerrit_reviews_test.sh
run_cmd "review-commits --help" bin/review-commits --help
run_cmd "process-reviews --help" bin/process-reviews --help
run_cmd "upload-gerrit-reviews --help" bin/upload-gerrit-reviews --help
run_cmd "respond-gerrit-reviews --help" bin/respond-gerrit-reviews --help
run_cmd "process-reviews symlink --help" "$tmp/process-reviews" --help
run_cmd "upload-gerrit-reviews symlink --help" \
  "$tmp/upload-gerrit-reviews" --help
run_cmd "respond-gerrit-reviews symlink --help" \
  "$tmp/respond-gerrit-reviews" --help
run_cmd "tui tests" tests/tui_test.sh
run_cmd "process-reviews tests" tests/process_reviews_test.sh
run_cmd "upload-gerrit-reviews tests" tests/upload_gerrit_reviews_test.sh
run_cmd "respond-gerrit-reviews tests" tests/respond_gerrit_reviews_test.sh

if (( status == 0 )); then
  printf '\nAll tests passed.\n'
else
  printf '\nTests failed.\n' >&2
fi

exit "$status"
