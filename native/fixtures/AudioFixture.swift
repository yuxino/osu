import UIKit
import AVFoundation

@main
final class AudioFixtureApp: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    let w = UIWindow(frame: UIScreen.main.bounds); w.rootViewController = AudioFixtureController(); w.makeKeyAndVisible(); window = w; return true
  }
}
final class AudioFixtureController: UIViewController {
  let synthesizer = AVSpeechSynthesizer()
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .white
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 30; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30), stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    let title = UILabel(); title.text = "Independent audio test"; title.font = .systemFont(ofSize: 26, weight: .bold); title.numberOfLines = 0; title.textColor = .black; stack.addArrangedSubview(title)
    let body = UILabel(); body.text = "This is a separate native app.\nIt plays a fixed English passage.\nNo microphone, network or personal data."; body.numberOfLines = 0; body.textColor = .darkGray; stack.addArrangedSubview(body)
    let play = UIButton(type: .system); play.setTitle("Play English passage", for: .normal); play.addTarget(self, action: #selector(start), for: .touchUpInside); stack.addArrangedSubview(play)
    let stop = UIButton(type: .system); stop.setTitle("Stop audio", for: .normal); stop.addTarget(self, action: #selector(end), for: .touchUpInside); stack.addArrangedSubview(stop)
    let picture = UIButton(type: .system); picture.setTitle("测试字幕小窗", for: .normal); picture.addTarget(self, action: #selector(openPicture), for: .touchUpInside); stack.addArrangedSubview(picture)
  }
  @objc func start() {
    do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers]); try AVAudioSession.sharedInstance().setActive(true) } catch { return }
    synthesizer.stopSpeaking(at: .immediate)
    for _ in 0..<3 {
      let u = AVSpeechUtterance(string: "Hello. This sound is coming from a different application. Today we are testing live subtitles on an iPhone. The sky is blue and the weather is warm. Please remember to take a bottle of water when you go outside. We want to read the English words and the Chinese translation while this application is playing.")
      u.voice = AVSpeechSynthesisVoice(language: "en-US"); u.rate = 0.42; u.postUtteranceDelay = 2; synthesizer.speak(u)
    }
  }
  @objc func end() { synthesizer.stopSpeaking(at: .immediate) }
  @objc func openPicture() {
    end(); let page = PictureFixtureController(); page.modalPresentationStyle = .fullScreen; present(page, animated: true)
  }
}

// Physical-device PiP check using the production renderer. No ReplayKit,
// provider credential, network request or captured content is involved.
final class PictureFixtureController: UIViewController {
  private let picture = SubtitlePicture()
  private let status = UILabel(), details = UILabel()
  private var timer: Timer?
  private var events: [[String: Any]] = []
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .systemBackground
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 24; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)])
    let title = UILabel(); title.text = "Osu 字幕小窗测试"; title.font = .systemFont(ofSize: 26, weight: .semibold); stack.addArrangedSubview(title)
    picture.original = "こんにちは。今日はいい天気です。"; picture.translated = "你好，今天天气很好。"
    stack.addArrangedSubview(picture.preview); picture.preview.heightAnchor.constraint(equalTo: picture.preview.widthAnchor, multiplier: 0.6).isActive = true
    status.numberOfLines = 0; status.text = "固定示例文字，不采集音频。"; stack.addArrangedSubview(status)
    for (title, action) in [("打开字幕小窗", #selector(startPicture)), ("停止小窗", #selector(stopPicture)), ("返回", #selector(close))] {
      let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.addTarget(self, action: action, for: .touchUpInside); stack.addArrangedSubview(button)
    }
    details.numberOfLines = 0; details.font = .monospacedSystemFont(ofSize: 12, weight: .regular); stack.addArrangedSubview(details)
    picture.onStatus = { [weak self] text in self?.status.text = text }
    picture.onEvent = { [weak self] event, error in
      guard let self else { return }
      var row: [String: Any] = ["event": event, "timestamp": ISO8601DateFormatter().string(from: Date())]
      if let error { row["errorCode"] = (error as NSError).code }
      self.events.append(row); self.events = Array(self.events.suffix(40)); self.writeStatus()
    }
    picture.onClosed = { [weak self] in self?.stopPicture() }
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.writeStatus() }
    picture.showStill(); writeStatus()
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); picture.layout() }
  deinit { timer?.invalidate() }
  @objc private func startPicture() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers]); try AVAudioSession.sharedInstance().setActive(true)
      picture.start(); writeStatus()
    } catch { status.text = "Audio session failed: \((error as NSError).code)" }
  }
  @objc private func stopPicture() { picture.stop(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); writeStatus() }
  @objc private func close() { stopPicture(); timer?.invalidate(); dismiss(animated: true) }
  private func writeStatus() {
    var state = picture.diagnostics.filter { ["possible", "supported", "frames", "mediaCreated", "layerStatus"].contains($0.key) }
    state["active"] = picture.active; state["foreground"] = UIApplication.shared.applicationState == .active; state["attached"] = picture.preview.window != nil
    state["width"] = picture.preview.bounds.width; state["height"] = picture.preview.bounds.height
    details.text = "possible: \(state["possible"]!) · active: \(picture.active)\nframes: \(state["frames"]!) · layer: \(state["layerStatus"]!)"
    let document: [String: Any] = ["timestamp": ISO8601DateFormatter().string(from: Date()), "state": state, "events": events, "scope": "Production PiP renderer, fixed text only; no capture or cloud"]
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("picture-status.json")
    if let data = try? JSONSerialization.data(withJSONObject: document) { try? data.write(to: url, options: .atomic) }
  }
}
