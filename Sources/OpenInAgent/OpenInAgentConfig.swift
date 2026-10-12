import AppKit
import Darwin
import Foundation

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
    Dictionary(
      uniqueKeysWithValues: AgentCatalog.all.map { agent in
        (
          agent.id.rawValue,
          AgentConfig(terminal: agent.terminal.rawValue, flags: agent.defaultAutonomousFlags)
        )
      }
    )
  }

  public static let `default` = OpenInAgentConfig()

  func terminal(for agent: AgentSpec) -> TerminalKind {
    guard let name = agents[agent.id.rawValue]?.terminal,
      let terminal = TerminalKind(rawValue: name.lowercased())
    else {
      return agent.terminal
    }
    return terminal
  }
}

enum ConfigStorageError: LocalizedError {
  case invalidConfiguration(String)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let path):
      "The configuration at \(path) is invalid. Fix its JSON before trying again."
    }
  }
}

public enum ConfigStorage {
  static let initializationArgument = "--initialize-config"
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
    if let userData = try? Data(contentsOf: userConfigFile) {
      // A readable user file is authoritative. Invalid edits must never revive
      // an older cached YOLO configuration. Container fallback remains for the
      // Finder extension, whose sandbox cannot read the user-facing path.
      guard var userConfig = try? JSONDecoder().decode(OpenInAgentConfig.self, from: userData)
      else {
        return .default
      }
      let isSymlink: Bool = {
        let values = try? userConfigFile.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
      }()
      if migrateLegacyAutonomousFlags(in: &userConfig) {
        try? save(
          userConfig, userConfigFile: userConfigFile, containerConfigFile: containerConfigFile
        )
      } else if !isSymlink {
        let containerDir = containerConfigFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
          at: containerDir, withIntermediateDirectories: true)
        try? userData.write(to: containerConfigFile, options: .atomic)
      }
      return userConfig
    }

    if let containerData = try? Data(contentsOf: containerConfigFile),
      var config = try? JSONDecoder().decode(OpenInAgentConfig.self, from: containerData)
    {
      if migrateLegacyAutonomousFlags(in: &config) {
        try? save(config, userConfigFile: userConfigFile, containerConfigFile: containerConfigFile)
      }
      return config
    }

    return .default
  }

  /// Replace only obsolete defaults; preserve custom flags and terminal choices.
  private static func migrateLegacyAutonomousFlags(in config: inout OpenInAgentConfig) -> Bool {
    var migrated = false
    for agent in ["agy", "grok"] where config.agents[agent]?.flags == ["-y"] {
      config.agents[agent]?.flags = OpenInAgentConfig.defaultAgents[agent]?.flags
      migrated = true
    }
    return migrated
  }

  public static func save(
    _ config: OpenInAgentConfig,
    userConfigFile: URL = userConfigFile,
    containerConfigFile: URL = containerConfigFile()
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(config)

    let containerTarget = containerConfigFile.resolvingSymlinksInPath()
    let resolvedUserConfig = userConfigFile.resolvingSymlinksInPath()
    if resolvedUserConfig.standardized.path != containerTarget.standardized.path {
      // The host reads this file first. A failed authoritative write must not
      // change the cached copy or report success that the next load undoes.
      try FileManager.default.createDirectory(
        at: resolvedUserConfig.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: resolvedUserConfig, options: .atomic)
    }

    try FileManager.default.createDirectory(
      at: containerTarget.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: containerTarget, options: .atomic)
  }

  @discardableResult
  static func setMode(
    _ mode: AgentLaunchMode,
    userConfigFile: URL = userConfigFile,
    containerConfigFile: URL = containerConfigFile()
  ) throws -> OpenInAgentConfig {
    // Only the host can update an independent user file outside the sandbox.
    // Validate first so changing mode never replaces an invalid edit.
    try ensureConfigFileExists(
      userConfigFile: userConfigFile, containerConfigFile: containerConfigFile
    )
    var config = load(userConfigFile: userConfigFile, containerConfigFile: containerConfigFile)
    config.mode = mode
    try save(config, userConfigFile: userConfigFile, containerConfigFile: containerConfigFile)
    return config
  }

  @discardableResult
  static func fileForEditing(
    userConfigFile: URL = userConfigFile,
    containerConfigFile: URL = containerConfigFile()
  ) throws -> URL {
    do {
      return try ensureConfigFileExists(
        userConfigFile: userConfigFile, containerConfigFile: containerConfigFile
      )
    } catch ConfigStorageError.invalidConfiguration(let path) {
      // Opening the original file is how the user repairs malformed JSON.
      return URL(fileURLWithPath: path)
    }
  }

  @discardableResult
  public static func ensureConfigFileExists(
    userConfigFile: URL = userConfigFile,
    containerConfigFile: URL = containerConfigFile()
  ) throws -> URL {
    let fileManager = FileManager.default
    var st = stat()
    let entryExists = lstat(userConfigFile.path, &st) == 0
    let targetExists = fileManager.fileExists(atPath: userConfigFile.path)
    if entryExists && st.st_mode & S_IFMT == S_IFLNK && !targetExists {
      try fileManager.removeItem(at: userConfigFile)
    }

    // An existing user file is authoritative even when the container is missing
    // or stale. Never replace invalid user data with defaults.
    let sourceFile: URL?
    if targetExists {
      sourceFile = userConfigFile
    } else if fileManager.fileExists(atPath: containerConfigFile.path) {
      sourceFile = containerConfigFile
    } else {
      sourceFile = nil
    }

    var config = OpenInAgentConfig.default
    var data: Data
    if let sourceFile {
      data = try Data(contentsOf: sourceFile)
      guard let decoded = try? JSONDecoder().decode(OpenInAgentConfig.self, from: data) else {
        throw ConfigStorageError.invalidConfiguration(sourceFile.path)
      }
      config = decoded
    } else {
      data = try JSONEncoder().encode(config)
    }

    let migrated = migrateLegacyAutonomousFlags(in: &config)
    if migrated { data = try JSONEncoder().encode(config) }
    let containerTarget = containerConfigFile.resolvingSymlinksInPath()
    try fileManager.createDirectory(
      at: containerTarget.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    if (try? Data(contentsOf: containerTarget)) != data {
      try data.write(to: containerTarget, options: .atomic)
    }

    if targetExists {
      if migrated {
        try data.write(to: userConfigFile.resolvingSymlinksInPath(), options: .atomic)
      }
    } else {
      try fileManager.createDirectory(
        at: userConfigFile.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      try fileManager.createSymbolicLink(
        at: userConfigFile, withDestinationURL: containerConfigFile)
    }

    return userConfigFile
  }
}
