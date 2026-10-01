import Foundation

enum AgentID: String, CaseIterable, Identifiable, Sendable {
  case claude
  case codex
  case grok
  case agy

  var id: String { rawValue }
}

enum TerminalKind: String, Sendable {
  case ghostty
  case iTerm

  var displayName: String {
    switch self {
    case .ghostty:
      "Ghostty"
    case .iTerm:
      "iTerm"
    }
  }

  var bundleIdentifier: String {
    switch self {
    case .ghostty:
      "com.mitchellh.ghostty"
    case .iTerm:
      "com.googlecode.iterm2"
    }
  }

  /// Oldest release whose automation API the launcher relies on. Ghostty's
  /// AppleScript dictionary first shipped in 1.3.0.
  var minimumVersion: String? {
    switch self {
    case .ghostty:
      "1.3.0"
    case .iTerm:
      nil
    }
  }
}

struct AgentSpec: Identifiable, Equatable, Sendable {
  let id: AgentID
  let displayName: String
  let executableName: String
  let terminal: TerminalKind
  let symbolName: String
  let preferredRelativePaths: [String]
}

enum AgentCatalog {
  static let all: [AgentSpec] = [
    AgentSpec(
      id: .claude,
      displayName: "Claude",
      executableName: "claude",
      terminal: .ghostty,
      symbolName: "brain.head.profile",
      preferredRelativePaths: [".local/bin/claude"]
    ),
    AgentSpec(
      id: .codex,
      displayName: "Codex",
      executableName: "codex",
      terminal: .iTerm,
      symbolName: "terminal",
      preferredRelativePaths: [".local/bin/codex"]
    ),
    AgentSpec(
      id: .grok,
      displayName: "Grok",
      executableName: "grok",
      terminal: .iTerm,
      symbolName: "sparkles",
      preferredRelativePaths: [".grok/bin/grok", ".local/bin/grok"]
    ),
    AgentSpec(
      id: .agy,
      displayName: "AGY",
      executableName: "agy",
      terminal: .iTerm,
      symbolName: "wand.and.stars",
      preferredRelativePaths: [".local/bin/agy"]
    ),
  ]
}

struct ResolvedAgent: Equatable, Sendable {
  let specification: AgentSpec
  let executableURL: URL?

  var isInstalled: Bool { executableURL != nil }
}
