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

  func testStartupDeadlineRejectsNonDefaultLaunchThatNeverGetsAURL() {
    // Printing, state restoration, or a URL that never arrives: without a
    // deadline the windowless accessory app would run forever.
    var state = ApplicationLaunchState()

    XCTAssertNil(state.didFinishLaunching(isDefaultLaunch: false))
    XCTAssertEqual(state.startupDeadlineExpired(), .rejectInvalidRequest)
    XCTAssertNil(state.startupDeadlineExpired())
    XCTAssertNil(state.receive(urls: [makeActivationURL()]))
  }

  func testStartupDeadlineDoesNothingOnceADecisionWasMade() {
    let activationURL = makeActivationURL()

    var handoff = ApplicationLaunchState()
    XCTAssertNil(handoff.didFinishLaunching(isDefaultLaunch: false))
    XCTAssertEqual(handoff.receive(urls: [activationURL]), .launch(activationURL))
    XCTAssertNil(handoff.startupDeadlineExpired())

    var interactive = ApplicationLaunchState()
    XCTAssertEqual(interactive.didFinishLaunching(isDefaultLaunch: true), .launch(nil))
    XCTAssertNil(interactive.startupDeadlineExpired())

    var notLaunchedYet = ApplicationLaunchState()
    XCTAssertNil(notLaunchedYet.startupDeadlineExpired())
    XCTAssertEqual(notLaunchedYet.didFinishLaunching(isDefaultLaunch: true), .launch(nil))
  }

  private func makeActivationURL() -> URL {
    URL(string: "openinagent://launch/\(UUID().uuidString)")!
  }
}
