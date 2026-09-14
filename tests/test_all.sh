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

require_absent() {
  local path=$1

  if [[ ! -e "$path" ]]; then
    pass "$path is absent"
  else
    fail "$path still exists"
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
ln -s "$ROOT_DIR/bin/casual-review" "$tmp/casual-review"
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
require_readable lib/casual-review/tui.sh
require_readable lib/casual-review/common.sh
require_readable lib/casual-review/gerrit-upload.sh
require_readable browser/casual-review-upload-core.js
require_readable Makefile
require_readable package.json
require_readable package-lock.json
require_readable playwright/playwright.config.mjs
require_readable browser/casual-review-upload.js
require_readable browser/upload-gerrit-reviews.user.js
require_readable tests/browser/gerrit_upload.spec.mjs
require_executable bin/casual-review
require_executable libexec/casual-review/completion
require_executable libexec/casual-review/review
require_executable libexec/casual-review/process
require_executable libexec/casual-review/gerrit/export
require_executable libexec/casual-review/gerrit/upload
require_executable libexec/casual-review/gerrit/respond
require_absent bin/review-commits
require_absent bin/process-reviews
require_absent bin/export-gerrit-reviews
require_absent bin/upload-gerrit-reviews
require_absent bin/respond-gerrit-reviews
require_executable tests/check_all.sh
require_executable tests/test_all.sh
require_executable tests/cli_test.sh
require_executable tests/common_test.sh
require_executable tests/tui_test.sh
require_executable tests/gerrit_export_test.sh
require_executable tests/gerrit_browser_upload_test.sh
require_executable tests/process_test.sh
require_executable tests/review_test.sh
require_executable tests/gerrit_upload_test.sh
require_executable tests/gerrit_respond_test.sh
run_cmd "casual-review --help" bin/casual-review --help
run_cmd "casual-review review --help" bin/casual-review review --help
run_cmd "casual-review process --help" bin/casual-review process --help
run_cmd "casual-review completion --help" \
  bin/casual-review completion --help
run_cmd "casual-review gerrit --help" bin/casual-review gerrit --help
run_cmd "casual-review gerrit export --help" \
  bin/casual-review gerrit export --help
run_cmd "casual-review gerrit upload --help" \
  bin/casual-review gerrit upload --help
run_cmd "casual-review gerrit respond --help" \
  bin/casual-review gerrit respond --help
run_cmd "casual-review symlink --help" "$tmp/casual-review" --help
run_cmd "CLI tests" tests/cli_test.sh
run_cmd "common tests" tests/common_test.sh
run_cmd "tui tests" tests/tui_test.sh
run_cmd "browser artifacts are valid" \
  env GERRIT_LABELS_JSON="$labels_json" make check-browser-artifacts
run_cmd "Gerrit export tests" tests/gerrit_export_test.sh
run_cmd "Gerrit browser upload tests" tests/gerrit_browser_upload_test.sh
run_cmd "Gerrit browser E2E config syntax" \
  node --check playwright/playwright.config.mjs
run_cmd "Gerrit browser E2E test syntax" \
  node --check tests/browser/gerrit_upload.spec.mjs
run_cmd "process tests" tests/process_test.sh
run_cmd "review tests" tests/review_test.sh
run_cmd "Gerrit upload tests" tests/gerrit_upload_test.sh
run_cmd "Gerrit respond tests" tests/gerrit_respond_test.sh

if (( status == 0 )); then
  printf '\nAll tests passed.\n'
else
  printf '\nTests failed.\n' >&2
fi

exit "$status"
