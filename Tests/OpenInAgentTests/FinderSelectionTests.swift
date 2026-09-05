import Foundation
import XCTest

@testable import OpenInAgent

final class FinderSelectionTests: XCTestCase {
  func testLaunchArgumentAcceptsExistingFile() throws {
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenInAgent-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data().write(to: file)

    XCTAssertEqual(
      FinderSelection.urlFromLaunchArguments(["Open in Agent", file.path]),
      file
    )
  }

  func testLaunchArgumentIgnoresProcessSerialNumberAndFlags() {
    XCTAssertNil(
      FinderSelection.urlFromLaunchArguments([
        "Open in Agent",
        "-psn_0_12345",
        "--not-a-path",
      ])
    )
  }

  func testLaunchArgumentRejectsFileURLWithAuthority() throws {
    // A `file://host/tmp` argument must not be accepted: its authority would
    // otherwise be dropped and reinterpreted as the local path /tmp.
    XCTAssertNil(
      FinderSelection.urlFromLaunchArguments([
        "Open in Agent",
        "file://server/tmp",
      ])
    )
  }
}
