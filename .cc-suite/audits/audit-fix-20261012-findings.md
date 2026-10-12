# OpenInAgent audit-fix findings

Date: 2026-10-12

Scope: current `Sources/`, `Tests/`, `scripts/`, and environment compatibility.

Requested workflow: `audit-fix`

## Findings

| ID | Severity | Classification | File / function | Finding and reproduction | Status | Commit |
|---|---|---|---|---|---|---|
| F-01 | High | Auto-fixable | `Sources/OpenInAgent/LoginShell.swift`, `arguments(executing:)` | POSIX interactive shell (`-i`) enables job control (`-m` / `MONITOR`) by default. When invoked from a process not in the foreground process group (e.g. background runners, test runners, non-controlling terminals), `zsh` attempts terminal control (`tcsetpgrp`) and is suspended by `SIGTTOU` (state `T`), timing out after 10s (exit 15). Adding `+m` disables job control while preserving the interactive login environment (`-l -i` sourcing `.zprofile`/`.zshrc`), preventing background suspension. | Fixed; all 73 tests pass in 0.04s (down from 20s+ timeout) | `463961e` |

Result: 1 of 1 auto-fixable findings fixed, 0 failed fixes.

## Scope decisions

- `TerminalLauncher.swift` executes the constant program `exec "$@"` inside Ghostty or iTerm. The shell is used exclusively to evaluate `.zprofile` / `.zshrc` and immediately `exec` into `open-in-agent`, so interactive job control is never needed by the wrapper shell.
- Both `testInteractiveLoginShellExecutesArgvLiterally` and `testInteractiveLoginShellChangesDirectory` in `LoginShellTests.swift` reproduce the timeout reliably in non-controlling terminal or background subshell environments prior to the fix.
- Existing untracked historical audit records were preserved.

## Verification

- **Isolated reproduction**: Confirmed that running `zsh -l -i -c 'exec "$@"'` in a detached process group without `+m` triggers `SIGTTOU` and enters stopped state `T`, timing out. Running with `+m` returns immediately with exit status 0 and correct stdout.
- **Unit test suite**: All 73 XCTest cases passed in parallel with `-Xswiftc -warnings-as-errors`. `LoginShellTests` executed in 0.040s (down from 20.134s with 4 timeout failures).
- **Full verification pipeline (`./scripts/verify.sh`)**: Passed completely:
  - `bash -n` linting on all scripts.
  - Strict recursive `swift-format` formatting check.
  - Strict warnings-as-errors parallel test suite.
  - Xcode project generation and `xcodebuild` scheme listing.
  - Release build packaging of the host app and both extensions.
  - Bundle metadata and plist validation.
  - Hardened runtime code signatures and sandbox/Apple Events entitlement verification.
  - Shell evaluation prohibition check (ensuring only sanitized constant `-c` in `LoginShell.swift`).
