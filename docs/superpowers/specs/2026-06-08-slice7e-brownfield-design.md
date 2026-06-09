# Design — Slice 7e: Brownfield Adoption & `.claude/` Hygiene

**Date:** 2026-06-08
**Status:** Approved (design) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Fifth sub-slice of Slice 7. Closes audit gap G10 (brownfield adoption + pre-existing `.claude/` unsupported; `.claude/` scoping undocumented). Plan: `~/.claude/plans/drifting-stirring-thunder.md` §7e.

---

## 1. Goal

Make the kit adoptable into an **existing** repo (brownfield) without clobbering the adopter's `.claude/`, document `.claude/` **scoping** so adopters know their machine is untouched, and — critically — make the **runtime guard's liveness a verified conformance check**, not a recommendation. Brownfield inverts the kit's risk gradient: a legacy repo already has prod credentials/contexts wired, so adopting agentic work with a *silently-inactive guard* is the worst case. The slice's enforcement teeth is a check that fails closed when the guard isn't wired.

## 2. Threat model (what this slice defends against)

If a brownfield adopter does **not** follow the merge guidance, they can adopt the kit's *process* while leaving its *guardrail* off:
- **Inactive guard / false assurance** — their own `.claude/settings.json` is kept but never registers `guard.sh`; agents run on a live legacy system with no PreToolUse protection.
- **Reverse clobber** — overwriting their own `.claude/` with the kit's, destroying their existing hooks.
- **Pre-wired blast radius** — legacy repos already have `.env`/cloud creds/kube contexts; an unguarded agent reaches prod immediately.
- **Guard-coverage gap** — the pattern-based guard may not recognize the legacy repo's bespoke destructive commands.
- **Human/other-runtime gap** — the guard covers only the Claude Code runtime (the 7a Org-owned boundary), which matters more on a legacy system with other automation/humans holding prod access.

The defense: a **fail-closed liveness check** (`guard-wired.sh`) wired into the Inception-Done gate, a **threat-model-first** brownfield doc, and honest documentation of the residual gaps + Org-owned backstop.

## 3. Decisions

- **Docs-first + minimal incept safety + a verification check.** No copy/adopt script (clobber risk); the human performs the `.claude/` merge — the kit shows exactly how, verifies the result, but never scripts the merge (the do-no-harm line).
- **`guard-wired.sh` is the enforcement teeth** — asserts the guard is actually live; wired into `inception-done.sh` so no project (greenfield *or* brownfield) passes Inception with a dead guard.
- **`incept.sh` only ever warns** about a foreign/un-merged `.claude/`; it never modifies or deletes it.
- **MINOR → 2.17.0** (docs + a warning + an additive conformance check; no new universally-required CI gate, no breaking change).

## 4. Deliverables

| Part | Files |
|------|-------|
| Brownfield path | `docs/adoption/brownfield.md` (new) |
| Scoping docs | `README.md` (`.claude/` project-vs-global section); `START-HERE.md` (brownfield router row → guide) |
| Guard liveness | `conformance/guard-wired.sh` (new); `conformance/inception-done.sh` (invoke it); `conformance/README.md` (index it) |
| Incept safety net | `scripts/incept.sh` (warn on un-wired `.claude/`, never modify) |
| Honesty | brownfield doc states guard-coverage gap + Org-owned platform backstop |
| Meta | `VERSION` 2.17.0; `CHANGELOG.md`; `docs/ROADMAP-KIT.md` (7e row) |

## 5. Detailed design

### 5.1 `conformance/guard-wired.sh` (new — the enforcement teeth)
A POSIX `sh`, fail-closed check that the runtime guard is actually active in a project dir:
- `.claude/settings.json` exists **and** registers a `PreToolUse` hook invoking `guard.sh` (grep for `guard.sh` within the file — the kit wires it as `sh "$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh"`).
- `.claude/hooks/guard.sh` exists **and** is executable (or invocable via `sh`).
- Takes an optional dir arg (default `.`), like `inception-done.sh`.
- Exit 0 = guard live; exit 1 with a clear FAIL message ("runtime guard NOT wired — agents would run unprotected; see docs/adoption/brownfield.md") otherwise.
- Run anytime; also called by the Inception gate. A **negative test** in the plan (rename the hook out / strip the settings registration → must FAIL) proves it non-vacuous.

### 5.2 `conformance/inception-done.sh` (wire the gate)
The gate currently does `need .claude` (existence only). Add a guard-**liveness** assertion: after the `need .claude` line, invoke `guard-wired.sh` for the same dir and fold its result into `fail`. So Inception-Done now requires not just that `.claude/` exists but that the guard is *wired*. (Greenfield passes automatically — the kit ships it wired; brownfield must merge correctly to pass.)

### 5.3 `docs/adoption/brownfield.md` (new — threat-model first)
Structure:
1. **Read this first — the risk.** Lead with the threat model: skip the `.claude/` merge and you get the kit's process without its guardrail; agents operate on your legacy system (existing prod creds, bespoke destructive scripts) with no runtime protection. **Verify with `sh conformance/guard-wired.sh` (must PASS) before any agent runs.**
2. **Greenfield vs brownfield** — when each applies.
3. **Copy-in steps** — which kit files to bring in (governing docs, `profiles/`, `conformance/`, `templates/`, `.github/` CI, `scripts/`, `.claude/`) and which to adapt.
4. **The `.claude/` MERGE policy (do-no-harm core)** — if your repo already has `.claude/`, do **not** overwrite: keep your hooks/settings and **add** the kit's `guard.sh` `PreToolUse` hook; **union** `settings.json` (the exact JSON hook block shown verbatim to paste); the kit's `settings.local.json` is gitignored, never committed over yours.
5. **Inception adapted** — `incept.sh`'s greenfield rename (`CLAUDE.md`→`ENGINEERING-PRINCIPLES.md`) assumes the kit's root principles doc; brownfield adopters do the Inception *judgment* steps manually (charter, ADR-000, roles) — then run `inception-done.sh` (which now checks the guard is live).
6. **Residual gaps (honest):** the guard is pattern-based — extend `guard.sh` for your repo's bespoke destructive verbs; and the **Org-owned platform backstop** (prod IAM, account separation, deploy approvals) is necessary and matters *more* in brownfield because the blast radius pre-exists (ties to the 7a human-coverage boundary).

### 5.4 `README.md` `.claude/` scoping section
A short subsection (near "Quickstart" / "Adapting it"): `.claude/` is **project-level** — it lives in the repo and governs Claude Code only within that repo's tree; it does **not** touch the user's global `~/.claude/`. `settings.json` = committed team policy; `settings.local.json` = gitignored personal overrides. **Dropping the kit in affects only that repo, not your machine.** Link the brownfield doc.

### 5.5 `START-HERE.md` brownfield row
Update the 7b router row from "a dedicated brownfield path is planned" → "see `docs/adoption/brownfield.md`."

### 5.6 `scripts/incept.sh` safety net
Before bootstrapping (after the existing "is this a kit?" guards): if `.claude/settings.json` exists but does **not** register the guard (`grep -q guard.sh` fails), print a WARNING — "a `.claude/` without the kit guard was detected; if this is an existing repo, MERGE per `docs/adoption/brownfield.md` before proceeding (the kit must add, not overwrite, `.claude/`)" — and continue **without touching `.claude/`**. In the greenfield flow the kit's settings register the guard, so it never fires. Warning only; never modifies.

## 6. Validation / testing
- `sh conformance/check-links.sh` → 0 (new doc + links resolve).
- `sh conformance/guard-wired.sh` → 0 against the kit root (guard is wired); **negative test:** temporarily strip the `guard.sh` registration from a copy → exit 1 (proves non-vacuous); restore.
- `sh conformance/inception-done.sh` against a fixture: with the guard wired → the guard line PASSes; with it unwired → the gate FAILs on the new assertion. (Note the kit root still fails inception-done for the pre-existing reasons — ADR/RUNBOOK/etc. — but the *guard* line must PASS there since the kit ships it wired.)
- `sh -n scripts/incept.sh` (+ `dash -n`) → clean; the warning fires only when `.claude/settings.json` lacks `guard.sh`.
- `profile-completeness.sh`, `agent-autonomy.sh`, `container-supply-chain.sh`, `backlog-adapters.sh`, `ci-gates.sh` ×10 → green (no regression).
- Kit CI green.

## 7. Risks & mitigations
- **Adopter ignores the doc.** Mitigation: `guard-wired.sh` gated by Inception-Done fails closed — the recommendation is enforced, not hoped-for.
- **`guard-wired.sh` false-passes a dead guard.** Mitigation: it checks registration *and* file presence/invocability; negative test proves it catches an unwired guard.
- **Wiring guard-liveness into inception-done breaks the kit's own bootstrap conformance.** Mitigation: the kit ships the guard wired, so the new assertion PASSes at the kit root (only the pre-existing ADR/RUNBOOK checks fail there, unchanged); verified in §6.
- **incept warning fires spuriously.** Mitigation: keyed on the precise `guard.sh` registration signal, which the kit's own settings satisfy.
- **Scripting the merge would clobber.** Mitigation: we don't — docs + verify only.

## 8. Out of scope
- A copy/adopt script (rejected — clobber risk).
- Auto-merging `.claude/` (human-performed; the kit shows how and verifies the result).
- Extending the guard's destructive-pattern coverage for specific legacy tools (the doc instructs adopters to do it for their repo; the kit doesn't enumerate every bespoke tool).
- The 7f-deferred items (Security-owner casing, inception-done-on-kit-root note) — stay in 7f.

## 9. Definition of Done
- `conformance/guard-wired.sh` present, fail-closed, negative-tested; invoked by `inception-done.sh`; indexed in `conformance/README.md`.
- `docs/adoption/brownfield.md` ships: threat-model-first, copy-in steps, the `.claude/` merge policy (verbatim hook block), Inception-adapted, residual-gaps + Org-owned backstop.
- `README.md` `.claude/` scoping section; `START-HERE.md` brownfield row → guide.
- `scripts/incept.sh` warns (never modifies) on an un-wired `.claude/`.
- All conformance green; the guard-liveness line PASSes at the kit root; `VERSION` 2.17.0; CHANGELOG + ROADMAP (7e).
- Feature branch → PR → **human ratification** (governing surface + a security check → Security-Owner lens). Agent never self-merges.
