# OpenInAgent

OpenInAgent is a small macOS utility that adds a native AI-agent menu to
Finder’s toolbar. Select a file or folder, click the monochrome toolbar button,
and launch the matching CLI in its preferred terminal.

| Menu item | Terminal | Command |
|---|---|---|
| Claude | Ghostty | `claude` |
| Codex | iTerm | `codex` |
| Grok | iTerm | `grok` |
| AGY | iTerm | `agy` |

Selecting a folder uses that folder as the working directory. Selecting a file
or package uses its parent directory. OpenInAgent never silently falls back to
the home directory.

## Why it uses a Finder extension

Command-dragging an application into Finder creates a generic file shortcut.
Finder therefore shows the colored app icon and literal bundle filename, and
the shortcut cannot own a native dropdown menu.

OpenInAgent instead embeds a sandboxed Finder Sync extension. Finder renders
its 23-point template icon, hover state, spacing, label, and four-item `NSMenu`
like a native toolbar control. The extension only captures the selected URL and
agent choice; the short-lived containing app performs terminal launching.

## Build and verify

Requirements:

- macOS 13 or newer
- Xcode with Swift 6.2 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Ghostty and iTerm
- whichever agent CLIs you want to launch

Run the complete verification:

```sh
cd /Users/joker/Projects/OpenInAgent
./scripts/verify.sh
```

The built containing app, including its embedded Finder extension, is written
to:

```text
.build/app/Open in Agent.app
```

## Install

Install a stable copy in `~/Applications`:

```sh
./scripts/install.sh --no-build
```

`--no-build` trusts the locally staged `.build/app` artifact; use it after
`verify.sh`. Omit the flag when you want the installer to build from source
first.

For this personal local installation, the installer registers and enables the
embedded Finder extension with `pluginkit`. On upgrade it stages and verifies
the complete signed bundle before replacing the canonical install path, cycles
the running extension, and rejects duplicate registrations. Backups live under
`~/Library/Application Support/OpenInAgent/Backups` with a non-app suffix.

Confirm the installed backend can see all four commands and both terminals
without opening an agent:

```sh
"$HOME/Applications/Open in Agent.app/Contents/MacOS/Open in Agent" --diagnose
```

Then configure Finder once:

1. Command-drag the old purple **Open in Agent.app** shortcut out of Finder’s
   toolbar, if it is still present.
2. In Finder, choose **View → Customize Toolbar…**.
3. Drag the native **Open in Agent** item into the toolbar and click **Done**.
4. Select a project folder or a file inside one, click the new toolbar button,
   and choose an agent.

If the native item is missing, open the containing app once and choose
**Open Extension Settings**, then enable its Finder extension. The first iTerm
launch may ask permission to control iTerm under System Settings → Privacy &
Security → Automation. Finder access itself does not require an Automation
prompt because Finder supplies the selection to its extension.

### Signing upgrades

Local builds use matching ad-hoc hardened-runtime signatures for the containing
app and embedded extension. The utility is fully usable on this Mac, but macOS
may ask for iTerm Automation permission again after a rebuild because an ad-hoc
identity is tied to that exact binary.

If this Mac later has a stable code-signing identity, build with it to preserve
the app identity across upgrades:

```sh
OPEN_IN_AGENT_SIGNING=identity \
OPEN_IN_AGENT_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
./scripts/build-app.sh release
```

Public distribution additionally requires Developer ID signing and Apple
notarization. Finder Sync is Apple’s only public API for a native Finder toolbar
menu, although Apple documents it primarily for file-sync products; this
repository targets a personal local installation rather than App Store review.

## Security model

- The Finder extension is sandboxed and never invokes a shell, AppleScript, or
  terminal.
- The extension writes a short-lived, owner-only request into its private
  sandbox container. Its activation URL carries only a random one-time UUID;
  the backend atomically consumes the record and rejects replay, stale data,
  symlinks, loose permissions, malformed records, and nonlocal file URLs.
- Claude is launched in Ghostty with discrete `NSWorkspace` arguments.
- iTerm receives an opaque, defensively quoted argv command through `osascript`
  argv; selected paths never enter AppleScript source.
- Every CLI resolves to a canonical absolute executable regular file in fixed
  configured locations. The parent process’s `PATH` is never searched.
- Tests cover quotes, backslashes, `$()`, backticks, separators, newlines,
  leading dashes, Unicode, opaque-token replay, expiry, record permissions, and
  symlink attacks.

See [SECURITY.md](SECURITY.md) for the detailed boundaries.

## Project layout

```text
Sources/OpenInAgent/                 One-shot host and terminal launchers
Sources/OpenInAgentFinderExtension/  Native Finder toolbar/menu extension
FinderExtension/                     Extension plist and sandbox entitlement
Tests/OpenInAgentTests/              Routing, lifecycle, and adversarial tests
project.yml                          Reproducible XcodeGen project definition
OpenInAgent.xcodeproj/               Generated Xcode project used for builds
OpenInAgent.icon/                    Original containing-app icon definition
scripts/build-app.sh                 App + extension packaging and signing
scripts/install.sh                   Stable install and extension registration
scripts/verify.sh                    Full automated verification
```

OpenInAgent is MIT licensed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
for the exact upstream references used during design.
