#!/usr/bin/env bash
# Stores the GitHub secrets required by the TestFlight workflow.
#
#   ./ci/setup-testflight.sh ~/Downloads/AuthKey_XXXXXXXXXX.p8 <issuer-id> [team-id]
#
# The key ID is read from the file name and the team ID from project.yml unless
# given. Values go straight to GitHub through gh and are never printed. You can
# delete the local .p8 afterwards.
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  sed -n '4p' "$0" | sed 's/^#   //'
  exit 64
fi

key_path=$1 issuer_id=$2
team_id=${3:-$(sed -nE 's/^ *DEVELOPMENT_TEAM: *([A-Z0-9]{10}).*/\1/p' project.yml | head -1)}
key_id=$(basename "$key_path" .p8)
key_id=${key_id#AuthKey_}

[ -f "$key_path" ] || { echo "File not found: $key_path" >&2; exit 1; }
[[ $team_id =~ ^[A-Z0-9]{10}$ ]] || { echo "Expected a 10-character team ID" >&2; exit 1; }

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh secret set ASC_KEY_P8 --repo "$repo" < "$key_path"
printf '%s' "$key_id" | gh secret set ASC_KEY_ID --repo "$repo"
printf '%s' "$issuer_id" | gh secret set ASC_ISSUER_ID --repo "$repo"
printf '%s' "$team_id" | gh secret set APPLE_TEAM_ID --repo "$repo"

echo "Secrets stored on $repo. To release: git tag vX.Y.Z && git push origin vX.Y.Z"
