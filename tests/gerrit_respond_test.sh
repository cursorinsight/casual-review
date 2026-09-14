#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

export CASUAL_REVIEW_ROOT=$ROOT_DIR
# shellcheck source=../libexec/casual-review/gerrit/respond
# shellcheck disable=SC1091
source "$ROOT_DIR/libexec/casual-review/gerrit/respond"

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

mkdir -p "$tmp/ai-reviews"
cp -- "$decisions" "$tmp/ai-reviews/DECISIONS.md"
(
  cd "$tmp"
"$ROOT_DIR/bin/casual-review" gerrit respond --dry-run >/dev/null 2>&1
) || die "respond test: default review and decisions paths failed"
if (
  cd "$tmp"
"$ROOT_DIR/bin/casual-review" gerrit respond \
  --dry-run "" >/dev/null 2>&1
); then
  die "respond test: explicit empty review directory accepted"
fi
if (
  cd "$tmp"
"$ROOT_DIR/bin/casual-review" gerrit respond \
    --dry-run ai-reviews "" >/dev/null 2>&1
); then
  die "respond test: explicit empty decisions file accepted"
fi

parse_decisions_file "$decisions"
[[ ${#DECISION_TITLES[@]} -eq 5 ]] ||
  die "respond test: decision count failed"
total=$(LIMIT=0 limited_decision_total "${#DECISION_TITLES[@]}")
[[ "$total" == 5 ]] ||
  die "respond test: unlimited interactive total failed"
total=$(LIMIT=3 limited_decision_total "${#DECISION_TITLES[@]}")
[[ "$total" == 3 ]] ||
  die "respond test: limited interactive total failed"
total=$(LIMIT=8 limited_decision_total "${#DECISION_TITLES[@]}")
[[ "$total" == 5 ]] ||
  die "respond test: over-limit interactive total failed"
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
comments_json=$(jq -c -n '{}')
comments_json=$(
  add_comment_to_comments_json \
    "$comments_json" \
    "bin/tool" \
    "42" \
    "abc123" \
    "$response" \
    false
)
payload=$(
  build_batch_payload "$comments_json" ""
)
jq -e '
  .comments["bin/tool"][0].in_reply_to == "abc123"
  and .comments["bin/tool"][0].unresolved == false
  and (.comments["bin/tool"][0].message | contains("**Decision:** Fix"))
  and (.comments["bin/tool"][0].message | contains("`abcdef1`"))
  and (.comments["bin/tool"][0].message | contains("`0123456`"))
  and (.comments["bin/tool"][0].message | contains("Added guard."))
' >/dev/null <<<"$payload" || die "respond test: response payload failed"

reset_pending_queues
# shellcheck disable=SC2034
DECISION_REVIEWED_COMMITS[0]=$REVIEW_COMMIT
queue_inline_response 0 "$review_file" "$comment_index" "$response" false
[[ "${#PENDING_COMMITS[@]}" == 1 ]] ||
  die "respond test: pending commit count failed"
[[ "${PENDING_TYPES[0]}" == comment ]] ||
  die "respond test: pending inline type failed"
[[ "${PENDING_PATHS[0]}" == "bin/tool" ]] ||
  die "respond test: pending inline path failed"
reset_pending_queues

marker=$(decision_marker 1)
response=$(build_change_message 1 "$marker")
payload=$(build_batch_payload "$(jq -c -n '{}')" "$response")
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

comments_json=$(jq -c -n '{}')
comments_json=$(
  add_comment_to_comments_json \
    "$comments_json" \
    "bin/tool" \
    "42" \
    "abc123" \
    "$response" \
    false
)
message=$(append_change_message "first" "second")
payload=$(build_batch_payload "$comments_json" "$message")
jq -e '
  .omit_duplicate_comments == true
  and .comments["bin/tool"][0].in_reply_to == "abc123"
  and .comments["bin/tool"][0].line == 42
  and .comments["bin/tool"][0].unresolved == false
  and (.message | contains("first"))
  and (.message | contains("---"))
  and (.message | contains("second"))
' >/dev/null <<<"$payload" || die "respond test: batch payload failed"

parse_review_file "$review_file" ||
  die "respond test: batch review reparse failed"
reset_pending_queues
# shellcheck disable=SC2034
DECISION_REVIEWED_COMMITS[0]=$REVIEW_COMMIT
# shellcheck disable=SC2034
DECISION_REVIEWED_COMMITS[1]=$REVIEW_COMMIT
# shellcheck disable=SC2034
DECISION_REVIEWED_COMMITS[2]=$REVIEW_COMMIT
queue_inline_response 0 "$review_file" 0 "$(build_response_message 0)" false
marker=$(decision_marker 1)
queue_change_message 1 "$review_file" "$marker" \
  "$(build_change_message 1 "$marker")"
queue_inline_response 2 "$review_file" 1 "$(build_response_message 2)" true

POST_COUNT=0
POST_PAYLOAD=
REMOTE_MESSAGE_0=$(format_original_comment 0)
REMOTE_MESSAGE_1=$(format_original_comment 1)
gerrit_find_change() {
  printf '123\t%s\n' "$REVIEW_COMMIT"
}
gerrit_list_messages() {
  printf '[]\n'
}
gerrit_list_comments() {
  jq -c -n \
    --arg message0 "$REMOTE_MESSAGE_0" \
    --arg message1 "$REMOTE_MESSAGE_1" '
      {
        "bin/tool": [
          {id: "remote0", line: 42, message: $message0}
        ],
        "README.md": [
          {id: "remote1", message: $message1}
        ]
      }
    '
}
gerrit_post_response() {
  POST_COUNT=$((POST_COUNT + 1))
  POST_PAYLOAD=$3
}
POSTED_RESPONSES=0
POSTED_CHANGE_MESSAGES=0
MATCHED_DECISIONS=0
CHANGE_MESSAGE_DECISIONS=0
SKIPPED_DECISIONS=0
post_pending_batches
[[ "$POST_COUNT" == 1 ]] || die "respond test: batch post count failed"
[[ "$POSTED_RESPONSES" == 2 ]] ||
  die "respond test: batch posted response count failed"
[[ "$POSTED_CHANGE_MESSAGES" == 1 ]] ||
  die "respond test: batch posted message count failed"
[[ "$MATCHED_DECISIONS" == 2 ]] ||
  die "respond test: batch matched response count failed"
[[ "$CHANGE_MESSAGE_DECISIONS" == 1 ]] ||
  die "respond test: batch matched message count failed"
jq -e --arg marker "$marker" '
  (.comments["bin/tool"] | length) == 1
  and (.comments["README.md"] | length) == 1
  and .comments["bin/tool"][0].in_reply_to == "remote0"
  and .comments["README.md"][0].in_reply_to == "remote1"
  and (.message | contains($marker))
' >/dev/null <<<"$POST_PAYLOAD" ||
  die "respond test: batched Gerrit payload failed"

reset_pending_queues
POST_COUNT=0
POST_PAYLOAD=
POSTED_RESPONSES=0
POSTED_CHANGE_MESSAGES=0
MATCHED_DECISIONS=0
CHANGE_MESSAGE_DECISIONS=0
# shellcheck disable=SC2034
MODE=yolo
queue_inline_response 0 "$review_file" 0 "$(build_response_message 0)" false
flush_pending_if_commit_changed "$REVIEW_COMMIT"
[[ "$POST_COUNT" == 0 ]] ||
  die "respond test: same-commit boundary flushed"
flush_pending_if_commit_changed fedcba9876543210fedcba9876543210fedcba98
[[ "$POST_COUNT" == 1 ]] ||
  die "respond test: next-commit boundary did not flush"
[[ "${#PENDING_TYPES[@]}" == 0 ]] ||
  die "respond test: boundary flush did not clear pending types"
[[ -z "$PENDING_CURRENT_COMMIT" ]] ||
  die "respond test: boundary flush did not clear current commit"
# shellcheck disable=SC2034
MODE=dry-run
reset_pending_queues

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

printf 'Gerrit respond test ok\n'
