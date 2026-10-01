import AppKit
import Foundation

struct DiagnosticEntry: Equatable, Sendable {
  let agent: ResolvedAgent
  let terminalURL: URL?
  var terminalMeetsMinimumVersion = true

  var isReady: Bool {
    agent.executableURL != nil && terminalURL != nil
      && terminalMeetsMinimumVersion
  }

  var description: String {
    let command = agent.executableURL?.path ?? "not found"
    let terminal = terminalURL?.path ?? "not found"
    let terminalKind = agent.specification.terminal
    var line =
      "\(agent.specification.displayName): command=\(command) | "
      + "terminal=\(terminalKind.displayName) (\(terminal))"
    if !terminalMeetsMinimumVersion, let minimum = terminalKind.minimumVersion {
      line += " | needs \(terminalKind.displayName) \(minimum) or newer"
    }
    return line
  }
}

enum Diagnostics {
  static let argument = "--diagnose"

  static func isRequested(
    arguments: [String] = CommandLine.arguments
  ) -> Bool {
    arguments.dropFirst().contains(argument)
  }

  @MainActor
  static func liveEntries() -> [DiagnosticEntry] {
    ExecutableResolver.resolveAll().map { agent in
      DiagnosticEntry(
        agent: agent,
        terminalURL: NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: agent.specification.terminal.bundleIdentifier
        ),
        terminalMeetsMinimumVersion: TerminalLauncher.meetsMinimumVersion(
          agent.specification.terminal
        )
      )
    }
  }

  static func report(entries: [DiagnosticEntry]) -> String {
    let header = "OpenInAgent diagnostics"
    let lines = entries.map(\.description)
    let summary =
      entries.allSatisfy(\.isReady)
      ? "Status: ready"
      : "Status: missing required software"
    return ([header] + lines + [summary]).joined(separator: "\n")
  }
}
