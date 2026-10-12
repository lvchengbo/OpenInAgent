import Darwin
import Foundation
import XCTest

@testable import OpenInAgent

final class AgentHandoffStoreTests: XCTestCase {
  func testRoundTripUsesOpaqueSingleUseToken() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let path = "/tmp/project ? # % ' \" \\ $() `cmd`; &\n组合—🙂"
    let request = AgentLaunchRequest(
      agentID: .codex,
      targetURL: URL(fileURLWithPath: path)
    )

    let activationURL = try fixture.store.create(request)

    XCTAssertEqual(activationURL.scheme, "openinagent")
    XCTAssertEqual(activationURL.host, "launch")
    XCTAssertNil(activationURL.query)
    XCTAssertFalse(activationURL.absoluteString.contains("codex"))
    XCTAssertFalse(activationURL.absoluteString.contains("project"))
    XCTAssertEqual(
      try fixture.store.consume(activationURL),
      .openAgent(request.agentID, targetURL: request.targetURL)
    )
    XCTAssertThrowsError(try fixture.store.consume(activationURL))
    XCTAssertEqual(try fixture.contents(), [])
  }

  func testRecordAndDirectoryUseOwnerOnlyPermissions() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let activationURL = try fixture.store.create(makeRequest())
    let recordURL = try XCTUnwrap(try fixture.contents().only)

    XCTAssertEqual(try permissions(of: fixture.directoryURL), 0o700)
    XCTAssertEqual(try permissions(of: recordURL), 0o600)
    _ = try fixture.store.consume(activationURL)
  }

  func testSymlinkDirectoryIsRejectedWithoutChangingItsTarget() throws {
    for request in [
      FinderToolbarRequest.openAgent(.codex), .copyPath, .openConfigFile,
      .setMode(.safe), .setMode(.yolo),
    ] {
      let fixture = try makeFixture()
      defer { fixture.remove() }
      let outsideURL = fixture.rootURL.appendingPathComponent("unrelated", isDirectory: true)
      try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: outsideURL.path
      )
      let preservedURL = outsideURL.appendingPathComponent("keep.txt")
      let preservedData = Data("unrelated directory content".utf8)
      try preservedData.write(to: preservedURL)
      try FileManager.default.createSymbolicLink(
        at: fixture.directoryURL,
        withDestinationURL: outsideURL
      )
      let store = AgentHandoffStore(
        directoryURL: fixture.directoryURL,
        endpoint: request.endpoint
      )

      XCTAssertThrowsError(try store.create(request)) { error in
        guard let storeError = error as? AgentHandoffStoreError,
          case .unavailableStore = storeError
        else {
          return XCTFail("Expected unavailableStore, received \(error)")
        }
      }
      XCTAssertEqual(try permissions(of: outsideURL), 0o755)
      XCTAssertEqual(try Data(contentsOf: preservedURL), preservedData)
      XCTAssertEqual(
        try FileManager.default.contentsOfDirectory(atPath: outsideURL.path),
        ["keep.txt"]
      )
      XCTAssertEqual(
        try FileManager.default.destinationOfSymbolicLink(atPath: fixture.directoryURL.path),
        outsideURL.path
      )
    }
  }

  func testOwnedUnreadableDirectoryIsRepairedAndSupportsRoundTrip() throws {
    for request in [
      FinderToolbarRequest.openAgent(.codex), .copyPath, .openConfigFile,
      .setMode(.safe), .setMode(.yolo),
    ] {
      let fixture = try makeFixture()
      defer { fixture.remove() }
      try FileManager.default.createDirectory(
        at: fixture.directoryURL,
        withIntermediateDirectories: true
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o000],
        ofItemAtPath: fixture.directoryURL.path
      )
      defer { Darwin.chmod(fixture.directoryURL.path, 0o700) }
      XCTAssertEqual(try permissions(of: fixture.directoryURL), 0o000)
      let store = AgentHandoffStore(
        directoryURL: fixture.directoryURL,
        endpoint: request.endpoint
      )

      let activationURL = try store.create(request)

      XCTAssertEqual(try permissions(of: fixture.directoryURL), 0o700)
      XCTAssertEqual(try store.consume(activationURL), request)
      XCTAssertThrowsError(try store.consume(activationURL))
      XCTAssertEqual(try fixture.contents(), [])
    }
  }

  func testExpiredAndFutureRecordsAreRejectedAndDeleted() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }

    let expiredURL = try fixture.store.create(makeRequest())
    fixture.clock.value = fixture.clock.value.addingTimeInterval(61)
    XCTAssertThrowsError(try fixture.store.consume(expiredURL))
    XCTAssertEqual(try fixture.contents(), [])

    fixture.clock.value = fixture.clock.value.addingTimeInterval(10)
    let futureURL = try fixture.store.create(makeRequest())
    fixture.clock.value = fixture.clock.value.addingTimeInterval(-6)
    XCTAssertThrowsError(try fixture.store.consume(futureURL))
    XCTAssertEqual(try fixture.contents(), [])
  }

  func testMalformedActivationURLsAreRejected() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let token = UUID().uuidString
    let malformed = [
      "https://launch/\(token)",
      "openinagent://other/\(token)",
      "openinagent://launch/\(token)?agent=codex",
      "openinagent://launch/\(token)#fragment",
      "openinagent://user@launch/\(token)",
      "openinagent://launch/\(token)/extra",
      "openinagent://launch/\(token.lowercased())",
      "openinagent://launch/not-a-uuid",
    ]

    for value in malformed {
      XCTAssertThrowsError(
        try fixture.store.consume(try XCTUnwrap(URL(string: value))),
        value
      )
    }
  }

  func testSymlinkAndLoosePermissionRecordsAreRejected() throws {
    let symlinkFixture = try makeFixture()
    defer { symlinkFixture.remove() }
    let symlinkURL = try symlinkFixture.store.create(makeRequest())
    let recordURL = try XCTUnwrap(try symlinkFixture.contents().only)
    let externalURL = symlinkFixture.directoryURL
      .deletingLastPathComponent()
      .appendingPathComponent("outside-record")
    try Data("{}".utf8).write(to: externalURL)
    try FileManager.default.removeItem(at: recordURL)
    try FileManager.default.createSymbolicLink(
      at: recordURL,
      withDestinationURL: externalURL
    )

    XCTAssertThrowsError(try symlinkFixture.store.consume(symlinkURL))
    XCTAssertTrue(FileManager.default.fileExists(atPath: externalURL.path))
    XCTAssertEqual(try symlinkFixture.contents(), [])

    let permissionsFixture = try makeFixture()
    defer { permissionsFixture.remove() }
    let permissionsURL = try permissionsFixture.store.create(makeRequest())
    let looseRecordURL = try XCTUnwrap(try permissionsFixture.contents().only)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: looseRecordURL.path
    )

    XCTAssertThrowsError(
      try permissionsFixture.store.consume(permissionsURL)
    )
    XCTAssertEqual(try permissionsFixture.contents(), [])
  }

  func testFIFOAgentRecordIsRejectedWithoutBlockingAndDeleted() throws {
    try assertFIFORecordIsRejectedWithoutBlocking(.openAgent(.codex))
  }

  func testFIFOCopyPathRecordIsRejectedWithoutBlockingAndDeleted() throws {
    try assertFIFORecordIsRejectedWithoutBlocking(.copyPath)
  }

  func testFIFOOpenConfigFileRecordIsRejectedWithoutBlockingAndDeleted() throws {
    try assertFIFORecordIsRejectedWithoutBlocking(.openConfigFile)
  }

  func testFIFOModeChangeRecordIsRejectedWithoutBlockingAndDeleted() throws {
    try assertFIFORecordIsRejectedWithoutBlocking(.setMode(.safe))
  }

  func testMalformedOversizedAndRelativeTargetRecordsAreRejected() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }

    let malformedURL = try fixture.store.create(makeRequest())
    let malformedRecordURL = try XCTUnwrap(try fixture.contents().only)
    try Data("not-json".utf8).write(to: malformedRecordURL)
    XCTAssertThrowsError(try fixture.store.consume(malformedURL))

    let oversizedURL = try fixture.store.create(makeRequest())
    let oversizedRecordURL = try XCTUnwrap(try fixture.contents().only)
    try Data(repeating: 0x41, count: 16 * 1024 + 1).write(
      to: oversizedRecordURL
    )
    XCTAssertThrowsError(try fixture.store.consume(oversizedURL))

    let relativeURL = try fixture.store.create(makeRequest())
    let relativeRecordURL = try XCTUnwrap(try fixture.contents().only)
    let token = relativeURL.lastPathComponent
    let record: [String: Any] = [
      "version": 2,
      "token": token,
      "createdAt": fixture.clock.value.timeIntervalSince1970,
      "agent": "codex",
      "action": "openAgent",
      "target": "file:relative",
    ]
    try JSONSerialization.data(withJSONObject: record).write(
      to: relativeRecordURL
    )
    XCTAssertThrowsError(try fixture.store.consume(relativeURL))

    let unknownAgentURL = try fixture.store.create(makeRequest())
    let unknownAgentRecordURL = try XCTUnwrap(try fixture.contents().only)
    let unknownAgentRecord: [String: Any] = [
      "version": 2,
      "token": unknownAgentURL.lastPathComponent,
      "createdAt": fixture.clock.value.timeIntervalSince1970,
      "agent": "unknown",
      "action": "openAgent",
      "target": "file:///tmp/project",
    ]
    try JSONSerialization.data(withJSONObject: unknownAgentRecord).write(
      to: unknownAgentRecordURL
    )
    XCTAssertThrowsError(try fixture.store.consume(unknownAgentURL))

    XCTAssertThrowsError(
      try fixture.store.create(
        AgentLaunchRequest(
          agentID: .codex,
          targetURL: URL(string: "file:relative")!
        )
      )
    )
    XCTAssertEqual(try fixture.contents(), [])
  }

  func testGlobalAgentRequestDefersFinderSelectionAndRemainsSingleUse() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let url = try fixture.store.create(.openAgent(.codex))

    XCTAssertEqual(try fixture.store.consume(url), .openAgent(.codex))
    XCTAssertThrowsError(try fixture.store.consume(url))
    XCTAssertEqual(try fixture.contents(), [])
  }

  func testNULTargetIsRejectedAtCreateAndConsume() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let activationURL = try fixture.store.create(makeRequest())
    let recordURL = try XCTUnwrap(try fixture.contents().only)
    let target = "file:///tmp/project%00suffix"
    let record: [String: Any] = [
      "version": 2,
      "token": activationURL.lastPathComponent,
      "createdAt": fixture.clock.value.timeIntervalSince1970,
      "action": "openAgent",
      "agent": "codex",
      "target": target,
    ]
    try JSONSerialization.data(withJSONObject: record).write(to: recordURL)
    XCTAssertThrowsError(try fixture.store.consume(activationURL))
    XCTAssertThrowsError(
      try fixture.store.create(.openAgent(.codex, targetURL: URL(string: target)!))
    )
    XCTAssertThrowsError(
      try fixture.store.create(AgentLaunchRequest(agentID: .codex, targetURL: URL(string: target)!))
    )
    XCTAssertEqual(try fixture.contents(), [])
  }

  func testOpenConfigFileRequestDefersFinderSelectionAndRemainsSingleUse() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let url = try fixture.store.create(.openConfigFile)

    XCTAssertEqual(url.host, "launch")
    XCTAssertEqual(try fixture.store.consume(url), .openConfigFile)
    XCTAssertThrowsError(try fixture.store.consume(url))
    XCTAssertEqual(try fixture.contents(), [])
  }

  func testModeChangesRoundTripWithoutTargetAndRemainSingleUse() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let copyStore = AgentHandoffStore(directoryURL: fixture.directoryURL, endpoint: .copyPath)
    for mode in AgentLaunchMode.allCases {
      let url = try fixture.store.create(.setMode(mode))
      XCTAssertEqual(url.host, "launch")
      XCTAssertNil(url.query)
      XCTAssertFalse(url.absoluteString.contains(mode.rawValue))
      XCTAssertEqual(try fixture.store.consume(url), .setMode(mode))
      XCTAssertThrowsError(try fixture.store.consume(url))
      XCTAssertThrowsError(try copyStore.create(.setMode(mode)))
      XCTAssertEqual(try fixture.contents(), [])
    }
  }

  func testInvalidModeChangeFieldsAndModesAreRejected() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let invalidFields: [[String: Any]] = [
      ["mode": ""], ["mode": "YOLO"], ["mode": "unknown"], ["mode": NSNull()],
      ["agent": "codex"], ["target": "file:///tmp"], ["version": 1],
      ["action": "openAgent", "agent": "codex"], ["action": "openConfigFile"],
    ]
    for fields in invalidFields {
      let url = try fixture.store.create(.setMode(.safe))
      let recordURL = try XCTUnwrap(try fixture.contents().only)
      var record: [String: Any] = [
        "version": 2, "token": url.lastPathComponent,
        "createdAt": fixture.clock.value.timeIntervalSince1970,
        "action": "setMode", "mode": "safe",
      ]
      record.merge(fields) { _, replacement in replacement }
      try JSONSerialization.data(withJSONObject: record).write(to: recordURL)
      XCTAssertThrowsError(try fixture.store.consume(url), "\(fields)")
      XCTAssertEqual(try fixture.contents(), [])
    }
  }

  func testTamperedOpenConfigFileFieldsAreRejected() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let invalidFields: [[String: Any]] = [
      ["action": "openConfigFile", "agent": "codex"],
      ["action": "openConfigFile", "target": "file:///tmp"],
      ["action": "openConfigFile", "version": 1],
    ]

    for fields in invalidFields {
      let url = try fixture.store.create(.openConfigFile)
      let recordURL = try XCTUnwrap(try fixture.contents().only)
      var record: [String: Any] = [
        "version": 2,
        "token": url.lastPathComponent,
        "createdAt": fixture.clock.value.timeIntervalSince1970,
      ]
      record.merge(fields) { _, replacement in replacement }
      try JSONSerialization.data(withJSONObject: record).write(to: recordURL)
      XCTAssertThrowsError(try fixture.store.consume(url), "\(fields)")
      XCTAssertEqual(try fixture.contents(), [])
    }
  }

  func testCopyPathUsesItsOwnContainerEndpointAndCannotLaunchAnAgent() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let copyStore = AgentHandoffStore(directoryURL: fixture.directoryURL, endpoint: .copyPath)
    let url = try copyStore.create(.copyPath)

    XCTAssertEqual(url.host, "copy-path")
    // The host must select the fixed Copy Path container before consuming it.
    XCTAssertThrowsError(try fixture.store.consume(url))
    XCTAssertEqual(try copyStore.consume(url), .copyPath)
    XCTAssertThrowsError(try copyStore.consume(url))
    XCTAssertThrowsError(try copyStore.create(.openAgent(.codex)))
    XCTAssertThrowsError(try fixture.store.create(.copyPath))
    XCTAssertEqual(try fixture.contents(), [])
  }

  func testTamperedActionAndUnexpectedCopyPathFieldsAreRejected() throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let copyStore = AgentHandoffStore(directoryURL: fixture.directoryURL, endpoint: .copyPath)
    let invalidFields: [[String: Any]] = [
      ["action": "openAgent", "agent": "codex"],
      ["action": "copyPath", "agent": "codex"],
      ["action": "copyPath", "target": "file:///tmp"],
      ["action": "unknown"],
      ["action": "copyPath", "version": 1],
    ]

    for fields in invalidFields {
      let url = try copyStore.create(.copyPath)
      let recordURL = try XCTUnwrap(try fixture.contents().only)
      var record: [String: Any] = [
        "version": 2,
        "token": url.lastPathComponent,
        "createdAt": fixture.clock.value.timeIntervalSince1970,
      ]
      record.merge(fields) { _, replacement in replacement }
      try JSONSerialization.data(withJSONObject: record).write(to: recordURL)
      XCTAssertThrowsError(try copyStore.consume(url), "\(fields)")
      XCTAssertEqual(try fixture.contents(), [])
    }
  }

  private func makeRequest() -> AgentLaunchRequest {
    AgentLaunchRequest(
      agentID: .claude,
      targetURL: URL(
        fileURLWithPath: "/tmp/OpenInAgentHandoffTests",
        isDirectory: true
      )
    )
  }

  private func assertFIFORecordIsRejectedWithoutBlocking(
    _ request: FinderToolbarRequest,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let fixture = try makeFixture()
    defer { fixture.remove() }
    let store = AgentHandoffStore(
      directoryURL: fixture.directoryURL,
      endpoint: request.endpoint
    )
    let activationURL = try store.create(request)
    let recordURL = try XCTUnwrap(try fixture.contents().only)
    try FileManager.default.removeItem(at: recordURL)
    guard Darwin.mkfifo(recordURL.path, 0o600) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    // Keep the watchdog's path outside the store so claiming and deleting the
    // request cannot remove it. A delayed writer releases a regressed blocking
    // open, letting the timing assertion fail instead of hanging the suite.
    let guardURL = fixture.rootURL.appendingPathComponent("fifo-guard")
    guard Darwin.link(recordURL.path, guardURL.path) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let guardPath = guardURL.path
    let completed = DispatchSemaphore(value: 0)
    let watchdogCompleted = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      defer { watchdogCompleted.signal() }
      guard completed.wait(timeout: .now() + 1) == .timedOut else { return }
      let descriptor = Darwin.open(guardPath, O_RDWR | O_NONBLOCK | O_CLOEXEC)
      guard descriptor >= 0 else { return }
      defer { Darwin.close(descriptor) }
      _ = completed.wait(timeout: .now() + 5)
    }
    defer {
      completed.signal()
      watchdogCompleted.wait()
    }

    let startedAt = ProcessInfo.processInfo.systemUptime
    XCTAssertThrowsError(try store.consume(activationURL), file: file, line: line) { error in
      guard let storeError = error as? AgentHandoffStoreError,
        case .invalidRequest = storeError
      else {
        return XCTFail("Expected invalidRequest, received \(error)", file: file, line: line)
      }
    }
    XCTAssertLessThan(
      ProcessInfo.processInfo.systemUptime - startedAt,
      0.5,
      "Rejecting a FIFO must not wait for a writer",
      file: file,
      line: line
    )
    XCTAssertEqual(try fixture.contents(), [], file: file, line: line)
    XCTAssertThrowsError(try store.consume(activationURL), file: file, line: line)
  }

  private func makeFixture() throws -> Fixture {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let directoryURL = rootURL.appendingPathComponent(
      "Handoffs",
      isDirectory: true
    )
    let clock = MutableClock(value: Date())
    return Fixture(
      rootURL: rootURL,
      directoryURL: directoryURL,
      clock: clock,
      store: AgentHandoffStore(
        directoryURL: directoryURL,
        clock: { clock.value }
      )
    )
  }

  private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(
      atPath: url.path
    )
    return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
  }
}

private final class MutableClock {
  var value: Date

  init(value: Date) {
    self.value = value
  }
}

private struct Fixture {
  let rootURL: URL
  let directoryURL: URL
  let clock: MutableClock
  let store: AgentHandoffStore

  func contents() throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directoryURL.path) else {
      return []
    }
    return try FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil
    ).sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

extension Array {
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}
