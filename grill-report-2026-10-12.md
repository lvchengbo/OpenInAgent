---
plugin: grill
version: 1.4.0
date: 2026-10-12
target: /Users/joker/Projects/OpenInAgent
style: correctness and failure-path audit
addons: [edge cases, assumptions audit]
skills: [grill-recon, grill-architecture, grill-error-handling, grill-security, grill-testing, grill-edge-cases]
---

## [Skill: grill-recon] Findings

Swift 6.2+ macOS application with two Finder Sync extensions, Foundation/AppKit/
SwiftUI, Swift Package Manager XCTest tests, XcodeGen, and Bash packaging scripts.
No external runtime packages, database, or CI configuration. Reviewed all 18
Swift source files, all 13 existing test files, the three build/install/verify
scripts, project metadata/entitlements, and earlier audit records. The existing
AGY repair and unrelated untracked audit records are retained.

## [Skill: grill-architecture] Findings

### F01 — Configured iTerm overrides are ignored [HIGH] [< 1 day]

- **File:** `Sources/OpenInAgent/Agent.swift:12`, `TerminalLauncher.swift:232`.
- **Observation/evidence:** The enum raw value is `iTerm`, while generated config
  uses `iterm`. `TerminalKind(rawValue: terminalString)` therefore fails for a
  valid documented setting. Switching Claude to iTerm still launches Ghostty.
- **Change:** Normalize configuration names and use one terminal resolver.
- **Tradeoff:** Both existing spellings remain accepted; unknown values retain
  the established fallback behavior.
- **Verification/status:** Fixed. The configured-route regression failed for
  `iterm` and `ITERM` before normalization, then passed for both and legacy
  `iTerm`. Logs: `/private/tmp/openinagent-f01-{red,green}.log`.

### F02 — Chooser and diagnostics report a different route [MEDIUM] [< 1 day]

- **File:** `AgentMenuController.swift:43`, `Diagnostics.swift:39`.
- **Observation/evidence:** Both use `agent.specification.terminal` without
  consulting config, while the launcher consults it. A configured installed
  terminal can be disabled in the chooser because the default is absent;
  diagnostics can report ready when the configured terminal is absent.
- **Change:** Resolve configured routes before availability and version checks.
- **Tradeoff:** Display and diagnostic readiness follow the same config as launch.
- **Verification/status:** Fixed. Diagnostics regressions failed for both a
  missing default and missing override before the change; all eight diagnostics
  and chooser tests passed afterward. Logs: `/private/tmp/openinagent-f02-{red,green}.log`.

## [Skill: grill-error-handling] Findings

### F07 — Grok YOLO uses another unsupported `-y` flag [HIGH] [< 1 day]

- **File:** `Agent.swift:60`, `OpenInAgentConfig.swift:39`, `scripts/install.sh:236`.
- **Observation/evidence:** The installed Grok CLI returns exit 2 and
  `unexpected argument '-y' found` for `grok -y --help`. Its local help specifies
  `--always-approve`. Codex accepts `--yolo`; Claude accepts its current flag.
- **Change:** Use Grok's supported flag and migrate the exact obsolete saved
  default while preserving custom lists and terminal choices.
- **Tradeoff:** Existing YOLO preference is retained with a working CLI option.
- **Verification/status:** Fixed. Grok's default and fallback now use `--always-approve`;
  saved exact `[-y]` defaults migrate on load and initialization. All 17 config
  tests passed. The supported flag was accepted by the installed CLI's parser.
  Config defaults now come from the agent catalog, and installation uses the
  host initializer, avoiding three independent flag lists.

### F03 — Config initialization loses settings and suppresses errors [HIGH] [< 1 day]

- **File:** `OpenInAgentConfig.swift:193`, `Application.swift:115,282`,
  `scripts/install.sh:213`.
- **Observation/evidence:** If a user config exists but the container file is
  absent, `ensureConfigFileExists` initializes the container to defaults instead
  of copying the user's config. Directory/write/link errors are discarded and
  the nonexistent path is returned as if initialization succeeded. The installer
  separately duplicates initialization/defaults.
- **Change:** Initialize from the existing valid user config, preserve links,
  propagate failures, and have installation call the same initializer.
- **Tradeoff:** Callers must handle configuration errors; failed initialization
  becomes visible rather than silently claiming success.
- **Verification/status:** Fixed. Both setting-preservation regressions failed
  before the fix; all 16 config tests then passed, including write-failure,
  invalid-JSON preservation, and symlink cases. The host reports initialization
  failures and JSON-opening failures. Installer integration is covered in F06.
  Logs: `/private/tmp/openinagent-f03-{red,green}.log`.

## [Skill: grill-edge-cases] Findings

### F04 — Helper deadlines do not bound output collection [MEDIUM] [< 1 day]

- **File:** `ProcessRunner.swift:91-95,126`, `TerminalLauncher.swift:300`.
- **Observation/evidence:** The parent is marked completed immediately after
  exiting, then `readers.wait()` waits indefinitely for EOF. A descendant
  inheriting stdout/stderr keeps those pipes open after the parent exits, so
  the watchdog cannot enforce its deadline. Previously noted but deferred in
  the October 11 audit. The launcher also accepts exit status zero before
  checking whether the run timed out.
- **Change:** Bound pipe collection as well as process lifetime and prioritize
  timeout classification.
- **Tradeoff:** Output held by descendants beyond the deadline is intentionally
  incomplete and the run is reported as timed out.
- **Verification/status:** Fixed. A 0.1-second deadline previously took 2.01
  seconds and was reported as successful; the regression now takes about 0.13
  seconds and reports timeout while preserving the parent's output. All 16
  helper/shell/hardening tests passed. Timeout classification precedes exit-zero
  success. Logs: `/private/tmp/openinagent-f04-{red,green}.log`.

### F06 — Installer rollback misses first-install and pre-swap failures [HIGH] [< 1 day]

- **File:** `scripts/install.sh:114-134,139-151,205-217`.
- **Observation/evidence:** Cleanup only restores when a backup already exists.
  Failure after stopping/unregistering the old install but before moving it to
  backup leaves its extensions unregistered. A failed first install leaves the
  failed destination installed because no backup exists. Config initialization
  runs after `commit_done=1`, so its failure cannot roll back the upgrade.
- **Change:** Track stopped/replaced state, restore registrations on pre-swap
  failures, remove failed first installs, and commit after config succeeds.
- **Tradeoff:** Additional transaction-state bookkeeping; previous app remains
  recoverable on every covered failure path.
- **Verification/status:** Fixed. Pre-swap, first-install, and failed-move
  rollback assertions failed against the original cleanup. All six temporary
  installation scenarios now pass. Initialization precedes commit, and handled
  INT/TERM signals enter the same EXIT cleanup. Logs:
  `/private/tmp/openinagent-f06-{red,green}.log`.

### Edge Case Risk Matrix

| Scenario | Likelihood | Impact | Risk | Component | Finding |
|---|---|---|---|---|---|
| Failed upgrade leaves extensions unregistered | Medium | High | HIGH | Installer | F06 |
| Existing user config initializes Finder with defaults | Medium | High | HIGH | Config | F03 |
| Parent exits while descendant retains pipes | Low in current constant scripts | Medium | MEDIUM | Helper | F04 |

The greatest recovery risk is an interrupted install leaving the canonical app
or Finder registrations in a partial state. Tests will inject failures in a
temporary installation, never the live app.

## [Skill: grill-security] Findings

### F05 — Target URL validation accepts embedded NUL [MEDIUM] [< 1 day]

- **File:** `AgentLaunchRequest.swift:15-30`.
- **Observation/evidence:** The common validator accepted percent-encoded NUL.
  On this Foundation build, standardization changed `%00` into `%2500` instead
  of rejecting the invalid URL. The request initializer also standardized before
  validation, losing the original encoding. Only the Finder-string adapter
  explicitly rejected a literal NUL.
- **Exploit scenario:** A malformed owner-accessible handoff can resolve to
  a different literal-percent filename in later filesystem/argv operations.
  This does not establish
  a privilege boundary bypass; same-user unsandboxed code already has launch
  authority.
- **Change:** Reject NUL at the common URL boundary and test create/consume.
- **Tradeoff:** Rejects only paths macOS cannot represent as a single filename.
- **Verification/status:** Fixed. Validator and handoff create/consume
  regressions failed before the fix; all 32 handoff/path tests now pass. Checks
  run before normalization, reject both literal and encoded NUL, and preserve
  legal filenames containing the literal text `%00`.
  Logs: `/private/tmp/openinagent-f05-{red,green}.log`.

### Existing boundaries [GOOD]

Opaque single-use handoff tokens, owner/mode/type/age/size checks, FIFO rejection,
endpoint allowlists, constant AppleScript/shell programs, literal argv encoders,
canonical executable discovery, and inside-out hardened signatures are present.
No additional injection or credential exposure was established by this review.

## [Skill: grill-testing] Findings

The existing 87-case suite covers normal launch, hostile filenames, record
replay/tampering, shell dialects, and several previous failure fixes. Its gaps
correspond to F01–F06; add behavioral regressions for those specific defects.
No coverage percentage is inferred from test-file counts. Native UI and Apple
Events permissions still need a local smoke check after the signed install.

## Fixing Plan

1. F01: accept configured iTerm names; verify route resolution.
2. F02 (depends on F01): use configured routes in chooser and diagnostics.
3. F03: unify initializer, preserve existing settings, surface failures.
4. F04: bound output collection and classify timeout before success.
5. F05: reject NUL URLs at create and consume boundaries.
6. F06 (depends on F03): repair installer transaction rollback; inject failures.
7. F07: repair Grok YOLO and migrate the old saved default.
8. Run full formatting/tests/build/signature verification, install, and check
   Finder handoff, configured routes, and canonical extension registrations.

Each fix is applied and verified sequentially. Total estimate: under one week;
all changes are local to the existing modules. This report records confirmed
code paths, their isolated reproductions, and the completed outcomes above.

## Verdict and Limits

The main launch and handoff boundaries are well isolated. Configuration routing
and partial-failure recovery are the remaining correctness risks found in this
review. Priority: F01/F02 routing, F03 config preservation, F06 rollback. Confidence
is high in the cited code-path defects; actual CLI/terminal compatibility must
be checked against this Mac's installed versions. Exhaustive OS event-ordering,
every supported login-shell installation, and permissions on other Macs are
outside what local verification can establish.

## Final Verification

All seven additional findings are fixed. The earlier AGY repair is retained.

- `./scripts/verify.sh` passed: 96 Swift XCTest cases with compiler warnings
  treated as errors, six installer rollback scenarios, strict formatting,
  shell syntax, XcodeGen/release packaging, resources/plists, hardened signatures,
  extension sandbox and host Apple Events entitlements, and launch-boundary checks.
- `./scripts/install.sh --no-build` passed, including the shared configuration
  initializer before commit. The installed host and both extension executables
  match the verified build byte for byte.
- Installed `--diagnose` reports all four CLI/terminal routes ready. Local CLI
  parsers accepted Codex's `--yolo`, Claude's permission flag, and Grok's
  `--always-approve`. AGY's permission flag was verified in a live launch.
- Clicking Finder's Grok and AGY YOLO items created live iTerm processes with
  `--always-approve` and `--dangerously-skip-permissions`, respectively. Both
  processes have `/Users/joker/Projects/voca` as their working directory,
  matching Finder's selected folder at the time. Existing sessions were retained.
- The user's config remains linked to the extension container, retains YOLO
  mode and terminal choices, and now contains the corrected Grok flag.
- Later PlugInKit queries show exactly one enabled canonical registration for
  each extension. The earlier audit's intermittent registration withdrawal did
  not recur in this check; no speculative daemon-related change was made.
- `git diff --check` passed. Earlier unrelated untracked audit files are preserved.

Final logs: `/private/tmp/openinagent-thorough-verify.log` and
`/private/tmp/openinagent-thorough-install.log`. Terminal console UI inspection
was unavailable through the computer tool; live launch verification used process
identity, arguments, working directory, and ongoing process state.

## Second-Pass Recheck

The requested recheck found four further configuration defects. The new
behavioral regressions reproduced each old failure before its fix. The review
also revisited process deadlines, launch argument handling, endpoint isolation,
installer failure recovery, and the two extension build targets.

### F08 — Malformed configuration could not be opened for repair — Medium

- **Evidence:** `ApplicationCoordinator.openConfiguration()` called the strict
  initializer, which rejected malformed JSON before invoking the editor.
  Both malformed-user and malformed-container editing tests threw before the fix.
- **Failure scenario:** An incomplete edit prevents the Finder menu's Open Config
  File action from opening the very file the user needs to repair.
- **Change:** `ConfigStorage.fileForEditing()` returns the original malformed
  file while keeping initialization strict and retaining other IO errors.
- **Tradeoff:** Editing does not validate the JSON; initialization and mode saves
  still do. Neither original malformed file is replaced.
- **Status:** Fixed; both editing regressions pass.

### F09 — Invalid user JSON revived cached YOLO settings — High

- **Evidence:** `ConfigStorage.load()` combined reading and decoding in one
  optional check, then used the container copy when decoding failed. A malformed
  user file beside a valid cached YOLO config loaded YOLO in the failing regression.
- **Failure scenario:** An editor replaces the symlink with a regular file and
  leaves its JSON incomplete. Launching unexpectedly reuses the previous cached
  permission-bypass mode.
- **Change:** A readable user file remains authoritative. Invalid JSON returns
  the Safe default; container fallback remains available when the sandbox cannot
  read the user-facing file.
- **Tradeoff:** Invalid edits temporarily use default terminal routes and Safe
  mode until repaired. The malformed user data is preserved.
- **Status:** Fixed; the stale-YOLO regression passes.

### F10 — Partial saves reported success and lost the requested mode — Medium

- **Evidence:** `ConfigStorage.save()` treated either write as success. With an
  independent readable user file in a non-writable directory, it changed the
  container while silently failing to update the authoritative file. The new
  write-failure regression failed both its error and unchanged-container checks.
- **Failure scenario:** A mode save appears successful, then the next host load
  reads the old user file and overwrites the cache with the previous mode.
- **Change:** Save the authoritative user target first, then the container target,
  preserving symlinks and propagating either required write failure.
- **Tradeoff:** Two independent files cannot be committed atomically together.
  A later container failure is reported even if the authoritative write already
  succeeded; an earlier user failure leaves the cached data untouched.
- **Status:** Fixed; authoritative and container failure regressions pass.

### F11 — Finder mode changes were undone after symlink replacement — Medium

- **Evidence:** The sandboxed Finder extension saved only its accessible
  container file. Simulating that write followed by a host load of an independent
  user file reverted the requested YOLO mode to Safe in the failing regression.
- **Failure scenario:** A text editor saves a replacement regular config file;
  selecting either Finder mode no longer persists across the next agent launch.
- **Change:** Finder sends a single-use `setMode` handoff to the host. The host
  validates existing JSON and saves both copies before reporting completion.
  The action accepts only the fixed Safe/YOLO enum, has no agent or target, and
  is unavailable through the Copy Path endpoint.
- **Tradeoff:** A mode change starts the short-lived host instead of writing
  directly from Finder. IO failures now produce a visible host error.
- **Status:** Fixed; independent-file persistence, malformed config preservation,
  replay, enum tampering, endpoint isolation, directory permissions, and FIFO
  rejection are covered.

### Recheck Verification

- `./scripts/verify.sh` passed with 106 Swift XCTest cases, six installer rollback
  scenarios, strict formatting, compiler warnings as errors, release packaging,
  signatures, entitlements, resource/plist checks, and launch-boundary checks.
  The initial release build caught the new mode enum's missing dependency in
  the Copy Path target; moving the enum into the shared request file fixed it.
- `./scripts/install.sh --no-build` passed. The installed host and both extension
  executables match the verified build byte for byte. Installed diagnostics
  reports all four CLI/terminal routes ready.
- A live Finder Safe Mode action with a temporary independent user config file
  updated both user and container configurations and preserved all agent
  preferences. Reopening the Finder menu displayed Safe-mode launch titles.
  The original config bytes, original symlink, and original YOLO setting were
  restored after the check.
- PlugInKit lists exactly one enabled extension at each canonical installed
  path. `git diff --check` passes. No other confirmed defect remains from this
  recheck; this does not establish exhaustive correctness on other Macs or
  for every OS event ordering.

Logs: `/private/tmp/openinagent-recheck-config-red.log`,
`/private/tmp/openinagent-recheck-mode-red.log`,
`/private/tmp/openinagent-recheck-config-green.log`,
`/private/tmp/openinagent-recheck-verify.log`, and
`/private/tmp/openinagent-recheck-install.log`.
