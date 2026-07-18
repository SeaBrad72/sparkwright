# Contributing to Sparkwright

Thanks for your interest — whether you're **reporting a defect**, suggesting an improvement, or sending a change.

## Reporting a defect or giving feedback

Open an issue using one of the templates:

- **🐛 Bug report** — something in the kit doesn't work as documented.
- **💬 Feedback / field report** — friction, a rough edge, or an idea from using the kit on a real project.

Good reports include: what you expected, what happened, the version (`VERSION`), your stack profile and harness (Claude Code, Codex, …), and the smallest steps to reproduce.

## Sending a change

1. **Open an issue first** for anything non-trivial, so we can agree on the approach before you build.
2. Branch with a conventional prefix (`feat/`, `fix/`, `docs/`, …) and use [Conventional Commits](https://www.conventionalcommits.org/).
3. Keep the change **small and vertical**, with tests. The kit is built with its own loop — the same Definition of Done in [`CLAUDE.md`](CLAUDE.md) applies.
4. Run the checks locally before opening the PR:
   ```sh
   sh conformance/verify.sh --require
   ```
5. Open a PR against `main` and fill in the template. A maintainer reviews; **builder ≠ sole reviewer**.

## How the kit is built (for deeper changes)

Sparkwright is a versioned platform product built with the very loop it prescribes. If you're changing its **contracts, reference implementations, or conformance checks**, read **[`MAINTAINING.md`](MAINTAINING.md)** — it explains the contract → reference → conformance convention and the release process.

## Ground rules

Be respectful and constructive — see **[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)**. For security issues, do **not** open a public issue; follow **[`SECURITY.md`](SECURITY.md)**.
