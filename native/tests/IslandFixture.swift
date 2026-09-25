import ActivityKit
import UIKit

/// Real ActivityKit lifecycle and production subtitle pipeline, synthetic cloud.
/// The session creates and owns its activity, exactly as the broadcast extension
/// will. This still does not establish ReplayKit extension behavior on device.
@MainActor final class IslandFixture {
  private var session: BroadcastIslandSession?

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
