import Foundation
import XCTest

@testable import OpenInAgent

final class DiagnosticsTests: XCTestCase {
  func testDiagnoseArgumentMustBeExplicit() {
    XCTAssertTrue(
      Diagnostics.isRequested(arguments: ["Open in Agent", "--diagnose"])
    )
    XCTAssertFalse(
      Diagnostics.isRequested(arguments: ["Open in Agent", "/tmp/project"])
    )
  }

  func testReportShowsResolvedRoutesAndReadyStatus() throws {
    let command = URL(fileURLWithPath: "/tmp/bin/claude")
    let terminal = URL(fileURLWithPath: "/Applications/Ghostty.app")
    let specification = try XCTUnwrap(
      AgentCatalog.all.first { $0.id == .claude }
    )
    let entry = DiagnosticEntry(
      agent: ResolvedAgent(
        specification: specification,
        executableURL: command
      ),
      terminalURL: terminal
    )

    XCTAssertEqual(
      Diagnostics.report(entries: [entry]),
      """
      OpenInAgent diagnostics
      Claude: command=/tmp/bin/claude | terminal=Ghostty (/Applications/Ghostty.app)
      Status: ready
      """
    )
  }

  func testReportFailsClosedWhenSoftwareIsMissing() throws {
    let specification = try XCTUnwrap(
      AgentCatalog.all.first { $0.id == .agy }
    )
    let entry = DiagnosticEntry(
      agent: ResolvedAgent(
        specification: specification,
        executableURL: nil
      ),
      terminalURL: nil
    )

    XCTAssertFalse(entry.isReady)
    XCTAssertTrue(
      Diagnostics.report(entries: [entry])
        .hasSuffix("Status: missing required software")
    )
  }

  func testTerminalBelowMinimumVersionIsNotReady() throws {
    let specification = try XCTUnwrap(
      AgentCatalog.all.first { $0.id == .claude }
    )
    let entry = DiagnosticEntry(
      agent: ResolvedAgent(
        specification: specification,
        executableURL: URL(fileURLWithPath: "/tmp/bin/claude")
      ),
      terminalURL: URL(fileURLWithPath: "/Applications/Ghostty.app"),
      terminalMeetsMinimumVersion: false
    )

    XCTAssertFalse(entry.isReady)
    XCTAssertEqual(
      entry.description,
      "Claude: command=/tmp/bin/claude | terminal=Ghostty (/Applications/Ghostty.app)"
        + " | needs Ghostty 1.3.0 or newer"
    )
  }
}
