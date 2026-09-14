#!/usr/bin/env bash
set -u

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

cd "$ROOT_DIR" || exit 1

status=0
tmp=
labels_json='{"Needs changes":{"AI-Review":-1}}'

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

reject_cmd() {
  local name=$1

  shift
  if "$@" >/dev/null 2>&1; then
    fail "$name"
  else
    pass "$name"
  fi
}

section "Sanity"
tmp=$(mktemp -d) || exit 1
ln -s "$ROOT_DIR/bin/upload-gerrit-reviews" "$tmp/upload-gerrit-reviews"
ln -s "$ROOT_DIR/bin/respond-gerrit-reviews" "$tmp/respond-gerrit-reviews"
ln -s "$ROOT_DIR/bin/process-reviews" "$tmp/process-reviews"
ln -s "$ROOT_DIR/bin/export-gerrit-reviews" "$tmp/export-gerrit-reviews"
run_cmd "browser artifacts can be cleaned" make clean
run_cmd "browser artifacts can be generated" \
  env GERRIT_URL=https://example.com \
    GERRIT_LABELS_JSON="$labels_json" make browser-artifacts
reject_cmd "make login rejects missing GERRIT_URL" \
  env -u GERRIT_URL make login
reject_cmd "make userscript rejects missing GERRIT_URL" \
  env -u GERRIT_URL GERRIT_LABELS_JSON="$labels_json" make userscript
reject_cmd "browser E2E rejects missing GERRIT_URL" \
  env -u GERRIT_URL -u GERRIT_TEST_PROJECT \
    -u GERRIT_E2E_ALLOW_WRITES make test-gerrit-browser
reject_cmd "browser E2E rejects missing project" \
  env -u GERRIT_TEST_PROJECT -u GERRIT_E2E_ALLOW_WRITES \
    GERRIT_URL=https://example.com make test-gerrit-browser
reject_cmd "browser E2E rejects disabled writes" \
  env -u GERRIT_E2E_ALLOW_WRITES GERRIT_URL=https://example.com \
    GERRIT_TEST_PROJECT=test make test-gerrit-browser
require_readable bin/tui.sh
require_readable bin/common.sh
require_readable bin/gerrit-upload.sh
require_readable browser/casual-review-upload-core.js
require_readable Makefile
require_readable package.json
require_readable package-lock.json
require_readable playwright/playwright.config.mjs
require_readable browser/casual-review-upload.js
require_readable browser/upload-gerrit-reviews.user.js
require_readable tests/browser/gerrit_upload.spec.mjs
require_executable bin/review-commits
require_executable bin/process-reviews
require_executable bin/export-gerrit-reviews
require_executable bin/upload-gerrit-reviews
require_executable bin/respond-gerrit-reviews
require_executable tests/check_all.sh
require_executable tests/test_all.sh
require_executable tests/common_test.sh
require_executable tests/tui_test.sh
require_executable tests/export_gerrit_reviews_test.sh
require_executable tests/gerrit_browser_upload_test.sh
require_executable tests/process_reviews_test.sh
require_executable tests/review_commits_test.sh
require_executable tests/upload_gerrit_reviews_test.sh
require_executable tests/respond_gerrit_reviews_test.sh
run_cmd "review-commits --help" bin/review-commits --help
run_cmd "process-reviews --help" bin/process-reviews --help
run_cmd "export-gerrit-reviews --help" bin/export-gerrit-reviews --help
run_cmd "upload-gerrit-reviews --help" bin/upload-gerrit-reviews --help
run_cmd "respond-gerrit-reviews --help" bin/respond-gerrit-reviews --help
run_cmd "process-reviews symlink --help" "$tmp/process-reviews" --help
run_cmd "export-gerrit-reviews symlink --help" \
  "$tmp/export-gerrit-reviews" --help
run_cmd "upload-gerrit-reviews symlink --help" \
  "$tmp/upload-gerrit-reviews" --help
run_cmd "respond-gerrit-reviews symlink --help" \
  "$tmp/respond-gerrit-reviews" --help
run_cmd "common tests" tests/common_test.sh
run_cmd "tui tests" tests/tui_test.sh
run_cmd "browser artifacts are valid" \
  env GERRIT_LABELS_JSON="$labels_json" make check-browser-artifacts
run_cmd "export-gerrit-reviews tests" tests/export_gerrit_reviews_test.sh
run_cmd "Gerrit browser upload tests" tests/gerrit_browser_upload_test.sh
run_cmd "Gerrit browser E2E config syntax" \
  node --check playwright/playwright.config.mjs
run_cmd "Gerrit browser E2E test syntax" \
  node --check tests/browser/gerrit_upload.spec.mjs
run_cmd "process-reviews tests" tests/process_reviews_test.sh
run_cmd "review-commits tests" tests/review_commits_test.sh
run_cmd "upload-gerrit-reviews tests" tests/upload_gerrit_reviews_test.sh
run_cmd "respond-gerrit-reviews tests" tests/respond_gerrit_reviews_test.sh

if (( status == 0 )); then
  printf '\nAll tests passed.\n'
else
  printf '\nTests failed.\n' >&2
fi

exit "$status"
