import AppKit
import Foundation

enum TerminalLauncherError: LocalizedError, Sendable {
  case missingTerminal(String)
  case missingExecutable(String)
  case invalidWorkingDirectory
  case automationDenied(String)
  case timedOut(String)
  case launchFailed(String)
  case unsupportedLoginShell(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedLoginShell(let name):
      "Your login shell (\(name)) isn’t supported. Open in Agent can wrap zsh, bash, sh, ksh, dash, ash, mksh, or fish; change your account shell or set SHELL to one of those."
    case .missingTerminal(let name):
      "\(name) is not installed."
    case .missingExecutable(let name):
      "The \(name) command-line tool could not be found."
    case .invalidWorkingDirectory:
      "The selected working directory is no longer available."
    case .automationDenied(let name):
      "Open in Agent is not allowed to control \(name). Enable \(name) under System Settings → Privacy & Security → Automation, then try again."
    case .timedOut(let name):
      "\(name) did not respond in time."
    case .launchFailed(let detail):
      "The agent could not be launched. \(detail)"
    }
  }
}

/// Builds the argv that every terminal ultimately executes.
enum AgentCommand {
  /// `env -C <dir> -- PWD=<dir> <executable>` pins the process directory and
  /// `PWD` even if the terminal's own working-directory setting is overridden.
  static func environmentArguments(
    executableURL: URL,
    workingDirectory: URL
  ) -> [String] {
    let directoryPath = workingDirectory.path
    return [
      "/usr/bin/env",
      "-C",
      directoryPath,
      "--",
      "PWD=\(directoryPath)",
      executableURL.path,
    ]
  }

  /// The complete argv: the user's interactive login shell wrapping the
  /// `env` invocation above, so the agent inherits the same `PATH` and
  /// environment it would get when typed into a terminal.
  static func arguments(
    executableURL: URL,
    workingDirectory: URL,
    loginShell: LoginShell
  ) -> [String] {
    loginShell.arguments(
      executing: environmentArguments(
        executableURL: executableURL,
        workingDirectory: workingDirectory
      )
    )
  }
}

/// Encodes argv for Ghostty's `command` surface property. Ghostty evaluates
/// that string through a non-interactive bash launched with no profile or rc
/// files, which then `exec -l`s the command. Every element is therefore
/// single-quoted: bash performs no expansion inside single quotes, and an
/// embedded quote becomes the `'\''` sequence.
enum BashCommandEncoder {
  static func quote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func command(arguments: [String]) -> String {
    arguments.map(quote).joined(separator: " ")
  }
}

/// Encodes argv for iTerm's `command` parameter. iTerm tokenizes that string
/// with its own `componentsInShellCommand` parser and execs the argv directly,
/// without a shell. Inside double quotes that tokenizer treats only `"` and `\`
/// as special; `$` and backticks are ordinary literals. Escaping `$`/`` ` ``
/// would therefore leave a stray backslash in the delivered argument — which
/// silently corrupted the login shell's constant `exec "$@"` program (it
/// arrived as `exec "\$@"`) and made every iTerm session exit immediately. Only
/// the two characters meaningful to the tokenizer are escaped; every other byte,
/// `$` and backtick included, is carried literally, and no shell ever evaluates
/// it.
enum ITermCommandEncoder {
  static func quote(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  static func command(arguments: [String]) -> String {
    arguments.map(quote).joined(separator: " ")
  }
}

enum TerminalLauncher {
  // Data reaches these static scripts only through osascript's argv. It is not
  // interpolated into AppleScript source and never enters a shell.
  static let ghosttyLaunchScript = """
    on run argv
        if (count of argv) is not 2 then error "Expected a working directory and a launch command"
        set workingDirectory to item 1 of argv
        set launchCommand to item 2 of argv
        tell application id "com.mitchellh.ghostty"
            new window with configuration {initial working directory:workingDirectory, command:launchCommand}
            activate
        end tell
    end run
    """

  static let iTermLaunchScript = """
    on run argv
        if (count of argv) is not 1 then error "Expected one launch command"
        set launchCommand to item 1 of argv
        tell application id "com.googlecode.iterm2"
            create window with default profile command launchCommand
            activate
        end tell
    end run
    """

  @MainActor
  static func isTerminalInstalled(_ terminal: TerminalKind) -> Bool {
    NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: terminal.bundleIdentifier
    ) != nil
  }

  @MainActor
  static func launch(
    _ resolvedAgent: ResolvedAgent,
    workingDirectory: URL,
    loginShell: LoginShell? = nil
  ) async throws {
    guard let executableURL = resolvedAgent.executableURL else {
      throw TerminalLauncherError.missingExecutable(
        resolvedAgent.specification.displayName
      )
    }

    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: workingDirectory.path,
        isDirectory: &isDirectory
      ), isDirectory.boolValue
    else {
      throw TerminalLauncherError.invalidWorkingDirectory
    }

    let terminal = resolvedAgent.specification.terminal
    guard isTerminalInstalled(terminal) else {
      throw TerminalLauncherError.missingTerminal(terminal.displayName)
    }

    let shell: LoginShell
    do {
      shell = try loginShell ?? LoginShell.current()
    } catch LoginShellError.unsupportedShell(let name) {
      throw TerminalLauncherError.unsupportedLoginShell(name)
    }

    let arguments = AgentCommand.arguments(
      executableURL: executableURL,
      workingDirectory: workingDirectory,
      loginShell: shell
    )

    switch terminal {
    case .ghostty:
      try await runLaunchScript(
        ghosttyLaunchScript,
        arguments: [
          workingDirectory.path,
          BashCommandEncoder.command(arguments: arguments),
        ],
        terminal: terminal
      )
    case .iTerm:
      try await runLaunchScript(
        iTermLaunchScript,
        arguments: [ITermCommandEncoder.command(arguments: arguments)],
        terminal: terminal
      )
    }
  }

  private static func runLaunchScript(
    _ script: String,
    arguments: [String],
    terminal: TerminalKind
  ) async throws {
    let result: ProcessResult
    do {
      result = try await ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
        arguments: ["-e", script, "--"] + arguments,
        timeout: 60
      )
    } catch {
      throw TerminalLauncherError.launchFailed(error.localizedDescription)
    }

    if result.terminationStatus == 0 {
      return
    }
    if result.timedOut {
      throw TerminalLauncherError.timedOut(terminal.displayName)
    }

    let errorText = result.standardError.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    if errorText.contains("(-1743)") {
      throw TerminalLauncherError.automationDenied(terminal.displayName)
    }

    throw TerminalLauncherError.launchFailed(
      errorText.isEmpty
        ? "\(terminal.displayName) automation exited with status \(result.terminationStatus)."
        : errorText
    )
  }
}
