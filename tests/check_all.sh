#!/usr/bin/env bash
set -u

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

cd "$ROOT_DIR" || exit 1
shopt -s nullglob

status=0
PASS_MARK=.
SKIP_MARK=s
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  PASS_MARK=$'\033[32m.\033[0m'
  SKIP_MARK=$'\033[33ms\033[0m'
fi

pass() {
  printf '%s' "$PASS_MARK"
  PASS_COUNT=$((PASS_COUNT + 1))
}

skip() {
  printf '%s' "$SKIP_MARK"
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

fail() {
  printf '\nFAIL: %s\n' "$*" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
  status=1
}

docker_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

tool_is_usable() {
  local tool=$1

  command -v "$tool" >/dev/null 2>&1 &&
    "$tool" --version >/dev/null 2>&1
}

run_docker_linter() {
  local image=$1
  local entrypoint=$2
  local path
  local result=0

  shift 2
  for path in "$@"; do
    if [[ -n "$entrypoint" ]]; then
      docker run --rm -i --entrypoint "$entrypoint" "$image" - \
        <"$path" || result=1
    else
      docker run --rm -i "$image" - <"$path" || result=1
    fi
  done

  return "$result"
}

run_linter() {
  local tool=$1
  local image=$2
  local entrypoint=$3

  shift 3
  if (( $# == 0 )); then
    printf '%s has no files to check' "$tool"
    return 2
  fi

  if tool_is_usable "$tool"; then
    "$tool" "$@"
    return
  fi

  if docker_available; then
    run_docker_linter "$image" "$entrypoint" "$@"
    return
  fi

  printf '%s not found and Docker daemon unavailable' "$tool"
  return 2
}

run_checked_linter() {
  local label=$1
  local tool=$2
  local image=$3
  local entrypoint=$4
  local output
  local result=0

  shift 4
  output=$(run_linter "$tool" "$image" "$entrypoint" "$@" 2>&1) ||
    result=$?
  if ((result == 0)); then
    pass "$label"
  elif ((result == 2)); then
    skip "$label"
  else
    fail "$label"
    [[ -z "$output" ]] || printf '%s\n' "$output" >&2
  fi
}

shellcheck_files=(
  bin/*
  lib/casual-review/*.sh
  libexec/casual-review/review
  libexec/casual-review/process
  libexec/casual-review/gerrit/*
  libexec/casual-review/github/*
  tests/*.sh
)
hadolint_files=(Dockerfile)

printf 'checks: '
run_checked_linter \
  "shellcheck" \
  shellcheck \
  koalaman/shellcheck:v0.10.0 \
  "" \
  "${shellcheck_files[@]}"

run_checked_linter \
  "hadolint" \
  hadolint \
  hadolint/hadolint:2.12.0 \
  /bin/hadolint \
  "${hadolint_files[@]}"

printf '\nSummary: %d passed, %d failed, %d skipped\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"

exit "$status"
