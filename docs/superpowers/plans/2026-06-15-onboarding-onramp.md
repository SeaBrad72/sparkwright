# Onboarding On-Ramp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fluency-aware onboarding on-ramp that meets developers across the experience spectrum, teaches *the system around the code* by routing (not duplicating), and lets the agent adapt its assistance — all enforced by a structural conformance check.

**Architecture:** New root `ONBOARDING.md` front door (experience axis) hands off to existing `START-HERE.md` (role axis). Teaching = connective tissue + the existing `WALKTHROUGH.md` + one new concrete TDD demo. AI adaptation via a declared `Operator fluency` line (read from project `CLAUDE.md`) + `docs/operations/operator-fluency.md`. A new `conformance/onboarding-complete.sh` (mirrors `persona-artifacts.sh`) proves the on-ramp exists and is wired.

**Tech Stack:** POSIX sh (conformance + incept), Markdown (docs). No new runtime deps.

**Branch:** `feature/onboarding-onramp` (already created off `main`).

**Doc-budget rule:** the core-3 (`CLAUDE.md`, `DEVELOPMENT-PROCESS.md`, `DEVELOPMENT-STANDARDS.md`) must stay **900/900**. None of these tasks touch them. Run `sh conformance/doc-budget.sh` in Task 8 to confirm.

**Spec:** `docs/superpowers/specs/2026-06-15-onboarding-onramp-design.md`

---

## File map

- **Create:** `conformance/onboarding-complete.sh` (structural check + `--selftest`)
- **Create:** `ONBOARDING.md` (root — front door, 3 lanes, thesis, connective tissue)
- **Create:** `docs/operations/operator-fluency.md` (agent adaptation per level)
- **Create:** `docs/onboarding/first-feature-tdd.md` (concrete red-green-refactor)
- **Modify:** `templates/PROJECT-CLAUDE-TEMPLATE.md` (add `Operator fluency` line to §3)
- **Modify:** `AGENTS.md` (one pointer line → operator-fluency.md; stays ≤ 80 lines)
- **Modify:** `scripts/incept.sh` (`--operator-fluency` flag + no-fluency nudge + stamp)
- **Modify:** `WALKTHROUGH.md` (one pointer in Part 2 → first-feature-tdd.md)
- **Modify:** `conformance/verify.sh` + `conformance/README.md` (register the new control)
- **Modify:** `README.md` (front-door link), `START-HERE.md` (cross-link), `GLOSSARY.md` (entry)
- **Modify:** `VERSION`, `README.md` badge, `CHANGELOG.md` (2.59.0)

---

### Task 1: `conformance/onboarding-complete.sh` — the structural check (slice's failing test)

**Files:**
- Create: `conformance/onboarding-complete.sh`

- [ ] **Step 1: Write the check** (mirrors `conformance/persona-artifacts.sh` exactly in shape)

```sh
#!/bin/sh
# onboarding-complete.sh — completeness drift-guard for the onboarding on-ramp.
# Asserts the on-ramp EXISTS and is WIRED: (a) ONBOARDING.md present + names the 3 fluency
# lanes; (b) the PROJECT-CLAUDE template carries an `Operator fluency` field; (c) the
# operator-fluency adaptation doc exists and AGENTS.md points at it; (d) the TDD walkthrough
# exists. Completeness, NOT content quality — green means the on-ramp is structurally whole and
# wired, NOT that anyone learned anything (the guard + gates are the enforced safety net).
#   sh conformance/onboarding-complete.sh [--selftest]
# Exit: 0 = complete · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

LANES="Novice Adjacent Practitioner"

# check_tree <root>: print PASS/FAIL per requirement; return 1 if any gap.
check_tree() {
  root=$1; f=0
  onramp="$root/ONBOARDING.md"
  tmpl="$root/templates/PROJECT-CLAUDE-TEMPLATE.md"
  fluency="$root/docs/operations/operator-fluency.md"
  brief="$root/AGENTS.md"
  tdd="$root/docs/onboarding/first-feature-tdd.md"
  if [ -f "$onramp" ]; then
    for lane in $LANES; do
      if grep -q "$lane" "$onramp"; then echo "PASS: ONBOARDING.md names lane $lane"; else echo "FAIL: ONBOARDING.md omits lane $lane"; f=1; fi
    done
  else echo "FAIL: missing $onramp"; f=1; fi
  if [ -f "$tmpl" ] && grep -q "Operator fluency" "$tmpl"; then echo "PASS: PROJECT-CLAUDE template carries Operator fluency"; else echo "FAIL: PROJECT-CLAUDE template lacks 'Operator fluency'"; f=1; fi
  if [ -f "$fluency" ]; then echo "PASS: operator-fluency.md exists"; else echo "FAIL: missing $fluency"; f=1; fi
  if [ -f "$brief" ] && grep -q "operator-fluency" "$brief"; then echo "PASS: AGENTS.md points at operator-fluency"; else echo "FAIL: AGENTS.md omits operator-fluency pointer"; f=1; fi
  if [ -f "$tdd" ]; then echo "PASS: first-feature-tdd.md exists"; else echo "FAIL: missing $tdd"; f=1; fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: empty -> must be detected
  g=$(mktemp -d); mkdir -p "$g/templates" "$g/docs/operations" "$g/docs/onboarding"
  if check_tree "$g" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap not detected"; sfail=1
  else
    echo "PASS: selftest — missing on-ramp artifacts detected"
  fi
  # complete tree: all present -> must pass
  ok=$(mktemp -d); mkdir -p "$ok/templates" "$ok/docs/operations" "$ok/docs/onboarding"
  printf '# Onboarding\nNovice\nAdjacent\nPractitioner\n' > "$ok/ONBOARDING.md"
  printf 'Operator fluency: x\n' > "$ok/templates/PROJECT-CLAUDE-TEMPLATE.md"
  printf '# fluency\n' > "$ok/docs/operations/operator-fluency.md"
  printf 'see docs/operations/operator-fluency.md\n' > "$ok/AGENTS.md"
  printf '# tdd\n' > "$ok/docs/onboarding/first-feature-tdd.md"
  if check_tree "$ok" >/dev/null 2>&1; then
    echo "PASS: selftest — complete on-ramp passes"
  else
    echo "FAIL: selftest — complete on-ramp wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: onboarding-complete selftest (fixtures left in $g, $ok)"; exit 0; } || { echo "FAIL: onboarding-complete selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: onboarding-complete.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Onboarding on-ramp completeness:"
if check_tree "."; then
  echo "OK: on-ramp present + wired (3 lanes, fluency field, adaptation doc + AGENTS pointer, TDD walkthrough)"
  exit 0
else
  echo "FAIL: on-ramp incomplete (see above)"
  exit 1
fi
```

- [ ] **Step 2: chmod + dash syntax + shellcheck**

Run: `chmod +x conformance/onboarding-complete.sh && dash -n conformance/onboarding-complete.sh && shellcheck -s sh -S warning conformance/onboarding-complete.sh && echo OK`
Expected: `OK` (dash-clean + shellcheck-clean — it's now in `shellcheck.sh` scope).

- [ ] **Step 3: Run `--selftest` (must pass — fixtures are self-contained)**

Run: `sh conformance/onboarding-complete.sh --selftest`
Expected: 2 PASS lines + `OK: onboarding-complete selftest`.

- [ ] **Step 4: Run the real check (must FAIL — artifacts don't exist yet; this is the slice's red)**

Run: `sh conformance/onboarding-complete.sh; echo "exit=$?"`
Expected: multiple `FAIL:` lines + `exit=1`. This is correct — Tasks 2–6 turn it green.

- [ ] **Step 5: Commit**

```bash
git add conformance/onboarding-complete.sh
git commit -m "feat(conformance): onboarding-complete — structural drift-guard for the on-ramp"
```

---

### Task 2: `ONBOARDING.md` — the front door

**Files:**
- Create: `ONBOARDING.md`

- [ ] **Step 1: Write the file.** Required structure (must contain the literal lane names `Novice`, `Adjacent`, `Practitioner` for the check; written in the layered "skip if you know this" style):

```markdown
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

## Learning lane (Novice + Adjacent)

You don't need to learn all of this before you start — you need to know it *exists* and *why*, then
learn each piece as you hit it. For each pillar: **why an enterprise needs it → learn it for real →
where the kit applies it.** (Skip any you already know.)

| Pillar | Why an enterprise needs it | Learn it (canonical) | Where the kit applies it |
|--------|----------------------------|----------------------|--------------------------|
| **Test-Driven Development** | Change without fear; tests are the safety net that lets agents move fast | [Martin Fowler — TDD](https://martinfowler.com/bliki/TestDrivenDevelopment.html) + the worked demo: [docs/onboarding/first-feature-tdd.md](docs/onboarding/first-feature-tdd.md) | `DEVELOPMENT-STANDARDS.md` §7 + your `profiles/<stack>.md` |
| **15-Factor architecture** | Apps that run the same everywhere, scale, and don't lose data | [12factor.net](https://12factor.net) (+ the 3 modern factors) | `DEVELOPMENT-STANDARDS.md` §13 + `conformance/15-factor-checklist.md` |
| **Security & privacy** | Enterprises hold real user/affiliate/children's data; a breach is existential | [OWASP Top 10](https://owasp.org/www-project-top-ten/) | `DEVELOPMENT-STANDARDS.md` §2 + `SECURITY.md` + `docs/enterprise/data-governance.md` |
| **Governance & autonomy** | Agents (and humans) must not be able to cause irreversible harm | — | `DEVELOPMENT-PROCESS.md` §12–13 + `.claude/` guard |
| **Environments & scale** | Prod is not your laptop; promotion is gated; production is human-gated | — | `DEVELOPMENT-PROCESS.md` "Environments & promotion" |
| **Observability** | If you can't see it in prod, you can't operate it | — | `DEVELOPMENT-STANDARDS.md` Factor 14 + `docs/operations/` |

Then see the whole thing in motion: **[WALKTHROUGH.md](WALKTHROUGH.md)** — one feature from idea to
operating software. When ready, go to **[START-HERE.md](START-HERE.md)**.

> **You can't break things by reading the wrong lane.** The kit's guard and CI gates protect every
> project regardless of what you read — they stop dangerous actions. This page makes you *educated*;
> the guardrails keep you *safe*.
```

- [ ] **Step 2: Verify the check advances + links resolve**

Run: `sh conformance/onboarding-complete.sh 2>&1 | grep lane; sh conformance/check-links.sh | tail -1`
Expected: 3 `PASS: ONBOARDING.md names lane …` lines; links resolve (the `docs/onboarding/first-feature-tdd.md` + `docs/operations/operator-fluency.md` links will fail until Tasks 3 & 6 — acceptable mid-slice; re-checked green in Task 8).

- [ ] **Step 3: Commit**

```bash
git add ONBOARDING.md
git commit -m "feat(onboarding): ONBOARDING.md — fluency front door (thesis + 3 lanes + connective tissue)"
```

---

### Task 3: `docs/operations/operator-fluency.md` + AGENTS.md pointer

**Files:**
- Create: `docs/operations/operator-fluency.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Write `docs/operations/operator-fluency.md`**

```markdown
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
```

- [ ] **Step 2: Add the pointer line to `AGENTS.md`** (it is 21 lines; bound is 80, so this is safe). Add under the existing canonical-doc pointers:

```markdown
- **Operator fluency** (adapt to the human's level): `docs/operations/operator-fluency.md`
```

- [ ] **Step 3: Verify AGENTS.md stays within bound + check advances**

Run: `sh conformance/agents-brief.sh && sh conformance/onboarding-complete.sh 2>&1 | grep -E "operator-fluency|AGENTS"`
Expected: agents-brief PASS (≤80 lines, refs intact); `PASS: operator-fluency.md exists` + `PASS: AGENTS.md points at operator-fluency`.

- [ ] **Step 4: Commit**

```bash
git add docs/operations/operator-fluency.md AGENTS.md
git commit -m "feat(onboarding): operator-fluency adaptation doc + AGENTS.md pointer"
```

---

### Task 4: `Operator fluency` field in the project-CLAUDE template

**Files:**
- Modify: `templates/PROJECT-CLAUDE-TEMPLATE.md` (§3 "Per-project process configuration", alongside the Data-classification line)

- [ ] **Step 1: Add the field.** Insert after the `Data classification` bullet in §3:

```markdown
- **Operator fluency** (§onboarding): [Novice / Adjacent / Practitioner] — the human operator's enterprise-SDLC experience; the agent adapts its assistance accordingly (`ONBOARDING.md`; behaviour in `docs/operations/operator-fluency.md`).
```

- [ ] **Step 2: Verify the check advances**

Run: `sh conformance/onboarding-complete.sh 2>&1 | grep "Operator fluency"`
Expected: `PASS: PROJECT-CLAUDE template carries Operator fluency`.

- [ ] **Step 3: Commit**

```bash
git add templates/PROJECT-CLAUDE-TEMPLATE.md
git commit -m "feat(onboarding): declare Operator fluency in the project-CLAUDE template"
```

---

### Task 5: `incept.sh` — `--operator-fluency` flag + nudge + stamp

**Files:**
- Modify: `scripts/incept.sh`

- [ ] **Step 1: Add the default var + allowlist.** After line 19 (`CI="${INCEPT_CI:-github}"`), add:

```sh
FLUENCY="${INCEPT_OPERATOR_FLUENCY:-}"          # empty = undeclared (nudge); else stamped
OPERATOR_FLUENCIES="novice adjacent practitioner"
```

- [ ] **Step 2: Parse the flag.** In the `while`/`case` loop, add a case before the `-h|--help` line:

```sh
    --operator-fluency) reqval $# --operator-fluency; FLUENCY="$2"; shift 2 ;;
```

Update the `-h|--help` usage string and the header comment to include `[--operator-fluency novice|adjacent|practitioner]`.

- [ ] **Step 3: Validate when given.** After the `--ci` validation (line ~82), add:

```sh
if [ -n "$FLUENCY" ]; then
  case " $OPERATOR_FLUENCIES " in *" $FLUENCY "*) : ;; *) echo "error: unknown --operator-fluency '$FLUENCY' (one of: $OPERATOR_FLUENCIES)" >&2; exit 2 ;; esac
fi
```

- [ ] **Step 4: Nudge when undeclared.** Near the `--stack` notice (line ~86), add:

```sh
[ -n "$FLUENCY" ] || echo "notice: operator fluency not declared. New to enterprise SDLC? read ONBOARDING.md. Already fluent? pass --operator-fluency practitioner. Leaving the field for you to fill in CLAUDE.md." >&2
```

- [ ] **Step 5: Stamp it.** In the `--- 3. stamp the project CLAUDE.md ---` block (after the `sedi` at line 116–121), add a conditional stamp that replaces the template placeholder with the chosen level (capitalized) when given:

```sh
if [ -n "$FLUENCY" ]; then
  # Capitalize first letter for the human-facing value (Novice/Adjacent/Practitioner)
  FCAP=$(printf '%s' "$FLUENCY" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$FLUENCY" | cut -c2-)
  sedi "s#\*\*Operator fluency\*\* (§onboarding): \[Novice / Adjacent / Practitioner\]#**Operator fluency** (§onboarding): ${FCAP}#" CLAUDE.md
fi
```

- [ ] **Step 6: dash + shellcheck + inception-done regression**

Run:
```bash
dash -n scripts/incept.sh && shellcheck -s sh -S warning scripts/incept.sh && echo OK
tmp=$(mktemp -d); git archive HEAD | tar -x -C "$tmp"
( cd "$tmp" && sh scripts/incept.sh --noninteractive --name DemoApp --intent-owner CI --stack typescript-node --backlog md --operator-fluency adjacent )
sh conformance/inception-done.sh "$tmp"
grep "Operator fluency" "$tmp/CLAUDE.md"
```
Expected: `OK`; inception-done passes; the grep shows `**Operator fluency** (§onboarding): Adjacent`.

- [ ] **Step 7: Commit**

```bash
git add scripts/incept.sh
git commit -m "feat(onboarding): incept --operator-fluency flag + undeclared nudge + CLAUDE stamp"
```

---

### Task 6: `docs/onboarding/first-feature-tdd.md` + WALKTHROUGH pointer

**Files:**
- Create: `docs/onboarding/first-feature-tdd.md`
- Modify: `WALKTHROUGH.md` (Part 2, the Build bullet)

- [ ] **Step 1: Write the TDD walkthrough.** Concrete red-green-refactor in the reference stack (typescript-node), explicitly flagged illustrative. Required content:

````markdown
# Your First Feature — the TDD rhythm (worked)

This zooms into the **Build** step of [WALKTHROUGH.md](../../WALKTHROUGH.md) and shows the
red-green-refactor rhythm with real code. **Illustrative — shown in the reference stack
(TypeScript/Node); your `profiles/<stack>.md` has the exact commands for yours.**

The discipline is always the same three beats:

## 1. RED — write the failing test first

```ts
// src/cart.test.ts
import { describe, it, expect } from "vitest";
import { subtotal } from "./cart";

it("sums line items", () => {
  expect(subtotal([{ price: 300, qty: 2 }, { price: 150, qty: 1 }])).toBe(750);
});
```

Run it. It MUST fail (the function doesn't exist yet):

```
$ npm test
✗ subtotal is not defined
```

Why first? The failing test proves the test actually tests something — and pins down the behaviour
*before* you write code to fit it.

## 2. GREEN — the minimal code to pass

```ts
// src/cart.ts
type Line = { price: number; qty: number };
export const subtotal = (lines: Line[]): number =>
  lines.reduce((sum, l) => sum + l.price * l.qty, 0);
```

```
$ npm test
✓ sums line items
```

Minimal. No edge cases you don't have a test for yet (YAGNI).

## 3. REFACTOR — improve with the test as your net

Now make it clean/safe knowing the test will catch a regression — e.g. guard against an empty cart,
add a test for it first (back to RED), then refactor. The test suite is what lets you change code
*without fear* — that safety net is the whole point, and it's why the kit treats tests as
non-negotiable rather than optional.

## What just happened (the enterprise part)

That rhythm is one beat inside the larger loop in [WALKTHROUGH.md](../../WALKTHROUGH.md): your tests
become the CI gate, the gate guards every future change, and the agent can move at machine speed
between the human checkpoints *because* the tests exist. Coding was the task; the test, the gate,
and the loop around it are the engineering.
````

- [ ] **Step 2: Add the pointer in `WALKTHROUGH.md` Part 2.** Modify the **Build** bullet (line ~35) to append a pointer — change the phrase `TDD per the profile` to:

```markdown
TDD per the profile (**new to TDD? see the worked red-green-refactor: `docs/onboarding/first-feature-tdd.md`**)
```

- [ ] **Step 3: Verify check + links**

Run: `sh conformance/onboarding-complete.sh 2>&1 | grep first-feature-tdd; sh conformance/check-links.sh | tail -1`
Expected: `PASS: first-feature-tdd.md exists`; `OK: all relative Markdown links resolve`.

- [ ] **Step 4: Commit**

```bash
git add docs/onboarding/first-feature-tdd.md WALKTHROUGH.md
git commit -m "feat(onboarding): worked red-green-refactor TDD walkthrough + WALKTHROUGH pointer"
```

---

### Task 7: Wiring — README front door + START-HERE cross-link + GLOSSARY

**Files:**
- Modify: `README.md` (add ONBOARDING.md to the intro links + "What's inside" table)
- Modify: `START-HERE.md` (cross-link back to ONBOARDING.md for the experience axis)
- Modify: `GLOSSARY.md` (add "operator fluency" entry)

- [ ] **Step 1: README — add a front-door line** after the existing "New to the terminology?" line (~line 13):

```markdown
**Brand new to enterprise software practices?** Start at [ONBOARDING.md](ONBOARDING.md) — it places you by experience and teaches the system around the code.
```

And add a row to the "What's inside" table (after the `START-HERE.md` row):

```markdown
| **`ONBOARDING.md`** | The experience-aware front door — meet developers from vibe-coder to principal, then hand to START-HERE. |
```

- [ ] **Step 2: START-HERE — cross-link** at the very top of the "Who are you? Start here" section (after line 15 intro), add:

```markdown
> **Not sure you're ready for Inception?** If enterprise SDLC practices are new to you, start at [ONBOARDING.md](ONBOARDING.md) first — it routes by *experience*; this page routes by *role*.
```

- [ ] **Step 3: GLOSSARY — add an entry** (alphabetical position):

```markdown
- **Operator fluency** — a project's declared signal of the human operator's enterprise-SDLC experience (Novice / Adjacent / Practitioner), set in `CLAUDE.md` §3. The agent adapts how it communicates to match (see `docs/operations/operator-fluency.md`); it never changes what the agent is permitted to do.
```

- [ ] **Step 4: Verify links**

Run: `sh conformance/check-links.sh | tail -1`
Expected: `OK: all relative Markdown links resolve`.

- [ ] **Step 5: Commit**

```bash
git add README.md START-HERE.md GLOSSARY.md
git commit -m "feat(onboarding): wire ONBOARDING.md from README + START-HERE + GLOSSARY"
```

---

### Task 8: Register the control + full conformance green

**Files:**
- Modify: `conformance/verify.sh` (add a control row)
- Modify: `conformance/README.md` (add a registry row)

- [ ] **Step 1: Register in `verify.sh`.** After the `ci-selftest-cov` control line, add:

```sh
check control onboarding       sh conformance/onboarding-complete.sh
```

- [ ] **Step 2: Add the `conformance/README.md` registry row** (after the `ci-selftest-coverage.sh` row):

```markdown
| `onboarding-complete.sh` | script | the onboarding on-ramp is structurally present + wired — `ONBOARDING.md` names the 3 fluency lanes, the project-CLAUDE template carries `Operator fluency`, `operator-fluency.md` exists and AGENTS.md points at it, the TDD walkthrough exists. Completeness only — green means present + wired, NOT that the teaching "works" (the guard + gates are the enforced safety net); `--selftest` covers gap + complete fixtures | CI |
```

- [ ] **Step 3: Run the full suite — everything green now**

Run:
```bash
sh conformance/onboarding-complete.sh; echo "real=$?"
sh conformance/onboarding-complete.sh --selftest >/dev/null && echo "selftest OK"
sh conformance/shellcheck.sh | tail -1
sh conformance/ci-selftest-coverage.sh | tail -1
sh conformance/check-links.sh | tail -1
sh conformance/doc-budget.sh | tail -1
sh conformance/verify.sh 2>&1 | grep -E "onboarding|Summary|RESULT"
```
Expected: `real=0`; `selftest OK`; shellcheck OK; ci-selftest-coverage OK; links OK; `OK: core docs within budget`; the `onboarding` control `PASS` + `RESULT: OK`.

> Note: `ci-selftest-coverage.sh` will report `onboarding-complete.sh` as **UNWIRED** until the owner adds the CI step (control-plane). That is expected and is the required follow-up below — it does not block this PR (the check is registered in `verify.sh`).

- [ ] **Step 4: Commit**

```bash
git add conformance/verify.sh conformance/README.md
git commit -m "feat(conformance): register onboarding-complete control in verify.sh + README"
```

---

### Task 9: Release bump → 2.59.0

**Files:**
- Modify: `VERSION`, `README.md` (badge), `CHANGELOG.md`

- [ ] **Step 1: Bump VERSION**

```bash
printf '2.59.0\n' > VERSION
```

- [ ] **Step 2: Badge** — in `README.md` change `` `v2.58.0` `` → `` `v2.59.0` `` (line 3).

> Note: the badge reads `v2.58.0` only after PR #87 merges; if `main` is still `v2.57.0` when this branch is cut, change whatever the current badge token is to `v2.59.0` and rebase once #87 lands so the bump is monotonic.

- [ ] **Step 3: CHANGELOG entry** — add above the most recent entry:

```markdown
## [2.59.0] - 2026-06-15

**Onboarding on-ramp** — a fluency-aware front door that meets developers across the experience spectrum (vibe-coder → principal), teaches *the system around the code* by routing to canonical sources (never duplicating the standards), and lets the agent adapt its assistance. **MINOR** — new front-door docs + a structural conformance control; no new universal-required gate.

### Added
- **`ONBOARDING.md`** — experience-axis front door: the *coding ≠ engineering* thesis + 3 self-select lanes (Novice / Adjacent / Practitioner, non-punitive to switch) + a layered Learning lane that motivates each pillar (TDD · 15-factor · security · governance · environments · observability) and routes to canonical sources + the existing kit docs. Hands off to `START-HERE.md` (role axis).
- **`docs/onboarding/first-feature-tdd.md`** — a worked red-green-refactor TDD walkthrough (reference stack), the one concrete code beat the whole-loop `WALKTHROUGH.md` lacked.
- **Operator fluency** — declared in the project-CLAUDE template (§3) and read by the agent via `docs/operations/operator-fluency.md`: adapts *communication* to the operator's level (explain + confirm-before-irreversible for Novice/Adjacent; terse for Practitioner), refined by observation, **never** changing what the agent is permitted to do. `incept.sh --operator-fluency <level>` stamps it; an undeclared run nudges (not walls) toward the on-ramp.
- **`conformance/onboarding-complete.sh`** — structural drift-guard: the on-ramp is present + wired.

### Honesty / engineering notes
- **The on-ramp teaches; the guard + gates protect.** A bypass (the Practitioner lane / `--operator-fluency practitioner`) skips the *teaching*, never the *protection* — which is what makes "functional and not dangerous" hold even for someone who skips onboarding.
- **No duplication of the standards** — the Learning lane motivates and routes; the canonical content stays in the standards/profiles as the single source of truth (DRY).
```

- [ ] **Step 4: Verify badge + final suite**

Run: `sh conformance/badge-version.sh && sh conformance/check-links.sh | tail -1 && sh conformance/verify.sh 2>&1 | grep RESULT`
Expected: badge PASS; links OK; `RESULT: OK`.

- [ ] **Step 5: Commit**

```bash
git add VERSION README.md CHANGELOG.md
git commit -m "chore(release): 2.59.0 — onboarding on-ramp"
```

---

## After all tasks

1. **Independent review** (builder ≠ reviewer): dispatch the `reviewer` (and `security-reviewer` for the `incept.sh` + `AGENTS.md` changes) on `git diff main...HEAD`. Address findings.
2. **Open the PR** with `--body-file` (the body mentions control-plane words → use a file to avoid the guard's command-string matcher). Bradley merges.
3. **Owner follow-up (control-plane hand-apply):** add the real-run CI step so the new control actually gates — colon-free `name:`:
   ```yaml
         - name: Onboarding on-ramp completeness (present + wired)
           run: sh conformance/onboarding-complete.sh
   ```
4. After merge: `git tag v2.59.0 && git push origin v2.59.0`.
