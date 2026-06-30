# Meta-Control Panel #29 — Global-Coherence Verdict

**Slice:** Blanket `export-ignore` for `docs/architecture/` (roadmap T4 item 6)
**Lens:** Independent global-coherence (drift / honest-ceiling / right-weight)
**Date:** 2026-06-29 · **Version finishing:** 3.77.0 → 3.78.0 · **Change-class:** Control-plane (AMBER)
**Steward:** kit-steward (read-mostly; proposes, human ratifies)

## Verdict: **GO**

Clean GO. No conditions. A small, correct, well-proven control-plane hygiene slice that fixes a real silent adopter-distribution leak (66 of 78 maintainer-internal design docs were shipping in `git archive` with no CI red). Both dual reviews APPROVE/PASS; every material proof independently re-run on a fresh clone, all green.

## Independently re-verified (fresh clone)
- leak AFTER = 0 (66 → 0); real export: `docs/architecture` absent
- lock `--selftest` OK (positive-blanket + 4 pre-existing negatives); lock real-run PASS; `verify --require` RESULT OK
- apply.py 2nd run fully idempotent; exactly 6 tracked files change (`.gitattributes`, `CHANGELOG.md`, `README.md`, `VERSION`, `conformance/adopter-export-wired.sh`, `docs/operations/agentic-ops.md`)
- kit-wide shellcheck regression-lock OK (110 files clean at the error/warning floor)

## Global-coherence assessment

**Drift: none.** Exactly what roadmap T4 item 6 specifies — blanket `docs/architecture/ export-ignore` + reconcile the lock's `IGN` var so future docs self-exclude. The roadmap entry even pre-named the one risk ("blanket-ignoring may surface KEPT→ignored link-safety failures the lock will flag") and the slice handled it precisely (the single de-link). Plan predicted reality; no silent re-plan. The fix mirrors the kit's existing `docs/superpowers/` blanket-ignore treatment — consistent with the established pattern, not a novel mechanism.

**Honest ceiling: stated and true.** The load-bearing assumption — "all `docs/architecture/` is maintainer-internal" — was verified directly against the full file listing: every entry is a design/plan doc, a meta-control panel, or `ADR-000-stack.md` (the kit's own dogfood ADR). Nothing adopter-facing is dropped: adopters generate their own ADR from the still-shipping top-level `docs/ADR-000-EXAMPLE.md`, and the only runtime reader of an architecture path (`inception-done.sh`) is outside `--require`. The honest residual: the assumption is a *convention*, not an *enforced invariant* — a future adopter-facing doc mis-filed under `docs/architecture/` would be silently excluded (the inverse leak). Real but low-probability; routed to backlog, not a GO blocker.

**Right-weight: yes.** Small surface (6 tracked files), no export-script change (native `git archive --worktree-attributes` directory-pattern support — leaned on the tool rather than adding code), and the lock moves from a brittle enumeration to a blanket assertion *plus a non-vacuous positive-blanket selftest* that proves an unlisted doc is excluded by the blanket AND leaks when the rule is stripped. The right amount of mechanism for the risk: it converts "silent leak, no CI red" into "CI red if the blanket regresses."

**The de-link is exact.** `agentic-ops.md:144` is the *sole* markdown link from any kept doc into `docs/architecture/`. The other six non-ignored docs that mention `docs/architecture/` (`ROADMAP-KIT.md`, `ADR-000-EXAMPLE.md`, `STACK-SELECTION.md`, `brownfield.md`, `orchestration.md`, `test-layers.md`) use inline-code path mentions, not links — `check-links` does not validate them and they remain accurate references. The other 12 architecture links are all in `meta-control-log.md`, itself export-ignored (ignored→ignored).

## Retro

The clone-proof caught apply.py clobbering its own three lock-edits (independent full-file payloads → only the last survived → lock red → `verify --require` red), fixed via per-file in-memory buffer accumulation. **This is the clone-proof earning its keep — a real bug neither dual review would have caught from the diff alone, because it only manifests on actual application, not inspection.** Routes to a standing practice (below).

## Ledgers

**Verified-as-quality:**
1. Leak 66 → 0; real export has no `docs/architecture/`.
2. Positive-blanket selftest non-vacuous — probe leaks when the rule is stripped.
3. apply.py idempotent (2nd run = full no-op) + all-or-abort + exactly 6 tracked files.
4. `verify.sh --require` RESULT OK (controls + exported-tree); lock real-run PASS.
5. De-link is the sole kept→architecture markdown link; prose mentions are link-safe.
6. Pattern-consistent with existing `docs/superpowers/` blanket handling; no export-script change.
7. Kit-wide shellcheck regression-lock OK.

**Fix-forward (ranked, none blocking):**
1. *(Low)* **Inverse-leak guard.** Nothing enforces "everything under `docs/architecture/` is maintainer-internal." A future mis-filed adopter-facing doc would be silently excluded. Cheap mitigation: a maintainer-internal marker/note (dir-top or `MAINTAINING.md`). → backlog.
2. *(Info)* SC2031 info-level findings in the lock's selftest are pre-existing-pattern, below the gating floor — note only.

## Routing

**To backlog (propose):** "Inverse-leak guard for `docs/architecture/`" — a maintainer-internal marker so a mis-filed adopter-facing doc can't be silently export-ignored. Low priority.

**Standing-practice proposal (propose, do NOT ratify):** "AMBER `apply.py` making ≥2 edits to one file MUST accumulate on a per-file in-memory buffer and write once; idempotence + all-or-abort proven on a *fresh clone*." Codifies the bug caught here so the next multi-edit apply.py can't reintroduce the clobber. Generalizes the existing "release finishing in apply.py" + "clone-proof before believing green" practices.

**Divergence from plan:** none.

---

## Governance close (human-authored per M2-S5)
- **Marker (`.meta-control-last`):** `3.78.0 GO`
- **Log row** (append to `docs/governance/meta-control-log.md`, matching the table's column order):
  `| 2026-06-29 | 3.78.0 | T4 item 6 — blanket export-ignore docs/architecture/ per-slice M verdict (A5) | light (5-lens) | GO | [#29](../architecture/2026-06-29-meta-control-29.md) | 0 blockers · 0 conditions · 2 routed (Low inverse-leak guard; standing-practice per-file-buffer apply.py). Stops a silent adopter-distribution leak: 66 of 78 maintainer-internal docs/architecture/ docs shipped in git archive with no CI red → one blanket docs/architecture/ export-ignore (mirrors docs/superpowers/), lock asserts the blanket + a non-vacuous positive-blanket selftest (unlisted doc excluded; leaks when the rule is stripped), sole kept→architecture link de-linked (agentic-ops.md). git archive --worktree-attributes honors dir patterns — no export-script change. Honest ceiling: all docs/architecture/ maintainer-internal (verified; adopters use top-level ADR-000-EXAMPLE). Clone-proof caught + fixed an apply.py self-clobber (3 edits to one file). Dual-reviewed (correctness APPROVE + security PASS). 6 files; no new claim/gate/guard. |`
