#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

# shellcheck source=../bin/common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/bin/common.sh"

tmp=
WARNINGS=0

cleanup() {
  gerrit_cleanup_auth
  if [[ -n "$tmp" ]]; then
    rm -rf -- "$tmp"
  fi
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf 'Warning: %s\n' "$*" >&2
}

trap cleanup EXIT

tmp=$(mktemp -d)

apply_engine_overrides codex codex-model xhigh
[[ "${CODEX_MODEL:-}" == codex-model ]] ||
  die "common test: codex model override failed"
[[ "${CODEX_EFFORT:-}" == xhigh ]] ||
  die "common test: codex effort override failed"

apply_engine_overrides claude claude-model high
[[ "${CLAUDE_MODEL:-}" == claude-model ]] ||
  die "common test: claude model override failed"
[[ "${CLAUDE_EFFORT:-}" == high ]] ||
  die "common test: claude effort override failed"

CLAUDE_EXTRA_ARGS='--extra value' build_engine_arg_arrays claude
[[ "${ENGINE_MODEL_ARGS[*]}" == "--model claude-model" ]] ||
  die "common test: claude model args failed"
[[ "${ENGINE_EFFORT_ARGS[*]}" == "--effort high" ]] ||
  die "common test: claude effort args failed"
[[ "${ENGINE_EXTRA_ARGS[*]}" == "--extra value" ]] ||
  die "common test: claude extra args failed"
ANTHROPIC_API_KEY=anthropic
OPENAI_API_KEY=openai
GOOGLE_API_KEY=google
GEMINI_API_KEY=gemini
strip_api_credit_env
[[ -z "${ANTHROPIC_API_KEY:-}${OPENAI_API_KEY:-}" ]] ||
  die "common test: API key env stripping failed"
[[ -z "${GOOGLE_API_KEY:-}${GEMINI_API_KEY:-}" ]] ||
  die "common test: Gemini API key env stripping failed"

query=$(
  GERRIT_PROJECT=project/name \
    GERRIT_BRANCH=main \
    GERRIT_QUERY_EXTRA='status:open' \
    change_query 0123456
)
expected_query="commit:0123456 project:project/name branch:main status:open"
[[ "$query" == "$expected_query" ]] ||
  die "common test: Gerrit query failed"

GERRIT_NOTIFY=OWNER validate_common_env
(
  GERRIT_NOTIFY=invalid validate_common_env
) >/dev/null 2>&1 &&
  die "common test: invalid Gerrit notify accepted"

create_curl_auth_config "reviewer" 'p"a\ss'
auth_config=$CURL_AUTH_CONFIG
auth_content=$(cat "$auth_config")
[[ "$auth_content" == 'user = "reviewer:p\"a\\ss"' ]] ||
  die "common test: curl auth config escaping failed"
auth_mode=$(file_mode "$auth_config") ||
  die "common test: curl auth config mode check failed"
[[ "$auth_mode" == 600 ]] ||
  die "common test: curl auth config mode is $auth_mode"
gerrit_cleanup_auth
[[ ! -e "$auth_config" ]] ||
  die "common test: curl auth config cleanup failed"

unset GERRIT_CONNECT_TIMEOUT GERRIT_MAX_TIME
validate_curl_timeouts
[[ "${CURL_TIMEOUT_ARGS[*]}" == "--connect-timeout 10 --max-time 120" ]] ||
  die "common test: default curl timeouts failed"
GERRIT_CONNECT_TIMEOUT=3 GERRIT_MAX_TIME=4 validate_curl_timeouts
[[ "${CURL_TIMEOUT_ARGS[*]}" == "--connect-timeout 3 --max-time 4" ]] ||
  die "common test: custom curl timeouts failed"
(
  GERRIT_CONNECT_TIMEOUT=0 validate_curl_timeouts
) >/dev/null 2>&1 &&
  die "common test: invalid connect timeout accepted"
(
  GERRIT_MAX_TIME=abc validate_curl_timeouts
) >/dev/null 2>&1 &&
  die "common test: invalid max-time accepted"

printf 'common test ok\n'
