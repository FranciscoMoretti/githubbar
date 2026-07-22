<div align="center">

# GitHubBar

### Review at scale, from your menu bar.

[![Latest release](https://img.shields.io/github/v/release/FranciscoMoretti/GitHubBar?style=flat-square&label=release&color=2f81f7)](https://github.com/FranciscoMoretti/GitHubBar/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0d1117?style=flat-square&logo=apple&logoColor=white)](https://github.com/FranciscoMoretti/GitHubBar/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://www.swift.org/)

<img src="docs/assets/githubbar-hero.png" alt="GitHubBar showing a high-volume pull-request review queue in the macOS menu bar" width="100%" />

**The number in your menu bar is your review queue.** Open GitHubBar to see review requests and your own pull requests across the repositories that matter on this Mac.

[Download GitHubBar](https://github.com/FranciscoMoretti/GitHubBar/releases) · [Report an issue](https://github.com/FranciscoMoretti/GitHubBar/issues)

</div>

## Built for review at scale

- **Know what needs you.** The menu-bar count shows open pull requests currently awaiting your review—GitHubBar's only proactive attention signal.
- **See your whole review workflow.** Scan Needs your review, Returned to you, Needs reviewers, Waiting for reviewers, Approved, and Drafts in one native menu.
- **Keep people visible.** Every row shows the author and review roster, so missing reviewers and completed reviews are easy to spot.
- **Focus each Mac.** Switch instantly between all accessible repositories and a device-local pinned set configured in Settings.
- **Navigate stacked work.** Linear pull-request stacks collapse into compact, section-aware rows; open the submenu to see every member's current section and reviewers.
- **Move without the website.** Open any pull request directly, refresh on demand, or press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> from anywhere.

GitHubBar reconciles the full account workload in the background, keeps the latest useful snapshot available, and applies repository scope locally—switching views does not trigger another GitHub request.

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

3. Unzip GitHubBar and move it to **Applications**.

GitHubBar 1.0.0 is ad-hoc signed and not Apple-notarized. On first launch, macOS may block it: try opening GitHubBar once, then choose **Open Anyway** under **System Settings → Privacy & Security** after verifying the downloaded checksum.

GitHubBar requires macOS 14 or newer and runs on both Apple silicon and Intel Macs. Developer ID signing, notarization, and automatic updates remain planned for a future release.

## Privacy

GitHubBar uses your existing GitHub CLI login. Tokens stay in memory, preferences and the latest PR snapshot stay on your Mac, and diagnostics never record repository names, PR titles, usernames, or credentials.

## Build from source

```sh
brew install xcodegen gh
scripts/generate-project.sh
open GitHubBar.xcodeproj
```

Run `scripts/check.sh` before submitting a pull request. Release details are in the [stable release runbook](docs/releases/stable-release-runbook.md) and [validation guide](docs/releases/validation-release.md).

---

<div align="center">
<sub>Built for developers who would rather review the PR than find the PR.</sub>
</div>
