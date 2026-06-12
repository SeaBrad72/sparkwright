# Modern Practices — arc design (test-quality · pre-commit · agentic-ops)

**Status:** design. A small arc adding the modern fast/safe/agentic practices the v2.52.0 audit + the §7 review found genuinely absent (verified by grep, not assumed).
**Shape:** three slices. **MP-1 test quality** (mutation + property-based) and **MP-2 pre-commit fast-loop** are concrete (docs + profile tooling, established pattern). **MP-3 agentic-ops** (agent-run trace + agent-behavior evals) is kit-shaping → its own brainstorm, not built here.

## Problem (verified absent)
- **Mutation testing** — absent. Coverage % is gameable; an **agent can hit 80% with assertion-free tests**. Mutation score is the honest test-*quality* signal (the kit's "green ≠ verified" applied to the suite itself).
- **Property-based testing** — absent. Generative inputs find edge cases examples miss; strong for agent-written code.
- **Pre-commit fast-feedback** — absent. The kit has a *pre-push* guard but no *pre-commit* inner loop (format/lint/fast-test in seconds before CI).

Already covered (not gaps): context-engineering (AGENTS.md + TCC), multi-agent coordination (§12), spike track, dependency auto-update, chaos, agent/compute-spend governance, trunk-based + flags + canary + preview-envs + DORA.

## Governing principles
- **No friction:** mutation testing is **slow/expensive → recommended, not a universal CI gate** (like commit-signing). Run on critical paths / nightly, not every PR. Property-based + pre-commit are opt-in per profile.
- **Agentic relevance up front:** these matter *because agents write code/tests* — mutation catches gamed coverage; property-based catches agent edge-case blind spots; pre-commit tightens the agent's inner loop.
- **Honesty:** coverage measures execution, mutation score measures assertion strength — name the difference.
- **Established pattern:** stack-neutral guidance doc + per-profile concrete tools; no new fail-closed gate (no friction, no slow-gate).

---

## Slice MP-1 — Test quality (mutation + property-based) · v2.53.0
- **`docs/operations/test-quality.md`** (new) — coverage ≠ quality; mutation testing (score, critical-paths/nightly cadence, the agentic "gamed coverage" angle); property-based testing (generative, the agentic edge-case angle); per-stack tools; when-to-run (recommended, not gated due to cost).
- **`DEVELOPMENT-STANDARDS.md` §7** — a **Test quality** principle (coverage = execution not assertion strength; verify with mutation score on critical paths; broaden with property-based; esp. for AI-generated tests) + a **Property-based** row in the testing pyramid.
- **`profiles/python.md`** — mutation (`mutmut` / `cosmic-ray`) + property (`hypothesis`) in the testing tools.
- **`profiles/typescript-node.md`** — mutation (`Stryker`) + property (`fast-check`).
- **No new conformance script / CI step** (recommended practice, cost-sensitive). Release v2.53.0.

## Slice MP-2 — Pre-commit fast-feedback loop · v2.54.0
- **`docs/operations/dev-inner-loop.md`** (or fold into a profile) — the pre-commit pattern (format + lint + fast/affected tests in seconds), distinct from the pre-push guard (safety) and CI (full gate). Per-profile reference config (`pre-commit` / `lint-staged` + a fast test subset).
- **`DEVELOPMENT-PROCESS.md`** §Build / `DEVELOPMENT-STANDARDS.md` — a one-line inner-loop pointer.
- Profile reference configs. No new gate. Release v2.54.0.

## Slice MP-3 — Agentic-ops (BRAINSTORM, not built here)
- **Agent-run observability / trace** — tool-call sequence, decisions, retries, latency, token cost per task (OTel-GenAI / Langfuse-style). The kit governs agent *spend* (§2) but not the *execution trace*.
- **Agent-behavior / process-conformance evals** — eval the agent's SDLC adherence over time (writes tests, doesn't skip gates, mergeable PRs), the agentic analog of eval-driven development pointed at the agent.
- These need design decisions (artifact shape, tool-neutrality, what's gated vs observed) → a dedicated brainstorm after MP-1/MP-2.

## Governance
Each slice: feature branch → PR → human ratification (Bradley merges). STANDARDS/PROCESS edits → security-owner lens. Generic/anonymized ([[kit-anonymization]]). No new CI step in MP-1/MP-2 (no new conformance script).
