#!/bin/zsh

set -euo pipefail

prototype_dir="${0:A:h}"
cd "$prototype_dir"
"/Users/fran/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3" render.py
echo "Created $prototype_dir/alternative-status-icons.png"
