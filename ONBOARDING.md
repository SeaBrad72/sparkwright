# Onboarding — Start Where You Are

> New to the kit? This is the front door. It places you by **experience**, then hands you to
> `START-HERE.md` for your **role** and Inception. Two minutes here saves you hours later.

## The one idea that matters

**Coding is the task. Software engineering is everything that has to go *around* the code for an
enterprise** — tests, environments, security, governance, observability, release safety. Vibe
coding gets you working code; it does not get you software that an enterprise can trust, operate,
and not be harmed by. **This kit is that "everything around it."** The goal of this page: get you
*functional and not dangerous*, fast.

## Which lane are you in?

Pick the one that sounds like you. Non-punitive — feels too basic? Jump up a lane.

- **Novice / Coding-first** — *"I can make code work (often with AI), but tests, environments,
  security, and governance are new to me."* → **Learning lane** below.
- **Adjacent** — *"I've worked in or around software delivery (product, PM, BA) — I know these
  practices exist but haven't done them myself."* → **Learning lane** below (skim what you know).
- **Practitioner** — *"I've shipped enterprise software; route me to the contract."* →
  **straight to [START-HERE.md](START-HERE.md)** + the principles (`CLAUDE.md`). Skip the rest.
  *Senior / principal / architect:* your home is the architecture lens at the §7 review gate (ADRs,
  15-factor), the autonomy-tier model (`DEVELOPMENT-PROCESS.md` §13), and the enterprise layer
  ([docs/enterprise/](docs/enterprise/)) — `MAINTAINING.md` if you'll extend the kit itself.

> **Don't have the product or design figured out yet?** Most of this kit assumes you arrive with a
> *Ready* backlog. If you're upstream of that — raw idea, no validated problem yet — start with the
> optional **[discovery loop](docs/discovery/discovery-loop.md)** (FRAME → SHAPE → Ready), then come back.

## Learning lane (Novice + Adjacent)

You don't need to learn all of this before you start — you need to know it *exists* and *why*, then
learn each piece as you hit it. For each pillar: **why an enterprise needs it → learn it for real →
where the kit applies it.** (Skip any you already know.)

| Pillar | Why an enterprise needs it | Learn it (canonical) | Where the kit applies it |
|--------|----------------------------|----------------------|--------------------------|
| **Test-Driven Development** | Change without fear; tests are the safety net that lets agents move fast | [Martin Fowler — TDD](https://martinfowler.com/bliki/TestDrivenDevelopment.html) + the worked demo: [docs/onboarding/first-feature-tdd.md](docs/onboarding/first-feature-tdd.md) | `DEVELOPMENT-STANDARDS.md` §7 + your `profiles/<stack>.md` |
| **15-Factor architecture** | Apps that run the same everywhere, scale, and don't lose data | [12factor.net](https://12factor.net) (+ the 3 modern factors) | `DEVELOPMENT-STANDARDS.md` §13 + `conformance/15-factor-checklist.md` |
| **Security & privacy** | Enterprises hold real user/affiliate/children's data; a breach is existential | [OWASP Top 10](https://owasp.org/www-project-top-ten/) | `DEVELOPMENT-STANDARDS.md` §2 + `SECURITY.md` + `docs/enterprise/data-governance.md` |
| **Governance & autonomy** | Agents (and humans) must not be able to cause irreversible harm | *kit-defined — learn it in the kit doc →* | `DEVELOPMENT-PROCESS.md` §12–13 + `.claude/` guard |
| **Environments & scale** | Prod is not your laptop; promotion is gated; production is human-gated | [12factor.net](https://12factor.net) (dev/prod parity) | `DEVELOPMENT-PROCESS.md` "Environments & promotion" |
| **Observability** | If you can't see it in prod, you can't operate it | [the three pillars](https://opentelemetry.io/docs/concepts/observability-primer/) | `DEVELOPMENT-STANDARDS.md` Factor 14 + `docs/operations/` |

Then see the whole thing in motion: **[WALKTHROUGH.md](WALKTHROUGH.md)** — one feature from idea to
operating software. When ready, go to **[START-HERE.md](START-HERE.md)**.

> **You can't break things by reading the wrong lane.** The kit's guard and CI gates protect every
> project regardless of what you read — they stop dangerous actions. This page makes you *educated*;
> the guardrails keep you *safe*.
