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

## Processing Review Feedback

`prompts/process-reviews.md` is a single-shot agent prompt for processing
generated review directories such as `ai-reviews/` or `reviews/`. Feed it to an
agent from the repository under review when you want to triage findings, apply
accepted fixes, append decisions to `DECISIONS.md`, squash clean fix commits
into their target commits, and audit the final branch delta.

`process-reviews` launches one selected agent with that prompt and an explicit
review directory:

```bash
process-reviews --engine codex
process-reviews --engine claude --reviews ./reviews
process-reviews --engine antigravity ./ai-reviews
```

The default review directory is `ai-reviews`. `--model`, `--effort`, and the
same `*_BIN`, `*_MODEL`, `*_EFFORT`, and `*_EXTRA_ARGS` environment overrides
used by `review-commits` are supported for the selected engine.

## Uploading to Gerrit

### Uploading Reviews

`upload-gerrit-reviews` reads a generated `ai-reviews` directory and uploads
the per-commit findings to Gerrit with its REST API. It posts inline comments
from each `Suggested Gerrit comment:` block and posts the review verdict as
the change message.

Each finding's `Location:` line decides where its comment lands. `path:line`
becomes a line comment, `path:line-range` uses the first line of the range,
and a bare `path` becomes a file-level comment. Any other trailing `:suffix`
is not a line number, so it is dropped and the comment is posted at file
level on the remaining path.

Dry-run is the default and makes no HTTP requests:

```bash
upload-gerrit-reviews ./ai-reviews
upload-gerrit-reviews --dry-run ./ai-reviews
```

Posting modes require Gerrit connection settings in environment variables:

```bash
export GERRIT_URL=https://gerrit.example.com
export GERRIT_USER="$USER"
export GERRIT_HTTP_PASSWORD='<http-password-or-token>'

upload-gerrit-reviews --interactive ./ai-reviews
upload-gerrit-reviews --yolo ./ai-reviews
```

When posting, the uploader passes credentials to `curl` through a temporary
config file with restrictive permissions, then removes it on exit. The Gerrit
HTTP password is not passed through `curl --user` argv.

Posting modes query existing Gerrit inline comments and review messages before
submitting. Already-posted AI inline comments and review verdict messages are
filtered out, so rerunning an upload does not duplicate them.

Gerrit requests use bounded curl timeouts so a stalled network cannot hang the
entire upload indefinitely. Override the defaults with
`GERRIT_CONNECT_TIMEOUT` (default: `10`) and `GERRIT_MAX_TIME`
(default: `120`), both in seconds.

`--interactive` shows a terminal review UI with progress, boxes, and
color-coded prompts before each inline comment and each review verdict. Set
`NO_COLOR=1` to disable colors. `--yolo` posts everything parsed from the
review files. Gerrit lookups use `commit:<sha>`; if that is ambiguous,
constrain them:

```bash
GERRIT_PROJECT=my/project \
GERRIT_BRANCH=master \
upload-gerrit-reviews --interactive ./ai-reviews
```

Optional review-label voting is deliberately explicit because Gerrit label
names and scores are site policy:

```bash
export GERRIT_LABELS_JSON='{
  "Reject": {"AI-Review": -2},
  "Needs changes": {"AI-Review": -1},
  "Looks good with minor comments": {"AI-Review": 1},
  "LGTM": {"AI-Review": 2}
}'
```

Without `GERRIT_LABELS_JSON`, verdicts are still posted as review messages but
no labels are voted. By default the uploader refuses to post a review when the
reviewed commit is not Gerrit's current revision for the change; set
`GERRIT_ALLOW_NON_CURRENT=1` to override.

### Uploading Responses

`respond-gerrit-reviews` reads the generated review files and a
`DECISIONS.md` file in the format used by `prompts/process-reviews.md`, finds
the already uploaded AI inline comments on Gerrit, and posts replies that
record the chosen decision, fix commit, squash target, checks, and reasoning.
It maps decisions to uploaded inline comments by review-file order. Decisions
for questions or other non-inline notes are posted as tagged Gerrit change
messages with a stable decision key when that review file had inline comments.
Decisions for commits with no uploaded review comments are ignored. Existing
response messages with the same decision key are skipped on reruns. For `Fix`
and `Skip` decisions, inline replies mark the Gerrit thread resolved:
Decision matching uses the decision title; `Reasoning` is posted as-is and
should contain only the final rationale.

```bash
respond-gerrit-reviews --dry-run ./ai-reviews ./ai-reviews/DECISIONS.md
respond-gerrit-reviews --interactive ./ai-reviews ./ai-reviews/DECISIONS.md
respond-gerrit-reviews --yolo ./ai-reviews ./ai-reviews/DECISIONS.md
```

As with uploads, set `GERRIT_ALLOW_NON_CURRENT=1` to reply on old patch sets.
`--interactive` shows a terminal response UI with progress, boxes, and
color-coded prompts. Set `NO_COLOR=1` to disable colors.

## Authentication

Log in to each CLI normally before running the batch. The script reuses the
credentials and configuration of the installed command.

## Safety model

`review-commits` is read-only: Codex is explicitly placed in a read-only
sandbox, Claude is limited to read access and selected read-only Git command
patterns, and Antigravity is run in non-interactive print mode.

`process-reviews` is intentionally not read-only. It starts an editing agent
from the repository under review, with Codex using a `workspace-write` sandbox
by default and Antigravity using `accept-edits` mode. For stronger isolation,
run review processing on a disposable clone or inside Capsule.

## Configuration

Model and reasoning-effort selection, via flags (single engine only) or
per-engine environment variables (works with `--engine all` too):

```bash
review-commits --engine claude --model claude-sonnet-5 --effort high

CODEX_MODEL='<model>' CODEX_EFFORT='<level>' review-commits --engine codex
CLAUDE_MODEL='<model>' CLAUDE_EFFORT='<level>' review-commits --engine claude
ANTIGRAVITY_MODEL='<model>' ANTIGRAVITY_EFFORT='<level>' \
  review-commits --engine antigravity
```

Valid effort levels are engine-specific (e.g. Claude accepts `low`, `medium`,
`high`, `xhigh`, `max`; Antigravity accepts `low`, `medium`, `high`); the
underlying CLI rejects invalid values. The model and effort actually used are
recorded at the end of every per-commit review file, in `SUMMARY.md`, and in
the run's `README.md` index — including when neither was overridden:

- Codex: both the real model and reasoning effort are parsed from its own
  startup banner (which reports them regardless of whether `--model`/
  `CODEX_EFFORT` were set), so nothing is ever reported as merely "default".
- Claude: the real model is recovered from `--output-format json`'s
  `modelUsage` (requires `jq`); when a run made more than one model call,
  the one with the most output tokens is reported, as a best-effort guess at
  which one produced the review. Effort is not exposed anywhere in Claude's
  output, so it still falls back to `CLAUDE_EFFORT` or `default` when
  `--effort` wasn't passed.
- Antigravity: neither is currently introspectable from its output, so both
  still fall back to `ANTIGRAVITY_MODEL`/`ANTIGRAVITY_EFFORT` or `default`.

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
CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
    /path/to/casual-capsule/capsule.sh review-commits \
    --engine claude --base origin/master --head HEAD
```

Upload a generated review directory with the same custom image:

```bash
CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
    /path/to/casual-capsule/capsule.sh env \
    GERRIT_URL=https://gerrit.example.com \
    GERRIT_USER='<gerrit-user>' \
    GERRIT_HTTP_PASSWORD='<http-password-or-token>' \
    upload-gerrit-reviews --interactive ./ai-reviews
```

Process a generated review directory with the same custom image:

```bash
CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
    /path/to/casual-capsule/capsule.sh process-reviews \
    --engine codex --reviews ./ai-reviews
```

Respond to uploaded Gerrit review comments from a processed decision log:

```bash
CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
    /path/to/casual-capsule/capsule.sh env \
    GERRIT_URL=https://gerrit.example.com \
    GERRIT_USER='<gerrit-user>' \
    GERRIT_HTTP_PASSWORD='<http-password-or-token>' \
    respond-gerrit-reviews --interactive ./ai-reviews ./ai-reviews/DECISIONS.md
```

`--build-custom` layers this project's `bin/` and `prompts/` on top of the
`casual-capsule-cli` base image and symlinks `review-commits`,
`process-reviews`, `upload-gerrit-reviews`, and `respond-gerrit-reviews` onto
`PATH`. Rerun it after changing scripts under `bin/` or the prompt templates.

To run `casual-review` inside a capsule directly from the CLI, the following
alias can come handy (applying Codex as the AI engine and `xhigh` reasoning
effort, for example):

```bash
alias review='CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
      capsule env \
      CODEX_EFFORT=xhigh \
      CODEX_EXTRA_ARGS="--dangerously-bypass-approvals-and-sandbox" \
      review-commits --engine codex'
```

## Testing

Run local sanity tests with:

```bash
./tests/test_all.sh
```

Run local linters with:

```bash
./tests/check_all.sh
```

`test_all.sh` checks command help paths and runs the script tests under
`tests/`.
`check_all.sh` runs `shellcheck` over shell scripts plus `hadolint` over
`Dockerfile`. When a linter is not installed locally, `check_all.sh` falls
back to Docker. CI runs hadolint and shellcheck as separate checker steps and
calls only `test_all.sh` from the test job.

## Notes

- Merge commits are compared with their first parent and trigger a warning.
- The script deliberately performs static review only. Testing historical
  commits requires isolated worktrees and a project-specific test strategy.
- `origin/master..HEAD` means commits reachable from `HEAD` but not from
  `origin/master`. Fetch first when the remote-tracking ref may be stale.
- Running all three engines triples the number of model calls, plus one summary.
