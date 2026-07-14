# GitHub API, authentication, and rate-limit constraints

Research for [Establish GitHub data, authentication, and rate-limit constraints at target scale](https://github.com/FranciscoMoretti/githubbar/issues/3), current as of 14 July 2026.

This note distinguishes GitHub-documented facts from product recommendations and estimates:

- **GitHub fact** means the linked GitHub documentation or first-party schema states the behavior.
- **Recommendation** is the proposed GitHubBar design based on those facts.
- **Estimate** is a planning calculation that must be measured against the live API before implementation is considered complete.

## Outcome

The target is feasible. A GraphQL-first client can reconcile at least 500 active pull requests every five minutes for a small fraction of the normal 5,000-point-per-user hourly GraphQL budget. A REST-per-PR design cannot: three reads per PR already produce about 1,500 REST calls per snapshot.

The recommended data path is:

1. Discover the active workload with three global GraphQL searches.
2. Deduplicate the resulting pull-request node IDs.
3. Hydrate summary and review-roster data in batches with `nodes(ids:)`.
4. Fetch required-check details and request-event timing in smaller, targeted GraphQL queries.
5. Preserve the last complete local snapshot through partial failures and only remove by absence after a complete reconciliation.

The main unresolved product trade-off is authentication, not API capacity:

- An **OAuth App** best matches “one monitored account across every repository it can access,” but private repository coverage requires the broad `repo` scope. GitHub cannot scope source-code access read-only for OAuth tokens.
- A **GitHub App** offers genuinely granular read-only permissions and short-lived user tokens, but it only sees repositories included in installations. Every organization must approve/install it and grant the relevant repositories.

For GitHubBar's stated coverage goal, this research recommends an OAuth App as the MVP default, with the scope and organization-access gaps made explicit. A later security-first GitHub App mode remains worthwhile.

## Query architecture

### 1. Discover the active workload

Use the GraphQL `search` connection with pages of 100:

```text
is:pr is:open author:@me archived:false sort:updated-desc
is:pr is:open user-review-requested:@me archived:false sort:updated-desc
is:pr is:open team-review-requested-user:USERNAME archived:false sort:updated-desc
```

**GitHub fact:** `author:@me` matches pull requests authored by the authenticated account. `user-review-requested:@me` matches direct requests, while `team-review-requested-user:USERNAME` matches requests for any team that person belongs to. The broader `review-requested:USERNAME` qualifier combines both categories. GitHub documents those qualifiers in [Searching issues and pull requests](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests#search-by-pull-request-review-status-and-reviewer). The first-party CLI likewise uses `--review-requested=@me` to search open review requests in [`gh search prs`](https://cli.github.com/manual/gh_search_prs).

**Recommendation:** keep direct and team discovery as separate searches, tag each resulting node ID with its discovery source, then deduplicate before hydration. This preserves the product's direct-versus-team distinction—including the case where both apply—without enumerating every team or issuing one search per team. The hydrated `reviewRequests` data supplies the actual requested users and teams for the review roster. A combined `review-requested:USERNAME` query is useful as a reconciliation diagnostic, not the primary classified feed.

This classification does not require organization Members permission. Enumerating `GET /user/teams` and requesting `read:org`/Members read is optional, only needed if a later feature must identify exactly which of several requested teams contain the monitored account. The [teams REST API](https://docs.github.com/en/rest/teams/teams#get-teams-for-the-authenticated-user) supports that expansion.

**GitHub fact:** GraphQL search returns at most 1,000 results, and connections are paged with cursors. The query is comfortably inside the limit at 500 active items, but GitHubBar must detect when `issueCount` approaches the ceiling and shard by `updated:` time range or repository. See the GraphQL [`search` query](https://docs.github.com/en/graphql/reference/queries#search) and [pagination guide](https://docs.github.com/en/graphql/guides/using-pagination-in-the-graphql-api).

**Recommendation:** paginate to exhaustion on every full reconciliation. A page failure makes the reconciliation incomplete; it must not make omitted pull requests disappear from the cache.

Organization and repository muting is initially a local post-fetch filter. That keeps global discovery simple and complete. If muted data later dominates the result set, server-side negative qualifiers or owner/time shards can be added without changing the domain model.

### 2. Batch-hydrate pull requests

After deduplicating the search results, use `nodes(ids:)` batches of 50–100 to fetch:

- node ID, number, title, URL, state, draft flag, creation/update/close/merge timestamps;
- repository name/owner/visibility and author identity/avatar;
- `reviewRequests(first: 100)`;
- `latestReviews(first: 100)` and `latestOpinionatedReviews(first: 100)`;
- `reviewDecision`, `mergeable`, `mergeStateStatus`, and `statusCheckRollup { state }`;
- head/base names and head OID for cache invalidation and quick links.

These fields are defined on the GraphQL [`PullRequest` object](https://docs.github.com/en/graphql/reference/pulls#pullrequest). `latestReviews` returns the latest non-pending review per reviewer; `latestOpinionatedReviews` retains the latest opinion-bearing review per reviewer. The PR-level `reviewDecision` is GitHub's merge-rule-aware review summary.

**Recommendation:** keep discovery and hydration separate. A skinny discovery pass makes membership reconciliation cheap; hydration can prioritize visible/actionable rows and spread the remaining workload through the refresh interval.

Every connection must be paginated. GraphQL requires `first` or `last` between 1 and 100, caps one call at 500,000 nodes, and may terminate deep/resource-heavy requests with partial data. GitHub recommends smaller pages, shallower queries, and splitting large queries. See [GraphQL rate and query limits](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api#node-limit).

Most pull requests will fit in one reviewer page. If `totalCount > 100`, fetch the remaining reviewers for that PR separately. GitHubBar must never render a truncated roster as complete.

### 3. Refresh required checks precisely

`statusCheckRollup.state` is a useful summary of all check runs and commit statuses, but it does not say which ones are required.

**GitHub fact:** `CheckRun` and `StatusContext` implement `RequirableByPullRequest`. Their `isRequired(pullRequestId:)` field answers whether that check/status must pass for the specified PR. This is part of the public GraphQL schema, not an administration endpoint. See [`RequirableByPullRequest`](https://docs.github.com/en/graphql/reference/interfaces#requirablebypullrequest), [`CheckRun`](https://docs.github.com/en/graphql/reference/checks#checkrun), and [`StatusContext`](https://docs.github.com/en/graphql/reference/commits#statuscontext). GitHub's own CLI uses the same field for `gh pr checks --required`; its behavior is documented in [`gh pr checks`](https://cli.github.com/manual/gh_pr_checks).

**Recommendation:** do not request repository Administration permission and do not reconstruct required checks from branch-protection/ruleset configuration. Query the status rollup contexts and evaluate `isRequired` against the PR itself. This automatically delegates classic protection and current ruleset evaluation to GitHub.

There is a batching wrinkle: `isRequired` needs the corresponding PR ID. A generic `nodes(ids:)` fragment cannot substitute each parent node's ID as a field argument. Generate a bounded alias query (for example, 20–50 PR aliases, each with its own ID variable), or query individual PRs through a low-concurrency queue. Measure document size and latency before choosing the batch size.

Refresh the cheap aggregate `statusCheckRollup.state` for every authored PR. Fetch the detailed required contexts:

- for authored PRs with pending/failing aggregate checks;
- for authored PRs whose aggregate state or head OID changed;
- periodically for the remainder, so a required-check transition cannot be hidden by an already-failing optional check;
- immediately for currently visible rows when the popover opens.

Paginate more than 100 check contexts rather than treating the first page as complete.

### 4. Resolve transitions and recently completed PRs

Compare every complete discovery result with the previous active set:

- A previously authored PR that disappeared is re-fetched by node ID. `MERGED`/`CLOSED` moves it to Recently completed; an authorization failure does not.
- A review request that disappeared but remains `OPEN` was satisfied or removed and leaves the active review-request queue.
- A tracked PR that becomes `MERGED`/`CLOSED` is removed from active queues immediately and retained locally for the agreed 24-hour Recently completed window.

**Recommendation:** retain recently departed node IDs in a small watch set for 24 hours and refresh them at a lower cadence. This catches merge/close transitions after the monitored account has completed its review. A first-run backfill can use an authored closed/merged search bounded by `closed:>=...`; after that, local edge detection is the canonical history.

Only bulk-remove by absence after both discovery searches and all their pages succeeded. Confirm individual disappearance with `node(id:)` where possible. A private repository that becomes inaccessible is indistinguishable from nonexistence in some API responses, so a `404`/`null` alone is not evidence of closure.

## Review roster and request semantics

Build the review roster from the union of current requests and submitted reviews.

### Current requests

`reviewRequests` is the authoritative set of outstanding reviewers. The current schema's `RequestedReviewer` union includes `User`, `Team`, `Bot`, `EnterpriseTeam`, and `Mannequin`, so request records should persist `__typename` rather than assume every entry is a person. See [`RequestedReviewer`](https://docs.github.com/en/graphql/reference/pulls#requestedreviewer).

**GitHub fact:** once a requested reviewer submits a review, GitHub removes that actor from current requested reviewers and returns the submitted review through the reviews API. See [REST review-request semantics](https://docs.github.com/en/rest/pulls/review-requests#get-all-requested-reviewers-for-a-pull-request).

**Recommendation:** a current request overrides an older submitted review for the same actor. That makes a re-requested reviewer display as Requested again, rather than preserving the stale Approved/Changes requested badge.

### Submitted review state

The public review states are `APPROVED`, `CHANGES_REQUESTED`, `COMMENTED`, `DISMISSED`, and `PENDING`; see [`PullRequestReviewState`](https://docs.github.com/en/graphql/reference/enums#pullrequestreviewstate). A submitted review exposes author, state, submission/update timestamps, and commit information through [`PullRequestReview`](https://docs.github.com/en/graphql/reference/pulls#pullrequestreview).

Recommended reduction per actor:

1. current `reviewRequests` entry -> Requested;
2. otherwise the latest opinion-bearing review -> Approved, Changes requested, or Dismissed;
3. otherwise latest non-pending review -> Commented or Dismissed;
4. no current request or review -> not in the active roster.

Use `reviewDecision` for the PR-level merge-review truth. Do not infer the whole PR's approval from a simple count of green reviewer avatars; repository rules can require code owners, last-push approval, or a minimum approval count.

A pending team request is displayed as a team entry. If an individual member reviews, that is the individual's review; GitHubBar should not invent a durable “team approved” state after GitHub removes the team request.

Dismissed reviews remain visible as Dismissed. If exact dismissal or re-request time matters, query `timelineItems` for `ReviewDismissedEvent`, `ReviewRequestedEvent`, and `ReviewRequestRemovedEvent`. The [GraphQL pull-request schema](https://docs.github.com/en/graphql/reference/pulls) exposes those event types and timestamps.

**Recommendation:** timeline hydration is targeted, not part of every 500-PR snapshot. Use it for actionable incoming requests where “new request” versus “re-request” affects ordering or notification. Current request state remains authoritative if an event page is incomplete.

## Merge readiness

No single low-level field should be interpreted in isolation:

- `mergeable` reports whether GitHub can create a conflict-free merge and may temporarily be `UNKNOWN`.
- `mergeStateStatus` provides GitHub's combined state: `BEHIND`, `BLOCKED`, `CLEAN`, `DIRTY`, `DRAFT`, `HAS_HOOKS`, `UNKNOWN`, or `UNSTABLE`.
- `reviewDecision` reports whether review requirements are approved, changes-requested, or still required.
- `statusCheckRollup` and each context's `isRequired` identify aggregate and required-check state.
- `isDraft`, merge-queue fields, and auto-merge state cover important special cases.

These fields and enum meanings are documented under [GraphQL pull requests](https://docs.github.com/en/graphql/reference/pulls#mergestatestatus).

**Recommendation:** derive the user-facing next move from this combined snapshot. Treat `UNKNOWN` as calculating/stale, never as ready. `CLEAN` (and, where supported, `HAS_HOOKS`) plus satisfied reviews and required checks can produce Ready to merge. `BLOCKED` remains a generic GitHub-rule blocker unless another fetched field identifies the cause. This avoids confidently labelling a PR merge-ready while unresolved conversations, deployments, merge queues, or other rules still block it.

## Authentication choices

### OAuth App

**Coverage advantage.** Authorizing an OAuth App grants it scoped access to resources the monitored account can access. Unlike a GitHub App installation, it is not restricted to a selected repository list. GitHub's [OAuth/GitHub App comparison](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps#what-can-github-apps-and-oauth-apps-access) documents that difference.

**Permission cost.** Private pull-request data requires the OAuth `repo` scope. OAuth does not offer a pull-requests-read-only scope, and GitHub states that source-code access cannot currently be made read-only. See [OAuth scopes](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps) and [authorizing OAuth apps](https://docs.github.com/en/apps/oauth-apps/using-oauth-apps/authorizing-oauth-apps#oauth-app-access).

Recommended MVP scopes:

- `repo` for public/private repository and pull-request coverage;
- `read:org` only if GitHubBar implements explicit private organization/team membership diagnostics. It is not required for the two primary search queries.

Do not request `notifications`; GitHubBar's review-request model comes from PR state, not the GitHub notification inbox.

**Flow trade-off.** GitHub currently recommends authorization code plus PKCE over device flow for a public client that can use a browser. A native/open-source client cannot keep a client secret confidential, even though the OAuth token exchange requires it; PKCE protects the authorization code, but the shipped secret must not be treated as a security boundary. Device flow avoids shipping a client secret, but GitHub warns that its lack of a redirect URI enables remote app-impersonation phishing and says not to enable it without reason. See [OAuth authorization](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps) and [OAuth App best practices](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/best-practices-for-creating-an-oauth-app#secure-your-apps-credentials).

**Recommendation:** default to authorization code + PKCE. The later authentication decision ticket should choose between a tiny token-exchange broker (keeps the client secret confidential) and a fully local public-client implementation (ships a recoverable secret). If zero embedded secret and zero backend are harder requirements than GitHub's phishing guidance, device flow is the documented fallback: it needs only a client ID, uses an eight-character user code that normally expires after 15 minutes, and starts with a five-second minimum polling interval.

OAuth App user tokens remain active until revoked; they do not provide GitHub App-style refresh-token rotation. Store the token using the platform's secure credential mechanism—Keychain on macOS is the implementation inference from GitHub's platform-storage guidance—and erase it plus cached private metadata on sign-out/revocation.

### GitHub App user access token

**Security advantage.** GitHub Apps support granular permissions, repository selection, and short-lived user tokens. GitHub generally recommends them over OAuth Apps. See [Differences between GitHub Apps and OAuth apps](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps).

GitHubBar would request read access to:

- repository Metadata;
- Pull requests;
- Checks and Commit statuses;
- organization Members only if explicit team enumeration is added.

**Coverage cost.** A GitHub App user token is limited to permissions shared by the user and the app, and private repository access depends on an app installation that includes the repository. See [Generating a GitHub App user access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app#about-user-access-tokens). A user may authorize the app without installing it, but authorization alone does not grant private repository coverage.

Every organization can restrict installation to owners or require approval. That makes “every accessible repository” impossible to promise until every relevant organization installs the app and grants all relevant repositories. GitHub documents these controls under [Limiting app access requests and installations](https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/limiting-oauth-app-and-github-app-access-requests-and-installations).

GitHub App device flow is documented for desktop apps. Expiring user access tokens normally last eight hours and refresh tokens six months; refresh rotates both credentials. See [Generating](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app#using-the-device-flow-to-generate-a-user-access-token) and [refreshing GitHub App user tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens#about-user-access-tokens-that-expire).

**Recommendation:** retain an authentication-provider boundary so GitHub App mode can be added later for organizations that prefer least privilege and accept installation. It should surface per-organization installation coverage rather than silently presenting an incomplete active workload as complete.

### Personal access tokens

PAT entry is suitable for development and an explicit advanced fallback, not primary onboarding.

- A fine-grained PAT is restricted to one resource owner and selected repositories, so it does not satisfy cross-organization coverage with one token.
- A classic PAT with `repo` behaves more like the broad OAuth grant but lacks a polished app authorization/revocation flow and may be disabled by organization policy.
- Organizations can require approval for fine-grained PATs, block PAT access, and impose lifetimes.

See [Managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#types-of-personal-access-tokens) and [Organization PAT policy](https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization).

Never silently import or reuse a token from `gh`; make PAT use an explicit user choice and store it in Keychain.

### Organization approval and SAML SSO

A successful GitHub login does not prove complete organization coverage.

- Organizations can require owner approval for OAuth Apps; until approved, private organization resources remain unavailable. See [OAuth App access restrictions](https://docs.github.com/en/organizations/managing-oauth-access-to-your-organizations-data/about-oauth-app-access-restrictions).
- GitHub App installations can be owner-restricted and repository-selected.
- Organizations using SAML may require the monitored account to establish an active SSO session and reauthorize the OAuth/GitHub App credential. See [SAML and GitHub Apps](https://docs.github.com/en/enterprise-cloud@latest/apps/using-github-apps/saml-and-github-apps) and [authorizing OAuth apps](https://docs.github.com/en/apps/oauth-apps/using-oauth-apps/authorizing-oauth-apps#oauth-apps-and-organizations).
- Classic PATs need separate SSO authorization; fine-grained PATs are authorized during creation. See [Authorizing a PAT for SSO](https://docs.github.com/en/authentication/authenticating-with-saml-single-sign-on/authorizing-a-personal-access-token-for-use-with-single-sign-on).

**Recommendation:** model access health separately from refresh health. Show available, organization approval required, SSO reauthorization required, and unknown/incomplete where GitHub exposes enough information. Never call a successful partial search “all repositories.”

## Rate limits and capacity

### Documented limits

For requests made on behalf of a user, GraphQL normally allows 5,000 points per hour per user. OAuth App, GitHub App user-token, and PAT requests made as that user share the user's GraphQL allowance. The response headers and optional `rateLimit { cost remaining resetAt }` expose live usage. GitHub's rough cost formula counts the requests needed for unique connections, divides by 100, rounds, and applies a minimum cost of one. See [GraphQL primary limits and cost](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api#primary-rate-limit).

Authenticated REST requests normally allow 5,000 requests per hour per user. Search has its own REST rate-limit resource. Prefer response headers over polling `/rate_limit`. See [REST primary limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#primary-rate-limit-for-authenticated-users).

Documented secondary limits include:

- no more than 100 concurrent requests across REST and GraphQL;
- at most 900 REST endpoint points/minute;
- at most 2,000 GraphQL endpoint points/minute;
- CPU-time and undisclosed abuse/resource limits.

These values can change, and GitHub can impose additional limits. Read `Retry-After`; otherwise pause at least one minute, then use exponential backoff. Continuing while limited can result in an integration ban. See [Secondary rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#about-secondary-rate-limits).

### Estimated full-reconciliation budget

Assumptions: 500 deduplicated active PRs, 100 discovery items/page, 50–100 summary items/batch, two review connections, bounded required-check detail batches, and a small number of timeline/exception pages.

| Work | Estimated GraphQL cost |
| --- | ---: |
| Active-workload discovery | 5–10 points |
| Core + review-roster hydration | 10–15 points |
| Required-check detail, targeted timelines, exceptional pagination | 10–15 points |
| **Full reconciliation** | **25–40 points** |

At that estimate:

- every five minutes: about 300–480 points/hour;
- every minute: about 1,500–2,400 points/hour.

Those are planning estimates, not guarantees. Query cost depends on the final connection shape, and GitHub may change its formula. Every prototype query should request/log `rateLimit.cost`, latency, node counts, and partial errors against representative 500-PR fixtures before cadence is locked.

This comfortably supports CodexBar-style fixed/adaptive refresh: immediately show cached data, refresh visible/actionable rows on open, perform a normal full reconciliation around every five minutes while active, and back off when idle or rate-limited.

A naive REST snapshot that calls current requested reviewers, submitted reviews, and checks for every one of 500 PRs is approximately 1,500 requests before discovery/core reads. At a five-minute cadence that is about 18,000 requests/hour—well beyond the normal 5,000 request allowance. REST is therefore reserved for narrow features and conditional metadata, not the primary snapshot pipeline.

### REST conditional requests

Most REST endpoints provide `ETag`, and many provide `Last-Modified`. An authenticated conditional request that returns `304 Not Modified` does not consume the primary REST limit. See [REST API best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests-if-appropriate).

Use `If-None-Match` for low-churn REST metadata such as optional team lists or access diagnostics. Conditional requests can still contribute to secondary limits, so they do not justify high-frequency per-PR polling.

GraphQL does not offer the same per-response conditional-GET mechanism. `updated:>=timestamp` with an overlap window can accelerate discovery, but it is not a correctness boundary: search indexing and fields such as check status can change independently of a useful PR `updatedAt` signal. Retain periodic full reconciliation.

## Partial failures and cache correctness

**GitHub fact:** a GraphQL request can return useful `data` alongside path-specific errors; GitHub may also terminate resource-heavy queries with partial results. Queries taking too long can return `502`/`504`, and timeouts may incur additional rate-limit cost. See [GraphQL timeouts and resource limits](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api#timeouts).

Recommended cache rules:

1. Track completeness and fetched-at time per reconciliation, entity, and expensive field group (roster/checks/timeline).
2. Merge successful fields into the cache; do not replace an errored/null roster or check list with an authoritative empty list.
3. Preserve the last complete snapshot on timeout, network failure, partial GraphQL errors, or rate limiting and mark affected rows stale/partial.
4. Never apply absence-based deletion from an incomplete discovery or pagination run.
5. Treat `401` as credential failure. Treat `403` by inspecting rate-limit headers, SSO/organization context, and error body. Treat `404`/GraphQL `null` on private resources as ambiguous until access loss or closure is confirmed.
6. On sign-out/revocation, erase credentials and private cached metadata. On confirmed organization access loss, remove that organization's private data rather than retaining it indefinitely.
7. Keep independent backoff for discovery, hydration, and optional detail so one failing field does not blank the whole menu.

## Decisions this research enables

- Use GraphQL global search plus batched hydration, not repository-by-repository or per-PR REST polling.
- Use separate `user-review-requested:@me` and `team-review-requested-user:USERNAME` searches; direct and team requests remain distinguishable without team enumeration.
- Build review rosters from current requests plus latest submitted/opinionated reviews; current request wins after re-request.
- Query `isRequired(pullRequestId:)` for exact required-check state without Administration permission.
- Treat merge readiness as a composition of GitHub's merge state, review decision, required checks, draft/conflict, and queue state.
- Design for incomplete access and partial refresh as explicit product states.
- Prefer OAuth App coverage for the stated MVP, while acknowledging that `repo` is broad and organization approval/SSO can still create gaps.
- Keep GitHub App and PAT support behind an authentication-provider boundary; GitHub App is the least-privilege alternative, PAT is an explicit advanced fallback.
