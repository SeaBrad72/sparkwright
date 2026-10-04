# Fixture charter (TBG-RECORD-GATES-BIND)

Deliverable fixture tree (design §2 scope D / §8.2): a `jira`-declaring tree with NO
`BACKLOG.md` — the treeless proof (§3, §6b R2). Consumed directly by
`conformance/loop-state.sh --selftest`'s tracker-arm legs via `SEAM_ROOT` pointed at
`tracker-jira/`; the SEAM_RECORD content itself is generated AT TEST TIME (never a tracked
file here) because a record's `read-day`/`pin`/`head` fields must be fresh/consistent with
whatever `.kit/tracker.conf` bytes this directory carries at the moment of the test — a
tracked record file would go stale (L-2's today/yesterday window) or drift (M-1's pin digest)
the day either side changed without the other.

- **Backlog backend**: Jira
