import AppKit
import Foundation

@MainActor
final class AgentMenuController: NSObject {
  private let agents: [ResolvedAgent]
  private let workingDirectory: URL
  private var selectedAgent: ResolvedAgent?

  init(agents: [ResolvedAgent], workingDirectory: URL) {
    self.agents = agents
    self.workingDirectory = workingDirectory
  }

  func chooseAgent() -> ResolvedAgent? {
    let menu = NSMenu(title: "Open in Agent")
    menu.autoenablesItems = false
    menu.minimumWidth = 250

    let header = NSMenuItem(
      title: "Open \(displayName(for: workingDirectory)) with…",
      action: nil,
      keyEquivalent: ""
    )
    header.isEnabled = false
    header.toolTip = workingDirectory.path
    menu.addItem(header)
    menu.addItem(.separator())

    for (index, agent) in agents.enumerated() {
      let terminalAvailable = TerminalLauncher.isTerminalInstalled(
        agent.specification.terminal
      )
      let isAvailable = agent.isInstalled && terminalAvailable

      let title: String
      if !agent.isInstalled {
        title = "\(agent.specification.displayName) — command not found"
      } else if !terminalAvailable {
        title =
          "\(agent.specification.displayName) — \(agent.specification.terminal.displayName) not found"
      } else {
        title = "\(agent.specification.displayName) in \(agent.specification.terminal.displayName)"
      }

      let item = NSMenuItem(
        title: title,
        action: #selector(agentSelected(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.tag = index
      item.isEnabled = isAvailable
      item.image = symbolImage(named: agent.specification.symbolName)
      item.toolTip = agent.executableURL?.path
      menu.addItem(item)
    }

    menu.addItem(.separator())
    let cancel = NSMenuItem(
      title: "Cancel",
      action: #selector(cancelSelected(_:)),
      keyEquivalent: ""
    )
    cancel.target = self
    menu.addItem(cancel)

    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)

    return selectedAgent
  }

  @objc private func agentSelected(_ sender: NSMenuItem) {
    guard agents.indices.contains(sender.tag) else { return }
    selectedAgent = agents[sender.tag]
  }

  @objc private func cancelSelected(_ sender: NSMenuItem) {
    selectedAgent = nil
  }

  private func displayName(for directory: URL) -> String {
    let name = directory.lastPathComponent
    let fallback = directory.path
    let value = name.isEmpty ? fallback : name
    guard value.count > 48 else { return value }
    return String(value.prefix(45)) + "…"
  }

  private func symbolImage(named name: String) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(
      pointSize: 14,
      weight: .regular
    )
    return NSImage(
      systemSymbolName: name,
      accessibilityDescription: nil
    )?.withSymbolConfiguration(configuration)
  }
}
