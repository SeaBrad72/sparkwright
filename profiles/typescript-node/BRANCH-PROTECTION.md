# Branch Protection — reference setup (TypeScript/Node profile)

Enforces the §14 contract at the repo boundary: `main` protected, green CI to merge, builder ≠ sole merger. COPY & ADAPT — replace `OWNER/REPO` and team handles.

## What to require
- The CI status check (`ci`) must pass before merge.
- At least 1 approving review from someone other than the author.
- Stale approvals dismissed on new commits.
- Branch up to date before merge.
- (Org/plan-dependent) CODEOWNERS review required; self-merge disallowed.

## Apply via GitHub CLI
Run **after** the CI workflow has run at least once (so the check name `ci` is registered):

```bash
gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["ci"] },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true
  },
  "restrictions": null
}
JSON
```

> "Builder ≠ sole merger" is enforced by required reviews + CODEOWNERS. GitHub cannot strictly forbid every user from merging their own PR on all plans; on GitHub Enterprise use rulesets / required reviewers. Document the policy in the project `CLAUDE.md` regardless.
