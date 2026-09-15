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
}
