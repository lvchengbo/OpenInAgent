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
}
