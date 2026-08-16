import Foundation
import XCTest

@testable import OpenInAgent

final class FinderSelectionTests: XCTestCase {
  func testSelectionPrecedesFrontWindowInScript() throws {
    let selection = try XCTUnwrap(
      FinderSelection.locationScript.range(of: "count of selection")
    )
    let window = try XCTUnwrap(
      FinderSelection.locationScript.range(of: "count of Finder windows")
    )

    XCTAssertLessThan(selection.lowerBound, window.lowerBound)
    XCTAssertFalse(FinderSelection.locationScript.contains("home directory"))
    XCTAssertFalse(FinderSelection.locationScript.contains("path to desktop"))
  }

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
}
