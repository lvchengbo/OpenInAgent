import Foundation
import XCTest

@testable import OpenInAgent

final class LoginShellTests: XCTestCase {
  private let adversarialPayload =
    "\"'\\ $(printf injected) `printf injected` ; & | *\n—🙂 e\u{301}"

  func testRecognizesBundledShellsAndRejectsUnknownOnes() {
    XCTAssertEqual(LoginShell(shellPath: "/bin/zsh")?.dialect, .posix)
    XCTAssertEqual(LoginShell(shellPath: "/bin/bash")?.dialect, .posix)
    XCTAssertEqual(LoginShell(shellPath: "/bin/sh")?.dialect, .posix)
    XCTAssertNil(LoginShell(shellPath: "zsh"))
    XCTAssertNil(LoginShell(shellPath: "/usr/bin/true"))
    XCTAssertNil(LoginShell(shellPath: "/nonexistent/zsh"))
    XCTAssertEqual(LoginShell.dialect(forShellNamed: "fish"), .fish)
    XCTAssertNil(LoginShell.dialect(forShellNamed: "nu"))
  }

  func testCurrentShellFallsBackToZshWhenNoUsableShell() throws {
    let shell = try LoginShell.current(
      accountShell: "/nonexistent/nu",
      environment: ["SHELL": "/nonexistent/nu"]
    )
    XCTAssertEqual(shell.executableURL.path, "/bin/zsh")
    XCTAssertEqual(shell.dialect, .posix)
  }

  func testUnsupportedAccountShellIsReportedNotSilentlyReplaced() throws {
    // csh/tcsh are real login shells the wrapper cannot drive. Silently
    // switching to zsh would drop that user's environment and PATH, so the
    // resolver must report it instead.
    XCTAssertThrowsError(
      try LoginShell.current(accountShell: "/bin/tcsh", environment: [:])
    ) { error in
      guard case LoginShellError.unsupportedShell(let name) = error else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertEqual(name, "tcsh")
    }
    XCTAssertThrowsError(
      try LoginShell.current(accountShell: nil, environment: ["SHELL": "/bin/csh"])
    )

    // A supported account shell still wins even when SHELL points at csh.
    XCTAssertEqual(
      try LoginShell.current(accountShell: "/bin/zsh", environment: ["SHELL": "/bin/tcsh"])
        .dialect,
      .posix
    )
  }

  func testProgramIsConstantAndDataStaysInArgv() throws {
    let shell = try XCTUnwrap(LoginShell(shellPath: "/bin/zsh"))
    let command = ["/usr/bin/env", "-C", "/tmp/a b", "--", "PWD=/tmp/a b", "/tmp/claude"]

    XCTAssertEqual(
      shell.arguments(executing: command),
      ["/bin/zsh", "-l", "-i", "-c", "exec \"$@\"", "open-in-agent"] + command
    )
    XCTAssertFalse(shell.program.contains("/tmp"))
    XCTAssertFalse(shell.program.contains("\\("))
  }

  func testInteractiveLoginShellExecutesArgvLiterally() async throws {
    let shell = try XCTUnwrap(LoginShell(shellPath: "/bin/zsh"))
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenInAgent-home-\(UUID().uuidString)", isDirectory: true)
    let project = home.appendingPathComponent("project with spaces", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }

    // Process supplies argv[0] itself, so drop the shell path the full argv
    // carries for the real (osascript) launch path.
    let result = try await ProcessRunner.run(
      executableURL: shell.executableURL,
      arguments: Array(
        shell.arguments(
          executing: [
            "/usr/bin/env", "-C", project.path, "--", "PWD=\(project.path)",
            "/usr/bin/printf", "%s\n", adversarialPayload,
          ]
        ).dropFirst()
      ),
      environment: ["HOME": home.path, "PATH": "/usr/bin:/bin", "TERM": "dumb"],
      timeout: 10
    )

    XCTAssertEqual(result.terminationStatus, 0, result.standardError)
    XCTAssertEqual(result.standardOutput, adversarialPayload + "\n")
  }

  func testInteractiveLoginShellChangesDirectory() async throws {
    let shell = try XCTUnwrap(LoginShell(shellPath: "/bin/zsh"))
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenInAgent-home-\(UUID().uuidString)", isDirectory: true)
    let project = home.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }

    let result = try await ProcessRunner.run(
      executableURL: shell.executableURL,
      arguments: AgentCommand.arguments(
        executableURL: URL(fileURLWithPath: "/bin/pwd"),
        workingDirectory: project,
        loginShell: shell
      ).dropFirst().map { $0 },
      environment: ["HOME": home.path, "PATH": "/usr/bin:/bin", "TERM": "dumb"],
      timeout: 10
    )

    XCTAssertEqual(result.terminationStatus, 0, result.standardError)
    XCTAssertEqual(
      result.standardOutput.trimmingCharacters(in: .newlines),
      project.resolvingSymlinksInPath().path
    )
  }

  func testBashEncoderSurvivesGhosttyEvaluation() async throws {
    let values = [
      "plain", "with spaces", "it's", "double\"quote", "back\\slash",
      "$(touch nope)", "`touch nope`", "; & | * ? [ ] ~", "line1\nline2",
      "-leading-option", "组合—🙂—e\u{301}",
    ]
    let command = BashCommandEncoder.command(
      arguments: ["/usr/bin/printf", "[%s]"] + values
    )

    // Ghostty runs the surface command exactly this way on macOS.
    let result = try await ProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/bin/bash"),
      arguments: ["--noprofile", "--norc", "-c", "exec -l \(command)"],
      timeout: 5
    )

    XCTAssertEqual(result.terminationStatus, 0, result.standardError)
    XCTAssertEqual(
      result.standardOutput,
      values.map { "[\($0)]" }.joined()
    )
  }
}
