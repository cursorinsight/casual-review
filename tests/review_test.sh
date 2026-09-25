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
fake_claude=$tmp/claude
log=$tmp/review.log
default_log=$tmp/default.log
missing_log=$tmp/missing.log

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
)

cat >"$fake_claude" <<'EOF_CLAUDE'
#!/usr/bin/env bash
printf '{invalid'
exit 0
EOF_CLAUDE
chmod +x "$fake_claude"

git -C "$repo" update-ref refs/remotes/origin/main HEAD~1
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

printf 'review test ok\n'
