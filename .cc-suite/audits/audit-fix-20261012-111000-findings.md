# OpenInAgent audit-fix findings

Date: 2026-10-12

Scope: `Sources/OpenInAgent/OpenInAgentConfig.swift`, `Sources/OpenInAgent/FinderToolbarRequest.swift`, `Sources/OpenInAgent/AgentHandoffStore.swift`, `Sources/OpenInAgentFinderExtension/FinderSync.swift`, `Sources/OpenInAgent/Application.swift`, `scripts/install.sh`, and test suites.

Requested workflow: `audit fix`

## Findings

| ID | Severity | Classification | File / function | Finding and reproduction | Status | Commit |
|---|---|---|---|---|---|---|
| F-01 | High | Auto-fixable | `Sources/OpenInAgent/OpenInAgentConfig.swift`, `FinderToolbarRequest.swift`, `AgentHandoffStore.swift`, `FinderSync.swift` | **Sandbox container path resolution, symlink preservation, and config handoff**: <br>1. `Data.write(to: options: .atomic)` uses `rename(2)` which destroys symbolic links, replacing `~/.config/openinagent/config.json` with an unlinked regular file upon save and breaking synchronization with the extension container.<br>2. In the sandboxed extension, `FileManager.default.homeDirectoryForCurrentUser` evaluates to the container `Data/` directory. Appending `Library/Containers/...` caused a double-nested nonexistent path, making `ConfigStorage.load()` inside the extension fail to read user settings.<br>3. `FinderSync` attempted `NSWorkspace.shared.open` directly from within the sandbox, which violates sandbox isolation and failed to open the user-facing path.<br>4. Broken symlinks were not safely recreated. | Fixed; all 83 tests pass; release app verified | `6764f24` |

Result: 1 of 1 auto-fixable findings fixed, 0 failed fixes.

## Scope decisions

- In `OpenInAgentConfig.swift`, `ConfigStorage.save` writes to `resolvedUserConfig` (`resolvingSymlinksInPath()`), ensuring the symlink is never replaced by `rename(2)` when pointing to the container.
- `ConfigStorage.containerConfigFile` checks `applicationSupportDirectory` to handle sandboxed extension vs unsandboxed host contexts transparently.
- When `userConfigFile` is a regular file (e.g. created by an external editor), `ConfigStorage.load` syncs its contents into `containerConfigFile` so the sandboxed extension immediately sees the update.
- Broken symlinks are detected and repaired in `ensureConfigFileExists` and `scripts/install.sh`.
- `FinderToolbarRequest` now includes `.openConfigFile`, allowing the sandboxed extension to delegate opening the config file to the unsandboxed host via the hardened `ToolbarHandoff` / `AgentHandoffStore` single-use token pipeline.
- 5 new test cases added in `OpenInAgentConfigTests` and `AgentHandoffStoreTests`.

## Verification

- **Unit test suite**: All 83 XCTest cases passed with `-Xswiftc -warnings-as-errors`.
- **Full verification pipeline (`./scripts/verify.sh`)**:
  - `bash -n` on all shell scripts.
  - Strict recursive `swift-format` check passed.
  - Strict compiler warnings-as-errors test suite passed (83/83 tests).
  - Xcode project generation and release build packaging passed.
  - Info.plist and bundle signature checks passed with hardened runtime.
  - Sandbox entitlements and Apple Events automation entitlements verified.
  - Prohibited shell evaluation patterns check passed.
- **Runtime validation**:
  - `./scripts/install.sh --no-build` cleanly replaced and registered the application and both Finder Sync extensions.
  - `Open in Agent --diagnose` verified all four agent CLI and terminal bindings are ready.
