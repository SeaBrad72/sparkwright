# Plan — blanket export-ignore for `docs/architecture/` (T4 item 6)

**Design:** `docs/architecture/2026-06-29-blanket-export-ignore-design.md` (owner-approved 2026-06-29).

**Goal:** One blanket `docs/architecture/ export-ignore` rule + a lock that asserts the blanket, so all design/meta-control docs (present + future) are excluded from adopter exports.

**Architecture:** `git archive --worktree-attributes` already honors directory export-ignore patterns; the lock already handles directory IGN entries (`docs/superpowers/`). So: collapse the enumerated `.gitattributes` + `IGN` entries to the `docs/architecture/` dir-entry, de-link the one kept→architecture markdown link, and add a non-vacuous "unlisted doc is excluded" selftest. No export-script change.

**Build model:** AMBER — `.gitattributes` + `conformance/adopter-export-wired.sh` are control-plane. Idempotent, clone-proven `apply.py`; version finishing **3.77.0 → 3.78.0** folded in. Build artifacts in `scratchpad/t4/` (gitignored).

**Global constraints:** behaviour of the export mechanism unchanged; non-architecture export-ignore entries unchanged; the lock's existing 4 selftest negatives preserved; `verify.sh --require` + `check-links` stay green on the kit tree AND the exported tree.

---

## File map

| File | Shipped? | Change |
|---|---|---|
| `.gitattributes` | ✅ apply.py | Replace the 13 enumerated `docs/architecture/<file>` lines with one `docs/architecture/ export-ignore` (keep `meta-control-log.md`, `.meta-control-last`, and all non-architecture entries) |
| `conformance/adopter-export-wired.sh` | ✅ apply.py | (a) `IGN` var: enumerated architecture entries → `docs/architecture/`; (b) run(): assert export contains no `docs/architecture/`; (c) new positive-blanket selftest case (unlisted doc excluded + load-bearing negative) |
| `docs/operations/agentic-ops.md` | ✅ apply.py | Line 144: de-link the `[…](../architecture/…e5-thin-otel-sensor-design.md)` reference → plain text |
| `VERSION` · `README.md` · `CHANGELOG.md` | ✅ apply.py | Version finishing → 3.78.0 |
| `scratchpad/t4/apply.py` · `cloneproof.sh` | ❌ build-time | Applier + clone-proof |

---

## Task 1 — author the 6 anchored edits into `apply.py`

1. **`.gitattributes`**: anchor-replace the 14-line block (current lines 12–25, which interleaves `meta-control-log.md`) with:
   ```
   docs/architecture/                  export-ignore
   docs/governance/meta-control-log.md export-ignore
   ```
2. **lock `IGN`**: anchor-replace the full current `IGN="…"` line with the same set but architecture entries collapsed to `docs/architecture/` (keep governance entries).
3. **lock run() (c-direct)**: after `[ -e "$_d/docs/ROADMAP-KIT.md" ] && { echo "FAIL: export kept ROADMAP-KIT.md"; rc=1; }`, insert
   `[ -e "$_d/docs/architecture" ] && { echo "FAIL: export kept docs/architecture/ (blanket export-ignore not honored)"; rc=1; }`.
4. **lock selftest (positive-blanket)**: before the final `[ "$sfail" -eq 0 ]` line, insert a case: archive HEAD → add `docs/architecture/zzz-unlisted-probe.md` → commit → export → assert ABSENT; then strip the `docs/architecture/` rule from the fixture `.gitattributes`, re-commit, re-export → assert PRESENT (load-bearing negative; a vacuous probe fails here).
5. **`agentic-ops.md:144`**: replace the linked sentence with a de-linked plain-text equivalent (no `](…)`).
6. **version finishing**: VERSION 3.77.0→3.78.0; README ``v3.77.0``→``v3.78.0``; CHANGELOG `## [3.78.0] — 2026-06-29` block.

apply.py: integrity-light (anchored string edits), all-or-abort (validate every anchor before writing), idempotent (skip if the new form is already present).

## Task 2 — clone-prove

`cloneproof.sh`: clone main → run apply.py → assert:
- `adopter-export-wired.sh --selftest` → OK (now 5 cases incl. positive-blanket).
- `adopter-export-wired.sh` real-run → PASS.
- `verify.sh --require` → 0 failed (the lock's export-tree `verify --require` + `check-links` stay green — proves the `agentic-ops.md` de-link removed the last kept→architecture link).
- A direct export inspection: `adopter-export.sh <tmp>` then `[ ! -e <tmp>/docs/architecture ]` (whole dir dropped) and a count showing ~65 fewer files than before.
- apply.py 2nd run = idempotent no-op; exactly 6 files change (`.gitattributes`, lock, `agentic-ops.md`, VERSION, README, CHANGELOG).

## Task 3 — dual review + panel #29 + ship

Reviewer (correctness/standards/non-vacuity) + security-reviewer (adopter-distribution integrity gate: confirm no teeth weakened, the blanket can't be subverted, the de-link doesn't drop adopter-needed content). Meta-control panel #29. Human ships (apply.py → governance close `3.78.0 GO` → commit → PR → admin-merge → release-tag).

## Honest ceiling
Proven: blanket present + asserted, real export drops the whole dir, an unlisted doc is excluded, exported tree stays green. Assumed (stated): all `docs/architecture/` is maintainer-internal (true today).
