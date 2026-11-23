#!/usr/bin/env bash
# Use the Nix a self-hosted runner already has, in place of installing one.
#
#   .github/scripts/machine-nix.sh
#
# A self-hosted runner keeps its Nix store between jobs, so nothing is
# installed and no Actions cache is needed. The job's PATH does not have Nix
# on it, so this puts the system profile there. Accepting the flake's
# nixConfig lets Nix use the binary cache it names, as long as the daemon
# trusts this user. Otherwise a cold store builds the pinned Roc once.
set -euo pipefail

for dir in /nix/var/nix/profiles/default/bin /run/current-system/sw/bin; do
  if [ -x "$dir/nix" ]; then
    echo "$dir" >> "$GITHUB_PATH"
    echo "NIX_CONFIG=accept-flake-config = true" >> "$GITHUB_ENV"
    "$dir/nix" --version
    exit 0
  fi
done

echo "error: this self-hosted runner has no Nix in /nix/var/nix/profiles/default/bin or /run/current-system/sw/bin" >&2
exit 1
