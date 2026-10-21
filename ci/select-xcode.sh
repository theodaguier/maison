#!/usr/bin/env bash
# Prints the path of the newest Xcode that can build Maison (Xcode 26 or later).
# The iOS 26 / Liquid Glass deployment target does not build on older Xcodes.
set -euo pipefail

best_path=""
best_ver=""

shopt -s nullglob
apps=(/Applications/Xcode*.app)
if [[ ${#apps[@]} -eq 0 ]]; then
  echo "No Xcode.app found in /Applications." >&2
  exit 1
fi

for app in "${apps[@]}"; do
  plist="$app/Contents/Info.plist"
  [[ -f "$plist" ]] || continue
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
  [[ -n "$ver" ]] || continue
  echo "Found $app ($ver)" >&2
  if [[ -z "$best_ver" ]]; then
    best_ver="$ver"
    best_path="$app"
    continue
  fi
  smaller="$(printf '%s\n%s\n' "$ver" "$best_ver" | sort -V | head -n 1)"
  # A greater version wins. An equal version keeps the later app path.
  if [[ "$smaller" != "$ver" || "$ver" == "$best_ver" ]]; then
    best_ver="$ver"
    best_path="$app"
  fi
done

if [[ -z "$best_path" ]]; then
  echo "No Xcode with a readable version was found in /Applications." >&2
  exit 1
fi

major="${best_ver%%.*}"
if (( major < 26 )); then
  echo "Newest Xcode on this runner is $best_ver at $best_path. Maison targets iOS 26 and needs Xcode 26 or later." >&2
  exit 1
fi

echo "Selected $best_path ($best_ver)" >&2
printf '%s\n' "$best_path"
