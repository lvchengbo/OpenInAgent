import AppKit
import FinderSync
import Foundation

final class FinderSync: FIFinderSync {
  override init() {
    super.init()
    // Monitored roots acquire the containing app's sidebar icon. This
    // extension only provides a global toolbar, so it must monitor no folders.
    FIFinderSyncController.default().directoryURLs = []
  }

  override var toolbarItemName: String {
    "Agent"
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

    let config = ConfigStorage.load()
    let isYolo = (config.mode == .yolo)

    let menu = NSMenu(title: toolbarItemName)
    for agent in AgentCatalog.all {
      let title = isYolo ? "Open in \(agent.displayName) (YOLO)" : "Open in \(agent.displayName)"
      let item = NSMenuItem(
        title: title,
        action: action(for: agent.id),
        keyEquivalent: ""
      )
      item.target = self

      if let image = NSImage(
        systemSymbolName: agent.symbolName,
        accessibilityDescription: agent.displayName
      ) {
        image.isTemplate = true
        item.image = image
      }

      menu.addItem(item)
    }

    menu.addItem(NSMenuItem.separator())

    let safeItem = NSMenuItem(
      title: "Safe Mode",
      action: #selector(setSafeMode(_:)),
      keyEquivalent: ""
    )
    safeItem.target = self
    safeItem.state = isYolo ? .off : .on
    menu.addItem(safeItem)

    let yoloItem = NSMenuItem(
      title: "YOLO Mode (Auto-Approve)",
      action: #selector(setYoloMode(_:)),
      keyEquivalent: ""
    )
    yoloItem.target = self
    yoloItem.state = isYolo ? .on : .off
    menu.addItem(yoloItem)

    menu.addItem(NSMenuItem.separator())

    let configItem = NSMenuItem(
      title: "Open Config File...",
      action: #selector(openConfigFile(_:)),
      keyEquivalent: ""
    )
    configItem.target = self
    menu.addItem(configItem)

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

  @objc private func setSafeMode(_ sender: NSMenuItem) {
    var config = ConfigStorage.load()
    config.mode = .safe
    try? ConfigStorage.save(config)
  }

  @objc private func setYoloMode(_ sender: NSMenuItem) {
    var config = ConfigStorage.load()
    config.mode = .yolo
    try? ConfigStorage.save(config)
  }

  @objc private func openConfigFile(_ sender: NSMenuItem) {
    let url = ConfigStorage.ensureConfigFileExists()
    NSWorkspace.shared.open(url)
  }

  private func openInAgent(_ agentID: AgentID) {
    ToolbarHandoff.send(.openAgent(agentID))
  }
}
