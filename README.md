<div align="center">

# GitHubBar

### Review at scale, from your menu bar.

[![Latest validation build](https://img.shields.io/github/v/release/FranciscoMoretti/GitHubBar?include_prereleases&style=flat-square&label=validation&color=2f81f7)](https://github.com/FranciscoMoretti/GitHubBar/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0d1117?style=flat-square&logo=apple&logoColor=white)](https://github.com/FranciscoMoretti/GitHubBar/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://www.swift.org/)

<img src="docs/assets/githubbar-hero.png" alt="GitHubBar showing pull requests grouped by review state" width="100%" />

**The number in your menu bar is your review queue:** open pull requests waiting for your review across the repositories you care about.

[Download GitHubBar](https://github.com/FranciscoMoretti/GitHubBar/releases) · [Report an issue](https://github.com/FranciscoMoretti/GitHubBar/issues)

</div>

## Built for review at scale

- See how many pull requests need your review without opening GitHub.
- Scan authors, repositories, and review state in one native macOS menu.
- Track your own PRs by next action: returned, needs reviewers, waiting, approved, or draft.
- Press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> from anywhere and open the right PR instantly.

## Install

1. Install and sign in to [GitHub CLI](https://cli.github.com/):

   ```sh
   brew install gh
   gh auth login
   ```

2. Download the ZIP and `.sha256` file from the [latest release](https://github.com/FranciscoMoretti/GitHubBar/releases), then verify it:

   ```sh
   cd ~/Downloads
   shasum -a 256 --check GitHubBar-*.zip.sha256
   ```

3. Unzip GitHubBar, move it to **Applications**, then Control-click the app and choose **Open** the first time.

GitHubBar requires macOS 14 or newer. Validation builds are universal, ad-hoc signed, and not yet notarized.

## Privacy

GitHubBar uses your existing GitHub CLI login. Tokens stay in memory, preferences and the latest PR snapshot stay on your Mac, and diagnostics never record repository names, PR titles, usernames, or credentials.

## Build from source

```sh
brew install xcodegen gh
scripts/generate-project.sh
open GitHubBar.xcodeproj
```

Run `scripts/check.sh` before submitting a pull request. Release details are in the [validation guide](docs/releases/validation-release.md).

---

<div align="center">
<sub>Built for developers who would rather review the PR than find the PR.</sub>
</div>
