import Darwin
import Foundation

enum AgentHandoffStoreError: Error {
  case invalidActivationURL
  case invalidRequest
  case unavailableStore
  case couldNotCreateRecord
  case couldNotClaimRecord
}

struct AgentHandoffStore {
  private static let recordVersion = 2
  private static let maximumRecordSize = 16 * 1024
  private static let maximumAge: TimeInterval = 60
  private static let maximumFutureSkew: TimeInterval = 5
  private static let cleanupAge: TimeInterval = 5 * 60
  private static let cleanupLimit = 64

  private let directoryURL: URL
  private let endpoint: FinderHandoffEndpoint
  private let clock: () -> Date

  init(
    directoryURL: URL,
    endpoint: FinderHandoffEndpoint = .agent,
    clock: @escaping () -> Date = Date.init
  ) {
    self.directoryURL = directoryURL.standardizedFileURL
    self.endpoint = endpoint
    self.clock = clock
  }

  static func finderExtension(
    endpoint: FinderHandoffEndpoint = .agent,
    fileManager: FileManager = .default,
    clock: @escaping () -> Date = Date.init
  ) throws -> AgentHandoffStore {
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return AgentHandoffStore(
      directoryURL:
        applicationSupport
        .appendingPathComponent("OpenInAgent", isDirectory: true)
        .appendingPathComponent("Handoffs", isDirectory: true),
      endpoint: endpoint,
      clock: clock
    )
  }

  static func containingApplication(
    endpoint: FinderHandoffEndpoint = .agent,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    clock: @escaping () -> Date = Date.init
  ) -> AgentHandoffStore {
    AgentHandoffStore(
      directoryURL:
        homeDirectory
        .appendingPathComponent("Library/Containers", isDirectory: true)
        .appendingPathComponent(endpoint.extensionBundleIdentifier, isDirectory: true)
        .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
        .appendingPathComponent("OpenInAgent", isDirectory: true)
        .appendingPathComponent("Handoffs", isDirectory: true),
      endpoint: endpoint,
      clock: clock
    )
  }

  func create(_ request: AgentLaunchRequest) throws -> URL {
    try create(.openAgent(request.agentID, targetURL: request.targetURL))
  }

  func create(_ request: FinderToolbarRequest) throws -> URL {
    guard request.endpoint == endpoint else {
      throw AgentHandoffStoreError.invalidRequest
    }

    let action: String
    let agent: String?
    let target: String?
    switch request {
    case .openAgent(let agentID, let targetURL):
      action = "openAgent"
      agent = agentID.rawValue
      if let targetURL {
        guard let validated = AgentLaunchRequest.validatedTargetURL(targetURL) else {
          throw AgentHandoffStoreError.invalidRequest
        }
        target = validated.absoluteString
      } else {
        target = nil
      }
    case .copyPath:
      action = "copyPath"
      agent = nil
      target = nil
    }

    try prepareDirectoryForWriting()
    cleanupExpiredRecords()

    for _ in 0..<4 {
      let token = UUID()
      let record = Record(
        version: Self.recordVersion,
        token: token.uuidString,
        createdAt: clock().timeIntervalSince1970,
        action: action,
        agent: agent,
        target: target
      )
      let data = try JSONEncoder().encode(record)
      guard data.count <= Self.maximumRecordSize else {
        throw AgentHandoffStoreError.invalidRequest
      }

      let recordURL = requestURL(for: token)
      if try createExclusiveFile(at: recordURL, data: data) {
        return activationURL(for: token)
      }
    }

    throw AgentHandoffStoreError.couldNotCreateRecord
  }

  func consume(_ activationURL: URL) throws -> FinderToolbarRequest {
    guard let token = token(from: activationURL) else {
      throw AgentHandoffStoreError.invalidActivationURL
    }
    try validateExistingDirectory()
    cleanupExpiredRecords()

    let requestURL = requestURL(for: token)
    let claimedURL = claimedURL(for: token)
    guard Darwin.link(requestURL.path, claimedURL.path) == 0 else {
      throw AgentHandoffStoreError.couldNotClaimRecord
    }

    guard Darwin.unlink(requestURL.path) == 0 else {
      Darwin.unlink(claimedURL.path)
      throw AgentHandoffStoreError.couldNotClaimRecord
    }
    defer { Darwin.unlink(claimedURL.path) }

    let data = try readValidatedRecord(at: claimedURL)
    let record = try JSONDecoder().decode(Record.self, from: data)
    let age = clock().timeIntervalSince1970 - record.createdAt

    guard
      record.version == Self.recordVersion,
      record.token == token.uuidString,
      age >= -Self.maximumFutureSkew,
      age <= Self.maximumAge
    else {
      throw AgentHandoffStoreError.invalidRequest
    }

    switch (endpoint, record.action) {
    case (.agent, "openAgent"):
      guard let agent = record.agent, let agentID = AgentID(rawValue: agent) else {
        throw AgentHandoffStoreError.invalidRequest
      }
      let targetURL: URL?
      if let target = record.target {
        guard
          let rawURL = URL(string: target),
          let validated = AgentLaunchRequest.validatedTargetURL(rawURL)
        else {
          throw AgentHandoffStoreError.invalidRequest
        }
        targetURL = validated
      } else {
        targetURL = nil
      }
      return .openAgent(agentID, targetURL: targetURL)
    case (.copyPath, "copyPath") where record.agent == nil && record.target == nil:
      return .copyPath
    default:
      throw AgentHandoffStoreError.invalidRequest
    }
  }

  private func activationURL(for token: UUID) -> URL {
    var components = URLComponents()
    components.scheme = AgentLaunchRequest.scheme
    components.host = endpoint.rawValue
    components.path = "/\(token.uuidString)"
    return components.url!
  }

  private func token(from activationURL: URL) -> UUID? {
    guard
      let components = URLComponents(
        url: activationURL,
        resolvingAgainstBaseURL: false
      ),
      components.scheme?.lowercased() == AgentLaunchRequest.scheme,
      components.host?.lowercased() == endpoint.rawValue,
      components.user == nil,
      components.password == nil,
      components.port == nil,
      components.query == nil,
      components.fragment == nil,
      components.path.first == "/",
      components.path.dropFirst().contains("/") == false
    else {
      return nil
    }

    let value = String(components.path.dropFirst())
    guard
      components.percentEncodedPath == "/\(value)",
      let token = UUID(uuidString: value),
      value == token.uuidString
    else {
      return nil
    }
    return token
  }

  private func requestURL(for token: UUID) -> URL {
    directoryURL.appendingPathComponent(
      "\(token.uuidString).request",
      isDirectory: false
    )
  }

  private func claimedURL(for token: UUID) -> URL {
    directoryURL.appendingPathComponent(
      "\(token.uuidString).claimed",
      isDirectory: false
    )
  }

  private func prepareDirectoryForWriting() throws {
    do {
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      throw AgentHandoffStoreError.unavailableStore
    }

    // Check the leaf before repairing permissions, and never follow a symlink
    // if the path is replaced between this check and the permission change.
    var status = stat()
    guard
      Darwin.lstat(directoryURL.path, &status) == 0,
      status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == Darwin.geteuid(),
      Darwin.fchmodat(AT_FDCWD, directoryURL.path, 0o700, AT_SYMLINK_NOFOLLOW) == 0
    else {
      throw AgentHandoffStoreError.unavailableStore
    }
    try validateExistingDirectory()
  }

  private func validateExistingDirectory() throws {
    var status = stat()
    guard
      Darwin.lstat(directoryURL.path, &status) == 0,
      status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == Darwin.geteuid(),
      status.st_mode & 0o077 == 0
    else {
      throw AgentHandoffStoreError.unavailableStore
    }
  }

  private func createExclusiveFile(
    at url: URL,
    data: Data
  ) throws -> Bool {
    let descriptor = Darwin.open(
      url.path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
      0o600
    )
    if descriptor < 0 {
      if errno == EEXIST { return false }
      throw AgentHandoffStoreError.couldNotCreateRecord
    }
    defer { Darwin.close(descriptor) }

    // O_CREAT's mode is masked by the process umask, so pin the record to
    // exactly 0600. A restrictive session umask could otherwise create an
    // unreadable record and make every handoff fail.
    guard Darwin.fchmod(descriptor, 0o600) == 0 else {
      Darwin.unlink(url.path)
      throw AgentHandoffStoreError.couldNotCreateRecord
    }

    do {
      try write(data, to: descriptor)
      guard Darwin.fsync(descriptor) == 0 else {
        throw AgentHandoffStoreError.couldNotCreateRecord
      }
    } catch {
      Darwin.unlink(url.path)
      throw error
    }
    return true
  }

  private func write(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      var offset = 0

      while offset < bytes.count {
        let count = Darwin.write(
          descriptor,
          baseAddress.advanced(by: offset),
          bytes.count - offset
        )
        if count < 0 {
          if errno == EINTR { continue }
          throw AgentHandoffStoreError.couldNotCreateRecord
        }
        offset += count
      }
    }
  }

  private func readValidatedRecord(at url: URL) throws -> Data {
    // Reject special files after opening without waiting for a FIFO writer or
    // device. Regular files retain the same descriptor-based validation below.
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else {
      throw AgentHandoffStoreError.invalidRequest
    }
    defer { Darwin.close(descriptor) }

    var status = stat()
    guard
      Darwin.fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == Darwin.geteuid(),
      status.st_mode & 0o077 == 0,
      status.st_size > 0,
      status.st_size <= Self.maximumRecordSize
    else {
      throw AgentHandoffStoreError.invalidRequest
    }

    var data = Data(count: Int(status.st_size))
    let bytesRead = try data.withUnsafeMutableBytes { bytes -> Int in
      guard let baseAddress = bytes.baseAddress else { return 0 }
      var offset = 0

      while offset < bytes.count {
        let count = Darwin.read(
          descriptor,
          baseAddress.advanced(by: offset),
          bytes.count - offset
        )
        if count < 0 {
          if errno == EINTR { continue }
          throw AgentHandoffStoreError.invalidRequest
        }
        if count == 0 { break }
        offset += count
      }
      return offset
    }

    guard bytesRead == data.count else {
      throw AgentHandoffStoreError.invalidRequest
    }
    return data
  }

  private func cleanupExpiredRecords() {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }

    let expiration = clock().timeIntervalSince1970 - Self.cleanupAge
    var inspected = 0
    for entry in entries {
      guard inspected < Self.cleanupLimit else { break }
      guard Self.isHandoffFilename(entry.lastPathComponent) else { continue }
      inspected += 1

      var status = stat()
      guard Darwin.lstat(entry.path, &status) == 0 else { continue }
      if TimeInterval(status.st_mtimespec.tv_sec) < expiration {
        Darwin.unlink(entry.path)
      }
    }
  }

  private static func isHandoffFilename(_ name: String) -> Bool {
    let suffix: String
    if name.hasSuffix(".request") {
      suffix = ".request"
    } else if name.hasSuffix(".claimed") {
      suffix = ".claimed"
    } else {
      return false
    }

    let tokenValue = String(name.dropLast(suffix.count))
    guard let token = UUID(uuidString: tokenValue) else { return false }
    return tokenValue == token.uuidString
  }
}

private struct Record: Codable {
  let version: Int
  let token: String
  let createdAt: TimeInterval
  let action: String
  let agent: String?
  let target: String?
}
