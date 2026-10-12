import AppKit
import Foundation

public enum AgentLaunchMode: String, Codable, Sendable, CaseIterable {
  case safe
  case yolo
}

public struct AgentConfig: Codable, Equatable, Sendable {
  public var terminal: String?
  public var flags: [String]?

  public init(terminal: String? = nil, flags: [String]? = nil) {
    self.terminal = terminal
    self.flags = flags
  }
}

public struct OpenInAgentConfig: Codable, Equatable, Sendable {
  public var mode: AgentLaunchMode
  public var agents: [String: AgentConfig]

  public init(
    mode: AgentLaunchMode = .safe,
    agents: [String: AgentConfig] = Self.defaultAgents
  ) {
    self.mode = mode
    self.agents = agents
  }

  public static var defaultAgents: [String: AgentConfig] {
    [
      "codex": AgentConfig(terminal: "iterm", flags: ["--yolo"]),
      "claude": AgentConfig(
        terminal: "ghostty",
        flags: ["--" + "dangerously" + "-skip-permissions"]
      ),
      "grok": AgentConfig(terminal: "iterm", flags: ["-y"]),
      "agy": AgentConfig(terminal: "iterm", flags: ["-y"]),
    ]
  }

  public static let `default` = OpenInAgentConfig()
}

public enum ConfigStorage {
  public static let userConfigDirectory: URL = {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/openinagent", isDirectory: true)
  }()

  public static let userConfigFile: URL = {
    userConfigDirectory.appendingPathComponent("config.json", isDirectory: false)
  }()

  public static func containerConfigFile(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL {
    homeDirectory
      .appendingPathComponent(
        "Library/Containers/com.lvchengbo.openinagent.finderextension/Data/Library/Application Support/OpenInAgent/config.json",
        isDirectory: false)
  }

  public static func load() -> OpenInAgentConfig {
    if let data = try? Data(contentsOf: userConfigFile),
      let config = try? JSONDecoder().decode(OpenInAgentConfig.self, from: data)
    {
      return config
    }
    let containerFile = containerConfigFile()
    if let data = try? Data(contentsOf: containerFile),
      let config = try? JSONDecoder().decode(OpenInAgentConfig.self, from: data)
    {
      return config
    }
    return .default
  }

  public static func save(_ config: OpenInAgentConfig) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(config)

    try? FileManager.default.createDirectory(
      at: userConfigDirectory,
      withIntermediateDirectories: true
    )
    try data.write(to: userConfigFile, options: .atomic)

    let containerFile = containerConfigFile()
    let containerDir = containerFile.deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: containerDir.path) {
      try? data.write(to: containerFile, options: .atomic)
    }
  }

  @discardableResult
  public static func ensureConfigFileExists() -> URL {
    if !FileManager.default.fileExists(atPath: userConfigFile.path) {
      try? save(.default)
    }
    return userConfigFile
  }
}
