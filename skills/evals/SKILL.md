---
name: evals
description: Use when building or changing ANY model/prompt-dependent behavior — BEFORE writing the prompt or feature. The kit's own eval-driven-development skill (a kit-original; superpowers has no evals skill). Evals are the test suite for AI — the AI-native sibling of skills/tdd/SKILL.md: write the eval first, watch the unbuilt feature miss the threshold, build to the bar. Pin an independent judge, red-team for safety, and grow the set from production misses.
---

# Evals — eval-driven development, the AI sibling of tdd

The kit's own `eval-driven` development skill: the craft of holding any model- or prompt-dependent behavior to a measured bar the same way `skills/tdd/SKILL.md` holds code to a failing test. A prompt is production logic; an eval is its test. This is a **kit-original** — superpowers has no evals skill — so it *adds* the AI-native discipline the rest of the spine lacks; it does not replace anything. It POINTS AT the kit's existing eval infrastructure (the EVAL-PLAN template, `conformance/eval-ready.sh`, the §7 Eval gate, the AI System Card); it does not duplicate it.

<!-- The frontmatter and the discipline phrases below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: evals, eval-driven, judge, red-team, threshold).
     Edits that drop or rename them can turn the skill-spine lock RED. -->

## When to use
BEFORE building or changing **any behavior that depends on a model or a prompt** — a new AI feature, a prompt edit, a model/version swap, a RAG or tool-use change, a classifier, an agent loop. If the output is probabilistic, `tdd` is the wrong gate (a single assertion cannot pin a distribution); the eval is the right one. Write the eval first, the same way you write the failing test first. Exceptions (ask the owner): pure deterministic glue around a model that has its own evals upstream.

## Evals are the test suite for AI (the `eval-driven` law)
Any behavior that depends on a model or a prompt is held to the same bar as code. The eval set — a dataset of inputs + a rubric or judge + a scored `threshold` — IS the test suite. Eval-driven development is the AI-native sibling of `skills/tdd/SKILL.md`: the failing-test-first cycle, made probabilistic.

## Probabilistic red -> green (the distinctive framing vs tdd)
1. **RED — write the eval first.** Build the dataset (representative + adversarial inputs) and the rubric/`judge` BEFORE the prompt or feature exists. State the `threshold` (the pass bar) up front.
2. **Verify RED — watch the UNBUILT feature MISS the bar.** Run it against the absent/naive implementation and confirm it scores **below the `threshold`**. This is the non-vacuity law of `tdd` made probabilistic: **an eval the unbuilt feature already passes proves nothing** (a never-red test). Calibrate the dataset/rubric until it *discriminates* — good answers score high, bad answers score low.
3. **GREEN — build the prompt/feature to the bar.** Iterate the prompt/system until the score meets the `threshold`.
4. **"Green" is a `threshold`, NOT 0 failures.** Unlike a unit test, green means **score ≥ bar** and **no tracked metric drops > N pts vs the pinned baseline** — never "every case passed". A probabilistic system has a failure rate by nature; the bar governs it.
5. **REFACTOR — tighten the bar as the feature matures**; raise the `threshold` and add cases, never lower it silently.

## Pin the `judge` + judge-independence
- **Pin the system under test.** Record the SUT model + version; an unpinned model means a "regression" might just be a silent provider update.
- **Pin the `judge`.** Record the judge model + version + rubric so a score is reproducible.
- **Judge-independence — no self-grading.** The `judge` model is independent of the system under test (a model grading its own output is not a measurement). For subjective rubrics, anchor the judge with few-shot exemplars and spot-check against human labels.

## `red-team` / safety (the security dimension — the §7 security gate for AI)
- Maintain an adversarial `red-team` set: jailbreaks, prompt-injection payloads, harmful-output probes, bias/leakage cases. Run it BEFORE shipping, not after.
- **AI incidents feed the `red-team` set.** Every harmful output, jailbreak, or safety miss in production becomes a permanent `red-team` case so the same failure cannot recur silently — the regression-test law of `tdd`, applied to safety.
- This is why the **Security-reviewer** also owns this skill: the AI red-team is a load-bearing §7 security gate, not a build-time nicety.

## Runtime guards COMPLEMENT evals (not either/or)
Dev-time evals do not remove the need for runtime defenses. Ship BOTH:
- **Prompt-injection defense** — never let user/tool input override system instructions; treat tool output as untrusted data, not commands.
- **Output-schema validation** — validate the model's output against a schema (and re-check authz/limits) before acting on it.
Evals measure the behavior offline; the runtime guards contain it online.

## Versioned + grows from production misses
The eval set is versioned WITH the code (a prompt change ships with its eval delta) and grows from production misses + retros. A declining eval score is tech debt surfaced at retro, not a number to quietly re-baseline. New failure modes become new cases.

## Policy: author + wire the evals; do NOT run the live provider
The agent **authors and wires** the evals (dataset, rubric, `threshold`, CI hook); **running the live model is a human/CI step.** The guard treats reading a live provider key into context as a speed-bump (see `docs/operations/secrets-for-ai.md`) — that is intentional. Do not exfiltrate keys or call paid endpoints to "just check"; hand the wired eval to CI / the human to execute, and prove the result with `skills/verification/SKILL.md` (evidence before claiming the eval passed).

## Chain to the kit's own eval infra + spine
- **Plan the evals** with `templates/EVAL-PLAN-TEMPLATE.md` (dataset, rubric, judge, `threshold`, baseline).
- **Readiness** — `conformance/eval-ready.sh` checks the eval scaffolding is present.
- **The §7 Eval gate** enforces the `threshold` in CI (the real enforcement of "green"; this skill is the craft, the gate is the teeth).
- **Risk / classification** — `templates/AI-SYSTEM-CARD-TEMPLATE.md` records the SUT, judge, and risk tier.
- **Sibling skills** — `skills/tdd/SKILL.md` (the deterministic sibling — code gets the failing test, AI gets the eval) and `skills/verification/SKILL.md` (prove the eval result is real before claiming it).

## Rationalizations to refuse
| Rationalization | Why it fails |
|---|---|
| "It's just a prompt tweak, no eval needed." | A prompt is production logic; an unevalled prompt change is an untested code change. Write the eval. |
| "I'll add evals after it works." | Evals-after pass immediately and prove nothing — you never watched the unbuilt feature MISS the `threshold`. |
| "It passed every case, ship it." | Green is a `threshold`, not 0 failures — and if every case passes the eval may be too easy to discriminate. |
| "The model can grade its own output." | Self-grading is not a measurement — pin an independent `judge`. |
| "We'll red-team later if there's a complaint." | The `red-team` set runs BEFORE shipping; an incident is a new permanent case, not the first test. |
| "Evals cover it; we can skip the runtime guard." | Evals are dev-time; prompt-injection defense + output-schema validation are runtime — ship both. |
| "Let me read the API key and run it to check." | Author + wire only; running the live provider is a human/CI step (the key speed-bump is deliberate). |

## Red flags (stop — you are about to skip eval-driven dev)
- Editing a prompt / swapping a model with no eval delta.
- An eval the unbuilt/naive feature already passes (a never-red eval — calibrate it to discriminate).
- A `judge` that is the same model (or family) as the system under test.
- "Green" reported as "all cases passed" instead of a `threshold` vs a pinned baseline.
- Shipping an AI feature with no `red-team` set, or with no runtime prompt-injection / output-schema guard.
- Reaching for a live provider key to run the eval yourself instead of handing it to CI / the human.

## Terminal state
The behavior has a versioned eval set written FIRST (it was watched missing the `threshold` before the feature existed), an independent pinned `judge`, a `red-team` safety set, and runtime guards; "green" is the `threshold` enforced by the §7 Eval gate in CI, not a 0-failure claim; the result was proven via `skills/verification/SKILL.md`, and every production miss becomes a new case. Never ship a model/prompt change without an eval that could fail.
