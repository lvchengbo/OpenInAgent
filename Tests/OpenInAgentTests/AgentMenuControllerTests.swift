import AppKit
import Foundation
import XCTest

@testable import OpenInAgent

final class AgentMenuControllerTests: XCTestCase {
  @MainActor
  func testChooserUsesPersistentKeyPanelInsteadOfTransientMenu() {
    let controller = AgentMenuController(
      agents: [],
      workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
      anchorPoint: NSPoint(x: 500, y: 500)
    )
    let panel = controller.makePanel()
    defer { panel.close() }

    XCTAssertTrue(panel.canBecomeKey)
    XCTAssertTrue(panel.canBecomeMain)
    XCTAssertEqual(panel.level, .popUpMenu)
    XCTAssertFalse(panel.hidesOnDeactivate)
    XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertGreaterThan(AgentMenuController.presentationDelay, 0)
  }

  @MainActor
  func testPanelOriginIsClampedToVisibleScreen() {
    let frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
    let size = NSSize(width: 300, height: 250)

    let topLeft = AgentMenuController.positionedOrigin(
      for: size,
      anchoredTo: NSPoint(x: 0, y: 800),
      visibleFrame: frame
    )
    let bottomRight = AgentMenuController.positionedOrigin(
      for: size,
      anchoredTo: NSPoint(x: 1_000, y: 0),
      visibleFrame: frame
    )

    XCTAssertGreaterThanOrEqual(topLeft.x, frame.minX + 6)
    XCTAssertLessThanOrEqual(topLeft.y + size.height, frame.maxY - 6)
    XCTAssertLessThanOrEqual(bottomRight.x + size.width, frame.maxX - 6)
    XCTAssertGreaterThanOrEqual(bottomRight.y, frame.minY + 6)
  }

  @MainActor
  func testUnavailableAgentTitlesExplainMissingDependency() throws {
    let specification = try XCTUnwrap(
      AgentCatalog.all.first { $0.id == .claude }
    )
    let missingCommand = ResolvedAgent(
      specification: specification,
      executableURL: nil
    )
    let installedCommand = ResolvedAgent(
      specification: specification,
      executableURL: URL(fileURLWithPath: "/tmp/claude")
    )

    XCTAssertEqual(
      AgentMenuController.title(
        for: missingCommand,
        terminalAvailable: true
      ),
      "Claude — command not found"
    )
    XCTAssertEqual(
      AgentMenuController.title(
        for: installedCommand,
        terminalAvailable: false
      ),
      "Claude — Ghostty not found"
    )
  }
}
