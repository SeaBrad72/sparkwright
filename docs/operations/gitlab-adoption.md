# GitLab Adoption Guide

How to bring this kit's governance controls to a GitLab-hosted repo. The CI contract is already
fully portable — the remaining controls (branch protection, control-plane ratification, DORA) are
adopter-owned on GitLab; this guide consolidates the wiring.

> **Honest ceiling up front.** The kit is GitHub-first for *automated* governance. On GitLab,
> the CI gates run identically, but the branch-protection and control-plane-ratification controls
> are adopter-wired, not kit-enforced — the kit returns **UNVERIFIED** rather than a faked pass,
> consistent with the three-state conformance model (`conformance/verify.sh`).

---

## What GitLab already has

**All 8 required CI gates** are present and verified on GitLab with zero adoption work:
- `profiles/typescript-node/ci.gitlab-ci.yml` expresses the gate-id contract as GitLab **job
  keys** (`gate-lint:`, `gate-type-check:`, …). Drop it in as `.gitlab-ci.yml` at the repo root
  (`incept.sh --ci gitlab` does this).
- `conformance/ci-gates.sh profiles/typescript-node/ci.gitlab-ci.yml` verifies all 8 gate-ids
  are declared — same check, same contract, same green output.

**The platform-neutral runtime guard** ships without changes:
- `PreToolUse` hook (`docs/operations/runtime-guards.md`) — blocks destructive commands and
  secret-reads inside Claude Code, platform-independent.
- `hooks/pre-push` — blocks force-push and push-to-main locally for every git client, including
  GitLab remotes.
- `scripts/kit-guard` — the CLI that wires any non-Claude runtime into the same deny-matrix.

No CI gap for the build pipeline. No guard gap.

---

## Branch protection

The **`conformance/branch-protection.sh`** check is GitHub-only (`gh api`). On GitLab it returns
**UNVERIFIED** (exit 2) — by design, never a false pass:

```
UNVERIFIED: no GitHub repo context — run in CI or authenticate gh. (NOT a pass.)
```

Wire the GitLab equivalent manually in **Settings → Repository → Protected branches**:

| GitHub setting the check verifies | GitLab equivalent |
|-----------------------------------|--------------------|
| Required pull request reviews | Require merge request (no direct push to `main`) |
| Required status checks | "Pipelines must succeed" |
| CODEOWNER review advisory | Approval rule ≥ 1 approver (see control-plane section) |

Minimum: enable **"Require merge request before merging"** and **"Pipelines must succeed"** for
the `main` branch. This satisfies the same PR-review + CI-pass intent that `branch-protection.sh`
verifies on GitHub.

The kit reports UNVERIFIED off-GitHub rather than emitting a false green — the same honesty
discipline as the three-state conformance model.

---

## Control-plane ratification

**This is the keystone gap.** The GitHub profile (`profiles/typescript-node/ci.yml`) carries a
`gate-agent-boundary` CI job that blocks merge on any PR touching control-plane paths until a
non-author has approved. GitLab has no equivalent job shipped in the kit — the `ci.gitlab-ci.yml`
comment is honest about this.

Wire it manually with two GitLab controls:

### 1 — Merge request approval rule

In **Settings → Merge requests → Approval rules**, create a rule:

- **Name:** `control-plane-ratification`
- **Required approvals:** 1
- **Eligible approvers:** maintainers / a named security-owner group
- **Target branch:** `main`

This is the approver equivalent of the `gate-agent-boundary` merge-gate: no control-plane MR
merges without a non-author approval.

### 2 — CODEOWNERS-scoped approval (Code Owners)

GitLab supports a `CODEOWNERS` file at the repo root (same syntax as GitHub). Scope an approval
requirement to the control-plane paths:

```
# illustrative subset — see guard-core.sh::is_control_plane_path for the full canonical set
# CODEOWNERS — control-plane ratification (mirrors guard-core.sh::is_control_plane_path)
# Any MR touching these paths requires a maintainer approval before merge.

/.claude/hooks/        @your-org/maintainers  # whole dir — intentionally broader than the two guard files; safe to protect more
/.claude/settings.json @your-org/maintainers
/.claude/mcp-policy.json @your-org/maintainers
/conformance/          @your-org/maintainers
/adapters/             @your-org/maintainers
/.gitlab-ci.yml        @your-org/maintainers
/CODEOWNERS            @your-org/maintainers
/DEVELOPMENT-STANDARDS.md @your-org/maintainers
/DEVELOPMENT-PROCESS.md   @your-org/maintainers
/CLAUDE.md             @your-org/maintainers
/scripts/kit-guard     @your-org/maintainers
/hooks/pre-push        @your-org/maintainers
```

Enable **"Require Code Owner approval"** under the protected branch rule to make this binding.

The full canonical set of control-plane paths is defined in
`/.claude/hooks/guard-core.sh::is_control_plane_path` — use that function as the source of truth
when updating the CODEOWNERS file.

**Honest ceiling:** this is adopter-wired, not kit-enforced on GitLab. There is no live-verifiable
gate the kit can ship without a GitLab instance to test against. `conformance/branch-protection.sh`
returns UNVERIFIED on GitLab rather than pretending it checked.

---

## Separation of duties (author ≠ approver)

GitLab has this natively — no additional CI gate or script is required. Enable both settings in
**Settings → Merge requests → Approval settings**:

- **Prevent approval by author** — the MR author cannot approve their own MR.
- **Prevent approvals by users who added commits** — any user who pushed a commit to the branch
  is excluded from approving it.

Together these are GitLab's native realization of the SoD FLOOR (`scripts/sod-check.sh`): the
same author ≠ approver ≠ commit-authors contract, enforced server-side by the platform rather
than via a CI script. See [`separation-of-duties.md`](separation-of-duties.md) for the neutral
contract, the selftest, and the GitHub binding.

---

## DORA

`scripts/dora.sh` derives the DORA subset from **GitHub APIs** (`gh`). On GitLab it prints
`unavailable` per metric — it never fabricates a number:

```
  - Release cadence: unavailable (needs gh)
  - PR lead time: unavailable (needs gh)
  - Review latency: unavailable (needs gh)
```

Re-derive from GitLab's own analytics:
- **Deployment frequency / lead time for changes:** GitLab DORA metrics API
  (`GET /groups/:id/dora/metrics?metric=deployment_frequency&…`) — available on GitLab Premium+.
- **Release cadence proxy:** GitLab Releases API (`GET /projects/:id/releases`).
- **MR lead time / review latency:** GitLab MR list API (`GET /projects/:id/merge_requests?…`)
  with `created_at` / `merged_at` / `first_comment_at` fields.

These are adopter-built scripts; the kit's measurement contract (what the metrics mean and why)
is in `docs/operations/dora-metrics.md`.

---

## Honest ceiling

The kit is GitHub-first for *automated* governance. On GitLab:

- **CI gates** — fully present and verified by `conformance/ci-gates.sh`. No gap.
- **Runtime guard** — fully present (`PreToolUse`, `pre-push`, `kit-guard`). No gap.
- **Branch protection** — adopter-owned. The kit returns **UNVERIFIED**, never a faked pass.
- **Control-plane ratification** — adopter-owned (MR approval rule + CODEOWNERS). No kit-enforced
  gate; the `gate-agent-boundary` job has no GitLab equivalent in this kit.
- **DORA** — adopter-built from GitLab analytics. `scripts/dora.sh` prints `unavailable`.

This is the same three-state honesty discipline as `conformance/verify.sh`: a control that cannot
be verified is reported as UNVERIFIED, not silently passed. Porting the GitHub-bound scripts to
the GitLab API is deliberately out of scope (adopter-owned) rather than faked.

## See also

- `docs/operations/ci-platforms.md` — the platform-neutral gate-id contract and honest-coupling
  table for GitLab / ADO.
- `profiles/typescript-node/ci.gitlab-ci.yml` — the reference GitLab pipeline.
- `docs/operations/runtime-guards.md` — the platform-neutral guard (four surfaces).
- `docs/operations/review-lane.md` — the `builder ≠ reviewer` + control-plane ratification lane.
- `docs/operations/dora-metrics.md` — what the DORA metrics mean and how to record them.
- `conformance/branch-protection.sh` — the three-state contract (UNVERIFIED off-GitHub).
- `conformance/agent-boundary.sh` — the control-plane path set (mirrors `guard-core.sh`).
