# Security disclosure — the response path

**Status:** operative · **Established:** 2026-08-04 (recovery-plan slice A1, row `T0-09`) · **Owner-ratified:** the triager assignment and clock below were set by the maintainer in-session, 2026-08-04.

`SECURITY.md` makes two external commitments: a **primary channel** (GitHub Private Vulnerability
Reporting on the public repo) and a **2-business-day acknowledgement**. This document is the internal
half — who answers, on what clock, and how. `SECURITY.md` states the promise; this file makes it
operable. The two must not disagree.

## The channel

- **Primary:** GitHub Private Vulnerability Reporting on **`SeaBrad72/sparkwright`** (the public
  repo). Enabled by the maintainer 2026-08-04 — verified live: the API returns `{"enabled":true}`.
- **Fallback** (per `SECURITY.md`): a public issue titled `security: request private contact`, no
  details, answered with a private channel on the same clock.
- **The setting is locked, not trusted:** `conformance/security-channel-live.sh` reads the declared
  channel repo from `SECURITY.md` and queries the **live forge setting** — a green run cannot coexist
  with a disabled channel. (`security-policy.sh` verifies the prose only; that gap is what let the
  channel sit disabled from publication until 2026-08-04.)

## Who and when

| step | owner | clock |
|---|---|---|
| **Acknowledgement** | **Bradley James (`SeaBrad72`)** — owns the clock | ≤ **2 business days** from report |
| **Triage + severity** (P0–P3 per `DEVELOPMENT-PROCESS.md` §9 / STANDARDS §15) | Bradley James, with agent assist (reproduce, assess blast radius, draft timeline) | ≤ 5 business days |
| **Fix / mitigation** | routed as a board row at the triaged severity; P0/P1 follow Incident Response (STANDARDS §15) | by severity |
| **Disclosure + credit** | coordinated timeline agreed with the reporter; credit with opt-out | per agreement |

Solo-maintainer honesty: one human holds every step. The clock commitment is therefore sized to what
one person can honour (2 business days, not hours), and the fallback channel makes the same promise
independently — a reporter is never dead-ended by the primary channel's availability.

## The advisory route for already-disclosed findings

The kit self-discloses security findings in `CHANGELOG.md` public notes (e.g. the v3.196.0 guard P0,
disclosed with its fix). For any finding that warrants reaching adopters beyond the changelog: publish
a **GitHub Security Advisory** on the public repo (Security → Advisories), scoped per `SECURITY.md`
(the kit's scripts/checks/templates/docs; not the inert `profiles/` references), with the fixed
version named. The v3.196.0 disclosure predates this path and stands as shipped; new findings of
comparable severity use the advisory route.

## Honest ceiling

This document proves a path exists and is owned. It does **not** prove the clock is met — that is
operator conduct, observable only in the record of an actual report. `security-channel-live.sh`
proves the advertised channel is genuinely on; nothing mechanically enforces the SLA itself.
