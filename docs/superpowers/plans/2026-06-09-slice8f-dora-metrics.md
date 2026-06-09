# Slice 8f — DORA metrics collection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Instrument the DORA four + agentic signals — ship a `dora-metrics.md` reference and a real `scripts/dora.sh` that reports the GitHub-derivable subset (graceful degradation → exit 0), CI-smoked, no baseline gate. Completes Slice 8.

**Architecture:** A reference doc + one POSIX-sh collector in `scripts/`. The collector uses `gh` (and gh's built-in `--jq` for date math — no separate `jq`). It is a report, not a gate: every `gh` call is guarded so a failure prints "unavailable" and the script still exits 0. A `--selftest` deterministically asserts the no-`gh` degradation path (CI runs it, no network). No new conformance gate — value-gating is documented as a §9 maturity step.

**Tech Stack:** POSIX `sh` (sh + dash), `gh` CLI, Markdown, GitHub Actions YAML, `git`.

**Spec:** `docs/superpowers/specs/2026-06-09-slice8f-dora-metrics-design.md`

---

## File structure

| File | Responsibility | Change |
|------|----------------|--------|
| `scripts/dora.sh` | GitHub-derivable DORA collector + `--selftest` | **Create** |
| `docs/operations/dora-metrics.md` | Per-metric derivation + maturity-gating + dashboard | **Create** |
| `DEVELOPMENT-PROCESS.md` §14 + §9 | Reference the doc + collector; cross-ref maturity-gating | Modify (2 edits) |
| `conformance/README.md` | DORA = measurement-enablement (no gate) note | Modify (1 note) |
| `.github/workflows/ci.yml` | `dora.sh --selftest` smoke step | Modify (1 step) |
| `VERSION` / `CHANGELOG.md` / `docs/ROADMAP-KIT.md` | Release meta + **Slice 8 complete** | Modify |

---

### Task 1: Create `scripts/dora.sh`

**Files:**
- Create: `scripts/dora.sh`

- [ ] **Step 1: Write the script**

Create `scripts/dora.sh` with EXACTLY this content:

```sh
#!/bin/sh
# dora.sh — report the GitHub-derivable DORA subset for the current repo.
#
# A REPORT, not a gate. Computes what is universally derivable from any GitHub repo
# (release cadence, PR lead time, review latency) via `gh` (+ gh's built-in --jq for
# date math — no separate jq needed). Metrics that need deployment + incident data
# (true deployment frequency, change-failure rate, MTTR, retro-action closure) are
# ADOPTER-WIRED and printed with how-to pointers. DEGRADES GRACEFULLY — any gh failure
# (no gh / no auth / missing scope / no network) prints "unavailable" for that metric
# and continues — and ALWAYS exits 0. A reporting tool must never fail a pipeline for
# lack of data. See docs/operations/dora-metrics.md.
#
# Usage:
#   sh scripts/dora.sh [--window DAYS]   (default 30)
#   sh scripts/dora.sh --selftest        (deterministic degradation self-test; no network)
set -eu

WINDOW="${WINDOW:-30}"
case "$WINDOW" in ""|*[!0-9]*) echo "WINDOW must be a positive integer" >&2; exit 2 ;; esac

have_gh() {
  [ "${DORA_FORCE_NO_GH:-0}" = "1" ] && return 1
  command -v gh >/dev/null 2>&1
}

report() {
  echo "DORA metrics (GitHub-derivable subset) — window: ${WINDOW}d"
  echo "---------------------------------------------------------------"

  if ! have_gh; then
    echo "gh not available (install GitHub CLI + run 'gh auth login') — GitHub-derivable metrics need it:"
    echo "  - Release cadence: unavailable (needs gh)"
    echo "  - PR lead time: unavailable (needs gh)"
    echo "  - Review latency: unavailable (needs gh)"
  else
    # Release cadence (deployment-frequency proxy): releases published within the window.
    if rc="$(gh api "repos/{owner}/{repo}/releases?per_page=100" \
              --jq "[.[] | select(((.published_at // .created_at)|fromdateiso8601) > (now - ${WINDOW}*86400))] | length" 2>/dev/null)"; then
      echo "  - Release cadence: ${rc} release(s) in last ${WINDOW}d (deployment-frequency proxy; true deploy-freq adopter-wired)"
    else
      echo "  - Release cadence: unavailable (needs gh auth + contents:read)"
    fi

    # PR lead time (lead-time proxy): avg created->merged hours for PRs merged in the window.
    if lt="$(gh pr list --state merged --limit 200 --json createdAt,mergedAt \
              --jq "[.[] | select(.mergedAt != null) | select((.mergedAt|fromdateiso8601) > (now - ${WINDOW}*86400)) | ((.mergedAt|fromdateiso8601) - (.createdAt|fromdateiso8601))] | if length > 0 then (add/length/3600 | floor) else -1 end" 2>/dev/null)"; then
      if [ "$lt" = "-1" ] || [ -z "$lt" ]; then
        echo "  - PR lead time: no PRs merged in last ${WINDOW}d"
      else
        echo "  - PR lead time: ~${lt} h avg created->merged (lead-time proxy; deploy leg adopter-wired)"
      fi
    else
      echo "  - PR lead time: unavailable (needs gh auth + pull-requests:read)"
    fi

    # Review latency (agentic): avg created->first-review hours (->merged if no review).
    if rl="$(gh pr list --state merged --limit 200 --json createdAt,mergedAt,reviews \
              --jq "[.[] | select(.mergedAt != null) | select((.mergedAt|fromdateiso8601) > (now - ${WINDOW}*86400)) | ((if (.reviews|length) > 0 then (.reviews[0].submittedAt|fromdateiso8601) else (.mergedAt|fromdateiso8601) end) - (.createdAt|fromdateiso8601))] | if length > 0 then (add/length/3600 | floor) else -1 end" 2>/dev/null)"; then
      if [ "$rl" = "-1" ] || [ -z "$rl" ]; then
        echo "  - Review latency: no PRs merged in last ${WINDOW}d"
      else
        echo "  - Review latency: ~${rl} h avg created->first-review (human-bottleneck signal, §14)"
      fi
    else
      echo "  - Review latency: unavailable (needs gh auth + pull-requests:read)"
    fi
  fi

  echo ""
  echo "Adopter-wired (need deployment + incident data — see docs/operations/dora-metrics.md):"
  echo "  - Deployment frequency (true): record GitHub Deployments from your deploy workflow"
  echo "  - Change-failure rate: deployments causing an incident/revert / total deployments"
  echo "  - MTTR: incident open->resolved (the postmortem / incident records, standards §15)"
  echo "  - Retro-action closure (agentic): share of retro action items closed (backlog labels, process §6)"
}

selftest() {
  out="$(DORA_FORCE_NO_GH=1 sh "$0" 2>/dev/null)" || { echo "dora --selftest: FAIL (non-zero exit on no-gh path)" >&2; return 1; }
  printf '%s\n' "$out" | grep -q "gh not available" || { echo "dora --selftest: FAIL (missing degradation message)" >&2; return 1; }
  printf '%s\n' "$out" | grep -q "Adopter-wired" || { echo "dora --selftest: FAIL (missing adopter-wired block)" >&2; return 1; }
  echo "dora --selftest: OK (no-gh path degrades cleanly and exits 0)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --window)
    WINDOW="${2:-}"
    case "$WINDOW" in ""|*[!0-9]*) echo "usage: --window needs a positive integer" >&2; exit 2 ;; esac
    report; exit 0 ;;
  "") report; exit 0 ;;
  *) echo "usage: sh scripts/dora.sh [--window DAYS] | --selftest" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Run the self-test (the CI smoke; deterministic, no network)**

Run: `sh scripts/dora.sh --selftest; echo "exit=$?"`
Expected: `dora --selftest: OK (no-gh path degrades cleanly and exits 0)`, `exit=0`.

- [ ] **Step 3: Run the no-gh path directly (prove graceful degradation + exit 0)**

Run: `DORA_FORCE_NO_GH=1 sh scripts/dora.sh; echo "exit=$?"`
Expected: prints "gh not available …", the three "unavailable" lines, the "Adopter-wired" block; `exit=0`.

- [ ] **Step 4: Run the real path (in this repo, gh present + authenticated)**

Run: `sh scripts/dora.sh; echo "exit=$?"`
Expected: `exit=0`. With `gh` authenticated it prints real release-cadence / PR-lead-time / review-latency numbers for this repo (plus the adopter-wired block); if a metric's scope is missing it prints that metric's "unavailable" line. Either way **exit 0**. (If `gh` is not installed locally, this behaves like Step 3 — that is acceptable.)

- [ ] **Step 5: Window arg + bad-arg behaviour**

Run:
```bash
sh scripts/dora.sh --window 7 >/dev/null; echo "window-ok=$?"
sh scripts/dora.sh --window abc >/dev/null 2>&1; echo "bad-window=$?"
sh scripts/dora.sh --bogus >/dev/null 2>&1; echo "bad-arg=$?"
```
Expected: `window-ok=0`; `bad-window=2`; `bad-arg=2`.

- [ ] **Step 6: Syntax lint (sh + dash)**

Run: `sh -n scripts/dora.sh && echo "sh OK"` then `command -v dash >/dev/null && dash -n scripts/dora.sh && echo "dash OK" || echo "dash not installed — skipped"`
Expected: `sh OK` (and `dash OK` or skip).

- [ ] **Step 7: Commit**

```bash
chmod +x scripts/dora.sh
git add scripts/dora.sh
git commit -m "feat(scripts): add dora.sh — GitHub-derivable DORA collector

Reports release cadence, PR lead time, review latency via gh (gh --jq
for date math). A report, not a gate: every gh call is guarded, degrades
to 'unavailable' and exits 0. Deploy-freq/change-fail/MTTR/retro-closure
printed as adopter-wired. --selftest asserts the no-gh degradation path.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- Create ONLY `scripts/dora.sh`. Do NOT modify other files. Do NOT run `inception-done.sh`. Preserve the `${WINDOW}` interpolation in the jq strings exactly (WINDOW is validated digits-only — injection-safe). No `rm`/destructive text. Use the Write tool.

## Report Format
Report: Status (DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT), exact output of Steps 2, 3, 5, 6, the commit SHA, any concerns (note whether `gh` is installed locally and what Step 4 printed).

---

### Task 2: Create `docs/operations/dora-metrics.md`

**Files:**
- Create: `docs/operations/dora-metrics.md`

- [ ] **Step 1: Create the file with EXACTLY this content**

```markdown
# DORA Metrics — Collection Reference

How to **collect** the DORA four + the kit's two agentic-specific signals that `DEVELOPMENT-PROCESS.md` §14 defines. Measurement is the precondition for the soft→hard-gating maturity the kit describes (§9). Stack-neutral; tooling is a project/Org choice. Aligns with the **DORA** program (Accelerate / State of DevOps).

> **DORA is a feedback instrument, not a gate.** Collect and surface these in metrics and retros. **Value-gating** (freeze releases when change-failure / MTTR breach a threshold) is a **maturity step** (§9 error budgets, soft → hard), *opt-in at scale* — never a baseline imposed on an early-stage project.

## Per metric — GitHub data source & derivation

| Metric | DORA / agentic | Data source | Derivation |
|--------|----------------|-------------|------------|
| **Deployment frequency** | DORA | GitHub **Deployments API** (true) / **Releases** (proxy) | count of deployments (or releases) per window |
| **Lead time for changes** | DORA | PR/commit **created → merged → deployed** timestamps | median/avg of (deployed − first-commit); PR created→merged is the universal proxy |
| **Change-failure rate** | DORA | deployments + an **incident signal** (an `incident`/`postmortem` label, or the §15 record) | deployments causing an incident/revert ÷ total deployments |
| **MTTR** | DORA | incident **open → resolved** (issues with an `incident` label, or postmortem records) | avg(resolved − opened) |
| **Review latency** | agentic | PR **created → first review** | avg(first-review − created) — the human bottleneck (§14) |
| **Retro-action closure** | agentic | backlog items labelled `retro`/`adjust` (§6) | closed ÷ total retro action items |

## What `scripts/dora.sh` collects (the GitHub-derivable subset)
`scripts/dora.sh` reports, for the current repo, what is derivable from any GitHub repo with `gh`:
- **Release cadence** (deployment-frequency proxy), **PR lead time** (lead-time proxy), **Review latency**.
It **degrades gracefully** (prints "unavailable" and exits 0 if `gh`/auth/scope is missing — a report never fails a pipeline). The remaining metrics — **true deployment frequency, change-failure rate, MTTR, retro-action closure** — are **adopter-wired**: they need deployment events + an incident/retro signal your platform records.

```
sh scripts/dora.sh             # last 30 days
sh scripts/dora.sh --window 7  # last 7 days
```

## Wiring the adopter-owned metrics
- **Deployment events** — have your deploy workflow record a GitHub **Deployment** (or a deploy log/warehouse row) per environment promotion (§9 promotion).
- **Incident signal** — label incident issues `incident` and link the postmortem (standards §15 / 8a); change-failure rate and MTTR derive from these + deployment events.
- **Retro-action closure** — label retro action items `retro` on the backlog (§6); closure rate is closed ÷ total.

## The maturity-gating path (the home for DORA enforcement)
Per §9 (error budgets, soft → hard):
- **Default — surface, don't gate.** Report the metrics in dashboards and retros; let trends inform improvement.
- **Maturity step — gate.** At production scale, promote to gating: e.g. **freeze non-critical releases when change-failure rate or MTTR breaches the budget** until reliability recovers. Mirrors the §9 error-budget promotion and the Stage 1–4 scale progression. This is opt-in at scale — not a baseline check.

## Dashboard pattern
Surface the metrics on a cadence/format the org sets (a configuration point, not a fixed ritual; ties to §12 stakeholder visibility):
- **DORA "Four Keys"** (the reference implementation), **Grafana** over a metrics warehouse, or a **board digest** (§12).
- Feed `scripts/dora.sh` output into the digest for the GitHub-derivable subset; wire deployment/incident sources for the rest.

## Tooling (Org-owned)
Four Keys, Grafana, a metrics warehouse, or `scripts/dora.sh` for the GitHub-derivable subset. The kit standardizes the **metric definitions and the derivation**, not the dashboard.
```

- [ ] **Step 2: Link check**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 3: Commit**

```bash
git add docs/operations/dora-metrics.md
git commit -m "docs(operations): add DORA metrics collection reference

Per-metric GitHub derivation (incl. adopter-wired change-fail/MTTR/
retro-closure), what scripts/dora.sh collects, the §9 maturity-gating
path, and a dashboard pattern. DORA is a feedback instrument, not a gate.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- Create ONLY `docs/operations/dora-metrics.md`. Preserve special chars (→, §, ÷). The fenced ```` ``` ```` code block inside the doc must be closed correctly. Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 2, commit SHA, any concerns.

---

### Task 3: Wire §14 + §9 + conformance/README

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md` (§14 closing sentence; §9 error-budget maturity line)
- Modify: `conformance/README.md` (DORA note)

- [ ] **Step 1: Reference the doc + collector from §14**

Find this EXACT line:
```
The last two have no DORA equivalent and are the agentic-specific signals: review latency (the real constraint) and whether *adjust* actually lands.
```
Replace with:
```
The last two have no DORA equivalent and are the agentic-specific signals: review latency (the real constraint) and whether *adjust* actually lands. **Collect them:** `docs/operations/dora-metrics.md` (per-metric GitHub data source + the maturity-gating path + a dashboard pattern); `scripts/dora.sh` reports the GitHub-derivable subset (release cadence, PR lead time, review latency).
```

- [ ] **Step 2: Cross-reference the maturity-gating path from §9**

Find this EXACT line:
```
- **Maturity step: hard-gate** — a project at production scale may promote to SRE-style gating (non-critical releases freeze when the budget is burned until reliability recovers). Mirrors the Stage 1–4 scale progression in `DEVELOPMENT-STANDARDS.md`.
```
Replace with:
```
- **Maturity step: hard-gate** — a project at production scale may promote to SRE-style gating (non-critical releases freeze when the budget is burned until reliability recovers). Mirrors the Stage 1–4 scale progression in `DEVELOPMENT-STANDARDS.md`. The same soft→hard promotion applies to the DORA change-failure rate / MTTR — see `docs/operations/dora-metrics.md`.
```

- [ ] **Step 3: Add the DORA note to conformance/README.md**

Find this EXACT line (the `> **Progressive delivery...` note added in 8e):
```
> **Progressive delivery (reference, no separate check):** `definition-of-deployable.md`'s progressive-delivery + smoke-gate rows pair with [`../docs/operations/progressive-delivery.md`](../docs/operations/progressive-delivery.md) for the *how* (canary/blue-green + smoke gates at every promotion boundary). The checklist is the conformance; the reference completes the triad.
```
Insert this note DIRECTLY AFTER it (with a blank line between):
```
> **DORA metrics (measurement-enablement, no gate):** §14's DORA four + agentic signals are *collected*, not gated — `../scripts/dora.sh` (GitHub-derivable subset; CI-smoked via `--selftest`) + [`../docs/operations/dora-metrics.md`](../docs/operations/dora-metrics.md) (derivation + the maturity-gating path). Value-gating is a §9 maturity step, not a baseline check.
```

- [ ] **Step 4: Verify**

Run:
```bash
grep -c "scripts/dora.sh\` reports the GitHub-derivable subset" DEVELOPMENT-PROCESS.md
grep -c "same soft→hard promotion applies to the DORA" DEVELOPMENT-PROCESS.md
grep -c "DORA metrics (measurement-enablement, no gate)" conformance/README.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; second `1`; third `1`; links `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add DEVELOPMENT-PROCESS.md conformance/README.md
git commit -m "docs: reference DORA collection from §14, §9 maturity-gating, README

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- TWO files. Preserve special chars (→, §). The README note uses real Markdown links validated by `check-links.sh` (paths relative to `conformance/`: `../scripts/dora.sh`, `../docs/operations/dora-metrics.md`). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 4, commit SHA, any concerns.

---

### Task 4: Dogfood the collector in kit CI

**Files:**
- Modify: `.github/workflows/ci.yml` (conformance job — after the Resilience-ready selftest step)

- [ ] **Step 1: Find the insertion point**

Run: `grep -n "Resilience-ready self-test" .github/workflows/ci.yml`
Expected: one match (the last step of the `conformance` job, before `bootstrap:`). Insert the new step directly after its `run:` line.

- [ ] **Step 2: Add the dora smoke step**

After the `run: sh conformance/resilience-ready.sh --selftest` line, insert (6-space `- name:`, 8-space `run:`):
```yaml
      - name: DORA collector smoke (executes + degrades cleanly)
        run: sh scripts/dora.sh --selftest
```

- [ ] **Step 3: Verify placement + it passes locally**

Run:
```bash
grep -n "DORA collector smoke" .github/workflows/ci.yml
sed -n '40,52p' .github/workflows/ci.yml   # confirm the step is in the conformance job, before bootstrap:
sh scripts/dora.sh --selftest; echo "selftest=$?"
```
Expected: the step is the tail of the `conformance` job (before `bootstrap:`); `selftest=0`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: dogfood the DORA collector (dora.sh --selftest)

Smokes the collector (executes + degrades cleanly); never gates on the
numbers. Honest enforcement — the tool works, not the values.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY `.github/workflows/ci.yml`. One step, in the `conformance` job, before `bootstrap:`. Indentation MUST match siblings. Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 3 (especially the sed showing placement), commit SHA, any concerns.

---

### Task 5: Version bump, CHANGELOG, ROADMAP (Slice 8 complete)

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Replace the contents of `VERSION` (`2.23.0`) with:
```
2.24.0
```

- [ ] **Step 2: Add the CHANGELOG entry**

Insert this entry IMMEDIATELY ABOVE the `## [2.23.0] - 2026-06-09` line:
```markdown
## [2.24.0] - 2026-06-09

Slice 8f — DORA metrics collection. Sixth and final sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap C1 (DORA defined but not instrumented). **Completes Slice 8.**

### Added
- **`docs/operations/dora-metrics.md`** — a collection reference: per-metric GitHub data source + derivation (incl. the adopter-wired change-failure rate / MTTR / retro-closure), the **§9 maturity-gating path** (the home for DORA enforcement — opt-in at scale), and a dashboard pattern. DORA is a feedback instrument, not a gate.
- **`scripts/dora.sh`** — a real collector for the **GitHub-derivable subset** (release cadence, PR lead time, review latency) via `gh` (gh's built-in `--jq` for date math; no separate `jq`). **Degrades gracefully** — any `gh` failure prints "unavailable" and the script still **exits 0** (a report never fails a pipeline) — and names deploy-freq-proper / change-fail / MTTR / retro-closure as adopter-wired. A `--selftest` asserts the no-`gh` degradation path.
- **Kit CI** smokes the collector (`dora.sh --selftest`) — proves it executes + degrades, never gates on the numbers.
- **`DEVELOPMENT-PROCESS.md`** §14 references the doc + collector; §9 cross-references the DORA change-fail / MTTR maturity-gating.

### Note
MINOR (2.24.0): additive — a reference + a report script + a CI smoke. **No new conformance gate**: DORA-value-gating is deliberately a §9 maturity step, not a baseline (a presence check would be theatre; a value-gate baseline would punish early-stage projects). No new CI gate-id; §14's gate set unchanged. **This release completes Slice 8** (incident response · definition of deployable · DR/backup-restore · resilience+load · progressive delivery · DORA).
```

- [ ] **Step 3: Add the ROADMAP row + mark Slice 8 complete**

In `docs/ROADMAP-KIT.md`, insert this row IMMEDIATELY AFTER the `8e ✅` row:
```
| 8f ✅ | **DORA metrics collection** *(shipped v2.24.0)* | process §14/§9 (DORA + maturity-gating) | `dora-metrics.md` + `scripts/dora.sh` (GitHub-derivable subset, graceful degradation, --selftest) | `dora.sh --selftest` (CI smoke) + `check-links.sh` |
```

- [ ] **Step 4: Verify**

Run:
```bash
cat VERSION
grep -c "## \[2.24.0\]" CHANGELOG.md
grep -c "8f ✅" docs/ROADMAP-KIT.md
grep -c "Completes Slice 8" CHANGELOG.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: `2.24.0`; `1`; `1`; `1`; links `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.24.0 — DORA metrics collection (8f); completes Slice 8

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY those three files. Insert-only for CHANGELOG/ROADMAP. Preserve special chars (—, →, §, ÷, ✅). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 4, commit SHA, any concerns.

---

### Task 6: Full conformance sweep + push + PR (stop for ratification)

**Files:** none (verification + push only)

- [ ] **Step 1: Run every conformance check + both dora paths**

Run:
```bash
sh conformance/check-links.sh; echo "links=$?"
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" >/dev/null 2>&1 || echo "FAIL $p"; done; echo "ci-gates done"
sh conformance/profile-completeness.sh >/dev/null 2>&1; echo "profiles=$?"
sh conformance/agent-autonomy.sh >/dev/null 2>&1; echo "autonomy=$?"
sh conformance/container-supply-chain.sh >/dev/null 2>&1; echo "containers=$?"
sh conformance/backlog-adapters.sh >/dev/null 2>&1; echo "backlog=$?"
sh conformance/guard-wired.sh >/dev/null 2>&1; echo "guard=$?"
sh conformance/deployable-ready.sh --selftest >/dev/null 2>&1; echo "deployable-selftest=$?"
sh conformance/dr-ready.sh --selftest >/dev/null 2>&1; echo "dr-selftest=$?"
sh conformance/resilience-ready.sh --selftest >/dev/null 2>&1; echo "resilience-selftest=$?"
sh scripts/dora.sh --selftest >/dev/null 2>&1; echo "dora-selftest=$?"
DORA_FORCE_NO_GH=1 sh scripts/dora.sh >/dev/null 2>&1; echo "dora-nogh=$?"
```
Expected: `links=0`, no `FAIL` from ci-gates, all the rest `=0`, `dora-selftest=0`, `dora-nogh=0`.

- [ ] **Step 2: Final spec-coverage greps**

Run:
```bash
ls scripts/dora.sh docs/operations/dora-metrics.md
grep -c "ALWAYS exits 0" scripts/dora.sh                                        # 1
grep -c "DORA is a feedback instrument, not a gate" docs/operations/dora-metrics.md  # 1
grep -c "DORA collector smoke" .github/workflows/ci.yml                         # 1
cat VERSION                                                                      # 2.24.0
grep -c "Completes Slice 8" CHANGELOG.md                                         # 1
```

- [ ] **Step 3: Confirm clean tree + push**

```bash
git status --short    # only the pre-existing untracked .firecrawl/
git push -u origin feature/slice-8f-dora-metrics
```

- [ ] **Step 4: Open the PR (do NOT merge — human ratification gate)**

```bash
gh pr create --title "Slice 8f — DORA metrics collection (v2.24.0) — completes Slice 8" \
  --body "$(cat <<'EOF'
Closes gap C1 (Slice 8 arc) and **completes Slice 8**. Instruments the DORA four + agentic signals that §14 maps but nothing collected.

## What
- **`docs/operations/dora-metrics.md`** — per-metric GitHub derivation (incl. adopter-wired change-fail/MTTR/retro-closure), the §9 maturity-gating path (the home for DORA enforcement), and a dashboard pattern.
- **`scripts/dora.sh`** — a real collector for the GitHub-derivable subset (release cadence, PR lead time, review latency) via `gh` (gh `--jq` for date math; no separate `jq`). **Degrades gracefully -> exit 0** (a report never fails a pipeline); names deploy-freq-proper/change-fail/MTTR/retro-closure as adopter-wired. `--selftest` asserts the no-`gh` path.
- **Kit CI** smokes the collector (`dora.sh --selftest`) — proves it runs + degrades, never gates on numbers.
- **§14 / §9 / conformance README** reference the collection + the maturity-gating path.

## Why no baseline gate (discussed + recorded)
DORA is a feedback instrument. A presence check measures the wrong thing (copied a file != measures-and-improves); a value-gate baseline punishes early-stage projects; the kit deliberately makes DORA-value-gating a §9 maturity step. So: collect + surface, document the maturity-gating path, CI-smoke the collector — no baseline conformance gate.

## Verification
All conformance green; `dora.sh --selftest` 0 (CI) and the no-gh path exits 0; `sh -n` + `dash -n` clean; **MINOR -> 2.24.0** (no new CI gate-id; §14 gate set unchanged).

## Governance
Governing-doc surface (PROCESS §14/§9) -> **security-owner lens**. Agent does not self-merge — this PR stops for human ratification. **Merging this completes Slice 8.**

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: STOP for human ratification**

Do not merge. Report the PR URL + green conformance to Bradley (governing-doc change → security-owner lens per §13/RBAC). Note that merging completes Slice 8.

---

## Self-Review

**1. Spec coverage:**
- Deliverable A (dora-metrics.md reference) → Task 2. ✅
- Deliverable B (scripts/dora.sh, graceful degradation, --selftest) → Task 1. ✅
- Deliverable C (§14 reference) → Task 3 Step 1. ✅
- Deliverable D (§9 maturity-gating cross-ref) → Task 3 Step 2. ✅
- Deliverable E (conformance README note) → Task 3 Step 3. ✅
- Deliverable F (CI smoke step) → Task 4. ✅
- Meta + Slice 8 complete → Task 5. ✅
- No baseline gate (spec §2) → no task adds a conformance script/checklist; the CI step is a smoke, not a gate. ✅
- Graceful degradation → exit 0 (spec §5) → Task 1 Step 3 asserts it; Task 6 Step 1 `dora-nogh=0`. ✅

**2. Placeholder scan:** No "TBD/implement later". The `${WINDOW}` in the jq strings is intentional (validated-digit interpolation). The `[date]`-style tokens do not appear. The script, doc, and edits are given in full. ✅

**3. Consistency:** `scripts/dora.sh` and `docs/operations/dora-metrics.md` paths are identical across Task 1/2 (create), Task 3 (§14/§9/README), Task 4 (CI), CHANGELOG, ROADMAP. The selftest output string "dora --selftest: OK" and the degradation message "gh not available" in Task 1 match the selftest's own greps. The "ALWAYS exits 0" comment string (Task 6 grep) is present in the script header. The CI step name "DORA collector smoke" matches between Task 4 and Task 6 grep. The README note's relative links (`../scripts/dora.sh`, `../docs/operations/dora-metrics.md`) resolve from `conformance/`. ✅
