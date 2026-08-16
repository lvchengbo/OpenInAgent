import Foundation

enum FinderPathResolver {
  static func workingDirectory(for finderURL: URL?) -> URL? {
    guard let finderURL, var url = filePathURL(for: finderURL) else {
      return nil
    }

    let initialValues = try? url.resourceValues(
      forKeys: [.isAliasFileKey, .isSymbolicLinkKey]
    )

    if initialValues?.isAliasFile == true,
      initialValues?.isSymbolicLink != true
    {
      guard let bookmarkData = try? URL.bookmarkData(withContentsOf: url) else {
        return nil
      }

      var isStale = false
      guard
        let resolvedURL = try? URL(
          resolvingBookmarkData: bookmarkData,
          options: [.withoutUI, .withoutMounting],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        ),
        let resolvedFileURL = filePathURL(for: resolvedURL)
      else {
        return nil
      }

      url = resolvedFileURL
    }

    let path = fileSystemPath(for: url)
    guard !path.isEmpty else { return nil }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      return nil
    }

    let packageValues = try? url.resolvingSymlinksInPath().resourceValues(
      forKeys: [.isPackageKey]
    )
    let isPackage = packageValues?.isPackage == true

    let directoryPath: String
    if isDirectory.boolValue && !isPackage {
      directoryPath = path
    } else {
      directoryPath = (path as NSString).deletingLastPathComponent
    }

    guard !directoryPath.isEmpty else { return nil }
    return URL(fileURLWithPath: directoryPath, isDirectory: true).standardizedFileURL
  }

  static func filePathURL(for url: URL) -> URL? {
    guard url.isFileURL else { return nil }

    let foundationURL = url as NSURL
    if foundationURL.isFileReferenceURL() {
      return foundationURL.filePathURL
    }
    return url
  }

  static func fileSystemPath(for url: URL) -> String {
    var path = url.path(percentEncoded: false)
    while path.count > 1 && path.last == "/" {
      path.removeLast()
    }
    return (path as NSString).expandingTildeInPath
  }
}
