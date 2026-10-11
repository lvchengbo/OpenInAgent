import AppKit
import Foundation

enum FinderSelectionError: LocalizedError {
  case automationDenied
  case unavailable
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .automationDenied:
      "Allow Open in Agent to read Finder under System Settings → Privacy & Security → Automation, then try again."
    case .unavailable:
      "Open a Finder window showing a local folder, select an item or leave the selection empty, and try again."
    case .failed(let detail):
      "Finder could not provide the selected location. \(detail)"
    }
  }
}

enum FinderSelection {
  // Constant source: selected filenames never enter executable AppleScript.
  // Reading Finder in the host avoids the sync roots that override disk icons.
  private static let currentLocationScript = """
    tell application id "com.apple.finder"
        with timeout of 10 seconds
            if (count of Finder windows) is 0 then error "No Finder window" number -1728
            set selectedItems to selection
            if (count of selectedItems) is greater than 0 then
                return POSIX path of (item 1 of selectedItems as alias)
            end if
            return POSIX path of (target of front Finder window as alias)
        end timeout
    end tell
    """

  @MainActor
  static func urlFromCurrentWindow() throws -> URL {
    guard let script = NSAppleScript(source: currentLocationScript) else {
      throw FinderSelectionError.unavailable
    }
    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)
    if let error {
      let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
      if number == -1743 { throw FinderSelectionError.automationDenied }
      if number == -1728 || number == -1700 { throw FinderSelectionError.unavailable }
      throw FinderSelectionError.failed(
        error[NSAppleScript.errorMessage] as? String ?? "Try again."
      )
    }
    guard let path = result.stringValue, let url = urlFromFinderPath(path) else {
      throw FinderSelectionError.unavailable
    }
    return url
  }

  static func urlFromFinderPath(_ path: String) -> URL? {
    // Do not trim: newlines and trailing spaces are legal filename characters.
    guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
    return AgentLaunchRequest.validatedTargetURL(URL(fileURLWithPath: path))
  }

  static func urlFromLaunchArguments(
    _ arguments: [String] = CommandLine.arguments,
    fileManager: FileManager = .default
  ) -> URL? {
    for argument in arguments.dropFirst() {
      guard !argument.hasPrefix("-psn_") else { continue }
      guard !argument.hasPrefix("--") else { continue }

      let candidate: URL
      if let parsed = URL(string: argument), parsed.isFileURL {
        candidate = parsed
      } else {
        candidate = URL(fileURLWithPath: argument)
      }

      // Hold launch-argument URLs to the same bar as the handoff: an absolute
      // local file URL with no authority, user info, port, query, or fragment.
      // This rejects `file://host/path`, whose authority would otherwise be
      // silently dropped to an unrelated local path.
      guard let url = AgentLaunchRequest.validatedTargetURL(candidate) else {
        continue
      }

      if fileManager.fileExists(atPath: url.path) {
        return url
      }
    }
    return nil
  }
}
