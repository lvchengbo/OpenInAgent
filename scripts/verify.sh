#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="$repo_root/.build/app/Open in Agent.app"
extension="$app/Contents/PlugIns/OpenInAgentFinderExtension.appex"
extension_executable="$extension/Contents/MacOS/OpenInAgentFinderExtension"
copy_path_extension="$app/Contents/PlugIns/CopyPathFinderExtension.appex"
copy_path_extension_executable="$copy_path_extension/Contents/MacOS/CopyPathFinderExtension"
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
plutil -lint "$copy_path_extension/Contents/Info.plist"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "com.lvchengbo.openinagent" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app/Contents/Info.plist")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$app/Contents/Info.plist")" == "openinagent" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension/Contents/Info.plist")" == "com.lvchengbo.openinagent.finderextension" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$extension/Contents/Info.plist")" == "com.apple.FinderSync" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPrincipalClass' "$extension/Contents/Info.plist")" == "OpenInAgentFinderExtension.FinderSync" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$copy_path_extension/Contents/Info.plist")" == "com.lvchengbo.openinagent.copypath.finderextension" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$copy_path_extension/Contents/Info.plist")" == "com.apple.FinderSync" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPrincipalClass' "$copy_path_extension/Contents/Info.plist")" == "CopyPathFinderExtension.FinderSync" ]]

[[ -x "$app/Contents/MacOS/Open in Agent" ]]
[[ -x "$extension_executable" ]]
[[ -x "$copy_path_extension_executable" ]]
[[ -f "$app/Contents/Resources/OpenInAgent.icns" ]]
[[ -f "$app/Contents/Resources/LICENSE" ]]
[[ -f "$app/Contents/Resources/THIRD_PARTY_NOTICES.md" ]]
[[ -f "$app/Contents/Resources/LICENSES/OpenInTerminal.txt" ]]
[[ -f "$app/Contents/Resources/LICENSES/OpenInCode.txt" ]]
[[ -f "$app/Contents/Resources/LICENSES/ClaudeLauncher.txt" ]]

main_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
extension_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$extension/Contents/Info.plist")"
copy_path_extension_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$copy_path_extension/Contents/Info.plist")"
main_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
extension_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$extension/Contents/Info.plist")"
copy_path_extension_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$copy_path_extension/Contents/Info.plist")"
[[ "$main_version" == "$extension_version" ]]
[[ "$main_version" == "$copy_path_extension_version" ]]
[[ "$main_build" == "$extension_build" ]]
[[ "$main_build" == "$copy_path_extension_build" ]]

if [[ "$signing_mode" != "unsigned" && "$signing_mode" != "none" ]]; then
  codesign --verify --deep --strict --verbose=2 "$app"
  codesign --verify --strict --verbose=2 "$extension"
  codesign --verify --strict --verbose=2 "$copy_path_extension"

  extension_sandbox="$(codesign -d --entitlements :- "$extension" 2>/dev/null \
    | plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - -)"
  [[ "$extension_sandbox" == "true" ]]

  copy_path_extension_sandbox="$(codesign -d --entitlements :- "$copy_path_extension" 2>/dev/null \
    | plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - -)"
  [[ "$copy_path_extension_sandbox" == "true" ]]

  app_automation="$(codesign -d --entitlements :- "$app" 2>/dev/null \
    | plutil -extract 'com\.apple\.security\.automation\.apple-events' raw -o - -)"
  [[ "$app_automation" == "true" ]]
else
  echo "WARNING: OPEN_IN_AGENT_SIGNING=$signing_mode — code signatures, the" \
    "extension sandbox entitlement, and the app's Apple Events entitlement" \
    "were NOT verified. This artifact's security model is unverified and it is" \
    "not installable as-is." >&2
fi

# Shell evaluation of launch data is prohibited. LoginShell.swift is the one
# sanctioned `-c` site: its program is a constant and data travels in argv.
if grep -rnE --include='*.swift' --exclude='LoginShell.swift' \
  'dangerously-skip-permissions|dangerously-bypass|/bin/(ba)?sh.*-c|/bin/zsh.*-c' \
  "$repo_root/Sources"; then
  echo "ERROR: unsafe launch pattern found in application sources" >&2
  exit 1
fi

if grep -nE 'exec \\"\$@\\"|exec \$argv' "$repo_root/Sources/OpenInAgent/LoginShell.swift" \
  | grep -vE '^[0-9]+:\s+"exec (\\"\$@\\"|\$argv)"$' >/dev/null; then
  echo "ERROR: LoginShell program must remain a bare constant" >&2
  exit 1
fi

# The check above is fail-open: if both approved constants were deleted it
# would find nothing and pass. Positively require exactly one of each.
login_shell_source="$repo_root/Sources/OpenInAgent/LoginShell.swift"
posix_constants="$(grep -cE '^\s+"exec \\"\$@\\""$' "$login_shell_source" || true)"
fish_constants="$(grep -cE '^\s+"exec \$argv"$' "$login_shell_source" || true)"
if [[ "$posix_constants" != "1" || "$fish_constants" != "1" ]]; then
  echo "ERROR: LoginShell must define exactly one POSIX and one fish program constant" \
    "(found $posix_constants POSIX, $fish_constants fish)" >&2
  exit 1
fi

if grep -rnE --include='*.swift' \
  'NSAppleScript|osascript|Process\s*\(|/bin/(ba)?sh|/bin/zsh' \
  "$repo_root/Sources/OpenInAgentFinderExtension" \
  "$repo_root/Sources/CopyPathFinderExtension"; then
  echo "ERROR: shell or AppleScript usage found in Finder extension" >&2
  exit 1
fi

if grep -n 'representedObject' \
  "$repo_root/Sources/OpenInAgentFinderExtension/FinderSync.swift" \
  "$repo_root/Sources/CopyPathFinderExtension/FinderSync.swift"; then
  echo "ERROR: Finder Sync does not preserve custom representedObject payloads" >&2
  exit 1
fi

if [[ "$signing_mode" == "unsigned" || "$signing_mode" == "none" ]]; then
  echo "Verification passed (compile-only, UNSIGNED): $app"
  echo "Signatures and entitlements were not verified; do not install this artifact." >&2
else
  echo "Verification passed: $app"
fi
echo "Finder extension verified: $extension"
echo "Copy Path extension verified: $copy_path_extension"
