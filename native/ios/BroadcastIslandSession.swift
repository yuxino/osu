import ActivityKit
import Foundation

// Experimental broadcast-side pipeline. The extension creates and owns its own
// Live Activity because a separate process cannot look up the host's activity.
// Whether a ReplayKit extension may request activities at all still needs
// physical-device validation; failure here ends the broadcast with guidance.
@MainActor final class BroadcastIslandSession {
  enum Failure: Error { case activityUnavailable }
  private let client: AlibabaClient
  private let activity: Activity<SubtitleActivityAttributes>
  private var state: SubtitleActivityAttributes.ContentState
  private var source = LyricTrack(), translation = LyricTrack()
  private var work: Task<Void, Never>?
  private var stopped = false
  private var lastPublished = Date.distantPast
  private var dirty = true
  var onFailure: (() -> Void)?

  init(configuration: IslandConfiguration, makeClient: (() -> AlibabaClient)? = nil) throws {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      DiagnosticStore.shared.record("island", "activities_disabled")
      throw Failure.activityUnavailable
    }
    state = .init(original: "", translated: "等待翻译", status: "正在连接", showsOriginal: configuration.showsOriginal)
    do {
      activity = try Activity.request(
        attributes: SubtitleActivityAttributes(sessionID: UUID().uuidString),
        content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(15)),
        pushType: nil)
    } catch {
      DiagnosticStore.shared.record("island", "activity_request_failed", error: error)
      throw Failure.activityUnavailable
    }
    DiagnosticStore.shared.record("island", "extension_activity_started")
    client = makeClient?() ?? AlibabaClient()
    client.onReady = { [weak self] in self?.state.status = "正在听"; self?.dirty = true }
    client.onSource = { [weak self] text, id, final in
      guard let self else { return }; self.source.update(text, id: id, final: final)
      self.state.original = islandText(self.source.current?.text ?? ""); self.dirty = true
    }
    client.onTranslation = { [weak self] text, id, final in
      guard let self else { return }; self.translation.update(text, id: id, final: final)
      self.state.translated = islandText(self.translation.current?.text ?? ""); self.dirty = true
    }
    client.onFailure = { [weak self] failure in DiagnosticStore.shared.record("island", "cloud_failed", metrics: ["code": Double(failure.rawValue)]); self?.onFailure?() }
    try client.start(key: configuration.credential, source: configuration.source, target: configuration.target)
    work = Task { [weak self] in
      while !Task.isCancelled {
        guard let self, !self.stopped else { return }
        guard self.activity.activityState != .ended && self.activity.activityState != .dismissed else { self.onFailure?(); return }
        if self.dirty || Date().timeIntervalSince(self.lastPublished) >= 5 {
          self.dirty = false; self.lastPublished = Date()
          await self.activity.update(ActivityContent(state: self.state, staleDate: Date().addingTimeInterval(15)))
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
  }
  func append(_ data: Data) { guard !stopped else { return }; client.append(data) }
  func pause(_ paused: Bool) { state.status = paused ? "广播已暂停" : "正在听"; dirty = true }
  func stop() {
    guard !stopped else { return }; stopped = true; work?.cancel(); work = nil; client.stop()
    Task { await activity.end(nil, dismissalPolicy: .immediate) }
  }
}
