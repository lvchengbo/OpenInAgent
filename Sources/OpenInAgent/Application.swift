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

    if CommandLine.arguments.dropFirst().contains(ConfigStorage.initializationArgument) {
      do {
        let fileURL = try ConfigStorage.ensureConfigFileExists()
        print("Configuration: \(fileURL.path)")
        exit(0)
      } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
      }
    }

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
  /// How long a non-default launch may wait for its activation URL.
  static let startupDeadline: TimeInterval = 10

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

    // Without a deadline, a non-default launch whose activation URL never
    // arrives would keep this windowless app alive indefinitely.
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.startupDeadline
    ) { [weak self] in
      guard let self else { return }
      self.handle(self.launchState.startupDeadlineExpired())
    }
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
    let request: FinderToolbarRequest?
    if let activationURL {
      guard let endpoint = FinderHandoffEndpoint(rawValue: activationURL.host?.lowercased() ?? "")
      else {
        finish(status: 4)
        return
      }
      do {
        request = try AgentHandoffStore.containingApplication(endpoint: endpoint).consume(
          activationURL
        )
      } catch {
        finish(status: 4)
        return
      }
    } else {
      request = nil
    }

    if request == .openConfigFile {
      finish(status: openConfiguration() ? 0 : 2)
      return
    }

    if case .setMode(let mode) = request {
      do {
        try ConfigStorage.setMode(mode)
        finish(status: 0)
      } catch {
        presentError(title: "Couldn’t save the launch mode", message: error.localizedDescription)
        finish(status: 2)
      }
      return
    }

    let finderURL: URL
    if let request {
      if case .openAgent(_, let targetURL?) = request {
        finderURL = targetURL
      } else {
        do {
          finderURL = try FinderSelection.urlFromCurrentWindow()
        } catch {
          presentError(
            title: "Couldn’t read the Finder location",
            message: error.localizedDescription,
            offersAutomationSettings: {
              if case .automationDenied = error as? FinderSelectionError { return true }
              return false
            }()
          )
          finish(status: 2)
          return
        }
      }
    } else if let launchURL = FinderSelection.urlFromLaunchArguments() {
      finderURL = launchURL
    } else {
      finish(status: presentSetup())
      return
    }

    if request == .copyPath {
      guard FileManager.default.fileExists(atPath: finderURL.path) else {
        presentError(
          title: "The selected item isn’t available",
          message: "Choose an accessible local file or folder and try again."
        )
        finish(status: 2)
        return
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      let copied = pasteboard.setString(finderURL.path, forType: .string)
      if !copied { NSSound.beep() }
      finish(status: copied ? 0 : 2)
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
    if case .openAgent(let agentID, _) = request {
      guard
        let requestedAgent = agents.first(where: {
          $0.specification.id == agentID
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

  private func openConfiguration() -> Bool {
    do {
      let fileURL = try ConfigStorage.fileForEditing()
      guard NSWorkspace.shared.open(fileURL) else {
        presentError(
          title: "Couldn’t open the configuration",
          message: "Choose an application to open JSON files, then try again."
        )
        return false
      }
      return true
    } catch {
      presentError(title: "Couldn’t open the configuration", message: error.localizedDescription)
      return false
    }
  }

  private func presentSetup() -> Int32 {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Open in Agent"
    alert.informativeText =
      "Enable both Finder extensions in System Settings. Then, in Finder, choose View → Customize Toolbar and add Agent and Copy Path.\n\nYou can configure execution modes and CLI flags in ~/.config/openinagent/config.json."
    alert.addButton(withTitle: "Open Extension Settings")
    alert.addButton(withTitle: "Open Config File")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      FIFinderSyncController.showExtensionManagementInterface()
    } else if response == .alertSecondButtonReturn {
      return openConfiguration() ? 0 : 2
    }
    return 0
  }
}
