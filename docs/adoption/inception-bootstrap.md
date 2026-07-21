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

## The three traps

- **K1 / K9 — do not commit before `incept`.** There is no repo yet (`incept` is what `git init`s), and a
  pre-incept commit breaks `inception-done`'s fixture build: its selftest keys the throwaway fixture on an
  incepted HEAD, so a spec-only HEAD would seed an incomplete tree. The inception design artifacts (charter,
  ADR-000) are committed **as** the incepted baseline — never before it.

- **Obtain the kit tree the way an adopter does — never by copying a working directory.** "Clone the kit"
  above means a **git clone**, a public-mirror clone at the release tag, or `sh scripts/adopter-export.sh
  <dest>`. All three carry only **committed** content. A `cp -R` of someone's working tree also carries
  their **untracked** files — build output, `node_modules`, local scratch — none of which any adopter
  receives, and none of which inception's manifest-driven pruning knows about (it reconciles
  `.kit-manifest`, which lists tracked files). A CP-7 cold field test was staged by directory copy and
  reported two "kit defects" that were purely artifacts of the copy. If you are standing up a *test*
  vehicle, record how you obtained the tree alongside the result — an unstated provenance makes a failure
  unattributable.

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

## Inception vocabulary — derive, don't block

A cold operator's routine inception values are usually **derivable from the charter and repo context** — the
agent should explain or derive them, not surface them as unexplained required inputs (K2). Two that recur:

- **Intent owner** (`--intent-owner`) — *the human who accepts the outcome and signs off on the project's
  "why."* For a certification/field test it is whoever accepts the result; for a product it is the sponsor.
  Derive it from the charter's owner. A VCS `@handle` (e.g. `@seabrad72`) additionally seeds an active
  CODEOWNERS rule; a plain name (`Bradley James`) does not (it is free text — see the CODEOWNERS handling in
  `scripts/incept.sh`). When it is genuinely unknown, ask **once** — don't turn a lookup into a blocker.
- **Representative real change** — *a small, real, tested change that exercises the full loop* (branch → PR →
  gates → merge), used to prove the emitted gates actually enforce (the "adopter operates" evidence, AC5).
  Pick the smallest genuine change in scope — e.g. a status/health endpoint with a test — never a throwaway
  edit whose gates wouldn't meaningfully run.

The rule: **derive safe values from the charter; surface a genuine decision, not a vocabulary lookup.**
