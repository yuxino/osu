import ActivityKit
import UIKit

/// Real ActivityKit lifecycle and production subtitle pipeline, synthetic cloud.
/// The session creates and owns its activity, exactly as the broadcast extension
/// will. This still does not establish ReplayKit extension behavior on device.
@MainActor final class IslandFixture {
  private var session: BroadcastIslandSession?

  /// Device logs at 2026-09-25 12:05:53 UTC showed the extension's
  /// Activity.request failing with ActivityAuthorizationError.visibility (a
  /// background process may not start a Live Activity). The host must stop the
  /// mode before opening broadcast, while PiP stays available.
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

  func run(completion: @escaping (Bool, String) -> Void) {
    Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 500_000_000)
        // End leftovers from an earlier crashed fixture run so matching below
        // can only see the activity this session creates.
        for abandoned in Activity<SubtitleActivityAttributes>.activities {
          await abandoned.end(nil, dismissalPolicy: .immediate)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw IslandConfiguration.Failure.invalid }
        let socket = FixtureRealtimeSocket()
        let config = IslandConfiguration(key: "fixture", credential: "fixture-only", source: "ja", target: "zh", showsOriginal: true)
        let session = try BroadcastIslandSession(configuration: config, makeClient: { AlibabaClient(factory: { _ in socket }) })
        self.session = session
        session.append(Data([0, 1, 2, 3]))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        guard let activity = Activity<SubtitleActivityAttributes>.activities.first(where: { $0.content.state.translated == "你好" }),
              activity.content.state.original == "こんにちは", activity.content.state.showsOriginal else { throw IslandConfiguration.Failure.invalid }
        session.pause(true)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        guard activity.content.state.status == "广播已暂停" else { throw IslandConfiguration.Failure.invalid }
        session.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        guard socket.closed, activity.activityState == .ended || activity.activityState == .dismissed else { throw IslandConfiguration.Failure.invalid }
        self.session = nil
        completion(true, "extension_created_activity_subtitles_original_pause_and_immediate_cleanup_no_network")
      } catch {
        session?.stop(); session = nil
        completion(false, "island_fixture_" + String(describing: error))
      }
    }
  }
}
