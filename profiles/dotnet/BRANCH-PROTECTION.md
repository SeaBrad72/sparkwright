# Branch Protection — reference setup (.NET profile)

Enforces the §14 contract at the repo boundary: `main` protected, green CI to merge, builder ≠ sole merger. COPY & ADAPT — replace `OWNER/REPO` and team handles. `REQUIRED-CHECKS.md` (stamped from `templates/REQUIRED-CHECKS-TEMPLATE.md` at incept), not this file, is the source of truth `conformance/branch-protection.sh` and `scripts/branch-protection-apply.sh` read — declare your required contexts there.

## What to require
- The status-check contexts declared in `REQUIRED-CHECKS.md` — at minimum the CI status check (`ci`); add `control-plane-ratification` once you require it:
  ```
  ci
  control-plane-ratification
  # provenance             <- uncomment once this profile's ci.yml gates on SLSA provenance
  # image-provenance       <- uncomment once this profile builds + attests a container image
  # backlog-presence       <- uncomment once you install profiles/adopter-gates.yml (Inception) and want gated PRs to require a bound board row before merge
  # ceremony-binding       <- uncomment once you want a gated PR to require a recorded design GO before merge
  # loop-state             <- uncomment ONLY after flipping LOOP_STATE_MODE to enforce in .github/workflows/adopter-gates.yml (binding it in observe mode is a silent pass-through — GitHub treats the posted `neutral` conclusion as satisfying a required check)
  # <add-your-check-here>
  ```
- At least 1 approving review from someone other than the author.
- Stale approvals dismissed on new commits.
- Branch up to date before merge.
- (Org/plan-dependent) CODEOWNERS review required; self-merge disallowed.

## Apply it
`sh scripts/branch-protection-apply.sh` reads `REQUIRED-CHECKS.md` and shows the diff by default (no mutation). Run it **after** the CI workflow has run at least once (so its check names are registered):
- **`--apply`** POSTs only the missing contexts via GitHub's ADDITIVE `.../protection/required_status_checks/contexts` endpoint — every other protection setting is left untouched.
- **`--replace`** performs the one-time full-object PUT that ESTABLISHES protection on a brand-new repo (reviews + `enforce_admins` + the declared contexts together) — it OVERWRITES every existing setting, resetting the non-context settings to the solo-owner defaults `enforce_admins:false` · `required_approving_review_count:1` · `require_code_owner_reviews:false` (see the note below), so it sits behind its own typed, tty-gated confirmation (piped input, e.g. `yes REPLACE |`, can never drive it). Use it once at setup; prefer `--apply` afterwards.

A single manual additive call (no script) looks like:
```bash
gh api --method POST repos/OWNER/REPO/branches/main/protection/required_status_checks/contexts -f 'contexts[]=ci'
```

Once `profiles/adopter-gates.yml` is installed (Inception) and you want to require its checks, the same additive call per context:
```bash
gh api --method POST repos/OWNER/REPO/branches/main/protection/required_status_checks/contexts -f 'contexts[]=backlog-presence'
gh api --method POST repos/OWNER/REPO/branches/main/protection/required_status_checks/contexts -f 'contexts[]=ceremony-binding'
# loop-state: bind this ONLY after flipping LOOP_STATE_MODE to enforce — see the note above.
gh api --method POST repos/OWNER/REPO/branches/main/protection/required_status_checks/contexts -f 'contexts[]=loop-state'
```

> "Builder ≠ sole merger" is enforced by required reviews + CODEOWNERS. GitHub cannot strictly forbid every user from merging their own PR on all plans; on GitHub Enterprise use rulesets / required reviewers. Document the policy in the project `CLAUDE.md` regardless.

> **Solo + agent-authored track:** the apply script's `--replace` payload already sets `"enforce_admins": false` so the owner can admin-merge their own PR (`gh pr merge --admin`) — the audit-trailed self-ratification of `START-HERE.md`'s solo/lite track — and `"require_code_owner_reviews": false`, because **GitHub forbids self-approval**: while the sole owner is also the sole code owner, a required code-owner review is structurally unsatisfiable (the PR stays BLOCKED with green CI; only `--admin` clears it). Flip `enforce_admins` back to `true` and enable code-owner review only once a second reviewer exists. See [`docs/operations/review-lane.md`](../../docs/operations/review-lane.md) "Solo + agent-authored PRs".
