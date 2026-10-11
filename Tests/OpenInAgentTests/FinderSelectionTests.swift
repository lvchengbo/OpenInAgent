import Foundation
import XCTest

@testable import OpenInAgent

final class FinderSelectionTests: XCTestCase {
  func testFinderPathPreservesLiteralCharactersAndTrailingWhitespace() throws {
    let paths = [
      "/Volumes/SAMSUNG T7 Shield 4TB",
      "/Volumes/DeepL",
      "/tmp/ project ' \" \\ $() `cmd`; & # ? % 组合—🙂 \n\n",
      "/",
    ]
    for path in paths {
      XCTAssertEqual(
        FinderSelection.urlFromFinderPath(path)?.path,
        path
      )
    }
  }

  func testFinderPathRejectsMissingRelativeAndInvalidPaths() {
    for path in ["", "relative", "file://server/share", "/tmp/invalid\0name"] {
      XCTAssertNil(FinderSelection.urlFromFinderPath(path), path)
    }
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
