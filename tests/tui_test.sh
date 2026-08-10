#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2153
set -Eeuo pipefail

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

# shellcheck source=../bin/tui.sh
source "$ROOT_DIR/bin/tui.sh"

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

capture_fd9() {
  local output=$1

  shift
  "$@" 9>"$output"
}

script_supports_qec() {
  local output=$1

  command -v script >/dev/null 2>&1 || return 1
  script -qec true "$output" >/dev/null 2>&1
}

tmp=$(mktemp -d)
box_output=$tmp/box.out
status_output=$tmp/status.out
confirm_output=$tmp/confirm.out

TUI_COLS=44
TUI_RESET=
TUI_BOLD='<b>'
TUI_RED='<red>'
TUI_GREEN='<green>'
TUI_YELLOW='<yellow>'
TUI_BLUE='<blue>'
TUI_CYAN='<cyan>'
TUI_BORDER=

[[ "$(tui_width)" == 44 ]] || die "tui_width ignored TUI_COLS"
TUI_COLS=200
[[ "$(tui_width)" == 100 ]] || die "tui_width did not cap width"
TUI_COLS=10
[[ "$(tui_width)" == 30 ]] || die "tui_width did not floor width"
TUI_COLS=44

[[ "$(tui_repeat x 4)" == xxxx ]] || die "tui_repeat failed"
[[ "$(tui_truncate abcdef 4)" == a... ]] || die "tui_truncate failed"
[[ "$(tui_progress_bar 2 4)" == "[############------------] 2/4" ]] ||
  die "tui_progress_bar failed"

tui_label_split "The overall design is sound: keep prose intact."
[[ -z "$TUI_LABEL" ]] || die "tui_label_split matched prose"
tui_label_split "Server: https://example.invalid"
[[ "$TUI_LABEL" == "Server:" ]] || die "tui_label_split missed label"
[[ "$TUI_VALUE" == "https://example.invalid" ]] ||
  die "tui_label_split kept label spacing"
tui_label_split "**Confidence:** High"
[[ "$TUI_LABEL" == "Confidence:" ]] ||
  die "tui_label_split missed bold label"
[[ "$TUI_VALUE" == High ]] || die "tui_label_split missed bold value"
tui_label_split "**[AI/codex] Major:** Bad thing"
[[ "$TUI_LABEL" == "[AI/codex] Major:" ]] ||
  die "tui_label_split missed AI label"
[[ "$TUI_LABEL_COLOR" == "<yellow><b>" ]] ||
  die "tui_label_split missed severity color"

capture_fd9 "$box_output" \
  tui_box "Title" info \
    "Server: https://example.invalid"$'\n'"Comment: very-long-path-name"
grep -q '╭' "$box_output" || die "tui_box missing top border"
grep -q '│  <b><cyan>Server:' "$box_output" ||
  die "tui_box did not color label"
grep -q 'https://example.invalid' "$box_output" ||
  die "tui_box missing label value"
grep -q 'very-long-path-name' "$box_output" ||
  die "tui_box missing body text"

capture_fd9 "$status_output" prompt_status "WARNING: careful" warn
grep -q '<yellow><b>WARNING: careful' "$status_output" ||
  die "prompt_status did not color warning"

if script_supports_qec "$tmp/script-probe.out"; then
  cat >"$tmp/confirm.sh" <<'EOF_CONFIRM'
set -Eeuo pipefail
source "$ROOT_DIR/bin/tui.sh"
TUI_RESET=
TUI_BOLD='<b>'
TUI_RED='<red>'
TUI_GREEN='<green>'
exec 9<>/dev/tty
if confirm "Post this"; then
  printf 'status:0\n'
else
  printf 'status:1\n'
fi
exec 9>&-
EOF_CONFIRM
  printf 'maybe\ny\n' |
    env ROOT_DIR="$ROOT_DIR" \
    script -qec "bash $tmp/confirm.sh" "$confirm_output" >/dev/null
  grep -q 'Enter y or n.' "$confirm_output" ||
    die "confirm did not reject invalid answer"
  grep -q '<green><b>\[y\]' "$confirm_output" ||
    die "confirm did not color yes indicator"
  grep -q 'status:0' "$confirm_output" ||
    die "confirm did not accept y"
fi

printf 'tui test ok\n'
