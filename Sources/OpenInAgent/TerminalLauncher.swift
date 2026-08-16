import AppKit
import Foundation

enum TerminalLauncherError: LocalizedError, Sendable {
  case missingTerminal(String)
  case missingExecutable(String)
  case invalidWorkingDirectory
  case automationDenied
  case timedOut(String)
  case launchFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingTerminal(let name):
      "\(name) is not installed."
    case .missingExecutable(let name):
      "The \(name) command-line tool could not be found."
    case .invalidWorkingDirectory:
      "The selected working directory is no longer available."
    case .automationDenied:
      "Open in Agent is not allowed to control iTerm. Enable iTerm under System Settings → Privacy & Security → Automation, then try again."
    case .timedOut(let name):
      "\(name) did not respond in time."
    case .launchFailed(let detail):
      "The agent could not be launched. \(detail)"
    }
  }
}

enum ITermCommandEncoder {
  static func quote(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "$", with: "\\$")
      .replacingOccurrences(of: "`", with: "\\`")
    return "\"\(escaped)\""
  }

  static func command(
    executableURL: URL,
    workingDirectory: URL,
    arguments: [String] = []
  ) -> String {
    let directoryPath = workingDirectory.path
    let components =
      [
        "/usr/bin/env",
        "-C",
        directoryPath,
        "--",
        "PWD=\(directoryPath)",
        executableURL.path,
      ] + arguments

    return components.map(quote).joined(separator: " ")
  }
}

enum TerminalLauncher {
  // Data reaches this static script only through osascript's argv. It is not
  // interpolated into AppleScript source and never enters a shell.
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
    workingDirectory: URL
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

    switch resolvedAgent.specification.terminal {
    case .ghostty:
      try await launchInGhostty(
        executableURL: executableURL,
        workingDirectory: workingDirectory
      )
    case .iTerm:
      try await launchInITerm(
        executableURL: executableURL,
        workingDirectory: workingDirectory
      )
    }
  }

  static func ghosttyArguments(
    executableURL: URL,
    workingDirectory: URL,
    arguments: [String] = []
  ) -> [String] {
    [
      "--working-directory=\(workingDirectory.path)",
      "-e",
      executableURL.path,
    ] + arguments
  }

  @MainActor
  private static func launchInGhostty(
    executableURL: URL,
    workingDirectory: URL
  ) async throws {
    let terminal = TerminalKind.ghostty
    guard
      let applicationURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: terminal.bundleIdentifier
      )
    else {
      throw TerminalLauncherError.missingTerminal(terminal.displayName)
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.promptsUserIfNeeded = true
    configuration.allowsRunningApplicationSubstitution = false
    configuration.createsNewApplicationInstance = true
    configuration.arguments = ghosttyArguments(
      executableURL: executableURL,
      workingDirectory: workingDirectory
    )

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      NSWorkspace.shared.openApplication(
        at: applicationURL,
        configuration: configuration
      ) { application, error in
        if let error {
          continuation.resume(
            throwing: TerminalLauncherError.launchFailed(
              error.localizedDescription
            )
          )
        } else if application == nil {
          continuation.resume(
            throwing: TerminalLauncherError.launchFailed(
              "Ghostty returned no running application."
            )
          )
        } else {
          continuation.resume()
        }
      }
    }
  }

  @MainActor
  private static func launchInITerm(
    executableURL: URL,
    workingDirectory: URL
  ) async throws {
    let terminal = TerminalKind.iTerm
    guard
      NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: terminal.bundleIdentifier
      ) != nil
    else {
      throw TerminalLauncherError.missingTerminal(terminal.displayName)
    }

    let command = ITermCommandEncoder.command(
      executableURL: executableURL,
      workingDirectory: workingDirectory
    )

    let result: ProcessResult
    do {
      result = try await ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
        arguments: ["-e", iTermLaunchScript, "--", command],
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
      throw TerminalLauncherError.automationDenied
    }

    throw TerminalLauncherError.launchFailed(
      errorText.isEmpty
        ? "iTerm automation exited with status \(result.terminationStatus)."
        : errorText
    )
  }
}
