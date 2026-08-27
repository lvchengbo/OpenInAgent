import AppKit
import FinderSync
import Foundation

final class FinderSync: FIFinderSync {
  private let controller = FIFinderSyncController.default()

  override init() {
    super.init()

    refreshMonitoredDirectories()

    let notifications = NSWorkspace.shared.notificationCenter
    notifications.addObserver(
      self,
      selector: #selector(volumesDidChange(_:)),
      name: NSWorkspace.didMountNotification,
      object: nil
    )
    notifications.addObserver(
      self,
      selector: #selector(volumesDidChange(_:)),
      name: NSWorkspace.didUnmountNotification,
      object: nil
    )
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
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
    // Handle the click immediately and return no menu so copying is one step.
    guard let targetURL = currentTargetURL, targetURL.isFileURL else {
      NSSound.beep()
      return nil
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(targetURL.path, forType: .string) else {
      NSSound.beep()
      return nil
    }

    return nil
  }

  private var currentTargetURL: URL? {
    let selectedURLs = controller.selectedItemURLs() ?? []
    return selectedURLs.first ?? controller.targetedURL()
  }

  @objc private func volumesDidChange(_ notification: Notification) {
    refreshMonitoredDirectories()
  }

  private func refreshMonitoredDirectories() {
    let resourceKeys: [URLResourceKey] = [.isHiddenKey, .isVolumeKey]
    let mountedVolumes =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: resourceKeys,
        options: [.skipHiddenVolumes]
      ) ?? []

    controller.directoryURLs = Set(mountedVolumes)
  }
}
