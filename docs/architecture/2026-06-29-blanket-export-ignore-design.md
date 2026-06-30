# Design — blanket export-ignore for `docs/architecture/` (T4 item 6)

**Date:** 2026-06-29
**Slice:** Roadmap T4 item 6 — stop design/meta-control docs leaking into adopter exports.
**Change-class:** Control-plane (`.gitattributes` + a conformance lock) — AMBER `apply.py`; dual review.
**Status:** DESIGN — owner-approved 2026-06-29.

---

## 1. Problem

`.gitattributes` export-ignores maintainer-internal design docs **one file at a time**, and the
list was last extended at **2026-06-26**. Measured on main: **78** `docs/architecture/*.md`
exist, only **13** are export-ignored → **65 leak** into the adopter distribution
(`scripts/adopter-export.sh`, which runs `git archive --worktree-attributes HEAD`). Every new
design doc or meta-control panel leaks silently — no CI goes red, because the lock
(`conformance/adopter-export-wired.sh`) only checks that the *enumerated* entries are ignored,
never that *all* design docs are. This is a self-perpetuating drift: the just-shipped v3.77.0
docs already leak.

## 2. Goal & non-goals

- **Goal:** a single blanket rule so every `docs/architecture/` doc — present and future —
  is excluded from adopter exports, with the lock asserting the blanket (not an enumeration)
  so the drift class cannot recur.
- **Non-goal:** changing the export *mechanism* (git archive already honors directory
  patterns); changing which non-architecture paths are ignored; shipping design docs to
  adopters.

## 3. The fix (small; follows an existing pattern)

1. **`.gitattributes`** — replace the 14 enumerated `docs/architecture/<file> export-ignore`
   lines with **one** blanket `docs/architecture/ export-ignore`. Keep all non-architecture
   entries (`docs/ROADMAP-KIT.md`, `drift-watch.yml`, `golden-path.yml`, `docs/superpowers/`,
   `.superpowers/`, `.github/CODEOWNERS`, `docs/governance/meta-control-log.md`,
   `docs/governance/.meta-control-last`). `git archive --worktree-attributes` honors directory
   export-ignore natively → **no change to `adopter-export.sh`**.
2. **`conformance/adopter-export-wired.sh`** — in the `IGN` var, swap the enumerated
   architecture entries for the single `docs/architecture/` **dir-entry**. This is the *same
   directory-entry form the lock already handles* for `docs/superpowers/` and `.superpowers/`,
   so block (a) presence-check, block (b) link-safety `git grep` + `:(exclude)` logic, and the
   unsafe-char guard all work unchanged (basename of `docs/architecture/` → `architecture`,
   the link scan greps `](…architecture…)`).
3. **`docs/operations/agentic-ops.md:144`** — the *only* kept→architecture markdown link
   (`[…](../architecture/2026-06-26-e5-thin-otel-sensor-design.md)`). De-link it: keep the
   sentence, drop the `](…)` target so no adopter-tree link dangles. (Verified by `git grep`:
   this is the single kept doc that links into `docs/architecture/`.)

## 4. New teeth (the slice's value — non-vacuity)

The current lock proves "the *listed* entries are ignored + the export drops them." The blanket's
value is **future docs self-exclude**, which the enumeration could never test. Add:
- **(c-direct)** in `run()`: assert the produced export contains **no** `docs/architecture/`
  directory at all (`[ -e "$_d/docs/architecture" ] && FAIL`). A direct, strong check that the
  blanket actually pruned the whole dir.
- **(selftest)** a positive-blanket case: a fixture tree with a `docs/architecture/NEW-unlisted.md`
  (never individually listed) + the blanket `.gitattributes` → export → assert `NEW-unlisted.md`
  is **absent** from the export. The load-bearing negative: the same tree WITHOUT the blanket
  rule must leak it (so the assertion is non-vacuous — it fails when the blanket is removed).

The lock already drives `git archive` for real and runs `verify.sh --require` + `check-links`
on the exported tree, so a broken link or a control that depends on a now-pruned doc is caught.

## 5. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Blanket-ignore breaks a kept doc's link to a design doc (check-links red on adopter tree) | Exactly one such link exists (`agentic-ops.md:144`) — de-linked in this slice; the lock's export-tree `check-links` confirms zero remain |
| A future architecture doc legitimately needs to ship to adopters | Honest ceiling (below): the blanket is the right default; an exception would be an explicit per-file un-ignore + a noted carve. None exists today |
| Lock's basename scan for `docs/architecture/` over-matches | Same coarse-but-safe behaviour already accepted for `docs/superpowers/`; after the one de-link, no kept doc matches |
| `git archive` directory-pattern semantics differ from per-file | Proven by clone: the export is inspected for an absent `docs/architecture/` and a dropped unlisted fixture doc |

## 6. Honest ceiling

- Proven: the blanket rule is present, the lock asserts it (not an enumeration), the real export
  drops the whole `docs/architecture/` dir, an *unlisted* doc is excluded, and the exported tree
  stays green (`verify --require` + `check-links`).
- Assumed (stated, not proven): every `docs/architecture/` doc *should* be maintainer-internal.
  True today (design docs + meta-control panels). A future doc meant for adopters would need an
  explicit un-ignore — out of scope here.

## 7. Build model & version

Control-plane (`.gitattributes` + `conformance/adopter-export-wired.sh`) → AMBER `apply.py`
(whole-file or anchored edits; idempotent; clone-proven) with version finishing **3.77.0 →
3.78.0** folded in. Dual review (reviewer + security — security because the lock is an
adopter-distribution integrity gate). Meta-control panel #29. Human ships.
