import Foundation
import XCTest

@testable import OpenInAgent

final class TerminalLauncherTests: XCTestCase {
  func testLaunchArgumentsWrapEnvInLoginShell() throws {
    let executable = URL(fileURLWithPath: "/Users/test/.local/bin/claude")
    let directory = URL(fileURLWithPath: "/tmp/project with spaces", isDirectory: true)
    let shell = try XCTUnwrap(LoginShell(shellPath: "/bin/zsh"))

    XCTAssertEqual(
      AgentCommand.arguments(
        executableURL: executable,
        workingDirectory: directory,
        loginShell: shell
      ),
      [
        "/bin/zsh",
        "-l",
        "-i",
        "-c",
        "exec \"$@\"",
        "open-in-agent",
        "/usr/bin/env",
        "-C",
        "/tmp/project with spaces",
        "--",
        "PWD=/tmp/project with spaces",
        "/Users/test/.local/bin/claude",
      ]
    )
  }

  func testGhosttyScriptTakesOnlyDirectoryAndCommandArguments() {
    XCTAssertTrue(TerminalLauncher.ghosttyLaunchScript.contains("item 1 of argv"))
    XCTAssertTrue(TerminalLauncher.ghosttyLaunchScript.contains("item 2 of argv"))
    XCTAssertTrue(TerminalLauncher.ghosttyLaunchScript.contains("new window with configuration"))
    XCTAssertFalse(TerminalLauncher.ghosttyLaunchScript.contains("initial input"))
    XCTAssertFalse(TerminalLauncher.ghosttyLaunchScript.contains("$("))
  }

  func testITermEncoderRoundTripsAdversarialArguments() throws {
    let values = [
      "plain",
      "with spaces",
      "single'quote",
      "double\"quote",
      "back\\slash",
      "$(touch nope)",
      "`touch nope`",
      "; & | * ? [ ]",
      "line1\nline2\rline3",
      "-leading-option",
      "组合—🙂—e\u{301}",
    ]

    for value in values {
      XCTAssertEqual(try decodeSingle(ITermCommandEncoder.quote(value)), value)
    }
  }

  func testITermCommandContainsOnlyExpectedArgv() throws {
    let directoryPath = "/tmp/a ' \" \\ $(touch nope) `touch nope`; &\n—"
    let executablePath = "/Users/test/.local/bin/codex"
    let command = ITermCommandEncoder.command(
      arguments: AgentCommand.environmentArguments(
        executableURL: URL(fileURLWithPath: executablePath),
        workingDirectory: URL(fileURLWithPath: directoryPath, isDirectory: true)
      )
    )

    XCTAssertEqual(
      try decodeCommand(command),
      [
        "/usr/bin/env",
        "-C",
        directoryPath,
        "--",
        "PWD=\(directoryPath)",
        executablePath,
      ]
    )
  }

  func testITermAppleScriptContainsNoLaunchDataInterpolation() {
    XCTAssertTrue(TerminalLauncher.iTermLaunchScript.contains("item 1 of argv"))
    XCTAssertFalse(TerminalLauncher.iTermLaunchScript.contains("$("))
    XCTAssertFalse(TerminalLauncher.iTermLaunchScript.contains("do script"))
    XCTAssertFalse(TerminalLauncher.iTermLaunchScript.contains("write text"))
  }

  func testITermEncoderDoesNotBackslashEscapeDollarOrBacktick() {
    // iTerm tokenizes and execs directly; it never expands, so $ and ` are
    // ordinary literals. Escaping them would inject a stray backslash into the
    // delivered argument.
    XCTAssertEqual(ITermCommandEncoder.quote("$@"), "\"$@\"")
    XCTAssertEqual(ITermCommandEncoder.quote("`cmd`"), "\"`cmd`\"")
    XCTAssertEqual(ITermCommandEncoder.quote("a\"b\\c"), "\"a\\\"b\\\\c\"")
  }

  func testITermCommandPreservesLoginShellProgram() throws {
    // Regression: the login shell's constant `exec "$@"` program must survive
    // iTerm's tokenizer intact. When $ was escaped it arrived as `exec "\$@"`,
    // so zsh treated $@ as a literal string, exec failed, and every iTerm
    // session exited immediately.
    let shell = try XCTUnwrap(LoginShell(shellPath: "/bin/zsh"))
    let argv = AgentCommand.arguments(
      executableURL: URL(fileURLWithPath: "/Users/test/.local/bin/codex"),
      workingDirectory: URL(fileURLWithPath: "/tmp/project $x `y`", isDirectory: true),
      loginShell: shell
    )

    XCTAssertEqual(
      try decodeCommand(ITermCommandEncoder.command(arguments: argv)),
      argv
    )
    XCTAssertTrue(argv.contains("exec \"$@\""))
  }

  func testOSAScriptTransportsCommandAsOneOpaqueArgument() async throws {
    let payload = "\"'\\ $(touch nope) `touch nope`; &\n—🙂"
    let echoArgumentScript = """
      on run argv
          if (count of argv) is not 1 then error "wrong argument count"
          return item 1 of argv
      end run
      """

    let result = try await ProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
      arguments: ["-e", echoArgumentScript, "--", payload],
      timeout: 2
    )

    XCTAssertEqual(result.terminationStatus, 0, result.standardError)
    XCTAssertEqual(
      result.standardOutput.trimmingCharacters(in: .newlines),
      payload
    )
  }

  func testWorkingDirectoryMustExistAndBeSearchable() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenInAgent-\(UUID().uuidString)", isDirectory: true)
    let locked = root.appendingPathComponent("locked", isDirectory: true)
    let file = root.appendingPathComponent("file.txt")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    try Data().write(to: file)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
      try? FileManager.default.removeItem(at: root)
    }

    XCTAssertTrue(TerminalLauncher.isUsableWorkingDirectory(root))
    XCTAssertFalse(TerminalLauncher.isUsableWorkingDirectory(file))
    XCTAssertFalse(
      TerminalLauncher.isUsableWorkingDirectory(root.appendingPathComponent("missing"))
    )

    // A directory that exists but cannot be entered: `env -C` would fail inside
    // the terminal after the launch had already been reported as a success.
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    XCTAssertFalse(TerminalLauncher.isUsableWorkingDirectory(locked))
  }

  func testVersionComparisonIsNumericPerComponent() {
    XCTAssertTrue(TerminalLauncher.isVersion("1.3.0", atLeast: "1.3.0"))
    XCTAssertTrue(TerminalLauncher.isVersion("1.3.1", atLeast: "1.3.0"))
    XCTAssertTrue(TerminalLauncher.isVersion("1.10.0", atLeast: "1.3.0"))
    XCTAssertTrue(TerminalLauncher.isVersion("2.0", atLeast: "1.3.0"))
    XCTAssertFalse(TerminalLauncher.isVersion("1.2.3", atLeast: "1.3.0"))
    XCTAssertFalse(TerminalLauncher.isVersion("1.2", atLeast: "1.3.0"))
    XCTAssertEqual(TerminalKind.ghostty.minimumVersion, "1.3.0")
    XCTAssertNil(TerminalKind.iTerm.minimumVersion)
  }

  func testLaunchErrorClassifiesAppleEventErrorNumbers() {
    func classify(_ standardError: String) -> TerminalLauncherError {
      TerminalLauncher.launchError(
        standardError: standardError,
        terminationStatus: 1,
        terminal: .iTerm
      )
    }

    guard
      case .automationDenied("iTerm") = classify(
        "execution error: Not authorized to send Apple events to iTerm. (-1743)\n"
      )
    else { return XCTFail("-1743 should be an Automation denial") }

    guard
      case .timedOut("iTerm") = classify(
        "execution error: iTerm got an error: AppleEvent timed out. (-1712)\n"
      )
    else { return XCTFail("-1712 should be a timeout") }

    guard case .launchFailed(let detail) = classify("  some other failure (-2700)\n") else {
      return XCTFail("unknown errors should be generic launch failures")
    }
    XCTAssertEqual(detail, "some other failure (-2700)")

    guard case .launchFailed(let fallback) = classify("") else {
      return XCTFail("empty output should be a generic launch failure")
    }
    XCTAssertEqual(fallback, "iTerm automation exited with status 1.")
  }

  private func decodeSingle(_ encoded: String) throws -> String {
    let values = try decodeCommand(encoded)
    return try XCTUnwrap(values.only)
  }

  private func decodeCommand(_ command: String) throws -> [String] {
    var values: [String] = []
    var current = ""
    var index = command.startIndex

    while index < command.endIndex {
      guard command[index] == "\"" else {
        throw DecodeError.expectedQuote
      }
      index = command.index(after: index)

      var closed = false
      while index < command.endIndex {
        let character = command[index]
        index = command.index(after: index)

        if character == "\\" {
          guard index < command.endIndex else {
            throw DecodeError.danglingEscape
          }
          let next = command[index]
          if next == "\"" || next == "\\" {
            current.append(next)
            index = command.index(after: index)
          } else {
            // iTerm's tokenizer keeps a backslash that precedes any other
            // character (only " and \ are escapes inside double quotes), so
            // $ and ` must never be backslash-escaped by the encoder.
            current.append("\\")
          }
        } else if character == "\"" {
          closed = true
          break
        } else {
          current.append(character)
        }
      }

      guard closed else { throw DecodeError.unclosedQuote }
      values.append(current)
      current = ""

      if index < command.endIndex {
        guard command[index] == " " else {
          throw DecodeError.expectedSeparator
        }
        index = command.index(after: index)
      }
    }

    return values
  }
}

private enum DecodeError: Error {
  case expectedQuote
  case danglingEscape
  case unclosedQuote
  case expectedSeparator
}

extension Array {
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}
