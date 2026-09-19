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
  private var engine = SubtitleEngine(rawValue: UserDefaults.standard.string(forKey: "mimi.engine") ?? "apple") ?? .apple
  private let engineButton = UIButton(type: .system)
  private var keyButton: UIButton!
  private var cloud: AlibabaClient?
  private let makeCloudClient: () -> AlibabaClient
  private let readCloudCredential: () throws -> String?
  private var cloudBytes = 0
  private var sampleButton: UIButton!
  private var longSampleButton: UIButton!
  private let sampleTest = CloudSampleTest()
  private var sampleData = Data()
  private var sampleOffset = 0
  private var sampleTimer: Timer?
  private var testingSample = false, finishing = false
  private var sourceFinals = 0, translationFinals = 0
  private var sampleRepeats = 1
  private var settingsPage: UIViewController?
  private let serviceHint = UILabel()
  private let broadcastRow = UIStackView()
  private let cloudTestSection = UIStackView()
  private let diagnosticFeedback = UILabel()
  private var copyDiagnosticsButton: UIButton!
  private var pipButton: UIButton!
  private var broadcastConnected = false
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

  // The isolated simulator harness substitutes an in-memory socket and dummy key.
  // Normal app startup uses the fixed provider endpoint and device Keychain.
  init(makeCloudClient: (() -> AlibabaClient)? = nil, readCloudCredential: (() throws -> String?)? = nil) {
    self.makeCloudClient = makeCloudClient ?? { AlibabaClient() }
    self.readCloudCredential = readCloudCredential ?? { try CloudCredentialStore.read() }
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("Use init()") }

  override func viewDidLoad() {
    super.viewDidLoad()
    if engine == .alibaba { selection = .init(source: UserDefaults.standard.string(forKey: "mimi.alibaba.source") ?? "ja", target: UserDefaults.standard.string(forKey: "mimi.alibaba.target") ?? "zh") }
    if log.previousWasRunning() { log.record("session", "previous_interrupted_unknown_cause") }
    log.record("app", "opened")
    log.snapshot(running: false, pip: false, metrics: [:])
    buildHome()
    picture.onStatus = { [weak self] text in self?.setStatus(text) }
    picture.onEvent = { [weak self] event, error in self?.log.record("pip", event, error: error) }
    picture.onClosed = { [weak self] in self?.finishSession(reason: "pip_closed") }
    for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification, AVAudioSession.interruptionNotification, UIContentSizeCategory.didChangeNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        guard let self else { return }
        if note.name == UIContentSizeCategory.didChangeNotification { self.picture.showStill(); return }
        if note.name == AVAudioSession.interruptionNotification {
          if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { self.log.record("audio", "interrupted"); self.stopSession(reason: "audio_interrupted") }
        } else {
          let foreground = note.name == UIApplication.didBecomeActiveNotification
          self.log.record("app", foreground ? "foreground" : "background")
          if foreground && !self.running && !self.startPending && !self.downloading { self.refreshLanguages() }
        }
      })
    }
    picture.showStill(); refreshLanguages()
  }
  deinit { observers.forEach(NotificationCenter.default.removeObserver); catalogTask?.cancel() }
  override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if !running { picture.showStill() } }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); picture.layout() }
  private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UILabel {
    let l = UILabel(); l.text = text; l.numberOfLines = 0
    l.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: size, weight: weight)); l.adjustsFontForContentSizeCategory = true
    return l
  }
  private func configureChoice(_ b: UIButton) {
    var c = UIButton.Configuration.gray(); c.baseForegroundColor = .label; c.baseBackgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.96, alpha: 1) }
    c.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16); c.cornerStyle = .medium
    c.image = UIImage(systemName: "chevron.down"); c.imagePlacement = .trailing; c.imagePadding = 10; c.preferredSymbolConfigurationForImage = .init(pointSize: 11, weight: .semibold)
    b.configuration = c
    b.configurationUpdateHandler = { button in
      guard var config = button.configuration else { return }
      let enabled = button.isEnabled
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var value = attributes; value.foregroundColor = enabled ? UIColor.label : UIColor.secondaryLabel; return value }
      config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var value = attributes; value.foregroundColor = UIColor.secondaryLabel; return value }
      button.configuration = config
    }
    b.showsMenuAsPrimaryAction = true; b.contentHorizontalAlignment = .leading
    b.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
  }
  private func button(_ title: String, _ action: Selector) -> UIButton {
    let b = UIButton(type: .system); configureChoice(b); b.showsMenuAsPrimaryAction = false; b.configuration?.image = nil
    b.configuration?.title = title; b.addTarget(self, action: action, for: .touchUpInside); return b
  }
  private func pageStack(in host: UIView, top: CGFloat = 20) -> UIStackView {
    let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(scroll)
    NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor)])
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 22; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
    NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: top), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28), stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24)])
    return stack
  }
  private func buildHome() {
    view.backgroundColor = .systemBackground
    let stack = pageStack(in: view)
    let header = UIStackView(); header.axis = .horizontal; header.alignment = .center
    let title = label("Osu", size: 35, weight: .semibold)
    if let descriptor = title.font.fontDescriptor.withDesign(.serif) { title.font = UIFont(descriptor: descriptor, size: title.font.pointSize) }
    header.addArrangedSubview(title)
    let settings = button("", #selector(openSettings)); settings.configuration = .plain(); settings.configuration?.image = UIImage(systemName: "slider.horizontal.3"); settings.tintColor = .label; settings.accessibilityLabel = "设置"
    settings.widthAnchor.constraint(equalToConstant: 48).isActive = true; header.addArrangedSubview(settings); stack.addArrangedSubview(header)
    let intro = label("听懂此刻。", size: 30, weight: .semibold); stack.addArrangedSubview(intro)
    let subtitle = label("为正在播放的声音，添上你的语言。", size: 15); subtitle.textColor = .secondaryLabel; stack.addArrangedSubview(subtitle); stack.setCustomSpacing(28, after: subtitle)
    configureChoice(sourceButton); configureChoice(targetButton)
    let languages = UIStackView(arrangedSubviews: [sourceButton, targetButton]); languages.axis = .horizontal; languages.spacing = 10; languages.distribution = .fillEqually; stack.addArrangedSubview(languages)
    picture.original = "播放一段你想听懂的内容"; picture.translated = "字幕会出现在这里"
    stack.addArrangedSubview(picture.preview); picture.preview.heightAnchor.constraint(equalTo: picture.preview.widthAnchor, multiplier: 0.60).isActive = true
    status.numberOfLines = 0; status.font = UIFont.preferredFont(forTextStyle: .subheadline); status.adjustsFontForContentSizeCategory = true; status.textColor = .secondaryLabel; status.text = "选择语言，然后开始。"; stack.addArrangedSubview(status)
    prepareButton = button("准备本地语言包", #selector(prepareLanguages)); stack.addArrangedSubview(prepareButton)
    startButton = button("开始听", #selector(primaryPressed)); var primary = UIButton.Configuration.filled(); primary.baseBackgroundColor = .label; primary.baseForegroundColor = .systemBackground; primary.cornerStyle = .medium; primary.contentInsets = .init(top: 18, leading: 24, bottom: 18, trailing: 24); primary.title = "开始听"; primary.image = UIImage(systemName: "waveform"); primary.imagePadding = 10; startButton.configurationUpdateHandler = nil; startButton.configuration = primary; stack.addArrangedSubview(startButton)
    broadcastRow.axis = .horizontal; broadcastRow.spacing = 12; broadcastRow.alignment = .center
    let instruction = label("允许收音\n选择 Osu Audio，开始广播", size: 14)
    broadcastRow.addArrangedSubview(instruction)
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52)); picker.preferredExtension = "com.yuxino.osu.MimiBroadcast"; picker.showsMicrophoneButton = false; picker.tintColor = .label; picker.widthAnchor.constraint(equalToConstant: 52).isActive = true; picker.heightAnchor.constraint(equalToConstant: 52).isActive = true
    picker.accessibilityLabel = "开始屏幕广播"; broadcastRow.addArrangedSubview(picker); stack.addArrangedSubview(broadcastRow)
    pipButton = button("显示字幕小窗", #selector(showPicture)); pipButton.configuration = .plain(); pipButton.configuration?.title = "显示字幕小窗"; pipButton.configuration?.image = UIImage(systemName: "pip.enter"); pipButton.configuration?.imagePadding = 8; pipButton.tintColor = .label; stack.addArrangedSubview(pipButton)
    serviceHint.numberOfLines = 0; serviceHint.font = UIFont.preferredFont(forTextStyle: .footnote); serviceHint.adjustsFontForContentSizeCategory = true; serviceHint.textColor = .secondaryLabel; stack.addArrangedSubview(serviceHint)
    configureChoice(engineButton)
    engineButton.menu = UIMenu(children: [UIAction(title: "Apple · 设备本地") { [weak self] _ in self?.chooseEngine(.apple) }, UIAction(title: "阿里云 · 实时同传") { [weak self] _ in self?.chooseEngine(.alibaba) }])
    keyButton = button("管理阿里云密钥", #selector(configureCloudKey))
    languageStatus.numberOfLines = 0; languageStatus.font = UIFont.preferredFont(forTextStyle: .footnote); languageStatus.adjustsFontForContentSizeCategory = true; languageStatus.textColor = .secondaryLabel
    counts.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); counts.numberOfLines = 0; counts.textColor = .secondaryLabel; counts.text = "尚未收到音频"
    sampleButton = button("测试日语同传", #selector(startSampleTest)); longSampleButton = button("连续测试 · 约一分钟", #selector(startLongSampleTest))
    cloudTestSection.axis = .vertical; cloudTestSection.spacing = 16
    cloudTestSection.addArrangedSubview(label("检查服务", size: 18, weight: .semibold))
    cloudTestSection.addArrangedSubview(sampleButton); cloudTestSection.addArrangedSubview(longSampleButton)
    cloudTestSection.addArrangedSubview(label("测试会把固定的日语合成语音发给阿里云并产生少量用量，不使用麦克风。", size: 12))
    diagnosticFeedback.numberOfLines = 0; diagnosticFeedback.font = UIFont.preferredFont(forTextStyle: .footnote); diagnosticFeedback.adjustsFontForContentSizeCategory = true; diagnosticFeedback.textColor = .secondaryLabel; diagnosticFeedback.isHidden = true
    copyDiagnosticsButton = button("复制诊断", #selector(copyDiagnostics))
    transcript.text = ""; translation.text = ""
  }
  @objc private func primaryPressed() { if running || startPending { stopPressed() } else { startPressed() } }
  @objc private func showPicture() { guard running && !finishing && !testingSample else { return }; picture.start() }
  @objc private func openSettings() {
    let page = UIViewController(); page.view.backgroundColor = .systemBackground; settingsPage = page
    let stack = pageStack(in: page.view, top: 28)
    let heading = UIStackView(arrangedSubviews: [label("设置", size: 28, weight: .semibold), button("完成", #selector(closeSettings))]); heading.axis = .horizontal; heading.spacing = 24; stack.addArrangedSubview(heading)
    stack.addArrangedSubview(engineButton); stack.addArrangedSubview(keyButton); stack.addArrangedSubview(languageStatus)
    stack.addArrangedSubview(button("重新检查本地语言", #selector(refreshPressed)))
    stack.addArrangedSubview(label("使用方法", size: 18, weight: .semibold))
    stack.addArrangedSubview(label("开始听 → 允许屏幕广播 → 切换到播放内容的 App。关闭字幕小窗也会停止收音。\n\n只处理 App 声音，不采集麦克风和视频，不保存录音或字幕。部分受保护内容无法采集。屏幕广播时需关闭 iPhone 镜像。", size: 14))
    stack.addArrangedSubview(cloudTestSection)
    copyDiagnosticsButton.configuration?.title = "复制诊断"
    stack.addArrangedSubview(counts); stack.addArrangedSubview(copyDiagnosticsButton); stack.addArrangedSubview(button("导出诊断", #selector(exportDiagnostics)))
    diagnosticFeedback.text = nil; diagnosticFeedback.isHidden = true; stack.addArrangedSubview(diagnosticFeedback)
    stack.addArrangedSubview(label("诊断只包含时间、阶段、错误代码和计数，不含音频、字幕或密钥。", size: 12))
    #if targetEnvironment(simulator)
    stack.addArrangedSubview(label("模拟器中的系统广播和语言资源不代表真机能力。", size: 12))
    #endif
    page.modalPresentationStyle = .pageSheet; page.sheetPresentationController?.prefersGrabberVisible = true
    present(page, animated: true); updateControls()
  }
  @objc private func closeSettings() { settingsPage?.dismiss(animated: true) }
  private func dismissSettingsThen(_ work: @escaping () -> Void) { if let page = settingsPage, page.presentingViewController != nil { page.dismiss(animated: true, completion: work) } else { work() } }
  private var presenter: UIViewController { if let page = settingsPage, page.presentingViewController != nil { return page }; return self }
  private func chooseEngine(_ value: SubtitleEngine) {
    guard !running && !startPending && !downloading else { return }
    engine = value; UserDefaults.standard.set(value.rawValue, forKey: "mimi.engine")
    let prefix = value == .alibaba ? "mimi.alibaba." : "mimi."
    selection = .init(source: UserDefaults.standard.string(forKey: prefix + "source") ?? (value == .alibaba ? "ja" : "en-US"), target: UserDefaults.standard.string(forKey: prefix + "target") ?? (value == .alibaba ? "zh" : "zh-Hans"))
    translator = nil; refreshLanguages()
  }
  @objc private func configureCloudKey() {
    guard !running && !startPending else { return }
    let alert = UIAlertController(title: "阿里云百炼 · 北京", message: "输入你的 API Key，仅保存到这台设备的系统钥匙串。开始云端会话后音频会上传并按阿里云规则计费。不会自动读取桌面 Mimi 的密钥。", preferredStyle: .alert)
    alert.addTextField { field in field.placeholder = "API Key"; field.isSecureTextEntry = true; field.autocorrectionType = .no; field.autocapitalizationType = .none }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in alert.textFields?.first?.text = "" })
    alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
      defer { alert.textFields?.first?.text = "" }
      do { try CloudCredentialStore.save(alert.textFields?.first?.text ?? ""); self?.setStatus("密钥已安全保存。"); self?.log.record("credential", "saved") }
      catch { self?.setStatus("密钥未保存，请检查输入或系统钥匙串。") }
      self?.updateControls()
    })
    alert.addAction(UIAlertAction(title: "移除已保存密钥", style: .destructive) { [weak self] _ in
      alert.textFields?.first?.text = ""
      do { try CloudCredentialStore.remove(); self?.setStatus("已移除密钥。"); self?.log.record("credential", "removed") }
      catch { self?.setStatus("无法移除密钥，请稍后重试。") }; self?.updateControls()
    })
    presenter.present(alert, animated: true)
  }
  @objc private func startSampleTest() {
    guard !running && !startPending && engine == .alibaba && selection.source == "ja" else { return }
    sampleRepeats = 1; testingSample = true; dismissSettingsThen { [weak self] in self?.startCloud() }
  }
  @objc private func startLongSampleTest() {
    guard !running && !startPending && engine == .alibaba && selection.source == "ja" && AlibabaProtocol.valid(source: selection.source, target: selection.target) else { return }
    sampleRepeats = 6; testingSample = true; dismissSettingsThen { [weak self] in self?.startCloud() }
  }
  private func beginSample() {
    let epoch = generation
    log.record("cloud", "synthetic_sample_preparing"); setStatus("正在准备固定日语合成语音；此测试不采集浏览器或麦克风。")
    sampleTest.prepare { [weak self] data in
      guard let self, self.running, !self.finishing, self.generation == epoch else { return }
      guard let data else { self.stopSession(reason: "sample_unavailable"); self.setStatus("无法生成日语测试语音；可用真机广播或稍后重试。"); return }
      self.sampleData = data + Data(repeating: 0, count: 32000); self.sampleOffset = 0
      self.log.record("cloud", "synthetic_sample_uploading"); self.setStatus("正在测试日语同传…")
      self.sampleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
        guard let self, self.running, !self.finishing, self.generation == epoch else { return }
        if self.sampleOffset >= self.sampleData.count && self.sampleRepeats > 1 { self.sampleRepeats -= 1; self.sampleOffset = 0 }
        guard self.sampleOffset < self.sampleData.count else {
          self.sampleTimer?.invalidate(); self.sampleTimer = nil; self.sampleData.removeAll()
          self.log.record("cloud", "synthetic_sample_sent")
          self.finishSession(reason: "sample_complete")
          return
        }
        let end = min(self.sampleOffset + 3200, self.sampleData.count)
        let chunk = self.sampleData.subdata(in: self.sampleOffset..<end); self.sampleOffset = end
        self.cloud?.append(chunk); self.receivedFrames += 1; self.seconds += Double(chunk.count) / 32000; self.lastAudio = Date()
        }
      }
    }
  }
  private func startCloud() {
    do {
      guard let key = try readCloudCredential() else { testingSample = false; setStatus("请先在设置中添加阿里云密钥。"); openSettings(); return }
      log.begin(source: selection.source, target: selection.target); log.record("cloud", "connecting"); log.snapshot(running: false, pip: false, metrics: [:])
      startPending = true; generation += 1; updateControls(); setStatus("正在连接阿里云，连接成功后再开启屏幕广播。")
      let client = makeCloudClient(); cloud = client
      client.onReady = { [weak self, weak client] in
        guard let self, let client, self.cloud === client, self.startPending else { return }
        self.log.record("cloud", "ready"); self.startSession()
      }
      client.onSource = { [weak self, weak client] text, final in
        guard let self, let client, self.cloud === client, self.running else { return }
        self.recognitionUpdates += 1; self.transcript.text = text; self.picture.original = text
        if self.recognitionUpdates == 1 { self.log.record("cloud", "first_source") }
        if final { self.sourceFinals += 1; self.log.record("cloud", "source_final") }
      }
      client.onTranslation = { [weak self, weak client] text, final in
        guard let self, let client, self.cloud === client, self.running else { return }
        self.translationUpdates += 1; self.translation.text = text; self.picture.translated = text
        if self.translationUpdates == 1 { self.log.record("cloud", "first_translation") }
        if final { self.translationFinals += 1; self.log.record("cloud", "translation_final") }
      }
      client.onMetric = { [weak self, weak client] bytes in guard let self, let client, self.cloud === client else { return }; self.cloudBytes += bytes }
      client.onFailure = { [weak self, weak client] failure in
        guard let self, let client, self.cloud === client else { return }
        self.log.record("cloud", "failed", metrics: ["code": Double(failure.rawValue)])
        self.stopSession(reason: "cloud_failed")
        self.setStatus(failure == .authentication ? "阿里云鉴权失败，请检查北京地域 API Key。" : failure == .quota ? "阿里云额度不足或请求受限，请检查账户。" : "阿里云会话已停止，请检查网络、密钥地域与服务权限。错误代码已写入诊断，可手动重试。")
      }
      try client.start(key: key, source: selection.source, target: selection.target)
    } catch {
      cloud?.stop(); cloud = nil; testingSample = false; startPending = false; updateControls(); setStatus("无法启动阿里云，请检查密钥和语言配置。"); log.record("cloud", "start_failed")
    }
  }
  private func updateControls() {
    let busy = running || startPending || downloading
    cloudTestSection.isHidden = engine != .alibaba
    sampleButton.isEnabled = !busy && selection.source == "ja" && AlibabaProtocol.valid(source: selection.source, target: selection.target)
    longSampleButton.isEnabled = sampleButton.isEnabled
    engineButton.isEnabled = !busy; keyButton.isEnabled = !busy; keyButton.isHidden = engine != .alibaba
    engineButton.configuration?.title = engine == .apple ? "服务 · Apple 设备本地" : "服务 · 阿里云实时同传"
    sourceButton.isEnabled = !busy; targetButton.isEnabled = !busy
    prepareButton.isHidden = engine == .alibaba || busy || pairState != .needsDownload
    prepareButton.isEnabled = !busy && (pairState == .needsDownload || pairState == .installed)
    startButton.isEnabled = running || startPending || (!busy && pairState != .checking)
    startButton.configuration?.title = finishing ? "立即结束" : (running ? "停止" : (startPending ? "取消连接" : "开始听"))
    startButton.configuration?.image = UIImage(systemName: running || startPending ? "stop.fill" : "waveform")
    sourceButton.configuration?.title = selection.source == "auto" ? "自动识别" : LanguageSelection.display(selection.source)
    sourceButton.configuration?.subtitle = "声音"
    targetButton.configuration?.title = selection.target.isEmpty ? "仅原文" : LanguageSelection.display(selection.target)
    targetButton.configuration?.subtitle = "字幕"
    broadcastRow.isHidden = !running || testingSample || finishing || broadcastConnected
    pipButton.isHidden = !running || testingSample || finishing
    serviceHint.text = engine == .alibaba ? "阿里云同传 · 音频上传北京并计费" : "Apple 本地 · 音频留在设备上"
    if engine == .apple && !pairState.canStart { serviceHint.text = pairState.message }

    if engine == .alibaba {
      let credential: String
      do { credential = try readCloudCredential() != nil ? "密钥已保存。" : "请先配置北京地域百炼 API Key。" }
      catch { credential = "系统钥匙串暂不可用。" }
      languageStatus.text = "沿用 Mimi 的低延迟同传服务；无需下载 Apple 语言包。\n开始后 App 音频将通过加密连接上传到阿里云（北京），由你的阿里云账户计费。\n" + credential + (pairState.canStart ? "" : "\n请选择不同的声音和字幕语言。")
      return
    }
    languageStatus.text = (localSources.contains(selection.source) ? "已检测到此语言的本地识别能力。\n" : "所选语言的本地识别当前不可用。可换语言或稍后重新检查；识别资源由系统提供，应用内无法直接下载，也不会改用云端识别。\n") + pairState.message
  }
  @objc private func refreshPressed() { guard !running && !startPending && !downloading else { return }; refreshLanguages() }
  private func choose(_ value: LanguageSelection) {
    guard !running && !startPending && !downloading else { return }
    selection = value; translator = nil
    let prefix = engine == .alibaba ? "mimi.alibaba." : "mimi."
    UserDefaults.standard.set(value.source, forKey: prefix + "source"); UserDefaults.standard.set(value.target, forKey: prefix + "target")
    refreshLanguages()
  }
  private func refreshLanguages() {
    catalogRevision += 1; let revision = catalogRevision; let captured = selection
    catalogTask?.cancel(); pairState = .checking
    if engine == .alibaba {
      localSources = Set(AlibabaProtocol.sources)
      sourceButton.menu = UIMenu(children: AlibabaProtocol.sources.map { id in
        UIAction(title: id == "auto" ? "自动识别" : LanguageSelection.display(id), state: id == selection.source ? .on : .off) { [weak self] _ in guard let self else { return }; self.choose(.init(source: id, target: self.selection.target)) }
      })
      targetButton.menu = UIMenu(children: AlibabaProtocol.targets.map { id in
        UIAction(title: id == "zh" ? "简体中文" : LanguageSelection.display(id), state: id == selection.target ? .on : .off) { [weak self] _ in guard let self else { return }; self.choose(.init(source: self.selection.source, target: id)) }
      })
      pairState = AlibabaProtocol.valid(source: selection.source, target: selection.target) ? .installed : .unsupported
      updateControls(); log.record("language", "alibaba_selected", source: selection.source, target: selection.target); return
    }
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
        self.downloading = false; self.presenter.dismiss(animated: true); self.log.record("translation", ok ? "download_ready" : "download_cancelled")
        self.refreshLanguages()
      }
    })
    sheet.isModalInPresentation = true; present(sheet, animated: true)
  }
  @objc private func startPressed() {
    if running { picture.start(); return }
    guard !startPending && !downloading else { return }
    if engine == .alibaba && !pairState.canStart { setStatus("声音和字幕语言相同，请在上方选择不同的语言。"); return }
    guard pairState.canStart && localSources.contains(selection.source) else { setStatus("此语言暂不可用，请选择其他语言或在设置中检查资源。"); openSettings(); return }
    if engine == .alibaba { startCloud(); return }
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
        guard let self, self.running, !self.finishing, self.generation == epoch else { return }
        self.log.record("transport", event, metrics: metrics, error: error)
        switch event {
        case "ready": self.setStatus("已准备好，允许屏幕广播后就能收音。")
        case "connected": self.broadcastConnected = true; self.updateControls(); self.setStatus("已连接，播放你想听懂的内容。")
        case "ended": self.finishSession(reason: event)
        case "failed", "listener_failed": self.stopSession(reason: event)
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
    if engine == .apple {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: selection.source)), recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
      log.record("speech", "local_unavailable"); setStatus("所选语言的本地识别暂不可用，请换语言或稍后重新检查。"); updateControls(); return
    }
    self.recognizer = recognizer
    translator = nil
    if !selection.target.isEmpty {
      guard #available(iOS 26.0, *), pairState == .installed else { updateControls(); return }
      translator = TranslationSession(installedSource: selection.sourceLanguage, target: selection.targetLanguage)
    }
    }
    generation += 1; bindReceiver()
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers]); try AVAudioSession.sharedInstance().setActive(true); if !testingSample { try receiver.start() }
    } catch { log.record("audio", "start_failed", error: error); receiver.stop(); cloud?.stop(); cloud = nil; testingSample = false; try? AVAudioSession.sharedInstance().setActive(false); updateControls(); setStatus("无法启动收音，错误已写入诊断。"); return }
    broadcastConnected = false; running = true; sourceFinals = 0; translationFinals = 0; cloudBytes = 0; receivedFrames = 0; seconds = 0; peak = 0; recognitionUpdates = 0; translationUpdates = 0; recognitionRestarts = 0; translationMS = 0; newest = ""; lastTranslated = ""; translationBusy = false; audioMissing = false; sessionStarted = Date(); lastAudio = .distantPast; lastJournal = .distantPast
    transcript.text = "原文等待中"; translation.text = selection.target.isEmpty ? "仅显示原文" : "译文等待中"; picture.original = "等待其他 App 的声音"; picture.translated = selection.target.isEmpty ? "仅显示原文" : "等待翻译"
    if engine == .apple { startRecognition() }; updateControls(); updateCounts()
    heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    setStatus("正在准备收音…"); log.record("session", "running"); picture.prime(); if !testingSample { picture.start() }; writeSnapshot(); if testingSample { beginSample() }
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
    guard running && !finishing else { return }
    if receivedFrames == 0 || audioMissing { log.record("audio", receivedFrames == 0 ? "first_frame" : "resumed"); setStatus("正在听，字幕会持续更新。"); audioMissing = false }
    receivedFrames += 1; seconds += Double(pcm.frameLength) / 16000; lastAudio = Date()
    if let channel = pcm.int16ChannelData?[0] { peak = (0..<Int(pcm.frameLength)).reduce(0.0) { max($0, abs(Double(channel[$1])) / 32768) } }
    if engine == .alibaba, let samples = pcm.int16ChannelData?[0] { cloud?.append(Data(bytes: samples, count: Int(pcm.frameLength) * 2)) }
    else { request?.append(pcm) }
  }
  private var metrics: [String: Double] {
    ["sourceFinals": Double(sourceFinals), "translationFinals": Double(translationFinals), "cloudBytes": Double(cloudBytes), "audioFrames": Double(receivedFrames), "audioSeconds": seconds, "recognitionUpdates": Double(recognitionUpdates), "translationUpdates": Double(translationUpdates), "peak": peak, "elapsed": Date().timeIntervalSince(sessionStarted), "translationMS": translationMS, "recognitionRestarts": Double(recognitionRestarts), "audioGapSeconds": receivedFrames == 0 ? Date().timeIntervalSince(sessionStarted) : Date().timeIntervalSince(lastAudio)]
  }
  private func writeSnapshot() { log.snapshot(running: running, pip: running && picture.active, metrics: metrics) }
  private func updateCounts() {
    let caption = running ? "当前会话" : "上次会话"
    counts.text = receivedFrames == 0 ? "尚未收到音频" : caption + String(format: " · 音频 %.1f 秒\n识别 %d 次 · 翻译 %d 次", seconds, recognitionUpdates, translationUpdates)
  }
  private func tick() {
    guard running else { return }
    updateCounts()
    if !testingSample && !finishing && (receivedFrames == 0 ? Date().timeIntervalSince(sessionStarted) : Date().timeIntervalSince(lastAudio)) > 5 && !audioMissing {
      audioMissing = true; log.record("audio", "waiting_or_gap", metrics: metrics); setStatus("等待音频：请检查广播和播放状态；受保护内容可能无法采集。")
    }
    if engine == .apple && Date().timeIntervalSince(lastRotation) > 45 { startRecognition() }
    if engine == .apple, !newest.isEmpty, newest != lastTranslated, !translationBusy, let translator {
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
  private func showDiagnosticFeedback(_ message: String) {
    diagnosticFeedback.text = message; diagnosticFeedback.isHidden = false
    UIAccessibility.post(notification: .announcement, argument: message)
  }
  @objc private func copyDiagnostics() {
    UIPasteboard.general.string = log.report()
    copyDiagnosticsButton.configuration?.title = "已复制诊断"
    showDiagnosticFeedback("诊断已复制，可粘贴到反馈消息中。内容不含音频、字幕或密钥。")
  }
  @objc private func exportDiagnostics() {
    do {
      let url = try log.export(); let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      let source = presenter.view!
      sheet.popoverPresentationController?.sourceView = source; sheet.popoverPresentationController?.sourceRect = CGRect(x: source.bounds.midX, y: source.bounds.midY, width: 1, height: 1)
      presenter.present(sheet, animated: true)
    } catch { showDiagnosticFeedback("无法导出诊断，请检查设备存储空间。") }
  }
  @objc private func stopPressed() {
    if finishing { stopSession(reason: "finish_cancelled") }
    else { finishSession(reason: "user_stopped") }
  }
  private func finishSession(reason: String) {
    guard running && !finishing && engine == .alibaba, let client = cloud else { stopSession(reason: reason); return }
    let epoch = generation, sample = testingSample
    finishing = true; receiver.stop(); sampleTest.cancel(); sampleTimer?.invalidate(); sampleTimer = nil; sampleData.removeAll(); picture.stop()
    setStatus("已停止收音，正在收好最后一句…"); updateControls(); log.record("cloud", "finishing")
    client.finish { [weak self, weak client] confirmed in
      guard let self, let client, self.cloud === client, self.generation == epoch else { return }
      self.log.record("cloud", confirmed ? "finish_confirmed" : "finish_incomplete", metrics: self.metrics)
      let sampleOK = confirmed && self.sourceFinals > 0 && self.translationFinals > 0
      let completedSample = sample && reason == "sample_complete"
      if sample { self.log.record("cloud", completedSample ? (sampleOK ? "synthetic_sample_passed" : "synthetic_sample_incomplete") : "synthetic_sample_stopped", metrics: self.metrics) }
      self.stopSession(reason: reason)
      self.setStatus(completedSample ? (sampleOK ? "测试完成，已收到完整原文和译文。" : "测试结束，末句未完整返回，可重试。") : (confirmed ? (self.recognitionUpdates > 0 ? "已结束，最后的字幕留在这里。" : "已结束，收音已停止。") : "已停止，部分末句可能未返回。"))
    }
  }
  private func stopSession(reason: String) {
    let wasPending = startPending
    testingSample = false; finishing = false; sampleTest.cancel(); sampleTimer?.invalidate(); sampleTimer = nil; sampleData.removeAll()
    generation += 1; startPending = false; cloud?.stop(); cloud = nil
    guard running else { if wasPending { log.record("session", reason); log.snapshot(running: false, pip: false, metrics: [:]); setStatus("已取消连接。") }; picture.stop(); updateControls(); return }
    running = false; recognitionGeneration += 1
    heartbeat?.invalidate(); heartbeat = nil; receiver.stop(); request?.endAudio(); request = nil; recognition?.cancel(); recognition = nil
    translationWork?.cancel(); translationWork = nil; translationBusy = false
    if #available(iOS 26.0, *) { translator?.cancel() }; translator = nil
    picture.stop()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    log.record("session", reason, metrics: metrics); writeSnapshot(); updateControls(); updateCounts()
    setStatus("已停止。准备好了就再开始。")
    refreshLanguages()
  }
  private func setStatus(_ text: String) { status.text = text }
}
