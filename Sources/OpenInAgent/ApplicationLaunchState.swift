import Foundation

enum ApplicationLaunchDecision: Equatable {
  case launch(URL?)
  case rejectInvalidRequest
}

struct ApplicationLaunchState {
  private var hasFinishedLaunching = false
  private var hasEmittedDecision = false
  private var pendingURL: URL?
  private var hasInvalidPendingRequest = false

  mutating func didFinishLaunching(
    isDefaultLaunch: Bool
  ) -> ApplicationLaunchDecision? {
    hasFinishedLaunching = true

    if hasInvalidPendingRequest {
      return emit(.rejectInvalidRequest)
    }
    if let pendingURL {
      return emit(.launch(pendingURL))
    }
    if isDefaultLaunch {
      return emit(.launch(nil))
    }
    return nil
  }

  mutating func receive(
    urls: [URL]
  ) -> ApplicationLaunchDecision? {
    guard !hasEmittedDecision else { return nil }
    guard
      pendingURL == nil,
      urls.count == 1,
      let handoffURL = urls.first
    else {
      hasInvalidPendingRequest = true
      return hasFinishedLaunching ? emit(.rejectInvalidRequest) : nil
    }

    pendingURL = handoffURL
    return hasFinishedLaunching ? emit(.launch(handoffURL)) : nil
  }

  /// Called when the startup grace period ends. A launch that is neither a
  /// default launch nor followed by an activation URL (printing, state
  /// restoration, a URL that never arrives) would otherwise leave the
  /// windowless accessory app running forever, so it is rejected instead.
  /// Does nothing once any decision has been made.
  mutating func startupDeadlineExpired() -> ApplicationLaunchDecision? {
    guard hasFinishedLaunching else { return nil }
    return emit(.rejectInvalidRequest)
  }

  private mutating func emit(
    _ decision: ApplicationLaunchDecision
  ) -> ApplicationLaunchDecision? {
    guard !hasEmittedDecision else { return nil }
    hasEmittedDecision = true
    return decision
  }
}
