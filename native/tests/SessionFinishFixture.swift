import UIKit
import Network

// In-memory provider replies and authenticated loopback PCM drive the real UI,
// receiver and client. PiP is unavailable on this simulator, so only its external
// close callback is substituted. No ReplayKit, Keychain or cloud service is used.
@MainActor final class SessionFinishFixture {
  private let picture = SubtitlePicture()
  private let tasks = FixtureBackgroundTasks()
  private var sockets: [FixtureRealtimeSocket] = []
  private var connection: NWConnection?
  private var observer: NSObjectProtocol?
  private var captureClosed = false
  private var results: [String] = []

  func controller(systemBackground: Bool) -> MimiPrototypeController {
    tasks.useSystem = systemBackground
    UserDefaults.standard.set(true, forKey: "osu.automaticLanguageDefaultsV1")
    UserDefaults.standard.set("alibaba", forKey: "mimi.engine")
    UserDefaults.standard.set("auto", forKey: "mimi.alibaba.source")
    UserDefaults.standard.set("zh", forKey: "mimi.alibaba.target")
    return MimiPrototypeController(makeCloudClient: { [self] in
      let socket = FixtureRealtimeSocket(); socket.acknowledgeFinish = false; sockets.append(socket)
      return AlibabaClient(factory: { _ in socket })
    }, readCloudCredential: { "fixture-only" }, picture: picture, backgroundTasks: tasks.provider)
  }

  func run(controller: MimiPrototypeController, completion: @escaping (Bool, String) -> Void) {
    Task { @MainActor in
      do {
        try await start(controller)
        try closePicture()
        // A second close callback must leave the first finalization intact.
        picture.onClosed?()
        guard tasks.hasFinish, !sockets.last!.closed else { throw failure("duplicate_close_cancelled_finish") }
        try await wait { self.sockets.last!.sentFinish == 1 }
        sockets.last!.confirmFinish()
        try await stopped(controller)
        guard picture.translated == "这是最后一句。" else { throw failure("last_translation_lost") }
        results.append("confirmed_tail_and_duplicate_close")

        try await start(controller); try closePicture()
        try await stopped(controller, timeout: 11)
        guard labels(in: controller.view).contains(where: { $0.contains("部分末句") }) else { throw failure("timeout_not_explained") }
        results.append("server_timeout")

        try await start(controller); try closePicture()
        guard let expired = tasks.finishExpiration else { throw failure("missing_expiration") }
        expired(); try await stopped(controller)
        results.append("system_expiration")

        try await start(controller); tasks.denyFinish = true
        picture.onClosed?(); try await stopped(controller)
        guard sockets.last!.sentFinish == 0 else { throw failure("denied_task_kept_network_work") }
        tasks.denyFinish = false; results.append("background_task_denied")

        try await start(controller); try closePicture()
        guard let oldExpiration = tasks.finishExpiration else { throw failure("missing_cancel_expiration") }
        try press("立即结束", in: controller.view); try await stopped(controller)
        try await start(controller)
        oldExpiration()
        guard snapshot()["running"] as? Bool == true, !sockets.last!.closed else { throw failure("old_expiration_stopped_new_session") }
        try closePicture(); try await wait { self.sockets.last!.sentFinish == 1 }
        sockets.last!.confirmFinish(); try await stopped(controller)
        results.append("cancel_restart_ignores_old_expiration")
        completion(true, results.joined(separator: ","))
      } catch { connection?.cancel(); completion(false, (error as NSError).domain) }
    }
  }

  // The runner opens Settings after the ready marker, so this path really runs
  // while UIApplication is backgrounded. It uses actual UIKit background tasks.
  func runInBackground(controller: MimiPrototypeController, acknowledge: Bool, completion: @escaping (Bool, String) -> Void) {
    Task { @MainActor in
      do {
        try await start(controller)
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
          guard let self else { return }
          Task { @MainActor in
            if let observer = self.observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            do {
              try await Task.sleep(nanoseconds: 500_000_000)
              guard UIApplication.shared.applicationState == .background else { throw self.failure("not_backgrounded") }
              self.tasks.onFinishEnd = { [weak self] in
                guard let self else { return }
                let valid = UIApplication.shared.applicationState == .background && self.isStopped(controller) && self.tasks.releaseWasClean && (!acknowledge || self.picture.translated == "这是最后一句。")
                // Record before ending the final UIKit assertion; the app may
                // suspend immediately afterward, which is the behavior under test.
                completion(valid, acknowledge ? "background_tail_confirmed_then_released" : "background_timeout_closed_then_released")
              }
              try self.closePicture()
              if acknowledge {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                self.sockets.last!.confirmFinish()
              }
            } catch { completion(false, (error as NSError).domain) }
          }
        }
        let marker = DiagnosticStore.shared.directory.deletingLastPathComponent().appendingPathComponent("background-finish-ready.json")
        try Data("{\"ready\":true}".utf8).write(to: marker, options: .atomic)
      } catch { completion(false, (error as NSError).domain) }
    }
  }

  private func start(_ controller: MimiPrototypeController) async throws {
    try await wait { UIApplication.shared.applicationState == .active && self.button("开始听", in: controller.view) != nil }
    let count = sockets.count
    try press("开始听", in: controller.view)
    try await wait { controller.presentedViewController is CapturePermissionController }
    captureClosed = false
    let stream = NWConnection(host: "127.0.0.1", port: 49371, using: .tcp); connection = stream
    stream.start(queue: DispatchQueue(label: "osu.finish.fixture"))
    try await wait { if case .ready = stream.state { return true }; return false }
    stream.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, ended, error in
      Task { @MainActor in
        guard let self, self.connection === stream else { return }
        if ended || error != nil { self.captureClosed = true }
      }
    }
    let packet = try JSONSerialization.data(withJSONObject: ["key": MimiWire.key, "event": "started", "audio": Data([0, 1, 2, 3]).base64EncodedString()]) + Data([10])
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      stream.send(content: packet, completion: .contentProcessed { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      })
    }
    try await wait { self.sockets.count == count + 1 && self.sockets.last!.sentAudio == 1 && controller.presentedViewController == nil && self.snapshot()["running"] as? Bool == true }
  }
  private func closePicture() throws {
    picture.onClosed?()
    let state = snapshot()
    guard tasks.hasFinish, state["captureState"] as? String == "finishing", state["running"] as? Bool == false, state["pip"] as? Bool == false, !sockets.last!.closed else { throw failure("close_not_bounded_or_snapshot_still_capturing") }
  }
  private func stopped(_ controller: MimiPrototypeController, timeout: Double = 3) async throws {
    try await wait(timeout: timeout) { self.isStopped(controller) && self.captureClosed }
    guard tasks.activeCount == 0, tasks.releaseWasClean else { throw failure("background_task_released_before_cleanup_or_leaked") }
    connection?.cancel(); connection = nil
  }
  private func isStopped(_ controller: MimiPrototypeController) -> Bool {
    let state = snapshot()
    return state["running"] as? Bool == false && state["pip"] as? Bool == false && state["captureState"] as? String == "stopped" && sockets.last?.closed == true && button("开始听", in: controller.view) != nil
  }
  private func snapshot() -> [String: Any] { FixtureBackgroundTasks.snapshot() }
  private func wait(timeout: Double = 3, until condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
    guard condition() else { throw failure("state_transition_timeout") }
  }
  private func button(_ title: String, in view: UIView) -> UIButton? {
    if let button = view as? UIButton, button.configuration?.title == title, button.isEnabled { return button }
    return view.subviews.lazy.compactMap { self.button(title, in: $0) }.first
  }
  private func press(_ title: String, in view: UIView) throws {
    guard let button = button(title, in: view) else { throw failure("action_unavailable") }
    button.sendActions(for: .touchUpInside)
  }
  private func labels(in view: UIView) -> [String] { (view as? UILabel).flatMap { $0.text }.map { [$0] } ?? view.subviews.flatMap { labels(in: $0) } }
  private func failure(_ name: String) -> NSError { NSError(domain: name, code: 1) }
}

@MainActor private final class FixtureBackgroundTasks {
  var useSystem = false, denyFinish = false
  var onFinishEnd: (() -> Void)?
  private var sequence = 0
  private var active: [UIBackgroundTaskIdentifier: (name: String, expiration: BackgroundTaskProvider.ExpirationHandler)] = [:]
  private(set) var releaseWasClean = true
  var activeCount: Int { active.count }
  var hasFinish: Bool { finishExpiration != nil }
  var finishExpiration: BackgroundTaskProvider.ExpirationHandler? { active.values.first { $0.name == "Finish Osu subtitles" }?.expiration }
  var provider: BackgroundTaskProvider {
    BackgroundTaskProvider(begin: { [unowned self] name, expiration in
      if name == "Finish Osu subtitles" && denyFinish { return .invalid }
      sequence += 1
      let identifier = useSystem ? BackgroundTaskProvider.application.begin(name, expiration) : UIBackgroundTaskIdentifier(rawValue: sequence)
      if identifier != .invalid { active[identifier] = (name, expiration) }
      return identifier
    }, end: { [unowned self] identifier in
      guard let task = active.removeValue(forKey: identifier) else { releaseWasClean = false; return }
      if task.name == "Finish Osu subtitles" {
        let state = Self.snapshot()
        releaseWasClean = releaseWasClean && state["running"] as? Bool == false && state["pip"] as? Bool == false && state["captureState"] as? String == "stopped"
        onFinishEnd?()
      }
      if useSystem { BackgroundTaskProvider.application.end(identifier) }
    })
  }
  static func snapshot() -> [String: Any] {
    let file = DiagnosticStore.shared.directory.deletingLastPathComponent().appendingPathComponent("probe-status.json")
    guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }
}
