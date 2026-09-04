import AppKit
import Darwin
import FinderSync
import Foundation

@main
private enum OpenInAgentApplication {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    if Diagnostics.isRequested() {
      let entries = Diagnostics.liveEntries()
      print(Diagnostics.report(entries: entries))
      exit(entries.allSatisfy(\.isReady) ? 0 : 1)
    }

    let coordinator = ApplicationCoordinator()
    application.delegate = coordinator
    withExtendedLifetime(coordinator) {
      application.run()
    }
    exit(coordinator.exitStatus)
  }
}

@MainActor
final class ApplicationCoordinator: NSObject, NSApplicationDelegate {
  private(set) var exitStatus: Int32 = 0
  private var launchTask: Task<Void, Never>?
  private var menuController: AgentMenuController?
  private var launchState = ApplicationLaunchState()

  func applicationDidFinishLaunching(_ notification: Notification) {
    let isDefaultLaunch =
      notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey]
      as? Bool ?? true
    handle(
      launchState.didFinishLaunching(isDefaultLaunch: isDefaultLaunch)
    )
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    handle(launchState.receive(urls: urls))
  }

  private func handle(_ decision: ApplicationLaunchDecision?) {
    switch decision {
    case .launch(let activationURL):
      start(activationURL: activationURL)
    case .rejectInvalidRequest:
      failInvalidRequest()
    case nil:
      break
    }
  }

  private func start(activationURL: URL?) {
    guard launchTask == nil else { return }
    launchTask = Task { @MainActor [weak self] in
      await self?.run(activationURL: activationURL)
    }
  }

  private func run(activationURL: URL?) async {
    let request: AgentLaunchRequest?
    if let activationURL {
      do {
        request = try AgentHandoffStore.containingApplication().consume(
          activationURL
        )
      } catch {
        finish(status: 4)
        return
      }
    } else {
      request = nil
    }

    let finderURL: URL
    if let request {
      finderURL = request.targetURL
    } else if let launchURL = FinderSelection.urlFromLaunchArguments() {
      finderURL = launchURL
    } else {
      presentSetup()
      finish(status: 0)
      return
    }

    guard
      let workingDirectory = FinderPathResolver.workingDirectory(
        for: finderURL
      )
    else {
      presentError(
        title: "The selected item isn’t available",
        message: "Choose an accessible local file or folder and try again."
      )
      finish(status: 2)
      return
    }

    let agents = ExecutableResolver.resolveAll()
    let selectedAgent: ResolvedAgent
    if let request {
      guard
        let requestedAgent = agents.first(where: {
          $0.specification.id == request.agentID
        })
      else {
        presentError(
          title: "The requested agent isn’t available",
          message: "Open in Agent could not match the Finder menu selection."
        )
        finish(status: 2)
        return
      }
      selectedAgent = requestedAgent
    } else {
      let menuController = AgentMenuController(
        agents: agents,
        workingDirectory: workingDirectory
      )
      self.menuController = menuController
      guard let choice = await menuController.chooseAgent() else {
        self.menuController = nil
        finish(status: 0)
        return
      }
      self.menuController = nil
      selectedAgent = choice
    }

    do {
      try await TerminalLauncher.launch(
        selectedAgent,
        workingDirectory: workingDirectory
      )
      finish(status: 0)
    } catch {
      let launchError = error as? TerminalLauncherError
      presentError(
        title: "Couldn’t open \(selectedAgent.specification.displayName)",
        message: error.localizedDescription,
        offersAutomationSettings: {
          if case .automationDenied = launchError { return true }
          return false
        }()
      )
      finish(status: 3)
    }
  }

  private func failInvalidRequest() {
    guard launchTask == nil else { return }
    finish(status: 4)
  }

  private func finish(status: Int32) {
    exitStatus = status
    NSApp.stop(nil)

    if let wakeEvent = NSEvent.otherEvent(
      with: .applicationDefined,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      subtype: 0,
      data1: 0,
      data2: 0
    ) {
      NSApp.postEvent(wakeEvent, atStart: false)
    }
  }

  private func presentError(
    title: String,
    message: String,
    offersAutomationSettings: Bool = false
  ) {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    if offersAutomationSettings {
      alert.addButton(withTitle: "Open Automation Settings")
    }

    let response = alert.runModal()
    if offersAutomationSettings,
      response == .alertSecondButtonReturn,
      let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
      )
    {
      NSWorkspace.shared.open(settingsURL)
    }
  }

  private func presentSetup() {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Configure the Finder toolbar"
    alert.informativeText =
      "Enable both Finder extensions in System Settings. Then, in Finder, choose View → Customize Toolbar and add Open in Agent and Copy Path. Command-drag the old app shortcut out of the toolbar."
    alert.addButton(withTitle: "Open Extension Settings")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      FIFinderSyncController.showExtensionManagementInterface()
    }
  }
}
