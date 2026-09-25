import ActivityKit
import UIKit

/// A separate simulator app runs the production broadcast-side ActivityKit lookup.
/// This tests process/bundle isolation, not the ReplayKit extension sandbox itself.
@main final class IslandProcessProbe: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var session: BroadcastIslandSession?

  func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    let controller = UIViewController(); controller.view.backgroundColor = .systemBackground
    window.rootViewController = controller; window.makeKeyAndVisible(); self.window = window
    Task { @MainActor in
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "--activity-id"), arguments.indices.contains(index + 1) else { return }
      let id = arguments[index + 1]
      var result: [String: Any] = [
        "probePID": ProcessInfo.processInfo.processIdentifier,
        "scope": "Separate simulator application process; not a ReplayKit extension",
        "visibleActivities": Activity<SubtitleActivityAttributes>.activities.count,
        "activityID": id,
        "acceptancePassed": false
      ]
      var clientCreated = false
      do {
        let configuration = IslandConfiguration(key: "fixture", activityID: id, credential: "fixture-only", source: "ja", target: "zh", showsOriginal: true)
        let socket = FixtureRealtimeSocket()
        session = try BroadcastIslandSession(configuration: configuration, makeClient: { clientCreated = true; return AlibabaClient(factory: { _ in socket }) })
        session?.append(Data([0, 1, 2, 3]))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let updated = Activity<SubtitleActivityAttributes>.activities.first { $0.id == id }?.content.state.translated == "你好"
        result["acceptancePassed"] = updated
        result["result"] = updated ? "cross_process_update_succeeded" : "cross_process_update_missing"
        session?.stop(); session = nil
      } catch BroadcastIslandSession.Failure.activityUnavailable {
        result["result"] = "activity_unavailable_in_separate_process"
        result["reproduced"] = true
      } catch {
        result["result"] = "unexpected_probe_error"
      }
      result["providerClientCreated"] = clientCreated
      let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: directory.appendingPathComponent("island-process-result.json"), options: .atomic)
      }
    }
    return true
  }
}
