# Operator Fluency — how the agent adapts to the human

The project `CLAUDE.md` declares `Operator fluency: Novice | Adjacent | Practitioner` (§3). The
agent reads it and adapts **how it communicates** — never **what it is permitted to do** (the §13
autonomy tiers and CI gates are unchanged; adaptation is style, not permission).

## Adaptation by level

- **Novice / Adjacent** — explain the *why* before the *how*; surface what is about to happen before
  doing it; **confirm before irreversible or destructive steps**; teach as you go; link to
  `ONBOARDING.md` and the relevant standard when introducing a new concept.
- **Practitioner** — be terse; assume competence; skip the explanations and the hand-holding;
  surface only genuine decisions and risks.

## Refine by observation

The declared level is the seed, not a cage. If a declared-Novice is plainly fluent (or a
declared-Practitioner is clearly struggling), adjust within reason and, once, note the mismatch so
the human can update the declaration. Default to the declared level when unsure.

## What this never changes

Fluency adaptation never relaxes the guard, the gates, or the Definition of Done. A Practitioner
gets terser prose — not fewer safeguards. This is the honest line between *teaching* (this doc) and
*protecting* (the guard + gates).
