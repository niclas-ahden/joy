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

# The apps are found by what they name, not listed by where they live, so an
# app in a new directory, or one more level down, is rewritten too.
local_platform='platform "(\.\./)+platform/main\.roc"'
apps=$(grep -rlE --include='*.roc' "$local_platform" examples tests || true)
[ -n "$apps" ] || {
  echo "error: no app names this checkout's platform" >&2
  exit 1
}

count=0
for src in $apps; do
  sed -i.bak -E "s|$local_platform|platform \"$url\"|" "$src"
  rm -f "$src.bak"
  count=$((count + 1))
done

# A rewrite that silently matched nothing would leave the run testing this
# checkout while reporting that it tested the bundle.
leftover=$(grep -rl --include='*.roc' 'platform "\.\.' examples tests || true)
[ -z "$leftover" ] || {
  echo "error: these apps still name this checkout's platform" >&2
  echo "$leftover" >&2
  exit 1
}

echo "rewrote $count apps to $url"
