#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

if ! command -v xcodegen >/dev/null 2>&1; then
  print -u2 "XcodeGen is required. Install it with: brew install xcodegen"
  exit 1
fi

xcodegen generate
