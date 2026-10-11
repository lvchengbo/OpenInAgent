# OpenInAgent

OpenInAgent is a small macOS utility that adds two native controls to Finder’s
toolbar: an AI-agent menu and a separate Copy Path button. Select a file or
folder to launch the matching CLI or copy its full POSIX path.

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

OpenInAgent instead embeds two sandboxed Finder Sync extensions. Finder renders
their 23-point template icons, hover states, spacing, labels, and native menus.
The extensions hand off the chosen action to the short-lived containing app.
The host reads the selected item—or current Finder directory when nothing is
selected—and either launches the chosen agent or copies its POSIX path.

Neither extension monitors directories. Registering every mounted volume as a
Finder Sync root lets Finder replace each volume's native sidebar icon with the
containing app's icon. Monitoring only `/` does not provide selection context
on external volumes. The toolbar is globally available without monitoring;
reading the location through Finder Automation preserves native sidebar icons
and supports external volume roots, mounted disk images, and their contents.
See [Apple's Finder Sync documentation](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html).

## Build and verify

Requirements:

- macOS 13 or newer
- Xcode with Swift 6.2 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Ghostty 1.3 or newer (its AppleScript support arrived in 1.3.0) and iTerm
- whichever agent CLIs you want to launch

Run the complete verification:

```sh
cd /Users/joker/Projects/OpenInAgent
./scripts/verify.sh
```

The built containing app, including both embedded Finder extensions, is written
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

For this personal local installation, the installer registers and enables both
embedded Finder extensions with `pluginkit`. On upgrade it stages and verifies
the complete signed bundle before replacing the canonical install path, cycles
the running extensions, and rejects duplicate registrations. Backups live
under `~/Library/Application Support/OpenInAgent/Backups` with a non-app suffix.

Confirm the installed backend can see all four commands and both terminals
without opening an agent:

```sh
"$HOME/Applications/Open in Agent.app/Contents/MacOS/Open in Agent" --diagnose
```

Then configure Finder once:

1. Command-drag the old purple **Open in Agent.app** shortcut out of Finder’s
   toolbar, if it is still present.
2. In Finder, choose **View → Customize Toolbar…**.
3. Drag the native **Open in Agent** and **Copy Path** items into the toolbar,
   then click **Done**.
4. Select a project folder or a file inside one. Use **Open in Agent** to choose
   an agent, or **Copy Path** to copy the selected path.

If either native item is missing, open the containing app once and choose
**Open Extension Settings**, then enable both Finder extensions. The first
use of either button asks permission to read Finder under System Settings →
Privacy & Security → Automation. Allow Finder so the host can read the selected
item or current folder. Launching an agent may also ask permission for Ghostty
or iTerm. If Finder access is denied or its location is unavailable, the host
reports the problem and performs no clipboard or terminal action.

### Signing upgrades

Local builds use matching ad-hoc hardened-runtime signatures for the containing
app and embedded extensions. The utility is fully usable on this Mac, but macOS
may ask for Finder, Ghostty, or iTerm Automation permission again after a rebuild because
an ad-hoc identity is tied to that exact binary.

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

- Both Finder extensions are sandboxed and never invoke a shell, AppleScript,
  or terminal.
- Each extension writes a short-lived, owner-only request into its private
  sandbox container. Its activation URL carries only a random one-time UUID;
  the backend atomically consumes the record and rejects replay, stale data,
  symlinks, loose permissions, malformed records, and nonlocal file URLs.
- The host uses constant AppleScript to read Finder; filenames are returned as
  data and never inserted into script source. Copy Path copies the selected
  item's path without converting files or packages to their parent directory.
- Each agent is wrapped in the user's interactive login shell with a constant
  `-c` program, so it inherits the same `PATH` it would when typed into a
  terminal while the selected path travels only as argv.
- Ghostty and iTerm are both driven through a constant AppleScript over
  `osascript` argv; selected paths never enter AppleScript source. Ghostty's
  `command` property is single-quoted for the bash that evaluates it, and
  iTerm's command is double-quoted for its own parser.
- Every CLI resolves to a canonical absolute executable regular file in fixed
  configured locations. The parent process’s inherited `PATH` is never searched
  to locate the executable.
- Tests cover quotes, backslashes, `$()`, backticks, separators, newlines,
  leading dashes, Unicode, opaque-token replay, expiry, record permissions, and
  symlink attacks.

See [SECURITY.md](SECURITY.md) for the detailed boundaries.

## Project layout

```text
Sources/OpenInAgent/                 One-shot host and terminal launchers
Sources/OpenInAgentFinderExtension/  Native Finder toolbar/menu extension
Sources/CopyPathFinderExtension/     Independent Copy Path toolbar extension
Sources/FinderExtensionSupport/     Shared sandbox-to-host toolbar handoff
FinderExtension/                     Extension plist and sandbox entitlement
CopyPathFinderExtension/             Copy Path extension plist
Tests/OpenInAgentTests/              Routing, lifecycle, and adversarial tests
project.yml                          Reproducible XcodeGen project definition
OpenInAgent.xcodeproj/               Generated Xcode project used for builds
OpenInAgent.icon/                    Original containing-app icon definition
scripts/build-app.sh                 App + extensions packaging and signing
scripts/install.sh                   Stable install and extension registrations
scripts/verify.sh                    Full automated verification
```

OpenInAgent is MIT licensed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
for the exact upstream references used during design.
