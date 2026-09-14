#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)"

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
fake_claude=$tmp/claude
log=$tmp/review.log

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
