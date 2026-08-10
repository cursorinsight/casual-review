#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

# shellcheck source=../bin/respond-gerrit-reviews
# shellcheck disable=SC1091
source "$ROOT_DIR/bin/respond-gerrit-reviews"

tmp=

test_cleanup() {
  cleanup
  if [[ -n "$tmp" ]]; then
    rm -rf -- "$tmp"
  fi
}

trap test_cleanup EXIT

validate_common_env

tmp=$(mktemp -d)
reviews="$tmp/reviews"
mkdir -p "$reviews/codex"
review_file="$reviews/codex/001-0123456789ab.md"
empty_review_file="$reviews/codex/002-fedcba987654.md"
decisions="$tmp/DECISIONS.md"
cat >"$review_file" <<'EOF_REVIEW'
# Commit review

## Commit

- Commit: `0123456789abcdef0123456789abcdef01234567`
- Parent: `1111111111111111111111111111111111111111`
- Subject: Add response script

## Findings

### [Major] Validate input

- Confidence: High
- Location: `bin/tool:42`
- Introduced by this commit: Yes
- Gerrit action: Must fix

Suggested Gerrit comment:

> Please reject empty input before sending the request.

### [Minor] Update docs

- Confidence: Medium
- Location: `README.md`
- Introduced by this commit: Yes
- Gerrit action: Consider

Suggested Gerrit comment:

> Explain the new mode in the README.

## Questions

- Follow-up question?
EOF_REVIEW
cat >"$empty_review_file" <<'EOF_EMPTY_REVIEW'
# Commit review

## Commit

- Commit: `fedcba9876543210fedcba9876543210fedcba98`
- Parent: `1111111111111111111111111111111111111111`
- Subject: Empty review

## Findings

None.

## Questions

None.
EOF_EMPTY_REVIEW
cat >"$decisions" <<EOF_DECISIONS
## 2026-08-07T00:00:00Z - 0123456 - Validate input

- Review file: \`$review_file\`
- Reviewed commit: \`0123456\`
- Decision: Fix
- Fix commit: \`abcdef1\`
- Squash target: \`0123456\`
- Checks: \`shellcheck bin/tool\` passed
- Reasoning: Added guard.

## 2026-08-07T00:00:00Z - 0123456 - Follow-up question

- Review file: \`$review_file\`
- Reviewed commit: \`0123456\`
- Decision: Skip
- Fix commit: none
- Squash target: none
- Checks: not run: no checks recorded
- Reasoning: No uploaded inline comment exists.

## 2026-08-07T00:00:00Z - 0123456 - Update docs

- Review file: \`$review_file\`
- Reviewed commit: \`0123456\`
- Decision: Skip
- Fix commit: none
- Squash target: none
- Checks: not run: no checks recorded
- Reasoning: The README already explains the command.

## 2026-08-07T00:00:00Z - fedcba987654 - Empty review

- Review file: \`$empty_review_file\`
- Reviewed commit: \`fedcba9\`
- Decision: Skip
- Fix commit: none
- Squash target: none
- Checks: not run: no checks recorded
- Reasoning: Nothing should be uploaded.

## 2026-08-07T00:00:00Z - 222222222222 - Wrong commit

- Review file: \`$review_file\`
- Reviewed commit: \`2222222\`
- Decision: Skip
- Fix commit: none
- Squash target: none
- Checks: not run: no checks recorded
- Reasoning: Mismatched review files must not be posted.
EOF_DECISIONS

parse_decisions_file "$decisions"
[[ ${#DECISION_TITLES[@]} -eq 5 ]] ||
  die "respond test: decision count failed"
parse_review_file "$review_file" ||
  die "respond test: review parse failed"
[[ ${#COMMENT_PATHS[@]} -eq 2 ]] ||
  die "respond test: interleaved review comment count failed"
comment_index=$(
  matching_review_comment_index "${DECISION_TITLES[0]}" "$review_file"
) ||
  die "respond test: first comment matching failed"
[[ "$comment_index" == 0 ]] ||
  die "respond test: wrong first comment index"
if matching_review_comment_index \
    "${DECISION_TITLES[1]}" \
    "$review_file" >/dev/null;
then
  die "respond test: non-inline decision matched a comment"
fi
comment_index=$(
  matching_review_comment_index "${DECISION_TITLES[2]}" "$review_file"
) ||
  die "respond test: second comment matching failed"
[[ "$comment_index" == 1 ]] ||
  die "respond test: wrong second comment index"
parse_review_file "$empty_review_file" ||
  die "respond test: empty review parse failed"
((${#COMMENT_PATHS[@]} == 0)) ||
  die "respond test: empty review comment count failed"
parse_review_file "$review_file" ||
  die "respond test: review reparse failed"
comment_index=$(
  matching_review_comment_index "${DECISION_TITLES[0]}" "$review_file"
) ||
  die "respond test: comment matching failed"
[[ "$comment_index" == 0 ]] ||
  die "respond test: wrong comment index"

DRY_RUN_RESPONSES=0
DRY_RUN_CHANGE_MESSAGES=0
process_decision 1 >/dev/null ||
  die "respond test: non-inline decision processing failed"
process_decision 2 >/dev/null ||
  die "respond test: interleaved inline decision processing failed"
[[ "$DRY_RUN_CHANGE_MESSAGES" == 1 ]] ||
  die "respond test: non-inline decision not converted to change message"
[[ "$DRY_RUN_RESPONSES" == 1 ]] ||
  die "respond test: interleaved inline decision not matched"

expected=$(format_original_comment "$comment_index")
comments_json=$(
  jq -c -n \
    --arg message "${expected//\*\*/}" \
    '{"bin/tool": [{id: "abc123", line: 42, message: $message}]}'
)
find_remote_comment \
  "$comments_json" \
  "bin/tool" \
  "42" \
  "$expected" \
  "Validate input" \
  "Please reject empty input before sending the request." ||
  die "respond test: remote comment matching failed"
[[ "$MATCH_COMMENT_ID" == abc123 ]] ||
  die "respond test: remote comment id failed"

response=$(build_response_message 0)
payload=$(
  build_response_payload "bin/tool" "42" "abc123" "$response" false
)
jq -e '
  .comments["bin/tool"][0].in_reply_to == "abc123"
  and .comments["bin/tool"][0].unresolved == false
  and (.comments["bin/tool"][0].message | contains("**Decision:** Fix"))
  and (.comments["bin/tool"][0].message | contains("`abcdef1`"))
  and (.comments["bin/tool"][0].message | contains("`0123456`"))
  and (.comments["bin/tool"][0].message | contains("Added guard."))
' >/dev/null <<<"$payload" || die "respond test: response payload failed"

marker=$(decision_marker 1)
response=$(build_change_message 1 "$marker")
payload=$(build_change_message_payload "$response")
jq -e --arg marker "$marker" '
  (.message | contains($marker))
  and (.message | contains("**Reviewed commit:** `0123456`"))
  and (.message | contains("No uploaded inline comment exists."))
' >/dev/null <<<"$payload" ||
  die "respond test: change message payload failed"
change_message_exists \
  "$(jq -c -n --arg message "$response" '
    [{tag: "autogenerated:casual-review-response", message: $message}]
  ')" \
  "$marker" ||
  die "respond test: change message duplicate check failed"

IGNORED_NO_COMMENTS=0
process_decision 3 >/dev/null ||
  die "respond test: empty review decision processing failed"
[[ "$IGNORED_NO_COMMENTS" == 1 ]] ||
  die "respond test: empty review decision not ignored"

SKIPPED_DECISIONS=0
process_decision 4 >/dev/null 2>/dev/null ||
  die "respond test: mismatched commit processing failed"
[[ "$SKIPPED_DECISIONS" == 1 ]] ||
  die "respond test: mismatched commit not skipped"

printf 'respond-gerrit-reviews test ok\n'
