#!/usr/bin/env bash
set -euo pipefail

# Run a simple HTTP server in the background
simple-http-server --ip 127.0.0.1 --port 3000 --index --nocache -- www/ &

# Recompile on changes and clear the screen
watchexec --no-global-ignore --restart --verbose --exts roc,html,rs,css,toml --debounce 500ms --clear -- "./build.sh --dev $1"
