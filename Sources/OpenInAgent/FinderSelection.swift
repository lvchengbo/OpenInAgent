import Foundation

enum FinderSelection {
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
