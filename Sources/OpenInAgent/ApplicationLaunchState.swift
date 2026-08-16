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

  private mutating func emit(
    _ decision: ApplicationLaunchDecision
  ) -> ApplicationLaunchDecision? {
    guard !hasEmittedDecision else { return nil }
    hasEmittedDecision = true
    return decision
  }
}
