# Inception bootstrap sequence (incept-first)

**Where this sits:** `DEVELOPMENT-PROCESS.md` §3 (Project Inception) is the conceptual gate — *what* Inception
is and *when* a project enters the loop. This doc is the operational *how*: the exact order in which a new
project bootstraps, and the two ordering traps to avoid (K1/K9, K15). It is the detail START-HERE and §3
point to.

Inception is a genuine **bootstrap exception**: you cannot dev-clone a repo that does not exist yet, and
`incept` **is** the act that creates the repo and its control plane. So `incept` `git init`s *first* — the
order is not arbitrary. The loop's design/build **mechanics** (commit-the-spec-first, author-in-a-dev-clone)
do not govern Phase 0; the design **principle** (architecture-first) still does, satisfied by Inception's own
gate — the charter + ADR-000. See the "Inception exception" notes in `skills/design` + `skills/build`.

## The canonical order

```
clone the kit
  → run incept            (git init + in-place transform + guard install + ADR-000 stamp)
  → commit the incepted baseline   ← THE FIRST COMMIT (carries charter + ADR-000)
  → protect main · green CI on the empty project
  → enter the loop: the first feature branches from the committed incepted baseline
                    and runs the full design → plan → build gates
```

## The two traps

- **K1 / K9 — do not commit before `incept`.** There is no repo yet (`incept` is what `git init`s), and a
  pre-incept commit breaks `inception-done`'s fixture build: its selftest keys the throwaway fixture on an
  incepted HEAD, so a spec-only HEAD would seed an incomplete tree. The inception design artifacts (charter,
  ADR-000) are committed **as** the incepted baseline — never before it.

- **K15 — branch the first feature from the incepted baseline.** The **first feature branches from the committed incepted baseline** (which carries the inception evidence / ADR-000 / ledger), **never from a restored `origin/main`** that would drop it. If the bootstrap produced reviewed evidence on a branch, the first feature branch descends from it so one coherent history carries both the bootstrap evidence and the first feature.

## Why this is not "Inception skips rigor"

Exempting the loop mechanics is not exempting the discipline. Inception is the *most* architectural act in the
project — choosing the stack is ADR-000, a spike with a fit-vs-maturity disclosure enforced by
`stack-decision-integrity.sh`. And `incept` keeps its ownership/guard refusals in force: it refuses to run
over a foreign-owned tree (`scripts/incept.sh` asserts ownership before any mutation). The bootstrap is
exempt from the loop's repo-presupposing *machinery*, not from the kit's ethos.

## Branch protection at Inception-Done

`inception-done` verifies branch protection as part of the exit gate (K5):

- **GitHub remote** — verified **live** (`conformance/branch-protection.sh`); an unprotected `main` FAILs.
- **Other hosts** (the kit can't yet query them) — require a recorded **attestation** in the project
  `CLAUDE.md` (`- **Branch protection** (§branch-protection): attested: <host + mechanism>`); see
  `docs/adoption/vc-hosts.md`.
- **Modes** — the default gate is **strict** (unverifiable ⇒ FAIL: not loop-ready). `--surface` is the
  local/post-incept check where the obligation is surfaced (OUTSTANDING) but non-fatal; the CI `bootstrap`
  job uses `--surface` because a freshly incepted temp has no remote yet.
