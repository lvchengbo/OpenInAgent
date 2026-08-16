import AppKit
import Foundation
import SwiftUI

@MainActor
final class AgentMenuController: NSObject {
  static let presentationDelay: TimeInterval = 0.03
  static let panelWidth: CGFloat = 300

  private let agents: [ResolvedAgent]
  private let workingDirectory: URL
  private let anchorPoint: NSPoint
  private var panel: AgentChooserPanel?
  private var globalClickMonitor: Any?
  private var localKeyMonitor: Any?
  private var continuation: CheckedContinuation<ResolvedAgent?, Never>?
  private var hasCompleted = false

  init(
    agents: [ResolvedAgent],
    workingDirectory: URL,
    anchorPoint: NSPoint = NSEvent.mouseLocation
  ) {
    self.agents = agents
    self.workingDirectory = workingDirectory
    self.anchorPoint = anchorPoint
  }

  func chooseAgent() async -> ResolvedAgent? {
    precondition(continuation == nil, "Agent chooser is already active")
    NSApp.activate(ignoringOtherApps: true)

    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Self.presentationDelay
      ) { [weak self] in
        self?.showPanel()
      }
    }
  }

  func makePanel() -> AgentChooserPanel {
    let choices = agents.enumerated().map { index, agent in
      AgentChoice(
        id: index,
        title: Self.title(
          for: agent,
          terminalAvailable: TerminalLauncher.isTerminalInstalled(
            agent.specification.terminal
          )
        ),
        symbolName: agent.specification.symbolName,
        toolTip: agent.executableURL?.path,
        isAvailable: agent.isInstalled
          && TerminalLauncher.isTerminalInstalled(agent.specification.terminal)
      )
    }

    let pickerView = AgentChooserView(
      directoryName: displayName(for: workingDirectory),
      directoryPath: workingDirectory.path,
      choices: choices,
      onSelect: { [weak self] index in
        self?.selectAgent(at: index)
      },
      onCancel: { [weak self] in
        self?.complete(with: nil)
      }
    )
    let hostingController = NSHostingController(rootView: pickerView)
    hostingController.view.layoutSubtreeIfNeeded()
    let fittingSize = hostingController.view.fittingSize
    let panelSize = NSSize(
      width: Self.panelWidth,
      height: max(fittingSize.height, 1)
    )
    let screen =
      NSScreen.screens.first {
        NSMouseInRect(anchorPoint, $0.frame, false)
      } ?? NSScreen.main
    let visibleFrame =
      screen?.visibleFrame
      ?? NSRect(origin: .zero, size: panelSize)
    let origin = Self.positionedOrigin(
      for: panelSize,
      anchoredTo: anchorPoint,
      visibleFrame: visibleFrame
    )

    let panel = AgentChooserPanel(
      contentRect: NSRect(origin: origin, size: panelSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentViewController = hostingController
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .popUpMenu
    panel.hidesOnDeactivate = false
    panel.isMovable = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [
      .transient,
      .moveToActiveSpace,
      .fullScreenAuxiliary,
    ]
    return panel
  }

  static func positionedOrigin(
    for size: NSSize,
    anchoredTo anchor: NSPoint,
    visibleFrame: NSRect
  ) -> NSPoint {
    let inset: CGFloat = 6
    var x = anchor.x - (size.width / 2)
    var y = anchor.y - size.height - inset

    x = max(visibleFrame.minX + inset, x)
    x = min(visibleFrame.maxX - inset - size.width, x)

    if y < visibleFrame.minY + inset {
      y = anchor.y + inset
    }
    y = min(visibleFrame.maxY - inset - size.height, y)
    y = max(visibleFrame.minY + inset, y)

    return NSPoint(x: x, y: y)
  }

  static func title(
    for agent: ResolvedAgent,
    terminalAvailable: Bool
  ) -> String {
    if !agent.isInstalled {
      return "\(agent.specification.displayName) — command not found"
    }
    if !terminalAvailable {
      return
        "\(agent.specification.displayName) — \(agent.specification.terminal.displayName) not found"
    }
    return "\(agent.specification.displayName) in \(agent.specification.terminal.displayName)"
  }

  private func showPanel() {
    guard !hasCompleted, panel == nil else { return }
    let panel = makePanel()
    self.panel = panel
    panel.makeKeyAndOrderFront(nil)
    installDismissMonitors()
  }

  private func installDismissMonitors() {
    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      Task { @MainActor in
        self?.complete(with: nil)
      }
    }

    localKeyMonitor = NSEvent.addLocalMonitorForEvents(
      matching: .keyDown
    ) { [weak self] event in
      guard event.keyCode == 53 else { return event }
      self?.complete(with: nil)
      return nil
    }
  }

  private func selectAgent(at index: Int) {
    guard agents.indices.contains(index) else { return }
    complete(with: agents[index])
  }

  private func complete(with agent: ResolvedAgent?) {
    guard !hasCompleted else { return }
    hasCompleted = true
    tearDownPresentation()
    continuation?.resume(returning: agent)
    continuation = nil
  }

  private func tearDownPresentation() {
    if let globalClickMonitor {
      NSEvent.removeMonitor(globalClickMonitor)
      self.globalClickMonitor = nil
    }
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
      self.localKeyMonitor = nil
    }
    panel?.orderOut(nil)
    panel = nil
  }

  private func displayName(for directory: URL) -> String {
    let name = directory.lastPathComponent
    let fallback = directory.path
    let value = name.isEmpty ? fallback : name
    guard value.count > 48 else { return value }
    return String(value.prefix(45)) + "…"
  }
}

final class AgentChooserPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

private struct AgentChoice: Identifiable {
  let id: Int
  let title: String
  let symbolName: String
  let toolTip: String?
  let isAvailable: Bool
}

private struct AgentChooserView: View {
  let directoryName: String
  let directoryPath: String
  let choices: [AgentChoice]
  let onSelect: (Int) -> Void
  let onCancel: () -> Void

  @State private var hoveredChoice: Int?
  @State private var cancelIsHovered = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Open \(directoryName) with…")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help(directoryPath)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)

      Divider()
        .padding(.bottom, 4)

      ForEach(choices) { choice in
        Button {
          onSelect(choice.id)
        } label: {
          HStack(spacing: 9) {
            Image(systemName: choice.symbolName)
              .frame(width: 18)
              .foregroundStyle(choice.isAvailable ? .primary : .tertiary)
            Text(choice.title)
              .lineLimit(1)
              .foregroundStyle(choice.isAvailable ? .primary : .secondary)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .background(
            hoveredChoice == choice.id && choice.isAvailable
              ? Color.accentColor.opacity(0.16)
              : Color.clear
          )
        }
        .buttonStyle(.plain)
        .disabled(!choice.isAvailable)
        .help(choice.toolTip ?? choice.title)
        .onHover { isInside in
          hoveredChoice = isInside ? choice.id : nil
        }
      }

      Divider()
        .padding(.top, 4)

      Button(action: onCancel) {
        HStack(spacing: 9) {
          Image(systemName: "xmark")
            .frame(width: 18)
            .foregroundStyle(.secondary)
          Text("Cancel")
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
          cancelIsHovered ? Color.accentColor.opacity(0.16) : Color.clear
        )
      }
      .buttonStyle(.plain)
      .onHover { cancelIsHovered = $0 }
    }
    .padding(.vertical, 6)
    .frame(width: AgentMenuController.panelWidth)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
    }
  }
}
