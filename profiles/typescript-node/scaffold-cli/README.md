# typescript-node — CLI archetype reference

A **non-service** starter: a command-line tool (`app [--name <name>] [--stdin]`), authored to the
typescript-node `ci.yml` contract; its npm steps (`npm ci → lint → type-check → test → build`) were **run green locally**.

**Not auto-incepted.** `scripts/incept.sh` copies the default service starter (`../scaffold/`,
a `/healthz` service). When you are building a **CLI** instead, copy *this* directory's contents
into your project root and delete the service scaffold. There is no `/healthz`, no `compose.yaml`,
and no `Dockerfile` — a CLI has no backing services.

## Shape
- `src/greet.ts` — the pure, unit-tested core (`greet(name)`).
- `src/bounded-input.ts` — the pure, unit-tested **input boundary** (`readBoundedInput` /
  `boundAndValidate`). The reference for reading **untrusted** input safely (see below).
- `src/cli.ts` — the entrypoint: parses `--name` / `--stdin` / `--help`, prints, exits. Does the I/O,
  so it is excluded from coverage (the service scaffold excludes `server.ts` the same way).
- `bin` (`package.json`) → `dist/cli.js`, so `npm link` / `npx` exposes the `app` command.

## Hardened input boundary (the reference pattern)
`app --stdin` reads a name from standard input through `readBoundedInput`. Copy that module whenever you
read untrusted text (stdin, a file, an argument). It encodes three rules a naïve boundary gets wrong:
- **Reject, don't strip.** A forbidden terminal-control byte (C0/C1/DEL, except tab/newline/CR) throws
  `ControlByteError` — an ANSI screen-clear must never flow through to `git log` or your output. A linter
  that fixes the *output* but accepts the *input* has fixed nothing.
- **Truncate at a code-point boundary.** Bounding by raw UTF-16 units (`str.slice(0, n)`) can split a
  surrogate pair and leave a **lone surrogate** (malformed, `encodeURIComponent` throws). The walk stops
  before a code point that would exceed the cap, so a 2-unit emoji at the edge is dropped whole.
- **Bound the read.** Consumption stops at the cap, so an open/infinite producer never drains; the source
  iterator is cleaned up (`.return()`).

## See it run
```sh
npm ci && npm run build
node dist/cli.js --name Ada     # Hello, Ada!
echo Ada | node dist/cli.js --stdin   # Hello, Ada! (bounded, control-byte-rejected read)
```

For other shapes: **batch/worker** = adapt this CLI (swap the argv parse for a scheduler/queue
trigger); **service** = use `../scaffold/`. See `docs/STACK-SELECTION.md` for the archetype map.
