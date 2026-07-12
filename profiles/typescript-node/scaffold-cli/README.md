# typescript-node — CLI archetype reference

A **non-service** starter: a command-line tool (`app [--name <name>]`), authored to the
typescript-node `ci.yml` contract; its npm steps (`npm ci → lint → type-check → test → build`) were **run green locally**.

**Not auto-incepted.** `scripts/incept.sh` copies the default service starter (`../scaffold/`,
a `/healthz` service). When you are building a **CLI** instead, copy *this* directory's contents
into your project root and delete the service scaffold. There is no `/healthz`, no `compose.yaml`,
and no `Dockerfile` — a CLI has no backing services.

## Shape
- `src/greet.ts` — the pure, unit-tested core (`greet(name)`).
- `src/cli.ts` — the entrypoint: parses `--name` / `--help`, prints, exits. Does the I/O, so it
  is excluded from coverage (the service scaffold excludes `server.ts` the same way).
- `bin` (`package.json`) → `dist/cli.js`, so `npm link` / `npx` exposes the `app` command.

## See it run
```sh
npm ci && npm run build
node dist/cli.js --name Ada   # Hello, Ada!
```

For other shapes: **batch/worker** = adapt this CLI (swap the argv parse for a scheduler/queue
trigger); **service** = use `../scaffold/`. See `docs/STACK-SELECTION.md` for the archetype map.
