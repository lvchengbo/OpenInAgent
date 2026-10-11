# OpenInAgent audit-fix findings

Date: 2026-10-11

Scope: current `Sources/`, `Tests/`, `scripts/`, and security/installation documentation, including the native Finder sidebar repair.

Requested workflow: `gsd-audit-fix` with defaults (up to 5 fixes, medium or higher).
`gsd-sdk query audit-uat` reported `No phases directory found in planning directory`; this repository has debug notes but no phase UAT/verification files. This run therefore reviews the live code and historical audit records directly, retaining classification, sequential fixes, regression verification, and atomic commits.

The pre-existing sidebar repair was verified with all 69 tests and saved separately as `74e9d67` (`fix(finder): preserve native volume icons with global toolbar actions`). Existing unrelated untracked audit records were preserved.

## Findings

| ID | Severity | Classification | File / function | Finding and reproduction | Status | Commit |
|---|---|---|---|---|---|---|
| F-01 | Medium | Auto-fixable | `Sources/OpenInAgent/AgentHandoffStore.swift`, `readValidatedRecord(at:)` | Replacing a valid owner-only request with a FIFO causes blocking `open(O_RDONLY)` before the `fstat` regular-file check. A subprocess using the real store remained blocked beyond two seconds. Added `O_NONBLOCK` while retaining owner, type, permission, size, and replay validation. | Fixed; 71 tests passed after this fix | `e315e88` |
| F-02 | Medium | Auto-fixable | `Sources/OpenInAgent/AgentHandoffStore.swift`, `prepareDirectoryForWriting()` | With `Handoffs` symlinked to an unrelated directory, `create` rejects the directory only after path-based `chmod` changes the target's permissions from 0755 to 0700. Added owner/type validation via `lstat` before `fchmodat(..., AT_SYMLINK_NOFOLLOW)` and retained final validation. Owned mode-000 directories can still be restored to 0700. | Fixed; 73 tests and full verification passed | `7c48cd0` |
| F-03 | Medium | Manual-only investigation | `scripts/install.sh`, post-install extension registration | The first installation reported success, but a later PlugInKit query found neither extension and Finder showed unlabeled toolbar buttons. Re-registering the installed extensions restored both. Three subsequent installs, including explicit registration of the source build with PlugInKit and LaunchServices before installation, did not reproduce withdrawal. Delayed daemon cleanup is a hypothesis, not a confirmed cause. | Runtime state restored; root cause unconfirmed; no speculative code change | — |

Result: 2 of 2 auto-fixable findings fixed, 0 failed fixes, 1 manual-only observation retained for investigation. The existing sidebar repair was saved in its own commit before these fixes.

## Scope decisions

- Historical lifecycle, shell, terminal-version, signing, installer, and URL-entry-point fixes were checked against current source. No additional reproducible code defect was established in those paths; the installation observation is recorded as F-03.
- The previously deferred `ProcessRunner` pipe-descendant issue remains a generic-helper limitation: the production constant `osascript` programs do not start descendants inheriting the helper's output pipes. This run found no new production trigger, so it does not rewrite that concurrency code.
- The BetterTouchTool Finder extension is outside this repository and remains disabled. OpenInAgent's two repaired extensions remain enabled.

## Verification

- Baseline: 69 XCTest cases passed with warnings treated as errors.
- The isolated pre-fix reproduction confirmed both new findings without modifying installed application containers or live disk data.
- F-01: both agent and Copy Path FIFO regressions failed against the old implementation, then passed after the fix. The full suite passed with 71 XCTest cases.
- F-02: symlink-target permission regressions failed against the old implementation for both endpoints. The fix passed those cases and preserved round trips through owned unreadable directories. The full suite passed with 73 XCTest cases.
- `./scripts/verify.sh` passed: strict formatting, warnings-as-errors tests, generated Xcode project, release app and both extensions, bundle metadata/resources, signature validation, sandbox entitlements, and launch-pattern checks.
- Installed the verified app at `/Users/joker/Applications/Open in Agent.app` using `./scripts/install.sh --no-build`. Earlier app versions were retained by the installer in its backup directory.
- Finder runtime check: Samsung retains its native Time Machine disk glyph, DeepL its native disk glyph, and both toolbar controls have labels. Clicking Copy Path at the DeepL volume root and pasting into Finder's Go to Folder field produced exactly `/Volumes/DeepL`, validating the sandboxed extension-to-host handoff with the new permission syscall. The temporary test tab was closed and the original three tabs restored.
- After the final repeat installation, the Open in Agent menu exposed all four enabled agent actions. The installed host and both extension executables matched the verified build byte for byte; final PlugInKit output showed both canonical extensions enabled and BetterTouchTool disabled (`final-registration.log`).
- F-03 evidence: first install log and later empty PlugInKit queries; manual re-registration restored both. Each of the three repeat installations was sampled 30 times at 0.5-second intervals after script exit and retained both canonical enabled registrations. Final registration and toolbar checks were also performed. These checks establish the current working state, not the cause or permanent resolution of the initial withdrawal.
- Local verification logs: `/private/tmp/openinagent-audit-20261011/` (`fifo-red.log`, `fifo-green.log`, `f01-full-tests.log`, `directory-red.log`, `directory-green.log`, `final-verify.log`, `install.log`, and the three registration reproduction/install monitoring logs).
