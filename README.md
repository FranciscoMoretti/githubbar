# GitHubBar

GitHubBar is a native macOS menu-bar app that keeps pull requests waiting for your review and your own open pull requests visible without repeatedly loading GitHub in a browser.

## Requirements

- macOS 14 or newer
- Xcode with the macOS 14 SDK or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [GitHub CLI](https://cli.github.com/) for the account connection used by the app

## Build

```sh
scripts/generate-project.sh
open GitHubBar.xcodeproj
```

Choose the `GitHubBar` scheme and run it. GitHubBar is an accessory app, so it appears in the menu bar rather than the Dock.

## Checks

```sh
scripts/check.sh
```

The check script builds the strict-concurrency core package, exercises its public seams, and typechecks the AppKit/SwiftUI shell. The normal XCTest suite is also available from a full Xcode installation.
