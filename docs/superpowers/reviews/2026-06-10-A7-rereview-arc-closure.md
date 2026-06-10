# A7 — Re-Review & Arc Closure — agentic-sdlc-kit @ v2.38.0

**Date:** 2026-06-10 · **Method:** the same 9 independent, skeptical lenses from the [2026-06-09 review](2026-06-09-independent-multiagent-review.md), each re-run with a fresh read of current `main`, briefed with its own prior score and instructed to verify (read files / run checks) rather than trust. This is the **exit gate** of the "Honest Assurance & Adoption Reach" arc (Slices 9a–9k-b + A4).

> **Bottom line:** Every lens improved. Persona average **5.5 → 8.5**; overall **5.83 → 8.44**. **Four of the five convergent findings are fully resolved**; the fifth (the runtime guard) is resolved *where the kit can enforce it* and — more importantly — its residual is now **honestly disclosed as a platform-owned boundary** rather than hidden behind a "does no harm" claim. The arc's thesis holds: the kit moved from *overselling safety it didn't have* to *honestly-scoped assurance with the boundary drawn in ink*.

---

## Scorecard — before → after

| Lens | 2026-06-09 | 2026-06-10 | Δ | New one-line |
|------|:---------:|:---------:|:--:|----------|
| **Whole-framework (SWOT)** | 6.5 | **8.0** | +1.5 | 6 of 9 weaknesses fully resolved + live-verified; the residual safety gap is now *disclosed*, not hidden |
| Persona — Beginner | 4 | **7** | +3 | Real on-ramp (preflight · glossary · rename disclosure · solo track); two cheap residuals remain |
| Persona — Brownfield | 6 | **9** | +3 | Governed waiver + ratchet; secret-scan/branch-protection provably non-waivable |
| Persona — Team on Jira | 5 | **8** | +3 | Real bootstrap-and-verify chain; the Only-Assignee condition honestly attested-not-verified |
| Persona — Stack-undecided | 5 | **9** | +4 | The ⭐ step now hands a real matrix + full-stack guidance; default is loud, not silent |
| Persona — Eng leader | 7 | **9** | +2 | Credible exec brief + non-fabricated ROI + fleet rollout; residual is citation polish |
| Persona — SDLC personas | 6 | **9** | +3 | QA/Designer now have dedicated, auditable sign-offs; the §2 table is honestly dedicated-vs-shared |
| **Industry best-practice fidelity** | 7 | **9** | +2 | SLSA L2 declared · SSDF mapped · reference SHA-pinned · a11y/load/eval honestly demoted to conditional gates |
| **Portability & economics** | 6 | **8** | +2 | Both mono-couplings broken (sourceable guard core + dual-platform CI); per-feature token floor ~470 tok |

**Persona average ≈ 8.5** (was 5.5). **Overall average ≈ 8.4** (was 5.8). The original headline — *"the spread (4→7) is the headline; the kit serves the experienced GitHub team far better than the beginner/brownfield/undecided"* — is closed: the previously-worst personas (Beginner 4→7, Brownfield 6→9, Stack-undecided 5→9) moved the most.

---

## Convergent findings — resolution

| # | Original convergent finding (≥2 agents) | Slice | Status @ v2.38.0 |
|---|------------------------------------------|-------|------------------|
| 1 | **"Green ≠ verified"** — gates went green on documentation; `branch-protection.sh` silently no-ops off-GitHub | 9a | **RESOLVED.** `verify.sh` labels every check `[control]` vs `[doc]` + honesty footer; `branch-protection.sh`/`tracker-contract.sh`/`dr-ready.sh` are three-state (UNVERIFIED = exit 2, "NOT a pass", escalates to FAIL in CI). |
| 2 | **Runtime guard has holes + ports to one runtime** | 9b · 9d-b | **PARTIAL — by honest design.** Deny-matrix hardened (find-delete/truncate/shred/single-file-rm now denied, live-verified) and extracted to a runtime-agnostic `guard-core.sh` consumed by the Claude adapter, `kit-guard` CLI, and a universal `pre-push`. **Residual (HIGH, disclosed):** interpreter-exfil (`python -c`/`node -e`) and non-Bash MCP tools remain ungated — now explicitly reframed as **platform-owned** (`platform-safety-boundary.md`), with the guard self-labeled "a speed bump, not a boundary." The false-assurance is gone; the boundary is real and stated. |
| 3 | **GitHub/`gh` coupling** | 9d | **RESOLVED.** Gate-ids not vendor; GitLab reference + `incept --ci github\|gitlab`; the two genuinely `gh`-API scripts return UNVERIFIED/unavailable off-GitHub, never a false pass. |
| 4 | **No "already failing the gates" story** | 9c | **RESOLVED.** `WAIVER-REGISTER.md` + `waivers-valid.sh` (governed, ≤90d, secret-scan/branch-protection non-waivable across 23 evasion attempts) + `coverage-ratchet.sh` no-regression-below-baseline. |
| 5 | **Persona table over-promises symmetry** | 9i · 9i-b | **RESOLVED.** TEST-PLAN + UAT-SIGNOFF + A11Y-SIGNOFF structured records; §2 table honestly annotated dedicated-vs-shared (Designer correctly downgraded to advisory-with-a-dedicated-artifact); `persona-artifacts.sh` drift-guard; DoR promoted to a first-class entry gate. |

**4 of 5 fully resolved; #2 resolved to the kit's honest boundary.** The deepest original concern — *false assurance contradicting the kit's own anti-false-assurance value* — is closed across the board.

---

## The headline judgment

Original headline under test: *"drop into a regulated, privacy-sensitive enterprise with relative assurance that agents cannot cause damage."*

- **Where the kit can enforce in-process, it now does** — and where it can't (a deny-list over a Turing-complete shell; tools outside the Bash matcher; PII egress), it **says so plainly** and names the platform controls (default-deny network egress, separate prod credentials, sandboxed FS, MCP allowlisting) as the adopter's responsibility.
- So the honest answer the SWOT lens gives: **assurance is now conditional and disclosed**, not claimed-and-hollow. A regulated adopter gets relative assurance *given they deploy the named platform boundary* — and the kit tells them exactly that, with the evidence chain (A4) surviving an auditor's probe.

That is the arc's actual goal — **honest assurance** — achieved. The kit is no longer overselling; it is a foundation an enterprise can adopt and harden, with the boundary drawn in ink.

---

## Residuals surfaced by A7 (candidate follow-ups — none block arc closure)

| Residual | Lens | Sev | Note |
|----------|------|-----|------|
| Interpreter-exfil + non-Bash MCP tools ungated | SWOT | HIGH | By design — platform-owned; the depth ceiling the kit honestly documents. The real next frontier if the kit ever ships a platform layer. |
| `gh` not in `preflight.sh`; first `gh` command still a silent wall at Inception step 3 | Beginner | Med | Cheap: add an optional `--github` preflight check for `gh` + auth. |
| Solo-track tells the owner to admin-merge, but the reference `BRANCH-PROTECTION.md` sets `enforce_admins: true` (blocks it) | Beginner | Med | Real beginner trap; the solo path should set `enforce_admins: false` (or a ruleset bypass) at solo scale. |
| Only-Assignee transition condition attested-not-verified | Jira | Med | Jira REST *can* introspect it (`/workflow/search?expand=transitions.rules`); an opt-in `--deep` would close it. |
| Brownfield guide asserts `settings.local.json` "is gitignored" but never tells the adopter to add the line to *their* `.gitignore` | Brownfield | Low | One sentence in `brownfield.md` §2. |
| `git commit --amend` still blocked (reversible) | SWOT | Low | Minor over-block; documented dev friction. |
| Conditional gates (a11y/load/eval) enforced at doc-presence, not CI-execution, when they apply | Best-practice | Low | The honest edge of a portable kit; the universal 7 are mechanically gated. |

These are a coherent **"Slice 10" candidate backlog** — small, mostly cheap, none undercutting the arc's close.

---

## Arc closure

The Slice 9 "Honest Assurance & Adoption Reach" arc — 14 build slices/fast-follows (9a · 9b · 9c · 9d · 9d-b · 9e · 9f · 9g · 9h · 9i · 9i-b · 9j · 9k · 9k-b) + analyses (A1/A2/A5/A6 informing, **A4** auditor sim, **A7** this re-review) — is **closed**. Every convergent finding addressed; persona scores lifted +3 on average; the evidence chain survives an auditor probe; and the kit's central value — *intellectual honesty about its own boundaries* — is stronger than when the arc began, not weaker.

*Re-review run as a 9-lens parallel panel; each lens's full file-cited finding retained in the orchestrator transcript.*
