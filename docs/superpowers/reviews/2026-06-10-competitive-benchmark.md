# Competitive Benchmark — agentic-SDLC / paved-road landscape

**Date:** 2026-06-10
**Purpose:** Position this kit against the adjacent offerings an enterprise would evaluate alongside it — to sharpen the differentiation story and the business case (the A5 follow-up flagged in the multi-agent review).
**Method:** Desk research across IDP/golden-path vendors and ADLC governance frameworks; claims are sourced below. Honest about where the kit is *not* the answer.

> **Bottom line:** The field is converging on the kit's operating model — agents take the first pass, humans own architecture and ratify the standards — but it arrives from two incomplete directions. IDPs/golden paths are bolting agent governance onto human-portal tooling; ADLC frameworks describe the model as methodology, not executable conformance. The kit is the rare offering that is **both agent-native and enforcement-native**, portable and vendor-neutral, and honest that green ≠ verified. It is a governance & assurance layer, not a platform.

---

## Landscape — convergence from two incomplete directions

The market is independently arriving at the same operating model this kit already encodes: **agents do the first pass; humans own architecture and ratify the governing standards.** Two camps are moving toward it, each missing the half the other has.

### (a) IDPs / golden paths — agent-aware, but retrofitting governance onto portal tooling

Internal developer platforms are adding agent entry points to tooling that was designed for humans clicking through a portal:

- **Backstage 1.43** ships experimental MCP token support and a `plugin-mcp-actions-backend` that exposes Scaffolder actions to agents such as Claude and Cursor ([Platform Engineering](https://platformengineering.com/features/backstage-1-43-when-internal-developer-platforms-start-acting-like-platforms/)).
- **Harness Knowledge Agent** and **Spacelift** are layering agent access onto their existing catalog/IaC surfaces.

The camp's own community states the core mismatch plainly: *"golden paths built for portal UIs, forms, and wizards don't translate to agent invocation"* ([Platform Engineering](https://platformengineering.com/features/backstage-1-43-when-internal-developer-platforms-start-acting-like-platforms/)). These platforms have catalogs, UIs, and token brokers — but their governance was built for a human at a keyboard, and agent invocation is being retrofitted onto it.

### (b) ADLC governance frameworks — right model, but norms not conformance

A parallel body of work describes the agentic development lifecycle as an operating model and a set of norms:

- Vendor frameworks — Cycode's *"Securing the ADLC,"* **EPAM**, **IBM** — define lifecycle stages and responsibilities.
- Analyst framing — **Forrester** declaring *"agentic software development takes the lead."*
- Recent academic work — translating *"governance norms into enforceable controls,"* and *"knowledge activation"* for agents.

The gap is consistent: this camp articulates the operating model as **methodology, norms, and PDF-grade guidance** — not as executable, CI-verified conformance an agent can actually run against.

---

## Differentiation — both agent-native and enforcement-native

The kit sits where the two camps haven't yet met. Three properties together are rare:

1. **Agent-native AND enforcement-native.** The contract → reference → conformance spine is CI-verified and agent-runnable. Not portal templates (camp a), not PDF norms (camp b) — executable checks a human or an agent runs the same way, on every push.
2. **Intellectual honesty as a feature.** The kit refuses false assurance: *"green ≠ verified,"* a three-state conformance model, and a guard positioned as a *speed-bump, not a boundary*. It tells adopters where its own controls stop — which is itself a differentiator against marketing-grade "secure by default" claims.
3. **Portable, vendor-neutral, no lock-in.** Stack-neutral by contract id, POSIX-clean, no proprietary runtime or catalog required. You adopt it *alongside* an IDP or CI system, not instead of one.

---

## Business case

Published field data — **not a kit measurement** — is the argument for guardrails-first adoption. The [Cortex 2026 Engineering Benchmark Report (reported by QASource)](https://www.qasource.com/blog/ai-generated-code-security-risks) found **incidents per pull request up 23.5% year-over-year** even as PR volume grew ~20%, with **change-failure rates rising comparably (~30%)** as AI adoption scaled on weak governance and catalog hygiene; empirical studies of failed agentic PRs corroborate the pattern ([arXiv 2601.15195](https://arxiv.org/abs/2601.15195)). The figures describe the *industry*, not this kit, and are presented as directional evidence — agents amplify whatever discipline (or lack of it) they are dropped into. The kit is the guardrails-first answer: the assurance layer that makes agent throughput safe to lean on rather than a multiplier of existing risk.

---

## Honest positioning — what the kit is NOT

The kit is **not a platform.** It has no UI, no service catalog, and no token broker. It does not replace Backstage, Harness, Spacelift, or your CI provider. It is the **governance & assurance layer** that sits on top of whatever platform a regulated, privacy-sensitive enterprise already runs — supplying the executable conformance and the honest assurance model the platform camp lacks and the framework camp only describes.

---

## Sources

**Business-case data (industry, not a kit measurement):**
- [AI-generated code security risks: why incidents per PR rose 23.5% (Cortex 2026 Engineering Benchmark Report, reported by QASource)](https://www.qasource.com/blog/ai-generated-code-security-risks)
- [Where do AI coding agents fail? An empirical study of failed agentic pull requests — arXiv 2601.15195](https://arxiv.org/abs/2601.15195)

**Landscape & frameworks:**
- [How agentic AI will reshape engineering workflows in 2026 — CIO](https://www.cio.com/article/4134741/how-agentic-ai-will-reshape-engineering-workflows-in-2026.html)
- [Agentic software development takes the lead — Forrester](https://www.forrester.com/blogs/agentic-software-development-takes-the-lead-from-code-assistants-to-orchestrated-sdlc-agents/)
- [Securing the ADLC — Cycode](https://cycode.com/blog/securing-adlc/)
- [The agentic development lifecycle explained — EPAM](https://www.epam.com/insights/ai/blogs/agentic-development-lifecycle-explained)
- [Agent development lifecycle (ADLC) — IBM](https://www.ibm.com/think/topics/agent-development-lifecycle-adlc)
- [Backstage 1.43: when internal developer platforms start acting like platforms — Platform Engineering](https://platformengineering.com/features/backstage-1-43-when-internal-developer-platforms-start-acting-like-platforms/)
- [A guide to the agentic software development lifecycle — CodeRabbit](https://www.coderabbit.ai/guides/agentic-sdlc)
- [From governance norms to enforceable controls: a layered translation method for runtime guardrails in agentic AI — arXiv 2604.05229](https://arxiv.org/abs/2604.05229)
- [Knowledge activation: AI skills as the institutional-knowledge primitive for agentic software development — arXiv 2603.14805](https://arxiv.org/abs/2603.14805)
