import Foundation
import XCTest

@testable import OpenInAgent

/// Regression coverage for launch/handoff paths the original suite left untested:
/// the fish login-shell dialect end to end, a tampered handoff token, a default
/// launch racing a pending activation URL, and a Finder alias to a package.
final class LaunchHardeningTests: XCTestCase {
  /// The fish dialect wraps the launch as `fish -l -i -c 'exec $argv' …`. Every
  /// argv element, including shell metacharacters, must reach the program
  /// literally and nothing may be evaluated.
  func testFishLoginShellRunsArgvLiterally() async throws {
    let fishPath = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"].first {
      FileManager.default.isExecutableFile(atPath: $0)
    }
    try XCTSkipIf(fishPath == nil, "fish is not installed")
    let shell = try XCTUnwrap(LoginShell(shellPath: fishPath!))
    XCTAssertEqual(shell.dialect, .fish)

    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenInAgent-fish-\(UUID().uuidString)", isDirectory: true)
    let project = home.appendingPathComponent("project with spaces", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }

    let payload = "$(printf injected) `printf injected` ; & | * \\ \" ' —🙂 -dash"
    let result = try await ProcessRunner.run(
      executableURL: shell.executableURL,
      arguments: Array(
        shell.arguments(
          executing: [
            "/usr/bin/env", "-C", project.path, "--", "PWD=\(project.path)",
            "/usr/bin/printf", "%s\n", payload,
          ]
        ).dropFirst()
      ),
      environment: ["HOME": home.path, "PATH": "/usr/bin:/bin", "TERM": "dumb"],
      timeout: 10
    )

    XCTAssertEqual(result.terminationStatus, 0, result.standardError)
    XCTAssertEqual(result.standardOutput, payload + "\n")
  }

  /// A record whose stored token no longer matches the activation token must be
  /// rejected even when it is otherwise well formed and correctly permissioned.
  func testHandoffRejectsInternalTokenMismatch() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenInAgent-\(UUID().uuidString)", isDirectory: true)
    let directoryURL = root.appendingPathComponent("Handoffs", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AgentHandoffStore(directoryURL: directoryURL, clock: Date.init)

    let activationURL = try store.create(
      AgentLaunchRequest(
        agentID: .claude,
        targetURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
      )
    )
    let recordURL = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil
      ).first
    )

    let tampered: [String: Any] = [
      "version": 1,
      "token": UUID().uuidString,
      "createdAt": Date().timeIntervalSince1970,
      "agent": "claude",
      "target": "file:///tmp",
    ]
    try JSONSerialization.data(withJSONObject: tampered).write(to: recordURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: recordURL.path
    )

    XCTAssertThrowsError(try store.consume(activationURL))
  }

  /// A pending activation URL that arrives before launch finishes must win even
  /// when the finish notification reports a default launch, so the handoff is
  /// honored instead of the interactive setup flow.
  func testDefaultLaunchAfterPendingURLLaunchesHandoff() {
    let activationURL = URL(string: "openinagent://launch/\(UUID().uuidString)")!
    var state = ApplicationLaunchState()

    XCTAssertNil(state.receive(urls: [activationURL]))
    XCTAssertEqual(
      state.didFinishLaunching(isDefaultLaunch: true),
      .launch(activationURL)
    )
  }

  /// A Finder alias whose target is a package resolves to the package's parent,
  /// matching the "a package uses its parent directory" rule for direct
  /// selections.
  func testAliasToPackageResolvesToParentDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenInAgent-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let package = root.appendingPathComponent("Sample.app", isDirectory: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    let alias = root.appendingPathComponent("Sample Alias")
    let bookmark = try package.bookmarkData(
      options: [.suitableForBookmarkFile],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    try URL.writeBookmarkData(bookmark, to: alias)

    XCTAssertEqual(
      FinderPathResolver.workingDirectory(for: alias),
      root.standardizedFileURL
    )
  }
}
