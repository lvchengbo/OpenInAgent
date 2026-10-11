import AppKit
import FinderSync
import Foundation

final class FinderSync: FIFinderSync {
  override init() {
    super.init()
    // Registering a volume as a sync root replaces its native sidebar icon.
    // The host reads Finder's location when the global toolbar button is used.
    FIFinderSyncController.default().directoryURLs = []
  }

  override var toolbarItemName: String {
    "Copy Path"
  }

  override var toolbarItemToolTip: String {
    "Copy Path"
  }

  override var toolbarItemImage: NSImage {
    let image =
      NSImage(
        systemSymbolName: "doc.on.doc",
        accessibilityDescription: toolbarItemName
      ) ?? NSImage(size: NSSize(width: 23, height: 23))
    let configuration = NSImage.SymbolConfiguration(
      pointSize: 17,
      weight: .medium
    )
    let configuredImage = image.withSymbolConfiguration(configuration) ?? image
    configuredImage.size = NSSize(width: 23, height: 23)
    configuredImage.isTemplate = true
    return configuredImage
  }

  override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    guard menuKind == .toolbarItemMenu else {
      return nil
    }

    // Finder Sync exposes this menu request as the toolbar click callback.
    // Keep the one-click operation; the host reads Finder and copies the path.
    ToolbarHandoff.send(.copyPath)
    return nil
  }
}
