import Foundation

enum FinderSelection {
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
