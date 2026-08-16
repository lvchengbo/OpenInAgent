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
    XCTAssertEqual(try fixture.store.consume(activationURL), request)
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
      "version": 1,
      "token": token,
      "createdAt": fixture.clock.value.timeIntervalSince1970,
      "agent": "codex",
      "target": "file:relative",
    ]
    try JSONSerialization.data(withJSONObject: record).write(
      to: relativeRecordURL
    )
    XCTAssertThrowsError(try fixture.store.consume(relativeURL))

    let unknownAgentURL = try fixture.store.create(makeRequest())
    let unknownAgentRecordURL = try XCTUnwrap(try fixture.contents().only)
    let unknownAgentRecord: [String: Any] = [
      "version": 1,
      "token": unknownAgentURL.lastPathComponent,
      "createdAt": fixture.clock.value.timeIntervalSince1970,
      "agent": "unknown",
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

  private func makeRequest() -> AgentLaunchRequest {
    AgentLaunchRequest(
      agentID: .claude,
      targetURL: URL(
        fileURLWithPath: "/tmp/OpenInAgentHandoffTests",
        isDirectory: true
      )
    )
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
