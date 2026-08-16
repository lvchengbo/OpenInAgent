import Foundation
import XCTest

@testable import OpenInAgent

final class ProcessRunnerTests: XCTestCase {
  func testCapturesOutput() async throws {
    let result = try await ProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
      arguments: ["safe-output"],
      timeout: 2
    )

    XCTAssertEqual(result.terminationStatus, 0)
    XCTAssertEqual(result.standardOutput, "safe-output")
    XCTAssertEqual(result.standardError, "")
    XCTAssertFalse(result.timedOut)
  }

  func testTerminatesTimedOutProcess() async throws {
    let result = try await ProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/bin/sleep"),
      arguments: ["2"],
      timeout: 0.05
    )

    XCTAssertTrue(result.timedOut)
    XCTAssertNotEqual(result.terminationStatus, 0)
  }

  func testDrainsStandardErrorWithoutDeadlocking() async throws {
    let result = try await ProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: [
        "-c",
        "/bin/dd if=/dev/zero bs=65536 count=16 1>&2; /usr/bin/printf done",
      ],
      timeout: 2
    )

    XCTAssertFalse(result.timedOut)
    XCTAssertEqual(result.terminationStatus, 0)
    XCTAssertEqual(result.standardOutput, "done")
    XCTAssertGreaterThan(result.standardError.utf8.count, 1_000_000)
  }

  func testForceKillsProcessThatIgnoresTermination() async throws {
    let startedAt = Date()
    let result = try await ProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "trap '' TERM; while :; do :; done"],
      timeout: 0.05
    )

    XCTAssertTrue(result.timedOut)
    XCTAssertNotEqual(result.terminationStatus, 0)
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
  }
}
