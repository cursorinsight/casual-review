#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

# Temporary repositories and engine mocks must share the host filesystem.
unset CASUAL_REVIEW_USE_CAPSULE CAPSULE_PROFILES

tmp=

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

tmp=$(mktemp -d)
repo=$tmp/repo
out=$tmp/out
default_out=$tmp/default-out
merge_out=$tmp/merge-out
merge_repo=$tmp/merge-repo
metadata_failure_out=$tmp/metadata-failure-out
recovery_out=$tmp/recovery-out
fake_claude=$tmp/claude
git_calls=$tmp/git-calls
git_wrapper_dir=$tmp/bin
log=$tmp/review.log
default_log=$tmp/default.log
merge_log=$tmp/merge.log
metadata_failure_log=$tmp/metadata-failure.log
recovery_log=$tmp/recovery.log
missing_log=$tmp/missing.log
unsafe_log=$tmp/unsafe.log
unreadable_log=$tmp/unreadable.log
test_change_id=I0123456789abcdef0123456789abcdef01234567

mkdir -p "$repo"
(
  cd "$repo"
  git init -q
  git config user.email test@example.com
  git config user.name 'Test User'
  printf 'one\n' >file.txt
  git add file.txt
  git commit -q -m base
  printf 'two\n' >file.txt
  git commit -am change -q
  printf 'more\n' >other.txt
  git add other.txt
  git commit -q -m 'second change' -m "Change-Id: $test_change_id"
)

cat >"$fake_claude" <<'EOF_CLAUDE'
#!/usr/bin/env bash
if [[ -n "${MOCK_PROMPT_LOG:-}" ]]; then
  cat >"$MOCK_PROMPT_LOG"
fi
printf '{invalid'
exit 0
EOF_CLAUDE
chmod +x "$fake_claude"

real_git=$(command -v git)
mkdir "$git_wrapper_dir"
cat >"$git_wrapper_dir/git" <<'EOF_GIT'
#!/usr/bin/env bash
if [[ "$1" == show && "${2:-}" == --no-ext-diff &&
    "${3:-}" == --pretty=format: ]]; then
  printf '%s\n' "$*" >>"$MOCK_GIT_LOG"
fi
exec "$REAL_GIT" "$@"
EOF_GIT
chmod +x "$git_wrapper_dir/git"

real_mv=$(command -v mv)
mv_wrapper_dir=$tmp/mv-bin
mkdir "$mv_wrapper_dir"
cat >"$mv_wrapper_dir/mv" <<'EOF_MV'
#!/usr/bin/env bash
destination=
for argument in "$@"; do
  destination=$argument
done
case "$destination" in
  */SERIES.md) exit 1 ;;
esac
exec "$REAL_MV" "$@"
EOF_MV
chmod +x "$mv_wrapper_dir/mv"

git -C "$repo" update-ref refs/remotes/origin/main HEAD~2
git -C "$repo" config remote.origin.url \
  'https://user:token@example.com/org/repo.git?access_token=query-secret'
unsafe_out=$tmp/unsafe-out
mkdir "$unsafe_out"
printf 'keep\n' >"$unsafe_out/.keep"
if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$unsafe_out" \
      --skip-summary
  ) >/dev/null 2>"$unsafe_log";
then
  die "review accepted an unrelated hidden-only output directory"
fi
grep -Fq 'output directory is not a Casual Review directory' "$unsafe_log" ||
  die "review did not reject an unrelated hidden-only output directory"

unreadable_out=$tmp/unreadable-out
mkdir "$unreadable_out"
chmod 100 "$unreadable_out"
if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$unreadable_out" \
      --skip-summary
  ) >/dev/null 2>"$unreadable_log";
then
  die "review accepted an unreadable output directory"
fi
chmod 700 "$unreadable_out"
grep -Fq 'cannot inspect output directory' "$unreadable_log" ||
  die "review did not fail closed for an unreadable output directory"

if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$default_out" \
      --skip-summary
  ) >/dev/null 2>"$default_log";
then
  die "review accepted invalid Claude JSON with detected base"
fi
grep -Fq -- "- Base: \`origin/main\`" "$default_out/README.md" ||
  die "review did not detect origin/main"

mkdir "$merge_repo"
(
  cd "$merge_repo"
  git init -q
  git config user.email test@example.com
  git config user.name 'Test User'
  printf 'base\n' >base.txt
  git add base.txt
  git commit -q -m base
  git branch topic
  printf 'main\n' >main.txt
  git add main.txt
  git commit -q -m 'main change'
  git switch -q topic
  printf 'topic\n' >topic.txt
  git add topic.txt
  git commit -q -m 'topic change'
  git switch -q master
  git merge --no-ff -q topic -m 'merge topic'
)
merge_base=$(git -C "$merge_repo" rev-list --max-parents=0 HEAD)
git -C "$merge_repo" update-ref refs/remotes/origin/main "$merge_base"
if (
    cd "$merge_repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$merge_out" \
      --skip-summary
  ) >/dev/null 2>"$merge_log";
then
  die "merge review accepted invalid Claude JSON"
fi
old_merge=$(git -C "$merge_repo" rev-parse HEAD)
git -C "$merge_repo" commit --amend -q \
  -m 'merge topic' -m 'rewritten merge'
new_merge=$(git -C "$merge_repo" rev-parse HEAD)
[[ "$old_merge" != "$new_merge" ]] || die "merge commit was not rewritten"
if (
    cd "$merge_repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$merge_out" \
      --skip-summary
  ) >/dev/null 2>>"$merge_log";
then
  die "rewritten merge review accepted invalid Claude JSON"
fi
[[ -r "$merge_out/rounds/002/README.md" ]] ||
  die "review rejected a corresponding rewritten merge range"

cp -R "$default_out" "$metadata_failure_out"
if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    PATH="$mv_wrapper_dir:$PATH" \
    REAL_MV="$real_mv" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$metadata_failure_out" \
      --skip-summary
  ) >/dev/null 2>"$metadata_failure_log";
then
  die "review accepted failed series metadata publication"
fi
grep -Fq 'failed to publish migrated review series metadata' \
  "$metadata_failure_log" ||
  die "review did not report failed series metadata publication"
[[ -r "$metadata_failure_out/README.md" ]] ||
  die "review did not restore flat metadata after migration failure"
[[ ! -e "$metadata_failure_out/SERIES.md" ]] ||
  die "review left series metadata after migration failure"
[[ ! -e "$metadata_failure_out/rounds" ]] ||
  die "review left rounds after migration failure"

if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$tmp/missing-claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --series \
      --head HEAD \
      --output "$recovery_out" \
      --skip-summary
  ) >/dev/null 2>"$recovery_log";
then
  die "review accepted a missing engine command"
fi
grep -Fq 'command not found' "$recovery_log" ||
  die "review did not explain the missing engine command"
for dir in "$recovery_out"/rounds/[0-9][0-9][0-9]; do
  [[ ! -d "$dir" ]] || die "failed review published an incomplete round"
done
for dir in "$recovery_out"/rounds/.*.tmp.*; do
  [[ ! -d "$dir" ]] || die "failed review left its staging directory"
done
mkdir "$recovery_out/rounds/.001.tmp.interrupted"
printf 'partial\n' >"$recovery_out/rounds/.001.tmp.interrupted/output"
if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$recovery_out" \
      --skip-summary
  ) >/dev/null 2>>"$recovery_log";
then
  die "review accepted invalid Claude JSON during retry"
fi
[[ -r "$recovery_out/rounds/001/README.md" ]] ||
  die "review did not publish the retried first round"

reviewed_commit=$(git -C "$repo" rev-parse --short=7 HEAD)
cat >"$default_out/DECISIONS.md" <<EOF_DECISIONS
## 2026-10-01T00:00:00Z - $reviewed_commit - Preserve behavior

- Review file: \`$default_out/claude/001-$reviewed_commit.md\`
- Reviewed commit: \`$reviewed_commit\`
- Decision: Skip
- Fix placement: None
- Checks: not run: no change required
- Reasoning: Existing behavior is intentional.

## 2026-10-01T00:01:00Z - $reviewed_commit - Correct behavior

- Review file: \`$default_out/claude/001-$reviewed_commit.md\`
- Reviewed commit: \`$reviewed_commit\`
- Reviewed subject: second change
- Change-Id: $test_change_id
- Finding fingerprint: \`other.txt::<file-scope>\`
- Decision: Fix
- Fix placement: Reviewed commit
- Checks: test passed
- Reasoning: The accepted fix must be revalidated at final HEAD.
EOF_DECISIONS
duplicated_index=$tmp/duplicated-index
awk '/^\| [0-9]+ \| `/ { print; print; next } { print }' \
  "$default_out/README.md" >"$duplicated_index"
mv "$duplicated_index" "$default_out/README.md"
printf 'more revised\n' >"$repo/other.txt"
git -C "$repo" commit -a --amend --no-edit -q
prompt_log=$tmp/round-two-prompt.md
if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    MOCK_GIT_LOG="$git_calls" \
    MOCK_PROMPT_LOG="$prompt_log" \
    PATH="$git_wrapper_dir:$PATH" \
    REAL_GIT="$real_git" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$default_out" \
      --skip-summary
  ) >/dev/null 2>>"$default_log";
then
  die "review accepted invalid Claude JSON in round two"
fi
patch_id_calls=$(wc -l <"$git_calls" | tr -d ' ')
[[ "$patch_id_calls" == 3 ]] ||
  die "review repeated patch ID work for duplicate review rows"
[[ -r "$default_out/SERIES.md" ]] ||
  die "review did not create series metadata"
grep -Fqx -- \
  "- Repository: \`https://example.com/org/repo.git\`" \
  "$default_out/SERIES.md" ||
  die "review did not remove credentials from series metadata"
if grep -Eq 'user:token|query-secret' "$default_out/SERIES.md"; then
  die "review leaked credentials into series metadata"
fi
[[ -r "$default_out/rounds/001/README.md" ]] ||
  die "review did not migrate the initial review"
[[ -r "$default_out/rounds/002/README.md" ]] ||
  die "review did not create the second round"
[[ -r "$default_out/DECISIONS.md" ]] ||
  die "review moved the cumulative decision log"
if grep -Fq 'Existing behavior is intentional.' "$prompt_log"; then
  die "review duplicated prior decisions into a commit-local prompt"
fi
grep -Fq "Gerrit Change-Id: $test_change_id" "$prompt_log" ||
  die "review prompt omitted the Gerrit Change-Id"

git -C "$repo" config remote.origin.url \
  'https://example.com/org/repo.git#fragment-secret'
if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$default_out" \
      --skip-summary
  ) >/dev/null 2>>"$default_log";
then
  die "review accepted invalid Claude JSON in round three"
fi
grep -Fqx -- \
  "- Repository: \`https://example.com/org/repo.git\`" \
  "$default_out/SERIES.md" ||
  die "review did not remove URL fragment from series metadata"
if grep -Fq 'fragment-secret' "$default_out/SERIES.md"; then
  die "review leaked URL fragment into series metadata"
fi

git -C "$repo" reset --hard -q HEAD~1
printf 'unrelated\n' >"$repo/unrelated.txt"
git -C "$repo" add unrelated.txt
git -C "$repo" commit -m unrelated -q
if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --head HEAD \
      --output "$default_out" \
      --skip-summary
  ) >/dev/null 2>>"$default_log";
then
  die "review continued an unrelated series"
fi
grep -Fq 'existing review series does not match' "$default_log" ||
  die "review did not explain the series mismatch"
grep -Fq 'only 1 of 2 recorded commits correspond to the current range' \
    "$default_log" ||
  die "review did not report partial range correspondence"
grep -Fq 'use --continue-series to override' "$default_log" ||
  die "review did not report the series mismatch workaround"

mkdir "$default_out/rounds/004"
if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
    "$ROOT_DIR/bin/casual-review" review \
      --continue-series \
      --head HEAD \
      --output "$default_out" \
      --skip-summary
  ) >/dev/null 2>>"$default_log";
then
  die "review accepted an incomplete round"
fi
grep -Fq 'incomplete review round' "$default_log" ||
  die "review did not explain the incomplete round"

git -C "$repo" update-ref -d refs/remotes/origin/main
if (
    cd "$repo"
    "$ROOT_DIR/bin/casual-review" review --skip-summary
  ) >/dev/null 2>"$missing_log";
then
  die "review accepted missing default base refs"
fi
grep -q 'could not detect base' "$missing_log" ||
  die "review did not explain missing default base refs"

if (
    cd "$repo"
    CASUAL_REVIEW_ENGINE=claude \
    CLAUDE_BIN="$fake_claude" \
"$ROOT_DIR/bin/casual-review" review \
      --base HEAD~1 \
      --head HEAD \
      --output "$out" \
      --skip-summary
  ) >/dev/null 2>"$log";
then
  die "review accepted invalid Claude JSON"
fi

review_file=$(find "$out/claude" -type f -name '001-*.md' | sed -n '1p')
[[ -n "$review_file" ]] ||
  die "review test: failure review file missing"
grep -q '^# Review failed$' "$review_file" ||
  die "review test: failure marker missing"
grep -q '{invalid' "$review_file" &&
  die "review test: invalid JSON leaked into review file"

reconcile_repo=$tmp/reconcile-repo
reconcile_out=$tmp/reconcile-out
reconcile_flat=$tmp/reconcile-flat
reconcile_bad=$tmp/reconcile-bad
reconcile_bad_question=$tmp/reconcile-bad-question
reconcile_prompts=$tmp/reconcile-prompts
reconcile_counter=$tmp/reconcile-counter
fake_codex=$tmp/codex
mkdir -p "$reconcile_repo" "$reconcile_prompts"
(
  cd "$reconcile_repo"
  git init -q
  git config user.email test@example.com
  git config user.name 'Test User'
  printf 'base\n' >sample.txt
  git add sample.txt
  git commit -q -m base
  printf 'broken\n' >sample.txt
  git commit -am feature -q \
    -m 'Change-Id: feature/unsafe&value'
  printf 'fixed\n' >sample.txt
  git commit -am fix -q
)
git -C "$reconcile_repo" update-ref refs/remotes/origin/main HEAD~2
fix_commit=$(git -C "$reconcile_repo" rev-parse --short=7 HEAD)
cat >"$fake_codex" <<'EOF_CODEX'
#!/usr/bin/env bash
output=
while (($#)); do
  case "$1" in
    -o)
      output=$2
      shift 2
      ;;
    *) shift ;;
  esac
done
prompt=$(cat)
count=0
[[ ! -r "$MOCK_COUNTER" ]] || count=$(cat "$MOCK_COUNTER")
count=$((count + 1))
printf '%s\n' "$count" >"$MOCK_COUNTER"
printf '%s' "$prompt" >"$MOCK_PROMPT_DIR/$count"
if [[ "$prompt" == *'You are reconciling completed'* ]]; then
  path_one=$(printf '%s\n' "$prompt" |
    sed -n 's/^<review path="\([^"]*\)">$/\1/p' | sed -n '1p')
  path_two=$(printf '%s\n' "$prompt" |
    sed -n 's/^<review path="\([^"]*\)">$/\1/p' | sed -n '2p')
  jq -n \
    --arg one "$path_one" \
    --arg two "$path_two" \
    --arg commit "$MOCK_FIX_COMMIT" \
    --arg skip_decision "${MOCK_SKIP_DECISION:-}" \
    --arg fix_decision "${MOCK_FIX_DECISION:-}" \
    --arg verdict \
      "${MOCK_VERDICT:-Looks good with minor comments}" '
      {
        reviews: [
          {
            path: $one,
            verdict: $verdict,
            reconciled: [
              if $skip_decision != "" then {
                ordinal: 1,
                fingerprint: "sample.txt::main",
                status: "prior_skip_valid",
                commit: null,
                decision: $skip_decision
              } elif $fix_decision != "" then {
                ordinal: 1,
                fingerprint: "sample.txt::main",
                status: "prior_fix_valid",
                commit: null,
                decision: $fix_decision
              } else {
                ordinal: 1,
                fingerprint: "sample.txt::main",
                status: "fixed_downstream",
                commit: $commit,
                decision: null
              } end
            ],
            questions: [{
              ordinal: 1,
              text: "Is the fallback required?",
              status: "fixed_downstream",
              commit: $commit,
              decision: null
            }]
          },
          {
            path: $two,
            verdict: "Needs changes",
            reconciled: [],
            questions: []
          }
        ]
      }
    ' >"$output"
else
  commit=$(printf '%s\n' "$prompt" |
    sed -n 's/^Review commit: //p')
  parent=$(printf '%s\n' "$prompt" |
    sed -n 's/^Parent commit: //p')
  subject=$(printf '%s\n' "$prompt" |
    sed -n 's/^Subject: //p')
  change_id=$(printf '%s\n' "$prompt" |
    sed -n 's/^Gerrit Change-Id: //p')
  question='- Is the fallback required?'
  if [[ "${MOCK_NUMBERED_QUESTION:-}" == 1 ]]; then
    question='1. Is the fallback required?'
  fi
  cat >"$output" <<EOF_REVIEW
# Commit review

## Commit

- Commit: \`$commit\`
- Parent: \`$parent\`
- Change-Id: \`$change_id\`
- Subject: $subject

## Findings

### [Major] Broken behavior

- Confidence: High
- Location: \`sample.txt:1\`
- Fingerprint: \`sample.txt::main\`
- Introduced by this commit: Yes
- Review action: Must fix

Suggested review comment:

> Correct the broken behavior.

### [Minor] Second problem in the same symbol

- Confidence: High
- Location: \`sample.txt:1\`
- Fingerprint: \`sample.txt::main\`
- Introduced by this commit: Yes
- Review action: Should fix

Suggested review comment:

> Correct the second problem too.

## Questions

$question

## Positive observations

None.

## Review verdict

Needs changes

The finding is actionable in the reviewed commit.
EOF_REVIEW
fi
EOF_CODEX
chmod +x "$fake_codex"

if (
  cd "$reconcile_repo"
  CODEX_BIN="$fake_codex" \
  MOCK_COUNTER="$reconcile_counter" \
  MOCK_FIX_COMMIT="$fix_commit" \
  MOCK_PROMPT_DIR="$reconcile_prompts" \
  MOCK_SKIP_DECISION='## missing prior skip' \
    "$ROOT_DIR/bin/casual-review" review \
      --engine codex \
      --head HEAD \
      --output "$reconcile_flat" \
      --skip-summary
) >/dev/null 2>&1; then
  die "review accepted an unreferenced prior skip"
fi
if find "$reconcile_flat" -mindepth 1 -print -quit | grep -q .; then
  die "failed flat reconciliation left partial output"
fi
if (
  cd "$reconcile_repo"
  CODEX_BIN="$fake_codex" \
  MOCK_COUNTER="$reconcile_counter" \
  MOCK_FIX_COMMIT="$fix_commit" \
  MOCK_PROMPT_DIR="$reconcile_prompts" \
  MOCK_VERDICT=LGTM \
    "$ROOT_DIR/bin/casual-review" review \
      --engine codex \
      --head HEAD \
      --output "$reconcile_bad" \
      --skip-summary
) >/dev/null 2>&1; then
  die "review accepted an inconsistent reconciliation verdict"
fi
if find "$reconcile_bad" -mindepth 1 -print -quit | grep -q .; then
  die "bad reconciliation verdict left partial output"
fi
if (
  cd "$reconcile_repo"
  CODEX_BIN="$fake_codex" \
  MOCK_COUNTER="$reconcile_counter" \
  MOCK_FIX_COMMIT="$fix_commit" \
  MOCK_NUMBERED_QUESTION=1 \
  MOCK_PROMPT_DIR="$reconcile_prompts" \
    "$ROOT_DIR/bin/casual-review" review \
      --engine codex \
      --head HEAD \
      --output "$reconcile_bad_question" \
      --skip-summary
) >/dev/null 2>&1; then
  die "review accepted a malformed question section"
fi
if find "$reconcile_bad_question" -mindepth 1 -print -quit |
    grep -q .; then
  die "malformed question section left partial output"
fi
rm -f -- "$reconcile_counter"
rm -rf -- "$reconcile_prompts"
mkdir "$reconcile_prompts"
(
  cd "$reconcile_repo"
  CODEX_BIN="$fake_codex" \
  MOCK_COUNTER="$reconcile_counter" \
  MOCK_FIX_COMMIT="$fix_commit" \
  MOCK_PROMPT_DIR="$reconcile_prompts" \
    "$ROOT_DIR/bin/casual-review" review \
      --engine codex \
      --head HEAD \
      --output "$reconcile_flat" \
      --skip-summary
) >/dev/null
[[ -r "$reconcile_flat/README.md" ]] ||
  die "review could not retry a failed flat reconciliation"

rm -f -- "$reconcile_counter"
rm -rf -- "$reconcile_prompts"
mkdir "$reconcile_prompts"
(
  cd "$reconcile_repo"
  CODEX_BIN="$fake_codex" \
  MOCK_COUNTER="$reconcile_counter" \
  MOCK_FIX_COMMIT="$fix_commit" \
  MOCK_PROMPT_DIR="$reconcile_prompts" \
    "$ROOT_DIR/bin/casual-review" review \
      --engine codex \
      --series \
      --head HEAD \
      --output "$reconcile_out" \
      --skip-summary
) >/dev/null
[[ "$(cat "$reconcile_counter")" == 3 ]] ||
  die "review did not use one reconciliation call"
first_review=$(find "$reconcile_out/rounds/001/codex" \
  -type f -name '001-*.md' | sed -n '1p')
grep -Fq -- '- Reconciliation: Fixed downstream by' "$first_review" ||
  die "review did not annotate a downstream fix"
[[ "$(grep -c '^- Reconciliation:' "$first_review")" == 1 ]] ||
  die "review annotated both findings with a shared fingerprint"
grep -Fq -- '  - Reconciliation: Fixed downstream by' "$first_review" ||
  die "review did not annotate a reconciled question"
grep -Fq '## Final-HEAD reconciliation' "$first_review" ||
  die "review did not append the reconciled verdict"
[[ -r "$reconcile_out/rounds/001/RECONCILIATION.json" ]] ||
  die "review did not retain the reconciliation manifest"
grep -Fq 'Gerrit Change-Id: none' "$reconcile_prompts/1" ||
  die "review did not reject an invalid Change-Id"

skip_heading='## 2026-10-02T00:00:00Z - deadbee - Prior skip'
fix_heading='## 2026-10-02T00:01:00Z - deadbee - Prior fix'
cat >"$reconcile_out/DECISIONS.md" <<EOF_RECONCILE_DECISIONS
$skip_heading

- Decision: Skip
- Fix placement: None
- Finding fingerprint: \`sample.txt::main\`
- Reasoning: OMIT_THIS_PRIOR_SKIP

$fix_heading

- Decision: Fix
- Fix placement: Standalone
- Finding fingerprint: \`sample.txt::main\`
- Reasoning: KEEP_THIS_PRIOR_FIX
EOF_RECONCILE_DECISIONS
rm -f -- "$reconcile_counter"
rm -rf -- "$reconcile_prompts"
mkdir "$reconcile_prompts"
(
  cd "$reconcile_repo"
  CODEX_BIN="$fake_codex" \
  MOCK_COUNTER="$reconcile_counter" \
  MOCK_FIX_COMMIT="$fix_commit" \
  MOCK_PROMPT_DIR="$reconcile_prompts" \
  MOCK_SKIP_DECISION="$skip_heading" \
    "$ROOT_DIR/bin/casual-review" review \
      --engine codex \
      --head HEAD \
      --output "$reconcile_out" \
      --skip-summary
) >/dev/null
skip_review=$(find "$reconcile_out/rounds/002/codex" \
  -type f -name '001-*.md' | sed -n '1p')
grep -Fq -- '- Reconciliation: Prior skip remains valid' \
  "$skip_review" || die "review rejected a referenced prior skip"

rm -f -- "$reconcile_counter"
rm -rf -- "$reconcile_prompts"
mkdir "$reconcile_prompts"
if (
  cd "$reconcile_repo"
  CODEX_BIN="$fake_codex" \
  MOCK_COUNTER="$reconcile_counter" \
  MOCK_FIX_COMMIT="$fix_commit" \
  MOCK_PROMPT_DIR="$reconcile_prompts" \
  MOCK_FIX_DECISION="$fix_heading" \
    "$ROOT_DIR/bin/casual-review" review \
      --engine codex \
      --recheck-skipped \
      --head HEAD \
      --output "$reconcile_out" \
      --skip-summary
) >/dev/null 2>&1; then
  die "review accepted a standalone fix as a commit-local fix"
fi
[[ ! -d "$reconcile_out/rounds/003" ]] ||
  die "rejected standalone fix published a review round"
sed 's/^- Fix placement: Standalone$/- Fix placement: Reviewed commit/' \
  "$reconcile_out/DECISIONS.md" >"$tmp/decisions-updated"
mv -- "$tmp/decisions-updated" "$reconcile_out/DECISIONS.md"
rm -f -- "$reconcile_counter"
rm -rf -- "$reconcile_prompts"
mkdir "$reconcile_prompts"
(
  cd "$reconcile_repo"
  CODEX_BIN="$fake_codex" \
  MOCK_COUNTER="$reconcile_counter" \
  MOCK_FIX_COMMIT="$fix_commit" \
  MOCK_PROMPT_DIR="$reconcile_prompts" \
  MOCK_FIX_DECISION="$fix_heading" \
    "$ROOT_DIR/bin/casual-review" review \
      --engine codex \
      --recheck-skipped \
      --head HEAD \
      --output "$reconcile_out" \
      --skip-summary
) >/dev/null
fix_review=$(find "$reconcile_out/rounds/003/codex" \
  -type f -name '001-*.md' | sed -n '1p')
grep -Fq -- '- Reconciliation: Prior fix remains valid' \
  "$fix_review" || die "review rejected a referenced prior fix"
reconcile_prompt=$(grep -Fl 'You are reconciling completed' \
  "$reconcile_prompts"/*)
grep -Fq 'KEEP_THIS_PRIOR_FIX' "$reconcile_prompt" ||
  die "review omitted a prior fix from reconciliation"
if grep -Fq 'OMIT_THIS_PRIOR_SKIP' "$reconcile_prompt"; then
  die "review retained a skip with --recheck-skipped"
fi
if grep -Fl 'KEEP_THIS_PRIOR_FIX' "$reconcile_prompts"/1 \
    "$reconcile_prompts"/2 >/dev/null; then
  die "review duplicated decisions into commit-local prompts"
fi

printf 'review test ok\n'
