import Darwin
import Foundation

/// The user's login shell, used to wrap an agent launch so the agent inherits
/// the same environment it would get when typed into a terminal.
///
/// Terminals hand our command to `login(1)`, which executes it directly. That
/// skips `~/.zprofile`, `~/.zshrc`, and friends, so `PATH` never gains Homebrew,
/// nvm, or `~/.local/bin`, and anything the agent spawns (for example Claude
/// Code hooks that call `node`) fails. Running the agent through an interactive
/// login shell restores that environment.
///
/// The shell program is a constant. Selected paths and executables travel only
/// as separate argv entries, never as text the shell parses.
struct LoginShell: Equatable, Sendable {
  enum Dialect: Equatable, Sendable {
    case posix
    case fish
  }

  static let fallbackShellPath = "/bin/zsh"
  static let argumentZero = "open-in-agent"

  private static let posixShellNames: Set<String> = [
    "sh", "bash", "zsh", "ksh", "dash", "ash", "mksh",
  ]

  let executableURL: URL
  let dialect: Dialect

  init?(shellPath: String, fileManager: FileManager = .default) {
    guard shellPath.hasPrefix("/") else { return nil }

    let url = URL(fileURLWithPath: shellPath).standardizedFileURL
    guard let dialect = Self.dialect(forShellNamed: url.lastPathComponent) else {
      return nil
    }

    let target = url.resolvingSymlinksInPath()
    guard fileManager.isExecutableFile(atPath: target.path) else { return nil }
    let values = try? target.resourceValues(forKeys: [.isRegularFileKey])
    guard values?.isRegularFile == true else { return nil }

    self.executableURL = url
    self.dialect = dialect
  }

  /// Resolves the current user's login shell from the account record, then the
  /// `SHELL` variable, then macOS's default `/bin/zsh`.
  static func current(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> LoginShell {
    var candidates: [String] = []
    if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
      candidates.append(String(cString: shell))
    }
    if let shell = environment["SHELL"] {
      candidates.append(shell)
    }
    candidates.append(fallbackShellPath)

    for candidate in candidates {
      if let shell = LoginShell(shellPath: candidate, fileManager: fileManager) {
        return shell
      }
    }

    // /bin/zsh ships with macOS. Reaching this point means the file system is
    // in an unexpected state; the launch will surface a clear error later.
    return LoginShell(
      executableURL: URL(fileURLWithPath: fallbackShellPath),
      dialect: .posix
    )
  }

  private init(executableURL: URL, dialect: Dialect) {
    self.executableURL = executableURL
    self.dialect = dialect
  }

  static func dialect(forShellNamed name: String) -> Dialect? {
    if posixShellNames.contains(name) { return .posix }
    if name == "fish" { return .fish }
    return nil
  }

  /// The constant program handed to the shell's `-c`. It only replaces the
  /// shell with the argv that follows it.
  var program: String {
    switch dialect {
    case .posix:
      "exec \"$@\""
    case .fish:
      "exec $argv"
    }
  }

  /// Full argv: interactive login shell, constant program, then `command`.
  func arguments(executing command: [String]) -> [String] {
    precondition(!command.isEmpty, "A command is required")
    switch dialect {
    case .posix:
      return [executableURL.path, "-l", "-i", "-c", program, Self.argumentZero] + command
    case .fish:
      return [executableURL.path, "-l", "-i", "-c", program] + command
    }
  }
}
