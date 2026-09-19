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
  private var engine: SubtitleEngine = .alibaba
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
  private var capture = CaptureReadiness()
  private var lastCaptureState = CaptureReadiness.State.idle
  private var captureGuide: CapturePermissionController?
  private var mediaActive = false
  private var captureHandoffTask: UIBackgroundTaskIdentifier = .invalid
  private var finishBackgroundTask: UIBackgroundTaskIdentifier = .invalid
  private let backgroundTasks: BackgroundTaskProvider
  private let picture: SubtitlePicture
  private let receiver = AudioReceiver()
  private let log = DiagnosticStore.shared
  private var audioDelivery: PCMDeliveryBuffer?
  private let status = UILabel(), transcript = UILabel(), translation = UILabel(), counts = UILabel(), languageStatus = UILabel()
  private let sourceButton = UIButton(type: .system), targetButton = UIButton(type: .system)
  private let languageRow = UIStackView()
  private var prepareButton: UIButton!, startButton: UIButton!
  private var selection = LanguageSelection(source: "auto", target: "zh")
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
  private var translationBusy = false
  private let pictureStoppedMessage = "字幕小窗已关闭，收音也已停止。iPhone 的视频小窗会替换字幕小窗；使用 Osu 时，请将视频留在原 App 内播放。"

  // The isolated simulator harness substitutes an in-memory socket and dummy key.
  // Normal app startup uses the fixed provider endpoint and device Keychain.
  init(makeCloudClient: (() -> AlibabaClient)? = nil, readCloudCredential: (() throws -> String?)? = nil, picture: SubtitlePicture = SubtitlePicture(), backgroundTasks: BackgroundTaskProvider? = nil) {
    SubtitleDefaults.migrate(.standard)
    engine = SubtitleEngine(rawValue: UserDefaults.standard.string(forKey: "mimi.engine") ?? "alibaba") ?? .alibaba
    let prefix = engine == .alibaba ? "mimi.alibaba." : "mimi."
    selection = .init(source: UserDefaults.standard.string(forKey: prefix + "source") ?? (engine == .alibaba ? "auto" : "ja-JP"), target: UserDefaults.standard.string(forKey: prefix + "target") ?? (engine == .alibaba ? "zh" : "zh-Hans"))
    if engine == .apple { selection = selection.localSelection }
    self.makeCloudClient = makeCloudClient ?? { AlibabaClient() }
    self.readCloudCredential = readCloudCredential ?? { try CloudCredentialStore.read() }
    self.picture = picture; self.backgroundTasks = backgroundTasks ?? .application
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("Use init()") }

  override func viewDidLoad() {
    super.viewDidLoad()
    if log.previousWasRunning() { log.record("session", "previous_interrupted_unknown_cause") }
    log.record("app", "opened")
    log.snapshot(running: false, pip: false, metrics: [:])
    buildHome()
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: MimiPrototypeController, _: UITraitCollection) in
      controller.updateLanguageLayout()
    }
    picture.onStatus = { [weak self] text in if self?.capture.connected == true { self?.setStatus(text) } }
    picture.onEvent = { [weak self] event, error in
      self?.log.record("pip", event, error: error)
      if event == "started" { self?.endCaptureHandoff() }
    }
    picture.onClosed = { [weak self] in self?.finishSession(reason: "pip_closed") }
    for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification, AVAudioSession.interruptionNotification, UIContentSizeCategory.didChangeNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        guard let self else { return }
        if note.name == UIContentSizeCategory.didChangeNotification { self.picture.showStill(); return }
        if note.name == AVAudioSession.interruptionNotification {
          if self.mediaActive && (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { self.log.record("audio", "interrupted"); self.stopSession(reason: "audio_interrupted"); self.setStatus("系统中断了字幕会话，收音已停止。准备好了可重新开始。") }
        } else {
          let foreground = note.name == UIApplication.didBecomeActiveNotification
          self.log.record("app", foreground ? "foreground" : "background")
          if foreground && !self.running && !self.startPending && !self.downloading { self.refreshLanguages() }
          if foreground && self.running && !self.testingSample && !self.finishing && !self.capture.connected {
            self.beginCaptureHandoff()
            do {
              if try self.receiver.refreshUnconnectedListener() { self.capture.start(); self.updateCaptureStatus(); self.log.record("transport", "listener_refreshed_after_resume") }
              self.showCaptureGuide()
            } catch { self.stopSession(reason: "receiver_resume_failed"); self.setStatus("无法恢复收音连接，请重新开始。") }
          }
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
    settings.configuration?.contentInsets = .zero; settings.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 20, weight: .regular)
    settings.widthAnchor.constraint(equalToConstant: 48).isActive = true; header.addArrangedSubview(settings); stack.addArrangedSubview(header)
    let intro = label("听懂此刻。", size: 30, weight: .semibold); stack.addArrangedSubview(intro)
    let subtitle = label("为正在播放的声音，添上你的语言。", size: 15); subtitle.textColor = .secondaryLabel; stack.addArrangedSubview(subtitle); stack.setCustomSpacing(28, after: subtitle)
    configureChoice(sourceButton); configureChoice(targetButton)
    languageRow.spacing = 10; languageRow.addArrangedSubview(sourceButton); languageRow.addArrangedSubview(targetButton)
    updateLanguageLayout(); stack.addArrangedSubview(languageRow)
    picture.original = "播放一段你想听懂的内容"; picture.translated = "字幕会出现在这里"
    stack.addArrangedSubview(picture.preview); picture.preview.heightAnchor.constraint(equalTo: picture.preview.widthAnchor, multiplier: LyricsPainter.aspect).isActive = true
    status.numberOfLines = 0; status.font = UIFont.preferredFont(forTextStyle: .subheadline); status.adjustsFontForContentSizeCategory = true; status.textColor = .secondaryLabel; status.text = selection.source == "auto" ? CaptureReadiness.State.idle.message : "准备好了就开始。声音语言可在上方随时调整。"; stack.addArrangedSubview(status)
    prepareButton = button("准备本地语言包", #selector(prepareLanguages)); stack.addArrangedSubview(prepareButton)
    startButton = button("开始听", #selector(primaryPressed)); var primary = UIButton.Configuration.filled(); primary.baseBackgroundColor = .label; primary.baseForegroundColor = .systemBackground; primary.cornerStyle = .medium; primary.contentInsets = .init(top: 18, leading: 24, bottom: 18, trailing: 24); primary.title = "开始听"; primary.image = UIImage(systemName: "waveform"); primary.imagePadding = 10; startButton.configurationUpdateHandler = nil; startButton.configuration = primary; stack.addArrangedSubview(startButton)
    broadcastRow.axis = .horizontal; broadcastRow.spacing = 12; broadcastRow.alignment = .center
    broadcastRow.addArrangedSubview(button("允许收音", #selector(showCaptureGuide))); stack.addArrangedSubview(broadcastRow)
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
  private func updateLanguageLayout() {
    let largeText = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    languageRow.axis = largeText ? .vertical : .horizontal
    languageRow.distribution = largeText ? .fill : .fillEqually
  }
  @objc private func primaryPressed() { if running || startPending { stopPressed() } else { startPressed() } }
  @objc private func showPicture() { guard running && mediaActive && !finishing && !testingSample else { return }; picture.start() }
  @objc private func showCaptureGuide() {
    guard running, !testingSample, !finishing, !capture.connected, captureGuide == nil, presentedViewController == nil, UIApplication.shared.applicationState == .active else { return }
    let guide = CapturePermissionController(); captureGuide = guide
    guide.onCancelled = { [weak self] in
      guard let self, !self.capture.connected else { return }
      self.captureGuide = nil; self.stopSession(reason: "capture_cancelled"); self.setStatus("尚未允许收音，当前没有采集声音。准备好了可重新开始。")
    }
    guide.modalPresentationStyle = .pageSheet; guide.sheetPresentationController?.detents = [.large()]; guide.sheetPresentationController?.prefersGrabberVisible = true
    present(guide, animated: true)
  }
  @objc private func openSettings() {
    let page = UIViewController(); page.view.backgroundColor = .systemBackground; settingsPage = page
    let stack = pageStack(in: page.view, top: 28)
    let heading = UIStackView(arrangedSubviews: [label("设置", size: 28, weight: .semibold), button("完成", #selector(closeSettings))]); heading.axis = .horizontal; heading.spacing = 24; stack.addArrangedSubview(heading)
    stack.addArrangedSubview(engineButton); stack.addArrangedSubview(keyButton); stack.addArrangedSubview(languageStatus)
    stack.addArrangedSubview(button("重新检查本地语言", #selector(refreshPressed)))
    stack.addArrangedSubview(label("使用方法", size: 18, weight: .semibold))
    stack.addArrangedSubview(label("默认自动识别原文并翻译成中文。需要指定语言时，再点首页的语言选项。\n\n点「开始听」后按提示确认 Osu Audio 的系统广播。小窗出现后切回播放内容的网页或 App。关闭小窗也会停止收音。\n\nOsu 只处理 App 声音，丢弃视频和麦克风数据，不保存录音或字幕。部分受保护内容无法采集。广播时需关闭 iPhone 镜像。", size: 14))
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
    selection = .init(source: UserDefaults.standard.string(forKey: prefix + "source") ?? (value == .alibaba ? "auto" : "ja-JP"), target: UserDefaults.standard.string(forKey: prefix + "target") ?? (value == .alibaba ? "zh" : "zh-Hans"))
    if value == .apple { selection = selection.localSelection; setStatus("已切到设备本地。此模式需要指定声音语言；自动识别可从上方切回。") }
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
    guard !running && !startPending && engine == .alibaba && ["auto", "ja"].contains(selection.source) else { return }
    sampleRepeats = 1; testingSample = true; dismissSettingsThen { [weak self] in self?.startCloud() }
  }
  @objc private func startLongSampleTest() {
    guard !running && !startPending && engine == .alibaba && ["auto", "ja"].contains(selection.source) && AlibabaProtocol.valid(source: selection.source, target: selection.target) else { return }
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
      guard try readCloudCredential() != nil else { testingSample = false; setStatus("请先在设置中添加阿里云密钥。"); openSettings(); return }
      log.begin(source: selection.source, target: selection.target); log.snapshot(running: false, pip: false, metrics: [:])
      // Permission can take as long as the user needs. Keep only the local
      // receiver ready until the broadcast authenticates; an idle cloud socket
      // can otherwise expire before any app audio reaches it.
      if testingSample { startPending = true; generation += 1; connectCloud() }
      else { startSession() }
    } catch {
      testingSample = false; updateControls(); setStatus("无法读取阿里云密钥，请在设置中检查。"); log.record("cloud", "credential_unavailable")
    }
  }
  private func connectCloud() {
    guard cloud == nil, !finishing, (running && capture.connected) || (testingSample && startPending) else { return }
    do {
      guard let key = try readCloudCredential() else { throw AlibabaProtocol.Failure.invalidConfiguration }
      startPending = true; updateControls(); setStatus("正在连接阿里云同传…"); log.record("cloud", "connecting")
      let client = makeCloudClient(); cloud = client
      client.onReady = { [weak self, weak client] in
        guard let self, let client, self.cloud === client, self.startPending, !self.finishing else { return }
        self.log.record("cloud", "ready")
        if self.testingSample { self.startSession() }
        else {
          // The receiver and its queued audio already belong to this session.
          // Restarting it here would discard the first audio and invalidate callbacks.
          self.startPending = false; self.updateControls()
          self.setStatus(self.capture.state(at: ProcessInfo.processInfo.systemUptime).message)
        }
      }
      client.onSource = { [weak self, weak client] text, id, final in
        guard let self, let client, self.cloud === client, self.running else { return }
        self.recognitionUpdates += 1; self.transcript.text = text; self.picture.updateOriginal(text, id: id, final: final)
        if self.recognitionUpdates == 1 { self.log.record("cloud", "first_source") }
        if final { self.sourceFinals += 1; self.log.record("cloud", "source_final") }
      }
      client.onTranslation = { [weak self, weak client] text, id, final in
        guard let self, let client, self.cloud === client, self.running else { return }
        self.translationUpdates += 1; self.translation.text = text; self.picture.updateTranslation(text, id: id, final: final)
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
      log.record("cloud", "start_failed"); stopSession(reason: "cloud_start_failed"); setStatus("无法启动阿里云，请检查密钥和语言配置。")
    }
  }
  private func updateControls() {
    let busy = running || startPending || downloading
    cloudTestSection.isHidden = engine != .alibaba
    sampleButton.isEnabled = !busy && ["auto", "ja"].contains(selection.source) && AlibabaProtocol.valid(source: selection.source, target: selection.target)
    sampleButton.configuration?.title = selection.source == "auto" ? "测试自动识别" : "测试日语同传"
    longSampleButton.isEnabled = sampleButton.isEnabled
    engineButton.isEnabled = !busy; keyButton.isEnabled = !busy; keyButton.isHidden = engine != .alibaba
    engineButton.configuration?.title = engine == .apple ? "服务 · Apple 设备本地" : "服务 · 阿里云实时同传"
    sourceButton.isEnabled = !busy; targetButton.isEnabled = !busy
    prepareButton.isHidden = engine == .alibaba || busy || pairState != .needsDownload
    prepareButton.isEnabled = !busy && (pairState == .needsDownload || pairState == .installed)
    startButton.isEnabled = running || startPending || (!busy && pairState != .checking)
    startButton.configuration?.title = finishing ? "立即结束" : (running ? (capture.connected || testingSample ? "停止" : "取消") : (startPending ? "取消连接" : "开始听"))
    startButton.configuration?.image = UIImage(systemName: running || startPending ? "stop.fill" : "waveform")
    sourceButton.configuration?.title = selection.source == "auto" ? "自动识别" : LanguageSelection.display(selection.source)
    sourceButton.configuration?.subtitle = selection.source == "auto" ? "声音 · 可手动指定" : "声音"
    targetButton.configuration?.title = selection.target.isEmpty ? "仅原文" : LanguageSelection.display(selection.target)
    targetButton.configuration?.subtitle = "字幕"
    broadcastRow.isHidden = !running || testingSample || finishing || capture.connected
    pipButton.isHidden = !running || testingSample || finishing || !mediaActive
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
    selection = engine == .apple ? value.localSelection : value; translator = nil
    let prefix = engine == .alibaba ? "mimi.alibaba." : "mimi."
    UserDefaults.standard.set(selection.source, forKey: prefix + "source"); UserDefaults.standard.set(selection.target, forKey: prefix + "target")
    if engine == .apple && !value.target.isEmpty && selection.target.isEmpty { setStatus("声音和字幕语言相同，已切为只显示原文。") }
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
    let automatic = UIAction(title: "自动识别 · 阿里云") { [weak self] _ in
      guard let self else { return }; self.chooseEngine(.alibaba); self.choose(.init(source: "auto", target: self.selection.target))
    }
    sourceButton.menu = UIMenu(children: [automatic] + locales.map { locale in
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
    if running { showPicture(); return }
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
    let delivery = PCMDeliveryBuffer(); audioDelivery?.cancel(); audioDelivery = delivery
    receiver.onEvent = { [weak self] event, error, metrics in
      DispatchQueue.main.async {
        guard let self, self.running, !self.finishing, self.generation == epoch else { return }
        if event != "heartbeat" { self.log.record("transport", event, metrics: metrics, error: error) }
        let now = ProcessInfo.processInfo.systemUptime
        switch event {
        case "ready": self.capture.receiverReady(); self.updateCaptureStatus(); self.showCaptureGuide()
        case "connecting": self.capture.connectionStarted()
        case "connected":
          self.capture.connectionReady(at: now); self.updateCaptureStatus()
          if self.engine == .alibaba { self.connectCloud() }
          else { self.startRecognition() }
          guard self.running else { return }
          if let guide = self.captureGuide {
            self.captureGuide = nil; guide.connected { [weak self] in self?.activateCapturedMedia() }
          } else { self.activateCapturedMedia() }
        case "heartbeat", "started": self.capture.heartbeat(at: now)
        case "paused": self.capture.setPaused(true, at: now)
        case "resumed": self.capture.setPaused(false, at: now)
        case "ended": self.capture.stop(); self.updateCaptureStatus(); self.finishSession(reason: "broadcast_ended")
        case "failed", "listener_failed", "authentication_timeout": self.stopSession(reason: event); self.setStatus("收音连接已中断，请重新开始。"); return
        default: break
        }
        if self.running && !self.finishing { self.updateCaptureStatus() }
      }
    }
    receiver.onAudio = { [weak self] data in
      switch delivery.append(data) {
      case .buffered, .closed: break
      case .overflow:
        DispatchQueue.main.async { [weak self] in
          guard let self, self.generation == epoch else { return }
          self.log.record("audio", "delivery_overflow"); self.stopSession(reason: "audio_overflow"); self.setStatus("音频处理跟不上播放速度，已停止收音。请重新开始。")
        }
      case .schedule:
        DispatchQueue.main.async { [weak self] in
          guard let self, self.generation == epoch else { delivery.cancel(); return }
          while let data = delivery.next() { self.consume(data) }
        }
      }
    }
  }
  private func updateCaptureStatus() {
    guard !testingSample else { return }
    let state = capture.state(at: ProcessInfo.processInfo.systemUptime)
    guard state != lastCaptureState else { return }
    lastCaptureState = state; log.record("capture", state.rawValue); setStatus(state.message); updateControls()
    if state == .lost { stopSession(reason: "broadcast_lost"); setStatus(state.message) }
  }
  private func activateCapturedMedia() {
    guard running, !finishing, !testingSample, capture.connected, !mediaActive else { return }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true); mediaActive = true
    } catch { log.record("audio", "start_failed", error: error); stopSession(reason: "media_failed"); setStatus("无法开启字幕小窗，收音已停止。可重新开始。"); return }
    log.record("media", "activated_after_broadcast")
    if engine == .apple && request == nil { startRecognition() }
    picture.start(); updateControls()
  }
  private func beginCaptureHandoff() {
    guard captureHandoffTask == .invalid else { return }
    captureHandoffTask = backgroundTasks.begin("Connect Osu Audio") { [weak self] in
      guard let self else { return }
      self.endCaptureHandoff()
      guard self.running, !self.testingSample else { return }
      self.log.record("capture", "handoff_expired")
      if self.capture.connected {
        self.stopSession(reason: "picture_handoff_expired"); self.setStatus("字幕小窗未能开启，收音已停止。请回到 Osu 重新开始。")
      } else {
        self.receiver.stop(); self.capture.start(); self.updateCaptureStatus()
      }
    }
  }
  private func endCaptureHandoff() {
    guard captureHandoffTask != .invalid else { return }
    let task = captureHandoffTask; captureHandoffTask = .invalid
    backgroundTasks.end(task)
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
      if !testingSample { try receiver.start() }
    } catch { log.record("transport", "start_failed", error: error); receiver.stop(); cloud?.stop(); cloud = nil; testingSample = false; updateControls(); setStatus("无法准备收音，错误已写入诊断。"); return }
    capture.start(); lastCaptureState = .idle; running = true; sourceFinals = 0; translationFinals = 0; cloudBytes = 0; receivedFrames = 0; seconds = 0; peak = 0; recognitionUpdates = 0; translationUpdates = 0; recognitionRestarts = 0; translationMS = 0; newest = ""; lastTranslated = ""; translationBusy = false; sessionStarted = Date(); lastAudio = .distantPast; lastJournal = .distantPast
    if !testingSample { beginCaptureHandoff() }
    transcript.text = "原文等待中"; translation.text = selection.target.isEmpty ? "仅显示原文" : "译文等待中"
    picture.resetLyrics(original: "等待其他 App 的声音", translated: selection.target.isEmpty ? "仅显示原文" : "等待翻译", translationEnabled: !selection.target.isEmpty)
    updateControls(); updateCounts(); updateCaptureStatus()
    heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    log.record("session", "waiting_for_broadcast"); picture.showStill(); writeSnapshot(); if testingSample { beginSample() }
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
  private func consume(_ data: Data) {
    guard running && !finishing else { return }
    if receivedFrames == 0 { log.record("audio", "first_frame") }
    receivedFrames += 1; seconds += Double(data.count) / 32000; lastAudio = Date()
    peak = data.withUnsafeBytes { bytes in
      stride(from: 0, to: data.count, by: 2).reduce(0.0) { max($0, abs(Double(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: $1, as: Int16.self)))) / 32768) }
    }
    capture.audio(peak: peak, at: ProcessInfo.processInfo.systemUptime); updateCaptureStatus()
    if engine == .alibaba { cloud?.append(data) }
    else if let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true), let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 2)), let dest = pcm.int16ChannelData?[0] {
      pcm.frameLength = pcm.frameCapacity; data.copyBytes(to: UnsafeMutableRawBufferPointer(start: dest, count: data.count)); request?.append(pcm)
    }
  }
  private var metrics: [String: Double] {
    ["sourceFinals": Double(sourceFinals), "translationFinals": Double(translationFinals), "cloudBytes": Double(cloudBytes), "audioFrames": Double(receivedFrames), "audioSeconds": seconds, "recognitionUpdates": Double(recognitionUpdates), "translationUpdates": Double(translationUpdates), "peak": peak, "elapsed": Date().timeIntervalSince(sessionStarted), "translationMS": translationMS, "recognitionRestarts": Double(recognitionRestarts), "audioGapSeconds": receivedFrames == 0 ? Date().timeIntervalSince(sessionStarted) : Date().timeIntervalSince(lastAudio)].merging(picture.metrics) { _, new in new }
  }
  private func writeSnapshot() { log.snapshot(running: running && !finishing, pip: running && !finishing && picture.active, metrics: metrics, captureState: finishing ? "finishing" : (testingSample ? "sample" : capture.state(at: ProcessInfo.processInfo.systemUptime).rawValue)) }
  private func updateCounts() {
    let caption = running ? "当前会话" : "上次会话"
    counts.text = receivedFrames == 0 ? "尚未收到音频" : caption + String(format: " · 音频 %.1f 秒\n识别 %d 次 · 翻译 %d 次", seconds, recognitionUpdates, translationUpdates)
  }
  private func tick() {
    guard running else { return }
    updateCounts()
    if !testingSample && !finishing { updateCaptureStatus() }
    guard running else { return }
    if engine == .apple && mediaActive && !finishing && Date().timeIntervalSince(lastRotation) > 45 { startRecognition() }
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
    // A repeated PiP/transport callback must not cancel an in-flight final result.
    guard !finishing else { return }
    guard running && (capture.connected || testingSample || reason == "broadcast_ended") && engine == .alibaba, let client = cloud else { stopSession(reason: reason); return }
    let epoch = generation, sample = testingSample
    finishing = true
    // Keep execution until the client's bounded finish completes. Acquire before
    // releasing PiP/audio: a background app can otherwise suspend in this gap.
    finishBackgroundTask = backgroundTasks.begin("Finish Osu subtitles") { [weak self] in
      guard let self, self.finishing, self.generation == epoch else { return }
      self.log.record("cloud", "finish_background_expired")
      self.stopSession(reason: reason)
      self.setStatus(reason == "pip_closed" ? self.pictureStoppedMessage + "部分末句可能未返回。" : "已停止，部分末句可能未返回。")
    }
    guard finishBackgroundTask != .invalid else {
      log.record("cloud", "finish_background_unavailable"); stopSession(reason: reason)
      setStatus(reason == "pip_closed" ? pictureStoppedMessage + "部分末句可能未返回。" : "已停止，部分末句可能未返回。")
      return
    }
    endCaptureHandoff()
    receiver.stop(); audioDelivery?.cancel(); capture.stop(); sampleTest.cancel(); sampleTimer?.invalidate(); sampleTimer = nil; sampleData.removeAll()
    // Persist the stopped capture even if the system later terminates the app.
    writeSnapshot(); picture.stop()
    if mediaActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); mediaActive = false }
    setStatus("已停止收音，正在收好最后一句…"); updateControls(); log.record("cloud", "finishing")
    client.finish { [weak self, weak client] confirmed in
      guard let self, let client, self.cloud === client, self.generation == epoch else { return }
      self.log.record("cloud", confirmed ? "finish_confirmed" : "finish_incomplete", metrics: self.metrics)
      let sampleOK = confirmed && self.sourceFinals > 0 && self.translationFinals > 0
      let completedSample = sample && reason == "sample_complete"
      if sample { self.log.record("cloud", completedSample ? (sampleOK ? "synthetic_sample_passed" : "synthetic_sample_incomplete") : "synthetic_sample_stopped", metrics: self.metrics) }
      self.stopSession(reason: reason)
      if reason == "pip_closed" {
        self.setStatus(self.pictureStoppedMessage + (confirmed ? "" : "部分末句可能未返回。"))
        return
      }
      self.setStatus(completedSample ? (sampleOK ? "测试完成，已收到完整原文和译文。" : "测试结束，末句未完整返回，可重试。") : (confirmed ? (reason == "broadcast_ended" ? "广播已停止，最后的字幕留在这里。" : (self.recognitionUpdates > 0 ? "已结束，最后的字幕留在这里。" : "已结束，收音已停止。")) : "已停止，部分末句可能未返回。"))
    }
  }
  private func stopSession(reason: String) {
    // Save idle state and close the socket before giving up background execution.
    defer { endFinishBackgroundTask() }
    let wasPending = startPending
    endCaptureHandoff()
    if let guide = captureGuide { captureGuide = nil; guide.connected {} }
    audioDelivery?.cancel(); audioDelivery = nil; capture.stop()
    testingSample = false; finishing = false; sampleTest.cancel(); sampleTimer?.invalidate(); sampleTimer = nil; sampleData.removeAll()
    generation += 1; startPending = false; cloud?.stop(); cloud = nil
    guard running else { if wasPending { log.record("session", reason); log.snapshot(running: false, pip: false, metrics: [:]); setStatus("已取消连接。") }; picture.stop(); updateControls(); return }
    running = false; recognitionGeneration += 1
    heartbeat?.invalidate(); heartbeat = nil; receiver.stop(); request?.endAudio(); request = nil; recognition?.cancel(); recognition = nil
    translationWork?.cancel(); translationWork = nil; translationBusy = false
    if #available(iOS 26.0, *) { translator?.cancel() }; translator = nil
    picture.stop()
    if mediaActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); mediaActive = false }
    log.record("session", reason, metrics: metrics); writeSnapshot(); updateControls(); updateCounts()
    setStatus(reason == "pip_closed" ? pictureStoppedMessage : "已停止。准备好了就再开始。")
    refreshLanguages()
  }
  private func endFinishBackgroundTask() {
    guard finishBackgroundTask != .invalid else { return }
    let task = finishBackgroundTask; finishBackgroundTask = .invalid
    backgroundTasks.end(task)
  }
  private func setStatus(_ text: String) { status.text = text }
}
