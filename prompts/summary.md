Read the generated Markdown commit reviews under the directory given below.
Do not independently review source code again. Consolidate only findings
already present in those reports. Do not turn questions into confirmed defects
and do not invent findings.

Treat findings and questions with a `Reconciliation` field as non-actionable
history. Do not include them in tables or counts. Use the verdict under
`Final-HEAD reconciliation`, when present. A commit with only reconciled items
belongs under `Commits with no actionable findings`.

Review directory: {{REVIEW_DIR}}

Produce Markdown with exactly these sections:

# Review summary

## Immediate attention

A table containing only Critical and Major findings:

| Engine | Commit | Severity | Confidence | File | Finding | Action |
|---|---|---|---|---|---|---|

## Minor findings

A compact table of Minor findings.

## Questions for authors

Group questions by commit and identify the review engine.

## Commits with no actionable findings

List commits whose review found nothing worth posting.

## Possible duplicates or disagreements

Identify duplicate findings and disagreements between engines. Do not resolve a
disagreement unless the reports themselves contain enough evidence.

## Suggested human review order

Order commits from highest to lowest priority and briefly explain why.

## Statistics

Include reviews read, distinct commits, findings by severity, and LGTM verdicts.
