import UIKit
import AVFoundation
import ReplayKit
import Speech
import SwiftUI
import Translation

private struct LanguageDownloadView: View {
  var done: (Bool, String) -> Void
  @State private var message = "准备英语 → 简体中文的本地语言包"
  var body: some View {
    VStack(spacing: 24) {
      Text("准备本地翻译").font(.title2.bold())
      Text(message).multilineTextAlignment(.center)
      Button("关闭") { done(false, "语言准备已取消") }
    }.padding(32)
    .translationTask(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "zh-Hans")) { session in
      do { try await session.prepareTranslation(); done(true, "英语 → 中文语言包已就绪") }
      catch { message = error.localizedDescription }
    }
  }
}

final class MimiPrototypeController: UIViewController {
  private let picture = SubtitlePicture()
  private let receiver = AudioReceiver()
  private let audioDelivery = DispatchSemaphore(value: 1)
  private let status = UILabel()
  private let transcript = UILabel()
  private let translation = UILabel()
  private let counts = UILabel()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognition: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var translator: TranslationSession?
  private var translationWork: Task<Void, Never>?
  private var running = false
  private var generation = 0
  private var recognitionGeneration = 0
  private var receivedFrames = 0
  private var seconds = 0.0
  private var peak = 0.0
  private var recognitionUpdates = 0
  private var translationUpdates = 0
  private var newest = ""
  private var lastTranslated = ""
  private var heartbeat: Timer?
  private var lastAudio = Date.distantPast
  private var lastRotation = Date()
  private var sessionStarted = Date()
  private var translationBusy = false
  private var lastError = ""
  private let speech = AVSpeechSynthesizer()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
    NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
    NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28), stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24)])
    let title = UILabel(); title.text = "Mimi / iPhone"; title.font = .systemFont(ofSize: 32, weight: .bold); stack.addArrangedSubview(title)
    let subtitle = UILabel(); subtitle.text = "英语 → 中文 · 真机可行性实验\n仅处理 App 声音，不保存音频或字幕。"; subtitle.font = .systemFont(ofSize: 14); subtitle.textColor = .secondaryLabel; subtitle.numberOfLines = 0; stack.addArrangedSubview(subtitle)
    stack.addArrangedSubview(picture.preview); picture.preview.heightAnchor.constraint(equalToConstant: 150).isActive = true
    status.numberOfLines = 0; status.font = .systemFont(ofSize: 15, weight: .medium); status.text = "先准备语言，然后开启小窗和屏幕广播。"; stack.addArrangedSubview(status)
    counts.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); counts.textColor = .secondaryLabel; counts.numberOfLines = 0; counts.text = "尚未收到音频"; stack.addArrangedSubview(counts)
    stack.addArrangedSubview(button("1 · 准备本地翻译", #selector(prepareLanguages)))
    stack.addArrangedSubview(button("2 · 开启字幕小窗", #selector(startPressed)))
    let broadcastRow = UIStackView(); broadcastRow.axis = .horizontal; broadcastRow.spacing = 12
    let broadcastLabel = UILabel(); broadcastLabel.text = "3 · 开始屏幕广播 →"; broadcastLabel.font = .systemFont(ofSize: 16, weight: .semibold); broadcastRow.addArrangedSubview(broadcastLabel)
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50)); picker.preferredExtension = "com.yuxino.osu.MimiBroadcast"; picker.showsMicrophoneButton = false; picker.widthAnchor.constraint(equalToConstant: 50).isActive = true; picker.heightAnchor.constraint(equalToConstant: 50).isActive = true; broadcastRow.addArrangedSubview(picker); stack.addArrangedSubview(broadcastRow)
    let explanation = UILabel(); explanation.text = "系统会询问是否广播屏幕。视频帧和麦克风声音会被丢弃。开始后切到播放英语内容的 App；受保护内容可能无法采集。"; explanation.numberOfLines = 0; explanation.font = .systemFont(ofSize: 12); explanation.textColor = .secondaryLabel; stack.addArrangedSubview(explanation)
    transcript.text = "原文等待中"; transcript.numberOfLines = 4; transcript.font = .systemFont(ofSize: 15); stack.addArrangedSubview(transcript)
    translation.text = "译文等待中"; translation.numberOfLines = 4; translation.font = .systemFont(ofSize: 19, weight: .semibold); stack.addArrangedSubview(translation)
    stack.addArrangedSubview(button("播放英语自测语音", #selector(playTest)))
    stack.addArrangedSubview(button("停止采集与字幕", #selector(stopPressed)))
    stack.addArrangedSubview(button("返回", #selector(closePressed)))
    picture.onStatus = { [weak self] text in self?.setStatus(text) }
    picture.onClosed = { [weak self] in self?.stopSession() }
    receiver.onStatus = { [weak self] text in DispatchQueue.main.async { self?.setStatus(text) } }
    receiver.onAudio = { [weak self] pcm in
      guard let self, self.audioDelivery.wait(timeout: .now()) == .success else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        defer { self.audioDelivery.signal() }
        self.consume(pcm)
      }
    }
    picture.prime()
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); picture.layout() }
  private func button(_ title: String, _ action: Selector) -> UIButton {
    let b = UIButton(type: .system); var c = UIButton.Configuration.gray(); c.title = title; c.baseForegroundColor = .label; c.cornerStyle = .medium; c.contentInsets = .init(top: 13, leading: 15, bottom: 13, trailing: 15); b.configuration = c; b.addTarget(self, action: action, for: .touchUpInside); return b
  }
  @objc private func prepareLanguages() {
    guard !running else { setStatus("请先停止当前会话再准备语言。"); return }
    let sheet = UIHostingController(rootView: LanguageDownloadView { [weak self] ok, message in
      DispatchQueue.main.async {
        guard let self else { return }
        self.dismiss(animated: true)
        if ok {
          if #available(iOS 26.0, *) { self.translator = TranslationSession(installedSource: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "zh-Hans")) }
          else { self.setStatus("本地翻译原型需要 iOS 26"); return }
        }
        self.setStatus(message)
      }
    })
    present(sheet, animated: true)
  }
  @objc private func startPressed() {
    if running { picture.start(); return }
    SFSpeechRecognizer.requestAuthorization { [weak self] permission in
      DispatchQueue.main.async {
        guard let self else { return }
        guard permission == .authorized else { self.setStatus("请在设置中允许语音识别；音频只在设备上处理。"); return }
        self.startSession()
      }
    }
  }
  private func startSession() {
    guard !running else { return }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.supportsOnDeviceRecognition else { setStatus("英语本地识别暂不可用，请先在系统中准备英语语音资源。"); return }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
      try receiver.start()
    } catch { setStatus("无法启动：\(error.localizedDescription)"); receiver.stop(); return }
    self.recognizer = recognizer; running = true; generation += 1; receivedFrames = 0; seconds = 0; recognitionUpdates = 0; translationUpdates = 0; newest = ""; lastTranslated = ""; sessionStarted = Date(); lastAudio = .distantPast
    startRecognition()
    if #available(iOS 26.0, *), translator == nil {
      Task { [weak self] in
        let available = await LanguageAvailability().status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "zh-Hans"))
        guard let self, self.running else { return }
        if available == .installed { self.translator = TranslationSession(installedSource: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "zh-Hans")) }
      }
    }
    heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    setStatus("接收器已就绪，请开启屏幕广播。")
    picture.prime(); picture.start()
  }
  private func startRecognition() {
    recognitionGeneration += 1; let epoch = recognitionGeneration
    recognition?.cancel()
    let req = SFSpeechAudioBufferRecognitionRequest(); req.requiresOnDeviceRecognition = true; req.shouldReportPartialResults = true; req.taskHint = .dictation
    request = req; lastRotation = Date()
    recognition = recognizer?.recognitionTask(with: req) { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self, self.running, self.recognitionGeneration == epoch else { return }
        if let result {
          self.newest = result.bestTranscription.formattedString
          self.recognitionUpdates += 1
          self.transcript.text = self.newest
          if self.translator == nil { self.picture.original = self.newest; self.picture.translated = "请准备本地翻译语言包" }
        }
        if let error { self.lastError = error.localizedDescription; self.setStatus("识别状态：\(error.localizedDescription)") }
        if error != nil || result?.isFinal == true {
          self.request = nil
          DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard self.running, self.recognitionGeneration == epoch else { return }; self.startRecognition()
          }
        }
      }
    }
  }
  private func consume(_ pcm: AVAudioPCMBuffer) {
    guard running else { return }
    receivedFrames += 1; seconds += Double(pcm.frameLength) / 16000; lastAudio = Date()
    if let channel = pcm.int16ChannelData?[0] { peak = (0..<Int(pcm.frameLength)).reduce(0.0) { max($0, abs(Double(channel[$1])) / 32768) } }
    request?.append(pcm)
  }
  private func tick() {
    guard running else { return }
    counts.text = String(format: "音频 %.1f 秒 · 帧 %d · 音量 %.0f%%\n识别 %d 次 · 翻译 %d 次", seconds, receivedFrames, peak * 100, recognitionUpdates, translationUpdates)
    if Date().timeIntervalSince(lastAudio) > 5 { setStatus(receivedFrames == 0 ? "等待音频：确认已开启广播，并在另一个 App 播放内容。" : "超过 5 秒未收到音频，请检查播放和广播状态。") }
    if Date().timeIntervalSince(lastRotation) > 45 { startRecognition() }
    if !newest.isEmpty, newest != lastTranslated, !translationBusy, let translator {
      let input = newest; let epoch = generation; translationBusy = true
      translationWork = Task { [weak self] in
        do {
          let result = try await translator.translate(input)
          guard let self, self.running, self.generation == epoch, !Task.isCancelled else { return }
          self.translation.text = result.targetText; self.picture.original = input; self.picture.translated = result.targetText
          self.lastTranslated = input; self.translationUpdates += 1; self.translationBusy = false
        } catch {
          guard let self, self.running, self.generation == epoch else { return }
          self.translationBusy = false; self.setStatus("本地翻译未就绪，请停止后准备语言包：\(error.localizedDescription)")
          self.translator = nil
        }
      }
    }
    let diagnostic: [String: Any] = ["running": running, "pip": picture.active, "audioFrames": receivedFrames, "audioSeconds": seconds, "recognitionUpdates": recognitionUpdates, "translationUpdates": translationUpdates, "peak": peak, "lastError": lastError, "elapsed": Date().timeIntervalSince(sessionStarted), "picture": picture.diagnostics, "screenCaptured": UIScreen.main.isCaptured, "replayAvailable": RPScreenRecorder.shared().isAvailable]
    if let data = try? JSONSerialization.data(withJSONObject: diagnostic), let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first { try? data.write(to: documents.appendingPathComponent("probe-status.json"), options: .atomic) }
  }
  @objc private func playTest() {
    do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers]); try AVAudioSession.sharedInstance().setActive(true) } catch { setStatus(error.localizedDescription); return }
    let u = AVSpeechUtterance(string: "Hello. This is a test of live subtitles on an iPhone. The weather is nice today. We are building a small app that helps people understand videos in another language. The sound should become English text and then Chinese subtitles.")
    u.voice = AVSpeechSynthesisVoice(language: "en-US"); u.rate = 0.43; speech.speak(u)
  }
  @objc private func stopPressed() { stopSession() }
  private func stopSession() {
    guard running else { picture.stop(); return }
    running = false; generation += 1; recognitionGeneration += 1
    heartbeat?.invalidate(); heartbeat = nil; receiver.stop(); request?.endAudio(); request = nil; recognition?.cancel(); recognition = nil
    translationWork?.cancel(); translationWork = nil; translationBusy = false; speech.stopSpeaking(at: .immediate); picture.stop()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    setStatus("已停止。音频和字幕未保存。")
    let diagnostic: [String: Any] = ["running": false, "pip": false, "audioFrames": receivedFrames, "audioSeconds": seconds, "recognitionUpdates": recognitionUpdates, "translationUpdates": translationUpdates]
    if let data = try? JSONSerialization.data(withJSONObject: diagnostic), let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first { try? data.write(to: documents.appendingPathComponent("probe-status.json"), options: .atomic) }
  }
  @objc private func closePressed() { stopSession(); dismiss(animated: true) }
  private func setStatus(_ text: String) { status.text = text }
}
