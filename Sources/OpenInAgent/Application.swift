import AppKit
import Darwin
import Foundation

@main
private enum OpenInAgentApplication {
  @MainActor
  static func main() async {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    if Diagnostics.isRequested() {
      let entries = Diagnostics.liveEntries()
      print(Diagnostics.report(entries: entries))
      exit(entries.allSatisfy(\.isReady) ? 0 : 1)
    }

    let finderURL: URL
    if let launchURL = FinderSelection.urlFromLaunchArguments() {
      finderURL = launchURL
    } else {
      switch await FinderSelection.resolveURL() {
      case .success(let url):
        finderURL = url
      case .failure(let error):
        presentError(
          title: "Couldn’t read the Finder selection",
          message: error.localizedDescription,
          offersAutomationSettings: error == .automationDenied
        )
        exit(1)
      }
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
      exit(2)
    }

    let agents = ExecutableResolver.resolveAll()
    let menuController = AgentMenuController(
      agents: agents,
      workingDirectory: workingDirectory
    )

    guard let selectedAgent = menuController.chooseAgent() else {
      exit(0)
    }

    do {
      try await TerminalLauncher.launch(
        selectedAgent,
        workingDirectory: workingDirectory
      )
      exit(0)
    } catch {
      let launchError = error as? TerminalLauncherError
      presentError(
        title: "Couldn’t open \(selectedAgent.specification.displayName)",
        message: error.localizedDescription,
        offersAutomationSettings: {
          if case .automationDenied? = launchError { return true }
          return false
        }()
      )
      exit(3)
    }
  }

  @MainActor
  private static func presentError(
    title: String,
    message: String,
    offersAutomationSettings: Bool = false
  ) {
    NSApp.setActivationPolicy(.accessory)
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
}
