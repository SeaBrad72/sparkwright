# Beginner On-Ramp (Slice 9f) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the beginner's cognitive friction (A6 findings F1–F4): a fail-fast prerequisite check, disclosure of the `CLAUDE.md→ENGINEERING-PRINCIPLES` rename, a one-page glossary, and a solo/lite track.

**Architecture:** One new POSIX-sh script (`scripts/preflight.sh`, universal + optional per-stack, `--selftest`), one new doc (`GLOSSARY.md`), and targeted edits to `incept.sh` (banner + startup preflight) and `START-HERE.md`/`README.md`. No loop-machinery change. Additive → MINOR v2.31.0.

**Tech Stack:** POSIX `sh` (dash-clean), Markdown. Verification via the script's `--selftest`, `dash -n`, `conformance/check-links.sh`, and a temp-repo incept run.

---

## Execution notes
- **One control-plane `cp`:** Task 6 edits `.github/workflows/ci.yml` (build in `/tmp` → human applies). Everything else is agent-editable (`scripts/preflight.sh` is in `scripts/`, not control-plane; `scripts/kit-guard`/`hooks/pre-push` are the only protected `scripts/`/`hooks/` paths).
- **Anonymization** ([[kit-anonymization]]): generic throughout — no enterprise/sector/personal names.
- **Branch:** `feature/slice-9f-beginner-onramp` (created; holds the A6 record + the spec already).
- **Guard-safety:** when testing, never put a dangerous token in a Bash command string; run corpora via `sh scripts/preflight.sh --selftest`.

## File structure

| File | Responsibility |
|------|----------------|
| `scripts/preflight.sh` (new) | Prerequisite check: universal (jq/git/sh) + optional `--stack` toolchain; `--selftest` |
| `GLOSSARY.md` (new) | One-page launchpad: ~12 load-bearing terms → authoritative sections |
| `scripts/incept.sh` (modify) | Rename banner in next-steps + startup universal-preflight hard-abort |
| `START-HERE.md` (modify) | preflight-first line · rename note · `## Solo / lite track` · GLOSSARY link |
| `README.md` (modify) | GLOSSARY link |
| `conformance/README.md` (modify) | preflight selftest index row |
| `.github/workflows/ci.yml` (modify, **human cp**) | `preflight.sh --selftest` step |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.31.0; 9f row → shipped |

---

## Task 1: `scripts/preflight.sh`

**Files:** Create `scripts/preflight.sh`

- [ ] **Step 1: Write the script** exactly as below. Note the **`for line in $tools` with `IFS=newline`** pattern — NOT a `printf | while` pipe, because a pipe runs the loop in a subshell and the `miss` accumulator would not propagate (the same subshell-pipe trap the guard avoids).

```sh
#!/bin/sh
# preflight.sh — prerequisite check for the Agentic SDLC Kit. Fails fast with
# install hints so a missing tool surfaces HERE, not as a cryptic guard/conformance
# failure later (jq is hard-required by the guard + conformance). Universal check
# always; optional per-stack toolchain via --stack.
#   sh scripts/preflight.sh [--stack <name>] [--selftest]
# Exit: 0 = all present · 1 = a required tool missing · 2 = bad usage.
# POSIX sh; dash-clean. New stack? add a row to stack_tools() (unknown degrades gracefully).
set -eu

miss=0
need() {  # need <tool> <install-hint>
  if command -v "$1" >/dev/null 2>&1; then
    echo "  ok   $1"
  else
    echo "  MISS $1 — $2"
    miss=1
  fi
}

stack_tools() {  # print "tool|hint" lines for a stack; return 1 if unknown
  case "$1" in
    typescript-node) printf 'node|nodejs.org or nvm\nnpm|ships with Node\n' ;;
    python|ml|data-engineering) printf 'python3|python.org or pyenv\npip3|ships with Python\n' ;;
    go) printf 'go|go.dev/dl\n' ;;
    dotnet) printf 'dotnet|dotnet.microsoft.com/download\n' ;;
    rust) printf 'cargo|rustup.rs\n' ;;
    java-spring) printf 'java|adoptium.net\nmvn|maven.apache.org\n' ;;
    kotlin) printf 'java|adoptium.net\n' ;;
    terraform) printf 'terraform|developer.hashicorp.com/terraform/install\n' ;;
    *) return 1 ;;
  esac
}

STACK=""; SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) STACK="${2:-}"; shift 2 ;;
    --selftest) SELFTEST=1; shift ;;
    -h|--help) echo "usage: preflight.sh [--stack <name>] [--selftest]"; exit 0 ;;
    *) echo "preflight: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ "$SELFTEST" -eq 1 ]; then
  fail=0
  if command -v kit_definitely_absent_tool_xyz >/dev/null 2>&1; then
    echo "FAIL: sentinel tool unexpectedly exists"; fail=1
  else
    echo "PASS: absent tool detected as missing"
  fi
  if command -v sh >/dev/null 2>&1; then echo "PASS: present tool (sh) detected"; else echo "FAIL: sh not detected"; fail=1; fi
  if stack_tools __nope__ >/dev/null 2>&1; then echo "FAIL: unknown stack not handled"; fail=1; else echo "PASS: unknown stack handled gracefully"; fi
  if stack_tools python >/dev/null 2>&1; then echo "PASS: known stack mapped"; else echo "FAIL: known stack not mapped"; fail=1; fi
  [ "$fail" -eq 0 ] && { echo "OK: preflight selftest"; exit 0; } || { echo "FAIL: preflight selftest"; exit 1; }
fi

echo "Agentic SDLC Kit — preflight"
echo "Universal prerequisites:"
need jq  "brew install jq | apt-get install jq | dnf install jq"
need git "git-scm.com/downloads"
need sh  "any POSIX shell"

if [ -n "$STACK" ]; then
  echo "Stack toolchain ($STACK):"
  if tools=$(stack_tools "$STACK"); then
    oldIFS=$IFS; IFS='
'
    for line in $tools; do
      [ -n "$line" ] || continue
      t=${line%%|*}; hint=${line#*|}
      need "$t" "$hint"
    done
    IFS=$oldIFS
  else
    echo "  (no toolchain map for '$STACK' — see profiles/$STACK.md)"
  fi
fi

if [ "$miss" -eq 0 ]; then
  echo "All prerequisites present."
  exit 0
else
  echo "Missing prerequisites above — install them, then re-run."
  exit 1
fi
```

- [ ] **Step 2: Make executable + dash-check.**
  Run: `chmod +x scripts/preflight.sh && dash -n scripts/preflight.sh && echo "syntax OK"`
  Expected: `syntax OK`.

- [ ] **Step 3: Run the selftest.**
  Run: `sh scripts/preflight.sh --selftest; echo "exit=$?"`
  Expected: four `PASS …` lines, `OK: preflight selftest`, `exit=0`.

- [ ] **Step 4: Smoke the real check (this machine has jq/git).**
  Run: `sh scripts/preflight.sh; echo "exit=$?"` then `sh scripts/preflight.sh --stack python; echo "exit=$?"`
  Expected: universal run lists `ok jq / ok git / ok sh`, "All prerequisites present.", `exit=0`; `--stack python` additionally lists `python3`/`pip3`. Bad stack: `sh scripts/preflight.sh --stack bogus` prints the "no toolchain map" note and still exits 0 if universal tools present.

- [ ] **Step 5: Commit.**
  ```bash
  git add scripts/preflight.sh
  git commit -m "feat(9f): preflight.sh — fail-fast prerequisite check (universal + per-stack, --selftest)"
  ```

---

## Task 2: incept.sh — rename banner + startup preflight

**Files:** Modify `scripts/incept.sh`

- [ ] **Step 1: Add the startup preflight hard-abort.** Insert immediately before the `# --- safety guards ---` line (after arg parsing, so `--help` still exits earlier without triggering it):

```sh
# 9f: fail fast if universal prerequisites are missing — jq is hard-required by the
# guard and conformance, so proceeding would only defer a cryptic failure.
if [ -f scripts/preflight.sh ] && ! sh scripts/preflight.sh >/dev/null 2>&1; then
  echo "incept: missing prerequisites. Run 'sh scripts/preflight.sh' for the list + install hints. Aborting." >&2
  exit 1
fi

```

- [ ] **Step 2: Add the rename-disclosure banner.** In the `cat <<EOF` next-steps block, add the banner line immediately after the `✅ Inception scaffolding complete …` line:

```
Note: the kit's principles doc moved to ENGINEERING-PRINCIPLES.md; this new CLAUDE.md is YOUR project guide (charter, config, roles).
```

- [ ] **Step 3: dash-check.**
  Run: `dash -n scripts/incept.sh && echo "syntax OK"`
  Expected: `syntax OK`.

- [ ] **Step 4: Functional test in a temp repo** (run as a script — guard-safe).
  Write `/tmp/test-incept-9f.sh`:
  ```sh
  #!/bin/sh
  set -eu
  SRC=~/Development/agentic-sdlc-kit
  T=$(mktemp -d)
  rsync -a --exclude '.git' --exclude 'node_modules' --exclude '.firecrawl' "$SRC"/ "$T"/
  cd "$T" && git init -q && git add -A && git -c user.email=ci@x -c user.name=ci commit -qm init
  out=$(sh scripts/incept.sh --noninteractive --name Demo --intent-owner Owner --stack python --backlog md 2>&1); echo "incept exit=$?"
  printf '%s\n' "$out" | grep -i "principles doc moved to ENGINEERING-PRINCIPLES" && echo "BANNER OK" || echo "BANNER MISSING"
  sh conformance/inception-done.sh . >/dev/null 2>&1 && echo "inception-done OK" || echo "inception-done FAIL"
  echo "leftover: $T"
  ```
  Run: `sh /tmp/test-incept-9f.sh`
  Expected: `incept exit=0`, `BANNER OK`, `inception-done OK`.

- [ ] **Step 5: Commit.**
  ```bash
  git add scripts/incept.sh
  git commit -m "feat(9f): incept fails fast on missing prereqs + discloses the principles-doc rename"
  ```

---

## Task 3: `GLOSSARY.md`

**Files:** Create `GLOSSARY.md` (repo root)

- [ ] **Step 1: Write the glossary.** One page, a `## Glossary` with a definition list. Each term: 1–2 sentences + a link to its authoritative home. Include exactly these ~12 terms:
  - **Inception (Phase 0)** — the one-time gate that turns an empty repo into a loop-ready project (`START-HERE.md`, `DEVELOPMENT-PROCESS.md` §3).
  - **The loop** — Discover → Plan → Build → Review → Release → Done (`DEVELOPMENT-PROCESS.md` §4).
  - **Contract → reference → conformance** — the kit's enforcement spine: a stated contract, a reference implementation, an executable check (`MAINTAINING.md`, `conformance/README.md`).
  - **Conformance check** — an executable script that proves a control holds (`conformance/README.md`).
  - **Ratification** — agents propose, humans approve; agents never self-merge governing changes (`docs/enterprise/ratification-rbac.md`).
  - **Autonomy tiers (L1/L2/L3)** — how much an agent may do without human sign-off (`DEVELOPMENT-PROCESS.md` §13).
  - **The guard** — the PreToolUse deny-matrix; a speed-bump, not a boundary (`.claude/hooks/guard.sh`, `docs/operations/runtime-guards.md`).
  - **The 7 CI gates** — lint, type-check, test+coverage, build, secret-scan, dep-scan, supply-chain (`DEVELOPMENT-STANDARDS.md` §14).
  - **Waiver** — a tracked, time-boxed, ratified exception to a gate for brownfield adoption (`templates/WAIVER-REGISTER.md`).
  - **Stage 1–4** — the maturity progression that tightens conformance as you scale (`docs/enterprise/ORG-ROLLOUT.md`).
  - **Profile** — the per-stack concrete config/commands you pick at Inception (`profiles/`).
  - **Control-plane** — the kit's own integrity files (guard, settings, CI, CODEOWNERS) an agent may not silently edit (`docs/operations/runtime-guards.md`).
  - **Green ≠ verified** — a passing check proves what it actually tests, never more (`conformance/README.md`).
  - Open with a one-line purpose and "new here? read `START-HERE.md`."

- [ ] **Step 2: Verify links + commit.**
  Run: `git add GLOSSARY.md && sh conformance/check-links.sh 2>&1 | tail -1` → links resolve.
  ```bash
  git commit -m "docs(9f): GLOSSARY.md — one-page launchpad for the load-bearing terms"
  ```

---

## Task 4: START-HERE.md — preflight line, rename note, solo track, glossary link

**Files:** Modify `START-HERE.md`

- [ ] **Step 1: Add the preflight-first line** near the top (after the intro paragraph, before "## Who are you?"):
  ```
  **Before anything:** run `sh scripts/preflight.sh` (add `--stack <yours>` once you've chosen) — it checks prerequisites (jq, git, your toolchain) and prints install hints. New to the terms here? See [GLOSSARY.md](GLOSSARY.md).
  ```

- [ ] **Step 2: Add the rename note** at the engineer row / first mention of running incept — append to the Engineer/Lead row or add a parenthetical where `CLAUDE.md` is first cited for principles:
  ```
  (Note: `incept` renames the kit's principles `CLAUDE.md` to `ENGINEERING-PRINCIPLES.md` and stamps a new project `CLAUDE.md` — your project guide. The glossary and START-HERE references to the *principles* file mean `ENGINEERING-PRINCIPLES.md` after Inception.)
  ```

- [ ] **Step 3: Add the `## Solo / lite track` section** (before the "Inception Done" checklist):
  ```markdown
  ## Solo / lite track

  Working alone? The kit assumes multiple people in places (builder ≠ sole reviewer, CODEOWNERS, ratification RBAC). Here is the sanctioned solo path:

  - **builder ≠ reviewer, solo.** You still open a PR and let CI gate it, then **merge your own PR via owner admin-merge.** GitHub records the admin bypass — that log *is* your audit trail of "solo maintainer self-ratified." When a second engineer joins, the required-review rule starts enforcing real review with **zero reconfiguration.**
  - **Deferrable gates at solo / Stage-1 scale.** Coverage, SBOM, provenance, and a11y can ride the waiver ramp ([templates/WAIVER-REGISTER.md](templates/WAIVER-REGISTER.md)) while you grow; **`secret-scan` and `branch-protection` stay non-negotiable.** You begin at **Stage 1** of the maturity model ([docs/enterprise/ORG-ROLLOUT.md](docs/enterprise/ORG-ROLLOUT.md)).
  - Everything else in this guide applies unchanged.
  ```

- [ ] **Step 4: Verify links + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → links resolve.
  ```bash
  git add START-HERE.md
  git commit -m "docs(9f): START-HERE — preflight-first, rename note, solo/lite track, glossary link"
  ```

---

## Task 5: README.md + conformance/README.md

**Files:** Modify `README.md`, `conformance/README.md`

- [ ] **Step 1: README glossary link.** Add near the top/intro (match existing link style):
  ```
  New to the terminology? See [GLOSSARY.md](GLOSSARY.md).
  ```

- [ ] **Step 2: conformance/README index row.** After the `agent-autonomy.sh`/`guard-core-sourced.sh` rows, add:
  ```markdown
  | `../scripts/preflight.sh` | script | beginner on-ramp (Slice 9f) — prerequisite check (jq/git/toolchain); `--selftest` regression-locks the detector | CI / pre-Inception |
  ```

- [ ] **Step 3: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → links resolve.
  ```bash
  git add README.md conformance/README.md
  git commit -m "docs(9f): README glossary link + conformance index row for preflight"
  ```

---

## Task 6: Wire preflight selftest into CI (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (build `/tmp` → human applies)

- [ ] **Step 1: Build the candidate.** Read the current `.github/workflows/ci.yml`; copy to `/tmp/ci.yml.9f`; add to the `conformance` job, after the `Agent-autonomy guard conformance (§13)` step:
  ```yaml
      - name: Preflight self-test (prerequisite detector)
        run: sh scripts/preflight.sh --selftest
  ```

- [ ] **Step 2: Validate.**
  Run: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.9f"); puts d["jobs"].keys.join(",")' && diff .github/workflows/ci.yml /tmp/ci.yml.9f`
  Expected: `conformance,bootstrap,docs-links`; diff shows only the one added step.

- [ ] **Step 3: Hand to Bradley to apply.**
  ```bash
  cp /tmp/ci.yml.9f .github/workflows/ci.yml && git add .github/workflows/ci.yml && git commit -m "ci(kit): 9f — gate preflight --selftest"
  ```

---

## Task 7: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: `VERSION`** → `2.31.0`.

- [ ] **Step 2: CHANGELOG entry** above `## [2.30.0]`:
  ```markdown
  ## [2.31.0] - 2026-06-10

  Beginner on-ramp (Slice 9f, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Closes the lowest-scoring review persona (beginner, 4/10), aimed by the A6 dogfood: the mechanical bootstrap was already fine; the friction was cognitive. **MINOR** — additive script + docs.

  ### Added
  - **`scripts/preflight.sh`** — fail-fast prerequisite check (universal jq/git/sh always; optional `--stack <name>` toolchain) with install hints; `--selftest`. `incept` runs it at startup and aborts on a missing universal prerequisite.
  - **`GLOSSARY.md`** — one-page launchpad for the ~12 load-bearing terms, each linking to its authoritative section.
  - **Solo / lite track** in `START-HERE.md` — how one person satisfies builder≠reviewer (owner admin-merge as logged self-ratification) and which gates are deferrable at Stage 1.

  ### Changed
  - **`incept` discloses the `CLAUDE.md → ENGINEERING-PRINCIPLES.md` rename** (banner) — closing A6 finding F2.
  - `START-HERE.md` / `README.md` point newcomers at preflight + the glossary; `conformance/README.md` indexes the preflight selftest (CI-gated).
  ```

- [ ] **Step 3: roadmap 9f row** — replace the `9f` row in `docs/ROADMAP-SLICE9.md`:
  ```markdown
  | **9f** ✅ | B | **Beginner on-ramp** (R6) — *shipped v2.31.0.* `preflight.sh` (universal + per-stack, --selftest; incept fails fast); `GLOSSARY.md`; rename disclosure (incept banner + START-HERE); solo/lite track. Aimed by the A6 dogfood (friction was cognitive, not mechanical). | P0¹ | MINOR ✅ |
  ```

- [ ] **Step 4: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1 && cat VERSION`
  ```bash
  git add VERSION CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.31.0 — beginner on-ramp (9f)"
  ```

---

## Task 8: Final verification + independent review + PR

- [ ] **Step 1: Full local sweep.**
  ```sh
  sh scripts/preflight.sh --selftest >/dev/null && echo "preflight selftest OK"
  dash -n scripts/preflight.sh && dash -n scripts/incept.sh && echo "dash OK"
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/check-links.sh 2>&1 | tail -1
  sh /tmp/test-incept-9f.sh   # banner + inception-done
  grep -rniE "enterprise|public.media|bradley" GLOSSARY.md scripts/preflight.sh START-HERE.md || echo "anon clean"
  ```
  Expected: all OK; banner present; anon clean.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer).** Dispatch a reviewer on `git diff main...HEAD`: preflight POSIX correctness (the `IFS=newline` for-loop accumulator, not a subshell pipe; `set -eu` safety on the `tools=$(...)` capture; `--selftest` actually fails on a real regression), incept abort logic (doesn't break `--help` or the noninteractive bootstrap), GLOSSARY link accuracy, solo-track honesty (doesn't misstate the admin-bypass), anonymization. Fix findings.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-9f-beginner-onramp
  gh pr create --base main --head feature/slice-9f-beginner-onramp \
    --title "Slice 9f — Beginner On-Ramp (v2.31.0)" --body-file /tmp/pr-9f-body.md
  ```
  (Write `/tmp/pr-9f-body.md`: A6-aimed scope, the four fixes, the one cp, anonymization.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** Agent never self-merges.

---

## Self-review (against the spec)
- **Spec coverage:** preflight universal+per-stack+selftest (Task 1) · incept abort + rename banner (Task 2) · GLOSSARY (Task 3) · START-HERE preflight/rename/solo/glossary (Task 4) · README + conformance index (Task 5) · CI selftest cp (Task 6) · MINOR 2.31.0 (Task 7) · review + PR (Task 8). All four A6 findings (F1 preflight, F2 rename, F3 glossary, F4 solo) covered.
- **Placeholder scan:** `preflight.sh` is complete real code; the incept edits have exact insertion anchors; GLOSSARY lists the exact 12 terms + homes; the solo-track and notes are full prose. No placeholders.
- **Consistency:** `scripts/preflight.sh` path, the `--selftest` contract, and the `--stack` map are referenced identically across Tasks 1, 2, 5, 6, 8; version 2.31.0 consistent in Task 7.
