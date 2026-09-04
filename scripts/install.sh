#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$repo_root/.build/app/Open in Agent.app"
install_root="${OPEN_IN_AGENT_INSTALL_DIR:-$HOME/Applications}"
backup_root="${OPEN_IN_AGENT_BACKUP_DIR:-$HOME/Library/Application Support/OpenInAgent/Backups}"
destination="$install_root/Open in Agent.app"
extension_bundle_id="com.lvchengbo.openinagent.finderextension"
extension_path="$destination/Contents/PlugIns/OpenInAgentFinderExtension.appex"
copy_path_extension_bundle_id="com.lvchengbo.openinagent.copypath.finderextension"
copy_path_extension_path="$destination/Contents/PlugIns/CopyPathFinderExtension.appex"
launch_services_register="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

verify_bundle() {
  local app="$1"
  local extension="$app/Contents/PlugIns/OpenInAgentFinderExtension.appex"
  local copy_path_extension="$app/Contents/PlugIns/CopyPathFinderExtension.appex"

  codesign --verify --deep --strict --verbose=2 "$app"
  codesign --verify --strict --verbose=2 "$extension"
  codesign --verify --strict --verbose=2 "$copy_path_extension"
}

stop_installed_components() {
  if [[ -d "$extension_path" ]]; then
    /usr/bin/pluginkit -r "$extension_path" >/dev/null 2>&1 || true
  fi
  if [[ -d "$copy_path_extension_path" ]]; then
    /usr/bin/pluginkit -r "$copy_path_extension_path" >/dev/null 2>&1 || true
  fi

  /usr/bin/pkill -TERM -x OpenInAgentFinderExtension 2>/dev/null || true
  /usr/bin/pkill -TERM -x CopyPathFinderExtension 2>/dev/null || true
  /usr/bin/pkill -TERM -x "Open in Agent" 2>/dev/null || true

  local attempt
  for attempt in {1..30}; do
    if ! /usr/bin/pgrep -x OpenInAgentFinderExtension >/dev/null \
      && ! /usr/bin/pgrep -x CopyPathFinderExtension >/dev/null \
      && ! /usr/bin/pgrep -x "Open in Agent" >/dev/null
    then
      return
    fi
    sleep 0.1
  done

  echo "ERROR: Open in Agent is still running; installation was not changed." >&2
  exit 1
}

if [[ "${1:-}" != "--no-build" ]]; then
  "$repo_root/scripts/build-app.sh" release
fi

if [[ ! -d "$source_app" ]]; then
  echo "ERROR: Build first; $source_app does not exist." >&2
  exit 1
fi

mkdir -p "$install_root"

staging_root="$(mktemp -d "$install_root/.open-in-agent-install.XXXXXX")"
case "$staging_root" in
  "$install_root"/.open-in-agent-install.*) ;;
  *)
    echo "ERROR: Refusing unexpected staging directory: $staging_root" >&2
    exit 1
    ;;
esac
staged_app="$staging_root/Open in Agent.app"

cleanup_staging() {
  if [[ -d "$staging_root" ]]; then
    rm -rf "$staging_root"
  fi
}
trap cleanup_staging EXIT

/usr/bin/ditto "$source_app" "$staged_app"
verify_bundle "$staged_app"
stop_installed_components

backup=""
if [[ -e "$destination" ]]; then
  mkdir -p "$backup_root"
  chmod 700 "$backup_root"
  timestamp="$(date +%Y%m%d_%H%M%S)"
  backup="$backup_root/Open in Agent.$timestamp.app.backup"
  suffix=1
  while [[ -e "$backup" ]]; do
    backup="$backup_root/Open in Agent.$timestamp.$suffix.app.backup"
    ((suffix += 1))
  done
  mv "$destination" "$backup"
  echo "Previous app moved to $backup"
fi

if ! mv "$staged_app" "$destination"; then
  if [[ -n "$backup" && -e "$backup" && ! -e "$destination" ]]; then
    mv "$backup" "$destination"
  fi
  echo "ERROR: Could not replace $destination; the previous app was restored." >&2
  exit 1
fi
verify_bundle "$destination"

"$launch_services_register" -f "$destination"
/usr/bin/pluginkit -a "$extension_path"
/usr/bin/pluginkit -a "$copy_path_extension_path"
/usr/bin/pluginkit -e use -i "$extension_bundle_id"
/usr/bin/pluginkit -e use -i "$copy_path_extension_bundle_id"

verify_registration() {
  local bundle_id="$1"
  local expected_path="$2"
  local registration
  local registration_matches
  local registration_count

  registration="$(/usr/bin/pluginkit -m -A -D -v -i "$bundle_id")"
  registration_matches="$(printf '%s\n' "$registration" | grep -F "$bundle_id" || true)"
  registration_count="$(printf '%s\n' "$registration_matches" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$registration_count" != "1" ]] \
    || [[ "$registration_matches" != *"$expected_path"* ]]
  then
    echo "ERROR: Finder extension did not register: $bundle_id" >&2
    printf '%s\n' "$registration" >&2
    exit 1
  fi
}

verify_registration "$extension_bundle_id" "$extension_path"
verify_registration \
  "$copy_path_extension_bundle_id" \
  "$copy_path_extension_path"

echo "Installed $destination"
echo "Enabled Finder extension $extension_bundle_id"
echo "Enabled Finder extension $copy_path_extension_bundle_id"
echo "Use Finder > View > Customize Toolbar to add Open in Agent and Copy Path."
