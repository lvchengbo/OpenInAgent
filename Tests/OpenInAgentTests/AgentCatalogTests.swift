import Foundation
import XCTest

@testable import OpenInAgent

final class AgentCatalogTests: XCTestCase {
  func testCatalogContainsRequestedAgentsInMenuOrder() {
    XCTAssertEqual(
      AgentCatalog.all.map(\.id),
      [.claude, .codex, .grok, .agy]
    )
  }

  func testTerminalRoutingMatchesPersonalWorkflow() {
    let routing = Dictionary(
      uniqueKeysWithValues: AgentCatalog.all.map { ($0.id, $0.terminal) }
    )

    XCTAssertEqual(routing[.claude], .ghostty)
    XCTAssertEqual(routing[.codex], .iTerm)
    XCTAssertEqual(routing[.grok], .iTerm)
    XCTAssertEqual(routing[.agy], .iTerm)
  }

  func testExecutableResolverPrefersConfiguredHomeLocation() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let executable = root.appendingPathComponent(".local/bin/claude")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )

    let claude = try XCTUnwrap(
      AgentCatalog.all.first { $0.id == .claude }
    )
    let resolved = ExecutableResolver.resolve(
      claude,
      homeDirectory: root
    )

    XCTAssertEqual(resolved.executableURL, executable.standardizedFileURL)
  }

  func testExecutableResolverRejectsExecutableDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let executableName = "not-a-command-\(UUID().uuidString)"
    let directory = root.appendingPathComponent(".local/bin/\(executableName)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: directory.path
    )

    let specification = AgentSpec(
      id: .claude,
      displayName: "Test",
      executableName: executableName,
      terminal: .ghostty,
      symbolName: "terminal",
      preferredRelativePaths: [".local/bin/\(executableName)"]
    )

    XCTAssertNil(
      ExecutableResolver.resolve(
        specification,
        homeDirectory: root
      ).executableURL
    )
  }
}
