import Darwin
import Foundation

struct ProcessResult: Sendable {
  let terminationStatus: Int32
  let standardOutput: String
  let standardError: String
  let timedOut: Bool
}

enum ProcessRunnerError: LocalizedError, Sendable {
  case failedToStart(String)

  var errorDescription: String? {
    switch self {
    case .failedToStart(let message):
      "The helper process could not start: \(message)"
    }
  }
}

enum ProcessRunner {
  static func run(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]? = nil,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          continuation.resume(
            returning: try runSynchronously(
              executableURL: executableURL,
              arguments: arguments,
              environment: environment,
              timeout: timeout
            )
          )
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func runSynchronously(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]?,
    timeout: TimeInterval
  ) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    if let environment {
      process.environment = environment
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.standardInput = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw ProcessRunnerError.failedToStart(error.localizedDescription)
    }

    let stdoutReader = PipeReader(
      fileHandle: stdoutPipe.fileHandleForReading
    )
    let stderrReader = PipeReader(
      fileHandle: stderrPipe.fileHandleForReading
    )
    let readers = DispatchGroup()
    stdoutReader.start(in: readers)
    stderrReader.start(in: readers)

    let state = ProcessWatchdogState(process: process, readers: [stdoutReader, stderrReader])
    let watchdog = DispatchWorkItem {
      state.timeoutIfIncomplete()
    }
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + timeout,
      execute: watchdog
    )

    process.waitUntilExit()
    readers.wait()
    state.markCompleted()
    watchdog.cancel()

    return ProcessResult(
      terminationStatus: process.terminationStatus,
      standardOutput: String(decoding: stdoutReader.data, as: UTF8.self),
      standardError: String(decoding: stderrReader.data, as: UTF8.self),
      timedOut: state.timedOut
    )
  }
}

private final class PipeReader: @unchecked Sendable {
  private let fileHandle: FileHandle
  private let lock = NSLock()
  private var capturedData = Data()
  private var stopRequested = false

  init(fileHandle: FileHandle) {
    self.fileHandle = fileHandle
  }

  var data: Data {
    lock.withLock { capturedData }
  }

  func stop() {
    lock.withLock { stopRequested = true }
  }

  func start(in group: DispatchGroup) {
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 64 * 1024)
      var descriptor = pollfd(
        fd: self.fileHandle.fileDescriptor,
        events: Int16(POLLIN | POLLHUP),
        revents: 0
      )
      // EOF can be held open by a descendant after the direct child exits.
      // Poll in bounded intervals so the watchdog can stop output collection.
      while !self.lock.withLock({ self.stopRequested }) {
        let ready = Darwin.poll(&descriptor, 1, 25)
        if ready < 0 {
          if errno == EINTR { continue }
          break
        }
        guard ready > 0 else { continue }
        let count = buffer.withUnsafeMutableBytes { bytes in
          Darwin.read(descriptor.fd, bytes.baseAddress!, bytes.count)
        }
        if count < 0 {
          if errno == EINTR { continue }
          break
        }
        guard count > 0 else { break }
        data.append(contentsOf: buffer.prefix(count))
      }
      self.lock.withLock {
        self.capturedData = data
      }
      group.leave()
    }
  }
}

private final class ProcessWatchdogState: @unchecked Sendable {
  private let process: Process
  private let readers: [PipeReader]
  private let lock = NSLock()
  private var completed = false
  private var didTimeOut = false

  init(process: Process, readers: [PipeReader]) {
    self.process = process
    self.readers = readers
  }

  var timedOut: Bool {
    lock.withLock { didTimeOut }
  }

  func markCompleted() {
    lock.withLock {
      completed = true
    }
  }

  func timeoutIfIncomplete() {
    let shouldTerminate = lock.withLock {
      guard !completed else { return false }
      didTimeOut = true
      return true
    }

    guard shouldTerminate else { return }
    for reader in readers { reader.stop() }
    guard process.isRunning else { return }
    process.terminate()

    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + 0.25
    ) {
      self.forceKillIfIncomplete()
    }
  }

  private func forceKillIfIncomplete() {
    let processIdentifier: pid_t? = lock.withLock {
      guard !completed, process.isRunning else { return nil }
      return process.processIdentifier
    }

    if let processIdentifier {
      Darwin.kill(processIdentifier, SIGKILL)
    }
  }
}
