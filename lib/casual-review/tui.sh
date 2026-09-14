# shellcheck shell=bash
# Shared terminal UI helpers.

TUI_COLS=${TUI_COLS:-80}
TUI_RESET=${TUI_RESET:-}
TUI_BOLD=${TUI_BOLD:-}
TUI_RED=${TUI_RED:-}
TUI_GREEN=${TUI_GREEN:-}
TUI_YELLOW=${TUI_YELLOW:-}
TUI_BLUE=${TUI_BLUE:-}
TUI_CYAN=${TUI_CYAN:-}
TUI_BORDER=${TUI_BORDER:-}
TUI_ACTIVE=${TUI_ACTIVE:-0}
TUI_LABEL=${TUI_LABEL:-}
TUI_LABEL_SEP=${TUI_LABEL_SEP:-}
TUI_LABEL_COLOR=${TUI_LABEL_COLOR:-}
TUI_VALUE=${TUI_VALUE:-}
TUI_TL=${TUI_TL:-╭}
TUI_TR=${TUI_TR:-╮}
TUI_BL=${TUI_BL:-╰}
TUI_BR=${TUI_BR:-╯}
TUI_L=${TUI_L:-├}
TUI_R=${TUI_R:-┤}
TUI_H=${TUI_H:-─}
TUI_V=${TUI_V:-│}

tui_setup() {
  local colors
  local cols

  if command -v tput >/dev/null 2>&1 &&
      [[ -n "${TERM:-}" && "${TERM:-}" != dumb ]]; then
    cols=$(tput cols 2>/dev/null || printf '80')
    [[ "$cols" =~ ^[0-9]+$ ]] && TUI_COLS=$cols

    colors=$(tput colors 2>/dev/null || printf '0')
    if [[ -z "${NO_COLOR:-}" &&
        "$colors" =~ ^[0-9]+$ &&
        "$colors" -ge 8 ]]; then
      TUI_RESET=$(tput sgr0 2>/dev/null || printf '')
      TUI_BOLD=$(tput bold 2>/dev/null || printf '')
      TUI_RED=$(tput setaf 1 2>/dev/null || printf '')
      TUI_GREEN=$(tput setaf 2 2>/dev/null || printf '')
      TUI_YELLOW=$(tput setaf 3 2>/dev/null || printf '')
      TUI_BLUE=$(tput setaf 4 2>/dev/null || printf '')
      TUI_CYAN=$(tput setaf 6 2>/dev/null || printf '')
      TUI_BORDER=$TUI_BLUE
    fi
  fi
}

tui_width() {
  local width=$TUI_COLS

  ((width > 100)) && width=100
  ((width < 30)) && width=30
  printf '%s' "$width"
}

tui_repeat() {
  local char=$1
  local count=$2
  local i=0

  while ((i < count)); do
    printf '%s' "$char"
    i=$((i + 1))
  done
}

tui_truncate() {
  local text=$1
  local limit=$2
  local keep

  if ((${#text} <= limit)); then
    printf '%s' "$text"
  elif ((limit <= 3)); then
    printf '%s' "${text:0:limit}"
  else
    keep=$((limit - 3))
    printf '%s...' "${text:0:keep}"
  fi
}

tui_severity_color() {
  case "$1" in
    Critical|CRITICAL) printf '%s' "$TUI_RED$TUI_BOLD" ;;
    Major|MAJOR) printf '%s' "$TUI_YELLOW$TUI_BOLD" ;;
    Minor|MINOR) printf '%s' "$TUI_CYAN" ;;
    good) printf '%s' "$TUI_GREEN$TUI_BOLD" ;;
    warn) printf '%s' "$TUI_YELLOW$TUI_BOLD" ;;
    *) printf '%s' "$TUI_BLUE$TUI_BOLD" ;;
  esac
}

tui_label_split() {
  local text=$1
  local labels_re
  local label_re
  local bold_label_re
  local ai_re='^(\[AI/[^]]+\][[:space:]]+([A-Za-z]+):)(.*)$'
  local bold_ai_re='^\*\*(\[AI/[^]]+\][[:space:]]+([A-Za-z]+):)\*\*(.*)$'

  labels_re='Action|Change message|Change messages matched'
  labels_re+='|Change messages posted|Checks|Comment|Commit'
  labels_re+='|Confidence|Decision|Decision key|Decisions file'
  labels_re+='|Decisions ignored|Decisions parsed|Decisions skipped'
  labels_re+='|Directory'
  labels_re+='|Dry-run change messages|Dry-run payloads'
  labels_re+='|Dry-run responses|Duplicate change messages'
  labels_re+='|Duplicate comments|Duplicate messages|Engine|Failures'
  labels_re+='|File|Fix commit|Inline comments|Inline responses matched'
  labels_re+='|Labels|Location|Message|Mode|Notify|Progress'
  labels_re+='|Response|Responses posted|Resolved|Review file'
  labels_re+='|Reviewed commit|Reviews|Reviews parsed|Reviews posted'
  labels_re+='|Reviews skipped|Server|Squash target|Subject|Tag|Title'
  labels_re+='|Verdict|Warnings'
  label_re="^(${labels_re}):(.*)$"
  bold_label_re="^\\*\\*(${labels_re}):\\*\\*(.*)$"

  TUI_LABEL=
  TUI_LABEL_SEP=
  TUI_LABEL_COLOR=$TUI_BOLD$TUI_CYAN
  TUI_VALUE=$text
  if [[ $text =~ $bold_ai_re ]]; then
    TUI_LABEL=${BASH_REMATCH[1]}
    TUI_LABEL_COLOR=$(tui_severity_color "${BASH_REMATCH[2]}")
    TUI_VALUE=${BASH_REMATCH[3]}
  elif [[ $text =~ $ai_re ]]; then
    TUI_LABEL=${BASH_REMATCH[1]}
    TUI_LABEL_COLOR=$(tui_severity_color "${BASH_REMATCH[2]}")
    TUI_VALUE=${BASH_REMATCH[3]}
  elif [[ $text =~ $bold_label_re ]]; then
    TUI_LABEL=${BASH_REMATCH[1]}:
    TUI_VALUE=${BASH_REMATCH[2]}
  elif [[ $text =~ $label_re ]]; then
    TUI_LABEL=${BASH_REMATCH[1]}:
    TUI_VALUE=${BASH_REMATCH[2]}
  fi
  if [[ -n "$TUI_LABEL" ]]; then
    TUI_VALUE=${TUI_VALUE# }
    [[ -n "$TUI_VALUE" ]] && TUI_LABEL_SEP=' '
  fi
}

tui_box_rule() {
  local width=$1
  local left=$2
  local right=$3

  printf '%s%s' "$TUI_BORDER" "$left" >&9
  tui_repeat "$TUI_H" $((width - 2)) >&9
  printf '%s%s\n' "$right" "$TUI_RESET" >&9
}

tui_box_line() {
  local text=$1
  local width=$2
  local content_width=$((width - 6))
  local chunk
  local piece
  local pad
  local first=1
  local label_len=0
  local label_sep_len=0
  local line_width
  local prefix_width=0
  local fold_width

  tui_label_split "$text"
  if [[ -n "$TUI_LABEL" ]]; then
    label_len=${#TUI_LABEL}
    label_sep_len=${#TUI_LABEL_SEP}
    prefix_width=$((label_len + label_sep_len))
  fi
  fold_width=$((content_width - prefix_width))
  ((fold_width < 10)) && fold_width=$content_width

  if [[ -z "$text" ]]; then
    printf '%s%s%s  %*s  %s%s%s\n' \
      "$TUI_BORDER" "$TUI_V" "$TUI_RESET" "$content_width" "" \
      "$TUI_BORDER" "$TUI_V" \
      "$TUI_RESET" >&9
    return 0
  fi

  if command -v fold >/dev/null 2>&1; then
    printf '%s\n' "$TUI_VALUE" | fold -s -w "$fold_width" |
      while IFS= read -r chunk || [[ -n "$chunk" ]]; do
        while ((${#chunk} > content_width)); do
          piece=${chunk:0:content_width}
          chunk=${chunk:content_width}
          printf '%s%s%s  %s  %s%s%s\n' \
            "$TUI_BORDER" "$TUI_V" "$TUI_RESET" "$piece" \
            "$TUI_BORDER" "$TUI_V" "$TUI_RESET" >&9
        done
        line_width=${#chunk}
        if ((first)); then
          line_width=$((line_width + label_len + label_sep_len))
        elif ((label_len > 0 && fold_width != content_width)); then
          line_width=$((line_width + label_len + label_sep_len))
        fi
        pad=$((content_width - line_width))
        ((pad < 0)) && pad=0
        if ((first && label_len > 0)); then
          printf '%s%s%s  %s%s%s%s%*s  %s%s%s\n' \
            "$TUI_BORDER" "$TUI_V" "$TUI_RESET" "$TUI_LABEL_COLOR" \
            "$TUI_LABEL" "$TUI_RESET" "$TUI_LABEL_SEP$chunk" \
            "$pad" "" "$TUI_BORDER" "$TUI_V" "$TUI_RESET" >&9
        elif ((label_len > 0 && fold_width != content_width)); then
          printf '%s%s%s  %*s%s%*s  %s%s%s\n' \
            "$TUI_BORDER" "$TUI_V" "$TUI_RESET" "$prefix_width" "" \
            "$chunk" "$pad" "" "$TUI_BORDER" "$TUI_V" "$TUI_RESET" >&9
        else
          printf '%s%s%s  %s%*s  %s%s%s\n' \
            "$TUI_BORDER" "$TUI_V" "$TUI_RESET" "$chunk" \
            "$pad" "" "$TUI_BORDER" "$TUI_V" "$TUI_RESET" >&9
        fi
        first=0
      done
  else
    if ((label_len > 0)); then
      chunk=$(tui_truncate "$TUI_VALUE" "$fold_width")
      pad=$((content_width - label_len - label_sep_len - ${#chunk}))
      ((pad < 0)) && pad=0
      printf '%s%s%s  %s%s%s%s%*s  %s%s%s\n' \
        "$TUI_BORDER" "$TUI_V" "$TUI_RESET" "$TUI_LABEL_COLOR" \
        "$TUI_LABEL" "$TUI_RESET" "$TUI_LABEL_SEP$chunk" "$pad" "" \
        "$TUI_BORDER" "$TUI_V" "$TUI_RESET" >&9
      return 0
    fi
    chunk=$(tui_truncate "$text" "$content_width")
    pad=$((content_width - ${#chunk}))
    ((pad < 0)) && pad=0
    printf '%s%s%s  %s%*s  %s%s%s\n' \
      "$TUI_BORDER" "$TUI_V" "$TUI_RESET" "$chunk" "$pad" "" \
      "$TUI_BORDER" "$TUI_V" "$TUI_RESET" >&9
  fi
}

tui_box() {
  local title=$1
  local severity=$2
  local body=$3
  local width
  local content_width
  local color
  local line
  local pad

  width=$(tui_width)
  content_width=$((width - 6))
  title=$(tui_truncate "$title" "$content_width")
  color=$(tui_severity_color "$severity")
  pad=$((content_width - ${#title}))
  ((pad < 0)) && pad=0

  printf '\n' >&9
  tui_box_rule "$width" "$TUI_TL" "$TUI_TR"
  printf '%s%s%s  %s%s%s%*s  %s%s%s\n' \
    "$TUI_BORDER" "$TUI_V" "$TUI_RESET" "$color" "$title" \
    "$TUI_RESET" "$pad" "" "$TUI_BORDER" "$TUI_V" \
    "$TUI_RESET" >&9
  tui_box_rule "$width" "$TUI_L" "$TUI_R"
  while IFS= read -r line || [[ -n "$line" ]]; do
    tui_box_line "$line" "$width"
  done <<<"$body"
  tui_box_rule "$width" "$TUI_BL" "$TUI_BR"
}

tui_progress_bar() {
  local current=$1
  local total=$2
  local width=24
  local filled=0
  local empty

  if ((total > 0)); then
    filled=$((current * width / total))
  fi
  empty=$((width - filled))
  printf '['
  tui_repeat '#' "$filled"
  tui_repeat '-' "$empty"
  printf '] %s/%s' "$current" "$total"
}

prompt_status() {
  local text=$1
  local kind=$2
  local color

  color=$(tui_severity_color "$kind")
  printf '%s%s%s\n' "$color" "$text" "$TUI_RESET" >&9
}

confirm() {
  local prompt=$1
  local answer

  prompt=${prompt%\?}
  while true; do
    printf '%s? %s[y]%s post / %s[N]%s skip: ' \
      "$prompt" "$TUI_GREEN$TUI_BOLD" "$TUI_RESET" \
      "$TUI_RED$TUI_BOLD" "$TUI_RESET" >&9
    IFS= read -r answer <&9 || return 1
    case "$answer" in
      y|Y|yes|YES)
        return 0
        ;;
      ""|n|N|no|NO)
        return 1
        ;;
      *)
        prompt_status "Enter y or n." warn
        ;;
    esac
  done
}
