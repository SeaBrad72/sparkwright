# Branch Protection — reference setup (Go profile)

Enforces the §14 contract at the repo boundary: `main` protected, green CI to merge, builder ≠ sole merger. COPY & ADAPT — replace `OWNER/REPO` and team handles. `REQUIRED-CHECKS.md` (stamped from `templates/REQUIRED-CHECKS-TEMPLATE.md` at incept), not this file, is the source of truth `conformance/branch-protection.sh` and `scripts/branch-protection-apply.sh` read — declare your required contexts there.

## What to require
- The status-check contexts declared in `REQUIRED-CHECKS.md`. **Inception declares the five it installs** — `ci`, `control-plane-ratification`, `backlog-presence`, `ceremony-binding`, `loop-state` — so the gates the kit installs become the gates your protection requires **once you bind them** (`--apply`); `inception-done` names any still unbound until then. The block below is paste-ready; opt-ins you add by hand:
  ```
  ci
  control-plane-ratification
  backlog-presence
  ceremony-binding
  loop-state
  # ^ the five above are what incept declares: ci = every profile's CI job key; ratification.yml; adopter-gates.yml x3
  # provenance             <- uncomment once this profile's ci.yml gates on SLSA provenance
  # image-provenance       <- uncomment once this profile builds + attests a container image
  # <add-your-check-here>
  ```
  ⚠️ `loop-state` is bound because it **enforces**: `.github/workflows/adopter-gates.yml` ships `LOOP_STATE_MODE: enforce` (since 2026-08-30). If you opt out to `observe`, **unbind this context in the same edit** — in observe mode the job always exits 0 and GitHub treats that as satisfying a required check, so you would be left requiring a gate that enforces nothing.
- Optional, continuous detection (fork-neutral): a cron + `workflow_dispatch`-only workflow running `sh conformance/branch-protection.sh --require` under a fine-grained `Administration: read` PAT secret reds when a declared context is unbound. **No `pull_request` trigger** — fork PRs get no secret and would red forever, and a PR head could print the token. Detection, not prevention; rulesets are the preventing shape.
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
# loop-state enforces as shipped; unbind it if you ever set LOOP_STATE_MODE back to observe.
gh api --method POST repos/OWNER/REPO/branches/main/protection/required_status_checks/contexts -f 'contexts[]=loop-state'
```

> "Builder ≠ sole merger" is enforced by required reviews + CODEOWNERS. GitHub cannot strictly forbid every user from merging their own PR on all plans; on GitHub Enterprise use rulesets / required reviewers. Document the policy in the project `CLAUDE.md` regardless.

> **Solo + agent-authored track:** the apply script's `--replace` payload already sets `"enforce_admins": false` so the owner can admin-merge their own PR (`gh pr merge --admin`) — the audit-trailed self-ratification of `START-HERE.md`'s solo/lite track — and `"require_code_owner_reviews": false`, because **GitHub forbids self-approval**: while the sole owner is also the sole code owner, a required code-owner review is structurally unsatisfiable (the PR stays BLOCKED with green CI; only `--admin` clears it). Flip `enforce_admins` back to `true` and enable code-owner review only once a second reviewer exists. See [`docs/operations/review-lane.md`](../../docs/operations/review-lane.md) "Solo + agent-authored PRs".
