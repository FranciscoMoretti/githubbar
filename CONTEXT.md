# GitHubBar

GitHubBar is a standalone native macOS menu-bar product for keeping high-volume GitHub work visible and actionable without repeatedly navigating GitHub's web interface.

## Language

**GitHubBar**:
The standalone product being designed in this repository; CodexBar is a design and architectural reference, not a host application or upstream codebase.
_Avoid_: CodexBar plugin, CodexBar feature

**Monitored account**:
The single authenticated GitHub account whose accessible repositories supply GitHubBar's pull-request workload. Organization and repository filters may mute parts of that workload.
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
An open pull request authored by the monitored account. Non-drafts and drafts appear in separate lists.
_Avoid_: Outgoing PR

**Waiting for my review**:
The list of open, non-draft pull requests with a current direct or team review request for the monitored account.
_Avoid_: Review inbox, unread reviews

**My PRs**:
The list of open, non-draft authored pull requests, without inferred workflow or readiness classification.
_Avoid_: Ready PRs, submitted PRs

**Drafts**:
The list of open authored pull requests that are currently drafts, shown separately below My PRs.
_Avoid_: Work in progress

**Review roster**:
The people and teams requested to review a pull request, plus people who have already submitted a review. It exists to make reviewer coverage visible, not to classify the pull request's workflow.
_Avoid_: Reviewer list, assignees, participants

**Active workload**:
The pull requests in Waiting for my review, My PRs, and Drafts, potentially spanning hundreds of pull requests under a target throughput of 100 pull requests per day.
_Avoid_: Inbox, feed, history

**Reconciliation**:
A complete network refresh that rediscovers Waiting for my review, My PRs, and Drafts and hydrates their row and review-roster data.
_Avoid_: Sync, poll, incremental update

**Snapshot**:
An account-bound, timestamped representation of the active workload, including whether the reconciliation that produced it was complete or partial.
_Avoid_: Cache, response, feed

**Refresh health**:
Whether the most recent reconciliation completed, produced partial data, or failed while an older snapshot remains usable. It is independent of the account connection and access coverage.
_Avoid_: Account status, access status
