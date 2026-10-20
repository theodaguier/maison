#!/usr/bin/env bash
# Enregistre les secrets GitHub nécessaires au workflow TestFlight.
#
#   ./ci/setup-testflight.sh ~/Downloads/AuthKey_XXXXXXXXXX.p8 <issuer-id> [team-id]
#
# Le Key ID est lu dans le nom du fichier, le Team ID dans project.yml par défaut. Les valeurs vont directement dans
# GitHub via gh, sans être affichées. Supprime le .p8 local ensuite si tu veux.
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  sed -n '4p' "$0" | sed 's/^#   //'
  exit 64
fi

key_path=$1 issuer_id=$2
team_id=${3:-$(sed -nE 's/^ *DEVELOPMENT_TEAM: *([A-Z0-9]{10}).*/\1/p' project.yml | head -1)}
key_id=$(basename "$key_path" .p8)
key_id=${key_id#AuthKey_}

[ -f "$key_path" ] || { echo "Fichier introuvable : $key_path" >&2; exit 1; }
[[ $team_id =~ ^[A-Z0-9]{10}$ ]] || { echo "Team ID attendu sur 10 caractères" >&2; exit 1; }

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh secret set ASC_KEY_P8 --repo "$repo" < "$key_path"
printf '%s' "$key_id" | gh secret set ASC_KEY_ID --repo "$repo"
printf '%s' "$issuer_id" | gh secret set ASC_ISSUER_ID --repo "$repo"
printf '%s' "$team_id" | gh secret set APPLE_TEAM_ID --repo "$repo"

echo "Secrets enregistrés sur $repo. Pour publier : git tag v0.1.0 && git push origin v0.1.0"
