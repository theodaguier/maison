#!/usr/bin/env bash
# Affiche l'UDID du simulateur iPhone disponible le plus récent (runtime iOS le plus haut).
set -euo pipefail
xcrun simctl list devices available --json \
  | jq -r '
      .devices
      | to_entries
      | map(select(.key | test("iOS")))
      | sort_by(.key | capture("iOS-(?<maj>[0-9]+)-(?<min>[0-9]+)") | [(.maj|tonumber), (.min|tonumber)])
      | reverse
      | map(.value[] | select(.name | startswith("iPhone")))
      | first
      | .udid'
