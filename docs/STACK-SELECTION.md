# Choosing a Stack Profile

**Compare options, don't guess.** This is the comparison material for [START-HERE](../START-HERE.md) §2 — pick the profile that fits the work, with each stack's honest strengths and limits side by side.

A stack profile is the concrete *how* for one deployable service: its toolchain, commands, and quality bar. Choose deliberately at Inception. The default works, but it should be a choice, not an accident.

Part of the kit's [neutrality-by-construction](adoption/neutrality-by-construction.md) requirement.

---

## Comparison matrix

| Stack | Best for | Avoid when | Typical domain/runtime |
|-------|----------|------------|------------------------|
| typescript-node | Full-stack web, APIs, SPAs, serverless; large JS/TS ecosystem; fast iteration | CPU-bound numeric/parallel work; hard real-time; tight memory | Node.js / browser |
| python | Data, ML, scripting, APIs, automation, glue; rapid development | Perf-critical hot loops without native extensions; mobile front-ends | CPython / data stack |
| go | Networked services, CLIs, high-concurrency, single-binary cloud infra | Rich desktop GUIs; heavy data-science/numerics | Go runtime / static binary |
| ml | Model training/serving, experiments, eval-driven development | Plain web APIs with no ML component | Python ML stack |
| terraform | Infrastructure-as-code, cloud provisioning | Application logic — it provisions infra, it is not an app stack (pair with an app profile) | Terraform / cloud |
| java-spring | Large transactional enterprise services; mature JVM ecosystem; big teams | Cold-start-sensitive tiny serverless; quick throwaway scripts | JVM |
| kotlin | Modern-language JVM services; Android; Spring with less ceremony | Non-JVM targets; minimal-dependency tiny CLIs | JVM / Android |
| dotnet | C#/Azure enterprise, Windows shops, high-performance services | One-off scripts; teams with no .NET familiarity | .NET runtime |
| rust | Performance- and safety-critical systems, embedded-adjacent, WASM | Rapid CRUD where delivery velocity dominates; exploratory prototyping | Native / WASM |
| data-engineering | ETL/ELT, batch & stream pipelines, warehouse/lakehouse work | Interactive apps / request-serving APIs | Python data/orchestration |

The four columns above — **Stack · Best for · Avoid when · Typical domain/runtime** — are **the stack card**: one uniform, side-by-side record per option. This matrix is the single source of truth for the cards; each `profiles/<stack>.md` links back here rather than restating them.

**References, not tiers.** All ten are **copy-and-adapt reference starting points held to the same
structural conformance bar** — the eight required gate ids (`conformance/ci-gates.sh`, applied fleet-wide by
`profile-completeness.sh`), SHA-pinned actions (`action-pinning.sh`), and workflow lint
(`actionlint-valid.sh`). **None is advertised as more-exercised or more-proven than another** — the kit's
answer to *"which stack?"* is **the loop handles any of them** (these ten, or any other you generate). Pick
by fit, adapt the reference, and let the loop hold the quality bar.

**"Structurally conformant" is not "observed green on a first run."** Budget for a first-run fix on **any**
stack and report what you hit — a real first-run failure of exactly this kind (an emitted step calling a
sensor subcommand that did not exist) is what the kit's own one-time verify sweep exists to catch. **SAST is
not part of the required bar:** the required set has no `gate-sast`, and only `typescript-node` and
`java-spring` (semgrep) and `go` (gosec) emit one — the other seven ship a secret scan and a vulnerability
scan, which are not the same thing.

**Three profiles ship no runnable scaffold** (`ml`, `data-engineering`, `terraform`): they are references
plus guidance, and the loop builds the scaffold. That is simply what those references are — not a
lesser tier.

Related enforcement boundary: the **runtime-version floor** is enforced at install time only for
npm-based stacks (`engine-strict` in the TypeScript scaffolds). Of the rest, the five that declare a floor
(`go`, `python`, `dotnet`, `java-spring`, `kotlin` — `go.mod`, `requires-python`, `pom.xml`, …) rely on
toolchains that do **not** hard-enforce it on install;
`rust`, `ml`, `terraform` and `data-engineering` declare **no** runtime floor at all (`rust` ships
edition-only). Check your runtime matches the profile before you debug anything stranger.

---

## How to derive the recommendation

Don't pick by familiarity or reputation — **derive** the recommendation from the shape of the work.
Score the problem on these **fit dimensions**, then read across to the stack whose strengths match:

- **Workload** — CPU-bound / systems / hard real-time vs IO-bound / concurrent / request-serving.
- **Ecosystem / libraries** — is the decisive library or framework native to one stack?
- **Team skills** — what the people who will own it already know.
- **Deploy target** — serverless / cold-start-sensitive, container, single-binary, managed cloud.
- **Data / ML** — heavy numerics, model training/serving, pipelines.
- **Compliance / regulatory** — constraints on runtime, provenance, or ecosystem.
- **Latency / cold-start**, **scale / throughput**, **interop / platform** (Android, Windows/Azure,
  WASM, embedded, GPU).

### Steer-away table

| If the work is… | Steer to | Away from the default when |
|---|---|---|
| CPU-bound / systems / hard real-time | `go`, `rust` | numeric/parallel/tight-memory |
| JVM enterprise / large transactional / big team | `java-spring`, `kotlin` | quick scripts / tiny serverless |
| data / ML / heavy numerics | `python`, `ml` | plain web APIs |
| IaC / cloud provisioning | `terraform` (+ app profile) | application logic |
| ETL / batch & stream pipelines | `data-engineering` | request-serving APIs |
| shared-JS full-stack / API / SPA, fast iteration | `typescript-node` | CPU-bound / hard real-time |

**Proven-ness is not a valid justification — cite fit.** "It's the default / most-exercised / safest"
is a *maturity* statement, not a *fit* reason. The recorded decision must cite at least one fit
dimension above; this is enforced by
[`conformance/stack-decision-integrity.sh`](../conformance/stack-decision-integrity.sh) against the
ADR-000 **`## Fit rationale`** field.

**Honest ceiling.** The check proves a fit reason is *articulated* (present, non-empty,
non-placeholder, names ≥1 fit dimension) — it **cannot** prove the choice was *correct*. That
judgment stays with the reviewer's / owner's Go/No-Go.

> This applies the **Neutrality pattern (instance #1: stack)** — the reusable, axis-agnostic shape
> (comparable cards · fit-driven selection · anti-bias lint) documented
> in [DEVELOPMENT-STANDARDS.md §1 (Neutrality by construction)](../DEVELOPMENT-STANDARDS.md#neutrality-by-construction-standing-requirement).
> Deploy-target (KW5) is instance #2; harness/model (KW9) is the next instance of the same pattern.
> Unlike those axes, the **stack** axis carries **no maturity tier** — every profile is a copy-and-adapt
> reference held to the same bar, so there is a fit rationale to record but no maturity ranking to disclose.

---

## Environments & backing services

Picking a stack also implies *which environments and backing services* you need. Each service
profile ships a `compose.yaml` matching its **default archetype** as a **COPY-&-ADAPT reference** —
`scripts/incept.sh` points you at it but does **not** copy it (auto-copying the container files would
make `docker build` fail on the bare `/healthz` starter; you adapt them when you containerize, which
activates the image-build CI gates). Start from this and add only what your feature needs — each
profile's **"Environments this stack needs"** section has the per-stack detail.

| Stack | Default archetype | Shipped `compose.yaml` | Typical services to add |
|-------|-------------------|------------------------|-------------------------|
| typescript-node | DB-backed service | app + Postgres | Redis (cache/session), object store |
| python | DB-backed service | app + Postgres | Redis, object store, task queue |
| go | **Stateless** service | app only | DB / Redis only if needed |
| rust | **Stateless** service | app only | DB / Redis only if needed |
| java-spring | DB-backed service | app + Postgres | Redis, message broker (Kafka/Rabbit) |
| kotlin | DB-backed service | app + Postgres | Redis, message broker |
| dotnet | DB-backed service | app + Postgres | Redis, Azure Service Bus |
| ml | Serving / batch | reference-only (no generic compose) | model/feature store, vector DB |
| data-engineering | Batch / pipeline | reference-only | warehouse, object store, orchestrator |
| terraform | Provisions infra (not an app) | — | — |

**Archetype coverage.** The auto-incepted `profiles/<stack>/scaffold/` starters cover the **service**
archetypes (stateless / db-backed). For a **CLI** tool, the reference is
[`profiles/typescript-node/scaffold-cli/`](../profiles/typescript-node/scaffold-cli/) — copy it instead
of the service scaffold. For **batch/worker**, adapt a service or CLI scaffold to your trigger.

**Environment promotion.** Run each environment Dev → QA → UAT → Prod with gated promotion;
**production is always human-gated** (DEVELOPMENT-PROCESS.md env model). Whether you *already have*
an environment or need to *stand one up*, record the approach in your RUNBOOK §1 and §4.

---

## Per-stack guidance

### typescript-node → [../profiles/typescript-node.md](../profiles/typescript-node.md)
Best for full-stack web, APIs, SPAs, and serverless, with the largest package ecosystem and fast iteration. The trade-off is the single-threaded event loop: CPU-bound numeric or parallel work, hard real-time, and tight-memory targets fight the runtime rather than fit it. Reach for it when shared JS/TS across client and server is the win.

### python → [../profiles/python.md](../profiles/python.md)
Best for data work, ML, scripting, APIs, automation, and glue code, with rapid development and a deep library ecosystem. Performance-critical hot loops are slow without native extensions, and it is not a fit for mobile front-ends. Choose it when readability and breadth of libraries matter more than raw per-core speed.

### go → [../profiles/go.md](../profiles/go.md)
Best for networked services, CLIs, high-concurrency workloads, and single-binary cloud infrastructure, with fast builds and easy deployment. It is a poor fit for rich desktop GUIs and heavy data-science or numerics, where the ecosystem is thin. Pick it when you want predictable concurrency and a static binary to ship.

### java-spring → [../profiles/java-spring.md](../profiles/java-spring.md)
Best for large transactional enterprise services with a mature JVM ecosystem and big teams that benefit from established conventions. JVM start-up cost makes it awkward for cold-start-sensitive tiny serverless functions and for quick throwaway scripts. Choose it when long-lived, heavily-integrated business systems are the goal.

### kotlin → [../profiles/kotlin.md](../profiles/kotlin.md)
Best for modern-language JVM services, Android, and Spring with less ceremony than Java, keeping JVM interop and tooling. It does not target non-JVM platforms, and it is overkill for minimal-dependency tiny CLIs. Reach for it when you want the JVM ecosystem with a more concise, expressive language.

### dotnet → [../profiles/dotnet.md](../profiles/dotnet.md)
Best for C#/Azure enterprise work, Windows-centric shops, and high-performance services on a unified runtime. It is heavyweight for one-off scripts and a steep ramp for teams with no prior .NET familiarity. Choose it when the Microsoft ecosystem or first-class Azure integration is already part of the picture.

### rust → [../profiles/rust.md](../profiles/rust.md)
Best for performance- and safety-critical systems, embedded-adjacent code, and WASM targets, with memory safety enforced at compile time. The ownership model and compile times slow rapid CRUD work where delivery velocity dominates and exploratory prototyping. Pick it when correctness and performance justify a steeper authoring cost.

### ml → [../profiles/ml.md](../profiles/ml.md)
Best for model training and serving, experiment tracking, and eval-driven development, layering ML practices on a Python base. It adds no value for plain web APIs that have no ML component — use python or another app profile there. Choose it when models, datasets, and evals are first-class parts of the deliverable.

### data-engineering → [../profiles/data-engineering.md](../profiles/data-engineering.md)
Best for ETL/ELT, batch and stream pipelines, and warehouse or lakehouse work, with orchestration and data-quality practices built in. It is not aimed at interactive apps or request-serving APIs, which have different latency and lifecycle needs. Reach for it when moving and shaping data is the product.

### terraform → [../profiles/terraform.md](../profiles/terraform.md)
Best for infrastructure-as-code and cloud provisioning, with declarative state and plan/apply discipline. It is not an application stack — it provisions infrastructure rather than running application logic, so pair it with an app profile rather than using it alone. Choose it to manage the cloud resources your services run on.

---

## Full-stack / polyglot (SPA + API)

Most real systems span more than one stack — a TypeScript SPA in front of a Go or Java API, say. The kit models this as a **documentation pattern, not new tooling**: there is one primary profile per deployable service.

Two ways to record it:

- **Monorepo, one profile per service** — run [`scripts/incept.sh`](../scripts/incept.sh) once per deployable service (e.g. `web/` and `api/`). Each service gets its own profile and its own CI, and is governed independently.
- **One primary + an ADR** — choose the API stack as the primary profile and record the frontend stack in **ADR-000** under `docs/architecture/`, so the second stack is documented and visible even though it isn't a separate profile.

Either way, there is no multi-profile mechanism to learn — you are composing the existing single-profile path.

---

## Don't see your stack?

Generate one. Run [`scripts/new-profile.sh`](../scripts/new-profile.sh) `<stack>` and fill in [`profiles/_TEMPLATE.md`](../profiles/_TEMPLATE.md) — this is option B in [START-HERE](../START-HERE.md) §2 ("Choose your stack"). The template carries the same 11-section contract every shipped profile satisfies, so a custom stack inherits the same quality bar.
