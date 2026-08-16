import Foundation
import XCTest

@testable import OpenInAgent

final class AgentLaunchRequestTests: XCTestCase {
  func testValidatesAdversarialAbsoluteFinderPath() throws {
    let path = "/tmp/project ? # % ' \" \\ $() `cmd`; &\n组合—🙂"
    let targetURL = URL(fileURLWithPath: path)

    XCTAssertEqual(
      AgentLaunchRequest.validatedTargetURL(targetURL),
      targetURL.standardizedFileURL
    )
  }

  func testRejectsNonLocalOrAmbiguousTargets() {
    let invalidValues = [
      "https://example.com/project",
      "file:relative",
      "file://server/share",
      "file:///tmp?x=y",
      "file:///tmp#fragment",
      "file://user@/tmp",
    ]

    for value in invalidValues {
      XCTAssertNil(
        AgentLaunchRequest.validatedTargetURL(URL(string: value)!),
        value
      )
    }
  }
}
