# Design — `prototype`/`team` → `lean` (honest ceremony dial) — T4 item 7 (C1)

**Date:** 2026-06-29
**Slice:** Roadmap T4 item 7 — resolve the `prototype`≡`team` mode-dial dead-letter (C1, confirmed false-promise since M1).
**Change-class:** Control-plane (`scripts/incept.sh` + `conformance/` + a template) — AMBER `apply.py`; dual review.
**Status:** DESIGN — owner-approved direction (collapse to `lean`/`enterprise`) + teeth location (extend `mode-enforcement-blind.sh`) 2026-06-29.

---

## 1. Problem

`incept.sh` offers `--mode prototype|team|enterprise`, but `prototype|team)` is a **single branch with identical behaviour** (both stamp `docs/conditional-obligations.md`); only `enterprise)` differs (governance templates). So `prototype` promises a lighter tier it never delivers, and `team` (a ceremony label) collides with the kit's *other* use of "team" — the solo→**team** human-team governance upgrade (`enforce_admins`/`review-lane.md`). Two axes wearing one word.

The generated `conditional-obligations.md` already calls the lean tier **"process mode: lean"** — the honest name was there all along.

## 2. Goal & non-goals

- **Goal:** an honest ceremony dial — `lean` (default) and `enterprise` — that does not imply team-size and does not promise an undelivered tier. `prototype`/`team` deprecate to `lean` (warn + map; backward-compatible).
- **Non-goals:** changing what `lean`/`enterprise` scaffold (lean == today's prototype|team behaviour, enterprise unchanged); touching the **solo-vs-team governance axis** (`enforce_admins`/`review-lane.md` — a separate, runtime concern, GitHub-enforced); adding an explicit solo/team *declared field* (banked as a separate enhancement).

## 3. The two-axis model (the conceptual fix)

| Axis | Question | Where it lives | Values |
|---|---|---|---|
| **Ceremony mode** (this slice) | how much governance *apparatus* incept scaffolds/surfaces | `--mode`, the CLAUDE `Process mode` field | `lean` · `enterprise` |
| **Solo-vs-team governance** (unchanged) | does a 2nd human ratify, or does the owner self-ratify | `enforce_admins` (branch protection) + `review-lane.md` | solo (`enforce_admins:false`, admin-merge) ↔ team (`enforce_admins:true`, non-author approval) |

The rename makes these orthogonal *in name*, not just in fact. `lean` carries no team-size implication; "team" returns to meaning the human-team upgrade only.

## 4. The change (mode-context only — human-team language untouched)

1. **`scripts/incept.sh`:**
   - `PROCESS_MODES="lean enterprise"` (was `"prototype team enterprise"`).
   - default `MODE="lean"` (was `"team"`).
   - **deprecation alias** (before validation): `case "$MODE" in prototype|team) warn-to-stderr "deprecated; using 'lean' — ceremony only; solo-vs-team governance is the separate enforce_admins/review-lane axis"; MODE="lean";; esac`.
   - prompt (line 112) → `Process mode (lean/enterprise) [lean]:`.
   - help comment (line 10) + `--help` usage (line 51) → `--mode lean|enterprise`.
   - the case (line 195) `prototype|team)` → `lean)` (alias already mapped, so only `lean)` remains).
   - the CLAUDE-stamp `sedi` pattern (line 190) updated to match the new template placeholder.
2. **`templates/PROJECT-CLAUDE-TEMPLATE.md:53`:** `[prototype / team / enterprise]` → `[lean / enterprise]`, with an added disambiguation clause: *"ceremony only; solo-vs-team governance is the separate `enforce_admins` / `review-lane.md` axis."*
3. **`conformance/mode-enforcement-blind.sh`:** (a) the selftest fixture string `prototype)` → `lean)` (cosmetic consistency); (b) **new static assertion block** (the teeth — see §5).

**Not touched:** `review-lane.md` and any "solo→team" / human-team language; the four *incidental* uses of "prototype" (low-fi/throwaway prototypes in `tdd/SKILL.md`, `SHAPING-DOC-TEMPLATE.md`, `discovery-loop.md`, `meta-control.md`).

## 5. Teeth (extend the existing mode lock — no new claim)

`conformance/mode-enforcement-blind.sh` already owns "the mode is enforcement-blind." Add a second, related assertion (same claim, same file, right-weight): **the producer offers honest mode names + the deprecation alias.** Static greps on `scripts/incept.sh`:
- `PROCESS_MODES` is exactly `lean enterprise` (no `prototype`/`team` as a canonical value).
- a `prototype|team` → `lean` deprecation alias is present (so the rename can't silently regress to offering dead names, and old invocations keep working).
- load-bearing selftest negative: a fixture `incept.sh` whose `PROCESS_MODES` still contains `prototype` (or that drops the alias) must FAIL the lock.

**Behavioural proof (build-time, clone-proof — not a shipped gate):** run the real `incept.sh` in a kit clone with `--mode prototype`, `--mode team`, `--mode lean`, `--mode enterprise`, `--mode bogus`, asserting: prototype/team stamp `lean` + emit the deprecation notice; lean/enterprise work; bogus errors (exit 2). Running incept needs the full kit tree in CWD — the same reason `mode-enforcement-blind` doesn't run it — so this is a build-time proof, stated in the honest ceiling, not a CI gate. (The bootstrap CI job already runs incept with no `--mode` → now defaults to `lean`; `inception-done.sh` stays green since `lean` scaffolds exactly what `team` did.)

## 6. Risks & mitigations

| Risk | Mitigation |
|---|---|
| An existing `--mode team`/`prototype` invocation breaks | Deprecation alias (warn + map to lean), not a hard error — backward-compatible |
| The CLAUDE-stamp `sedi` no longer matches the template (silent non-stamp) | Template field + the `sedi` pattern are edited together; clone-proof asserts the stamped CLAUDE.md shows the chosen mode |
| Accidentally renaming a human-team "team" reference | Surface enumerated in §4; only mode-context spots touched; `review-lane.md` explicitly out of scope; clone-proof greps that "solo→team" language is unchanged |
| Bootstrap CI assumed `team` default | It runs incept with no `--mode`; new default `lean` scaffolds identically; `inception-done.sh` re-verified in clone-proof |

## 7. Honest ceiling

- Proven (shipped lock): incept offers only `lean`/`enterprise` canonical + a `prototype|team→lean` alias is present; mode stays enforcement-blind.
- Proven (build-time clone-proof): the alias actually maps + warns; `lean`/`enterprise` work; `bogus` errors; the stamped CLAUDE.md reflects the mode.
- **Not** changed/claimed: the solo-vs-team governance axis (`enforce_admins`/review-lane) — untouched; an explicit solo/team declared field does not exist (banked enhancement).

## 8. Build model & version

Control-plane → AMBER `apply.py` (anchored edits, per-file buffer per the new MAINTAINING §3a, idempotent, clone-proven), version finishing **3.78.0 → 3.79.0** (MINOR — additive `lean` + deprecation, no hard removal). Dual review (reviewer + security: incept is the project-genesis surface; confirm no enforcement weakened, the alias can't be abused, human-team language intact). Meta-control panel #30.
