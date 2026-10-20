#!/usr/bin/env bash
# Stores the Apple Distribution certificate used by the TestFlight workflow.
#
#   ./ci/setup-signing-certificate.sh ~/Desktop/distribution.p12
#
# Export the certificate from Keychain Access (My Certificates → "Apple Distribution: …"
# → Export, .p12 format, with a password). The password is read without echo and both
# values go straight to GitHub through gh. Delete the .p12 afterwards.
set -euo pipefail

if [ $# -ne 1 ]; then
  sed -n '4p' "$0" | sed 's/^#   //'
  exit 64
fi

p12_path=$1
[ -f "$p12_path" ] || { echo "File not found: $p12_path" >&2; exit 1; }

read -r -s -p "Password of the .p12: " password
echo

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
base64 -i "$p12_path" | gh secret set DIST_CERT_P12 --repo "$repo"
printf '%s' "$password" | gh secret set DIST_CERT_PASSWORD --repo "$repo"

echo "Certificate stored on $repo."
