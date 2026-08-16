import Foundation

enum ExecutableResolver {
  private static let standardSearchDirectories = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
  ]

  static func resolve(
    _ specification: AgentSpec,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) -> ResolvedAgent {
    let preferred = specification.preferredRelativePaths.map {
      homeDirectory.appendingPathComponent($0).standardizedFileURL
    }

    var seen = Set<String>()
    let searchDirectories =
      standardSearchDirectories
      .filter { seen.insert($0).inserted }
      .map { URL(fileURLWithPath: $0, isDirectory: true) }

    let fallback = searchDirectories.map {
      $0.appendingPathComponent(specification.executableName).standardizedFileURL
    }

    let executableURL = (preferred + fallback).lazy.compactMap {
      canonicalExecutableURL($0, fileManager: fileManager)
    }.first

    return ResolvedAgent(
      specification: specification,
      executableURL: executableURL
    )
  }

  static func resolveAll() -> [ResolvedAgent] {
    AgentCatalog.all.map { resolve($0) }
  }

  private static func canonicalExecutableURL(
    _ url: URL,
    fileManager: FileManager
  ) -> URL? {
    let target = url.resolvingSymlinksInPath()
    guard fileManager.isExecutableFile(atPath: target.path) else { return nil }
    let values = try? target.resourceValues(forKeys: [.isRegularFileKey])
    return values?.isRegularFile == true ? target : nil
  }
}
