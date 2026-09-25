import ActivityKit
import Foundation

// Runs in ReplayKit's process, so subtitle updates do not depend on the host
// staying awake or on a hidden PiP / silent audio keepalive.
@MainActor final class BroadcastIslandSession {
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
    client = makeClient?() ?? AlibabaClient()
    let activities = Activity<SubtitleActivityAttributes>.activities
    guard let activity = activities.first(where: { $0.id == configuration.activityID }) else {
      DiagnosticStore.shared.record("island", "activity_unavailable")
      throw IslandConfiguration.Failure.invalid
    }
    DiagnosticStore.shared.record("island", "extension_attached")
    self.activity = activity
    state = .init(original: "", translated: "等待翻译", status: "正在连接", showsOriginal: configuration.showsOriginal)
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
