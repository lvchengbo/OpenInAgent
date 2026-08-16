import Foundation
import XCTest

@testable import OpenInAgent

final class FinderPathResolverTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenInAgentTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    if let root {
      try? FileManager.default.removeItem(at: root)
    }
    root = nil
  }

  func testFolderResolvesToItself() throws {
    let folder = root.appendingPathComponent("Project", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    XCTAssertEqual(
      FinderPathResolver.workingDirectory(for: folder),
      folder.standardizedFileURL
    )
  }

  func testFileResolvesToParentFolder() throws {
    let file = root.appendingPathComponent("notes.md")
    try Data().write(to: file)

    XCTAssertEqual(
      FinderPathResolver.workingDirectory(for: file),
      root.standardizedFileURL
    )
  }

  func testPackageResolvesToParentFolder() throws {
    let package = root.appendingPathComponent("Sample.app", isDirectory: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

    XCTAssertEqual(
      FinderPathResolver.workingDirectory(for: package),
      root.standardizedFileURL
    )
  }

  func testDirectorySymlinkKeepsSelectedPath() throws {
    let target = root.appendingPathComponent("Target", isDirectory: true)
    let link = root.appendingPathComponent("LinkedProject", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: link.path,
      withDestinationPath: target.path
    )

    XCTAssertEqual(
      FinderPathResolver.workingDirectory(for: link),
      link.standardizedFileURL
    )
  }

  func testAliasResolvesToTargetDirectory() throws {
    let target = root.appendingPathComponent("AliasTarget", isDirectory: true)
    let alias = root.appendingPathComponent("Project Alias")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

    let bookmark = try target.bookmarkData(
      options: [.suitableForBookmarkFile],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    try URL.writeBookmarkData(bookmark, to: alias)

    XCTAssertEqual(
      FinderPathResolver.workingDirectory(for: alias),
      target.standardizedFileURL
    )
  }

  func testAliasToUnavailableTargetFailsClosed() throws {
    let target = root.appendingPathComponent("UnavailableTarget", isDirectory: true)
    let alias = root.appendingPathComponent("Unavailable Alias")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

    let bookmark = try target.bookmarkData(
      options: [.suitableForBookmarkFile],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    try URL.writeBookmarkData(bookmark, to: alias)
    try FileManager.default.removeItem(at: target)

    XCTAssertNil(FinderPathResolver.workingDirectory(for: alias))
  }

  func testMissingAndNonFileURLsAreRejected() {
    XCTAssertNil(
      FinderPathResolver.workingDirectory(
        for: root.appendingPathComponent("missing")
      )
    )
    XCTAssertNil(
      FinderPathResolver.workingDirectory(
        for: URL(string: "https://example.com/project")
      )
    )
  }

  func testAdversarialFilenameStillResolvesOnlyToParent() throws {
    let name = "'\"`$(touch nope);&\n-leading-—.txt"
    let file = root.appendingPathComponent(name)
    try Data().write(to: file)

    XCTAssertEqual(
      FinderPathResolver.workingDirectory(for: file),
      root.standardizedFileURL
    )
  }
}
