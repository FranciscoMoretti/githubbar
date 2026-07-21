# RepoBar repository tabs and pinning

Research snapshot: `steipete/RepoBar` commit [`5c754564`](https://github.com/steipete/RepoBar/commit/5c754564b4097c759538f35ca34624fd45ca6edc) (2026-07-06). All findings below come from that source tree.

## What RepoBar actually does

### Menu tabs

RepoBar models the menu selection as a four-case `MenuRepoSelection`: `all`, `pinned`, `local`, and `work`. `Pinned` changes the repository query scope; `Local` takes a separate path based on discovered local checkouts; and `Work` is not a saved group—it applies an “open issues or open PRs” filter. ([`MenuRepoFilters.swift` lines 3–34](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/Support/MenuRepoFilters.swift#L3-L34), [`RepositoryOnlyWith.swift` lines 3–27](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBarCore/Support/RepositoryOnlyWith.swift#L3-L27))

The tabs are a custom SwiftUI control embedded in an `NSMenuItem`: four fixed-width plain buttons inside a rounded background, plus a separate sort button. Changing a tab posts `menuFiltersDidChange`; the menu manager defers rebuilding the menu to the next run-loop turn so it does not mutate the menu during layout. ([`MenuFilterViews.swift` lines 5–79](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/Views/MenuFilterViews.swift#L5-L79), [`StatusBarMenuManager.swift` lines 194–208](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/StatusBar/StatusBarMenuManager.swift#L194-L208))

The active tab is transient: `Session.menuRepoSelection` starts at `.all` and is not part of `UserSettings`. Pinned repository membership is persistent, but the currently viewed tab is not. ([`Session.swift` lines 5–31](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/App/Session.swift#L5-L31), [`UserSettings.swift` lines 3–30](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBarCore/Settings/UserSettings.swift#L3-L30))

When building the menu, RepoBar converts the active tab into a `RepositoryQuery`, filters the already-loaded repository collection, and then renders the result. The tab change itself does not fetch data. ([`StatusBarMenuBuilder.swift` lines 308–339](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/StatusBar/StatusBarMenuBuilder.swift#L308-L339), [`RepositoryPipeline.swift` lines 64–122](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBarCore/Support/RepositoryPipeline.swift#L64-L122))

### Pinned state and persistence

For the current single-account path, pinned repositories are an ordered `[String]` of canonical `owner/name` values in `RepoListSettings`; hidden repositories use a second list. Both are persisted as part of the Codable `UserSettings` envelope in `UserDefaults`. ([`UserSettings.swift` lines 243–252](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBarCore/Settings/UserSettings.swift#L243-L252), [`SettingsStore.swift` lines 4–49](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBarCore/Support/SettingsStore.swift#L4-L49))

Visibility is tri-state—`visible`, `pinned`, or `hidden`. `setVisibility` normalizes case, removes the repository from both lists, adds it to the chosen list when appropriate, saves settings, and refreshes RepoBar. This keeps pinned and hidden mutually exclusive. ([`RepoVisibility.swift` lines 1–17](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/Support/RepoVisibility.swift#L1-L17), [`AppState+Visibility.swift` lines 115–140](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/App/AppState%2BVisibility.swift#L115-L140))

RepoBar also contains an account-scoped persistence model that maps account IDs to pinned and hidden `owner/name` arrays, with fallback to the legacy single-account lists. That is migration scaffolding for multi-account support rather than a requirement for the basic UI. ([`AccountScopedRepositoryLists.swift` lines 3–69](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBarCore/Settings/AccountScopedRepositoryLists.swift#L3-L69))

### Settings repository browser

Settings is a native SwiftUI `TabView`; the Repositories tab hosts `RepoSettingsView` and is given a much wider preferred width (980 points) than the other tabs. ([`SettingsView.swift` lines 11–33](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/Settings/SettingsView.swift#L11-L33), [`SettingsTab.swift` lines 12–53](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/Settings/SettingsTab.swift#L12-L53))

The repository screen provides:

- A search field and an optional manual `owner/name` rule input.
- A selectable, sortable SwiftUI `Table` with Repository, Issues, PRs, Stars, Updated, and Visibility columns.
- A per-row visibility menu, multi-row Pin/Hide/Set Visible actions, double-click/context-menu opening in GitHub, a status summary, and Refresh Now. ([`RepoSettingsView.swift` lines 18–159](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/Settings/RepoSettingsView.swift#L18-L159), [`RepoSettingsView.swift` lines 250–284](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/Settings/RepoSettingsView.swift#L250-L284))

The table is fed from accessible repositories, falling back to menu-snapshot or currently loaded repositories. Its row builder deduplicates names case-insensitively, preserves pinned/hidden entries that are no longer in the loaded catalog as “manual” rows, sorts pinned first, and reports loaded/pinned/hidden totals. ([`RepoSettingsView.swift` lines 163–187](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/Settings/RepoSettingsView.swift#L163-L187), [`RepoBrowserRows.swift` lines 85–171](https://github.com/steipete/RepoBar/blob/5c754564b4097c759538f35ca34624fd45ca6edc/Sources/RepoBar/Settings/RepoBrowserRows.swift#L85-L171))

## What GitHubBar should reuse

1. **Separate configuration from navigation.** Persist a set of pinned repository IDs in settings, but model the menu tab (`All` or `Pinned`) separately. GitHubBar’s current `RepositoryScope` conflates these two concepts; RepoBar’s split between persistent `pinnedRepositories` and transient `menuRepoSelection` is the cleaner model.
2. **Put only `All | Pinned` in the menu.** These tabs answer the immediate navigation question without expanding a giant repository submenu. Switch tabs by filtering GitHubBar’s already-loaded PR snapshot locally, so the interaction is instant and performs no refresh.
3. **Configure pins in a dedicated Settings view.** Use a searchable table/list with repository name and a Pin checkbox or two-state control. Apply changes immediately and store them locally on that Mac.
4. **Keep unavailable pins visible in Settings.** Preserve their stable repository IDs/names with an unavailable state instead of silently deleting them. This makes permission changes diagnosable.
5. **Keep pin order only if it has a defined effect.** RepoBar’s array order is meaningful because pinned repositories receive priority. If GitHubBar only uses pins as a membership filter, a normalized `Set<String>` is sufficient and simpler.

## What is overkill for GitHubBar 1.0

- `Local` and `Work` tabs: they reflect RepoBar’s repository/local-git dashboard domain, not GitHubBar’s PR-attention workflow.
- Hidden repositories and tri-state visibility: pin membership plus `All | Pinned` already expresses the requested machine-local scope.
- Repository statistics, sortable table columns, manual rules, bulk visibility actions, and explicit Refresh Now: GitHubBar only needs a fast pin selector over its discovered repository catalog.
- RepoBar’s forced refresh after every visibility mutation: GitHubBar already retains the full PR snapshot and can recompute visible sections and the menu-bar count locally.
- Account-scoped pin maps until GitHubBar actually supports multiple accounts. Keep the stored shape migration-friendly, but do not build the multi-account machinery now.

## Recommended GitHubBar shape

- **Persistent:** `pinnedRepositoryIDs: Set<String>` (plus last-known `nameWithOwner` for unavailable-row display).
- **Menu-only selection:** `RepositoryListFilter.all | .pinned`; default to `.all` on launch, matching RepoBar, unless product requirements explicitly say the active tab itself should persist.
- **Menu:** a compact `All | Pinned` view-backed row above the PR sections; show counts if they remain legible.
- **Settings → Repositories:** search, repository name, and Pin checkbox; selected rows first is optional, but the sort must remain stable while toggling.
- **Behavior:** pin/unpin persists immediately, then re-filters the cached PRs and count without network activity. If there are no pins, the Pinned tab shows an empty state with a direct route to Settings.
