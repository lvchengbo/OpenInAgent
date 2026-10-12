import AppKit
import Foundation

struct DiagnosticEntry: Equatable, Sendable {
  let agent: ResolvedAgent
  let terminalURL: URL?
  var terminalMeetsMinimumVersion = true
  var configuredTerminal: TerminalKind?

  var isReady: Bool {
    agent.executableURL != nil && terminalURL != nil
      && terminalMeetsMinimumVersion
  }

  var description: String {
    let command = agent.executableURL?.path ?? "not found"
    let terminal = terminalURL?.path ?? "not found"
    let terminalKind = configuredTerminal ?? agent.specification.terminal
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
    entries(
      agents: ExecutableResolver.resolveAll(),
      config: ConfigStorage.load(),
      applicationURL: {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier)
      },
      meetsMinimumVersion: TerminalLauncher.meetsMinimumVersion
    )
  }

  static func entries(
    agents: [ResolvedAgent],
    config: OpenInAgentConfig,
    applicationURL: (TerminalKind) -> URL?,
    meetsMinimumVersion: (TerminalKind) -> Bool
  ) -> [DiagnosticEntry] {
    agents.map { agent in
      let terminal = config.terminal(for: agent.specification)
      return DiagnosticEntry(
        agent: agent,
        terminalURL: applicationURL(terminal),
        terminalMeetsMinimumVersion: meetsMinimumVersion(terminal),
        configuredTerminal: terminal
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
