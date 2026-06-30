# Design — Golden-path trigger-filter parity (T4 item 1)

**Date:** 2026-06-30
**Slice:** T4 item 1 (widen the golden-path `paths:` filter + lock the parity so it can't recur). Item 5 (private-repo `enforce_admins` note) is handled as a roadmap correction only — it already shipped in `review-lane.md` at v3.48.11.
**Version:** 3.79.0 → 3.80.0 (MINOR — additive new claim + check).

---

## Problem

`.github/workflows/golden-path.yml` is the heavy end-to-end harness (npm pipeline + docker build + liveness + the operate-loop / orchestrator / OTLP jobs). It is deliberately **path-filtered** (`on.pull_request.paths` / `on.push.paths`) so the fast per-PR `ci.yml` stays seconds-quick — golden-path only runs when a file it actually exercises changes.

The filter is a **hand-maintained literal list**, and it has drifted: seven files that the golden-path jobs invoke are **absent** from the filter, so a change to any of them will **not** re-trigger the end-to-end proof:

| File | Invoked by job |
|------|----------------|
| `scripts/smoke.sh` | golden-path (kill-switch / feature boot) |
| `scripts/otlp-export.sh` | golden-path, otlp-backend, trace-query |
| `scripts/escalate.sh` | orchestrator-loop |
| `conformance/escalation-wired.sh` | orchestrator-loop |
| `conformance/actionlint-valid.sh` | generator-golden-path |
| `conformance/provenance-precondition.sh` | generator-golden-path |
| `conformance/ci-gates.sh` | generator-golden-path |

This is a **parity-drift class** (the same shape as the producer-flag ↔ stamped-artifact-name smell): a hand-kept list that must track an independently-evolving set, with nothing asserting they agree. Fixing the list once does not stop it drifting again the next time a job gains a script invocation — which is exactly what happened here.

## Goal

1. **Widen** the filter so the seven drifted files re-trigger golden-path (the actual fix).
2. **Lock** the parity so the class self-closes: a conformance check that fails CI if any invoked script is missing from the filter. "If it isn't automated, it isn't enforced."

## Non-goals

- **Inverse parity** (filter entries that aren't invoked → flag as dead). An over-broad filter is *conservative* — it only causes golden-path to run more often, never the silent-skip bug. Enforcing the inverse is YAGNI.
- **Coarsening the filter to `scripts/**` / `conformance/**`.** Rejected: it undermines the file's explicit design intent (path-filtered so per-PR CI stays fast) by running the heavy harness on far more PRs.
- **Touching `branch-protection.sh`** for item 5. The `enforce_admins` 404-on-private-free-tier caveat already lives in `docs/operations/review-lane.md` (lines 72–78, shipped v3.48.11) — the user-facing place a blocked adopter looks. `branch-protection.sh` does not verify `enforce_admins`, so a note there is misplaced. Item 5 is closed by correcting the roadmap.

## Architecture

### New check — `conformance/golden-path-filter-parity.sh`

Models `conformance/ci-selftest-coverage.sh` (the kit's existing workflow-scanner meta-check): a `scan()`-style core, a kit-self N/A detector, and a non-vacuous `--selftest`.

**Core logic (`check_parity <workflow_file>`):**

1. **Filter set** — extract single-quoted tokens from the `paths:` lines:
   `grep 'paths:' "$f" | grep -oE "'[^']*'" | tr -d "'"` (union of the pull_request + push lists; they are identical).
2. **Invoked set** — comment-stripped, excluding the `paths:` lines, extract script tokens:
   `sed 's/#.*//' "$f" | grep -v 'paths:' | grep -oE '(scripts|conformance)/[A-Za-z0-9._/-]+\.sh' | sort -u`.
3. **Assert invoked ⊆ filter** — for each invoked token `T`, PASS if:
   - `T` appears literally in the filter set, **or**
   - the filter contains a glob `E` ending `/**` whose prefix is a path-prefix of `T` (so `scripts/**` covers `scripts/foo.sh` — future-proofs against a filter rewrite).
   Otherwise FAIL, listing `T`. Fail-closed: any missing token fails the check.

**Exit contract:** `0` = parity holds (or N/A outside the kit) · `1` = a missing file · `2` = usage.

**Kit-self N/A detector:** when `.github/workflows/golden-path.yml` is absent (a true adopter tree), print `N/A — kit-self check` and exit 0 — identical posture to `ci-selftest-coverage.sh`.

**`--selftest` (non-vacuous, four cases):**
- **dirty** — filter `['scripts/a.sh']`, body invokes `sh scripts/a.sh` + `sh scripts/b.sh` → must FAIL naming `scripts/b.sh`.
- **clean** — filter has both → PASS.
- **glob** — filter `['scripts/**']`, body invokes `sh scripts/c.sh` → PASS (glob covers).
- **comment** — a commented `# sh scripts/d.sh` not in the filter → must NOT fail (proves comment-stripping is load-bearing).

### The widen

Add the seven files to **both** `paths:` lists in `golden-path.yml`. After the widen, the new check passes; removing any one drives it RED (the teeth).

### Registration

- **`conformance/claims.tsv`** — new claim `golden-path-trigger`:
  *"the golden-path trigger `paths:` filter covers every script the workflow invokes — no silent skip (.github/workflows/golden-path.yml)"* → `sh conformance/golden-path-filter-parity.sh`.
- **`conformance/claims-registry.sh`** — add `golden-path-trigger` to `REQUIRED_IDS` (control-plane; protected from silent drop, matching `golden-path` / `conformance-ci-wired`).
- **`.github/workflows/ci.yml`** — two steps next to `golden-path-wired`: a real-run (`sh conformance/golden-path-filter-parity.sh`) and a `--selftest` (required by `ci-selftest-coverage`, since the check ships a `--selftest`).

Not added to `verify.sh` — it is a curated representative aggregate, and the sibling `golden-path-wired` is likewise not in it; the claim runs via `claims-registry` + the dedicated ci.yml steps.

## Delivery — one AMBER `apply.py`

Control-plane paths → AMBER `apply.py` (clone-proven idempotent), version-finishing folded in ([[release-finishing-in-apply-py]]), per-file buffering for the multi-edit files (MAINTAINING §3a):

| File | Change | Control-plane |
|------|--------|:-:|
| `conformance/golden-path-filter-parity.sh` | NEW | ✓ |
| `.github/workflows/golden-path.yml` | widen both `paths:` (buffer the 2 edits) | ✓ |
| `.github/workflows/ci.yml` | +2 steps | ✓ |
| `conformance/claims.tsv` | +1 row | ✓ |
| `conformance/claims-registry.sh` | +id in REQUIRED_IDS | ✓ |
| `docs/ROADMAP-KIT.md` | mark items 1+5 done | — |
| `CHANGELOG.md` / `VERSION` / `README.md` | 3.79.0→3.80.0 + badge | mixed |

Governance close (marker + meta-control-log row) is a separate human-run step (M2-S5 — the agent does not self-certify its own GO).

## Testing / verification

- `sh conformance/golden-path-filter-parity.sh --selftest` (4 cases, mutation-proven non-vacuous).
- `sh conformance/golden-path-filter-parity.sh` real-run green on the widened workflow; RED if a file is removed from the filter.
- `sh conformance/claims-registry.sh` green (new claim verifies; coverage intact).
- `sh conformance/ci-selftest-coverage.sh` green (new `--selftest` wired into ci.yml).
- `sh conformance/golden-path-wired.sh` still green (unaffected).
- `sh conformance/badge-version.sh` green (README badge == VERSION 3.80.0).
- Clone-proven idempotent apply; fresh-clone `verify --require` green.

## Risks

- **Extraction false-positives** from comments → mitigated by comment-stripping (and a selftest case proving it).
- **Extraction over-capture** (a path mentioned in a `run:` that isn't truly an invocation) → only makes the parity requirement *stricter* (more files required in the filter), which is fail-safe.
- **Glob clause untested in production** (current filter is all-literal) → covered by the glob selftest case so the branch is non-vacuous.
