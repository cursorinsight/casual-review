#!/usr/bin/env bash
set -u

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

cd "$ROOT_DIR" || exit 1
shopt -s nullglob

status=0

section() {
  printf '\n== %s ==\n' "$*"
}

pass() {
  printf 'ok - %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

fail() {
  printf 'not ok - %s\n' "$*" >&2
  status=1
}

docker_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
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
    warn "$tool has no files to check; skipped"
    return 0
  fi

  if command -v "$tool" >/dev/null 2>&1; then
    "$tool" "$@"
    return
  fi

  if docker_available; then
    run_docker_linter "$image" "$entrypoint" "$@"
    return
  fi

  warn "$tool not found and Docker daemon unavailable; skipped"
  return 1
}

run_checked_linter() {
  local label=$1
  local tool=$2
  local image=$3
  local entrypoint=$4

  shift 4
  section "$label"
  if run_linter "$tool" "$image" "$entrypoint" "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

shellcheck_files=(bin/* tests/*.sh)
hadolint_files=(Dockerfile)

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

if (( status == 0 )); then
  printf '\nAll checks passed.\n'
else
  printf '\nChecks failed.\n' >&2
fi

exit "$status"
