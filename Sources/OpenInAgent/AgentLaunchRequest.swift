import Foundation

struct AgentLaunchRequest: Equatable, Sendable {
  static let scheme = "openinagent"
  static let host = "launch"

  let agentID: AgentID
  let targetURL: URL

  init(agentID: AgentID, targetURL: URL) {
    self.agentID = agentID
    self.targetURL = targetURL.standardizedFileURL
  }

  static func validatedTargetURL(_ url: URL) -> URL? {
    guard
      let components = URLComponents(
        url: url,
        resolvingAgainstBaseURL: false
      ),
      components.scheme?.lowercased() == "file",
      components.user == nil,
      components.password == nil,
      components.port == nil,
      components.query == nil,
      components.fragment == nil,
      components.path.hasPrefix("/"),
      components.host == nil || components.host?.isEmpty == true,
      let validatedURL = components.url
    else {
      return nil
    }
    return validatedURL.standardizedFileURL
  }
}
