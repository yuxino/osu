import ActivityKit
import UIKit

/// Real ActivityKit lifecycle and production subtitle pipeline, synthetic cloud.
/// This does not establish cross-process ReplayKit access on a physical device.
@MainActor final class IslandFixture {
  private var host: SubtitleActivity?
  private var session: BroadcastIslandSession?
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
