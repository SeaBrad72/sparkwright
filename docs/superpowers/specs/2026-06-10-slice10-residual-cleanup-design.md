# Slice 10 — A7 Residual Cleanup (design)

**Date:** 2026-06-10 · **Arc:** post-Slice-9 follow-up (clears the A7 residual backlog) · **Version target:** MINOR → **v2.39.0**
**Input:** the A7 re-review ([`2026-06-10-A7-rereview-arc-closure.md`](../reviews/2026-06-10-A7-rereview-arc-closure.md)) closed the Slice 9 arc but surfaced a tidy backlog of small residuals — two beginner traps, one Jira honest-edge, two hygiene fixes. This slice clears them. The HIGH-severity W2/W3 residuals (interpreter-exfil, non-Bash MCP tools) are the honestly-disclosed **platform-owned boundary** and are explicitly **out of scope**.

## Components

### 1. `gh` in preflight (#1 — beginner silent-wall, Med)
`scripts/preflight.sh` gains a **soft `recommend()`** helper: checks `gh` and `gh auth status`, **warns but does not fail** (a GitLab/ADO adopter doesn't need `gh`). It names where `gh` is first needed — the GitHub branch-protection setup at Inception step 3. The hard `need` set (jq/git) is unchanged. `--selftest` extended to exercise the recommend path.

### 2. Solo-track `enforce_admins` contradiction (#2 — real beginner trap, Med)
The Solo/lite track told the owner to "merge via owner admin-merge — GitHub records the bypass," but the reference set `enforce_admins: true`, which **blocks** admin bypass — a solo dev with no second reviewer is stuck. `branch-protection.sh` asserts only *required reviews + status checks configured* (not `enforce_admins`), so the fix doesn't break conformance:
- `START-HERE.md` Solo/lite track: explicitly instruct setting **`enforce_admins: false`** at solo scale (so the documented admin-merge self-ratification works), and flip back to `true` when a second reviewer joins.
- `profiles/typescript-node/BRANCH-PROTECTION.md`: a one-line **"Solo scale"** note beside `enforce_admins: true`.

### 3. Jira `--deep` Only-Assignee verifier (#3 — honest-edge, Med)
`conformance/tracker-contract.sh` gains a `--deep` opt-in: with creds, it calls `/rest/api/3/workflow/search?expand=transitions.rules` and checks the In-Progress transition actually carries an **assignee-restriction condition** — turning *attested* into *verified* for the one property that distinguishes Jira's structural claim. Three-state: UNVERIFIED without creds. The parse logic is proven in `--selftest` against a **recorded workflow-JSON fixture** (a conformant one with the condition + a gap one without); the live path is **best-effort + honestly documented** (Jira workflow JSON shape varies across Cloud/Server, so the matcher is broad and the header says so). `templates/JIRA-SETUP-TEMPLATE.md` points at `--deep` as the way to verify the condition.

### 4. Brownfield `.gitignore` one-liner (#4 — Low)
`docs/adoption/brownfield.md` §2: append to the `settings.local.json` line the instruction to **add `.claude/settings.local.json` to the adopter's own `.gitignore`** (the kit's gitignore has it; a brownfield repo's won't), closing the personal-override leak risk.

### 5. Lift the amend over-block (#5 — control-plane, Low)
`.claude/hooks/guard-core.sh`: **remove** the `git commit --amend` deny (lines 92–94). Local amend is reversible (recoverable via reflog) and **cannot be published destructively** because force-push and non-fast-forward push are independently denied (guard-core.sh force-push rule + the pre-push non-ff rule), and `git reset --hard` stays denied. This is a deliberate loosening of an over-block that "trains circumvention" (SWOT W8), aligned with the guard's "speed bump for honest mistakes" philosophy. Regression-lock the new behavior: add `assert_allow 'git commit --amend'` to `conformance/agent-autonomy.sh`, keeping every force-push `assert_deny`. (No amend assertion exists in the `kit-guard`/`pre-push` selftest batteries, so nothing else changes.) **One control-plane `cp`** (guard-core.sh, applied with `KIT_GUARD_SELFEDIT=1`).

### 6. Release
`VERSION` → 2.39.0; CHANGELOG; roadmap note that the A7-residual backlog is cleared.

## Files

| File | Change | Owner |
|------|--------|-------|
| `scripts/preflight.sh` | soft `recommend()` for `gh` + auth; `--selftest` | agent |
| `START-HERE.md` | Solo track sets `enforce_admins: false` (flip to true with a 2nd reviewer) | agent |
| `profiles/typescript-node/BRANCH-PROTECTION.md` | "Solo scale" note beside `enforce_admins` | agent |
| `conformance/tracker-contract.sh` | `--deep` Only-Assignee introspection + fixture `--selftest` | agent |
| `templates/JIRA-SETUP-TEMPLATE.md` | point at `--deep` to verify the condition | agent |
| `docs/adoption/brownfield.md` | add `.gitignore` instruction | agent |
| `.claude/hooks/guard-core.sh` | **remove** the amend deny | **human `cp`** (security-owner lens) |
| `conformance/agent-autonomy.sh` | `assert_allow 'git commit --amend'`; keep force-push denies | agent |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.39.0; A7-residuals cleared | agent |

## Verification
- `sh scripts/preflight.sh --selftest` green; the live preflight warns (not fails) when `gh` is absent.
- `sh conformance/branch-protection.sh --selftest` still green (the solo `enforce_admins:false` change is doc-only and conformance never asserted `enforce_admins`).
- `sh conformance/tracker-contract.sh --selftest` green incl. the new `--deep` fixture (conformant passes, gap fails); cred-free `--deep` → UNVERIFIED exit 2.
- `sh conformance/agent-autonomy.sh` green with the new amend allow-case **and** every force-push deny still passing; `sh scripts/kit-guard --selftest` and `sh hooks/pre-push --selftest` still green; `sh conformance/guard-core-sourced.sh` green (the core is still single-source).
- `dash -n` clean on the edited scripts; `sh conformance/check-links.sh` + `sh conformance/verify.sh` green.
- Security-owner lens on the guard diff: confirm ONLY the amend deny is removed; force-push / non-ff / reset --hard / destructive-tool denies are intact (no coverage reduction).
- Anonymization: generic ([[kit-anonymization]]).

## Out of scope / deferred
- **W2 interpreter-exfil + W3 non-Bash MCP-tool gating** — the HIGH platform-owned boundary; a major effort, not a residual cleanup. Stays disclosed in `platform-safety-boundary.md`.
- Porting the solo `enforce_admins` note to all 10 profiles' `BRANCH-PROTECTION.md` — the canonical reference carries it; the others are stack variants (a future sweep if desired).
- A `--deep` verifier for the convention-tier trackers — they have no server-side condition to introspect (by definition).

## Known implications
- The beginner journey loses its two hard traps (the `gh` wall and the admin-merge contradiction); the Jira persona's core property is now *verifiable*, not just attested; brownfield adopters won't leak a personal override; and the guard stops over-blocking a reversible op (less circumvention pressure).
- The guard change is a **net loosening of one over-block**, leaving the destructive-action coverage intact — verified by the full agent-autonomy battery staying green.
