# `casual-review`

`casual-review` is a multi-engine generative AI assisted reviewer, a
read-oriented batch reviewer for a Git range, supporting:

- OpenAI Codex CLI
- Anthropic Claude Code CLI
- Google Antigravity CLI
- all three engines in one run

It reviews every commit in `BASE..HEAD` without checking commits out. Each
agent uses historical Git objects (`git diff`, `git show`) and writes one
Markdown file per commit. An aggregate `SUMMARY.md` is generated after the
individual reviews.

## Quick start

Extract this package, enter the repository to review, then run:

```bash
/path/to/casual-review/bin/review-commits \
  --engine all \
  --base origin/master \
  --head HEAD \
  --output ./ai-reviews
```

Start with three commits to tune output and cost:

```bash
/path/to/casual-review/bin/review-commits \
  --engine all --limit 3
```

Single-engine examples:

```bash
review-commits --engine codex
review-commits --engine claude
review-commits --engine antigravity
```

Add the package's `bin` directory to `PATH` for the shorter form.

## Result layout

```text
ai-reviews/
├── README.md
├── SUMMARY.md
├── failures.tsv
├── codex/
│   ├── 001-<sha>.md
│   └── ...
├── claude/
│   └── ...
└── antigravity/
    └── ...
```

## Authentication

Log in to each CLI normally before running the batch. The script reuses the
credentials and configuration of the installed command.

## Safety model

The prompt forbids modifications, builds, tests, package managers, and network
commands. Codex is explicitly placed in a read-only sandbox. Claude is limited
to read access and selected read-only Git command patterns. Antigravity is run
in non-interactive print mode; its exact permission configuration can vary by
CLI release, so configure its Fine-Grained Permissions Engine to deny writes
and shell commands other than read-only Git inspection before using it on a
valuable working tree. For stronger isolation, run the whole process on a
disposable clone.

## Configuration

Model and reasoning-effort selection, via flags (single engine only) or
per-engine environment variables (works with `--engine all` too):

```bash
review-commits --engine claude --model claude-sonnet-5 --effort high

CODEX_MODEL='<model>' CODEX_EFFORT='<level>' review-commits --engine codex
CLAUDE_MODEL='<model>' CLAUDE_EFFORT='<level>' review-commits --engine claude
ANTIGRAVITY_MODEL='<model>' ANTIGRAVITY_EFFORT='<level>' review-commits --engine antigravity
```

Valid effort levels are engine-specific (e.g. Claude accepts `low`, `medium`,
`high`, `xhigh`, `max`; Antigravity accepts `low`, `medium`, `high`); the
underlying CLI rejects invalid values. The resolved model and effort (or
`default` when unset) are recorded at the end of every per-commit review file,
in `SUMMARY.md`, and in the run's `README.md` index.

By default the script strips `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
`GOOGLE_API_KEY`, and `GEMINI_API_KEY` from each engine's environment, so a
batch run always falls back to the engine's logged-in plan/subscription
instead of silently billing metered API credits. Pass `--use-credits` to allow
metered billing instead:

```bash
review-commits --engine claude --use-credits
```

Verified behavior: for Claude, this reliably switches billing away from the
`claude.ai` subscription login to `ANTHROPIC_API_KEY` (confirmed directly — an
invalid key set alongside an active claude.ai login causes Claude to attempt
and fail the API-key path rather than silently using the subscription). For
Codex, an active `codex login` (ChatGPT) session took precedence over
`OPENAI_API_KEY` in testing regardless of this flag — to actually bill Codex
via OpenAI API credits, use `codex login --with-api-key` yourself first
(a persistent, global change outside this tool's scope). Antigravity's
behavior here is unverified.

Extra CLI arguments:

```bash
CODEX_EXTRA_ARGS='...' review-commits --engine codex
CLAUDE_EXTRA_ARGS='--max-turns 20' review-commits --engine claude
ANTIGRAVITY_EXTRA_ARGS='...' review-commits --engine antigravity
```

Because extra arguments are split by the shell script on whitespace, use them
for simple flags only. For complex quoting, make a wrapper executable and point
`CODEX_BIN`, `CLAUDE_BIN`, or `ANTIGRAVITY_BIN` to it.

Choose another engine for the aggregate summary:

```bash
SUMMARY_ENGINE=claude review-commits --engine all
```

## Running inside Capsule

This project's `Dockerfile` and `compose.yml` plug into
[Capsule](https://github.com/cursorinsight/casual-capsule)'s
`CAPSULE_CUSTOM_COMPOSE` custom-image mechanism directly — point it at this
checkout, no copying into the Capsule checkout required:

```bash
export CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml
cd /path/to/casual-capsule
./capsule.sh --build-custom
./capsule.sh review-commits --engine claude --base origin/master --head HEAD
```

`--build-custom` layers this project's `bin/` and `prompts/` on top of the
`casual-capsule-cli` base image and symlinks `review-commits` onto `PATH`.
Rerun it after changing `bin/review-commits` or the prompt templates.

## Notes

- Merge commits are compared with their first parent and trigger a warning.
- The script deliberately performs static review only. Testing historical commits
  requires isolated worktrees and a project-specific test strategy.
- `origin/master..HEAD` means commits reachable from `HEAD` but not from
  `origin/master`. Fetch first when the remote-tracking ref may be stale.
- Running all three engines triples the number of model calls, plus one summary.
