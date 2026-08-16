import Foundation

enum FinderSelectionError: LocalizedError, Equatable, Sendable {
  case automationDenied
  case timedOut
  case noLocation
  case inaccessibleLocation
  case queryFailed(String)

  var errorDescription: String? {
    switch self {
    case .automationDenied:
      "Open in Agent is not allowed to read Finder’s selection. Enable Finder under System Settings → Privacy & Security → Automation, then try again."
    case .timedOut:
      "Finder did not respond in time. A disconnected or stalled volume may be blocking the selected location."
    case .noLocation:
      "Select a local file or folder, or open a Finder window for the project you want to use."
    case .inaccessibleLocation:
      "The selected Finder item does not expose an accessible local file URL."
    case .queryFailed(let detail):
      "Finder could not provide its current selection. \(detail)"
    }
  }
}

enum FinderSelection {
  // This source is constant: no selected path is ever interpolated into it.
  // Selection intentionally wins over the front window target.
  static let locationScript = """
    with timeout of 3 seconds
        tell application "Finder"
            if (count of selection) > 0 then
                set targetItem to item 1 of selection
            else if (count of Finder windows) > 0 then
                set targetItem to target of front Finder window
            else
                return ""
            end if

            return URL of targetItem
        end tell
    end timeout
    """

  static func resolveURL() async -> Result<URL, FinderSelectionError> {
    do {
      // The long outer timeout leaves time for the first-run TCC prompt;
      // the Apple Event itself still has a three-second Finder timeout.
      let result = try await ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
        arguments: ["-e", locationScript],
        timeout: 60
      )

      let output = result.standardOutput.trimmingCharacters(in: .newlines)
      if result.terminationStatus == 0, !output.isEmpty {
        guard let url = URL(string: output), url.isFileURL else {
          return .failure(.inaccessibleLocation)
        }
        return .success(url)
      }

      if result.timedOut {
        return .failure(.timedOut)
      }

      let errorText = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
      if errorText.contains("(-1743)") {
        return .failure(.automationDenied)
      }
      if errorText.contains("(-1712)") {
        return .failure(.timedOut)
      }
      if result.terminationStatus == 0 {
        return .failure(.noLocation)
      }

      let detail =
        errorText.isEmpty
        ? "The query exited with status \(result.terminationStatus)."
        : errorText
      return .failure(.queryFailed(detail))
    } catch {
      return .failure(.queryFailed(error.localizedDescription))
    }
  }

  static func urlFromLaunchArguments(
    _ arguments: [String] = CommandLine.arguments,
    fileManager: FileManager = .default
  ) -> URL? {
    for argument in arguments.dropFirst() {
      guard !argument.hasPrefix("-psn_") else { continue }
      guard !argument.hasPrefix("--") else { continue }

      let url: URL
      if let parsed = URL(string: argument), parsed.isFileURL {
        url = parsed
      } else {
        url = URL(fileURLWithPath: argument)
      }

      if fileManager.fileExists(atPath: url.path) {
        return url
      }
    }
    return nil
  }
}
