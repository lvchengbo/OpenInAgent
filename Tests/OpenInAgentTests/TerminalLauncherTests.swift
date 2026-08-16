import Foundation
import XCTest

@testable import OpenInAgent

final class TerminalLauncherTests: XCTestCase {
  func testGhosttyUsesDiscreteArguments() {
    let executable = URL(fileURLWithPath: "/Users/test/.local/bin/claude")
    let directory = URL(fileURLWithPath: "/tmp/project with spaces", isDirectory: true)

    XCTAssertEqual(
      TerminalLauncher.ghosttyArguments(
        executableURL: executable,
        workingDirectory: directory
      ),
      [
        "--working-directory=/tmp/project with spaces",
        "-e",
        "/usr/bin/env",
        "-C",
        "/tmp/project with spaces",
        "--",
        "PWD=/tmp/project with spaces",
        "/Users/test/.local/bin/claude",
      ]
    )
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
      executableURL: URL(fileURLWithPath: executablePath),
      workingDirectory: URL(fileURLWithPath: directoryPath, isDirectory: true)
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

  func testITermQuoteRemainsLiteralIfEvaluatedByAShell() async throws {
    let payload = "$(printf injected) `printf injected` \\ \" ' ; & |\n—🙂"
    let command = "printf '%s' \(ITermCommandEncoder.quote(payload))"

    let result = try await ProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", command],
      timeout: 2
    )

    XCTAssertEqual(result.terminationStatus, 0, result.standardError)
    XCTAssertEqual(result.standardOutput, payload)
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
          current.append(command[index])
          index = command.index(after: index)
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
