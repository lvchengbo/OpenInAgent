# Security

## Trust boundaries

The selected Finder URL and the extension-to-host activation URL are untrusted
input. Legal macOS filenames can contain spaces, quotes, backticks, shell
metacharacters, and newlines, so no selected path may become executable source
text.

Both Finder Sync extensions are App-Sandboxed. They read the current Finder
selection only while Finder is constructing a menu or invoking a menu action.
The Agent extension sends a strictly structured request to the containing app;
the Copy Path extension writes only the selected local POSIX path to the system
clipboard. Neither extension resolves commands, runs processes, uses Apple
Events, or launches a terminal.

The short-lived containing app is intentionally not App-Sandboxed because it
launches locally installed command-line tools. It requests Apple Events access
only for iTerm. It does not request Full Disk Access, Accessibility,
administrator privileges, or Finder Automation.

## Finder handoff

The extension stores a small versioned request inside its private App Sandbox
container. The directory is mode `0700`, each request is created exclusively at
mode `0600`, and—besides its version, token, and timestamp—the record contains
exactly two command inputs:

- one `AgentID` from the fixed Claude/Codex/Grok/AGY enum;
- one percent-encoded local file URL supplied by Finder.

The extension then asks LaunchServices to open its containing app with an
`openinagent://launch/<UUID>` URL. This public activation URL contains only an
unguessable one-time token—never the agent or selected path.

The host reconstructs the record name only from a canonical UUID, atomically
claims it with a same-directory hard link, removes the original name, and
deletes the claim after reading. It rejects replay, records older than 60
seconds or more than 5 seconds in the future, records over 16 KiB, symlinks,
nonregular or non-user-owned files, loose permissions, unknown agents, relative
or remote file URLs, and nested user information, ports, queries, or fragments.
Invalid tokens exit silently so arbitrary callers cannot create alert spam.

macOS gives other sandboxed apps no access to this extension’s container, so
they cannot manufacture a valid record even though they can invoke the public
URL scheme. An unsandboxed process running as the same user can inspect the
container, but already has equivalent process-launch authority.

After consuming the record, the host independently checks that the selected
item still exists. No executable path, terminal argument, or free-form command
crosses the extension boundary.

Finder aliases are resolved without UI and without mounting unavailable
volumes. Selecting a file or package resolves only to its parent; selecting a
directory keeps that directory.

## Terminal launch boundaries

### Ghostty

`NSWorkspace.OpenConfiguration.arguments` sends these discrete arguments from
the unsandboxed host:

```text
--working-directory=<selected directory>
-e
/usr/bin/env -C <selected directory> -- PWD=<selected directory> <absolute claude executable>
```

Ghostty documents `-e` as an argv command with shell expansion disabled. The
direct `env -C` invocation also pins both the process directory and `PWD`, even
if Ghostty's own working-directory preference is overridden.

### iTerm

OpenInAgent asks iTerm to create a window with an encoded argv command:

```text
/usr/bin/env -C <selected directory> -- PWD=<selected directory> <absolute executable>
```

The value is passed to a constant AppleScript through `osascript` argv, not
inserted into AppleScript source. Each element is double-quoted for iTerm’s
`componentsInShellCommand` parser. iTerm launches the resulting path and
arguments directly rather than invoking a shell. As defense in depth, the
encoding also preserves every argument literally if a future iTerm version
routes the command through a POSIX shell.

## Explicitly prohibited patterns

- `sh -c`, `zsh -c`, or equivalent shell evaluation
- terminal `write text` or synthetic keystrokes
- editable free-form command templates
- automatic permission-bypass flags
- Finder preference mutation
- force-restarting Finder
- process, shell, or AppleScript execution inside either Finder extension

`scripts/verify.sh` rejects these patterns in production Swift sources. Unit
tests round-trip adversarial values through the private handoff record, iTerm
encoder, and `osascript` argv transport, while separately enforcing that the
public activation URL contains only a canonical UUID token.

## Remaining platform trust

OpenInAgent trusts the user-managed Ghostty, iTerm, and agent CLI installations;
it does not install or update them. Agent discovery checks only fixed per-user,
system, and Homebrew locations, resolves each symlink once to a canonical path,
and requires an executable regular file. The launching process’s inherited
`PATH` is not searched. This local build does not pin terminal Team IDs or CLI
code-signing requirements, so software substitution within those configured
locations remains a user-installation risk.

The containing app and both embedded extensions are signed inside-out with the
same identity. Local builds use ad-hoc signing, so iTerm Automation consent may
need to be granted again after rebuilding. `scripts/build-app.sh` supports a
stable identity through `OPEN_IN_AGENT_SIGNING=identity`; public distribution
still requires Developer ID signing and notarization.
