# E4 — Agent sandbox: hardened + writable across all container profiles

**Status:** Design approved 2026-06-23 (owner-ratified; scope expanded from the ts-node-only `/work` fix to
all-7-profile parity — owner directed the fold). Closes the E4a `/work` follow-up **and** the
agent-sandbox profile-parity gap.
**Tracked here** (not `docs/superpowers/specs/`) per the C7 lesson.

---

## 0. Context

E4a proved the reference `agent` sandbox *contains* but surfaced it can't **write** `/work` on Linux:
the `agent` service builds `target: builder` (root, no `USER`), and `cap_drop: [ALL]` strips
**DAC_OVERRIDE**, so root can't write a host-owned bind mount (works on Docker-Desktop/Mac via
fakeowner). E4a demoted the `/work` positive control to an informational line.

Recon for this fix surfaced a second gap: **only `typescript-node` ships the hardened `agent`
sandbox** — it was added in H2a (v3.8.0) to the maintainer-verified reference profile and never
propagated. The other six container profiles' `compose.yaml` carry only `app`/`db`. Owner directed
folding the parity fix in: every container profile should ship the agent sandbox (the containment
safety floor for any stack, and the safe area E3's agents will work in).

This slice does both: **fix `/work` writability** (host-uid mapping) **and propagate the hardened
sandbox to all 7 container profiles.**

---

## 1. Owner-ratified decisions

1. **Fix `/work`:** add a host-uid `user:` mapping to the `agent` service (keeps all containment).
2. **Parity:** provide the hardened `agent` sandbox in **all 7** container profiles' `compose.yaml`.
3. **Proof model:** **provide for all, prove on the reference** — behaviourally prove only `typescript-node`
   via `containment-audit` (as today); the other six are **reference configs**, consistent with how
   the kit already treats every per-profile artifact (Dockerfile, `ci.yml`, compose `app`/`db`). No
   new static lock (owner chose this over the static-lock-all-7 option).
4. **One combined slice.**

**Recon de-risks the parity:** all 7 builder stages are named `builder` and are Debian/Ubuntu-based
**with `bash`** (`dotnet/sdk:8.0`, `golang:1.22-bookworm`, `eclipse-temurin:21-jdk` ×2,
`python:3.12-slim-bookworm`, `rust:1-bookworm`, `node:24-bookworm-slim`). So the agent block is
**near-uniform** — same hardening + `command: ["bash"]`; the only per-stack variance (build cache
dir) is covered uniformly by `HOME=/tmp` (tools default caches under `$HOME` → tmpfs).

---

## 2. The agent sandbox block (added to all 7 `profiles/*/compose.yaml`, agent-editable)

Uniform across profiles (ts-node already has most of it — gains the `user:` line; the other six get
the whole service). Per the existing ts-node reference, with the two changes in **bold**:

```yaml
  # --- Agent sandbox (containment reference — docs/operations/containment.md §1) ---
  # Headless agent/dev shell, host UNREACHABLE: read-only root, ONLY the work tree mounted, all caps
  # dropped, no-new-privileges, no network. Opt-in; never auto-started. Run as the HOST uid so the
  # work-tree bind mount is writable under cap_drop:[ALL] (which strips DAC_OVERRIDE):
  #     HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose --profile agent run --rm agent
  agent:
    build: { context: ., target: builder }
    profiles: [agent]
    read_only: true
    network_mode: none
    cap_drop: [ALL]
    security_opt: [ no-new-privileges:true ]
    tmpfs: [ /tmp ]
    volumes: [ "./:/work:rw" ]
    working_dir: /work
    user: "${HOST_UID:-1000}:${HOST_GID:-1000}"   # ← the /work fix (host-uid owns the mount)
    environment:
      HOME: /tmp                                   # ← uniform: tool caches land on tmpfs, not read-only root
    command: ["bash"]
```

ts-node keeps its `npm_config_cache: /tmp/.npm` (additive). The other six use `HOME: /tmp` (covers
go/rust/python/java/dotnet tool caches, all of which default under `$HOME`). Each profile's existing
`app`/`db` services are untouched; `docker compose up` still ignores the opt-in `agent` profile.

**Why `HOST_UID`/`HOST_GID`, not `UID`/`GID`:** bash's `UID` is a readonly builtin (`UID=$(id -u)
docker compose …` errors) and `GID` is often unset. Custom names avoid the clash; the `:-1000`
default keeps a plain run working (and Mac fakeowner makes 1000 fine there).

---

## 3. Re-promote the `/work` positive + prove on ts-node

### 3.1 `scripts/containment-audit.sh` (control-plane)
- `export HOST_UID="$(id -u)" HOST_GID="$(id -g)"` before the `docker compose --profile agent
  build/run`, so the agent runs as the caller (works in CI and for adopters).
- Change the `/work` probe from the E4c **INFO** line back to a **gated POSITIVE** (`POS fs-work:
  PASS` — write to `/work` must succeed), re-added to the required-marker gate; update the SCOPE
  comment (writable via the host-uid mapping).

### 3.2 `conformance/containment-audit-wired.sh` (control-plane)
Re-add the `POS fs-work` token + a selftest fixture so a runner that regresses `/work` to INFO/neg-only
fails the lock.

### 3.3 Proof
The `containment-audit` golden-path job (ts-node, Linux) now prints **`POS fs-work: PASS`** — the
agent writes `/work` running as the runner uid — **while every containment negative still passes**
(read-only root, `/etc`, host-unreachable, egress ENETUNREACH, caps `mknod` EPERM — all
uid-independent; `mknod` still denied as non-root). Local docker red-green on Mac confirms. CI Linux
is canonical. The six other sandboxes are provided (reference configs), proven on the reference.

---

## 4. Docs

`docs/operations/containment.md` — document the `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose
--profile agent run --rm agent` invocation + rationale (write the work tree under `cap_drop:[ALL]`
without weakening containment), and that the agent sandbox now ships in **all container profiles**
(provided for all, behaviourally proven on the ts-node reference).

---

## 5. Footprint & verification

- **Control-plane → AMBER** (flat `/tmp` scratch → `apply.py` → **security-review-of-scratch**):
  `containment-audit.sh`, `containment-audit-wired.sh`. (Security review confirms the `user:` mapping
  weakens no containment negative and the re-promotion has no vacuous hole.)
- **Agent-editable on-branch:** 7× `profiles/*/compose.yaml`, `docs/operations/containment.md`,
  VERSION 3.46.0, CHANGELOG, README badge, `docs/ROADMAP-KIT.md`.
- **No new claim** (re-promotion within `containment-audit`; claims stay 28).
- **Per-stack correctness diligence:** the build verifies each builder stage is `builder`-named +
  bash-present (all confirmed Debian/Ubuntu-based in recon) so the 6 new configs are valid, not
  broken-on-arrival — the honest minimum for "reference config" without a formal lock.
- **apply.py invariants:** explicit ROOT, idempotent, atomic, fail-loud anchors, mode-preserve 0755.
- **DoD:** containment-audit job GREEN on PR + main with `POS fs-work: PASS` + all negatives;
  `containment-audit-wired.sh --selftest` green; 7 compose files valid (`docker compose config`
  parses each); `verify --require` OK; `doctor` PASS; builder ≠ reviewer + security-review-of-scratch
  APPROVE; merge landed verified.

---

## 6. E4 decomposition (updated)

| Slice | Status |
|---|---|
| E4a / E4b / E4a′ / E4c | ✅ (v3.42.0 / v3.43.0 / v3.44.0 / v3.45.0) |
| **agent sandbox: hardened + writable across all 7 profiles (this)** | **building** — closes the E4a `/work` follow-up + the sandbox-parity gap |
| E4e — R2 bot-identity ratification gate | next candidates |
| E4f — G8 per-segment guard | (delicate; standalone session) |
| E4d — cost/runaway kill-switch | deferred to land with E3 |

E3 (orchestration) builds after E4. Order: E2 ✓ → E4 → E3 → E1/E5/E6.
