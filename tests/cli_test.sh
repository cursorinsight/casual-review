#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)
CLI=$ROOT_DIR/bin/casual-review
tmp=$(mktemp -d)

cleanup() {
  rm -rf -- "$tmp"
}

trap cleanup EXIT

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

expect_status() {
  local expected=$1
  local actual=0

  shift
  "$@" >"$tmp/stdout" 2>"$tmp/stderr" || actual=$?
  [[ "$actual" == "$expected" ]] ||
    die "expected status $expected, got $actual from: $*"
}

expect_status 0 "$CLI" --help
grep -q '^  gerrit <command>' "$tmp/stdout" ||
  die "top-level help does not list Gerrit"
expect_status 0 "$CLI" gerrit --help
grep -q '^  upload ' "$tmp/stdout" ||
  die "Gerrit help does not list upload"

expect_status 2 "$CLI"
expect_status 2 "$CLI" unknown
expect_status 2 "$CLI" gerrit
expect_status 2 "$CLI" gerrit unknown

for command in \
  'review' \
  'process' \
  'gerrit export' \
  'gerrit upload' \
  'gerrit respond'; do
  # Intentional word splitting: command contains dispatcher path segments.
  # shellcheck disable=SC2086
  expect_status 0 "$CLI" $command --help
done

ln -s "$CLI" "$tmp/casual-review"
expect_status 0 "$tmp/casual-review" gerrit upload --help

expect_status 1 "$CLI" review --engine ''
expect_status 1 "$CLI" process --reviews ''
expect_status 1 "$CLI" gerrit export --limit ''
expect_status 1 "$CLI" gerrit upload --engine ''
expect_status 1 "$CLI" gerrit respond --limit ''

printf 'CLI test ok\n'
