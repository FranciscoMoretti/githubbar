---
status: superseded
superseded-by: 0005-keep-repository-scope-session-local.md
---

# Reconcile the account workload and filter locally

GitHubBar will reconcile one account-wide workload containing every open Review request and Authored pull request visible through the Monitored account's Access coverage. Repository scope is a device-local presentation filter over that workload; changing it does not perform network work. ADR-0005 supersedes the persistence part of this decision.

## Considered options

- Scope-bound Snapshots reduce data fetched when a Mac only cares about one repository, but moving between scopes requires another Reconciliation and cannot immediately reveal data that was excluded from the previous Snapshot.
- A coverage-aware per-repository store could fetch missing slices on demand while retaining prior slices, but it adds Snapshot-coverage and invalidation states that the MVP does not otherwise need.
- An account-wide Snapshot costs more on narrowly scoped Macs, but keeps the selector instant, makes its behavior independent of GitHub latency, and has been validated against the MVP target of 500 open pull requests.

## Consequences

- The GitHub workload interface has no Repository-scope input, so every Reconciliation produces a canonical account-wide Snapshot.
- Repository-scope changes only re-project the current Snapshot into the Active workload and Review count.
- The Snapshot schema advances to version 2. Earlier scope-bound Snapshots are discarded rather than being mistaken for complete account-wide data.
- GitHub GraphQL search exposes at most 1,000 results for a search. Before the Account workload can approach that ceiling, discovery must detect it and partition searches without changing the Repository-scope interaction model.
