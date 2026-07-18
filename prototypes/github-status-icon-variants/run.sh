#!/bin/zsh

set -euo pipefail

prototype_dir="${0:A:h}"
cd "$prototype_dir"
mkdir -p .rendered
swiftc render-svg.swift -framework AppKit -o .render-svg
for asset in assets/*.svg; do
  name="${asset:t:r}"
  ./.render-svg "$asset" ".rendered/$name.png" 512
done
"/Users/fran/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3" render.py
echo "Created $prototype_dir/github-status-icon-variants.png"
