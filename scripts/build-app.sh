#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"

case "$configuration" in
  debug|release) ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

app_name="Open in Agent"
product_name="OpenInAgent"
bundle_id="com.lvchengbo.openinagent"
build_root="$repo_root/.build/app"
app_bundle="$build_root/$app_name.app"
icon_source="$repo_root/OpenInAgent.icon/Assets/agent-spark.png"
signing_mode="${OPEN_IN_AGENT_SIGNING:-adhoc}"
signing_identity="${OPEN_IN_AGENT_SIGN_IDENTITY:-}"
marketing_version="${MARKETING_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_root/Info.plist")}"
build_number="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$repo_root/Info.plist")}"

if [[ "$build_root" != "$repo_root/.build/app" ]]; then
  echo "Refusing unexpected build root: $build_root" >&2
  exit 1
fi

architectures=()
if [[ -n "${ARCHES:-}" ]]; then
  IFS=' ' read -r -a architectures <<< "$ARCHES"
else
  architectures=("$(uname -m)")
fi

verify_architectures() {
  local binary="$1"
  local actual
  actual="$(lipo -archs "$binary")"

  for architecture in "${architectures[@]}"; do
    if [[ "$actual" != *"$architecture"* ]]; then
      echo "ERROR: $binary is missing $architecture (contains: $actual)" >&2
      exit 1
    fi
  done
}

build_architecture() {
  local architecture="$1"
  local scratch_path="$build_root/swiftpm/$architecture"
  local binary_directory
  local source_binary
  local staged_directory="$build_root/arch-products/$architecture"

  swift build \
    --package-path "$repo_root" \
    --scratch-path "$scratch_path" \
    --configuration "$configuration" \
    --arch "$architecture" \
    --product "$product_name"

  binary_directory="$(swift build \
    --package-path "$repo_root" \
    --scratch-path "$scratch_path" \
    --configuration "$configuration" \
    --arch "$architecture" \
    --show-bin-path)"
  source_binary="$binary_directory/$product_name"

  if [[ ! -f "$source_binary" ]]; then
    echo "ERROR: SwiftPM did not produce $source_binary" >&2
    exit 1
  fi

  mkdir -p "$staged_directory"
  cp "$source_binary" "$staged_directory/$product_name"
  chmod +x "$staged_directory/$product_name"
}

install_executable() {
  local destination="$1"
  local binaries=()
  local architecture

  for architecture in "${architectures[@]}"; do
    binaries+=("$build_root/arch-products/$architecture/$product_name")
  done

  if [[ ${#binaries[@]} -eq 1 ]]; then
    cp "${binaries[0]}" "$destination"
  else
    lipo -create "${binaries[@]}" -output "$destination"
  fi
  chmod +x "$destination"
  verify_architectures "$destination"
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

echo "Building $app_name ($configuration) for ${architectures[*]}"
rm -rf "$build_root"
mkdir -p "$build_root"

for architecture in "${architectures[@]}"; do
  build_architecture "$architecture"
done

mkdir -p \
  "$app_bundle/Contents/MacOS" \
  "$app_bundle/Contents/Resources/English.lproj" \
  "$app_bundle/Contents/Resources/LICENSES"

install_executable "$app_bundle/Contents/MacOS/$app_name"
compile_app_icon "$app_bundle/Contents/Resources"
cp "$repo_root/English.lproj/InfoPlist.strings" \
  "$app_bundle/Contents/Resources/English.lproj/InfoPlist.strings"
cp "$repo_root/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$repo_root/LICENSE" "$app_bundle/Contents/Resources/LICENSE"
cp "$repo_root/THIRD_PARTY_NOTICES.md" \
  "$app_bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$repo_root/LICENSES/OpenInTerminal.txt" \
  "$app_bundle/Contents/Resources/LICENSES/OpenInTerminal.txt"
cp "$repo_root/LICENSES/OpenInCode.txt" \
  "$app_bundle/Contents/Resources/LICENSES/OpenInCode.txt"
cp "$repo_root/LICENSES/ClaudeLauncher.txt" \
  "$app_bundle/Contents/Resources/LICENSES/ClaudeLauncher.txt"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" \
  "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $marketing_version" \
  "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" \
  "$app_bundle/Contents/Info.plist"
plutil -lint "$app_bundle/Contents/Info.plist" >/dev/null

case "$signing_mode" in
  unsigned|none)
    echo "Leaving app unsigned"
    ;;
  adhoc)
    echo "Applying ad-hoc hardened-runtime signature"
    codesign --force --options runtime --timestamp=none \
      --entitlements "$repo_root/OpenInAgent.entitlements" \
      --sign - "$app_bundle"
    codesign --verify --deep --strict --verbose=2 "$app_bundle"
    ;;
  identity)
    if [[ -z "$signing_identity" ]]; then
      echo "ERROR: OPEN_IN_AGENT_SIGN_IDENTITY is required for identity signing" >&2
      exit 2
    fi
    echo "Applying hardened-runtime signature with $signing_identity"
    codesign --force --options runtime --timestamp=none \
      --entitlements "$repo_root/OpenInAgent.entitlements" \
      --sign "$signing_identity" "$app_bundle"
    codesign --verify --deep --strict --verbose=2 "$app_bundle"
    ;;
  *)
    echo "ERROR: OPEN_IN_AGENT_SIGNING must be 'adhoc', 'identity', 'unsigned', or 'none'" >&2
    exit 2
    ;;
esac

echo "Built $app_bundle"
echo "Architectures: $(lipo -archs "$app_bundle/Contents/MacOS/$app_name")"
echo "Version: $marketing_version ($build_number)"
