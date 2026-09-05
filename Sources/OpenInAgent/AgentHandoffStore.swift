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
  static let extensionBundleIdentifier =
    "com.lvchengbo.openinagent.finderextension"

  private static let recordVersion = 1
  private static let maximumRecordSize = 16 * 1024
  private static let maximumAge: TimeInterval = 60
  private static let maximumFutureSkew: TimeInterval = 5
  private static let cleanupAge: TimeInterval = 5 * 60
  private static let cleanupLimit = 64

  private let directoryURL: URL
  private let clock: () -> Date

  init(
    directoryURL: URL,
    clock: @escaping () -> Date = Date.init
  ) {
    self.directoryURL = directoryURL.standardizedFileURL
    self.clock = clock
  }

  static func finderExtension(
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
      clock: clock
    )
  }

  static func containingApplication(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    clock: @escaping () -> Date = Date.init
  ) -> AgentHandoffStore {
    AgentHandoffStore(
      directoryURL:
        homeDirectory
        .appendingPathComponent("Library/Containers", isDirectory: true)
        .appendingPathComponent(extensionBundleIdentifier, isDirectory: true)
        .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
        .appendingPathComponent("OpenInAgent", isDirectory: true)
        .appendingPathComponent("Handoffs", isDirectory: true),
      clock: clock
    )
  }

  func create(_ request: AgentLaunchRequest) throws -> URL {
    guard
      let targetURL = AgentLaunchRequest.validatedTargetURL(
        request.targetURL
      )
    else {
      throw AgentHandoffStoreError.invalidRequest
    }

    try prepareDirectoryForWriting()
    cleanupExpiredRecords()

    for _ in 0..<4 {
      let token = UUID()
      let record = Record(
        version: Self.recordVersion,
        token: token.uuidString,
        createdAt: clock().timeIntervalSince1970,
        agent: request.agentID.rawValue,
        target: targetURL.absoluteString
      )
      let data = try JSONEncoder().encode(record)
      guard data.count <= Self.maximumRecordSize else {
        throw AgentHandoffStoreError.invalidRequest
      }

      let recordURL = requestURL(for: token)
      if try createExclusiveFile(at: recordURL, data: data) {
        return Self.activationURL(for: token)
      }
    }

    throw AgentHandoffStoreError.couldNotCreateRecord
  }

  func consume(_ activationURL: URL) throws -> AgentLaunchRequest {
    guard let token = Self.token(from: activationURL) else {
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
      age <= Self.maximumAge,
      let agentID = AgentID(rawValue: record.agent),
      let rawTargetURL = URL(string: record.target),
      let targetURL = AgentLaunchRequest.validatedTargetURL(rawTargetURL)
    else {
      throw AgentHandoffStoreError.invalidRequest
    }

    return AgentLaunchRequest(agentID: agentID, targetURL: targetURL)
  }

  private static func activationURL(for token: UUID) -> URL {
    var components = URLComponents()
    components.scheme = AgentLaunchRequest.scheme
    components.host = AgentLaunchRequest.host
    components.path = "/\(token.uuidString)"
    return components.url!
  }

  private static func token(from activationURL: URL) -> UUID? {
    guard
      let components = URLComponents(
        url: activationURL,
        resolvingAgainstBaseURL: false
      ),
      components.scheme?.lowercased() == AgentLaunchRequest.scheme,
      components.host?.lowercased() == AgentLaunchRequest.host,
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

    guard Darwin.chmod(directoryURL.path, 0o700) == 0 else {
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
    let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
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
  let agent: String
  let target: String
}
