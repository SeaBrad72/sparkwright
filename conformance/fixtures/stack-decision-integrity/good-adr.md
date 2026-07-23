# ADR-000: Technology Stack Selection
**Status:** Accepted
## Decision
Use **Go**, captured in `profiles/go.md`.
## Fit rationale
The service is a high-concurrency, IO-bound networking API where predictable
goroutine concurrency and a single-binary deployment matter more than raw
per-core numeric throughput. The team has Go experience and the deploy target
is a container platform.
