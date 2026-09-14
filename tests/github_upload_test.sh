#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)
CLI=$ROOT_DIR/bin/casual-review
COMMIT=0123456789abcdef0123456789abcdef01234567
COMMIT2=abcdef0123456789abcdef0123456789abcdef01
tmp=$(mktemp -d)

cleanup() {
  rm -rf -- "$tmp"
}

trap cleanup EXIT

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

expect_status() {
  local expected=$1
  local actual=0

  shift
  "$@" >"$tmp/stdout" 2>"$tmp/stderr" || actual=$?
  [[ "$actual" == "$expected" ]] ||
    die "expected status $expected, got $actual from: $*"
}

write_lgtm_review() {
  local file=$1
  local commit=$2
  local parent=$3
  local subject=$4

  cat >"$file" <<EOF_REVIEW
# Commit review

## Commit

- Commit: \`$commit\`
- Parent: \`$parent\`
- Subject: $subject

## Summary

Ready for approval.

## Findings

None.

## Review verdict

LGTM

The commit is ready to merge.
EOF_REVIEW
}

reviews=$tmp/ai-reviews
mkdir -p "$reviews/codex"
cat >"$reviews/codex/001-0123456789ab.md" <<'EOF_REVIEW'
# Commit review

## Commit

- Commit: `0123456789abcdef0123456789abcdef01234567`
- Parent: `1111111111111111111111111111111111111111`
- Subject: Add GitHub upload

## Summary

Adds an uploader.

## Findings

### [Major] Validate input

- Confidence: High
- Location: `src/tool.sh:42`
- Introduced by this commit: Yes
- Review action: Must fix

Suggested review comment:

> Please reject empty input before submitting the request.

### [Minor] Document behavior

- Confidence: High
- Location: `README.md`
- Introduced by this commit: Yes
- Review action: Consider

Suggested review comment:

> Document the new upload behavior.

## Questions

None.

## Positive observations

None.

## Review verdict

Needs changes

The input must be validated before this is merged.
EOF_REVIEW

cat >"$reviews/codex/002-abcdef012345.md" <<'EOF_REVIEW'
# Commit review

## Commit

- Commit: `abcdef0123456789abcdef0123456789abcdef01`
- Parent: `0123456789abcdef0123456789abcdef01234567`
- Subject: Document GitHub upload

## Summary

Documents the uploader.

## Findings

### [Minor] Clarify authentication

- Confidence: High
- Location: `README.md:12`
- Introduced by this commit: Yes
- Review action: Consider

Suggested review comment:

> Clarify which GitHub token variable is preferred.

## Questions

None.

## Positive observations

None.

## Review verdict

LGTM

The documentation is ready to merge.
EOF_REVIEW

expect_status 0 env GH_BIN="$tmp/missing-gh" \
  "$CLI" github upload "$reviews"
grep -q '^  event: REQUEST_CHANGES$' "$tmp/stdout" ||
  die "dry-run did not emit the strictest unified verdict"
[[ $(grep -c '^  event: COMMENT$' "$tmp/stdout") == 2 ]] ||
  die "dry-run did not keep commit review payloads comment-only"
grep -q '^  comment: src/tool.sh:42$' "$tmp/stdout" ||
  die "dry-run did not include the inline comment"
grep -q '^Comments skipped: 1$' "$tmp/stdout" ||
  die "dry-run did not skip the file-only finding"

mock_gh=$tmp/gh
cat >"$mock_gh" <<'EOF_GH'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"$GH_LOG"
printf '%s' "${GITHUB_TOKEN:-}" >"$GH_TOKEN_LOG"

if [[ "$1 $2" == "pr view" ]]; then
  head=$GH_HEAD
  if [[ "${3-}" == 7 && -n "${GH_RECHECK_HEAD:-}" ]]; then
    head=$GH_RECHECK_HEAD
  fi
  jq -cn --arg head "$head" '{
    number: 7,
    url: "https://github.com/acme/repo/pull/7",
    headRefOid: $head
  }'
  exit 0
fi

endpoint=${2-}
case "$endpoint" in
  */commits)
    printf '[%s]\n' "$GH_COMMITS"
    ;;
  */comments)
    if [[ -s "$GH_POSTED" ]]; then
      jq -cs \
        --arg moved_from "$GH_MOVED_FROM" \
        --arg moved_to "$GH_MOVED_TO" '[
        [
          .[] as $review
          | ($review.comments // [])[]
          | . + {
              commit_id: (
                if $review.commit_id == $moved_from
                then $moved_to
                else $review.commit_id
                end
              ),
              line: (
                if $review.commit_id == $moved_from
                then .line + 10
                else .line
                end
              ),
              original_commit_id: $review.commit_id,
              original_line: .line
            }
        ]
      ]' "$GH_POSTED"
    else
      printf '[[]]\n'
    fi
    ;;
  */reviews)
    if [[ " $* " == *" --method POST "* ]]; then
      payload=$(cat)
      printf '%s\n' "$payload" >>"$GH_POSTED"
      printf 'POST\n' >>"$GH_LOG"
    elif [[ -s "$GH_POSTED" ]]; then
      jq -cs '[
        [
          .[]
          | {
              commit_id: (.commit_id // ""),
              body: .body,
              state: (
                if .event == "REQUEST_CHANGES" then "CHANGES_REQUESTED"
                elif .event == "APPROVE" then "APPROVED"
                else "COMMENTED"
                end
              )
            }
        ]
      ]' "$GH_POSTED"
    else
      printf '[[]]\n'
    fi
    ;;
  *)
    printf 'Unexpected gh arguments: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF_GH
chmod 755 "$mock_gh"

export GH_BIN=$mock_gh
export GH_LOG=$tmp/gh.log
export GH_TOKEN_LOG=$tmp/token.log
export GH_POSTED=$tmp/posted.json
export GH_MOVED_FROM=$COMMIT
export GH_MOVED_TO=$COMMIT2
export GH_HEAD=$COMMIT2
export GH_RECHECK_HEAD=
export GH_COMMITS
GH_COMMITS=$(jq -c -n \
  --arg first "$COMMIT" \
  --arg second "$COMMIT2" \
  '[{sha: $first}, {sha: $second}]')
export GITHUB_TOKEN=test-token

expect_status 0 "$CLI" github upload --yolo \
  --repo acme/repo "$reviews"
[[ $(<"$GH_TOKEN_LOG") == test-token ]] ||
  die "GITHUB_TOKEN was not inherited by gh"
grep -q '^pr view --json number,url,headRefOid$' "$GH_LOG" ||
  die "upload did not resolve the current branch pull request"
grep -q '^pr view 7 --json headRefOid$' "$GH_LOG" ||
  die "upload did not revalidate the pull request head"
jq -e -s --arg first "$COMMIT" --arg second "$COMMIT2" '
  length == 3
  and .[0].commit_id == $first
  and .[0].event == "COMMENT"
  and (.[0].comments | length) == 1
  and .[0].comments[0].path == "src/tool.sh"
  and .[0].comments[0].line == 42
  and .[0].comments[0].side == "RIGHT"
  and .[1].commit_id == $second
  and .[1].event == "COMMENT"
  and (.[1].comments | length) == 1
  and .[1].comments[0].path == "README.md"
  and .[2].event == "REQUEST_CHANGES"
  and .[2].commit_id == $second
  and (.[2] | has("comments") | not)
  and (.[2].body | contains("**Verdict:** Needs changes"))
  and (.[2].body | contains("**Verdict:** LGTM"))
' >/dev/null "$GH_POSTED" || die "GitHub review payload is invalid"

expect_status 0 "$CLI" github upload --yolo \
  --repo acme/repo "$reviews"
[[ $(grep -c '^POST$' "$GH_LOG") == 3 ]] ||
  die "rerun submitted a duplicate review"
grep -q 'already posted to GitHub' "$tmp/stderr" ||
  die "rerun did not report the duplicate review"

approval_reviews=$tmp/approval-reviews/codex
mkdir -p "$approval_reviews"
write_lgtm_review "$approval_reviews/001-$COMMIT.md" \
  "$COMMIT" 1111111111111111111111111111111111111111 \
  "Add GitHub upload"
write_lgtm_review "$approval_reviews/002-$COMMIT2.md" \
  "$COMMIT2" "$COMMIT" "Document GitHub upload"
: >"$GH_LOG"
: >"$GH_POSTED"
expect_status 1 "$CLI" github upload --yolo --limit 1 \
  --repo acme/repo "${approval_reviews%/codex}"
[[ ! -s "$GH_POSTED" ]] ||
  die "partial review coverage posted an approval"
grep -q 'selected verdicts do not cover every pull-request commit' \
  "$tmp/stderr" || die "partial review coverage did not explain refusal"

expect_status 0 "$CLI" github upload --yolo \
  --repo acme/repo "${approval_reviews%/codex}"
jq -e -s --arg head "$COMMIT2" '
  length == 1
  and .[0].event == "APPROVE"
  and .[0].commit_id == $head
' >/dev/null "$GH_POSTED" || die "complete review coverage was not approved"

: >"$GH_POSTED"
GH_RECHECK_HEAD=ffffffffffffffffffffffffffffffffffffffff
expect_status 1 "$CLI" github upload --yolo \
  --repo acme/repo "${approval_reviews%/codex}"
[[ ! -s "$GH_POSTED" ]] || die "changed pull request head was approved"
grep -q 'pull request head changed' "$tmp/stderr" ||
  die "changed pull request head did not explain refusal"
GH_RECHECK_HEAD=

posts_before=$(grep -c '^POST$' "$GH_LOG")
GH_COMMITS='[{"sha":"ffffffffffffffffffffffffffffffffffffffff"}]'
expect_status 1 "$CLI" github upload --yolo \
  --repo acme/repo "$reviews"
grep -q 'commit is not part of pull request #7' "$tmp/stderr" ||
  die "upload did not reject a commit outside the pull request"
[[ $(grep -c '^POST$' "$GH_LOG") == "$posts_before" ]] ||
  die "upload posted a review for a commit outside the pull request"

printf 'GitHub upload test ok\n'
