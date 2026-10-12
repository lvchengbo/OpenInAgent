import AppKit
import Darwin
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
  public static func userConfigDirectory(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL {
    var home = homeDirectory
    let containerMarker = "/Library/Containers/"
    if let range = home.path.range(of: containerMarker) {
      home = URL(fileURLWithPath: String(home.path[..<range.lowerBound]), isDirectory: true)
    }
    return home.appendingPathComponent(".config/openinagent", isDirectory: true)
  }

  public static var userConfigDirectory: URL {
    userConfigDirectory()
  }

  public static func userConfigFile(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL {
    userConfigDirectory(homeDirectory: homeDirectory)
      .appendingPathComponent("config.json", isDirectory: false)
  }

  public static var userConfigFile: URL {
    userConfigFile()
  }

  public static func containerConfigFile(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) -> URL {
    if let appSupport = try? fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false
    ), appSupport.path.contains("/Library/Containers/com.lvchengbo.openinagent.finderextension/") {
      return
        appSupport
        .appendingPathComponent("OpenInAgent", isDirectory: true)
        .appendingPathComponent("config.json", isDirectory: false)
    }

    var home = homeDirectory
    let containerMarker = "/Library/Containers/"
    if let range = home.path.range(of: containerMarker) {
      home = URL(fileURLWithPath: String(home.path[..<range.lowerBound]), isDirectory: true)
    }

    return
      home
      .appendingPathComponent(
        "Library/Containers/com.lvchengbo.openinagent.finderextension/Data/Library/Application Support/OpenInAgent/config.json",
        isDirectory: false)
  }

  public static func load(
    userConfigFile: URL = userConfigFile,
    containerConfigFile: URL = containerConfigFile()
  ) -> OpenInAgentConfig {
    if let userData = try? Data(contentsOf: userConfigFile),
      let userConfig = try? JSONDecoder().decode(OpenInAgentConfig.self, from: userData)
    {
      let isSymlink: Bool = {
        let values = try? userConfigFile.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
      }()
      if !isSymlink {
        let containerDir = containerConfigFile.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: containerDir.path) {
          try? userData.write(to: containerConfigFile, options: .atomic)
        }
      }
      return userConfig
    }

    if let containerData = try? Data(contentsOf: containerConfigFile),
      let config = try? JSONDecoder().decode(OpenInAgentConfig.self, from: containerData)
    {
      return config
    }

    return .default
  }

  public static func save(
    _ config: OpenInAgentConfig,
    userConfigFile: URL = userConfigFile,
    containerConfigFile: URL = containerConfigFile()
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(config)

    var writeError: Error?
    var succeeded = false

    let containerDir = containerConfigFile.deletingLastPathComponent()
    try? FileManager.default.createDirectory(
      at: containerDir,
      withIntermediateDirectories: true
    )
    do {
      try data.write(to: containerConfigFile, options: .atomic)
      succeeded = true
    } catch {
      writeError = error
    }

    let resolvedUserConfig = userConfigFile.resolvingSymlinksInPath()
    if resolvedUserConfig.standardized.path != containerConfigFile.standardized.path {
      try? FileManager.default.createDirectory(
        at: userConfigFile.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      do {
        try data.write(to: resolvedUserConfig, options: .atomic)
        succeeded = true
      } catch {
        if !succeeded {
          writeError = error
        }
      }
    }

    if !succeeded, let writeError {
      throw writeError
    }
  }

  @discardableResult
  public static func ensureConfigFileExists(
    userConfigFile: URL = userConfigFile,
    containerConfigFile: URL = containerConfigFile()
  ) -> URL {
    let containerDir = containerConfigFile.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: containerConfigFile.path) {
      try? FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      if let data = try? encoder.encode(OpenInAgentConfig.default) {
        try? data.write(to: containerConfigFile, options: .atomic)
      }
    }

    var st = stat()
    let entryExists = lstat(userConfigFile.path, &st) == 0
    let targetExists = FileManager.default.fileExists(atPath: userConfigFile.path)

    if entryExists && !targetExists {
      try? FileManager.default.removeItem(at: userConfigFile)
    }

    let userConfigDir = userConfigFile.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: userConfigFile.path) {
      try? FileManager.default.createDirectory(at: userConfigDir, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: containerConfigFile.path) {
        try? FileManager.default.createSymbolicLink(
          at: userConfigFile,
          withDestinationURL: containerConfigFile
        )
      }
    }

    if !FileManager.default.fileExists(atPath: userConfigFile.path) {
      try? save(.default, userConfigFile: userConfigFile, containerConfigFile: containerConfigFile)
    }

    return userConfigFile
  }
}
