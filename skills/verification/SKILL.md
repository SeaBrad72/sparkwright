---
name: verification
description: Use BEFORE any completion/done/passing claim and BEFORE committing or opening a PR — the kit's own verification-before-completion skill (replaces, does not depend on, superpowers verification-before-completion). Evidence before claims: run the verification command fresh in this turn, read the exit code, count failures, and never trust a subagent's "done" report on file artifacts — verify on disk / via a clone dry-run.
---

# Verification — evidence before claims, confabulation-proofed

The kit's own verification-before-completion skill: the craft of proving work is actually done before saying so. It keeps the proven Iron-Law spine and bakes in the kit's hardest-won, most-bitten lessons — confabulation-proofing, the clone dry-run, and tagless-clone fidelity. Wired DUAL-SEAT: the **Engineer** invokes it as *evidence-before-claims* (the primary done-claimer); the **Orchestrator** invokes it as *confabulation-proofing* (the controller integrating subagent work). Replaces (does not depend on) superpowers `verification-before-completion`.

<!-- The frontmatter and the discipline phrases below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: verification, confabulation, clone dry-run, evidence before claims, fresh).
     Edits that drop or rename them can turn the skill-spine lock RED. -->

## When to use
Before **any** completion claim — "done", "passing", "green", "it works", "tests pass", "ready to merge" — and before committing or opening a PR. Every claim of completion is a claim of fact; this skill is how you earn the right to make it. A simple slice still gets verified; the cost of a verification run is always less than the cost of a false "done".

## The Iron Law
**No completion claim without fresh verification evidence.** You may not write a success word until you have, in this turn, run the verification command, read its exit code, and counted its failures. A prior run, a "should pass", a plan that says it will pass, or an agent's word is **not** evidence. If you have not run it, you do not know — and saying you know is the failure this skill exists to prevent.

## The gate function (identify → run → read → verify → claim)
1. **Identify** the command that actually proves the slice done — the slice's tests, the conformance check (`sh conformance/verify.sh --require`), `--selftest`, the build, the linter. Name it explicitly; do not hand-wave "the tests".
2. **Run it fresh** in *this* turn. Not a remembered run, not CI's last run, not the run before your edit — a `fresh` run against the current tree, after the change.
3. **Read** the exit code and **count** the failures. Read the actual output, not the first reassuring line. Zero failed is the only pass; "1 passed, 1 failed" is a fail.
4. **Verify** the artifacts exist on disk and contain what you claim — do not infer from intent.
5. **Only then claim** — and state the evidence (command + exit code + counts) alongside the claim, so the reader can check it.

## Confabulation-proofing
Never trust a subagent's "done" report on file artifacts. **A subagent can report success for files it never wrote** — it can confabulate a clean diff, a passing test, a created file, in perfect good faith. The report is a *claim*, not evidence. The controller's gate is to **verify on the VCS diff and on disk**, never on the report: did the files actually change? does the verifier actually pass against the integrated tree? The strongest form is a **clone dry-run** — apply the change to a fresh `git clone` and run the gate there; the clone + `verify --require` gate is confabulation-proof because nothing in the agent's narration can fake a green exit code in a tree it did not touch. This is the Orchestrator's verification gate, distinct from the Engineer's: the Engineer proves its own slice; the Orchestrator proves the *integrated* result it was handed.

## Evidence before claims
The whole skill compresses to three words: **evidence before claims.** Evidence is a command you ran in this turn, an exit code you read, a count you checked, a file you opened. Everything else — intent, memory, an agent's word, "it obviously works" — is a claim wearing evidence's clothes. When you catch yourself about to say "done", ask: *what fresh output am I looking at right now?* If the answer is "none", you are confabulating, and the Iron Law forbids the claim.

## Tagless-clone fidelity
A `git clone .` of the local repo is **not** a faithful CI simulation: it carries the local tags, but `actions/checkout` does **not** fetch tags by default. A check that reads git tags (release-coherence, version-tag checks) will false-pass on a tag-carrying local clone and then go RED in CI. **Validate any tag-reading check on a tagless clone** (clone then `git tag -d` the tags, or fetch with `--no-tags`) so your local green means what CI's green means. The clone dry-run is confabulation-proof for file artifacts; for tag-reading checks it is only faithful when tagless.

## The non-vacuity tie-in
A green check must *mean* something. Verification is also how you know the check is **live, not drifted-green** — a conformance assertion that passes no matter what proves nothing. When you add or rely on a check, prove it has teeth: break the thing it guards and watch it go RED, then restore. A check you have never seen fail is not yet evidence; it is a hope.

## Rationalizations to refuse
| Rationalization | Why it fails |
|---|---|
| "It passed last time / before my edit." | Not fresh. The current tree is unverified. |
| "The subagent reported it done." | A report is a claim; verify the diff/clone, not the narration. |
| "It's a trivial change, it obviously works." | The cheapest bugs to catch are the obvious ones you didn't run. |
| "CI will catch it." | CI is the backstop, not the gate; a red CI is a missed verification, not a substitute for one. |
| "I'm out of time / budget." | A false "done" costs more than the run. Raise, don't fake. |
| "The local clone passed, so CI will." | Only if the check reads no tags — otherwise validate tagless. |

## Red flags (stop and verify)
- About to write "done", "passing", "green", "works", "ready" with no fresh command output in this turn.
- Relaying a subagent's success without inspecting the diff or running the gate against the integrated tree.
- "Should pass", "I believe", "it ought to" — belief is not evidence.
- A green check you have never watched fail (possibly drifted-green / vacuous).
- A tag-reading check verified only on a tag-carrying clone.

## Terminal state
Every completion claim is backed by a fresh verification run whose exit code and failure count you read in this turn; subagent work is proven on the diff / a clone dry-run, never on the report; tag-reading checks are validated tagless; and any check you rely on has been seen to fail. The claim states its evidence. No evidence, no claim — fail-closed.
