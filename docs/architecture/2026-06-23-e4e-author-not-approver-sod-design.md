# E4e — author≠approver separation-of-duties gate (FLOOR + NATIVE)

**Date:** 2026-06-23 · **Slice:** E4e (containment epic; the R2-deferred bot-identity ratification gate) · **Status:** design → plan
**Source:** RETEST-2 finding R2 (`docs/operations/review-lane.md` "Solo + agent-authored PRs"; design `docs/superpowers/specs/2026-06-22-r2-agent-boundary-honesty-design.md`) deferred the *gated* fix here. Sizes from E3 §10 containment contract item #4 (prod-credential separation of duties) — `docs/architecture/2026-06-22-e3-agentic-orchestration-design.md`.

## Problem

R2 made the agent boundary **honest** in the docs but left the ratification control as **convention, not a gate**. In the single-maintainer + agent-authored-PR configuration the kit otherwise prescribes:

- **A1 — the guard sees only local git.** The runtime guard / `pre-push` hook blocks a local push to `main`, not a server-side `gh pr merge --admin`. An agent holding the owner's `gh` CLI can admin-merge — a server action the guard never sees.
- **A2 — code-owner approval is structurally unsatisfiable solo.** If the sole owner is also the sole code owner, `require_code_owner_reviews` makes approval impossible (the forge forbids self-approval → permanent `BLOCKED`).

The net: the "humans ratify" control silently degrades to "the human admin-merges." The deferred fix is to make **author ≠ approver** a *real* gate — satisfiable solo, and not bypassable by the building agent — by giving the agent a **distinct authoring identity** so the human becomes a legitimate distinct approver.

## Goal

Make author≠approver a **proven** control to the strongest degree achievable without a live forge org, **without over-claiming a server-side gate**, and **without binding the kit to GitHub** (the kit is platform-agnostic by design — LLM/harness/forge neutrality).

## Design — FLOOR + NATIVE

The **principle is universal; the mechanism is platform-specific.** Separation of duties (*author ≠ approver ≠ commit-authors*) is a stack- and forge-neutral SDLC truth. Only the *binding* is forge-specific. The slice splits accordingly — the kit **proves** the neutral floor and **provides** per-forge bindings.

### Components

1. **Neutral logic core — `scripts/sod-check.sh` (the FLOOR; control-plane).**
   Pure identity-set comparison, **zero forge-specific code**. Inputs are normalized identities supplied via environment:
   - `SOD_AUTHOR` — the PR/MR author identity.
   - `SOD_APPROVERS` — the set of approving-reviewer identities (newline/space-separated).
   - `SOD_COMMIT_AUTHORS` — the set of commit-author identities on the branch (newline/space-separated).

   **Decision:** PASS (exit 0) iff at least one approver identity is distinct from `SOD_AUTHOR` **and** distinct from every identity in `SOD_COMMIT_AUTHORS`; else FAIL (exit 1). When required inputs are absent/empty: exit 2 (UNVERIFIED) normally, **escalated to exit 1 (FAIL) under `CI`/`--require`** — anti-vacuity (the E4b RED-vacuity lesson: a gate must fail closed when it cannot evaluate). Identities are **normalized** (trim + case-fold) before comparison to prevent a `Alice`-vs-`alice` bypass.

   Ships `--selftest` with fixtures (below). This script is what the kit *proves*, and being forge-neutral, the proof is forge-neutral.

2. **Neutral contract doc — `docs/operations/separation-of-duties.md` (new; agent-editable).**
   - The principle and the **agentic rationale**: an agent must not ratify its own work; the building identity and the ratifying identity must differ, and the ratifying identity must be one the **building agent cannot assume**.
   - **Tiers (progressive disclosure):** solo/lite keeps the honest admin-merge convention (cross-ref `review-lane.md`); team/enterprise use a distinct ratifying identity.
   - The **FLOOR**: the contract + the neutral logic core (`sod-check.sh`).
   - The **honest ceiling**: server-side enforcement is the adopter's branch-protection / forge approval rules; kit CI cannot run a live distinct-approver scenario (the kit is itself the solo case); `--admin` remains a human-only, audit-trailed escape hatch (R2's boundary, unchanged).

3. **NATIVE bindings (documented; not the proven center):**
   - **GitHub** — a real reference workflow `docs/operations/sod-gate.github.yml` (exports to adopters, but is **not** in `.github/workflows/`, so it never auto-runs on the kit and cannot block the kit's own solo PRs). It populates `SOD_*` from the PR event + reviews API and invokes `sod-check.sh`. Plus the **bot-identity** reference: a GitHub App token is the recommended GitHub mechanism (distinct PR author, scoped perms, no human-seat cost); a machine user is the simpler alternative. The bot must **not** be a code owner, so the human code owner's review is the distinct ratification.
   - **GitLab** — point to its **native** MR approval rules: *Prevent approval by author* and *Prevent approvals by users who added commits*. SoD is native there — no gate needed. Documented in `docs/operations/gitlab-adoption.md`.
   - **Other forges** — the contract + "use your forge's equivalent approval rule."

4. **Conformance lock — `conformance/author-not-approver-wired.sh` (new; control-plane). New claim `author-not-approver`, claims 28 → 29.**
   - Runs `sh scripts/sod-check.sh --selftest` — the **behaviour** proof of the floor.
   - Static-locks: the contract doc exists; the GitHub reference workflow exists and invokes `sod-check.sh`; the GitLab native-rule pointer exists in `gitlab-adoption.md`.
   - **Parse-validates** the reference workflow with `actionlint` when available (the R1 lesson: a generated/shipped workflow gate must include a PARSE, not just a line-grep).
   - **Mode-blind** (reads no process mode — the S1 invariant; `mode-enforcement-blind.sh` enforces it).
   - Registered in the claims registry + `REQUIRED_IDS` + `ci-selftest-coverage` (the S3 lesson: a new script shipping `--selftest` must be CI-wired or `ci-selftest-coverage` fails).
   - **No export-carve needed**: every path the verifier reads (`scripts/sod-check.sh`, the doc, `gitlab-adoption.md`, the reference workflow, the conformance script itself) ships to adopters — unlike `golden-path-wired` which reads an export-ignored `.github/workflows/` path (the E2 carve lesson does not apply here).

### Selftest fixtures (the proof of the logic)

| Case | `SOD_AUTHOR` | `SOD_APPROVERS` | `SOD_COMMIT_AUTHORS` | Expect |
|------|--------------|-----------------|----------------------|--------|
| distinct approver | `agent-bot` | `alice` | `agent-bot` | PASS |
| author-only approves | `alice` | `alice` | `alice` | FAIL |
| approver also committed | `agent-bot` | `bob` | `agent-bot bob` | FAIL |
| no approvals | `agent-bot` | (empty) | `agent-bot` | FAIL under CI/--require; exit 2 otherwise |
| distinct + author also approved | `agent-bot` | `agent-bot alice` | `agent-bot` | PASS (≥1 distinct suffices) |
| casing variant | `Agent-Bot` | `agent-bot` | `Agent-Bot` | FAIL (normalized: same identity) |

## Hardening / abuse-case pass

- **Self-approval via a second agent-held token** — SoD holds only if the ratifying identity is outside the building agent's control; the logic core cannot detect "is a human," so the doc states this as an explicit precondition.
- **Approver who also committed** — a code author cannot be the sole ratifier (fixture: approver ∈ commit-authors → FAIL).
- **Empty/missing approver set** — fails closed under CI (anti-vacuity).
- **Identity casing/whitespace** — normalized before comparison.
- **Mode weakening** — the conformance check reads no process mode (mode-blind).
- **`--admin` bypass** — acknowledged honest ceiling; the detective audit that would close it is a **flagged follow-up**, not this slice.

## Non-goals (scope-creep guard)

- No detective audit of `--admin` merges (flagged follow-up; candidate to fold into E5 observability).
- No live-org proof (impossible in kit CI; the selftest is the honest proof).
- No change to `branch-protection.sh`'s advisory `require_code_owner_reviews` stance (honest as-is; it cannot know whether a bot-identity is configured).
- No bot-identity *provisioning/automation* (platform-owned — the pattern is documented, not scripted).
- No wiring the gate into the kit's own required checks (the kit is solo and could not satisfy it).
- No touching all 10 `BRANCH-PROTECTION.md` templates — cross-link centrally from `review-lane.md` + the new doc.

## Verification

- `sh scripts/sod-check.sh --selftest` green; all fixtures behave as tabled (TDD: write a fixture, confirm it FAILS on a regressed logic core first).
- `conformance/author-not-approver-wired.sh --selftest` green; the lock FAILS when the reference workflow / doc / wiring is removed (red-green on a regressed state).
- `actionlint` parse-clean on `docs/operations/sod-gate.github.yml`.
- `verify.sh --require` + `sparkwright doctor` green; claims = 29; `mode-enforcement-blind.sh` green (new check reads no mode); `check-links.sh` green (new cross-links resolve).
- Independent `reviewer` (functional) + **`security-reviewer` of the scratch** (control-plane/security gate — non-negotiable): is the logic bypassable? does it fail closed? is anything over-claimed as a server-side gate?

## Mechanic

Control-plane (`scripts/sod-check.sh` + `conformance/author-not-approver-wired.sh` + claims-registry/REQUIRED_IDS/ci-selftest-coverage wiring) → build in `/tmp` scratch, dual-review (reviewer + security-reviewer of scratch), fold nits, human-run `apply.py` (AMBER). Agent-editable on-branch: the new doc, `gitlab-adoption.md`, the reference workflow, the `review-lane.md` cross-link. Then I author VERSION/CHANGELOG/README-badge/ROADMAP✅ on-branch → commit → PR (AMBER) → Bradley admin-merge **then** tag (merge-first), verifying HEAD+tag+PR=MERGED before claiming done. v3.46.0 → **3.47.0**.
