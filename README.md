# OpenInAgent

OpenInAgent is a tiny macOS utility for launching a command-line AI agent from
the item currently selected in Finder. It is designed to live as one icon in
Finder’s toolbar.

| Menu item | Terminal | Command |
|---|---|---|
| Claude | Ghostty | `claude` |
| Codex | iTerm | `codex` |
| Grok | iTerm | `grok` |
| AGY | iTerm | `agy` |

Selecting a folder uses that folder as the working directory. Selecting a file
or package uses its parent directory. With no selection, the front Finder
window’s folder is used. OpenInAgent never silently falls back to the home
directory.

## Build and verify

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools with Swift 6.2 or newer
- Ghostty and iTerm
- whichever agent CLIs you want to launch

Run the complete non-GUI verification:

```sh
cd /Users/joker/Projects/OpenInAgent
./scripts/verify.sh
```

The built app is written to:

```text
.build/app/Open in Agent.app
```

## Install

Install a stable copy in `~/Applications`:

```sh
./scripts/install.sh --no-build
```

On upgrade, the previous copy is preserved under
`~/Library/Application Support/OpenInAgent/Backups` with a non-app suffix so
LaunchServices sees only the current installation.

Confirm the installed copy can see all four commands and both terminals without
opening an agent:

```sh
"$HOME/Applications/Open in Agent.app/Contents/MacOS/Open in Agent" --diagnose
```

Then:

1. Open `~/Applications` in Finder.
2. Hold Command and drag **Open in Agent** into Finder’s toolbar.
3. Select a project folder or a file inside one.
4. Click the toolbar icon and choose an agent.

On first use, macOS asks permission to read Finder. The first iTerm launch may
also ask permission to control iTerm. If access was denied, enable it under
System Settings → Privacy & Security → Automation.

The toolbar position is managed entirely by Finder. OpenInAgent deliberately
does not edit Finder preferences, restart Finder, or install a Finder Sync
extension.

### Signing upgrades

Local builds use an ad-hoc hardened-runtime signature by default. The app is
fully usable, but macOS may ask for Finder/iTerm Automation permission again
after a rebuild because an ad-hoc identity is tied to that exact binary.

If this Mac later has a stable code-signing identity, build with it to preserve
the app identity across upgrades:

```sh
OPEN_IN_AGENT_SIGNING=identity \
OPEN_IN_AGENT_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
./scripts/build-app.sh release
```

Public distribution additionally requires Developer ID signing and Apple
notarization; this repository currently targets a personal local installation.

## Security model

- Finder is queried with one constant AppleScript; paths are never inserted
  into its source.
- Claude is launched in Ghostty with discrete `NSWorkspace` arguments.
- iTerm receives an opaque command through `osascript` argv. iTerm 3.6.11
  parses that command into process arguments and launches `/usr/bin/env`
  directly; no shell is involved.
- Every CLI is resolved to an absolute executable path before launch.
- Resolution uses the configured per-user locations plus fixed system and
  Homebrew directories; it never trusts the parent process’s `PATH`.
- There is no `sh -c`, keystroke injection, editable command template, or
  permission-bypass flag.
- Tests cover quotes, backslashes, `$()`, backticks, separators, newlines,
  leading dashes, and Unicode in selected paths.

See [SECURITY.md](SECURITY.md) for the detailed boundaries.

## Project layout

```text
Sources/OpenInAgent/       App, Finder resolver, menu, and launchers
Tests/OpenInAgentTests/    Resolver, routing, transport, and adversarial tests
OpenInAgent.icon/          Original Finder/app icon definition
scripts/build-app.sh       Reproducible `.app` packaging and local signing
scripts/install.sh         Stable per-user installation
scripts/verify.sh          Full automated verification
```

OpenInAgent is MIT licensed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
for the exact upstream references used during design.
