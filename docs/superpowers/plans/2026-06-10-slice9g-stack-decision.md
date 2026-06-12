# Stack-Decision Aid (Slice 9g) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the stack-undecided adopter real comparison material (R7): a comparison matrix + per-profile "Best for / Avoid when," full-stack guidance, and a loud (not silent) `incept` default.

**Architecture:** A new `docs/STACK-SELECTION.md` (matrix + per-stack blurbs + full-stack guidance), a `## Best for / Avoid when` section in each of the 10 profiles, a completeness check (`conformance/stack-selection.sh`) that drift-guards the two, and an `incept` notice when no `--stack` is given. Additive → MINOR v2.32.0.

**Tech Stack:** Markdown + POSIX `sh`. Verified by `stack-selection.sh --selftest`, `dash -n`, `check-links.sh`, `profile-completeness.sh`, and a temp-repo incept run.

---

## Execution notes
- **One control-plane `cp`:** Task 6 (`.github/workflows/ci.yml`). Everything else agent-editable (`conformance/stack-selection.sh` is in `conformance/`, not control-plane; `scripts/incept.sh` editable).
- **Anonymization** ([[kit-anonymization]]): generic throughout.
- **Matrix is opinion-bearing** — keep every "Avoid when" a genuine limitation, not a strawman; fair, not hype.
- **Branch:** `feature/slice-9g-stack-decision` (holds the spec already).

## Canonical per-stack copy (single source — used in BOTH the matrix row and the profile section)

| Stack | Best for | Avoid when | Typical domain/runtime |
|-------|----------|------------|------------------------|
| typescript-node | Full-stack web, APIs, SPAs, serverless; large JS/TS ecosystem; fast iteration | CPU-bound numeric/parallel work; hard real-time; tight memory | Node.js / browser |
| python | Data, ML, scripting, APIs, automation, glue; rapid development | Perf-critical hot loops without native extensions; mobile front-ends | CPython / data stack |
| go | Networked services, CLIs, high-concurrency, single-binary cloud infra | Rich desktop GUIs; heavy data-science/numerics | Go runtime / static binary |
| java-spring | Large transactional enterprise services; mature JVM ecosystem; big teams | Cold-start-sensitive tiny serverless; quick throwaway scripts | JVM |
| kotlin | Modern-language JVM services; Android; Spring with less ceremony | Non-JVM targets; minimal-dependency tiny CLIs | JVM / Android |
| dotnet | C#/Azure enterprise, Windows shops, high-performance services | One-off scripts; teams with no .NET familiarity | .NET runtime |
| rust | Performance- and safety-critical systems, embedded-adjacent, WASM | Rapid CRUD where delivery velocity dominates; exploratory prototyping | Native / WASM |
| ml | Model training/serving, experiments, eval-driven development | Plain web APIs with no ML component | Python ML stack |
| data-engineering | ETL/ELT, batch & stream pipelines, warehouse/lakehouse work | Interactive apps / request-serving APIs | Python data/orchestration |
| terraform | Infrastructure-as-code, cloud provisioning | Application logic — it provisions infra, it is not an app stack (pair with an app profile) | Terraform / cloud |

(Task 1 puts this in the guide matrix; Task 2 puts each row's Best-for/Avoid-when into that profile's section. Same words → no drift; the completeness check enforces presence.)

## File structure

| File | Responsibility |
|------|----------------|
| `docs/STACK-SELECTION.md` (new) | Matrix + per-stack blurbs + full-stack guidance + custom-stack pointer |
| `profiles/<stack>.md` ×10 (modify) | `## Best for / Avoid when` section + guide pointer |
| `conformance/stack-selection.sh` (new) | Completeness drift-guard + `--selftest` |
| `scripts/incept.sh` (modify) | Loud default notice + interactive-prompt pointer |
| `START-HERE.md`, `README.md`, `conformance/README.md` (modify) | Links + index |
| `.github/workflows/ci.yml` (modify, **human cp**) | `stack-selection.sh` step |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.32.0; 9g row → shipped |

---

## Task 1: `docs/STACK-SELECTION.md`

**Files:** Create `docs/STACK-SELECTION.md`

- [ ] **Step 1: Write the guide.** Sections:
  1. Title + one-line purpose ("Choosing a stack profile — compare options, don't guess. The comparison material for START-HERE §2.").
  2. **Comparison matrix** — reproduce the canonical table above verbatim (all 10 rows, 4 columns).
  3. **Per-stack "Best for / Avoid when"** — a short paragraph per stack (the matrix row expanded to 2–3 sentences), each linking to `../profiles/<stack>.md`.
  4. **Full-stack / polyglot (SPA + API)** — guidance: pick a **primary profile per deployable service**; in a monorepo, run `scripts/incept.sh` per service (each gets its own profile + CI) **or** choose the API stack as primary and record the frontend stack in **ADR-000** (`docs/architecture/`). No multi-profile tooling — this is a documentation pattern.
  5. **Don't see your stack?** → `scripts/new-profile.sh <stack>` + `profiles/_TEMPLATE.md` (the existing custom path; link `START-HERE.md` §2 B).
  - Generic, fair, accurate; no hype. ~70–100 lines.

- [ ] **Step 2: Verify + commit.**
  Run: `git add docs/STACK-SELECTION.md && sh conformance/check-links.sh 2>&1 | tail -1` → links resolve (the `../profiles/<stack>.md` links must all exist — they do).
  Run: `grep -niE "enterprise|public.media|bradley" docs/STACK-SELECTION.md || echo clean` → `clean`.
  ```bash
  git commit -m "docs(9g): STACK-SELECTION.md — comparison matrix + per-stack guidance + full-stack pattern"
  ```

---

## Task 2: Per-profile "Best for / Avoid when" sections (all 10)

**Files:** Modify each of `profiles/typescript-node.md`, `python.md`, `go.md`, `java-spring.md`, `kotlin.md`, `dotnet.md`, `rust.md`, `ml.md`, `data-engineering.md`, `terraform.md`

- [ ] **Step 1: Add the section to each profile.** Immediately AFTER the title block / intro and BEFORE `## 1. Toolchain`, insert (using that stack's row from the canonical table):

```markdown
## Best for / Avoid when

**Best for:** <Best-for cell for this stack>.
**Avoid when:** <Avoid-when cell for this stack>.

Choosing a stack? Compare all profiles → [../docs/STACK-SELECTION.md](../docs/STACK-SELECTION.md).
```

Do this for all 10, substituting the matching cells. (Read each profile first to find the exact spot after its title/intro; do not disturb the existing numbered sections.)

- [ ] **Step 2: Verify section + numbering intact, then commit.**
  Run: `for p in profiles/typescript-node profiles/python profiles/go profiles/java-spring profiles/kotlin profiles/dotnet profiles/rust profiles/ml profiles/data-engineering profiles/terraform; do grep -q "Best for / Avoid when" "$p.md" && echo "ok $p" || echo "MISSING $p"; done`
  Expected: `ok` for all 10.
  Run: `sh conformance/profile-completeness.sh >/dev/null 2>&1 && echo "profile-completeness OK"` (the new section must not break the 11-section contract) and `sh conformance/check-links.sh 2>&1 | tail -1`.
  ```bash
  git add profiles/*.md
  git commit -m "docs(9g): per-profile Best-for/Avoid-when sections + guide pointer (10 profiles)"
  ```

---

## Task 3: `conformance/stack-selection.sh`

**Files:** Create `conformance/stack-selection.sh`

- [ ] **Step 1: Write the check** (completeness drift-guard + `--selftest`; uses two separate temp trees in the selftest so it needs no `rm`):

```sh
#!/bin/sh
# stack-selection.sh — completeness drift-guard for the stack-decision aid (Slice 9g / R7).
# Asserts: (a) docs/STACK-SELECTION.md exists; (b) every shipped profiles/<stack>.md has a
# "Best for" + "Avoid when" section; (c) the matrix names every shipped profile. Completeness,
# NOT content-equality (a doc aid, not a security control). A new profile must add a matrix
# row + its own section or this fails.
#   sh conformance/stack-selection.sh [--selftest]
# Exit: 0 = complete · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

GUIDE="docs/STACK-SELECTION.md"
PROFILE_DIR="profiles"

# check_tree <guide> <profile-dir>: print PASS/FAIL lines; return 1 if any gap.
check_tree() {
  guide=$1; pdir=$2; f=0
  if [ ! -f "$guide" ]; then echo "FAIL: missing $guide"; return 1; fi
  for p in "$pdir"/*.md; do
    [ -f "$p" ] || continue
    case "$p" in */_TEMPLATE.md) continue ;; esac
    name=$(basename "$p" .md)
    if grep -qi "best for" "$p" && grep -qi "avoid when" "$p"; then
      echo "PASS: $name has Best-for/Avoid-when"
    else
      echo "FAIL: $name profile missing Best-for/Avoid-when"; f=1
    fi
    # name present in the matrix, bounded so 'go' does not match 'good'
    if grep -Eq "(^|[^a-z])$name([^a-z]|\$)" "$guide"; then
      echo "PASS: matrix names $name"
    else
      echo "FAIL: $guide matrix omits $name"; f=1
    fi
  done
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # (1) a tree with a gap must be DETECTED (check returns non-zero)
  g=$(mktemp -d); mkdir -p "$g/profiles"
  printf '# guide\n\n| okstack | x | y |\n' > "$g/guide.md"
  printf '# gap-stack\n## Toolchain\nno section here\n' > "$g/profiles/gap-stack.md"
  if check_tree "$g/guide.md" "$g/profiles" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap not detected"; sfail=1
  else
    echo "PASS: selftest — missing section / matrix row detected"
  fi
  # (2) an all-good tree must PASS
  ok=$(mktemp -d); mkdir -p "$ok/profiles"
  printf '# guide\n\n| okstack | x | y |\n' > "$ok/guide.md"
  printf '# okstack\n## Best for / Avoid when\nBest for: x. Avoid when: y.\n' > "$ok/profiles/okstack.md"
  if check_tree "$ok/guide.md" "$ok/profiles" >/dev/null 2>&1; then
    echo "PASS: selftest — complete tree passes"
  else
    echo "FAIL: selftest — complete tree wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: stack-selection selftest"; exit 0; } || { echo "FAIL: stack-selection selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: stack-selection.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Stack-selection completeness:"
if check_tree "$GUIDE" "$PROFILE_DIR"; then
  echo "OK: stack-decision aid complete (guide + per-profile sections + matrix rows)"
  exit 0
else
  echo "FAIL: stack-decision aid incomplete (see above)"
  exit 1
fi
```

- [ ] **Step 2: Make executable + dash-check.**
  Run: `chmod +x conformance/stack-selection.sh && dash -n conformance/stack-selection.sh && echo "syntax OK"`

- [ ] **Step 3: Run selftest + real check.**
  Run: `sh conformance/stack-selection.sh --selftest; echo "exit=$?"` → three `PASS …`, `OK: stack-selection selftest`, exit 0.
  Run: `sh conformance/stack-selection.sh; echo "exit=$?"` → after Tasks 1–2, all 10 profiles `PASS` + matrix names each, `OK: …`, exit 0. (If run before Tasks 1–2 land, it correctly FAILs — that's the guard working.)

- [ ] **Step 4: Commit.**
  ```bash
  git add conformance/stack-selection.sh
  git commit -m "feat(conformance): 9g — stack-selection.sh completeness drift-guard (+ --selftest)"
  ```

---

## Task 4: Loud incept default

**Files:** Modify `scripts/incept.sh`

- [ ] **Step 1: Track explicit `--stack`.** In the variable-init area (near `STACK="${INCEPT_STACK:-typescript-node}"`), add:
```sh
STACK_EXPLICIT=0
```
In the `--stack` case arm (currently `--stack) reqval $# --stack; STACK="$2"; shift 2 ;;`), set the flag:
```sh
    --stack) reqval $# --stack; STACK="$2"; STACK_EXPLICIT=1; shift 2 ;;
```

- [ ] **Step 2: Append the guide pointer to the interactive stack prompt.** The line `printf 'Stack [%s]: ' "$STACK"` becomes:
```sh
  printf 'Stack [%s] (compare: docs/STACK-SELECTION.md): ' "$STACK"
```
(If the user types a value here, also set `STACK_EXPLICIT=1` on that branch — i.e. `[ -n "${_s:-}" ] && { STACK="$_s"; STACK_EXPLICIT=1; }`.)

- [ ] **Step 3: Print the loud notice when not explicit.** Immediately AFTER input collection and the existing backlog/ci validation (before `DATE=$(date …)`), add:
```sh
# 9g: never SILENTLY default the stack — make the default choice explicit + pointed.
if [ "$STACK_EXPLICIT" -eq 0 ]; then
  echo "notice: no --stack given — using '$STACK'. Choose deliberately: docs/STACK-SELECTION.md" >&2
fi
```

- [ ] **Step 4: dash-check + functional test** (script form — guard-safe). Write `/tmp/test-incept-9g.sh`:
```sh
#!/bin/sh
set -eu
SRC=~/Development/agentic-sdlc-kit
T=$(mktemp -d); rsync -a --exclude '.git' --exclude 'node_modules' --exclude '.firecrawl' "$SRC"/ "$T"/
cd "$T" && git init -q && git add -A && git -c user.email=ci@x -c user.name=ci commit -qm init
echo "--- no --stack: expect notice ---"
sh scripts/incept.sh --noninteractive --name D --intent-owner O --backlog md 2>&1 | grep -i "no --stack given" && echo "NOTICE OK" || echo "NOTICE MISSING"
echo "--- inception-done ---"; sh conformance/inception-done.sh . >/dev/null 2>&1 && echo "inception-done OK"
T2=$(mktemp -d); rsync -a --exclude '.git' --exclude 'node_modules' --exclude '.firecrawl' "$SRC"/ "$T2"/
cd "$T2" && git init -q && git add -A && git -c user.email=ci@x -c user.name=ci commit -qm init
echo "--- explicit --stack go: expect NO notice ---"
sh scripts/incept.sh --noninteractive --name D --intent-owner O --stack go --backlog md 2>&1 | grep -i "no --stack given" && echo "NOTICE WRONGLY SHOWN" || echo "NO NOTICE (correct)"
```
Run: `dash -n scripts/incept.sh && echo "syntax OK"` then `sh /tmp/test-incept-9g.sh`
Expected: `NOTICE OK`, `inception-done OK`, `NO NOTICE (correct)`.

- [ ] **Step 5: Commit.**
  ```bash
  git add scripts/incept.sh
  git commit -m "feat(9g): incept makes the stack default explicit (loud notice + guide pointer), not silent"
  ```

---

## Task 5: START-HERE §2 link + README + conformance index

**Files:** Modify `START-HERE.md`, `README.md`, `conformance/README.md`

- [ ] **Step 1: START-HERE §2.** In the "## 2. Choose your stack" section, after the "compare options, don't guess" line, add:
```
**Compare the shipped stacks:** [docs/STACK-SELECTION.md](docs/STACK-SELECTION.md) — a matrix of "Best for / Avoid when" plus full-stack (SPA + API) guidance. (Don't see your stack? Generate one — option B below.)
```

- [ ] **Step 2: README.** Near the stack/profiles mention (or the intro), add:
```
Choosing a stack? See [docs/STACK-SELECTION.md](docs/STACK-SELECTION.md).
```

- [ ] **Step 3: conformance/README index row** (4-column table — match the header). After the `stack`… no: after an existing script row (e.g. `profile-completeness.sh`), add:
```markdown
| `stack-selection.sh` | script | Slice 9g / R7 — the stack-decision aid is complete (guide + per-profile Best-for/Avoid-when + a matrix row per profile); drift-guard | CI |
```

- [ ] **Step 4: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add START-HERE.md README.md conformance/README.md
  git commit -m "docs(9g): link STACK-SELECTION from START-HERE §2 + README; conformance index row"
  ```

---

## Task 6: Wire stack-selection into CI (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (build `/tmp` → human applies)

- [ ] **Step 1: Build candidate.** Read `.github/workflows/ci.yml`; copy to `/tmp/ci.yml.9g`; add to the `conformance` job after the `Profile-completeness conformance` step:
```yaml
      - name: Stack-selection completeness (decision aid present + per-profile sections)
        run: sh conformance/stack-selection.sh
      - name: Stack-selection self-test
        run: sh conformance/stack-selection.sh --selftest
```

- [ ] **Step 2: Validate.**
  Run: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.9g"); puts d["jobs"].keys.join(",")' && diff .github/workflows/ci.yml /tmp/ci.yml.9g`
  Expected: `conformance,bootstrap,docs-links`; diff shows only the two added steps.

- [ ] **Step 3: Hand to Bradley to apply.**
  ```bash
  cp /tmp/ci.yml.9g .github/workflows/ci.yml && git add .github/workflows/ci.yml && git commit -m "ci(kit): 9g — gate stack-selection completeness + selftest"
  ```

---

## Task 7: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: `VERSION`** → `2.32.0`.

- [ ] **Step 2: CHANGELOG entry** above `## [2.31.0]`:
  ```markdown
  ## [2.32.0] - 2026-06-10

  Stack-decision aid (Slice 9g, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Closes the stack-undecided persona (review 5/10): the "⭐ key step" now has comparison material, and `incept` no longer silently defaults. **MINOR** — additive docs + a notice + a completeness check.

  ### Added
  - **`docs/STACK-SELECTION.md`** — comparison matrix across all 10 profiles (Best for / Avoid when / domain), per-stack blurbs, and full-stack (SPA + API) / polyglot guidance.
  - **`## Best for / Avoid when`** sections in all 10 `profiles/<stack>.md`, each pointing at the guide.
  - **`conformance/stack-selection.sh`** — completeness drift-guard (guide present · every profile has the section · a matrix row per profile); `--selftest`. CI-gated.

  ### Changed
  - **`incept` no longer silently defaults the stack** — prints a loud notice + the guide pointer when no `--stack` is given (the default still works; automation unaffected).
  - `START-HERE.md` §2 and `README.md` link the decision aid; `conformance/README.md` indexes the check.
  ```

- [ ] **Step 3: roadmap 9g row** — replace it:
  ```markdown
  | **9g** ✅ | B | **Stack-decision aid** (R7) — *shipped v2.32.0.* `STACK-SELECTION.md` (matrix + per-stack Best-for/Avoid-when + full-stack guidance); per-profile sections (×10) drift-guarded by `stack-selection.sh`; incept default now loud-not-silent. | P0¹ | MINOR ✅ |
  ```

- [ ] **Step 4: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1 && cat VERSION`
  ```bash
  git add VERSION CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.32.0 — stack-decision aid (9g)"
  ```

---

## Task 8: Final verification + independent review + PR

- [ ] **Step 1: Full local sweep.**
  ```sh
  sh conformance/stack-selection.sh >/dev/null && echo "stack-selection OK"
  sh conformance/stack-selection.sh --selftest >/dev/null && echo "selftest OK"
  sh conformance/profile-completeness.sh >/dev/null && echo "profile-completeness OK"
  dash -n conformance/stack-selection.sh && dash -n scripts/incept.sh && echo "dash OK"
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/check-links.sh 2>&1 | tail -1
  sh /tmp/test-incept-9g.sh
  grep -rniE "enterprise|public.media|bradley" docs/STACK-SELECTION.md profiles/*.md conformance/stack-selection.sh || echo "anon clean"
  ```
  Expected: all OK; notice shown only without `--stack`; anon clean.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer).** Dispatch a reviewer on `git diff main...HEAD`: (a) `stack-selection.sh` POSIX correctness (the `(^|[^a-z])$name([^a-z]|$)` bound actually prevents `go`/`good` false-positives; `--selftest` is a real test using two trees, no `rm`; `return $f` propagates; `set -eu` safety); (b) the matrix/blurbs are **fair and accurate, not hype** — each "Avoid when" a real limitation; (c) per-profile sections didn't break `profile-completeness.sh`; (d) incept `STACK_EXPLICIT` logic (notice only when truly defaulted; interactive override sets it); (e) anonymization. Fix findings.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-9g-stack-decision
  gh pr create --base main --head feature/slice-9g-stack-decision \
    --title "Slice 9g — Stack-Decision Aid (v2.32.0)" --body-file /tmp/pr-9g-body.md
  ```
  (Write `/tmp/pr-9g-body.md`: the comparison aid, per-profile sections + drift guard, loud default, one cp.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** Agent never self-merges.

---

## Self-review (against the spec)
- **Spec coverage:** STACK-SELECTION matrix + blurbs + full-stack (Task 1) · per-profile sections ×10 (Task 2) · completeness drift-guard + selftest (Task 3) · loud incept default (Task 4) · START-HERE/README/conformance links (Task 5) · CI cp (Task 6) · MINOR 2.32.0 (Task 7) · review (fairness) + PR (Task 8). All four R7 pieces (matrix, per-profile, full-stack, stop-silent-default) covered.
- **Placeholder scan:** the canonical 10-stack table is concrete; `stack-selection.sh` is complete code; incept edits have exact anchors; CHANGELOG/roadmap text is final. No placeholders.
- **Consistency:** the canonical per-stack copy is the single source for both the matrix (Task 1) and the profile sections (Task 2); `stack-selection.sh`/`STACK_EXPLICIT` referenced identically across Tasks 3, 4, 6, 8; version 2.32.0 consistent in Task 7.
