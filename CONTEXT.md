# GitHubBar

GitHubBar is a standalone native macOS menu-bar product for keeping high-volume GitHub work visible and actionable without repeatedly navigating GitHub's web interface.

## Language

**GitHubBar**:
The standalone product being designed in this repository; CodexBar is a design and architectural reference, not a host application or upstream codebase.
_Avoid_: CodexBar plugin, CodexBar feature

**Monitored account**:
The single authenticated GitHub account whose accessible repositories supply GitHubBar's pull-request workload. Repository scope selects the subset relevant on this Mac.
_Avoid_: User, identity, profile

**Account connection**:
The authenticated relationship through which GitHubBar observes the monitored account's accessible pull-request workload. Its credential health and its access coverage are independent.
_Avoid_: Login, token, authentication

**Access coverage**:
The organizations and repositories visible to GitHubBar through the account connection. Successful authentication does not guarantee complete access coverage.
_Avoid_: Permissions, login status, refresh health

**Account connection required**:
The condition in which GitHubBar cannot observe an active workload because GitHub CLI is missing or no usable authenticated CLI session is available.
_Avoid_: Logged out, refresh failed

**Review request**:
An open pull request on which the monitored account or one of its teams currently has an explicit GitHub review request. Mere mentions, subscriptions, assignments, and past participation do not qualify.
_Avoid_: Notification, incoming PR, unread PR

**Authored pull request**:
An open pull request authored by the monitored account. Ready and draft pull requests share the My PRs list.
_Avoid_: Outgoing PR

**Waiting for my review**:
The list of open, non-draft pull requests with a current direct or team review request for the monitored account.
_Avoid_: Review inbox, unread reviews

**My PRs**:
The list of all open authored pull requests, ordered by recent activity. Draft status is shown on the pull request itself rather than creating another list.
_Avoid_: Ready PRs, submitted PRs

**Draft pull request**:
An authored pull request whose current GitHub state is draft. It remains a normal member of My PRs with a draft status marker.
_Avoid_: Drafts list, work in progress

**Review roster**:
The people and teams requested to review a pull request, plus people who have already submitted a review. An empty roster stays empty rather than becoming a separate warning or workflow state.
_Avoid_: Reviewer list, assignees, participants

**Repository scope**:
The device-local set of accessible repositories included in the active workload. It controls reconciliation, visible pull requests, and the review count, and defaults to all accessible repositories.
_Avoid_: Mute list, notification filter

**Review count**:
The number of pull requests in Waiting for my review under the current Repository scope. It is GitHubBar's only proactive attention signal in the MVP.
_Avoid_: Unread count, notification count

**Active workload**:
The pull requests in Waiting for my review and My PRs under the current Repository scope, potentially spanning hundreds of pull requests under a target throughput of 100 pull requests per day.
_Avoid_: Inbox, feed, history

**Reconciliation**:
A complete network refresh that rediscovers Waiting for my review and My PRs and hydrates their row and review-roster data.
_Avoid_: Sync, poll, incremental update

**Snapshot**:
An account-bound, timestamped representation of the active workload, including whether the reconciliation that produced it was complete or partial.
_Avoid_: Cache, response, feed

**Refresh health**:
Whether the most recent reconciliation completed, produced partial data, or failed while an older snapshot remains usable. It is independent of the account connection and access coverage.
_Avoid_: Account status, access status
