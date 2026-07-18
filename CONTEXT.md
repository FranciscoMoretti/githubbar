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
An open pull request authored by the monitored account. Its Draft state, aggregate Review decision, and Outstanding review requests determine its Authored workflow section.
_Avoid_: Outgoing PR

**Needs your review**:
The list of open, non-draft pull requests with a current direct or team review request for the monitored account.
_Avoid_: Waiting for my review, review inbox, unread reviews

**My PRs**:
The collective Authored pull requests visible across Returned to you, Needs reviewers, Waiting for reviewers, Approved, and Drafts.
_Avoid_: Ready PRs, submitted PRs

**Draft pull request**:
An Authored pull request whose current GitHub state is draft. Drafts take precedence over Review decision when assigning the Authored workflow section.
_Avoid_: Work in progress

**Review decision**:
GitHub's aggregate review status for an Authored pull request: approved, changes requested, review required, or absent.
_Avoid_: Review status, reviewer state

**Outstanding review request**:
A current request for a person or team to review an Authored pull request. It is distinct from the Review roster because completed reviewers remain visible in the roster.
_Avoid_: Reviewer, review participant

**Authored workflow section**:
The single actionable section assigned to an Authored pull request when its Draft state, Review decision, and Outstanding review requests are known.
_Avoid_: Lifecycle status, PR bucket

**Returned to you**:
The Authored workflow section for non-draft pull requests whose Review decision is changes requested.
_Avoid_: Changes requested

**Needs reviewers**:
The Authored workflow section for non-draft pull requests with no Review decision and no Outstanding review requests.
_Avoid_: No reviewers, unassigned

**Waiting for reviewers**:
The Authored workflow section for non-draft pull requests whose Review decision is review required, or whose decision is absent but has one or more Outstanding review requests.
_Avoid_: Pending review

**Approved**:
The Authored workflow section for non-draft pull requests whose Review decision is approved.
_Avoid_: Ready to merge, mergeable

**Drafts**:
The Authored workflow section containing Draft pull requests.
_Avoid_: Work in progress

**Review roster**:
The people and teams requested to review a pull request, plus people who have already submitted a review. It exists for visibility and does not itself determine the Authored workflow section.
_Avoid_: Reviewer list, assignees, participants

**Repository scope**:
The device-local set of accessible repositories projected from the Account workload into the Active workload. It controls visible pull requests and the Review count, defaults to all accessible repositories, and does not cause Reconciliation when changed.
_Avoid_: Mute list, notification filter

**Review count**:
The number of pull requests in Needs your review under the current Repository scope. It is GitHubBar's only proactive attention signal in the MVP.
_Avoid_: Unread count, notification count

**Account workload**:
All open Review requests and Authored pull requests visible through the Monitored account's Access coverage, before Repository scope is applied. It is the canonical source for device-local filtering and may span hundreds of pull requests under a target throughput of 100 pull requests per day.
_Avoid_: Global scope, unfiltered feed

**Active workload**:
The visible Needs your review and Authored workflow sections projected from the Account workload under the current Repository scope.
_Avoid_: Inbox, feed, history

**Reconciliation**:
A complete network refresh that rediscovers the Account workload and hydrates its row and Review-roster data.
_Avoid_: Sync, poll, incremental update

**Snapshot**:
An account-bound, timestamped representation of the Account workload, including whether the Reconciliation that produced it was complete or partial. A Snapshot is independent of Repository scope.
_Avoid_: Cache, response, feed

**Refresh health**:
Whether the most recent reconciliation completed, produced partial data, or failed while an older snapshot remains usable. It is independent of the account connection and access coverage.
_Avoid_: Account status, access status
