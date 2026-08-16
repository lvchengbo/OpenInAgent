import Foundation
import XCTest

@testable import OpenInAgent

final class ApplicationLaunchStateTests: XCTestCase {
  func testURLBeforeFinishLaunchesExactlyOnce() throws {
    let activationURL = makeActivationURL()
    var state = ApplicationLaunchState()

    XCTAssertNil(state.receive(urls: [activationURL]))
    XCTAssertEqual(
      state.didFinishLaunching(isDefaultLaunch: false),
      .launch(activationURL)
    )
    XCTAssertNil(state.didFinishLaunching(isDefaultLaunch: false))
    XCTAssertNil(state.receive(urls: [activationURL]))
  }

  func testURLAfterFinishLaunchesExactlyOnce() throws {
    let activationURL = makeActivationURL()
    var state = ApplicationLaunchState()

    XCTAssertNil(state.didFinishLaunching(isDefaultLaunch: false))
    XCTAssertEqual(
      state.receive(urls: [activationURL]),
      .launch(activationURL)
    )
    XCTAssertNil(state.receive(urls: [activationURL]))
  }

  func testDefaultLaunchChoosesInteractiveFlow() {
    var state = ApplicationLaunchState()

    XCTAssertEqual(
      state.didFinishLaunching(isDefaultLaunch: true),
      .launch(nil)
    )
  }

  func testEmptyAndMultipleURLsAreRejected() throws {
    let validURL = makeActivationURL()

    var emptyState = ApplicationLaunchState()
    XCTAssertNil(emptyState.receive(urls: []))
    XCTAssertEqual(
      emptyState.didFinishLaunching(isDefaultLaunch: false),
      .rejectInvalidRequest
    )

    var multipleState = ApplicationLaunchState()
    XCTAssertNil(
      multipleState.receive(urls: [validURL, validURL])
    )
    XCTAssertEqual(
      multipleState.didFinishLaunching(isDefaultLaunch: false),
      .rejectInvalidRequest
    )
  }

  func testCompetingRequestsBeforeFinishAreRejected() throws {
    let firstURL = makeActivationURL()
    let secondURL = makeActivationURL()
    var state = ApplicationLaunchState()

    XCTAssertNil(state.receive(urls: [firstURL]))
    XCTAssertNil(state.receive(urls: [secondURL]))
    XCTAssertEqual(
      state.didFinishLaunching(isDefaultLaunch: false),
      .rejectInvalidRequest
    )
  }

  private func makeActivationURL() -> URL {
    URL(string: "openinagent://launch/\(UUID().uuidString)")!
  }
}
