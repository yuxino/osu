import UIKit
import AVFoundation
import ReplayKit
import Speech
import SwiftUI
import Translation

private struct LanguageDownloadView: View {
  let selection: LanguageSelection
  var done: (Bool) -> Void
  @State private var message = "系统将检查资源；下载需要网络与系统确认。"
  var body: some View {
    VStack(spacing: 24) {
      Text("准备本地翻译").font(.title2.bold())
      Text("\(LanguageSelection.display(selection.source)) → \(LanguageSelection.display(selection.target))")
      Text(message).multilineTextAlignment(.center)
      Button("关闭") { done(false) }
    }.padding(32)
    .translationTask(source: selection.sourceLanguage, target: selection.targetLanguage) { session in
      do { try await session.prepareTranslation(); guard !Task.isCancelled else { return }; done(true) }
      catch {
        DiagnosticStore.shared.record("translation", "download_failed", error: error)
        message = "语言包准备未完成。可关闭后重试，并在诊断中查看错误代码。"
      }
    }
  }
}

final class MimiPrototypeController: UIViewController {
  private let picture = SubtitlePicture()
  private let receiver = AudioReceiver()
  private let log = DiagnosticStore.shared
  private let audioDelivery = DispatchSemaphore(value: 1)
  private let status = UILabel(), transcript = UILabel(), translation = UILabel(), counts = UILabel(), languageStatus = UILabel()
  private let sourceButton = UIButton(type: .system), targetButton = UIButton(type: .system)
  private var prepareButton: UIButton!, startButton: UIButton!
  private var selection = LanguageSelection(source: UserDefaults.standard.string(forKey: "mimi.source") ?? "en-US", target: UserDefaults.standard.string(forKey: "mimi.target") ?? "zh-Hans")
  private var pairState = PairReadiness.checking
  private var localSources: Set<String> = []
  private var catalogRevision = 0
  private var catalogTask: Task<Void, Never>?
  private var startPending = false
  private var downloading = false
  private var observers: [NSObjectProtocol] = []
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognition: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var translator: TranslationSession?
  private var translationWork: Task<Void, Never>?
  private var running = false
  private var generation = 0, recognitionGeneration = 0
  private var receivedFrames = 0, recognitionUpdates = 0, translationUpdates = 0, recognitionRestarts = 0
  private var seconds = 0.0, peak = 0.0, translationMS = 0.0
  private var newest = "", lastTranslated = ""
  private var heartbeat: Timer?
  private var lastAudio = Date.distantPast, lastRotation = Date(), sessionStarted = Date(), lastJournal = Date.distantPast
  private var translationBusy = false, audioMissing = false


  override func viewDidLoad() {
    super.viewDidLoad()
    if log.previousWasRunning() { log.record("session", "previous_interrupted_unknown_cause") }
    log.record("app", "opened")
    log.snapshot(running: false, pip: false, metrics: [:])
    view.backgroundColor = .systemBackground
    let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
    NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
    NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28), stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24)])
    let title = UILabel(); title.text = "Mimi / iPhone"; title.font = .systemFont(ofSize: 32, weight: .bold); stack.addArrangedSubview(title)
    let subtitle = label("听懂其他 App 的声音\n设备本地识别 · 自选字幕语言", size: 14); subtitle.textColor = .secondaryLabel; stack.addArrangedSubview(subtitle)
    configureChoice(sourceButton); configureChoice(targetButton)
    #if targetEnvironment(simulator)
    stack.addArrangedSubview(label("模拟器用于界面和本地连接测试；语言资源与屏幕广播能力不代表真机。", size: 12))
    #endif
    stack.addArrangedSubview(sourceButton); stack.addArrangedSubview(targetButton)
    languageStatus.numberOfLines = 0; languageStatus.font = .systemFont(ofSize: 13); languageStatus.textColor = .secondaryLabel; stack.addArrangedSubview(languageStatus)
    stack.addArrangedSubview(button("重新检查设备语言", #selector(refreshPressed)))
    stack.addArrangedSubview(picture.preview); picture.preview.heightAnchor.constraint(equalToConstant: 150).isActive = true
    status.numberOfLines = 0; status.font = .systemFont(ofSize: 15, weight: .medium); status.text = "先选择语言，再开启小窗和屏幕广播。"; stack.addArrangedSubview(status)
    counts.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); counts.textColor = .secondaryLabel; counts.numberOfLines = 0; counts.text = "尚未收到音频"; stack.addArrangedSubview(counts)
    prepareButton = button("1 · 准备翻译语言包", #selector(prepareLanguages)); stack.addArrangedSubview(prepareButton)
    startButton = button("2 · 开启字幕小窗", #selector(startPressed)); stack.addArrangedSubview(startButton)
    let broadcastRow = UIStackView(); broadcastRow.axis = .horizontal; broadcastRow.spacing = 12
    broadcastRow.addArrangedSubview(label("3 · 开始屏幕广播 →", size: 16))
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50)); picker.preferredExtension = "com.yuxino.osu.MimiBroadcast"; picker.showsMicrophoneButton = false; picker.widthAnchor.constraint(equalToConstant: 50).isActive = true; picker.heightAnchor.constraint(equalToConstant: 50).isActive = true; broadcastRow.addArrangedSubview(picker); stack.addArrangedSubview(broadcastRow)
    stack.addArrangedSubview(label("系统会询问是否广播屏幕。仅处理 App 声音，丢弃视频和麦克风；不保存音频或字幕。受保护内容可能无法采集。使用时请关闭 iPhone 镜像。", size: 12))
    transcript.text = "原文等待中"; transcript.numberOfLines = 4; transcript.font = .systemFont(ofSize: 15); stack.addArrangedSubview(transcript)
    translation.text = "译文等待中"; translation.numberOfLines = 4; translation.font = .systemFont(ofSize: 19, weight: .semibold); stack.addArrangedSubview(translation)
    stack.addArrangedSubview(button("停止采集与字幕", #selector(stopPressed)))
    stack.addArrangedSubview(button("复制诊断日志", #selector(copyDiagnostics)))
    stack.addArrangedSubview(button("导出诊断日志", #selector(exportDiagnostics)))
    stack.addArrangedSubview(label("诊断仅保存会话时间、阶段、错误代码和性能计数，容量有限，旧记录会轮换。手机连接电脑并授权后才能读取；未连接时无法实时查看。", size: 12))
    stack.addArrangedSubview(button("返回", #selector(closePressed)))
    picture.onStatus = { [weak self] text in self?.setStatus(text) }
    picture.onEvent = { [weak self] event, error in self?.log.record("pip", event, error: error) }
    picture.onClosed = { [weak self] in self?.stopSession(reason: "pip_closed") }
    for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification, AVAudioSession.interruptionNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        guard let self else { return }
        if note.name == AVAudioSession.interruptionNotification {
          if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { self.log.record("audio", "interrupted"); self.stopSession(reason: "audio_interrupted") }
        } else {
          let foreground = note.name == UIApplication.didBecomeActiveNotification
          self.log.record("app", foreground ? "foreground" : "background")
          if foreground && !self.running && !self.startPending && !self.downloading { self.refreshLanguages() }
        }
      })
    }
    picture.prime(); refreshLanguages()
  }
  deinit { observers.forEach(NotificationCenter.default.removeObserver); catalogTask?.cancel() }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); picture.layout() }
  private func label(_ text: String, size: CGFloat) -> UILabel { let l = UILabel(); l.text = text; l.numberOfLines = 0; l.font = .systemFont(ofSize: size); return l }
  private func configureChoice(_ b: UIButton) { var c = UIButton.Configuration.gray(); c.baseForegroundColor = .label; c.contentInsets = .init(top: 12, leading: 12, bottom: 12, trailing: 12); b.configuration = c; b.showsMenuAsPrimaryAction = true; b.contentHorizontalAlignment = .leading }
  private func button(_ title: String, _ action: Selector) -> UIButton {
    let b = UIButton(type: .system); configureChoice(b); b.showsMenuAsPrimaryAction = false; b.configuration?.title = title; b.addTarget(self, action: action, for: .touchUpInside); return b
  }
  private func updateControls() {
    let busy = running || startPending || downloading
    sourceButton.isEnabled = !busy; targetButton.isEnabled = !busy
    sourceButton.configuration?.title = "声音语言 · \(LanguageSelection.display(selection.source))"
    targetButton.configuration?.title = "字幕语言 · \(selection.target.isEmpty ? "仅显示原文" : LanguageSelection.display(selection.target))"
    prepareButton.isEnabled = !busy && (pairState == .needsDownload || pairState == .installed)
    startButton.isEnabled = running || (!busy && pairState.canStart && localSources.contains(selection.source))
    languageStatus.text = (localSources.contains(selection.source) ? "已检测到此语言的本地识别能力。\n" : "所选语言的本地识别当前不可用。可换语言或稍后重新检查；识别资源由系统提供，应用内无法直接下载，也不会改用云端识别。\n") + pairState.message
  }
  @objc private func refreshPressed() { guard !running && !startPending && !downloading else { return }; refreshLanguages() }
  private func choose(_ value: LanguageSelection) {
    guard !running && !startPending && !downloading else { return }
    selection = value; translator = nil
    UserDefaults.standard.set(value.source, forKey: "mimi.source"); UserDefaults.standard.set(value.target, forKey: "mimi.target")
    refreshLanguages()
  }
  private func refreshLanguages() {
    catalogRevision += 1; let revision = catalogRevision; let captured = selection
    catalogTask?.cancel(); pairState = .checking
    let locales = SFSpeechRecognizer.supportedLocales().sorted { LanguageSelection.display($0.identifier) < LanguageSelection.display($1.identifier) }
    localSources = Set(locales.filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }.map(\.identifier))
    sourceButton.menu = UIMenu(children: locales.map { locale in
      let local = localSources.contains(locale.identifier)
      return UIAction(title: LanguageSelection.display(locale.identifier) + (local ? "" : " · 本地不可用"), attributes: local ? [] : [.disabled], state: locale.identifier == selection.source ? .on : .off) { [weak self] _ in
        guard let self else { return }; self.choose(.init(source: locale.identifier, target: self.selection.target))
      }
    })
    targetButton.menu = UIMenu(children: [UIAction(title: "仅显示原文", state: selection.target.isEmpty ? .on : .off) { [weak self] _ in
      guard let self else { return }; self.choose(.init(source: self.selection.source, target: ""))
    }])
    if captured.target.isEmpty { pairState = .transcriptionOnly }
    updateControls()
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
      guard let self, self.catalogRevision == revision, self.pairState == .checking else { return }
      self.catalogRevision += 1; self.catalogTask?.cancel(); self.pairState = .checkFailed; self.updateControls(); self.log.record("language", "check_timeout")
    }
    catalogTask = Task { [weak self] in
      let availability = LanguageAvailability()
      let languages = await availability.supportedLanguages
      let state: PairReadiness
      if captured.target.isEmpty { state = .transcriptionOnly }
      else if #available(iOS 26.0, *) {
        switch await availability.status(from: captured.sourceLanguage, to: captured.targetLanguage) {
        case .installed: state = .installed
        case .supported: state = .needsDownload
        case .unsupported: state = .unsupported
        @unknown default: state = .unsupported
        }
      } else { state = .requiresNewerOS }
      guard let self, !Task.isCancelled, self.catalogRevision == revision, self.selection == captured else { return }
      var actions = [UIAction(title: "仅显示原文", state: captured.target.isEmpty ? .on : .off) { [weak self] _ in guard let self else { return }; self.choose(.init(source: self.selection.source, target: "")) }]
      for id in Set(languages.map { LanguageSelection.identifier($0) }).sorted(by: { LanguageSelection.display($0) < LanguageSelection.display($1) }) {
        actions.append(UIAction(title: LanguageSelection.display(id), state: id == captured.target ? .on : .off) { [weak self] _ in guard let self else { return }; self.choose(.init(source: self.selection.source, target: id)) })
      }
      self.targetButton.menu = UIMenu(children: actions); self.pairState = state; self.updateControls()
      self.log.record("language", state.rawValue, source: captured.source, target: captured.target.isEmpty ? "none" : captured.target)
    }
  }
  @objc private func prepareLanguages() {
    guard !running && !startPending && !downloading, pairState == .needsDownload || pairState == .installed else { return }
    downloading = true; updateControls(); let captured = selection
    log.record("translation", "download_requested", source: captured.source, target: captured.target)
    let sheet = UIHostingController(rootView: LanguageDownloadView(selection: captured) { [weak self] ok in
      DispatchQueue.main.async {
        guard let self, self.downloading else { return }
        self.downloading = false; self.dismiss(animated: true); self.log.record("translation", ok ? "download_ready" : "download_cancelled")
        self.refreshLanguages()
      }
    })
    sheet.isModalInPresentation = true; present(sheet, animated: true)
  }
  @objc private func startPressed() {
    if running { picture.start(); return }
    guard !startPending && !downloading && pairState.canStart else { return }
    startPending = true; generation += 1; let epoch = generation; updateControls()
    log.begin(source: selection.source, target: selection.target.isEmpty ? "none" : selection.target)
    log.snapshot(running: false, pip: false, metrics: [:])
    SFSpeechRecognizer.requestAuthorization { [weak self] permission in
      DispatchQueue.main.async {
        guard let self, self.startPending, self.generation == epoch else { return }
        self.log.record("permission", "speech", metrics: ["permission": Double(permission.rawValue)])
        guard permission == .authorized else { self.startPending = false; self.updateControls(); self.setStatus("请在系统设置中允许语音识别；音频仅在设备处理。"); self.log.record("session", "permission_denied"); return }
        self.startSession()
      }
    }
  }
  private func bindReceiver() {
    let epoch = generation
    receiver.onEvent = { [weak self] event, error, metrics in
      DispatchQueue.main.async {
        guard let self, self.running, self.generation == epoch else { return }
        self.log.record("transport", event, metrics: metrics, error: error)
        switch event {
        case "ready": self.setStatus("接收器已就绪，请开始屏幕广播。")
        case "connected": self.setStatus("屏幕广播已连接，等待 App 声音。")
        case "ended", "failed", "listener_failed": self.stopSession(reason: event)
        default: break
        }
      }
    }
    receiver.onAudio = { [weak self] pcm in
      guard let self, self.audioDelivery.wait(timeout: .now()) == .success else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }; defer { self.audioDelivery.signal() }; guard self.generation == epoch else { return }; self.consume(pcm)
      }
    }
  }
  private func startSession() {
    startPending = false
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: selection.source)), recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
      log.record("speech", "local_unavailable"); setStatus("所选语言的本地识别暂不可用，请换语言或稍后重新检查。"); updateControls(); return
    }
    translator = nil
    if !selection.target.isEmpty {
      guard #available(iOS 26.0, *), pairState == .installed else { updateControls(); return }
      translator = TranslationSession(installedSource: selection.sourceLanguage, target: selection.targetLanguage)
    }
    generation += 1; bindReceiver()
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers]); try AVAudioSession.sharedInstance().setActive(true); try receiver.start()
    } catch { log.record("audio", "start_failed", error: error); receiver.stop(); try? AVAudioSession.sharedInstance().setActive(false); updateControls(); setStatus("无法启动收音，错误已写入诊断。"); return }
    self.recognizer = recognizer; running = true; receivedFrames = 0; seconds = 0; peak = 0; recognitionUpdates = 0; translationUpdates = 0; recognitionRestarts = 0; translationMS = 0; newest = ""; lastTranslated = ""; translationBusy = false; audioMissing = false; sessionStarted = Date(); lastAudio = .distantPast; lastJournal = .distantPast
    transcript.text = "原文等待中"; translation.text = selection.target.isEmpty ? "仅显示原文" : "译文等待中"; picture.original = "等待其他 App 的声音"; picture.translated = selection.target.isEmpty ? "仅显示原文" : "等待翻译"
    startRecognition(); updateControls()
    heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    setStatus("正在启动接收器…"); log.record("session", "running"); picture.prime(); picture.start(); writeSnapshot()
  }
  private func startRecognition() {
    recognitionGeneration += 1; let epoch = recognitionGeneration
    recognition?.cancel(); recognitionRestarts += 1
    let req = SFSpeechAudioBufferRecognitionRequest(); req.requiresOnDeviceRecognition = true; req.shouldReportPartialResults = true; req.taskHint = .dictation
    request = req; lastRotation = Date(); log.record("speech", "task_started", metrics: ["recognitionRestarts": Double(recognitionRestarts)])
    recognition = recognizer?.recognitionTask(with: req) { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self, self.running, self.recognitionGeneration == epoch else { return }
        if let result {
          self.newest = result.bestTranscription.formattedString; self.recognitionUpdates += 1; self.transcript.text = self.newest
          if self.translator == nil { self.picture.original = self.newest; self.picture.translated = self.selection.target.isEmpty ? "" : "翻译不可用，请停止后检查语言资源" }
          if self.recognitionUpdates == 1 { self.log.record("speech", "first_result") }
        }
        if let error { self.log.record("speech", "task_failed", error: error); self.setStatus("识别暂时中断，正在重试；错误代码已写入诊断。") }
        if error != nil || result?.isFinal == true {
          self.request = nil
          DispatchQueue.main.asyncAfter(deadline: .now() + (error == nil ? 1 : 3)) {
            guard self.running, self.recognitionGeneration == epoch else { return }; self.startRecognition()
          }
        }
      }
    }
  }
  private func consume(_ pcm: AVAudioPCMBuffer) {
    guard running else { return }
    if receivedFrames == 0 || audioMissing { log.record("audio", receivedFrames == 0 ? "first_frame" : "resumed"); setStatus("正在接收 App 声音并生成字幕。"); audioMissing = false }
    receivedFrames += 1; seconds += Double(pcm.frameLength) / 16000; lastAudio = Date()
    if let channel = pcm.int16ChannelData?[0] { peak = (0..<Int(pcm.frameLength)).reduce(0.0) { max($0, abs(Double(channel[$1])) / 32768) } }
    request?.append(pcm)
  }
  private var metrics: [String: Double] {
    ["audioFrames": Double(receivedFrames), "audioSeconds": seconds, "recognitionUpdates": Double(recognitionUpdates), "translationUpdates": Double(translationUpdates), "peak": peak, "elapsed": Date().timeIntervalSince(sessionStarted), "translationMS": translationMS, "recognitionRestarts": Double(recognitionRestarts), "audioGapSeconds": receivedFrames == 0 ? Date().timeIntervalSince(sessionStarted) : Date().timeIntervalSince(lastAudio)]
  }
  private func writeSnapshot() { log.snapshot(running: running, pip: running && picture.active, metrics: metrics) }
  private func tick() {
    guard running else { return }
    counts.text = String(format: "音频 %.1f 秒 · 帧 %d · 音量 %.0f%%\n识别 %d 次 · 翻译 %d 次", seconds, receivedFrames, peak * 100, recognitionUpdates, translationUpdates)
    if Date().timeIntervalSince(lastAudio) > 5 && !audioMissing {
      audioMissing = true; log.record("audio", "waiting_or_gap", metrics: metrics); setStatus("等待音频：请检查广播和播放状态；受保护内容可能无法采集。")
    }
    if Date().timeIntervalSince(lastRotation) > 45 { startRecognition() }
    if !newest.isEmpty, newest != lastTranslated, !translationBusy, let translator {
      let input = newest; let epoch = generation; translationBusy = true; let began = Date()
      translationWork = Task { [weak self] in
        do {
          let result = try await translator.translate(input)
          guard let self, self.running, self.generation == epoch, !Task.isCancelled else { return }
          self.translation.text = result.targetText; self.picture.original = input; self.picture.translated = result.targetText
          self.lastTranslated = input; self.translationUpdates += 1; self.translationBusy = false; self.translationMS = Date().timeIntervalSince(began) * 1000
          if self.translationUpdates == 1 { self.log.record("translation", "first_result", metrics: ["translationMS": self.translationMS]) }
        } catch {
          guard let self, self.running, self.generation == epoch else { return }
          self.translationBusy = false; self.log.record("translation", "failed", error: error); self.setStatus("翻译暂不可用，原文继续显示。请停止后检查或重新准备语言包。"); self.translator = nil
        }
      }
    }
    if Date().timeIntervalSince(lastJournal) >= 5 { log.record("session", "counters", metrics: metrics); lastJournal = Date() }
    writeSnapshot()
  }
  @objc private func copyDiagnostics() { UIPasteboard.general.string = log.report(); setStatus("诊断已复制，包含近期会话记录，不含音频或字幕。") }
  @objc private func exportDiagnostics() {
    do {
      let url = try log.export(); let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = view; sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
      present(sheet, animated: true)
    } catch { setStatus("无法导出诊断，请检查设备存储空间。") }
  }
  @objc private func stopPressed() { stopSession(reason: "user_stopped") }
  private func stopSession(reason: String) {
    generation += 1; startPending = false
    guard running else { picture.stop(); updateControls(); return }
    running = false; recognitionGeneration += 1
    heartbeat?.invalidate(); heartbeat = nil; receiver.stop(); request?.endAudio(); request = nil; recognition?.cancel(); recognition = nil
    translationWork?.cancel(); translationWork = nil; translationBusy = false
    if #available(iOS 26.0, *) { translator?.cancel() }; translator = nil
    picture.stop()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    log.record("session", reason, metrics: metrics); writeSnapshot(); updateControls()
    setStatus("会话已停止；可复制或导出诊断日志。")
    refreshLanguages()
  }
  @objc private func closePressed() { stopSession(reason: "closed"); catalogRevision += 1; catalogTask?.cancel(); dismiss(animated: true) }
  private func setStatus(_ text: String) { status.text = text }
}
