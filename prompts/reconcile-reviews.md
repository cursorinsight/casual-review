You are reconciling completed commit-local reviews against the final branch
head. Do not add findings or questions. Decide only whether existing review
items remain actionable at final HEAD.

For every supplied review:

1. Inspect each finding at the reviewed commit and at final HEAD.
   Inspect each question against final HEAD too.
2. Start correlation with its `path::nearest-symbol` fingerprint.
3. Use Gerrit Change-Id as a strong identity only when both sides provide one.
4. Without Change-Id, use reviewed subject, range position, prior review
   metadata, and semantic equivalence.
5. Treat a prior Fix as evidence, not proof. Verify the final code and history.
6. Keep a prior Skip only while its relevant code and rationale are unchanged.
7. For legacy decisions, inspect the referenced review and match semantically.
   Keep ambiguous matches actionable.
8. Locate downstream fixes with `git log <reviewed>..FINAL_HEAD -- <path>` and
   `git show`. Never reuse an ephemeral fix hash from a decision log.

Return JSON only, with exactly this shape:

```json
{
  "reviews": [
    {
      "path": "engine/001-abcdef123456.md",
      "verdict": "LGTM",
      "reconciled": [
        {
          "ordinal": 1,
          "fingerprint": "path/to/file::nearest-symbol",
          "status": "fixed_downstream",
          "commit": "1234567",
          "decision": null
        },
        {
          "ordinal": 2,
          "fingerprint": "path/to/file::<file-scope>",
          "status": "prior_skip_valid",
          "commit": null,
          "decision": "## 2026-10-01T12:00:00Z - abcdef1 - Title"
        }
      ],
      "questions": [
        {
          "ordinal": 1,
          "text": "Could this path run with an empty input?",
          "status": "fixed_downstream",
          "commit": "1234567",
          "decision": null
        }
      ]
    }
  ]
}
```

Include every supplied review exactly once. Use its exact relative path.
Include only findings that should no longer be uploaded or processed under
`reconciled`. Use an empty array when all findings remain actionable.
`ordinal` is the finding's 1-based position under that review's `Findings`
section. It disambiguates findings that share a fingerprint. Copy the exact
fingerprint from that finding.
Under `questions`, include only questions that are no longer actionable. Use
their 1-based position under `Questions` and copy their exact first-line text.
Use an empty array when every question remains actionable.

Derive each verdict from items that remain actionable after reconciliation:

- `Reject` when any Critical finding remains;
- `Needs changes` when any Major finding remains;
- `Looks good with minor comments` when Minor findings or questions remain;
- `LGTM` only when no findings or questions remain.

Use `fixed_downstream` only when a later commit demonstrably fixes the finding,
and provide that commit's 7-character hash; set `decision` to null. Use
`prior_skip_valid` only for an unchanged finding with a matching prior Skip
decision. Set `commit` to null and copy that decision's exact `## ` heading into
`decision`. Use `prior_fix_valid` when a matching prior Fix remains correct in
the reviewed commit itself and its decision records
`Fix placement: Reviewed commit`; reference its heading in the same way.
These statuses also apply to questions. Do not include prose, Markdown
fences, additional keys, or items absent from the supplied reviews.
