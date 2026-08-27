#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration_input="${1:-release}"

case "$configuration_input" in
  debug) configuration="Debug" ;;
  release) configuration="Release" ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

app_name="Open in Agent"
extension_name="OpenInAgentFinderExtension"
copy_path_extension_name="CopyPathFinderExtension"
bundle_id="com.lvchengbo.openinagent"
extension_bundle_id="$bundle_id.finderextension"
copy_path_extension_bundle_id="$bundle_id.copypath.finderextension"
build_root="$repo_root/.build/app"
derived_data="$repo_root/.build/xcode"
app_bundle="$build_root/$app_name.app"
extension_bundle="$app_bundle/Contents/PlugIns/$extension_name.appex"
copy_path_extension_bundle="$app_bundle/Contents/PlugIns/$copy_path_extension_name.appex"
icon_source="$repo_root/OpenInAgent.icon/Assets/agent-spark.png"
signing_mode="${OPEN_IN_AGENT_SIGNING:-adhoc}"
signing_identity="${OPEN_IN_AGENT_SIGN_IDENTITY:-}"
marketing_version="${MARKETING_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_root/Info.plist")}"
build_number="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$repo_root/Info.plist")}"

if [[ "$build_root" != "$repo_root/.build/app" ]]; then
  echo "Refusing unexpected build root: $build_root" >&2
  exit 1
fi

if [[ -n "${ARCHES:-}" ]]; then
  requested_architectures="$ARCHES"
else
  requested_architectures="$(uname -m)"
fi

verify_architectures() {
  local binary="$1"
  local actual
  local architecture
  actual="$(lipo -archs "$binary")"

  for architecture in $requested_architectures; do
    if [[ " $actual " != *" $architecture "* ]]; then
      echo "ERROR: $binary is missing $architecture (contains: $actual)" >&2
      exit 1
    fi
  done
}

compile_app_icon() {
  local resources_directory="$1"
  local partial_info_plist="$build_root/AppIconPartialInfo.plist"

  if [[ ! -f "$icon_source" ]]; then
    swift "$repo_root/tools/render-icon.swift" "$icon_source"
  fi

  xcrun actool "$repo_root/OpenInAgent.icon" \
    --compile "$resources_directory" \
    --notices --warnings --errors \
    --output-partial-info-plist "$partial_info_plist" \
    --app-icon OpenInAgent \
    --enable-on-demand-resources NO \
    --development-region English \
    --target-device mac \
    --minimum-deployment-target 13.0 \
    --platform macosx

  [[ -f "$resources_directory/Assets.car" ]] || {
    echo "ERROR: actool did not produce Assets.car" >&2
    exit 1
  }
  [[ -f "$resources_directory/OpenInAgent.icns" ]] || {
    echo "ERROR: actool did not produce OpenInAgent.icns" >&2
    exit 1
  }
}

stage_resources() {
  local resources_directory="$app_bundle/Contents/Resources"

  mkdir -p \
    "$resources_directory/English.lproj" \
    "$resources_directory/LICENSES"

  compile_app_icon "$resources_directory"
  cp "$repo_root/English.lproj/InfoPlist.strings" \
    "$resources_directory/English.lproj/InfoPlist.strings"
  cp "$repo_root/LICENSE" "$resources_directory/LICENSE"
  cp "$repo_root/THIRD_PARTY_NOTICES.md" \
    "$resources_directory/THIRD_PARTY_NOTICES.md"
  cp "$repo_root/LICENSES/OpenInTerminal.txt" \
    "$resources_directory/LICENSES/OpenInTerminal.txt"
  cp "$repo_root/LICENSES/OpenInCode.txt" \
    "$resources_directory/LICENSES/OpenInCode.txt"
  cp "$repo_root/LICENSES/ClaudeLauncher.txt" \
    "$resources_directory/LICENSES/ClaudeLauncher.txt"
}

set_bundle_metadata() {
  local plist="$1"
  local identifier="$2"

  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $identifier" "$plist"
  /usr/libexec/PlistBuddy -c \
    "Set :CFBundleShortVersionString $marketing_version" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"
  plutil -lint "$plist" >/dev/null
}

sign_bundles() {
  local identity="$1"
  local description="$2"

  echo "$description"
  codesign --force --options runtime --timestamp=none \
    --entitlements "$repo_root/FinderExtension/OpenInAgentFinderExtension.entitlements" \
    --sign "$identity" "$extension_bundle"
  codesign --force --options runtime --timestamp=none \
    --entitlements "$repo_root/FinderExtension/OpenInAgentFinderExtension.entitlements" \
    --sign "$identity" "$copy_path_extension_bundle"
  codesign --force --options runtime --timestamp=none \
    --entitlements "$repo_root/OpenInAgent.entitlements" \
    --sign "$identity" "$app_bundle"
  codesign --verify --deep --strict --verbose=2 "$app_bundle"
}

command -v xcodegen >/dev/null 2>&1 || {
  echo "ERROR: xcodegen is required. Install it with 'brew install xcodegen'." >&2
  exit 1
}

echo "Generating Xcode project"
xcodegen generate --spec "$repo_root/project.yml" \
  --project "$repo_root"

echo "Building $app_name ($configuration) for $requested_architectures"
rm -rf "$build_root"
mkdir -p "$build_root"

xcodebuild \
  -project "$repo_root/OpenInAgent.xcodeproj" \
  -scheme OpenInAgent \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data" \
  ARCHS="$requested_architectures" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$marketing_version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  clean build

built_app="$derived_data/Build/Products/$configuration/$app_name.app"
if [[ ! -d "$built_app" ]]; then
  echo "ERROR: Xcode did not produce $built_app" >&2
  exit 1
fi
built_extension="$built_app/Contents/PlugIns/$extension_name.appex"
built_copy_path_extension="$built_app/Contents/PlugIns/$copy_path_extension_name.appex"

/usr/bin/ditto "$built_app" "$app_bundle"

if [[ ! -d "$extension_bundle" ]]; then
  echo "ERROR: Xcode did not embed $extension_bundle" >&2
  exit 1
fi
if [[ ! -d "$copy_path_extension_bundle" ]]; then
  echo "ERROR: Xcode did not embed $copy_path_extension_bundle" >&2
  exit 1
fi

stage_resources
set_bundle_metadata "$app_bundle/Contents/Info.plist" "$bundle_id"
set_bundle_metadata "$extension_bundle/Contents/Info.plist" "$extension_bundle_id"
set_bundle_metadata \
  "$copy_path_extension_bundle/Contents/Info.plist" \
  "$copy_path_extension_bundle_id"

verify_architectures "$app_bundle/Contents/MacOS/$app_name"
verify_architectures "$extension_bundle/Contents/MacOS/$extension_name"
verify_architectures \
  "$copy_path_extension_bundle/Contents/MacOS/$copy_path_extension_name"

case "$signing_mode" in
  unsigned|none)
    echo "Leaving app and extension unsigned"
    ;;
  adhoc)
    sign_bundles - "Applying ad-hoc hardened-runtime signatures"
    ;;
  identity)
    if [[ -z "$signing_identity" ]]; then
      echo "ERROR: OPEN_IN_AGENT_SIGN_IDENTITY is required for identity signing" >&2
      exit 2
    fi
    sign_bundles "$signing_identity" \
      "Applying hardened-runtime signatures with $signing_identity"
    ;;
  *)
    echo "ERROR: OPEN_IN_AGENT_SIGNING must be 'adhoc', 'identity', 'unsigned', or 'none'" >&2
    exit 2
    ;;
esac

echo "Built $app_bundle"
echo "App architectures: $(lipo -archs "$app_bundle/Contents/MacOS/$app_name")"
echo "Extension architectures: $(lipo -archs "$extension_bundle/Contents/MacOS/$extension_name")"
echo "Copy Path extension architectures: $(lipo -archs "$copy_path_extension_bundle/Contents/MacOS/$copy_path_extension_name")"
echo "Version: $marketing_version ($build_number)"

# Xcode registers development products during a normal macOS build. Remove
# those transient copies so Finder and URL dispatch see only the stable install.
launch_services_register="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
/usr/bin/pluginkit -r "$built_extension" >/dev/null 2>&1 || true
/usr/bin/pluginkit -r "$built_copy_path_extension" >/dev/null 2>&1 || true
/usr/bin/pluginkit -r "$extension_bundle" >/dev/null 2>&1 || true
/usr/bin/pluginkit -r "$copy_path_extension_bundle" >/dev/null 2>&1 || true
"$launch_services_register" -u "$built_app" >/dev/null 2>&1 || true
"$launch_services_register" -u "$app_bundle" >/dev/null 2>&1 || true
