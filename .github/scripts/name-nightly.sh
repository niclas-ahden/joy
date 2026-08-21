#!/usr/bin/env bash
# Point a release's "Compatible with:" line at a Roc nightly.
#
#   .github/scripts/name-nightly.sh <release-tag> <nightly-tag>
#
# Needs GH_TOKEN and GITHUB_REPOSITORY in the environment.
#
# Two workflows call this. release.yaml runs it once a fresh draft has passed
# on the latest nightly, so the notes are right before anyone publishes them.
# test-nightly-roc.yml runs it every morning, moving the recommendation
# forward as newer nightlies keep passing.
#
# Only ever call it for a nightly that has actually passed the suite. The line
# is a claim we are making to people who will install what it names.
set -euo pipefail

release=${1:?usage: name-nightly.sh <release-tag> <nightly-tag>}
nightly=${2:?usage: name-nightly.sh <release-tag> <nightly-tag>}

notes=$(mktemp)
trap 'rm -f "$notes" "$notes.bak"' EXIT
gh release view "$release" --json body -q .body --repo "$GITHUB_REPOSITORY" > "$notes"

# Anchor on the compatibility line rather than on the first nightly link
# anywhere in the body. The notes are hand edited, and a section such as
# "Known issues" may well name the nightly a bug was seen on. That is a
# statement about the past and must survive.
current=$(sed -n 's|^Compatible with: \[`roc \(nightly-[^`]*\)`\].*|\1|p' "$notes" | head -1)

# Releases from before the notes carried a compatibility section have nothing
# to update. That is not a reason to redden a green run, so say so and stop.
[ -n "$current" ] || {
  echo "::warning::$release notes carry no 'Compatible with:' line naming a roc nightly, leaving them alone"
  exit 0
}

if [ "$current" = "$nightly" ]; then
  echo "$release notes already name $nightly"
  exit 0
fi

# The tag is both the link text and the URL, so replacing it wherever it
# appears on that line leaves any wording around it intact.
sed -i.bak "/^Compatible with: \[\`roc /s|$current|$nightly|g" "$notes"
gh release edit "$release" --notes-file "$notes" --repo "$GITHUB_REPOSITORY"
echo "$release now names $nightly (was $current)"
