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

    let state = ProcessWatchdogState(process: process)
    let watchdog = DispatchWorkItem {
      state.timeoutIfIncomplete()
    }
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + timeout,
      execute: watchdog
    )

    process.waitUntilExit()
    state.markCompleted()
    watchdog.cancel()
    readers.wait()

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

  init(fileHandle: FileHandle) {
    self.fileHandle = fileHandle
  }

  var data: Data {
    lock.withLock { capturedData }
  }

  func start(in group: DispatchGroup) {
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      let data = self.fileHandle.readDataToEndOfFile()
      self.lock.withLock {
        self.capturedData = data
      }
      group.leave()
    }
  }
}

private final class ProcessWatchdogState: @unchecked Sendable {
  private let process: Process
  private let lock = NSLock()
  private var completed = false
  private var didTimeOut = false

  init(process: Process) {
    self.process = process
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
      guard !completed, process.isRunning else { return false }
      didTimeOut = true
      return true
    }

    guard shouldTerminate else { return }
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
