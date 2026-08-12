#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

cd "$ROOT_DIR"

tmp=

# shellcheck disable=SC2317
cleanup() {
  if [[ -n "$tmp" ]]; then
    rm -rf -- "$tmp"
  fi
}

trap cleanup EXIT

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

assert_grep() {
  local pattern=$1
  local file=$2
  local label=$3

  grep -F -- "$pattern" "$file" >/dev/null ||
    die "process test: missing $label"
}

run_process() {
  local engine=$1
  local log=$2

  shift 2
  MOCK_LOG=$log "$@" bin/process-reviews \
    --engine "$engine" \
    --reviews "$tmp/reviews" \
    --prompt "$tmp/process-prompt.md" >/dev/null
}

tmp=$(mktemp -d)
mkdir -p "$tmp/reviews"
cat >"$tmp/process-prompt.md" <<'EOF_PROMPT'
Process review prompt body.
EOF_PROMPT
cat >"$tmp/mock-engine" <<'EOF_MOCK'
#!/usr/bin/env bash
printf 'PWD=%s\n' "$PWD" >>"$MOCK_LOG"
i=0
for arg in "$@"; do
  printf 'ARG[%03d]=%s\n' "$i" "$arg" >>"$MOCK_LOG"
  i=$((i + 1))
done
EOF_MOCK
chmod 755 "$tmp/mock-engine"

bin/process-reviews --help >/dev/null ||
  die "process test: help failed"
if bin/process-reviews --engine >/dev/null 2>&1; then
  die "process test: --engine without value succeeded"
fi
if bin/process-reviews --unknown >/dev/null 2>&1; then
  die "process test: unknown option succeeded"
fi

codex_log=$tmp/codex.log
run_process codex "$codex_log" \
  env \
  CODEX_BIN="$tmp/mock-engine" \
  CODEX_MODEL=codex-model \
  CODEX_EFFORT=xhigh \
  CODEX_EXTRA_ARGS='--extra value'
assert_grep "ARG[000]=-C" "$codex_log" "codex cd flag"
assert_grep "ARG[002]=--sandbox" "$codex_log" "codex sandbox flag"
assert_grep "ARG[003]=workspace-write" "$codex_log" "codex sandbox"
assert_grep "ARG[004]=--model" "$codex_log" "codex model flag"
assert_grep "ARG[005]=codex-model" "$codex_log" "codex model"
assert_grep 'model_reasoning_effort="xhigh"' "$codex_log" "codex effort"
assert_grep "ARG[009]=$tmp/reviews" "$codex_log" "codex add-dir"
assert_grep "ARG[010]=--extra" "$codex_log" "codex extra flag"
assert_grep "ARG[011]=value" "$codex_log" "codex extra value"
assert_grep "Review directory: \`$tmp/reviews\`" "$codex_log" \
  "codex review dir"
assert_grep "Process review prompt body." "$codex_log" "codex prompt body"

claude_log=$tmp/claude.log
run_process claude "$claude_log" \
  env \
  CLAUDE_BIN="$tmp/mock-engine" \
  CLAUDE_MODEL=claude-model \
  CLAUDE_EFFORT=high \
  CLAUDE_EXTRA_ARGS='--extra value'
assert_grep "PWD=$ROOT_DIR" "$claude_log" "claude working directory"
assert_grep "ARG[000]=--model" "$claude_log" "claude model flag"
assert_grep "ARG[001]=claude-model" "$claude_log" "claude model"
assert_grep "ARG[002]=--effort" "$claude_log" "claude effort flag"
assert_grep "ARG[003]=high" "$claude_log" "claude effort"
assert_grep "ARG[004]=--extra" "$claude_log" "claude extra flag"
assert_grep "Review directory: \`$tmp/reviews\`" "$claude_log" \
  "claude review dir"

antigravity_log=$tmp/antigravity.log
run_process antigravity "$antigravity_log" \
  env \
  ANTIGRAVITY_BIN="$tmp/mock-engine" \
  ANTIGRAVITY_MODEL=ag-model \
  ANTIGRAVITY_EFFORT=medium \
  ANTIGRAVITY_EXTRA_ARGS='--dangerously-skip-permissions'
assert_grep "ARG[000]=--mode" "$antigravity_log" "antigravity mode flag"
assert_grep "ARG[001]=accept-edits" "$antigravity_log" "antigravity mode"
assert_grep "ARG[002]=--prompt-interactive" "$antigravity_log" \
  "antigravity prompt mode"
assert_grep "ARG[003]=--model" "$antigravity_log" "antigravity model flag"
assert_grep "ARG[004]=ag-model" "$antigravity_log" "antigravity model"
assert_grep "ARG[005]=--effort" "$antigravity_log" "antigravity effort flag"
assert_grep "ARG[006]=medium" "$antigravity_log" "antigravity effort"
assert_grep "ARG[008]=$tmp/reviews" "$antigravity_log" \
  "antigravity add-dir"
assert_grep "ARG[009]=--dangerously-skip-permissions" "$antigravity_log" \
  "antigravity extra"
assert_grep "Review directory: \`$tmp/reviews\`" "$antigravity_log" \
  "antigravity review dir"

printf 'process-reviews test ok\n'
