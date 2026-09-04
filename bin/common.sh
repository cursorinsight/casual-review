# shellcheck shell=bash
# Shared helpers for casual-review shell entrypoints.

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "command not found: $1"
}

write_file_from_command() {
  local output=$1

  shift
  if ! "$@" >"$output"; then
    rm -f -- "$output"
    return 1
  fi
}

write_file_from_string() {
  local output=$1
  local content=$2

  if ! printf '%s' "$content" >"$output"; then
    rm -f -- "$output"
    return 1
  fi
}

replace_file_from_command() {
  local target=$1
  local tmp=$2

  shift 2
  write_file_from_command "$tmp" "$@" || return 1
  if ! mv -- "$tmp" "$target"; then
    rm -f -- "$tmp"
    return 1
  fi
}

replace_file_from_filter() {
  local target=$1
  local tmp=$2

  shift 2
  if ! "$@" <"$target" >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if ! mv -- "$tmp" "$target"; then
    rm -f -- "$tmp"
    return 1
  fi
}

apply_engine_overrides() {
  local engine=$1
  local model=$2
  local effort=$3

  if [[ -n "$model" ]]; then
    case "$engine" in
      codex)
        # shellcheck disable=SC2034
        CODEX_MODEL=$model
        ;;
      claude)
        # shellcheck disable=SC2034
        CLAUDE_MODEL=$model
        ;;
      antigravity)
        # shellcheck disable=SC2034
        ANTIGRAVITY_MODEL=$model
        ;;
    esac
  fi

  if [[ -n "$effort" ]]; then
    case "$engine" in
      codex)
        # shellcheck disable=SC2034
        CODEX_EFFORT=$effort
        ;;
      claude)
        # shellcheck disable=SC2034
        CLAUDE_EFFORT=$effort
        ;;
      antigravity)
        # shellcheck disable=SC2034
        ANTIGRAVITY_EFFORT=$effort
        ;;
    esac
  fi
}

strip_api_credit_env() {
  unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY
}

ENGINE_MODEL_ARGS=()
ENGINE_EFFORT_ARGS=()
ENGINE_EXTRA_ARGS=()

build_engine_arg_arrays() {
  local engine=$1
  local effort=
  local extra=
  local model=

  ENGINE_MODEL_ARGS=()
  ENGINE_EFFORT_ARGS=()
  ENGINE_EXTRA_ARGS=()

  case "$engine" in
    codex)
      model=${CODEX_MODEL:-}
      effort=${CODEX_EFFORT:-}
      extra=${CODEX_EXTRA_ARGS:-}
      if [[ -n "$effort" ]]; then
        # shellcheck disable=SC2034
        ENGINE_EFFORT_ARGS=(-c "model_reasoning_effort=\"$effort\"")
      fi
      ;;
    claude)
      model=${CLAUDE_MODEL:-}
      effort=${CLAUDE_EFFORT:-}
      extra=${CLAUDE_EXTRA_ARGS:-}
      if [[ -n "$effort" ]]; then
        # shellcheck disable=SC2034
        ENGINE_EFFORT_ARGS=(--effort "$effort")
      fi
      ;;
    antigravity)
      model=${ANTIGRAVITY_MODEL:-}
      effort=${ANTIGRAVITY_EFFORT:-}
      extra=${ANTIGRAVITY_EXTRA_ARGS:-}
      if [[ -n "$effort" ]]; then
        # shellcheck disable=SC2034
        ENGINE_EFFORT_ARGS=(--effort "$effort")
      fi
      ;;
    *)
      die "invalid engine: $engine"
      ;;
  esac

  if [[ -n "$model" ]]; then
    # shellcheck disable=SC2034
    ENGINE_MODEL_ARGS=(--model "$model")
  fi
  if [[ -n "$extra" ]]; then
    # shellcheck disable=SC2034
    read -r -a ENGINE_EXTRA_ARGS <<<"$extra"
  fi
}

GERRIT_URL_EFFECTIVE=${GERRIT_URL_EFFECTIVE:-}
CURL_AUTH_CONFIG=${CURL_AUTH_CONFIG:-}
CURL_AUTH_ARGS=()
CURL_TIMEOUT_ARGS=()

gerrit_cleanup_auth() {
  if [[ -n "${CURL_AUTH_CONFIG:-}" ]]; then
    rm -f -- "$CURL_AUTH_CONFIG"
    CURL_AUTH_CONFIG=
  fi
}

curl_config_escape() {
  local value=$1

  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

create_curl_auth_config() {
  local user=$1
  local password=$2
  local config

  case "$user$password" in
    *$'\n'*|*$'\r'*)
      die "Gerrit credentials must not contain newlines"
      ;;
  esac
  case "$user" in
    *:*)
      die "GERRIT_USER must not contain ':'"
      ;;
  esac

  gerrit_cleanup_auth
  config=$(mktemp) || die "failed to create temporary curl config"
  chmod 600 "$config" || {
    rm -f -- "$config"
    die "failed to restrict temporary curl config permissions"
  }

  if ! {
    printf 'user = "'
    curl_config_escape "$user"
    printf ':'
    curl_config_escape "$password"
    printf '"\n'
  } >"$config"; then
    rm -f -- "$config"
    die "failed to write temporary curl config"
  fi

  CURL_AUTH_CONFIG=$config
}

file_mode() {
  local file=$1

  if stat -c '%a' "$file" 2>/dev/null; then
    return 0
  fi
  stat -f '%Lp' "$file" 2>/dev/null
}

validate_curl_timeouts() {
  local connect_timeout=${GERRIT_CONNECT_TIMEOUT:-10}
  local max_time=${GERRIT_MAX_TIME:-120}

  [[ "$connect_timeout" =~ ^[1-9][0-9]*$ ]] ||
    die "GERRIT_CONNECT_TIMEOUT must be a positive integer"
  [[ "$max_time" =~ ^[1-9][0-9]*$ ]] ||
    die "GERRIT_MAX_TIME must be a positive integer"

  CURL_TIMEOUT_ARGS=(
    --connect-timeout "$connect_timeout"
    --max-time "$max_time"
  )
}

gerrit_validate_common_env() {
  local notify=${GERRIT_NOTIFY:-NONE}

  need jq
  case "$notify" in
    NONE|OWNER|OWNER_REVIEWERS|ALL) ;;
    *) die "GERRIT_NOTIFY must be NONE, OWNER, OWNER_REVIEWERS, or ALL" ;;
  esac
}

validate_common_env() {
  gerrit_validate_common_env
}

validate_gerrit_env() {
  local auth_type=${GERRIT_AUTH_TYPE:-basic}
  local password

  validate_common_env
  need curl
  [[ -n "${GERRIT_URL:-}" ]] || die "GERRIT_URL is required"
  [[ -n "${GERRIT_USER:-}" ]] || die "GERRIT_USER is required"
  password=${GERRIT_HTTP_PASSWORD:-${GERRIT_PASSWORD:-}}
  [[ -n "$password" ]] ||
    die "GERRIT_HTTP_PASSWORD or GERRIT_PASSWORD is required"

  GERRIT_URL_EFFECTIVE=${GERRIT_URL%/}
  case "$auth_type" in
    basic|digest) ;;
    *) die "GERRIT_AUTH_TYPE must be basic or digest" ;;
  esac
  validate_curl_timeouts
  create_curl_auth_config "$GERRIT_USER" "$password"
  unset GERRIT_HTTP_PASSWORD GERRIT_PASSWORD
  password=

  case "$auth_type" in
    basic)
      CURL_AUTH_ARGS=(--config "$CURL_AUTH_CONFIG")
      ;;
    digest)
      CURL_AUTH_ARGS=(--config "$CURL_AUTH_CONFIG" --digest)
      ;;
  esac
}

strip_xssi_file() {
  local file=$1
  local first

  IFS= read -r first <"$file" || return 0
  if [[ "$first" == ")]}'" ]]; then
    sed '1d' "$file"
  else
    cat "$file"
  fi
}

change_query() {
  local commit=$1
  local query

  query="commit:$commit"
  [[ -z "${GERRIT_PROJECT:-}" ]] || query+=" project:${GERRIT_PROJECT}"
  [[ -z "${GERRIT_BRANCH:-}" ]] || query+=" branch:${GERRIT_BRANCH}"
  [[ -z "${GERRIT_QUERY_EXTRA:-}" ]] || query+=" ${GERRIT_QUERY_EXTRA}"
  printf '%s' "$query"
}

gerrit_get_json() {
  local url=$1
  local output
  local status

  output=$(mktemp) || return 1
  if ! status=$(
    curl -sS -w '%{http_code}' -o "$output" \
      "${CURL_AUTH_ARGS[@]}" \
      "${CURL_TIMEOUT_ARGS[@]}" \
      -H 'Accept: application/json' \
      "$url"
  ); then
    rm -f "$output"
    return 1
  fi

  case "$status" in
    2*) ;;
    *)
      strip_xssi_file "$output" >&2
      rm -f "$output"
      return 1
      ;;
  esac
  strip_xssi_file "$output"
  rm -f "$output"
}

gerrit_query_changes() {
  local query=$1
  local output
  local status
  local url

  output=$(mktemp) || {
    warn "failed to create temporary Gerrit query response file"
    return 1
  }
  url="$GERRIT_URL_EFFECTIVE/a/changes/"
  if ! status=$(
    curl -sS -w '%{http_code}' -o "$output" \
      "${CURL_AUTH_ARGS[@]}" \
      "${CURL_TIMEOUT_ARGS[@]}" \
      -H 'Accept: application/json' \
      --get "$url" \
      --data-urlencode "q=$query" \
      --data-urlencode 'n=2' \
      --data-urlencode 'o=CURRENT_REVISION' \
      --data-urlencode 'pp=0'
  ); then
    rm -f "$output"
    warn "Gerrit change query failed for: $query"
    return 1
  fi

  case "$status" in
    2*) ;;
    *)
      warn "Gerrit change query returned HTTP $status for: $query"
      strip_xssi_file "$output" >&2
      rm -f "$output"
      return 1
      ;;
  esac
  strip_xssi_file "$output"
  rm -f "$output"
}

gerrit_find_change() {
  local commit=$1
  local query
  local json
  local count

  query=$(change_query "$commit")
  json=$(gerrit_query_changes "$query") || return 1
  if ! count=$(jq 'length' <<<"$json"); then
    warn "invalid Gerrit JSON response for query: $query"
    return 1
  fi
  if ((count == 0)); then
    warn "no Gerrit change found for query: $query"
    return 1
  fi
  if ((count > 1)); then
    warn "multiple Gerrit changes found for query: $query"
    warn "set GERRIT_PROJECT, GERRIT_BRANCH, or GERRIT_QUERY_EXTRA"
    return 1
  fi
  jq -r '.[0] | [._number, (.current_revision // "")] | @tsv' <<<"$json"
}

gerrit_list_comments() {
  local change_number=$1
  local revision=$2
  local url

  url="$GERRIT_URL_EFFECTIVE/a/changes/$change_number"
  url="$url/revisions/$revision/comments/"
  gerrit_get_json "$url" || {
    warn "Gerrit comment list failed for change $change_number"
    return 1
  }
}

gerrit_list_messages() {
  local change_number=$1
  local url

  url="$GERRIT_URL_EFFECTIVE/a/changes/$change_number/messages"
  gerrit_get_json "$url" || {
    warn "Gerrit message list failed for change $change_number"
    return 1
  }
}

gerrit_post_revision_review() {
  local change_number=$1
  local revision=$2
  local payload=$3
  local label=$4
  local output
  local payload_file
  local status
  local url

  output=$(mktemp) || {
    warn "failed to create temporary Gerrit $label response file"
    return 1
  }
  payload_file=$(mktemp) || {
    rm -f "$output"
    warn "failed to create temporary Gerrit $label payload file"
    return 1
  }
  if ! write_file_from_string "$payload_file" "$payload"; then
    rm -f "$output"
    warn "failed to write temporary Gerrit $label payload file"
    return 1
  fi
  url="$GERRIT_URL_EFFECTIVE/a/changes/$change_number"
  url="$url/revisions/$revision/review"

  if ! status=$(
    curl -sS -w '%{http_code}' -o "$output" \
      "${CURL_AUTH_ARGS[@]}" \
      "${CURL_TIMEOUT_ARGS[@]}" \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json; charset=UTF-8' \
      -X POST \
      --data-binary "@$payload_file" \
      "$url"
  ); then
    rm -f "$output" "$payload_file"
    warn "Gerrit $label POST failed for change $change_number"
    return 1
  fi

  rm -f "$payload_file"
  case "$status" in
    2*) ;;
    *)
      warn "Gerrit $label POST returned HTTP $status for change $change_number"
      strip_xssi_file "$output" >&2
      rm -f "$output"
      return 1
      ;;
  esac
  strip_xssi_file "$output" >/dev/null
  rm -f "$output"
}
