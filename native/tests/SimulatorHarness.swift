import UIKit
import Network
import AVFoundation
import ReplayKit
import AVKit

@main
final class SimulatorHarness: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private let receiver = AudioReceiver()
  private var client: NWConnection?
  private let cloudFixture = CloudFixture()
  private let lifecycle = CloudLifecycleFixture()
  private let cloudUI = CloudUIFixture()
  private let interactions = InteractionFixture()
  private let captureStartup = CaptureStartupFixture()
  private let sessionFinish = SessionFinishFixture()
  private let endurance = StreamEnduranceFixture()
  private let sample = CloudSampleTest()
  private var completed = false
  private let queue = DispatchQueue(label: "mimi.simulator.tests")
  func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    let w = UIWindow(frame: UIScreen.main.bounds)
    let arguments = ProcessInfo.processInfo.arguments
    let category = AVAudioSession.sharedInstance().category, mode = AVAudioSession.sharedInstance().mode
    let backgroundFinish = arguments.contains("--verify-background-finish") || arguments.contains("--verify-background-timeout")
    let stream = arguments.contains("--verify-stream-smoke") || arguments.contains("--verify-stream-endurance")
    let motion = arguments.contains("--verify-motion") || arguments.contains("--verify-reduced-motion")
    if motion { w.rootViewController = UIViewController() }
    else if arguments.contains("--verify-interactions") || arguments.contains("--interactions-ui") { w.rootViewController = interactions.controller() }
    else if arguments.contains("--broadcast-ui") { w.rootViewController = cloudUI.controller(ready: true, systemPicker: true) }
    else if stream { w.rootViewController = endurance.controller() }
    else if arguments.contains("--verify-session-finish") || backgroundFinish { w.rootViewController = sessionFinish.controller(systemBackground: backgroundFinish) }
    else if arguments.contains("--lyrics-ui") { w.rootViewController = LyricsDemoController() }
    else { w.rootViewController = arguments.contains("--capture-ui") || arguments.contains("--verify-capture-start") ? cloudUI.controller(ready: true) : (arguments.contains("--cloud-ui") ? cloudUI.controller() : MimiPrototypeController()) }
    w.makeKeyAndVisible(); window = w
    if arguments.contains("--broadcast-ui") {
      func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
      let events = descendants(w.rootViewController!.view).compactMap { $0 as? RPSystemBroadcastPickerView }.flatMap { $0.subviews.compactMap { $0 as? UIButton } }.map { $0.allControlEvents.rawValue }
      let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("broadcast-control.json")
      if let data = try? JSONSerialization.data(withJSONObject: ["events": events, "touchUpInside": UIControl.Event.touchUpInside.rawValue]) { try? data.write(to: url, options: .atomic) }
    }
    if motion, let view = w.rootViewController?.view { MotionFixture.run(in: view, reduced: arguments.contains("--verify-reduced-motion")) { [weak self] ok, result in self?.finish(ok, result) } }
    if arguments.contains("--verify-lyrics-layout") { let result = LyricsRenderFixture.run(); finish(result.0, result.1) }
    if arguments.contains("--export-lyrics") {
      Task { @MainActor in
        do {
          let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("lyrics-\(UUID().uuidString).mp4")
          try await LyricsClipExporter.write(to: url); self.finish(true, url.lastPathComponent)
        } catch { self.finish(false, "lyrics_export_failed") }
      }
    }
    if arguments.contains("--verify-capture-start"), let controller = w.rootViewController as? MimiPrototypeController {
      captureStartup.run(controller: controller, fixture: cloudUI) { [weak self] ok, result in self?.finish(ok, result) }
    }
    if let controller = w.rootViewController as? MimiPrototypeController {
      if arguments.contains("--verify-interactions") { interactions.run(controller) { [weak self] ok, result in self?.finish(ok, result) } }
      if stream { endurance.run(controller: controller, duration: arguments.contains("--verify-stream-endurance") ? 900 : 12) { [weak self] ok, result in self?.finish(ok, result) } }
      if arguments.contains("--verify-session-finish") { sessionFinish.run(controller: controller) { [weak self] ok, result in self?.finish(ok, result) } }
      if backgroundFinish { sessionFinish.runInBackground(controller: controller, acknowledge: arguments.contains("--verify-background-finish")) { [weak self] ok, result in self?.finish(ok, result) } }
    }
    if arguments.contains("--verify-media-idle") {
      let picture = SubtitlePicture(); picture.preview.frame = CGRect(x: 0, y: 0, width: 320, height: 192); picture.layout()
      picture.showStill(); picture.original = "Static subtitles"; picture.showStill()
      let idle = picture.diagnostics["mediaCreated"] as? Bool == false && picture.diagnostics["frames"] as? Int64 == 0
      let unchanged = category == AVAudioSession.sharedInstance().category && mode == AVAudioSession.sharedInstance().mode
      picture.start(); picture.stop(); picture.showStill()
      let stopped = picture.diagnostics["mediaCreated"] as? Bool == false
      finish(idle && unchanged && stopped, "idle_labels_do_not_register_media_and_stop_releases_source")
    }
    if ProcessInfo.processInfo.arguments.contains("--verify-transport") { verifyTransport() }
    if ProcessInfo.processInfo.arguments.contains("--verify-cloud") {
      cloudFixture.run { [weak self] ok, result in self?.finish(ok, result) }
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.finish(false, "cloud_fixture_timeout") }
    }
    if ProcessInfo.processInfo.arguments.contains("--verify-lifecycle") { lifecycle.run { [weak self] ok, result in self?.finish(ok, result) } }
    if ProcessInfo.processInfo.arguments.contains("--verify-sample") {
      sample.prepare { [weak self] data in
        let valid = data.map { $0.count > 32000 && $0.count <= 640000 && $0.count % 2 == 0 && $0.contains(where: { $0 != 0 }) } ?? false
        self?.finish(valid, valid ? "synthetic_japanese_pcm_generated" : "synthetic_japanese_unavailable")
      }
    }
    return true
  }
  private func verifyTransport() {
    receiver.onEvent = { [weak self] event, _, _ in
      guard let self else { return }
      if event == "ready" { self.connect() }
      if event == "listener_failed" { self.finish(false, "listener_failed") }
    }
    receiver.onAudio = { [weak self] data in
      guard let self else { return }
      let valid = data == Data([0, 1, 2, 3])
      self.finish(valid, valid ? "loopback_pcm_passed" : "pcm_mismatch")
    }
    do { try receiver.start() } catch { finish(false, "start_failed") }
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.finish(false, "timeout") }
  }
  private func connect() {
    let c = NWConnection(host: "127.0.0.1", port: 49371, using: .tcp); client = c
    c.stateUpdateHandler = { state in
      if case .ready = state {
        let data = try! JSONSerialization.data(withJSONObject: ["key": MimiWire.key, "audio": Data([0, 1, 2, 3]).base64EncodedString()]) + Data([10])
        c.send(content: data.prefix(7), completion: .contentProcessed { _ in c.send(content: data.dropFirst(7), completion: .contentProcessed { _ in }) })
      }
    }
    c.start(queue: queue)
  }
  private func finish(_ passed: Bool, _ result: String) {
    let record = { [self] in
      guard !completed else { return }; completed = true
      receiver.stop(); client?.cancel()
      let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("simulator-test.json")
      let data = try! JSONSerialization.data(withJSONObject: ["screenRecorderAvailable": RPScreenRecorder.shared().isAvailable, "pictureInPictureSupported": AVPictureInPictureController.isPictureInPictureSupported(), "passed": passed, "result": result, "timestamp": ISO8601DateFormatter().string(from: Date()), "scope": "Production receiver/client, fixture input only; no live Alibaba, ReplayKit or Apple model acceptance"])
      try! data.write(to: url, options: .atomic)
    }
    if Thread.isMainThread { record() } else { DispatchQueue.main.async(execute: record) }
  }
}

/// A fixed-text visual fixture. It uses the actual renderer, without capture or cloud.
final class LyricsDemoController: UIViewController {
  private let picture = SubtitlePicture()
  private var ticker: Timer?
  private var sequence = 0
  private let lines = [
    ("窓の外は、少しずつ明るくなってきた。", "窗外，正一点一点亮起来。"),
    ("今日は、いつもと違う道を歩いてみよう。", "今天，走一条不一样的路吧。"),
    ("知らない言葉も、少しずつ分かるようになる。", "陌生的话语，也会慢慢听懂。")
  ]
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .systemBackground
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 28; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 42)])
    let title = UILabel(); title.text = "Osu · 歌词字幕"; title.font = .systemFont(ofSize: 28, weight: .semibold); stack.addArrangedSubview(title)
    let note = UILabel(); note.text = "当前一句亮起，上一句轻轻退后。\n固定文字预览，不收音、不连接云端。"; note.numberOfLines = 0; note.font = .preferredFont(forTextStyle: .subheadline); note.textColor = .secondaryLabel; stack.addArrangedSubview(note)
    stack.addArrangedSubview(picture.preview); picture.preview.heightAnchor.constraint(equalTo: picture.preview.widthAnchor, multiplier: LyricsPainter.aspect).isActive = true
    let replay = UIButton(type: .system); replay.setTitle("重新播放示例", for: .normal); replay.addTarget(self, action: #selector(play), for: .touchUpInside); stack.addArrangedSubview(replay)
    play()
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); picture.layout() }
  deinit { ticker?.invalidate() }
  @objc private func play() {
    ticker?.invalidate(); sequence = 0; picture.resetLyrics(original: "", translated: "")
    nextLine()
    let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.nextLine() }; ticker = timer; RunLoop.main.add(timer, forMode: .common)
  }
  private func nextLine() {
    let (source, target) = lines[sequence % lines.count], id = "demo-\(sequence)"; sequence += 1
    picture.updateOriginal(source, id: id, final: true)
    picture.updateTranslation(target, id: id, final: true)
  }
}
