# A4 — Third-Party Auditor Simulation (Evidence-Chain Stress Test)

**Date:** 2026-06-10
**Scope:** `agentic-sdlc-kit` @ v2.38.0 — SOC 2 + ISO 27001:2022 + NIST SSDF (SP 800-218) / SLSA evidence-chain probe.
**Auditor stance:** Skeptical, independent third party. Goal: break the evidence chain — find where the kit *claims* a control but the demanded evidence is weak, missing, mislabeled, or unverifiable. Honestly-disclosed boundaries are a strength, not a finding, *unless* the disclosure is buried or contradicted elsewhere.
**Method:** Read every evidence surface; ran the conformance battery (`verify.sh`, `ci-gates.sh`, `container-supply-chain.sh`, `branch-protection.sh`, `waivers-valid.sh --selftest`, `action-pinning.sh`, `agent-autonomy.sh`, `guard-wired.sh`, `tracker-contract.sh`). All runs reproduced below.

---

## Executive verdict

**This kit survives an auditor's evidence-chain probe.** It would wobble in three narrow places, none of which is a misrepresentation of a security control — they are *consistency / dogfooding / carry-through* gaps in the assurance narrative, not false "Kit-enforced" claims.

The thing auditors most often catch — a green dashboard silently swallowing an UNVERIFIED, or "we enforce X" with no runnable proof — is **not present here**. The three-state model (PASS / FAIL / UNVERIFIED, exit 0/1/2) is real and tested; `verify.sh` escalates UNVERIFIED to FAIL under CI; the waiver allow-list rejects every spelling of the non-negotiable gates I threw at it (case, markdown, separator-swap, homoglyph, html-comment, dash-leading, GFM-separator); SLSA is claimed at **L2 and explicitly not L3**; the guard is consistently labelled a "speed bump, not a boundary" on **every** surface I checked (EXEC-BRIEF §5, platform-safety-boundary, enterprise README §29, PROCESS §13, README runtime note). The honesty is not marketing varnish — it holds under probing.

Where it wobbles:
1. The **kit's own** `.github/workflows/ci.yml` runs the *self-tests* of `branch-protection.sh` and `verify.sh`, not the live checks, and floats `actions/checkout@v4` (unpinned) while *enforcing* SHA-pinning on the adopter reference. Defensible (kit = template source) and partly disclosed, but it is a "do as I say, not as I do" surface.
2. **NIST SSDF is mapped in the crosswalk but does not carry through** to the two surfaces an auditor actually works from — the EXEC-BRIEF "compliance at a glance" table and the `audit-evidence-checklist.md`. The mapping exists; the evidence-gathering checklist an SSDF assessor would fill out has no SSDF practice IDs.
3. The **SBOM-vs-attested-digest gap** (PR-scanned image digest ≠ pushed/attested digest) is real but **honestly disclosed in-line** and the digest-binding *is* independently verified — this is an HONEST BOUNDARY, not a gap.

No Critical or High findings. Three Low, one Med (the SSDF carry-through, because a framework named on the cover page should appear on the evidence worksheet).

---

## Findings table

| # | Claim | Evidence an auditor demands | What I found | Verdict | Sev | Fix |
|---|-------|-----------------------------|--------------|---------|-----|-----|
| 1 | "SLSA Build L2 — provenance bound to artifact/image digest" (STANDARDS §14 L239; crosswalk L18) | A runnable check that the *image digest* is bound, not just a tag | `container-supply-chain.sh` requires a literal `subject-digest:` YAML key (L65); reference `ci.yml` L164-169 binds `subject-digest: ${{ steps.build-push.outputs.digest }}`. Ran clean against the real Dockerfile+ci.yml (`1 profile checked`). | **HONEST BOUNDARY** (verified, correctly scoped) | — | None — disclosed and verified |
| 2 | Reference CI proves SLSA L2 end-to-end | SBOM and provenance cover *identical bits* (same digest) | PR-time image build (scanned) and push-only `image-provenance` build are **independent jobs**, so the scanned digest is not guaranteed identical to the attested digest. | **HONEST BOUNDARY** — disclosed verbatim in `ci.yml` L84-90 ("the scanned digest is not guaranteed identical to the attested digest… least-privilege forbids the PR job from pushing") with the production remediation spelled out | — | None — the disclosure is in the file, not buried |
| 3 | Every **Kit-enforced** crosswalk row has automatic mechanical evidence | For each Kit-enforced row, a runnable check producing the named artifact | All 9 Kit-enforced rows map to a real check: gates 1–7 → `ci-gates.sh` (green); OIDC least-priv → reviewable two-job split in `ci.yml`; branch-protection → `branch-protection.sh` (live PASS against this repo); agent guard → `agent-autonomy.sh` + `guard-wired.sh` (green). No row overclaims. | **SOLID** (no finding) | — | None |
| 4 | UNVERIFIED is never silently a pass | A green aggregate cannot hide an UNVERIFIED | `verify.sh` L38-40, 66: exit-2 → UNVERIFIED, escalates to FAIL under CI/`--require`; honesty footer printed ("UNVERIFIED is NOT a pass"). `branch-protection.sh` three-state confirmed via selftest. `tracker-contract.sh` exit-2 asserted in kit CI (L68-69). | **SOLID** | — | None |
| 5 | Kit dogfoods its own governance (kit `.github/workflows/ci.yml`) | The kit's pipeline runs the same *live* controls it ships | Kit CI runs `branch-protection.sh **--selftest**` (L95) and `verify.sh **--selftest**` (L97) — the verifier *logic*, not the live aggregate / live remote check. Live branch-protection passes only because I ran it by hand. | **REAL GAP** (minor; defensible: kit = template source, live checks belong in the adopter pipeline) | Low | Add a non-blocking kit-CI step that runs live `branch-protection.sh` (it has `gh`) and `verify.sh` (not `--selftest`) so the kit visibly eats its own dog food; OR add a one-line note in `conformance/README.md` that kit-CI intentionally runs selftests because the live checks are the adopter's. |
| 6 | "pin every `uses:` to a full commit SHA" (STANDARDS §14 L228; enforced by `action-pinning.sh`) | The kit's *own* workflows are SHA-pinned | `action-pinning.sh` only targets `profiles/typescript-node/ci.yml` (L9, comment L4 scopes the contract to the *reference*). The kit's own `.github/workflows/ci.yml` floats `actions/checkout@v4` (L19, 106, 117) — unpinned. | **REAL GAP** (partially disclosed: the script comment discloses the scope, but no surface says the kit's own CI is intentionally unpinned) | Low | Either SHA-pin `actions/checkout` in the kit's own three jobs, or add `action-pinning.sh .github/workflows/ci.yml` as a second (non-blocking) invocation with a documented exception. A SHA-pinning *advocate* whose own checkout floats is the first thing a supply-chain auditor flags. |
| 7 | "Frameworks covered: NIST SSDF (SP 800-218 v1.1)" (crosswalk L7) | An SSDF assessor follows the **evidence checklist**, not just the crosswalk, and expects SSDF practice IDs there | SSDF practice IDs (PW/PS/PO/RV) appear **only** in `compliance-crosswalk.md`. The `audit-evidence-checklist.md` (the surface the addendum's README sends an auditor to, and where evidence is actually gathered) carries SOC 2 + ISO refs but **no SSDF column**. The EXEC-BRIEF "compliance at a glance" table (§6) lists SOC 2 + ISO only — **no SSDF row**. | **REAL GAP** — SSDF is named on the cover but doesn't reach the worksheet | Med | Add an SSDF column (or "SSDF ref" cell) to `audit-evidence-checklist.md` rows that have SSDF mappings, and add an SSDF row to the EXEC-BRIEF §6 table. The mappings already exist in the crosswalk — this is carry-through, ~1 column. |
| 8 | secret-scan + branch-protection are non-negotiable, never waivable | A waiver cannot smuggle a non-negotiable gate through `waivers-valid.sh` | Default-deny allow-list (`WAIVABLE`, L21) + explicit `NONNEGOTIABLE` reject (L90-94). Selftest FAILs every spelling: `secret-scan`, `SECRET-SCAN`, `**secret-scan**`, `secret_scan`, homoglyph `ѕecret-scan`, `coverage<!--x-->secret-scan`, `-secret-scan`, GFM-separator-hidden, `branch-protection`, unknown gate, missing-pipe row, data-above-separator. All caught. | **SOLID** (genuinely hard to break) | — | None |
| 9 | Guard is a "speed bump, not a security boundary" | The honesty is stated *everywhere* the guard is referenced — no marketing surface implies it IS the boundary | Consistent on every surface checked: EXEC-BRIEF §5 (L31), platform-safety-boundary L3/L7/L29, enterprise README §29 (L29), PROCESS §13 (L379), README runtime note (L40). The red-team's ~16%-caught figure is cited *in the doc* (platform-safety-boundary L9), not hidden. | **SOLID / HONEST BOUNDARY** | — | None |
| 10 | Human-coverage / Org-owned boundary disclosed wherever assurance is claimed | A reader cannot over-trust the guard for humans-at-a-shell or other runtimes | Disclosed in enterprise README §29, platform-safety-boundary "Human and other-runtime coverage" (L27-29), EXEC-BRIEF §5. The cross-runtime reuse (pre-push hook, `kit-guard` CLI) is explicitly called "widen the speed bump — not a boundary." | **SOLID / HONEST BOUNDARY** | — | None |
| 11 | tracker-contract "Only-Assignee" condition & SLSA L3 are attested-not-verified | These honest scopings don't leak into a stronger claim elsewhere | `tracker-contract.sh` prints "ATTESTED (not auto-verified)" (L43); README index L52 repeats "the Only-Assignee claim is attested." SLSA L3 explicitly **not** claimed (STANDARDS §14 L239). No stronger claim found downstream. | **HONEST BOUNDARY** | — | None |

---

## Detail on the Med finding (#7 — SSDF carry-through)

The crosswalk's `## Security & engineering controls` table has a fully-populated `NIST SSDF (800-218)` column with defensible practice mappings (e.g. SBOM/provenance → `PS.2, PS.3 (SLSA Build L2)`; dep-scan → `PW.4, RV.1`; secret-scan → `PW.8, PS.1`; guard → `PO.5, PS.1`). That part is good work.

The problem is the *evidence chain* an SSDF assessor walks:
- `docs/enterprise/README.md` L16 routes the auditor to `audit-evidence-checklist.md` as the "per-control evidence checklist for an audit."
- That checklist's `Crosswalk ref` column carries **SOC 2 + ISO only** (e.g. `CC8.1 / A.8.28–29`). No SSDF IDs.
- The EXEC-BRIEF §6 "Compliance at a glance" table — the leadership/auditor front door — lists **SOC 2** and **ISO 27001:2022** rows. **No SSDF row**, despite SSDF being named as a covered framework one click away.

So an SSDF (SP 800-218) assessor who is handed the EXEC-BRIEF and the evidence checklist sees no SSDF anywhere; only if they open the crosswalk specifically do the practice IDs appear. A framework named on the cover ("Frameworks covered: … NIST SSDF") that is absent from the evidence worksheet is a carry-through gap. It is **not** an overclaim of a control — every mapped practice has the same underlying mechanical evidence as its SOC 2/ISO siblings — but it weakens the *navigability* of the evidence chain an auditor would actually follow. Low blast radius, easy fix (one column + one table row), rated Med only because it touches the named-framework promise.

---

## What's genuinely solid (credit where the chain holds)

- **Three-state honesty is real and load-bearing.** PASS/FAIL/UNVERIFIED with exit 0/1/2, escalation to FAIL under CI/`--require`, and an aggregate (`verify.sh`) that prints a footer telling you exactly what green does and does not prove. The kit CI even asserts `tracker-contract.sh` returns exit-2 (`.github/workflows/ci.yml` L68-69) — it tests its own honesty.
- **Digest-bound provenance is verified, not asserted.** `container-supply-chain.sh` demands a literal `subject-digest:` key and the reference pipeline supplies it; the residual PR-vs-push digest gap is disclosed verbatim with a remediation path. This is exactly how an honest SLSA L2 claim should read.
- **The waiver allow-list is adversarially hardened.** Default-deny, ASCII-only gate tokens, markdown/comment normalization that fails-closed, malformed-row detection, and a 19-case selftest that includes homoglyph and table-smuggling attacks on the non-negotiable gates. I could not find a spelling of `secret-scan` or `branch-protection` that slips through.
- **The guard is honestly demoted everywhere.** "Speed bump, not a boundary" is stated on all five surfaces I checked, the four real Org-owned platform controls are named consistently, the red-team's catch-rate is cited *in* the doc, and the human/other-runtime coverage limit is disclosed wherever assurance is claimed. No surface oversells it.
- **Kit-enforced means Kit-enforced.** Every crosswalk row marked Kit-enforced has a runnable check that produces the named evidence; none should be demoted to Kit-assisted. The honest "Kit-assisted / Org-owned" labels are used correctly and generously (the kit under-claims, if anything, on audit-logging and secrets).
- **SLSA L3 is explicitly disclaimed**, the OIDC least-privilege two-job split is real and reviewable, and the canonical reference pipeline SHA-pins every action it ships (`action-pinning.sh` green).

---

## Reproduction log (key runs)

```
$ sh conformance/verify.sh
  [control] agent-autonomy PASS · ci-gates PASS · guard-wired PASS · check-links PASS
  [control] backlog-adapters PASS · branch-protect PASS
  [doc] deployable-ready PASS · dr-ready PASS · resilience-ready PASS
  Summary: 6 control-checks · 3 doc-checks · 0 unverified · 0 failed → RESULT: OK

$ sh conformance/ci-gates.sh profiles/typescript-node/ci.yml          → OK (8 gate ids)
$ sh conformance/ci-gates.sh profiles/typescript-node/ci.gitlab-ci.yml → OK (platform portability)
$ sh conformance/container-supply-chain.sh                            → OK (1 profile w/ Dockerfile: multi-stage, non-root, image SBOM + digest provenance)
$ sh conformance/branch-protection.sh                                 → OK: main on SeaBrad72/agentic-sdlc-kit is protected (live)
$ CI=true sh conformance/branch-protection.sh                         → exit 0 (live PASS; would FAIL-escalate if unverifiable)
$ sh conformance/action-pinning.sh                                    → OK (reference fully SHA-pinned)
$ sh conformance/waivers-valid.sh --selftest                          → all non-negotiable spellings FAIL (19 cases)
$ sh conformance/agent-autonomy.sh / guard-wired.sh                   → guard denies destructive battery, wired as PreToolUse hook
```

---

## Recommended remediation priority

1. **(Med) SSDF carry-through** — add an SSDF cell to `audit-evidence-checklist.md` and an SSDF row to EXEC-BRIEF §6. Mappings already exist; pure carry-through.
2. **(Low) Kit dogfooding** — run live `branch-protection.sh` / non-selftest `verify.sh` in the kit's own CI, or document why kit-CI runs selftests.
3. **(Low) Self-pinning** — SHA-pin `actions/checkout` in the kit's own `.github/workflows/ci.yml`, or document the intentional exception.

None blocks an audit. All three are credibility polish on an evidence chain that is, by the standards of what auditors usually see, unusually honest and largely verifiable.
