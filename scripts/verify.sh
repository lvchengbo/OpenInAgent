#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="$repo_root/.build/app/Open in Agent.app"
extension="$app/Contents/PlugIns/OpenInAgentFinderExtension.appex"
extension_executable="$extension/Contents/MacOS/OpenInAgentFinderExtension"
signing_mode="${OPEN_IN_AGENT_SIGNING:-adhoc}"

bash -n \
  "$repo_root/scripts/build-app.sh" \
  "$repo_root/scripts/install.sh" \
  "$repo_root/scripts/verify.sh"

command -v xcodegen >/dev/null 2>&1 || {
  echo "ERROR: xcodegen is required. Install it with 'brew install xcodegen'." >&2
  exit 1
}

xcodegen generate --spec "$repo_root/project.yml" \
  --project "$repo_root"
xcodebuild -project "$repo_root/OpenInAgent.xcodeproj" \
  -scheme OpenInAgent -list >/dev/null

xcrun swift-format lint --strict --recursive \
  "$repo_root/Sources" \
  "$repo_root/Tests" \
  "$repo_root/Package.swift"
swift test --package-path "$repo_root" --parallel \
  -Xswiftc -warnings-as-errors
"$repo_root/scripts/build-app.sh" release

plutil -lint "$app/Contents/Info.plist"
plutil -lint "$extension/Contents/Info.plist"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "com.lvchengbo.openinagent" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app/Contents/Info.plist")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$app/Contents/Info.plist")" == "openinagent" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension/Contents/Info.plist")" == "com.lvchengbo.openinagent.finderextension" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$extension/Contents/Info.plist")" == "com.apple.FinderSync" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPrincipalClass' "$extension/Contents/Info.plist")" == "OpenInAgentFinderExtension.FinderSync" ]]

[[ -x "$app/Contents/MacOS/Open in Agent" ]]
[[ -x "$extension_executable" ]]
[[ -f "$app/Contents/Resources/OpenInAgent.icns" ]]
[[ -f "$app/Contents/Resources/LICENSE" ]]
[[ -f "$app/Contents/Resources/THIRD_PARTY_NOTICES.md" ]]
[[ -f "$app/Contents/Resources/LICENSES/OpenInTerminal.txt" ]]
[[ -f "$app/Contents/Resources/LICENSES/OpenInCode.txt" ]]
[[ -f "$app/Contents/Resources/LICENSES/ClaudeLauncher.txt" ]]

main_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
extension_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$extension/Contents/Info.plist")"
main_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
extension_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$extension/Contents/Info.plist")"
[[ "$main_version" == "$extension_version" ]]
[[ "$main_build" == "$extension_build" ]]

if [[ "$signing_mode" != "unsigned" && "$signing_mode" != "none" ]]; then
  codesign --verify --deep --strict --verbose=2 "$app"
  codesign --verify --strict --verbose=2 "$extension"

  extension_sandbox="$(codesign -d --entitlements :- "$extension" 2>/dev/null \
    | plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - -)"
  [[ "$extension_sandbox" == "true" ]]

  app_automation="$(codesign -d --entitlements :- "$app" 2>/dev/null \
    | plutil -extract 'com\.apple\.security\.automation\.apple-events' raw -o - -)"
  [[ "$app_automation" == "true" ]]
fi

if rg -n --glob '*.swift' \
  'dangerously-skip-permissions|dangerously-bypass|/bin/(ba)?sh.*-c|/bin/zsh.*-c' \
  "$repo_root/Sources"; then
  echo "ERROR: unsafe launch pattern found in application sources" >&2
  exit 1
fi

if rg -n --glob '*.swift' \
  'NSAppleScript|osascript|Process\s*\(|/bin/(ba)?sh|/bin/zsh' \
  "$repo_root/Sources/OpenInAgentFinderExtension"; then
  echo "ERROR: shell or AppleScript usage found in Finder extension" >&2
  exit 1
fi

if rg -n 'representedObject' \
  "$repo_root/Sources/OpenInAgentFinderExtension/FinderSync.swift"; then
  echo "ERROR: Finder Sync does not preserve custom representedObject payloads" >&2
  exit 1
fi

echo "Verification passed: $app"
echo "Finder extension verified: $extension"
