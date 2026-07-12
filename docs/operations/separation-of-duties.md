# Separation of Duties — author ≠ approver

**Purpose:** ensure the identity that builds a change cannot also be the identity that ratifies it.

---

## Principle

An agent must not ratify its own work. The contract is: **author ≠ approver ≠ commit-authors** — every identity that appears in the commit history of a branch is a *builder*, and no builder may be the *sole ratifier*.

The critical constraint for agentic workflows is that the ratifying identity must be one the **building agent cannot assume**. A second token, a second bot account, or a second identity that the same agent process can mint or impersonate does not satisfy separation of duties — the agent would be self-approving with a credential it controls. The constraint is a *human-in-the-loop* or a *distinct controlled identity outside the build agent's reach* — not just a second label.

---

## Tiers

**Solo / lite** — a single maintainer with no distinct build bot. This case uses the honest admin-merge convention: the maintainer is simultaneously author and ratifier, but the forge logs the `--admin` bypass as an explicit, audit-visible act. The `REVIEW-RECORD` plus an independent agent review and automated CI gates form the compensating control set. See [`review-lane.md`](review-lane.md) "Solo + agent-authored PRs" for the full reasoning and its honest ceiling.

**Team / enterprise** — a distinct ratifying identity exists (a human with write access, or a second controlled identity outside the build agent). Here the SoD constraint is satisfiable: the build agent opens the PR under its own identity, and a different identity approves it. The rest of this document covers how to wire that configuration.

---

## The FLOOR — `scripts/sod-check.sh`

The kit proves the neutral SoD logic in `scripts/sod-check.sh`. It is zero forge-specific code: a pure identity-set comparison that any CI platform, any harness, and any human auditor can read and reason about.

**Three env inputs (normalized — trimmed, case-folded — before comparison):**

| Variable | Content |
|----------|---------|
| `SOD_AUTHOR` | The PR/MR author's stable machine identity (login or email — not a display name). |
| `SOD_APPROVERS` | The set of approving-reviewer identities, newline- or space-separated. |
| `SOD_COMMIT_AUTHORS` | The set of commit-author identities on the branch, newline- or space-separated. |

**Decision:** PASS iff at least one identity in `SOD_APPROVERS` is distinct from `SOD_AUTHOR` **and** distinct from every identity in `SOD_COMMIT_AUTHORS`. Both conditions must hold for a given approver — an approver who also committed is treated as a builder, not a ratifier.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | PASS — a qualifying distinct approver was found. |
| `1` | FAIL — no qualifying approver, or the self-test failed. Also returned when inputs are absent/empty **and** the environment is `CI=true` or the `--require` flag is passed (fail-closed, anti-vacuity). |
| `2` | UNVERIFIED — inputs absent/empty in a non-CI, non-`--require` context; cannot evaluate. |

The fail-closed behaviour on missing inputs under CI is deliberate — the E4b red-team lesson: a gate that exits 0 when it cannot read its inputs silently vacuates itself.

**Identities must be stable machine identities** (GitHub logins, GitLab usernames, email addresses) — not display names, which are user-controlled and non-unique.

Prove the logic is correct at any time:

```sh
sh scripts/sod-check.sh --selftest
```

This runs the full fixture table (distinct approver, author-only approves, approver who committed, empty approvals, casing variants) and exits non-zero if any fixture regresses.

---

## NATIVE — GitHub

The recommended pattern on GitHub is a **GitHub App token** as the build agent's authoring identity:

- The App is a distinct PR author (its login is `<app-slug>[bot]`), so the PR author is different from any human reviewer from the moment the PR is opened.
- A GitHub App token is scoped — the App can be granted only the permissions it needs (contents + pull-requests), with no human-seat cost.
- The App must **not** be listed in `CODEOWNERS`. If it were, GitHub's code-owner review requirement would demand the App's approval for its own PR — structurally unsatisfiable (`review-lane.md` "Solo + agent-authored PRs", caveat 2). Keep the App off `CODEOWNERS` so that human code-owner approval is the *distinct* ratification.

A **machine user** (a separate GitHub account) is the simpler alternative — no App registration required — at the cost of occupying a seat and offering less granular token scoping.

**Reference workflow:** [the reference workflow](sod-gate.github.yml) is a copy-and-adapt workflow at `docs/operations/sod-gate.github.yml`. It gathers identities from the PR event and the GitHub reviews API, passes them as `SOD_*` env vars, and calls `sh scripts/sod-check.sh --require`. Copy it into your repo's `.github/workflows/` and add `separation-of-duties / author-not-approver` as a **required status check** on `main`. All dynamic values flow via `env:` — no `${{ }}` expressions appear inside `run:` blocks.

---

## NATIVE — GitLab

GitLab satisfies the SoD constraint natively through Merge Request approval settings. No additional CI gate is required — enable the platform controls and the constraint is enforced server-side:

- **Prevent approval by author** — the MR author cannot approve their own MR.
- **Prevent approvals by users who added commits** — any user who pushed a commit to the branch is excluded from approving it.

Both options live in **Settings → Merge requests → Approval settings**. Together they express the same author ≠ approver ≠ commit-authors contract that `sod-check.sh` proves neutrally.

See [`gitlab-adoption.md`](gitlab-adoption.md) for the full GitLab wiring guide, including MR approval rules and CODEOWNERS scoping.

---

## Other forges

Apply the contract through your forge's equivalent mechanism: an approval rule that prohibits the PR/MR author from self-approving, combined with a rule that excludes commit authors from the approver pool. Feed the resulting identities into `SOD_AUTHOR`, `SOD_APPROVERS`, and `SOD_COMMIT_AUTHORS` and invoke `sh scripts/sod-check.sh --require` in CI to prove the neutral contract holds.

---

## Honest ceiling

**Server-side enforcement is the adopter's responsibility**, not the kit's. The kit proves the neutral logic (`scripts/sod-check.sh`) and provides per-forge reference bindings (the workflow above, the GitLab pointer). What it cannot do:

- **Run a live distinct-approver scenario in kit CI.** The kit is itself the solo case — no second controlled identity exists to open PRs and be approved by a human. The self-test proves the *logic* is correct; it cannot prove that a live forge org is configured to enforce the constraint server-side.
- **Gate the kit's own PRs via this workflow.** `sod-gate.github.yml` lives outside `.github/workflows/` deliberately — it is a reference document for adopters, not a live workflow on this repo. Running it here would block every kit PR (the kit's CI actor is the same identity as the PR author).
- **Replace `gh pr merge --admin`.** The `--admin` bypass remains a human-only, audit-trailed escape hatch for the solo/lite track. The guard/`pre-push` hook never sees it (a server-side API call, not a local git operation). See [`runtime-guards.md`](runtime-guards.md) "Honesty boundary" and [`review-lane.md`](review-lane.md) "Solo + agent-authored PRs".
- **Attribute every commit to a forge identity.** The gate compares forge logins; a commit whose author email is not linked to a forge account has no login, so the reference workflow maps it to a placeholder rather than letting it vanish silently. The kit still cannot tie that unattributed commit to whoever later approves the PR — so **require linked emails (or signed commits)** for the commit-author check to be complete, or harden the reference to fail closed when any commit is unattributed. And note the bound of the model itself: SoD stops an agent (or author) from ratifying *its own* work; it does **not** stop two colluding distinct identities — no author≠approver gate can.

The kit's honest position: it proves the neutral floor, documents the per-forge paths, and leaves server-side enforcement to the adopter's branch-protection and forge approval rules.

---

## See also

- [`review-lane.md`](review-lane.md) — the solo/lite compensating-control bundle; the `--admin` convention and its audit trail.
- [`gitlab-adoption.md`](gitlab-adoption.md) — GitLab wiring guide; native MR approval settings for SoD.
- [`runtime-guards.md`](runtime-guards.md) — the guard's honest ceiling and why `gh pr merge --admin` is outside its reach.
- [`sod-gate.github.yml`](sod-gate.github.yml) — the GitHub reference workflow (copy into `.github/workflows/`).
- `scripts/sod-check.sh` — the neutral FLOOR; `--selftest` proves the logic.
- `conformance/author-not-approver-wired.sh` — the conformance lock; runs the self-test and verifies static wiring.
