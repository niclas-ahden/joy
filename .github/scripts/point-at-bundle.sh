#!/usr/bin/env bash
# Point every app in the checkout at a platform bundle.
#
#   .github/scripts/point-at-bundle.sh https://.../joy-0.33.0.tar.zst
#   .github/scripts/point-at-bundle.sh http://127.0.0.1:8788/<hash>.tar.zst
#
# Makes a run test the artifact instead of this checkout's platform. The
# localhost form is for draft bundles: roc allows http to localhost, and does
# the download, hash check and unbundle itself either way.
set -euo pipefail

url=${1:?usage: point-at-bundle.sh <bundle-url>}

apps=(examples/*.roc examples/*/app.roc tests/apps/*.roc)
for src in "${apps[@]}"; do
  sed -i.bak \
    -e "s|\"\.\./\.\./platform/main\.roc\"|\"$url\"|" \
    -e "s|\"\.\./platform/main\.roc\"|\"$url\"|" \
    "$src"
  rm -f "$src.bak"
done

# A rewrite that silently matched nothing would leave the run testing this
# checkout while reporting that it tested the bundle.
leftover=$(grep -l 'platform "\.\.' "${apps[@]}" || true)
[ -z "$leftover" ] || {
  echo "error: these apps still name this checkout's platform" >&2
  echo "$leftover" >&2
  exit 1
}

echo "rewrote ${#apps[@]} apps to $url"
