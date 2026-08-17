import AppKit
import FinderSync
import Foundation
import OSLog

final class FinderSync: FIFinderSync {
  private static let logger = Logger(
    subsystem: "com.lvchengbo.openinagent.finderextension",
    category: "Handoff"
  )

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
    "Open in Agent"
  }

  override var toolbarItemToolTip: String {
    "Open this Finder location in an AI coding agent"
  }

  override var toolbarItemImage: NSImage {
    let image =
      NSImage(
        systemSymbolName: "sparkles",
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

    let menu = NSMenu(title: toolbarItemName)
    let targetURL = currentTargetURL

    for agent in AgentCatalog.all {
      let item = NSMenuItem(
        title: "Open in \(agent.displayName)",
        action: action(for: agent.id),
        keyEquivalent: ""
      )
      item.target = self
      item.isEnabled = targetURL != nil

      if let image = NSImage(
        systemSymbolName: agent.symbolName,
        accessibilityDescription: agent.displayName
      ) {
        image.isTemplate = true
        item.image = image
      }

      menu.addItem(item)
    }

    menu.addItem(.separator())
    let copyPathItem = NSMenuItem(
      title: "Copy Path",
      action: #selector(copyPath(_:)),
      keyEquivalent: ""
    )
    copyPathItem.target = self
    copyPathItem.isEnabled = targetURL?.isFileURL == true
    if let image = NSImage(
      systemSymbolName: "doc.on.doc",
      accessibilityDescription: "Copy Path"
    ) {
      image.isTemplate = true
      copyPathItem.image = image
    }
    menu.addItem(copyPathItem)

    if targetURL == nil {
      menu.addItem(.separator())
      let unavailableItem = NSMenuItem(
        title: "No Finder location available",
        action: nil,
        keyEquivalent: ""
      )
      unavailableItem.isEnabled = false
      menu.addItem(unavailableItem)
    }

    return menu
  }

  private func action(for agentID: AgentID) -> Selector {
    switch agentID {
    case .claude:
      #selector(openInClaude(_:))
    case .codex:
      #selector(openInCodex(_:))
    case .grok:
      #selector(openInGrok(_:))
    case .agy:
      #selector(openInAGY(_:))
    }
  }

  @objc private func openInClaude(_ sender: NSMenuItem) {
    openInAgent(.claude)
  }

  @objc private func openInCodex(_ sender: NSMenuItem) {
    openInAgent(.codex)
  }

  @objc private func openInGrok(_ sender: NSMenuItem) {
    openInAgent(.grok)
  }

  @objc private func openInAGY(_ sender: NSMenuItem) {
    openInAgent(.agy)
  }

  @objc private func copyPath(_ sender: NSMenuItem) {
    guard let targetURL = currentTargetURL, targetURL.isFileURL else {
      NSSound.beep()
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(targetURL.path, forType: .string) else {
      NSSound.beep()
      return
    }
  }

  private func openInAgent(_ agentID: AgentID) {
    guard
      let targetURL = currentTargetURL,
      let applicationURL = containingApplicationURL
    else {
      NSSound.beep()
      return
    }

    let requestURL: URL
    do {
      let store = try AgentHandoffStore.finderExtension()
      requestURL = try store.create(
        AgentLaunchRequest(agentID: agentID, targetURL: targetURL)
      )
    } catch {
      Self.logger.error("Could not create a secure handoff request")
      NSSound.beep()
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.createsNewApplicationInstance = true

    NSWorkspace.shared.open(
      [requestURL],
      withApplicationAt: applicationURL,
      configuration: configuration,
      completionHandler: { _, error in
        guard let error else {
          return
        }

        Self.logger.error(
          "Could not hand off request to the containing app: \(error.localizedDescription, privacy: .public)"
        )
        DispatchQueue.main.async {
          NSSound.beep()
        }
      }
    )
  }

  private var currentTargetURL: URL? {
    let selectedURLs = controller.selectedItemURLs() ?? []
    return selectedURLs.first ?? controller.targetedURL()
  }

  private var containingApplicationURL: URL? {
    var candidate = Bundle.main.bundleURL

    while candidate.path != "/" {
      if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
        return candidate
      }
      candidate.deleteLastPathComponent()
    }

    return nil
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
