import AppKit
import Foundation
import OSLog

/// Only writes an opaque request and opens the containing app. Finder reading,
/// clipboard access, and terminal launching belong to the unsandboxed host.
enum ToolbarHandoff {
  static func send(_ request: FinderToolbarRequest) {
    guard let applicationURL = containingApplicationURL else {
      NSSound.beep()
      return
    }

    let requestURL: URL
    do {
      let store = try AgentHandoffStore.finderExtension(endpoint: request.endpoint)
      requestURL = try store.create(request)
    } catch {
      logger.error("Could not create a secure toolbar request")
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
      configuration: configuration
    ) { _, error in
      guard let error else { return }
      logger.error(
        "Could not open the containing app: \(error.localizedDescription, privacy: .public)"
      )
      DispatchQueue.main.async { NSSound.beep() }
    }
  }

  private static let logger = Logger(
    subsystem: "com.lvchengbo.openinagent",
    category: "ToolbarHandoff"
  )

  private static var containingApplicationURL: URL? {
    var candidate = Bundle.main.bundleURL
    while candidate.path != "/" {
      if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
        return candidate
      }
      candidate.deleteLastPathComponent()
    }
    return nil
  }
}
