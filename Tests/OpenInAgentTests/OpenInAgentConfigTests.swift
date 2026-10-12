import Foundation
import XCTest

@testable import OpenInAgent

final class OpenInAgentConfigTests: XCTestCase {
  func testDefaultConfigValues() {
    let config = OpenInAgentConfig.default
    XCTAssertEqual(config.mode, .safe)
    XCTAssertEqual(config.agents["codex"]?.terminal, "iterm")
    XCTAssertEqual(config.agents["codex"]?.flags, ["--yolo"])
    XCTAssertEqual(config.agents["claude"]?.terminal, "ghostty")
    XCTAssertEqual(config.agents["grok"]?.flags, ["--always-approve"])
    XCTAssertEqual(config.agents["agy"]?.flags, ["--dangerously-skip-permissions"])
  }

  func testJSONEncodingAndDecodingRoundTrip() throws {
    var config = OpenInAgentConfig()
    config.mode = .yolo
    config.agents["codex"] = AgentConfig(terminal: "ghostty", flags: ["--yolo", "--verbose"])

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(OpenInAgentConfig.self, from: data)

    XCTAssertEqual(decoded.mode, .yolo)
    XCTAssertEqual(decoded.agents["codex"]?.terminal, "ghostty")
    XCTAssertEqual(decoded.agents["codex"]?.flags, ["--yolo", "--verbose"])
  }

  func testTerminalOverridesMatchConfiguredRoutes() throws {
    let claude = try XCTUnwrap(AgentCatalog.all.first { $0.id == .claude })
    let codex = try XCTUnwrap(AgentCatalog.all.first { $0.id == .codex })
    var config = OpenInAgentConfig.default
    for name in ["iterm", "iTerm", "ITERM"] {
      config.agents["claude"]?.terminal = name
      XCTAssertEqual(config.terminal(for: claude), .iTerm, name)
    }
    config.agents["codex"]?.terminal = "ghostty"
    XCTAssertEqual(config.terminal(for: codex), .ghostty)
    config.agents["claude"]?.terminal = "unknown"
    XCTAssertEqual(config.terminal(for: claude), .ghostty)
    config.agents["claude"]?.terminal = nil
    XCTAssertEqual(config.terminal(for: claude), .ghostty)
  }

  func testAgentCommandAppendsExtraArguments() throws {
    let executable = URL(fileURLWithPath: "/Users/test/.local/bin/codex")
    let directory = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
    let shell = try XCTUnwrap(LoginShell(shellPath: "/bin/zsh"))

    let args = AgentCommand.arguments(
      executableURL: executable,
      workingDirectory: directory,
      loginShell: shell,
      arguments: ["--yolo", "--model", "o3-mini"]
    )

    XCTAssertEqual(
      args,
      [
        "/bin/zsh",
        "+m",
        "-l",
        "-i",
        "-c",
        "exec \"$@\"",
        "open-in-agent",
        "/usr/bin/env",
        "-C",
        "/tmp/project",
        "--",
        "PWD=/tmp/project",
        "/Users/test/.local/bin/codex",
        "--yolo",
        "--model",
        "o3-mini",
      ]
    )
  }

  func testConfigStorageSymlinkPreservation() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let containerFile = tmp.appendingPathComponent("container/config.json")
    let userFile = tmp.appendingPathComponent("user/config.json")
    try FileManager.default.createDirectory(
      at: containerFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: userFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var initial = OpenInAgentConfig.default
    initial.mode = .safe
    let encoder = JSONEncoder()
    try encoder.encode(initial).write(to: containerFile)
    try FileManager.default.createSymbolicLink(at: userFile, withDestinationURL: containerFile)

    var updated = OpenInAgentConfig.default
    updated.mode = .yolo
    try ConfigStorage.save(updated, userConfigFile: userFile, containerConfigFile: containerFile)

    var st = stat()
    XCTAssertEqual(lstat(userFile.path, &st), 0)
    XCTAssertEqual(
      st.st_mode & S_IFMT,
      S_IFLNK,
      "userConfigFile must remain a symbolic link after save"
    )

    let loaded = ConfigStorage.load(userConfigFile: userFile, containerConfigFile: containerFile)
    XCTAssertEqual(loaded.mode, .yolo)

    let containerData = try Data(contentsOf: containerFile)
    let decodedContainer = try JSONDecoder().decode(OpenInAgentConfig.self, from: containerData)
    XCTAssertEqual(decodedContainer.mode, .yolo)
  }

  func testConfigStorageSyncFromIndependentUserFileToContainer() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let containerFile = tmp.appendingPathComponent("container/config.json")
    let userFile = tmp.appendingPathComponent("user/config.json")
    try FileManager.default.createDirectory(
      at: containerFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: userFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var initial = OpenInAgentConfig.default
    initial.mode = .safe
    try JSONEncoder().encode(initial).write(to: containerFile)

    var userEdited = OpenInAgentConfig.default
    userEdited.mode = .yolo
    try JSONEncoder().encode(userEdited).write(to: userFile)

    let loaded = ConfigStorage.load(userConfigFile: userFile, containerConfigFile: containerFile)
    XCTAssertEqual(loaded.mode, .yolo)

    let containerData = try Data(contentsOf: containerFile)
    let decodedContainer = try JSONDecoder().decode(OpenInAgentConfig.self, from: containerData)
    XCTAssertEqual(
      decodedContainer.mode,
      .yolo,
      "containerConfigFile must be synced with userFile edits"
    )
  }

  func testConfigStorageMigratesLegacyAGYFlagsInUserFileAndContainer() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let userFile = tmp.appendingPathComponent("user/config.json")
    let containerFile = tmp.appendingPathComponent("container/config.json")

    var legacy = OpenInAgentConfig.default
    legacy.mode = .yolo
    legacy.agents["agy"] = AgentConfig(terminal: "ghostty", flags: ["-y"])
    legacy.agents["codex"]?.flags = ["--yolo", "--model", "custom-model"]
    try ConfigStorage.save(legacy, userConfigFile: userFile, containerConfigFile: containerFile)

    let loaded = ConfigStorage.load(userConfigFile: userFile, containerConfigFile: containerFile)
    XCTAssertEqual(loaded.mode, .yolo)
    XCTAssertEqual(loaded.agents["agy"]?.terminal, "ghostty")
    XCTAssertEqual(loaded.agents["agy"]?.flags, ["--dangerously-skip-permissions"])
    XCTAssertEqual(loaded.agents["codex"], legacy.agents["codex"])

    for file in [userFile, containerFile] {
      let stored = try JSONDecoder().decode(OpenInAgentConfig.self, from: Data(contentsOf: file))
      XCTAssertEqual(stored.agents, loaded.agents)
      XCTAssertEqual(stored.mode, .yolo)
    }
  }

  func testConfigStorageMigratesLegacyAGYFlagsWithoutReplacingSymlink() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let userFile = tmp.appendingPathComponent("config.json")
    let containerFile = tmp.appendingPathComponent("container/config.json")
    try FileManager.default.createDirectory(
      at: containerFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    var legacy = OpenInAgentConfig.default
    legacy.agents["agy"]?.flags = ["-y"]
    try JSONEncoder().encode(legacy).write(to: containerFile)
    try FileManager.default.createSymbolicLink(at: userFile, withDestinationURL: containerFile)

    let loaded = ConfigStorage.load(userConfigFile: userFile, containerConfigFile: containerFile)
    XCTAssertEqual(loaded.mode, .safe)
    XCTAssertEqual(loaded.agents["agy"]?.flags, ["--dangerously-skip-permissions"])
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: userFile.path),
      containerFile.path
    )
    let stored = try JSONDecoder().decode(
      OpenInAgentConfig.self, from: Data(contentsOf: containerFile)
    )
    XCTAssertEqual(stored.agents, loaded.agents)
  }

  func testConfigStorageMigratesLegacyAGYFlagsWhenOnlyContainerExists() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let userFile = tmp.appendingPathComponent("user/config.json")
    let containerFile = tmp.appendingPathComponent("container/config.json")
    try FileManager.default.createDirectory(
      at: containerFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    var legacy = OpenInAgentConfig.default
    legacy.agents["agy"]?.flags = ["-y"]
    try JSONEncoder().encode(legacy).write(to: containerFile)

    let loaded = ConfigStorage.load(userConfigFile: userFile, containerConfigFile: containerFile)
    XCTAssertEqual(loaded.agents["agy"]?.flags, ["--dangerously-skip-permissions"])
    for file in [userFile, containerFile] {
      let stored = try JSONDecoder().decode(OpenInAgentConfig.self, from: Data(contentsOf: file))
      XCTAssertEqual(stored.agents, loaded.agents)
    }
  }

  func testConfigStoragePreservesCustomAutonomousFlags() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let userFile = tmp.appendingPathComponent("user/config.json")
    let containerFile = tmp.appendingPathComponent("container/config.json")

    let flagSets: [[String]?] = [nil, [], ["--model", "custom-model"], ["-y", "--custom-flag"]]
    for agent in ["agy", "grok"] {
      for flags in flagSets {
        var custom = OpenInAgentConfig.default
        custom.agents[agent] = AgentConfig(terminal: "ghostty", flags: flags)
        try ConfigStorage.save(custom, userConfigFile: userFile, containerConfigFile: containerFile)

        let originalData = try Data(contentsOf: userFile)
        let loaded = ConfigStorage.load(
          userConfigFile: userFile, containerConfigFile: containerFile)
        XCTAssertEqual(loaded.agents, custom.agents)
        XCTAssertEqual(try Data(contentsOf: userFile), originalData)
      }
    }
  }

  func testConfigStorageMigratesLegacyGrokFlagsAndPreservesPreferences() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let userFile = tmp.appendingPathComponent("user/config.json")
    let containerFile = tmp.appendingPathComponent("container/config.json")
    var legacy = OpenInAgentConfig.default
    legacy.mode = .yolo
    legacy.agents["grok"] = AgentConfig(terminal: "ghostty", flags: ["-y"])
    try ConfigStorage.save(legacy, userConfigFile: userFile, containerConfigFile: containerFile)

    let loaded = ConfigStorage.load(userConfigFile: userFile, containerConfigFile: containerFile)
    XCTAssertEqual(loaded.mode, .yolo)
    XCTAssertEqual(loaded.agents["grok"]?.terminal, "ghostty")
    XCTAssertEqual(loaded.agents["grok"]?.flags, ["--always-approve"])
    for file in [userFile, containerFile] {
      let stored = try JSONDecoder().decode(OpenInAgentConfig.self, from: Data(contentsOf: file))
      XCTAssertEqual(stored, loaded)
    }

    let grok = try XCTUnwrap(AgentCatalog.all.first { $0.id == .grok })
    XCTAssertEqual(grok.defaultAutonomousFlags, ["--always-approve"])
  }

  func testEnsureConfigFileExistsRepairsBrokenSymlink() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let containerFile = tmp.appendingPathComponent("container/config.json")
    let userFile = tmp.appendingPathComponent("user/config.json")
    let brokenTarget = tmp.appendingPathComponent("nonexistent/target.json")
    try FileManager.default.createDirectory(
      at: userFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(at: userFile, withDestinationURL: brokenTarget)

    let result = try ConfigStorage.ensureConfigFileExists(
      userConfigFile: userFile,
      containerConfigFile: containerFile
    )
    XCTAssertEqual(result.path, userFile.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: containerFile.path))

    var st = stat()
    XCTAssertEqual(lstat(userFile.path, &st), 0)
    XCTAssertEqual(
      st.st_mode & S_IFMT,
      S_IFLNK,
      "Repaired userConfigFile must be a valid symbolic link"
    )
  }

  func testEnsureConfigFileCopiesExistingUserSettingsToMissingContainer() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let userFile = tmp.appendingPathComponent("user/config.json")
    let containerFile = tmp.appendingPathComponent("container/config.json")
    try FileManager.default.createDirectory(
      at: userFile.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    var custom = OpenInAgentConfig.default
    custom.mode = .yolo
    custom.agents["claude"]?.terminal = "iterm"
    let originalData = try JSONEncoder().encode(custom)
    try originalData.write(to: userFile)

    _ = try ConfigStorage.ensureConfigFileExists(
      userConfigFile: userFile, containerConfigFile: containerFile
    )
    XCTAssertEqual(try Data(contentsOf: userFile), originalData)
    XCTAssertEqual(try Data(contentsOf: containerFile), originalData)
  }

  func testConfigLoadCreatesMissingContainerFromUserFile() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let userFile = tmp.appendingPathComponent("user/config.json")
    let containerFile = tmp.appendingPathComponent("container/config.json")
    try FileManager.default.createDirectory(
      at: userFile.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    var custom = OpenInAgentConfig.default
    custom.mode = .yolo
    let originalData = try JSONEncoder().encode(custom)
    try originalData.write(to: userFile)

    XCTAssertEqual(
      ConfigStorage.load(userConfigFile: userFile, containerConfigFile: containerFile), custom
    )
    XCTAssertEqual(try Data(contentsOf: containerFile), originalData)
  }

  func testConfigInitializationReportsWriteFailureAndPreservesUserFile() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let userFile = tmp.appendingPathComponent("config.json")
    let blockedDirectory = tmp.appendingPathComponent("not-a-directory")
    let containerFile = blockedDirectory.appendingPathComponent("config.json")
    let originalData = try JSONEncoder().encode(OpenInAgentConfig.default)
    try originalData.write(to: userFile)
    try Data("keep".utf8).write(to: blockedDirectory)

    XCTAssertThrowsError(
      try ConfigStorage.ensureConfigFileExists(
        userConfigFile: userFile, containerConfigFile: containerFile
      )
    )
    XCTAssertEqual(try Data(contentsOf: userFile), originalData)
    XCTAssertEqual(try Data(contentsOf: blockedDirectory), Data("keep".utf8))
  }

  func testConfigInitializationRejectsInvalidJSONWithoutOverwritingIt() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let userFile = tmp.appendingPathComponent("config.json")
    let containerFile = tmp.appendingPathComponent("container/config.json")
    let invalidData = Data("{ unfinished".utf8)
    try invalidData.write(to: userFile)

    XCTAssertThrowsError(
      try ConfigStorage.ensureConfigFileExists(
        userConfigFile: userFile, containerConfigFile: containerFile
      )
    ) { error in
      guard case .invalidConfiguration = error as? ConfigStorageError else {
        return XCTFail("Expected an invalid configuration error, received \(error)")
      }
    }
    XCTAssertEqual(try Data(contentsOf: userFile), invalidData)
    XCTAssertFalse(FileManager.default.fileExists(atPath: containerFile.path))
  }

  func testContainerConfigFileResolutionStripsContainerPrefix() {
    let containerHome = URL(
      fileURLWithPath:
        "/Users/alice/Library/Containers/com.lvchengbo.openinagent.finderextension/Data",
      isDirectory: true
    )
    let resolved = ConfigStorage.containerConfigFile(homeDirectory: containerHome)
    XCTAssertEqual(
      resolved.path,
      "/Users/alice/Library/Containers/com.lvchengbo.openinagent.finderextension/Data/Library/Application Support/OpenInAgent/config.json"
    )

    let userHome = URL(fileURLWithPath: "/Users/alice", isDirectory: true)
    let userResolved = ConfigStorage.containerConfigFile(homeDirectory: userHome)
    XCTAssertEqual(
      userResolved.path,
      "/Users/alice/Library/Containers/com.lvchengbo.openinagent.finderextension/Data/Library/Application Support/OpenInAgent/config.json"
    )

    let userConfigDir = ConfigStorage.userConfigDirectory(homeDirectory: containerHome)
    XCTAssertEqual(userConfigDir.path, "/Users/alice/.config/openinagent")
  }

  func testInvalidUserConfigurationCanBeOpenedForRepair() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let userFile = tmp.appendingPathComponent("config.json")
    let containerFile = tmp.appendingPathComponent("container/config.json")
    let invalidData = Data("{ unfinished".utf8)
    try invalidData.write(to: userFile)

    XCTAssertEqual(
      try ConfigStorage.fileForEditing(
        userConfigFile: userFile, containerConfigFile: containerFile
      ), userFile
    )
    XCTAssertEqual(try Data(contentsOf: userFile), invalidData)
    XCTAssertFalse(FileManager.default.fileExists(atPath: containerFile.path))
  }

  func testInvalidContainerConfigurationCanBeOpenedForRepair() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let userFile = tmp.appendingPathComponent("user/config.json")
    let containerFile = tmp.appendingPathComponent("config.json")
    let invalidData = Data("{ unfinished".utf8)
    try invalidData.write(to: containerFile)

    XCTAssertEqual(
      try ConfigStorage.fileForEditing(
        userConfigFile: userFile, containerConfigFile: containerFile
      ), containerFile
    )
    XCTAssertEqual(try Data(contentsOf: containerFile), invalidData)
    XCTAssertFalse(FileManager.default.fileExists(atPath: userFile.path))
  }

  func testMalformedUserConfigurationDoesNotLoadStaleYOLOSettings() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let userFile = tmp.appendingPathComponent("config.json")
    let containerFile = tmp.appendingPathComponent("cached.json")
    let invalidData = Data("{ unfinished".utf8)
    try invalidData.write(to: userFile)
    var stale = OpenInAgentConfig.default
    stale.mode = .yolo
    try JSONEncoder().encode(stale).write(to: containerFile)

    XCTAssertEqual(
      ConfigStorage.load(userConfigFile: userFile, containerConfigFile: containerFile), .default
    )
    XCTAssertEqual(try Data(contentsOf: userFile), invalidData)
  }

  func testSaveReportsAuthoritativeUserWriteFailureWithoutChangingContainer() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let userDir = tmp.appendingPathComponent("user")
    try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
    let userFile = userDir.appendingPathComponent("config.json")
    let containerFile = tmp.appendingPathComponent("cached.json")
    let originalData = try JSONEncoder().encode(OpenInAgentConfig.default)
    try originalData.write(to: userFile)
    try originalData.write(to: containerFile)
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: userFile.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: userDir.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: userDir.path)
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644], ofItemAtPath: userFile.path)
    }
    var updated = OpenInAgentConfig.default
    updated.mode = .yolo

    XCTAssertThrowsError(
      try ConfigStorage.save(updated, userConfigFile: userFile, containerConfigFile: containerFile)
    )
    XCTAssertEqual(try Data(contentsOf: userFile), originalData)
    XCTAssertEqual(try Data(contentsOf: containerFile), originalData)
  }

  func testModeChangeSurvivesLoadingIndependentUserFile() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let userFile = tmp.appendingPathComponent("config.json")
    let containerFile = tmp.appendingPathComponent("cached.json")
    var original = OpenInAgentConfig.default
    original.agents["agy"] = AgentConfig(terminal: "ghostty", flags: ["--custom"])
    try ConfigStorage.save(original, userConfigFile: userFile, containerConfigFile: containerFile)

    let store = AgentHandoffStore(directoryURL: tmp.appendingPathComponent("Handoffs"))
    let activationURL = try store.create(.setMode(.yolo))
    guard case .setMode(let mode) = try store.consume(activationURL) else {
      return XCTFail("Expected a mode change request")
    }
    try ConfigStorage.setMode(mode, userConfigFile: userFile, containerConfigFile: containerFile)

    let loaded = ConfigStorage.load(userConfigFile: userFile, containerConfigFile: containerFile)
    XCTAssertEqual(loaded.mode, .yolo)
    XCTAssertEqual(loaded.agents, original.agents)
    let storedUser = try JSONDecoder().decode(
      OpenInAgentConfig.self, from: Data(contentsOf: userFile))
    let storedContainer = try JSONDecoder().decode(
      OpenInAgentConfig.self, from: Data(contentsOf: containerFile))
    XCTAssertEqual(storedUser, loaded)
    XCTAssertEqual(storedContainer, loaded)
  }

  func testModeChangePreservesInvalidUserConfigurationAndCachedSettings() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let userFile = tmp.appendingPathComponent("config.json")
    let containerFile = tmp.appendingPathComponent("cached.json")
    let invalidData = Data("{ unfinished".utf8)
    let cachedData = try JSONEncoder().encode(OpenInAgentConfig.default)
    try invalidData.write(to: userFile)
    try cachedData.write(to: containerFile)

    XCTAssertThrowsError(
      try ConfigStorage.setMode(.yolo, userConfigFile: userFile, containerConfigFile: containerFile)
    )
    XCTAssertEqual(try Data(contentsOf: userFile), invalidData)
    XCTAssertEqual(try Data(contentsOf: containerFile), cachedData)
  }

  func testSaveReportsContainerWriteFailure() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let userFile = tmp.appendingPathComponent("config.json")
    let blockedDirectory = tmp.appendingPathComponent("not-a-directory")
    let containerFile = blockedDirectory.appendingPathComponent("config.json")
    try Data("keep".utf8).write(to: blockedDirectory)

    XCTAssertThrowsError(
      try ConfigStorage.save(.default, userConfigFile: userFile, containerConfigFile: containerFile)
    )
    XCTAssertEqual(try Data(contentsOf: blockedDirectory), Data("keep".utf8))
  }
}
