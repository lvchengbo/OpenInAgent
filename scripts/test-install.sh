#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/openinagent-install-test.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

# Test the real EXIT-trap function with temporary bundles and mocked OS
# registrations. No signed app is replaced and no live registration is touched.
cleanup_source="$(awk '
  /^cleanup\(\) \{/ { capturing = 1 }
  /^trap cleanup EXIT/ { exit }
  capturing { print }
' "$repo_root/scripts/install.sh")"
[[ -n "$cleanup_source" ]] || { echo "ERROR: installer cleanup function missing" >&2; exit 1; }
cleanup_source="${cleanup_source//\/usr\/bin\/pluginkit/mock_pluginkit}"
eval "$cleanup_source"

run_scenario() (
  local scenario="$1"
  local root="$fixture_root/$scenario"
  mkdir -p "$root"
  destination="$root/Open in Agent.app"
  staging_root="$root/staging"
  staged_app="$staging_root/Open in Agent.app"
  extension_path="$destination/Contents/PlugIns/Agent.appex"
  copy_path_extension_path="$destination/Contents/PlugIns/Copy.appex"
  extension_bundle_id="test.agent"
  copy_path_extension_bundle_id="test.copy"
  launch_services_register="mock_lsregister"
  registrations="$root/registrations"
  backup=""
  commit_done=0
  components_stopped=1
  destination_replaced=0
  mkdir -p "$staging_root"
  : > "$registrations"

  mock_pluginkit() { printf 'plugin %s\n' "$*" >> "$registrations"; }
  mock_lsregister() { printf 'launch-services %s\n' "$*" >> "$registrations"; }
  register_installed_components() { printf 'register\n' >> "$registrations"; }
  unregister_installed_components() { printf 'unregister\n' >> "$registrations"; }

  case "$scenario" in
    pre-swap)
      mkdir -p "$destination"
      touch "$destination/old-version"
      cleanup
      [[ -f "$destination/old-version" && -s "$registrations" ]] || return 1
      ;;
    first-install)
      destination_replaced=1
      mkdir -p "$destination"
      touch "$destination/failed-version"
      cleanup
      [[ ! -e "$destination" ]] || return 1
      ;;
    upgrade)
      destination_replaced=1
      backup="$root/previous.backup"
      mkdir -p "$backup" "$destination"
      touch "$backup/old-version" "$destination/failed-version"
      cleanup
      [[ -f "$destination/old-version" && ! -e "$destination/failed-version" ]] || return 1
      [[ ! -e "$backup" && -s "$registrations" ]] || return 1
      ;;
    move-failed)
      backup="$root/nonexistent.backup"
      mkdir -p "$destination"
      touch "$destination/old-version"
      cleanup
      [[ -f "$destination/old-version" && -s "$registrations" ]] || return 1
      ;;
    before-stop)
      components_stopped=0
      mkdir -p "$destination"
      touch "$destination/old-version"
      cleanup
      [[ -f "$destination/old-version" && ! -s "$registrations" ]] || return 1
      ;;
    committed)
      commit_done=1
      destination_replaced=1
      mkdir -p "$destination"
      touch "$destination/new-version"
      cleanup
      [[ -f "$destination/new-version" && ! -s "$registrations" ]] || return 1
      ;;
  esac
  [[ ! -e "$staging_root" ]]
)

failed=0
for scenario in pre-swap first-install upgrade move-failed before-stop committed; do
  if (set -e; run_scenario "$scenario"); then
    echo "PASS: installer rollback $scenario"
  else
    echo "FAIL: installer rollback $scenario" >&2
    failed=$((failed + 1))
  fi
done
[[ "$failed" == 0 ]]
