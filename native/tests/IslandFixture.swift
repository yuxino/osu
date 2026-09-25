import ActivityKit
import UIKit

/// Real ActivityKit lifecycle and production subtitle pipeline, synthetic cloud.
/// This does not establish cross-process ReplayKit access on a physical device.
@MainActor final class IslandFixture {
  private var host: SubtitleActivity?
  private var session: BroadcastIslandSession?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  func verifyUnavailableMode(_ controller: MimiPrototypeController, fixture: CloudUIFixture, completion: @escaping (Bool, String) -> Void) {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 700_000_000)
      func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
      let views = descendants(controller.view)
      guard let mode = views.first(where: { $0.accessibilityIdentifier == "home.displayMode" }) as? UISegmentedControl,
            let primary = views.first(where: { $0.accessibilityIdentifier == "home.primary" }) as? UIButton else { completion(false, "island_controls_missing"); return }
      mode.selectedSegmentIndex = 1; mode.sendActions(for: .valueChanged)
      primary.sendActions(for: .touchUpInside)
      try? await Task.sleep(nanoseconds: 500_000_000)
      let explained = descendants(controller.view).compactMap { ($0 as? UILabel)?.text }.contains { $0.contains("暂不可用") }
      let stoppedBeforeCapture = fixture.pickerRequests == 0 && fixture.sockets.isEmpty && Activity<SubtitleActivityAttributes>.activities.isEmpty
      mode.selectedSegmentIndex = 0; mode.sendActions(for: .valueChanged)
      primary.sendActions(for: .touchUpInside)
      try? await Task.sleep(nanoseconds: 500_000_000)
      let pictureStillStarts = fixture.pickerRequests == 1
      if let cancel = descendants(controller.view).first(where: { $0.accessibilityIdentifier == "home.secondary" }) as? UIButton { cancel.sendActions(for: .touchUpInside) }
      completion(explained && stoppedBeforeCapture && pictureStillStarts, "unavailable_mode_stops_before_broadcast_or_cloud_and_picture_mode_still_starts")
    }
  }

  func prepareProcessProbe() {
    Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 500_000_000)
        let host = SubtitleActivity(); self.host = host
        let id = try host.start(showsOriginal: true)
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Island process probe") { [weak self] in self?.finishProcessProbe() }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let data = try JSONSerialization.data(withJSONObject: ["activityID": id, "hostPID": ProcessInfo.processInfo.processIdentifier])
        try data.write(to: directory.appendingPathComponent("island-probe-ready.json"), options: .atomic)
        try await Task.sleep(nanoseconds: 20_000_000_000)
        finishProcessProbe()
      } catch { finishProcessProbe() }
    }
  }
  private func finishProcessProbe() {
    host?.stop(); host = nil
    if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
  }
  func run(completion: @escaping (Bool, String) -> Void) {
    Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 500_000_000)
        let host = SubtitleActivity(); self.host = host
        let id = try host.start(showsOriginal: true)
        let socket = FixtureRealtimeSocket()
        let config = IslandConfiguration(key: "fixture", activityID: id, credential: "fixture-only", source: "ja", target: "zh", showsOriginal: true)
        let session = try BroadcastIslandSession(configuration: config, makeClient: { AlibabaClient(factory: { _ in socket }) })
        self.session = session
        session.append(Data([0, 1, 2, 3]))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        guard let activity = host.activity, activity.content.state.translated == "你好", activity.content.state.original == "こんにちは", activity.content.state.showsOriginal else { throw IslandConfiguration.Failure.invalid }
        session.pause(true)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        guard activity.content.state.status == "广播已暂停" else { throw IslandConfiguration.Failure.invalid }
        session.stop(); host.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        guard socket.closed, host.activity == nil, activity.activityState == .ended || activity.activityState == .dismissed else { throw IslandConfiguration.Failure.invalid }
        self.session = nil; self.host = nil
        completion(true, "activity_subtitles_original_pause_and_immediate_cleanup_no_network")
      } catch {
        session?.stop(); host?.stop(); session = nil; host = nil
        completion(false, "island_fixture_" + String(describing: error))
      }
    }
  }
}
