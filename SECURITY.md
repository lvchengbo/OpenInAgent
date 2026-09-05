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
because it drives both Ghostty and iTerm through AppleScript. It does not
request Full Disk Access, Accessibility, administrator privileges, or Finder
Automation.

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

Both terminals run the same login-shell-wrapped argv. The wrapping login shell
restores the interactive `PATH` the agent needs (Homebrew, nvm, `~/.local/bin`),
its `-c` program is the constant `exec "$@"` (or `exec $argv` for fish), and the
selected directory and executable travel only as later argv elements, never as
shell source:

```text
<login shell> -l -i -c 'exec "$@"' open-in-agent /usr/bin/env -C <dir> -- PWD=<dir> <absolute executable>
```

The `env -C` invocation pins both the process directory and `PWD`. Data reaches
each terminal only through `osascript` argv; it is never interpolated into the
constant AppleScript source.

### Ghostty

The unsandboxed host runs a constant AppleScript through `osascript` argv that
creates a window from Ghostty's scripting dictionary:

```text
new window with configuration {initial working directory:<dir>, command:<launch command>}
```

`<launch command>` is the wrapped argv above, single-quoted element by element.
Ghostty evaluates its `command` surface property through a non-interactive
`bash --noprofile --norc -c "exec -l …"`, so every element is single-quoted
(`'…'`, an embedded quote becoming `'\''`); bash performs no expansion inside
single quotes.

### iTerm

The host asks iTerm to create a window with the wrapped argv as its command:

```text
create window with default profile command <launch command>
```

Here `<launch command>` double-quotes each element for iTerm’s
`componentsInShellCommand` tokenizer, escaping only the two characters that
tokenizer treats as special inside double quotes — `"` and `\`. iTerm does not
expand the command, so `$`, backticks, and other metacharacters are ordinary
literals and must not be backslash-escaped; escaping them would leave a stray
backslash in the delivered argument (which previously corrupted the login
shell's constant `exec "$@"` program and made every iTerm session exit at once).
The value is passed to a constant AppleScript through `osascript` argv, not
inserted into AppleScript source. iTerm tokenizes the string and launches the
resulting path and arguments directly, without a shell, so no element is ever
evaluated; the login shell it launches is what restores the interactive `PATH`.

## Explicitly prohibited patterns

- shell evaluation of a command string built from the selection; the login-shell
  wrapper is the one sanctioned `-c` site, and its program is the bare constant
  `exec "$@"` (or `exec $argv`) with every path carried only as argv
- terminal `write text` or synthetic keystrokes
- editable free-form command templates
- automatic permission-bypass flags
- Finder preference mutation
- force-restarting Finder
- process, shell, or AppleScript execution inside either Finder extension

`scripts/verify.sh` enforces this in production Swift sources: it bans
data-bearing shell evaluation everywhere and separately pins `LoginShell`'s `-c`
program to its bare constant. Unit tests round-trip adversarial values through
the private handoff record, both terminal encoders, the login-shell wrapper, and
`osascript` argv transport, while separately enforcing that the public
activation URL contains only a canonical UUID token.

## Remaining platform trust

OpenInAgent trusts the user-managed Ghostty, iTerm, and agent CLI installations;
it does not install or update them. Agent discovery checks only fixed per-user,
system, and Homebrew locations, resolves each symlink once to a canonical path,
and requires an executable regular file. The launching process’s inherited
`PATH` is not searched. This local build does not pin terminal Team IDs or CLI
code-signing requirements, so software substitution within those configured
locations remains a user-installation risk.

The containing app and both embedded extensions are signed inside-out with the
same identity. Local builds use ad-hoc signing, so Ghostty or iTerm Automation
consent may need to be granted again after rebuilding. `scripts/build-app.sh` supports a
stable identity through `OPEN_IN_AGENT_SIGNING=identity`; public distribution
still requires Developer ID signing and notarization.
