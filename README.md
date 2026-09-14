# 🤖 Casual Review

[![ci][ci-badge]][ci]
[![License][license-badge]][license]
[![Shell][shell-badge]][shell]
[![Shellcheck][shellcheck-badge]][shellcheck]
[![Tooling][mise-badge]][mise]

A multi-engine generative AI assisted reviewer.

## Table of contents

- [Quick start](#-quick-start)
- [Shell Completion](#%EF%B8%8F-shell-completion)
- [Result layout](#-result-layout)
- [Processing Review Feedback](#-processing-review-feedback)
- [Uploading to Gerrit](#-uploading-to-gerrit)
  - [Uploading Reviews](#uploading-reviews)
  - [Uploading Responses](#uploading-responses)
- [Uploading to GitHub](#-uploading-to-github)
- [Authentication](#-authentication)
- [Safety model](#%EF%B8%8F-safety-model)
- [Configuration](#-configuration)
- [Running inside Capsule](#-running-inside-capsule)
- [Testing](#-testing)
- [Notes](#-notes)

## 🚀 Quick start

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

Extract this package, enter the repository to review, then run:

```bash
/path/to/casual-review/bin/casual-review review \
  --engine all \
  --base origin/master \
  --head HEAD \
  --output ./ai-reviews
```

Start with three commits to tune output and cost:

```bash
/path/to/casual-review/bin/casual-review review \
  --engine all --limit 3
```

Single-engine examples:

```bash
casual-review review --engine codex
casual-review review --engine claude
casual-review review --engine antigravity
```

Add the package's `bin` directory to `PATH` for the shorter form.

The package exposes one public executable:

```text
casual-review review
casual-review process
casual-review completion bash|zsh|fish
casual-review gerrit export
casual-review gerrit upload
casual-review gerrit respond
casual-review github upload
```

## ⌨️ Shell Completion

`casual-review completion` generates native completion code. Regenerate it
after updating `casual-review` so command and option lists stay current.

Bash, using the standard per-user `bash-completion` directory:

```bash
mkdir -p "$HOME/.local/share/bash-completion/completions"
casual-review completion bash > \
  "$HOME/.local/share/bash-completion/completions/casual-review"
```

Zsh, using a per-user function directory already present in `fpath`:

```zsh
mkdir -p "$HOME/.local/share/zsh/site-functions"
casual-review completion zsh > \
  "$HOME/.local/share/zsh/site-functions/_casual-review"
```

Add that directory to `fpath` before `compinit` when it is not already there:

```zsh
fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
autoload -Uz compinit && compinit
```

Fish loads completions directly from its per-user completion directory:

```fish
mkdir -p "$HOME/.config/fish/completions"
casual-review completion fish > \
  "$HOME/.config/fish/completions/casual-review.fish"
```

## 📂 Result layout

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

## 🔄 Processing Review Feedback

`prompts/process-reviews.md` is a single-shot agent prompt for processing
generated review directories such as `ai-reviews/` or `reviews/`. Feed it to an
agent from the repository under review when you want to triage findings, apply
accepted fixes, append decisions to `DECISIONS.md`, squash clean fix commits
into their target commits, and audit the final branch delta.

`casual-review process` launches one selected agent with that prompt and an
explicit review directory:

```bash
casual-review process --engine codex
casual-review process --engine claude --reviews ./reviews
casual-review process --engine antigravity ./ai-reviews
```

The default review directory is `ai-reviews`. `--model`, `--effort`, and the
same `*_BIN`, `*_MODEL`, `*_EFFORT`, and `*_EXTRA_ARGS` environment overrides
used by `casual-review review` are supported for the selected engine.
Set `CASUAL_REVIEW_ENGINE` to choose the default engine without a flag.

## 📤 Uploading to Gerrit

### Uploading Reviews

#### CLI Uploads

`casual-review gerrit upload` reads a generated `ai-reviews` directory and
uploads the per-commit findings to Gerrit with its REST API. It posts inline
comments from each `Suggested review comment:` block and posts the review
verdict as the change message.

Dry-run is the default and makes no HTTP requests:

```bash
casual-review gerrit upload
casual-review gerrit upload --dry-run
```

Posting modes require Gerrit connection settings in environment variables:

```bash
export GERRIT_URL=https://gerrit.example.com
export GERRIT_USER="$USER"
export GERRIT_HTTP_PASSWORD='<http-password-or-token>'

casual-review gerrit upload --interactive
casual-review gerrit upload --yolo
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
casual-review gerrit upload --interactive
```

The default review directory is `./ai-reviews`. Pass a path only when using a
different generated review directory.

#### Labels and Patch Sets

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

Browser userscripts and plugins also use `GERRIT_LABELS_JSON`, but at
generation time. Run the `make` target with the variable set when you want
browser-submitted verdicts to vote labels. If it is undefined, `make` prints a
warning and the generated browser uploader does not add label votes beyond
labels already present in the uploaded bundle.

#### Browser Bundle Export

For browser-based uploads, export one compressed JSON bundle per Gerrit change:

```bash
casual-review gerrit export --engine claude
```

Bundles are written to `./ai-reviews/gerrit-browser-upload/` by default, using
the 7-character reviewed commit hash as the file name.

#### Tampermonkey Userscript

For personal browser use, generate the Tampermonkey userscript for your Gerrit
URL and install it in [Tampermonkey](https://www.tampermonkey.net/):

```bash
make userscript \
    GERRIT_URL=https://gerrit.example.com/r \
    GERRIT_LABELS_JSON="$GERRIT_LABELS_JSON"
```

`GERRIT_URL` is required. The target writes
`browser/upload-gerrit-reviews.user.js` with a userscript `@match` line such as
`https://gerrit.example.com/r/c/*`, preserving the scheme and base path. The
URL must include the scheme, such as `https://`.
Open the matching Gerrit change page, click `Upload AI review`, load the
matching `.json.gz` file, select or unselect items, then submit. The browser
uploader uses the existing Gerrit web session and XSRF cookie; it does not need
`GERRIT_HTTP_PASSWORD`. It refuses to submit if the bundle commit is not the
current Gerrit revision, and it marks already-posted AI comments and verdicts
as duplicates before submission.

#### Gerrit Plugin

Use either the userscript or the plugin, not both. As a server-wide
alternative, generate and install the standalone Gerrit JavaScript plugin:

```bash
make gerrit-plugin GERRIT_LABELS_JSON="$GERRIT_LABELS_JSON"
cp browser/casual-review-upload.js "$GERRIT_SITE/plugins/"
```

The file name is the Gerrit plugin name. After the plugin is loaded by Gerrit,
refresh a change page and use the same `Upload AI review` flow. The plugin does
not need a Tampermonkey `@match` host and uses the same browser session as the
userscript. See Gerrit's JavaScript plugin documentation for standalone plugin
loading details:
<https://gerrit-review.googlesource.com/Documentation/pg-plugin-dev.html>

#### Gerrit Browser Test

The Playwright test exercises the installed plugin against Gerrit staging. It
creates a work-in-progress change in an existing test project, submits a
selected inline comment and verdict, verifies Gerrit's stored comments,
message, and label vote, checks duplicate and stale-patch-set handling, then
abandons the change. Set `GERRIT_TEST_PROJECT` to a project where the test
account can create changes.

Install the pinned test dependency and Chromium once:

```bash
make install-deps
```

Authenticate with a saved browser session. The state file contains credentials
and is ignored by Git:

```bash
make login GERRIT_URL=https://gerrit.example.com/r
```

Sign in, close the browser, then run the destructive staging test explicitly:

```bash
make test-gerrit-browser \
    GERRIT_URL=https://gerrit.example.com/r \
    GERRIT_E2E_ALLOW_WRITES=1 \
    GERRIT_IGNORE_HTTPS_ERRORS=1 \
    GERRIT_TEST_PROJECT=project-name
```

`GERRIT_URL` and `GERRIT_TEST_PROJECT` are required. Override
`GERRIT_STORAGE_STATE` when needed. As an alternative to saved state, set
`GERRIT_USER` and the LDAP `GERRIT_PASSWORD`; the Gerrit HTTP password is not
an LDAP login password. The test account must be able to create changes and
vote `AI-Review` in the selected project.

#### Generated Browser Artifacts

Both browser integrations are generated from
`browser/casual-review-upload-core.js`. After editing the shared core, run
`make browser-artifacts` to refresh both generated files. Generated browser
artifacts are ignored by git.

### Uploading Responses

`casual-review gerrit respond` reads the generated review files and a
`DECISIONS.md` file in the format used by `prompts/process-reviews.md`, finds
the already uploaded AI inline comments on Gerrit, and posts replies recording
the chosen decision, fix commit, squash target, checks, and reasoning.
It maps decisions to uploaded inline comments by review-file order. Decisions
for questions or other non-inline notes are posted as tagged Gerrit change
messages with a stable decision key when that review file had inline comments.
Decisions for commits with no uploaded review comments are ignored. Existing
response messages with the same decision key are skipped on reruns. For `Fix`
and `Skip` decisions, inline replies mark the Gerrit thread resolved:
Decision matching uses the decision title; `Reasoning` is posted as-is and
should contain only the final rationale.

```bash
casual-review gerrit respond --dry-run
casual-review gerrit respond --interactive
casual-review gerrit respond --yolo
```

As with uploads, set `GERRIT_ALLOW_NON_CURRENT=1` to reply on old patch sets.
`--interactive` shows a terminal response UI with progress, boxes, and
color-coded prompts. Set `NO_COLOR=1` to disable colors.

The default review directory is `./ai-reviews`, and the default decisions file
is `./ai-reviews/DECISIONS.md`. Pass a review directory to use its
`DECISIONS.md`; pass both paths only when the decision log lives elsewhere.

## 📤 Uploading to GitHub

`casual-review github upload` submits generated findings as pull-request
reviews through the GitHub CLI. Dry-run is the default and does not invoke
`gh`:

```bash
casual-review github upload
casual-review github upload --dry-run ./reviews
```

For real uploads, install `gh`, set `GITHUB_TOKEN` or `GH_TOKEN`, or log in
with `gh auth login`. The token needs write access to pull requests.

```bash
export GITHUB_TOKEN='<token>'
casual-review github upload --interactive
casual-review github upload --yolo
```

By default, `gh pr view` selects the pull request for the current branch. Use
`--pr` with a pull-request number, URL, or branch, and `--repo` when operating
outside the repository selected by the current checkout:

```bash
casual-review github upload --pr 123 --repo owner/repository --yolo
```

Inline comments from each review file are submitted as one atomic `COMMENT`
review against its recorded commit. The commit must belong to the selected
pull request. GitHub only accepts batched inline comments on lines in the
pull-request diff, so findings without a line number are skipped. Locations
use the reviewed file's post-commit line on the `RIGHT` side. If GitHub rejects
any location, it rejects that commit's review request without partially
posting its other comments.

Selected verdicts are accumulated across all processed review files. After
the inline comments, the uploader submits one unified verdict pinned to the
pull-request head captured at startup. It refuses the verdict if the head
changes before submission. The strictest selected verdict wins, so a later
clean commit cannot override an earlier request for changes. In strictness
order: `Reject`, `Needs changes`, `Looks good with minor comments`, then
`LGTM`.

An `APPROVE` verdict additionally requires selected verdicts for every commit
currently in the pull request. Partial selections such as `--limit 1` fail
instead of approving unreviewed commits. Dry-run stays network-free, so it
prints the prospective verdict without remote head or coverage validation.

Verdicts map to GitHub review events as follows:

- `Reject` and `Needs changes`: `REQUEST_CHANGES`
- `Looks good with minor comments`: `COMMENT`
- `LGTM`: `APPROVE`

Before posting, the uploader loads existing reviews and inline comments.
Exact duplicates for the same engine, commit, path, and line are skipped, as
is an identical unified verdict. `--interactive` uses the same terminal UI as
the Gerrit uploader and confirms the final unified verdict separately.

GitHub review creation and line-location constraints are documented in the
[pull-request review API](https://docs.github.com/en/rest/pulls/reviews).
Authentication behavior comes from
[GitHub CLI](https://cli.github.com/manual/gh_help_environment).

## 🔑 Authentication

Log in to each CLI normally before running the batch. The script reuses the
credentials and configuration of the installed command.

## 🛡️ Safety model

`casual-review review` is read-only: Codex is explicitly placed in a read-only
sandbox, Claude is limited to read access and selected read-only Git command
patterns, and Antigravity is run in non-interactive print mode.

`casual-review process` is intentionally not read-only. It starts an editing
agent from the repository under review, with Codex using a `workspace-write`
sandbox by default and Antigravity using `accept-edits` mode. For stronger
isolation, run review processing on a disposable clone or inside Capsule.

## 🔧 Configuration

Model and reasoning-effort selection, via flags (single engine only) or
per-engine environment variables (works with `--engine all` too):

```bash
CASUAL_REVIEW_ENGINE=claude casual-review review

casual-review review --engine claude --model claude-sonnet-5 --effort high

CODEX_MODEL='<model>' CODEX_EFFORT='<level>' \
  casual-review review --engine codex
CLAUDE_MODEL='<model>' CLAUDE_EFFORT='<level>' \
  casual-review review --engine claude
ANTIGRAVITY_MODEL='<model>' ANTIGRAVITY_EFFORT='<level>' \
  casual-review review --engine antigravity
```

`CASUAL_REVIEW_ENGINE` also supplies the default `--engine` filter for Gerrit
export/upload and GitHub upload commands. An explicit `--engine` always
overrides it. Use `all` or leave the filter unset to include every engine.

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
casual-review review --engine claude --use-credits
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
CODEX_EXTRA_ARGS='...' casual-review review --engine codex
CLAUDE_EXTRA_ARGS='--max-turns 20' casual-review review --engine claude
ANTIGRAVITY_EXTRA_ARGS='...' casual-review review --engine antigravity
```

Because extra arguments are split by the shell script on whitespace, use them
for simple flags only. For complex quoting, make a wrapper executable and point
`CODEX_BIN`, `CLAUDE_BIN`, or `ANTIGRAVITY_BIN` to it.

Choose another engine for the aggregate summary:

```bash
SUMMARY_ENGINE=claude casual-review review --engine all
```

## 💊 Running inside Capsule

This project's `Dockerfile` and `compose.yml` plug into
[Capsule](https://github.com/cursorinsight/casual-capsule)'s
`CAPSULE_CUSTOM_COMPOSE` custom-image mechanism directly — point it at this
checkout, no copying into the Capsule checkout required:

```bash
CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
    /path/to/casual-capsule/capsule.sh casual-review review \
    --engine claude --base origin/master --head HEAD
```

Upload a generated review directory with the same custom image:

```bash
CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
    /path/to/casual-capsule/capsule.sh env \
    GERRIT_URL=https://gerrit.example.com/r \
    GERRIT_USER='<gerrit-user>' \
    GERRIT_HTTP_PASSWORD='<http-password-or-token>' \
    casual-review gerrit upload --interactive
```

Export browser-upload bundles from a generated review directory:

```bash
CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
    /path/to/casual-capsule/capsule.sh casual-review gerrit export \
    --engine claude
```

Process a generated review directory with the same custom image:

```bash
CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
    /path/to/casual-capsule/capsule.sh casual-review process \
    --engine codex --reviews ./ai-reviews
```

Respond to uploaded Gerrit review comments from a processed decision log:

```bash
CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
    /path/to/casual-capsule/capsule.sh env \
    GERRIT_URL=https://gerrit.example.com/r \
    GERRIT_USER='<gerrit-user>' \
    GERRIT_HTTP_PASSWORD='<http-password-or-token>' \
    casual-review gerrit respond --interactive
```

`--build-custom` layers this project's CLI and prompts on top of the
`casual-capsule-cli` base image and puts `casual-review` on `PATH`. Rerun it
after changing files under `bin/`, `lib/`, `libexec/`, or `prompts/`.

To run `casual-review` inside a capsule directly from the CLI, the following
alias can come handy (applying Codex as the AI engine and `xhigh` reasoning
effort, for example):

```bash
alias review='CAPSULE_CUSTOM_COMPOSE=/path/to/casual-review/compose.yml \
      capsule env \
      CODEX_EFFORT=xhigh \
      CODEX_EXTRA_ARGS="--dangerously-bypass-approvals-and-sandbox" \
      casual-review review --engine codex'
```

## 🧪 Testing

Run local sanity tests with:

```bash
make test
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

Remove generated browser artifacts with:

```bash
make clean
```

## 📝 Notes

- Merge commits are compared with their first parent and trigger a warning.
- The script deliberately performs static review only. Testing historical
  commits requires isolated worktrees and a project-specific test strategy.
- `origin/master..HEAD` means commits reachable from `HEAD` but not from
  `origin/master`. Fetch first when the remote-tracking ref may be stale.
- Running all three engines triples the number of model calls, plus one summary.


[ci-badge]: ../../actions/workflows/ci.yml/badge.svg
[ci]: ../../actions/workflows/ci.yml
[license-badge]: https://img.shields.io/badge/license-Apache%202.0-blue
[license]: LICENSE
[mise-badge]: https://img.shields.io/badge/tools-mise-orange
[mise]: https://mise.en.dev
[shell-badge]: https://img.shields.io/badge/shell-bash-green?logo=gnu-bash
[shell]: bin/casual-review
[shellcheck-badge]: https://img.shields.io/badge/lint-shellcheck-yellow
[shellcheck]: https://www.shellcheck.net
