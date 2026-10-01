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

# PIDs of this user's processes whose executable is one of the installed
# bundle's three binaries. `ps -o comm=` reports the executable path (not the
# argv), so the comparison is an exact, literal string match: spaces and regex
# metacharacters in "Open in Agent.app" need no escaping, and a same-user
# development copy running an identically named binary from Xcode or .build is
# left untouched because its path differs.
installed_component_pids() {
  local uid pid executable
  uid="$(/usr/bin/id -u)"
  local finder_executable="$extension_path/Contents/MacOS/OpenInAgentFinderExtension"
  local copy_path_executable="$copy_path_extension_path/Contents/MacOS/CopyPathFinderExtension"
  local app_executable="$destination/Contents/MacOS/Open in Agent"

  while read -r pid executable; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if [[ "$executable" == "$finder_executable" \
      || "$executable" == "$copy_path_executable" \
      || "$executable" == "$app_executable" ]]
    then
      printf '%s\n' "$pid"
    fi
  done < <(/bin/ps -ww -U "$uid" -o pid= -o comm= 2>/dev/null)
}

stop_installed_components() {
  # Only this user's processes count, and only those running the installed
  # bundle's own executables (see installed_component_pids): another logged-in
  # user's copy must not stall the wait below, and we must never signal a
  # process we do not own or a development copy of the same-named binary.

  # Unregister before killing so Finder cannot respawn the extensions while we
  # wait for them to exit.
  if [[ -d "$extension_path" ]]; then
    /usr/bin/pluginkit -r "$extension_path" >/dev/null 2>&1 || true
  fi
  if [[ -d "$copy_path_extension_path" ]]; then
    /usr/bin/pluginkit -r "$copy_path_extension_path" >/dev/null 2>&1 || true
  fi

  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && /bin/kill -TERM "$pid" 2>/dev/null || true
  done < <(installed_component_pids)

  local attempt
  for attempt in {1..30}; do
    if [[ -z "$(installed_component_pids)" ]]; then
      return
    fi
    sleep 0.1
  done

  # The existing install stays in place, so put its extensions back; otherwise
  # the "not changed" claim below would be false and Finder integration would
  # be left unregistered with no backup for the rollback trap to restore.
  if [[ -d "$extension_path" ]]; then
    /usr/bin/pluginkit -a "$extension_path" >/dev/null 2>&1 || true
  fi
  if [[ -d "$copy_path_extension_path" ]]; then
    /usr/bin/pluginkit -a "$copy_path_extension_path" >/dev/null 2>&1 || true
  fi

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

backup=""
commit_done=0
cleanup() {
  # Roll back a half-finished upgrade: if the destination was already swapped
  # for the new (still-unverified) app and we did not reach a clean finish,
  # remove it and restore the known-good backup, then re-register it. Otherwise
  # the old app is lost to the backup directory and the Mac is left with no
  # working install.
  if [[ "$commit_done" != "1" && -n "$backup" && -e "$backup" ]]; then
    if [[ -e "$destination" && ! -e "$staged_app" ]]; then
      rm -rf "$destination" || true
    fi
    if [[ ! -e "$destination" ]] && mv "$backup" "$destination"; then
      "$launch_services_register" -f "$destination" >/dev/null 2>&1 || true
      /usr/bin/pluginkit -a "$extension_path" >/dev/null 2>&1 || true
      /usr/bin/pluginkit -a "$copy_path_extension_path" >/dev/null 2>&1 || true
      echo "Restored the previous app from backup after a failed install." >&2
    fi
  fi
  if [[ -d "$staging_root" ]]; then
    rm -rf "$staging_root"
  fi
}
trap cleanup EXIT

/usr/bin/ditto "$source_app" "$staged_app"
verify_bundle "$staged_app"
stop_installed_components

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

# The staged build is byte-identical to what was just installed. If that copy
# is registered as well (LaunchServices registers an app the moment it is run
# or scanned), PlugInKit keeps it and never lists the installed one, so the
# duplicate check below fails. Only the installed copy may stay registered.
/usr/bin/pluginkit -r \
  "$source_app/Contents/PlugIns/OpenInAgentFinderExtension.appex" >/dev/null 2>&1 || true
/usr/bin/pluginkit -r \
  "$source_app/Contents/PlugIns/CopyPathFinderExtension.appex" >/dev/null 2>&1 || true
"$launch_services_register" -u "$source_app" >/dev/null 2>&1 || true

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

# Every post-swap check passed; keep the new app and stop the rollback trap
# from restoring the backup on exit.
commit_done=1

echo "Installed $destination"
echo "Enabled Finder extension $extension_bundle_id"
echo "Enabled Finder extension $copy_path_extension_bundle_id"
echo "Use Finder > View > Customize Toolbar to add Open in Agent and Copy Path."
