# shellcheck shell=bash
# Shared parsing and payload helpers for Gerrit review uploads.

REVIEW_COMMIT=
REVIEW_SUBJECT=
REVIEW_ENGINE=
REVIEW_VERDICT=
REVIEW_JUSTIFICATION=
CURRENT_FILE=
COMMENT_PATHS=()
COMMENT_LINES=()
COMMENT_MESSAGES=()
COMMENT_SEVERITIES=()
COMMENT_TITLES=()
COMMENT_CONFIDENCES=()
COMMENT_ACTIONS=()
COMMENT_LOCATIONS=()
ACCEPT_COMMENTS=()
ACCEPT_JUDGEMENT=0

reset_review() {
  REVIEW_COMMIT=
  REVIEW_SUBJECT=
  REVIEW_ENGINE=
  REVIEW_VERDICT=
  REVIEW_JUSTIFICATION=
  COMMENT_PATHS=()
  COMMENT_LINES=()
  COMMENT_MESSAGES=()
  COMMENT_SEVERITIES=()
  COMMENT_TITLES=()
  COMMENT_CONFIDENCES=()
  COMMENT_ACTIONS=()
  COMMENT_LOCATIONS=()
  ACCEPT_COMMENTS=()
  ACCEPT_JUDGEMENT=0
}

append_justification_line() {
  local line=$1

  if [[ -z "$REVIEW_JUSTIFICATION" ]]; then
    REVIEW_JUSTIFICATION=$line
  else
    REVIEW_JUSTIFICATION+=$'\n'"$line"
  fi
}

append_finding_comment_line() {
  local line=$1

  if [[ -z "$FINDING_COMMENT" ]]; then
    FINDING_COMMENT=$line
  else
    FINDING_COMMENT+=$'\n'"$line"
  fi
}

parse_location_span() {
  local span=$1
  local path_line_re='^(.+):([0-9]+)([-,][0-9,-]*)?$'

  LOCATION_PATH=
  LOCATION_LINE=

  if [[ $span =~ $path_line_re ]]; then
    LOCATION_PATH=${BASH_REMATCH[1]}
    LOCATION_LINE=${BASH_REMATCH[2]}
    return 0
  fi

  case "$span" in
    */*|*.*)
      LOCATION_PATH=$span
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

parse_location_text() {
  local text=$1
  local rest=$1
  local span
  local fallback_re='([^[:space:],()]+):([0-9]+)'
  local line_hint_re='line[[:space:]]+([0-9]+)'

  PARSED_LOCATION_PATH=
  PARSED_LOCATION_LINE=

  while [[ $rest == *\`* ]]; do
    rest=${rest#*\`}
    [[ $rest == *\`* ]] || break
    span=${rest%%\`*}
    rest=${rest#"$span"}
    rest=${rest#\`}

    parse_location_span "$span" || continue
    if [[ -n "$LOCATION_LINE" ]]; then
      PARSED_LOCATION_PATH=$LOCATION_PATH
      PARSED_LOCATION_LINE=$LOCATION_LINE
      return 0
    fi
    if [[ -z "$PARSED_LOCATION_PATH" ]]; then
      PARSED_LOCATION_PATH=$LOCATION_PATH
    fi
  done

  if [[ -n "$PARSED_LOCATION_PATH" ]]; then
    if [[ $text =~ $line_hint_re ]]; then
      PARSED_LOCATION_LINE=${BASH_REMATCH[1]}
    fi
    return 0
  fi

  if [[ $text =~ $fallback_re ]]; then
    PARSED_LOCATION_PATH=${BASH_REMATCH[1]}
    PARSED_LOCATION_LINE=${BASH_REMATCH[2]}
    return 0
  fi

  return 1
}

finish_comment() {
  local idx

  if ((HAVE_FINDING == 0 || COMMENT_STORED == 1)); then
    return 0
  fi
  COMMENT_STORED=1

  if [[ -z "$FINDING_COMMENT" ]]; then
    warn "$CURRENT_FILE: skipping finding without suggested review comment"
    return 0
  fi
  if [[ -z "$FINDING_PATH" ]]; then
    warn "$CURRENT_FILE: skipping finding without usable location"
    return 0
  fi

  idx=${#COMMENT_PATHS[@]}
  COMMENT_PATHS[idx]=$FINDING_PATH
  COMMENT_LINES[idx]=$FINDING_LINE
  COMMENT_MESSAGES[idx]=$FINDING_COMMENT
  COMMENT_SEVERITIES[idx]=$FINDING_SEVERITY
  COMMENT_TITLES[idx]=$FINDING_TITLE
  COMMENT_CONFIDENCES[idx]=$FINDING_CONFIDENCE
  COMMENT_ACTIONS[idx]=$FINDING_ACTION
  COMMENT_LOCATIONS[idx]=$FINDING_LOCATION
}

start_finding() {
  FINDING_SEVERITY=$1
  FINDING_TITLE=$2
  FINDING_CONFIDENCE=
  FINDING_PATH=
  FINDING_LINE=
  FINDING_ACTION=
  FINDING_COMMENT=
  FINDING_LOCATION=
  HAVE_FINDING=1
  COMMENT_STORED=0
  COLLECT_COMMENT=0
}

parse_review_file() {
  local file=$1
  local line
  local in_findings=0
  local in_verdict=0
  local commit_re subject_re heading_re location_re
  local confidence_re action_re engine_re
  local location_text verdict_line

  reset_review
  CURRENT_FILE=$file
  REVIEW_ENGINE=$(basename "$(dirname -- "$file")")
  HAVE_FINDING=0
  COMMENT_STORED=0
  COLLECT_COMMENT=0
  FINDING_SEVERITY=
  FINDING_TITLE=
  FINDING_CONFIDENCE=
  FINDING_PATH=
  FINDING_LINE=
  FINDING_ACTION=
  FINDING_COMMENT=
  FINDING_LOCATION=

  commit_re="^(- )?Commit: \`([0-9A-Fa-f]{40})\`"
  subject_re='^- Subject: (.*)$'
  heading_re='^### \[([^]]+)\] (.*)$'
  location_re='^- Location: (.*)$'
  confidence_re='^- Confidence: (.*)$'
  action_re='^- (Gerrit action|Review action): (.*)$'
  engine_re='^_Engine: ([^[:space:]]+)'

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $line =~ $commit_re ]]; then
      REVIEW_COMMIT=$(printf '%s' "${BASH_REMATCH[2]}" | tr 'A-F' 'a-f')
      continue
    fi
    if [[ $line =~ $subject_re ]]; then
      REVIEW_SUBJECT=${BASH_REMATCH[1]}
      continue
    fi
    if [[ $line =~ $engine_re ]]; then
      REVIEW_ENGINE=${BASH_REMATCH[1]}
      continue
    fi

    case "$line" in
      "## Findings")
        in_findings=1
        in_verdict=0
        continue
        ;;
      "## Questions"|"## Positive observations")
        finish_comment
        in_findings=0
        in_verdict=0
        COLLECT_COMMENT=0
        continue
        ;;
      "## Review verdict")
        finish_comment
        in_findings=0
        in_verdict=1
        COLLECT_COMMENT=0
        continue
        ;;
      "---")
        finish_comment
        in_findings=0
        in_verdict=0
        COLLECT_COMMENT=0
        continue
        ;;
    esac

    if ((in_findings)); then
      if [[ $line =~ $heading_re ]]; then
        finish_comment
        start_finding "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        continue
      fi
      if ((HAVE_FINDING == 0)); then
        continue
      fi
      if ((COLLECT_COMMENT)); then
        if [[ $line == ">" ]]; then
          append_finding_comment_line ""
        elif [[ $line == "> "* ]]; then
          append_finding_comment_line "${line#> }"
        elif [[ -n "$line" ]]; then
          COLLECT_COMMENT=0
        fi
        continue
      fi
      if [[ $line =~ $confidence_re ]]; then
        FINDING_CONFIDENCE=${BASH_REMATCH[1]}
      elif [[ $line =~ $location_re ]]; then
        location_text=${BASH_REMATCH[1]}
        FINDING_LOCATION=$location_text
        if parse_location_text "$location_text"; then
          FINDING_PATH=$PARSED_LOCATION_PATH
          FINDING_LINE=$PARSED_LOCATION_LINE
        fi
      elif [[ $line =~ $action_re ]]; then
        FINDING_ACTION=${BASH_REMATCH[2]}
      elif [[ $line == "Suggested Gerrit comment:" ||
          $line == "Suggested review comment:" ]]; then
        COLLECT_COMMENT=1
      fi
      continue
    fi

    if ((in_verdict)); then
      verdict_line=${line#- }
      case "$verdict_line" in
        "Reject"|"Needs changes"|"LGTM")
          REVIEW_VERDICT=$verdict_line
          continue
          ;;
        "Looks good with minor comments")
          REVIEW_VERDICT=$verdict_line
          continue
          ;;
      esac
      if [[ -n "$REVIEW_VERDICT" && -n "$line" ]]; then
        append_justification_line "$line"
      fi
    fi
  done <"$file"

  finish_comment

  if [[ -z "$REVIEW_COMMIT" ]]; then
    warn "$file: skipping review without commit metadata"
    return 1
  fi
  return 0
}

comment_unresolved() {
  case "$1" in
    "Must fix"|"Should fix") printf 'true' ;;
    *) printf 'false' ;;
  esac
}

comment_location() {
  local i=$1

  if [[ -n "${COMMENT_LINES[$i]:-}" ]]; then
    printf '%s:%s' "${COMMENT_PATHS[$i]}" "${COMMENT_LINES[$i]}"
  else
    printf '%s' "${COMMENT_PATHS[$i]}"
  fi
}

format_comment() {
  local i=$1
  local msg title severity confidence action short location

  title=${COMMENT_TITLES[$i]:-}
  severity=${COMMENT_SEVERITIES[$i]:-}
  confidence=${COMMENT_CONFIDENCES[$i]:-}
  action=${COMMENT_ACTIONS[$i]:-}
  location=${COMMENT_LOCATIONS[$i]:-}
  short=${REVIEW_COMMIT:0:7}

  msg="**[AI/${REVIEW_ENGINE}] ${severity}:**"
  [[ -z "$title" ]] || msg+=" $title"
  [[ -z "$confidence" ]] || msg+=$'\n'"**Confidence:** $confidence"
  [[ -z "$action" ]] || msg+=$'\n'"**Action:** $action"
  [[ -z "$location" ]] || msg+=$'\n'"**Location:** $location"
  msg+=$'\n'"**Commit:** "
  msg+="$(printf '%s%s%s' '`' "$short" '`')"
  msg+=$'\n\n'"${COMMENT_MESSAGES[$i]}"
  printf '%s' "$msg"
}

normalize_text() {
  printf '%s' "$1" |
    tr '\n' ' ' |
    tr '[:upper:]' '[:lower:]' |
    sed 's/[`*]//g; s/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

message_matches() {
  local candidate=$1
  local expected=$2
  local title=$3
  local body=$4
  local candidate_norm
  local expected_first
  local expected_norm
  local title_norm
  local body_norm

  candidate_norm=$(normalize_text "$candidate")
  expected_first=${expected%%$'\n'*}
  expected_norm=$(normalize_text "$expected_first")
  title_norm=$(normalize_text "$title")
  body_norm=$(normalize_text "$body")

  [[ -n "$expected_norm" && "$candidate_norm" == *"$expected_norm"* ]] &&
    return 0
  [[ -n "$title_norm" && "$candidate_norm" == *"$title_norm"* ]] &&
    return 0
  [[ -n "$body_norm" && "$candidate_norm" == *"$body_norm"* ]] &&
    return 0
  return 1
}

initialize_acceptance() {
  local i=0

  ACCEPT_COMMENTS=()
  while ((i < ${#COMMENT_PATHS[@]})); do
    ACCEPT_COMMENTS[i]=1
    i=$((i + 1))
  done
  if [[ -n "$REVIEW_VERDICT" ]]; then
    ACCEPT_JUDGEMENT=1
  else
    ACCEPT_JUDGEMENT=0
  fi
}

selected_comment_count() {
  local i=0
  local count=0

  while ((i < ${#COMMENT_PATHS[@]})); do
    if [[ ${ACCEPT_COMMENTS[$i]:-0} == 1 ]]; then
      count=$((count + 1))
    fi
    i=$((i + 1))
  done
  printf '%s' "$count"
}

build_comments_json() {
  local comments_json='{}'
  local comment_json
  local i=0
  local line unresolved message

  while ((i < ${#COMMENT_PATHS[@]})); do
    if [[ ${ACCEPT_COMMENTS[$i]:-0} != 1 ]]; then
      i=$((i + 1))
      continue
    fi

    line=${COMMENT_LINES[$i]}
    unresolved=$(comment_unresolved "${COMMENT_ACTIONS[$i]:-}")
    message=$(format_comment "$i")
    if [[ -n "$line" ]]; then
      comment_json=$(
        jq -c -n \
          --arg message "$message" \
          --argjson line "$line" \
          --argjson unresolved "$unresolved" \
          '{line: $line, message: $message, unresolved: $unresolved}'
      ) || return 1
    else
      comment_json=$(
        jq -c -n \
          --arg message "$message" \
          --argjson unresolved "$unresolved" \
          '{message: $message, unresolved: $unresolved}'
      ) || return 1
    fi
    comments_json=$(
      jq -c \
        --arg path "${COMMENT_PATHS[$i]}" \
        --argjson comment "$comment_json" \
        '.[$path] = ((.[$path] // []) + [$comment])' \
        <<<"$comments_json"
    ) || return 1
    i=$((i + 1))
  done

  printf '%s' "$comments_json"
}

build_comments_array_json() {
  local comments_json='[]'
  local comment_json
  local i=0
  local line message unresolved

  while ((i < ${#COMMENT_PATHS[@]})); do
    if [[ ${ACCEPT_COMMENTS[$i]:-0} != 1 ]]; then
      i=$((i + 1))
      continue
    fi

    line=${COMMENT_LINES[$i]:-}
    message=$(format_comment "$i")
    unresolved=$(comment_unresolved "${COMMENT_ACTIONS[$i]:-}")
    if [[ -n "$line" ]]; then
      comment_json=$(
        jq -c -n \
          --arg path "${COMMENT_PATHS[$i]}" \
          --arg message "$message" \
          --arg title "${COMMENT_TITLES[$i]:-}" \
          --arg severity "${COMMENT_SEVERITIES[$i]:-}" \
          --arg confidence "${COMMENT_CONFIDENCES[$i]:-}" \
          --arg action "${COMMENT_ACTIONS[$i]:-}" \
          --arg location "${COMMENT_LOCATIONS[$i]:-}" \
          --arg body "${COMMENT_MESSAGES[$i]:-}" \
          --argjson line "$line" \
          --argjson unresolved "$unresolved" \
          '{
            path: $path,
            line: $line,
            unresolved: $unresolved,
            message: $message,
            title: $title,
            severity: $severity,
            confidence: $confidence,
            action: $action,
            location: $location,
            body: $body
          }'
      ) || return 1
    else
      comment_json=$(
        jq -c -n \
          --arg path "${COMMENT_PATHS[$i]}" \
          --arg message "$message" \
          --arg title "${COMMENT_TITLES[$i]:-}" \
          --arg severity "${COMMENT_SEVERITIES[$i]:-}" \
          --arg confidence "${COMMENT_CONFIDENCES[$i]:-}" \
          --arg action "${COMMENT_ACTIONS[$i]:-}" \
          --arg location "${COMMENT_LOCATIONS[$i]:-}" \
          --arg body "${COMMENT_MESSAGES[$i]:-}" \
          --argjson unresolved "$unresolved" \
          '{
            path: $path,
            unresolved: $unresolved,
            message: $message,
            title: $title,
            severity: $severity,
            confidence: $confidence,
            action: $action,
            location: $location,
            body: $body
          }'
      ) || return 1
    fi
    comments_json=$(
      jq -c --argjson comment "$comment_json" \
        '. + [$comment]' <<<"$comments_json"
    ) || return 1
    i=$((i + 1))
  done

  printf '%s' "$comments_json"
}

build_review_message() {
  local short
  local message

  if [[ "$ACCEPT_JUDGEMENT" != 1 || -z "$REVIEW_VERDICT" ]]; then
    printf ''
    return 0
  fi

  short=${REVIEW_COMMIT:0:7}
  message=$(review_message_marker "$REVIEW_ENGINE" "$short")
  [[ -z "$REVIEW_SUBJECT" ]] ||
    message+=$'\n'"**Subject:** $REVIEW_SUBJECT"
  message+=$'\n\n'"**Verdict:** $REVIEW_VERDICT"
  [[ -z "$REVIEW_JUSTIFICATION" ]] ||
    message+=$'\n\n'"$REVIEW_JUSTIFICATION"
  printf '%s' "$message"
}

review_message_marker() {
  local engine=$1
  local short=$2

  printf 'AI review from %s for %s' "$engine" "$short"
}

labels_for_verdict() {
  local verdict=$1

  if [[ -z "${GERRIT_LABELS_JSON:-}" || -z "$verdict" ]]; then
    printf '{}'
    return 0
  fi

  jq -c --arg verdict "$verdict" '
    .[$verdict] // {}
    | if type == "object" then . else error("label mapping is not object") end
  ' <<<"$GERRIT_LABELS_JSON"
}

build_review_json() {
  local comments_json=$1
  local labels_json=$2
  local message=$3
  local tag=${GERRIT_TAG:-autogenerated:casual-review}
  local notify=${GERRIT_NOTIFY:-NONE}

  jq -c -n \
    --arg tag "$tag" \
    --arg notify "$notify" \
    --arg message "$message" \
    --argjson comments "$comments_json" \
    --argjson labels "$labels_json" '
      {tag: $tag, notify: $notify, omit_duplicate_comments: true}
      + (if $message == "" then {} else {message: $message} end)
      + (if ($comments | length) == 0 then {} else {comments: $comments} end)
      + (if ($labels | length) == 0 then {} else {labels: $labels} end)
    '
}

build_review_export_json() {
  local file=$1
  local comments_json
  local labels_json
  local message
  local marker

  comments_json=$(build_comments_array_json) || return 1
  message=$(build_review_message) || return 1
  labels_json=$(labels_for_verdict "$REVIEW_VERDICT") || return 1
  marker=$(review_message_marker "$REVIEW_ENGINE" "${REVIEW_COMMIT:0:7}")

  jq -c -n \
    --arg file "$file" \
    --arg engine "$REVIEW_ENGINE" \
    --arg commit "$REVIEW_COMMIT" \
    --arg short "${REVIEW_COMMIT:0:7}" \
    --arg subject "$REVIEW_SUBJECT" \
    --arg verdict "$REVIEW_VERDICT" \
    --arg message "$message" \
    --arg marker "$marker" \
    --argjson labels "$labels_json" \
    --argjson comments "$comments_json" '
      {
        review_file: $file,
        engine: $engine,
        commit: $commit,
        commit_short: $short,
        subject: $subject,
        verdict: $verdict,
        message: $message,
        message_marker: $marker,
        labels: $labels,
        comments: $comments
      }
    '
}

validate_common_env() {
  gerrit_validate_common_env

  if [[ -n "${GERRIT_LABELS_JSON:-}" ]]; then
    jq -e 'type == "object"' >/dev/null <<<"$GERRIT_LABELS_JSON" ||
      die "GERRIT_LABELS_JSON must be a JSON object"
  fi
}

comment_already_posted() {
  local comments_json=$1
  local path=$2
  local line=$3
  local expected=$4
  local title=$5
  local body=$6
  local candidate
  local message

  while IFS= read -r candidate; do
    message=$(jq -r '.message // ""' <<<"$candidate")
    message_matches "$message" "$expected" "$title" "$body" && return 0
  done < <(
    jq -c --arg path "$path" --arg line "$line" '
      to_entries[] |
      select(.key == $path) |
      .value[] |
      select((.in_reply_to // "") == "") |
      select(
        ($line == "" and ((has("line") | not) or .line == 0)) or
        ($line != "" and ((.line // 0) | tostring) == $line)
      )
    ' <<<"$comments_json"
  )

  return 1
}

filter_duplicate_comments() {
  local comments_json=$1
  local i=0
  local line
  local expected

  while ((i < ${#COMMENT_PATHS[@]})); do
    if [[ ${ACCEPT_COMMENTS[$i]:-0} == 1 ]]; then
      line=${COMMENT_LINES[$i]:-}
      expected=$(format_comment "$i")
      if comment_already_posted \
          "$comments_json" \
          "${COMMENT_PATHS[$i]}" \
          "$line" \
          "$expected" \
          "${COMMENT_TITLES[$i]}" \
          "${COMMENT_MESSAGES[$i]}"; then
        ACCEPT_COMMENTS[i]=0
        DUPLICATE_COMMENTS=$((DUPLICATE_COMMENTS + 1))
      fi
    fi
    i=$((i + 1))
  done
}

review_message_already_posted() {
  local messages_json=$1
  local marker=$2
  local verdict=$3
  local tag=${GERRIT_TAG:-autogenerated:casual-review}

  jq -e \
    --arg tag "$tag" \
    --arg marker "$marker" \
    --arg verdict "$verdict" '
    [
      .[] |
      select((.tag // "") == $tag) |
      select((.message // "") | contains($marker)) |
      select((.message // "") | contains($verdict))
    ] | length > 0
  ' >/dev/null <<<"$messages_json"
}

gerrit_post_review() {
  local change_number=$1
  local revision=$2
  local payload=$3

  gerrit_post_revision_review "$change_number" "$revision" "$payload" review
}
