#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)
CLI=$ROOT_DIR/bin/casual-review
tmp=$(mktemp -d)

# Tests opt into Capsule and profiles explicitly where needed.
unset CASUAL_REVIEW_USE_CAPSULE CAPSULE_PROFILES

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

expect_status 0 "$CLI" --help
grep -q '^  gerrit <command>' "$tmp/stdout" ||
  die "top-level help does not list Gerrit"
grep -q '^  github <command>' "$tmp/stdout" ||
  die "top-level help does not list GitHub"
grep -q '^  completion <shell>' "$tmp/stdout" ||
  die "top-level help does not list completion generation"
expect_status 0 "$CLI" gerrit --help
grep -q '^  upload ' "$tmp/stdout" ||
  die "Gerrit help does not list upload"
expect_status 0 "$CLI" github --help
grep -q '^  upload ' "$tmp/stdout" ||
  die "GitHub help does not list upload"

capsule_bin=$tmp/capsule
capsule_log=$tmp/capsule.log
other_profile=$tmp/other-profile
mkdir "$other_profile"
cat >"$capsule_bin" <<'EOF_CAPSULE'
#!/usr/bin/env bash
{
  printf 'compose=%s\n' "${CAPSULE_CUSTOM_COMPOSE:-}"
  printf 'profiles=%s\n' "${CAPSULE_PROFILES:-}"
  printf 'engine=%s\n' "${CASUAL_REVIEW_ENGINE:-}"
  printf 'effort=%s\n' "${CODEX_EFFORT:-}"
  printf 'arg=%s\n' "$@"
} >"$CAPSULE_LOG"
EOF_CAPSULE
chmod 755 "$capsule_bin"

expect_status 0 env \
  CASUAL_REVIEW_USE_CAPSULE=1 \
  CAPSULE_HOST_WORKDIR= \
  CAPSULE_CUSTOM_COMPOSE="$tmp/compose.yml" \
  CAPSULE_PROFILES="$other_profile" \
  CAPSULE_BIN="$capsule_bin" \
  CAPSULE_LOG="$capsule_log" \
  CASUAL_REVIEW_ENGINE=claude \
  CODEX_EFFORT=xhigh \
  "$CLI" review --limit 2
grep -Fqx 'compose=' "$capsule_log" ||
  die "review preserved incompatible custom Compose configuration"
grep -Fqx "profiles=$other_profile" "$capsule_log" ||
  die "review did not preserve ambient Capsule profiles"
grep -Fqx 'engine=claude' "$capsule_log" ||
  die "review did not preserve CASUAL_REVIEW_ENGINE"
grep -Fqx 'effort=xhigh' "$capsule_log" ||
  die "review did not preserve CODEX_EFFORT"
printf -v review_args \
  'arg=--profile\narg=%s\narg=casual-review\narg=review\narg=--limit\narg=2' \
  "$ROOT_DIR"
[[ $(grep '^arg=' "$capsule_log") == "$review_args" ]] ||
  die "review did not preserve arguments through Capsule"

expect_status 0 env \
  CASUAL_REVIEW_USE_CAPSULE=1 \
  CAPSULE_HOST_WORKDIR= \
  CAPSULE_PROFILES="$other_profile" \
  CAPSULE_BIN="$capsule_bin" \
  CAPSULE_LOG="$capsule_log" \
  "$CLI" process --reviews reviews
printf -v process_args 'arg=--profile\narg=%s' "$ROOT_DIR"
process_args+=$'\narg=casual-review\narg=process'
process_args+=$'\narg=--reviews\narg=reviews'
[[ $(grep '^arg=' "$capsule_log") == "$process_args" ]] ||
  die "process did not preserve arguments through Capsule"

rm -f -- "$capsule_log"
expect_status 0 env \
  CASUAL_REVIEW_USE_CAPSULE=1 \
  CAPSULE_HOST_WORKDIR= \
  CAPSULE_BIN="$capsule_bin" \
  CAPSULE_LOG="$capsule_log" \
  "$CLI" review --help
[[ ! -e "$capsule_log" ]] ||
  die "review --help entered Capsule"

expect_status 0 env \
  CASUAL_REVIEW_USE_CAPSULE=1 \
  CAPSULE_HOST_WORKDIR= \
  CAPSULE_BIN="$capsule_bin" \
  CAPSULE_LOG="$capsule_log" \
  "$CLI" gerrit respond --help
[[ ! -e "$capsule_log" ]] ||
  die "plain Bash command entered Capsule"

expect_status 1 env \
  CASUAL_REVIEW_USE_CAPSULE=1 \
  CAPSULE_HOST_WORKDIR=/host/repository \
  CAPSULE_BIN="$capsule_bin" \
  CAPSULE_LOG="$capsule_log" \
  "$CLI" review --engine ''
[[ ! -e "$capsule_log" ]] ||
  die "review nested an existing Capsule"

expect_status 1 env \
  CASUAL_REVIEW_USE_CAPSULE=1 \
  CAPSULE_HOST_WORKDIR= \
  CAPSULE_BIN="$tmp/missing-capsule" \
  "$CLI" review --limit 1
grep -q 'Capsule executable not found' "$tmp/stderr" ||
  die "missing Capsule executable was not reported"

for name in \
  CASUAL_REVIEW_USE_CAPSULE CASUAL_REVIEW_ENGINE \
  CODEX_BIN CLAUDE_BIN ANTIGRAVITY_BIN \
  CODEX_MODEL CLAUDE_MODEL ANTIGRAVITY_MODEL \
  CODEX_EFFORT CLAUDE_EFFORT ANTIGRAVITY_EFFORT \
  CODEX_EXTRA_ARGS CLAUDE_EXTRA_ARGS ANTIGRAVITY_EXTRA_ARGS \
  SUMMARY_ENGINE OPENAI_API_KEY ANTHROPIC_API_KEY \
  GOOGLE_API_KEY GEMINI_API_KEY; do
  expected="${name} = \"\${${name}}\""
  grep -Fqx "$expected" "$ROOT_DIR/capsule.toml" ||
    die "capsule.toml does not forward $name"
done

grep -Fqx 'version = 1' "$ROOT_DIR/capsule.toml" ||
  die "capsule.toml does not use profile version 1"
grep -Fqx 'name = "casual-review"' "$ROOT_DIR/capsule.toml" ||
  die "capsule.toml has the wrong profile name"
[[ $(grep -c '^COPY --from=casual-review ' \
  "$ROOT_DIR/capsule.toml") == 4 ]] ||
  die "capsule.toml does not use the named build context"
if grep -Eq '^[[:space:]]*FROM[[:space:]]' "$ROOT_DIR/capsule.toml"; then
  die "capsule.toml contains a forbidden FROM instruction"
fi

expect_status 2 "$CLI"
expect_status 2 "$CLI" unknown
expect_status 2 "$CLI" gerrit
expect_status 2 "$CLI" gerrit unknown
expect_status 2 "$CLI" github
expect_status 2 "$CLI" github unknown

for command in \
  'review' \
  'process' \
  'completion' \
  'gerrit export' \
  'gerrit upload' \
  'gerrit respond' \
  'github upload'; do
  # Intentional word splitting: command contains dispatcher path segments.
  # shellcheck disable=SC2086
  expect_status 0 "$CLI" $command --help
done

ln -s "$CLI" "$tmp/casual-review"
expect_status 0 "$tmp/casual-review" gerrit upload --help

expect_status 1 "$CLI" review --engine ''
expect_status 1 "$CLI" process --reviews ''
expect_status 1 "$CLI" gerrit export --limit ''
expect_status 1 "$CLI" gerrit upload --engine ''
expect_status 1 "$CLI" gerrit respond --limit ''
expect_status 1 "$CLI" github upload --pr ''
expect_status 1 "$CLI" github upload --repo ''
expect_status 1 "$CLI" github upload --engine ''
expect_status 1 "$CLI" github upload --limit ''

expect_status 0 "$CLI" completion bash
bash -n "$tmp/stdout" || die "generated Bash completion is invalid"
grep -q '^complete -o filenames -F _casual_review casual-review$' \
  "$tmp/stdout" ||
  die "generated Bash completion does not register casual-review"
# shellcheck source=/dev/null
source "$tmp/stdout"
COMP_WORDS=(casual-review gerrit up)
COMP_CWORD=2
_casual_review
[[ "${COMPREPLY[*]}" == upload ]] ||
  die "Bash completion does not suggest Gerrit upload"
COMP_WORDS=(casual-review github up)
COMP_CWORD=2
_casual_review
[[ "${COMPREPLY[*]}" == upload ]] ||
  die "Bash completion does not suggest GitHub upload"
COMP_WORDS=(casual-review review --engine cod)
COMP_CWORD=3
_casual_review
[[ "${COMPREPLY[*]}" == codex ]] ||
  die "Bash completion does not suggest the Codex engine"
COMP_WORDS=(casual-review gerrit export --engine al)
COMP_CWORD=4
_casual_review
[[ "${COMPREPLY[*]}" == all ]] ||
  die "Bash completion does not suggest all Gerrit engines"
spaced_dir="$tmp/review outputs"
mkdir -p "$spaced_dir"
COMP_WORDS=(casual-review gerrit export "$tmp/rev")
COMP_CWORD=3
_casual_review
[[ ${#COMPREPLY[@]} == 1 && "${COMPREPLY[0]}" == "$spaced_dir" ]] ||
  die "Bash completion splits directory candidates containing spaces"
spaced_file="$tmp/prompt file.md"
touch "$spaced_file"
COMP_WORDS=(casual-review review --prompt "$tmp/pro")
COMP_CWORD=3
_casual_review
[[ ${#COMPREPLY[@]} == 1 && "${COMPREPLY[0]}" == "$spaced_file" ]] ||
  die "Bash completion splits file candidates containing spaces"

expect_status 0 "$CLI" completion zsh
grep -q '^#compdef casual-review$' "$tmp/stdout" ||
  die "generated Zsh completion has no compdef"
grep -Fq "'2:shell:(bash zsh fish)'" "$tmp/stdout" ||
  die "Zsh completion has the wrong shell argument position"
grep -Fq "'2:reviews directory:_directories'" "$tmp/stdout" ||
  die "Zsh completion has the wrong process path position"
grep -Fq "'3:reviews directory:_directories'" "$tmp/stdout" ||
  die "Zsh completion has the wrong Gerrit path position"
grep -Fq "'2:GitHub command:(upload)'" "$tmp/stdout" ||
  die "Zsh completion does not include GitHub upload"
[[ $(grep -c 'engine:(codex claude antigravity all)' "$tmp/stdout") == 4 ]] ||
  die "Zsh completion does not suggest all upload engines"
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$tmp/stdout" || die "generated Zsh completion is invalid"
fi

expect_status 0 "$CLI" completion fish
grep -q '^complete -c casual-review ' "$tmp/stdout" ||
  die "generated Fish completion has no registrations"
[[ $(grep -c "'codex claude antigravity all'" "$tmp/stdout") == 3 ]] ||
  die "Fish completion does not suggest all upload engines"
if command -v fish >/dev/null 2>&1; then
  fish -n "$tmp/stdout" || die "generated Fish completion is invalid"
fi

expect_status 2 "$CLI" completion
expect_status 2 "$CLI" completion ''
expect_status 2 "$CLI" completion powershell
expect_status 2 "$CLI" completion bash extra

printf 'CLI test ok\n'
