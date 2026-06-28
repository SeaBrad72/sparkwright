# Skill-spine brick #9 — the kit's own `evals` skill (Phase 2, AI-native)

**Date:** 2026-06-28
**Epic / slice:** E3 → **skill-spine brick #9** (the kit's own eval-driven-development skill). Second brick of **Skill-Spine Phase 2** (debugging → **evals** → discovery → E10). Toward [[self-hosting-commitment]] / E10.
**Status:** Design converged — **designed by dogfooding `skills/design/SKILL.md`** (9th self-host use), owner-ratified 2026-06-28 (dual-seat Engineer + Security-reviewer, both asserted; live-provider policy as-is). Ready for the implementation plan (dogfoods `skills/plan/SKILL.md`).
**Tracked here** because the skill spine + the E10 self-host test depend on the convention, and it must be resumable cold.

**Reads-first for a cold resume:** [[reprioritized-backlog]] (the Phase-2 plan + the keystone-structural-check that protects this slice), brick #8's design (`docs/architecture/2026-06-28-debugging-skill-design.md`, the convention this mirrors), the shipped spine (`skills/*/SKILL.md`), the eval infra this skill ties together (`templates/EVAL-PLAN-TEMPLATE.md`, `conformance/eval-ready.sh`, `templates/AI-SYSTEM-CARD-TEMPLATE.md`, DEVELOPMENT-STANDARDS §AI Evaluations), the shared verifier (`conformance/orchestrator-loop-wired.sh`), and the seats this wires (`agents/engineer.agent.md`, `agents/security.agent.md`).

## 0. Why this slice (the decision trail)

The comprehensiveness assessment (2026-06-28) found the kit has the eval *infrastructure* (EVAL-PLAN template, `conformance/eval-ready.sh`, the §7 Eval gate, AI-SYSTEM-CARD, standards on prompt-injection/output-validation/judge-pinning) but **no craft SKILL** — the *how* of eval-driven development. `evals` is to that infra what `tdd` is to the test runner: the discipline that produces and grows the eval suite. It is the direct answer to "is AI dev covered under the Engineer?" — the SEAT was; the DISCIPLINE was not (the Engineer built AI features with `tdd`, the wrong gate for an LLM feature).

### It is a KIT-ORIGINAL, not a superpowers replacement
Bricks #1–8 each replaced a superpowers skill. **Superpowers has no evals skill** — so #9 *adds* the AI-native craft superpowers lacks. The `skill-spine` claim wording must reflect this: "#1–8 replace superpowers (content + discovery); + `evals`, the kit's own AI-native eval-driven-dev craft." Do NOT say "replaces superpowers" for `evals`.

### Wiring (owner-ratified 2026-06-28): DUAL-SEAT, both asserted — Engineer + Security-reviewer
Evals have two genuinely distinct dimensions: a **build** dimension (eval-driven dev — the Engineer's craft, the AI sibling of `tdd`) and a **safety/red-team** dimension (adversarial prompts, jailbreaks, harmful-output, judge-independence — the §7 *security* gate for AI features, which the kit's standards explicitly route to the security lens). So:
- **Engineer** references it for eval-driven build.
- **Security-reviewer** references it for the red-team/safety lens.
Both are **asserted** by the verifier (unlike `review`, where the security-reviewer reference was ungated consistency) — because the AI red-team is a genuinely load-bearing gate, not a consistency echo. This mirrors `verification` (Engineer + Orchestrator, both asserted) and costs one extra reference-teeth case.

### Intent (unchanged): zero superpowers dependency at the FLOOR; acceptance = E10.

## 1. What this slice is
Author the kit's **ninth own skill — `evals`**: the craft of eval-driven development (evals are the test suite for any model/prompt-dependent behavior), invoked by the Engineer (build) and the Security-reviewer (red-team/safety). **FLOOR-only** (invoke-by-read). It POINTS AT the existing eval infra; it does not duplicate it.

## 2. The skill's content — the craft (where the kit's value is)

`skills/evals/SKILL.md` encodes the eval-driven-dev craft and chains to the kit's own infra + spine:

- **Evals are the test suite for AI.** Any behavior depending on a model or prompt is held to the same bar as code — a prompt is production logic. Eval-driven dev is the AI sibling of `skills/tdd/SKILL.md`.
- **★ Probabilistic red→green (the distinctive framing vs tdd).** Write the eval (dataset + rubric/judge) FIRST; watch the *unbuilt* feature **miss the `threshold`**; build the prompt/feature until it meets the bar. "Green" = a threshold (score ≥ bar; no metric drops > N pts vs baseline), **not** 0 failures. Non-vacuity analog: an eval the unbuilt feature already passes proves nothing (a never-red test) — calibrate evals to discriminate.
- **Pin the `judge` + judge-independence.** No self-grading (the judge model is independent of the system under test); pin the SUT model+version and the judge model+version, so a score is reproducible and a regression is real.
- **`red-team` / safety (the security dimension).** Adversarial prompts, jailbreaks, harmful-output checks before shipping; AI incidents (harmful output, jailbreak, bias) feed back into the eval red-team set.
- **Runtime guards complement evals.** Prompt-injection defense (never let user input override system instructions; treat tool output as untrusted) + output-schema validation before acting — dev-time evals AND runtime guards, not either/or.
- **Versioned + grows.** The eval set is versioned with the code and grows from production misses + retros; a declining eval score is tech debt surfaced at retro.
- **Policy: author + wire, do not run the live provider.** The agent authors and wires the evals; running the live model is a human/CI step (the guard blocks reading a live key into context as a speed bump; see `docs/operations/secrets-for-ai.md`).
- **Chains to the kit's own artifacts:** plan the evals with `templates/EVAL-PLAN-TEMPLATE.md`; readiness `conformance/eval-ready.sh`; the §7 Eval gate enforces the threshold in CI; risk/classification via `templates/AI-SYSTEM-CARD-TEMPLATE.md`; prove a result with `skills/verification/SKILL.md` (evidence before claiming the eval passed).

This is a kit-original craft that makes the existing eval infra *usable as a discipline* — the AI-native completion of the build loop.

## 3. Wiring (DUAL-SEAT — Engineer + Security-reviewer, both asserted)
- **Engineer def (FLOOR + native):** for any model/prompt-dependent behavior, follow the kit's own `skills/evals/SKILL.md` (eval-driven dev: evals are the test suite; write the eval, watch it miss the bar, build to threshold). Edit `agents/engineer.agent.md` + `.claude/agents/engineer.md`, alongside the tdd/debugging/verification chain.
- **Security-reviewer def:** for AI features, apply the eval red-team/safety/judge-independence lens via `skills/evals/SKILL.md` (the §7 security gate for AI). Edit `agents/security.agent.md` (FLOOR) + `.claude/agents/security-reviewer.md` (native).
- **Guard:** none — `skills/*` already control-plane; `skills/evals/SKILL.md` is agent-immutable for free (confirm-don't-add).

## 4. Conformance (right-weighted — no new gate, no new claim row)
- **Extend the `skill-spine` claim** text → "… + the kit's own `evals` skill (`skills/evals/SKILL.md`), the AI-native eval-driven-dev craft, referenced by the engineer (eval-driven build) and the security-reviewer (red-team/safety lens) … bricks #1–8 replace superpowers; `evals` adds the AI-native craft superpowers lacks …".
- **Extend `conformance/orchestrator-loop-wired.sh`:** add a `SECURITY_DEF` path var + `check_evals_skill "$EVALS_SKILL_FILE" "$ENGINEER_DEF" "$SECURITY_DEF"` asserting the skill exists + ASCII markers + **both** the Engineer and Security defs reference it. Candidate markers (locked at plan time, `grep -qF`, ASCII): `name: evals`, `eval-driven`, `judge`, `red-team`, `threshold`.
- **Non-vacuity — 3 new cases (dual-seat):** case 21 (marker teeth: drop `red-team` → exit 1), case 22 (Engineer omits the reference → exit 1), case 23 (Security def omits the reference → exit 1). Cases 1–20 fixtures gain a conformant evals skill + both refs + a new `security.agent.md` fixture def.
- **Keystone (the structural check now forces this):** add the `evals` index row to `skills/using-skills/SKILL.md`, and **fold in panel-#16 Low-1** — replace the count-coupled prose ("all seven / seven spine skills" at lines ~3/8/29/42/65) with **count-neutral** wording ("every spine skill on disk"). `check_keystone` (structural since v3.65.0) requires the `skills/evals` index row.
- **Extend `docs/operations/orchestration.md`** — the Engineer + Security-reviewer follow `skills/evals/SKILL.md` for eval-driven dev / AI red-team.

## 5. Honest ceiling & scope (named, not built)
- **Provided + structurally-proven; quality un-gateable** — correct for a skill. The check proves the skill exists, is kit-distinctive, and both seats reference it; it cannot prove an agent actually does eval-driven dev. The real enforcement of the eval *threshold* is the §7 Eval gate (CI), which this skill points at — not the skill text.
- **Points at, doesn't duplicate, the eval infra** — EVAL-PLAN / eval-ready.sh / §7 gate / AI-SYSTEM-CARD remain the artifacts; the skill is the craft that uses them.
- **Live provider out of scope by policy** — the agent authors+wires; running the live model is human/CI.
- **Kit-original** — no superpowers equivalent; the claim says so.
- **Phase-2 position** — brick #2 of 3 (debugging ✅ → evals → discovery), then E10. Heavy live-eval-harness/red-team infra is the future E6 epic; this is the cheap FLOOR craft brick, separate from the epic.

## 6. Build approach
Control-plane slice (new `skills/evals/SKILL.md`; engineer defs ×2 + security defs ×2; `conformance/orchestrator-loop-wired.sh` [+ `SECURITY_DEF`, `check_evals_skill`, cases 21–23, fixtures gain security def + evals refs] + `conformance/claims.tsv` + `docs/operations/orchestration.md`; keystone `skills/using-skills/SKILL.md` [evals row + Low-1 count-neutral prose]; version finishing **3.65.0 → 3.66.0**) → **AMBER `apply.py`**, clone dry-run incl. shellcheck + `verify --require` + the case 21/22/23 flips + confirm the structural `check_keystone` passes with the evals row → **dual review** (reviewer: is the skill genuinely the kit's eval-driven-dev craft + the conformance non-vacuous incl. cases 22/23 + the keystone count-neutral; security: the red-team-lens wiring + that the live-provider policy is stated + `skills/` immutability) → **light 5-lens meta-control panel #17** (A5) → **fold the governance close INTO the feature PR**. Subagent-driven build; the human applies/merges/release-tags — **`git show --stat HEAD` confirms the keystone + security defs are in the commit; admin-merge only when `conformance` is GREEN** (the brick-#8 incident lessons).

## 7. Convergence record (owner-ratified 2026-06-28)
Designed by dogfooding `skills/design/SKILL.md` (9th self-host use). `evals` = the kit's own AI-native eval-driven-dev craft (a kit-original, no superpowers equivalent), dual-seat Engineer (build) + Security-reviewer (red-team/safety), both asserted (mirrors `verification`). Distinctive framing: probabilistic red→green (threshold, not 0-failures) + pinned independent judge + red-team + author-don't-run-the-live-provider; points at the kit's existing eval infra (EVAL-PLAN / §7 gate / AI-SYSTEM-CARD) rather than duplicating it. Folds in panel-#16 Low-1 (count-neutral keystone prose) since this is the 8th content skill the structural `check_keystone` now requires indexed. Right-weighted conformance (extend the shared verifier + the one `skill-spine` claim; +case 21 marker + cases 22/23 dual reference-teeth). FLOOR-only. **Next: the implementation plan, dogfooding `skills/plan/SKILL.md`; then brick #10 `discovery`.**
