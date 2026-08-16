#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="$repo_root/.build/app/Open in Agent.app"

bash -n \
  "$repo_root/scripts/build-app.sh" \
  "$repo_root/scripts/install.sh" \
  "$repo_root/scripts/verify.sh"
xcrun swift-format lint --strict --recursive \
  "$repo_root/Sources" \
  "$repo_root/Tests" \
  "$repo_root/Package.swift"
swift test --package-path "$repo_root" --parallel \
  -Xswiftc -warnings-as-errors
"$repo_root/scripts/build-app.sh" release

plutil -lint "$app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "com.lvchengbo.openinagent" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app/Contents/Info.plist")" == "true" ]]
[[ -x "$app/Contents/MacOS/Open in Agent" ]]
[[ -f "$app/Contents/Resources/OpenInAgent.icns" ]]
[[ -f "$app/Contents/Resources/LICENSE" ]]
[[ -f "$app/Contents/Resources/THIRD_PARTY_NOTICES.md" ]]
[[ -f "$app/Contents/Resources/LICENSES/OpenInTerminal.txt" ]]
[[ -f "$app/Contents/Resources/LICENSES/OpenInCode.txt" ]]
[[ -f "$app/Contents/Resources/LICENSES/ClaudeLauncher.txt" ]]

if rg -n --glob '*.swift' \
  'dangerously-skip-permissions|dangerously-bypass|/bin/(ba)?sh.*-c|/bin/zsh.*-c' \
  "$repo_root/Sources"; then
  echo "ERROR: unsafe launch pattern found in application sources" >&2
  exit 1
fi

echo "Verification passed: $app"
