import Foundation

/// Toolbar buttons are global; they must not register volumes as sync roots
/// just to obtain a selection. A nil target is resolved by the host in Finder.
enum FinderToolbarRequest: Equatable, Sendable {
  case openAgent(AgentID, targetURL: URL? = nil)
  case copyPath
  case openConfigFile

  var endpoint: FinderHandoffEndpoint {
    switch self {
    case .openAgent, .openConfigFile: .agent
    case .copyPath: .copyPath
    }
  }
}

enum FinderHandoffEndpoint: String, Sendable {
  case agent = "launch"
  case copyPath = "copy-path"

  var extensionBundleIdentifier: String {
    switch self {
    case .agent: "com.lvchengbo.openinagent.finderextension"
    case .copyPath: "com.lvchengbo.openinagent.copypath.finderextension"
    }
  }
}
