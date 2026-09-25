import ActivityKit
import Foundation

@MainActor final class SubtitleActivity {
  private(set) var activity: Activity<SubtitleActivityAttributes>?
  private var observation: Task<Void, Never>?
  var onEnded: (() -> Void)?
  var onContent: ((SubtitleActivityAttributes.ContentState) -> Void)?

  init() {
    let abandoned = Activity<SubtitleActivityAttributes>.activities
    Task { for activity in abandoned { await activity.end(nil, dismissalPolicy: .immediate) } }
  }
  func start(showsOriginal: Bool) throws -> String {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw Failure.disabled }
    let state = SubtitleActivityAttributes.ContentState(original: "", translated: "等待声音", status: "等待广播", showsOriginal: showsOriginal)
    let activity = try Activity.request(attributes: SubtitleActivityAttributes(sessionID: UUID().uuidString), content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)), pushType: nil)
    self.activity = activity
    observation = Task { [weak self] in
      for await content in activity.contentUpdates {
        guard !Task.isCancelled, let self, self.activity?.id == activity.id else { return }
        self.onContent?(content.state)
      }
    }
    return activity.id
  }
  func check() {
    guard let activity else { return }
    if activity.activityState == .ended || activity.activityState == .dismissed { onEnded?() }
    else { onContent?(activity.content.state) }
  }
  func stop() {
    observation?.cancel(); observation = nil
    guard let activity else { return }; self.activity = nil
    Task { await activity.end(nil, dismissalPolicy: .immediate) }
  }
  enum Failure: Error { case disabled }
}
