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
    XCTAssertEqual(config.agents["grok"]?.flags, ["-y"])
    XCTAssertEqual(config.agents["agy"]?.flags, ["-y"])
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

    let result = ConfigStorage.ensureConfigFileExists(
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
}
