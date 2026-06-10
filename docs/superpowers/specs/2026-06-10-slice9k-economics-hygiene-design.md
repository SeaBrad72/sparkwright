# Slice 9k — Economics & Hygiene (design)

**Date:** 2026-06-10 · **Arc:** Slice 9, Stage V (R11) · **Version target:** MINOR → **v2.35.0**
**Input:** the A1 economics baseline — an agent operating by-the-book carries **~24K tokens** of standing governance per feature (core 3 docs ~16.5K + global 2 ~4.6K + 1 profile + 2 templates) before reading any feature code. Plus two hygiene debts the review and dogfood surfaced: the README version badge is **10 versions stale** (`v2.24.0` vs `VERSION` 2.34.0), and the DoD/security ownership is fuzzy (a misdirecting §7 DoD pointer; an unlabeled summary↔detail security split).

## Scope (ratified at brainstorm)
Three threads: (1) a `≤1-page` **load-first agent brief** (`AGENTS.md`) that lets an agent read a small index first and expand the full docs only on demand; (2) **canonical-home + pointer** fixes so the DoD/security have one owner each and the layering is explicit (no content collapsed); (3) a **badge-from-VERSION** drift-killer with a `--fix` sync. Two new conformance checks + doc edits + CI wiring. No governing-rule change.

**Trim is explicitly deferred, not dropped:** this slice lands the brief and *measures* the brief-enabled load; the core-doc prose trim is recorded as **9k-b (core-doc trim)** so we cut from a measurement, not by feel, and don't churn the brief twice.

## Components

### 1. `AGENTS.md` — the load-first operating brief (new, ≤ 1 page)
A root-level brief an agent reads **first** (~1.5–2K tokens) instead of front-loading the three core docs. It is an **index, not an authority** — a header states "`CLAUDE.md` wins; this only points." Contents, each with a `→`-pointer to the full section:
- **The loop** — Discover → Plan → Build → Review → Release → Operate (`→ DEVELOPMENT-PROCESS.md`).
- **The gates** — DoR (entry) · DoD (exit) · the 7 required CI gates (`→ CLAUDE.md` / `→ DEVELOPMENT-STANDARDS.md §14`).
- **Security non-negotiables** — the terse list (`→ CLAUDE.md` summary / `→ DEVELOPMENT-STANDARDS.md §2` detail).
- **The agent boundary** — the guard / control-plane protection + "agents propose, humans ratify" (`→ DEVELOPMENT-PROCESS.md §13`).
- **Stack specifics** — `→ profiles/<stack>.md`.
- **The economics instruction (the lever):** "Load a full doc only when your task touches it." This is what turns the standing ~24K into an on-demand pull.

AGENTS.md is also the emerging cross-tool convention (Claude Code / Copilot / Codex read it), so it doubles as the canonical agent entry surface.

### 2. Canonical-home + pointer fixes (doc edits only — no content collapsed)
- **DoD home:** `DEVELOPMENT-PROCESS.md` §7 gate row (line 192) currently says the DoD is "(per `DEVELOPMENT-STANDARDS.md`)". The DoD block actually lives in `CLAUDE.md`. Fix → "(per `CLAUDE.md`)". One home, correctly pointed.
- **Security layering made explicit:** `CLAUDE.md` "Security (non-negotiable)" labeled the **authoritative summary**; `DEVELOPMENT-STANDARDS.md` §2 labeled its **expansion**. A one-line cross-reference each way so the summary↔detail split is intentional and drift-evident, not accidental. **No security rule is added, removed, or reworded** — labels only.

### 3. `conformance/badge-version.sh` (new) — badge drift-killer
- No-arg: read the version token from the README header and assert it equals `VERSION`; **fail (exit 1) on drift**.
- `--fix`: rewrite the README badge from `VERSION` (idempotent).
- `--selftest`: two-tree fixture (a drifted README must fail-detect; a synced one must pass), no `rm`.
- POSIX sh, `dash -n` clean. The README badge is **corrected to v2.34.0** in this slice (the current actual version before 9k's own bump).
- The **release flow calls `--fix`** (documented in the release task) so the badge can never silently drift again.

### 4. `conformance/agents-brief.sh` (new) — keep the brief a brief
Light completeness + economics guard:
- `AGENTS.md` exists;
- it references each canonical doc (`CLAUDE.md`, `DEVELOPMENT-PROCESS.md`, `DEVELOPMENT-STANDARDS.md`);
- it is **≤ a line bound** (a fixed cap, e.g. 80 lines) so the brief cannot quietly grow into a fourth standards doc — this *enforces* the "≤1 page / load-first" economics intent.
- `--selftest`: two-tree fixture (a missing/oversized/unreferenced brief must fail; a good one must pass), no `rm`. `dash -n` clean.

### 5. CI + release
- Both scripts wired into kit CI after the existing `dor-defined` steps (**one control-plane `cp`**): `badge-version.sh` (assert) + its `--selftest`; `agents-brief.sh` + its `--selftest`.
- `VERSION` → 2.35.0; CHANGELOG entry; roadmap 9k → shipped **and** a new **9k-b (core-doc trim)** row recorded.

## Files

| File | Change | Owner |
|------|--------|-------|
| `AGENTS.md` | **New** — ≤1-page load-first brief (index → pointers) | agent |
| `DEVELOPMENT-PROCESS.md` | §7 DoD pointer → `CLAUDE.md` | agent |
| `CLAUDE.md` | Security section labeled "authoritative summary" (+ pointer to STANDARDS §2 expansion) | agent (governing surface → security-owner lens) |
| `DEVELOPMENT-STANDARDS.md` | §2 labeled "expansion of the CLAUDE.md summary" | agent |
| `README.md` | version badge corrected to v2.34.0 (then 2.35.0 at release) | agent |
| `conformance/badge-version.sh` | **New** — assert + `--fix` + `--selftest` | agent |
| `conformance/agents-brief.sh` | **New** — brief completeness/line-bound + `--selftest` | agent |
| `conformance/README.md` | two index rows | agent |
| `.github/workflows/ci.yml` | both checks + selftests | **human `cp`** |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.35.0; 9k → shipped; add 9k-b row | agent |

## Verification
- `sh conformance/badge-version.sh` → PASS (badge == VERSION); `--fix` syncs; `--selftest` detects drift + accepts synced.
- `sh conformance/agents-brief.sh` → PASS (exists + references + within line bound); `--selftest` detects a missing/oversized/unreferenced brief.
- `dash -n` clean on both scripts.
- `sh conformance/check-links.sh` green (AGENTS.md pointers + cross-references resolve).
- `sh conformance/verify.sh` OK; existing checks unaffected.
- `git diff main..HEAD -- CLAUDE.md` shows the security edit is **labels only** — no security rule added/removed/reworded (security-owner lens).
- Anonymization: generic ([[kit-anonymization]]).
- Governance: feature branch → PR → human ratification; the `.github/workflows` step via human `cp`.

## Out of scope / deferred
- **Core-doc prose trim** → recorded as **9k-b (core-doc trim)**: tighten CLAUDE.md / DEVELOPMENT-PROCESS / DEVELOPMENT-STANDARDS prose and push detail to references, measured against the brief-enabled load this slice establishes. Deferred deliberately so we trim from data, not feel, and don't churn the brief twice.
- **Aggressive security merge** — rejected at brainstorm; CLAUDE.md stays self-contained (summary), STANDARDS holds the detail. 9k only labels the layering.
- **A measured re-run of the 24K number** — that's the arc's analysis work (A1 deeper pass / A7), not this build slice; 9k's brief is *designed* to move it and 9k-b will trim against it.

## Known implications
- The kit gains a canonical agent entry surface (`AGENTS.md`) that the broader tool ecosystem already expects, and the per-feature governance load becomes an *on-demand pull* rather than a standing front-load.
- Two hygiene drifts (badge, DoD/security ownership) become machine-guarded or one-owner-clear.
- A future version bump auto-syncs the badge via the release `--fix` step; a future brief edit must stay within the line bound or `agents-brief.sh` fails.
