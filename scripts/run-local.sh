#!/bin/zsh
set -euo pipefail

GITHUBBAR_VERSION=0.1.0 scripts/package-validation.sh
pkill -f '/GitHubBar.app/Contents/MacOS/GitHubBar' 2>/dev/null || true
exec .build/validation/GitHubBar.app/Contents/MacOS/GitHubBar
