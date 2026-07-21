---
status: accepted
---

# Keep Repository scope session-local

GitHubBar will persist Pinned repository membership on each Mac, but the active Repository scope will remain session-local and default to All whenever the app launches.

## Considered options

- Persisting the active All or Pinned scope restores the last view, but can hide work on a later launch without an obvious user action in that session.
- Making both scope and pins transient loses the per-machine configuration that makes Pinned useful.
- Persisting pins while resetting the active scope preserves intentional machine-specific configuration and gives every launch a complete default view.

## Consequences

- Settings stores stable repository IDs and last-known names for Pinned repositories.
- The All and Pinned tabs only re-project the retained Account workload and never trigger Reconciliation.
- GitHubBar launches in All even when the previous session ended in Pinned.
- ADR-0004 remains authoritative for account-wide reconciliation and local filtering, but its persisted-scope statement is superseded by this decision.
