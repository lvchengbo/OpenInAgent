#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$repo_root/.build/app/Open in Agent.app"
install_root="${OPEN_IN_AGENT_INSTALL_DIR:-$HOME/Applications}"
backup_root="${OPEN_IN_AGENT_BACKUP_DIR:-$HOME/Library/Application Support/OpenInAgent/Backups}"
destination="$install_root/Open in Agent.app"

if [[ "${1:-}" != "--no-build" ]]; then
  "$repo_root/scripts/build-app.sh" release
fi

if [[ ! -d "$source_app" ]]; then
  echo "ERROR: Build first; $source_app does not exist." >&2
  exit 1
fi

mkdir -p "$install_root"

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

/usr/bin/ditto "$source_app" "$destination"
codesign --verify --deep --strict --verbose=2 "$destination"

echo "Installed $destination"
echo "Hold Command and drag the app into Finder's toolbar."
