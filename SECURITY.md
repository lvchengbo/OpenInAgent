# Security

## Trust boundary

The selected Finder URL is untrusted input. Legal macOS filenames can contain
spaces, quotes, backticks, shell metacharacters, and newlines, so no selected
path may become executable source text.

OpenInAgent is intentionally not App-Sandboxed because it launches locally
installed command-line tools. It requests only Apple Events automation access
for Finder and iTerm. It does not request Full Disk Access, Accessibility, or
administrator privileges.

## Launch boundaries

### Finder

`FinderSelection.locationScript` is a constant, selection-first AppleScript.
It returns Finder’s file URL. No path is interpolated into the script.
Finder aliases are resolved without UI and without mounting unavailable volumes.

### Ghostty

`NSWorkspace.OpenConfiguration.arguments` sends these discrete arguments:

```text
--working-directory=<selected directory>
-e
<absolute claude executable>
```

Ghostty documents `-e` as an argv command with shell expansion disabled.

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
- Terminal/iTerm `write text` or synthetic keystrokes
- editable free-form command templates
- automatic permission bypass flags
- undocumented Finder preference mutation
- force-restarting Finder

`scripts/verify.sh` rejects several of these patterns in production Swift
sources, and unit tests round-trip adversarial values through the iTerm
argument encoder and `osascript` argument transport.

## Remaining platform trust

OpenInAgent trusts the installed, code-signed Ghostty, iTerm, and agent CLI
binaries. It does not install or update them. Replacing one of those binaries
changes the behavior outside this app’s boundary.
Agent discovery checks only configured per-user paths and fixed system or
Homebrew directories, resolves symlinks, and requires an executable regular
file. The launching process’s inherited `PATH` is not searched.

The default local build is ad-hoc signed, so Automation consent may need to be
granted again after rebuilding. `scripts/build-app.sh` also supports a stable
identity through `OPEN_IN_AGENT_SIGNING=identity`; public distribution would
still require Developer ID signing and notarization.
