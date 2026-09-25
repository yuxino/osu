import UIKit
import AVKit

final class SubtitlePreviewView: UIView {
  var onLayout: (() -> Void)?
  var onDraw: ((CGContext, CGRect) -> Void)?
  override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
  override func draw(_ rect: CGRect) { if let context = UIGraphicsGetCurrentContext() { onDraw?(context, bounds) } }
}

final class SubtitlePicture: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
  let preview = SubtitlePreviewView()
  private var layer: AVSampleBufferDisplayLayer?
  private var pip: AVPictureInPictureController?
  private var timer: Timer?
  private var animationTimer: Timer?
  private var transitionStarted = -Double.infinity
  private var sourceTrack = LyricTrack(), translationTrack = LyricTrack()
  private var translationEnabled = true
  private var wantsPicture = false
  private var starting = false
  private var stopping = false
  private var lastStartAttempt = Date.distantPast
  private var readiness: NSKeyValueObservation?
  var showsOriginal = false { didSet { updateAccessibility(); showStill() } }
  var original = "播放一段你想听懂的内容" { didSet { updateAccessibility() } }
  var translated = "字幕会出现在这里" { didSet { updateAccessibility() } }
  private func updateAccessibility() {
    preview.accessibilityLabel = "字幕"
    preview.accessibilityValue = translationEnabled ? (showsOriginal ? original + "\n" + translated : translated) : original
    preview.setNeedsDisplay()
  }
  func showStill() {
    preview.setNeedsDisplay()
    if timer != nil { render() }
  }
  func resetLyrics(original: String, translated: String, translationEnabled: Bool = true) {
    animationTimer?.invalidate(); animationTimer = nil; transitionStarted = -Double.infinity
    sourceTrack = LyricTrack(); translationTrack = LyricTrack(); self.translationEnabled = translationEnabled
    self.original = original; self.translated = translated
  }
  func updateOriginal(_ text: String, id: String, final: Bool) {
    let advances = sourceTrack.update(text, id: id, final: final)
    original = sourceTrack.current?.text ?? original
    if advances && !translationEnabled { animateNextLine() }
  }
  func updateTranslation(_ text: String, id: String, final: Bool) {
    let advances = translationTrack.update(text, id: id, final: final)
    translated = translationTrack.current?.text ?? translated
    if advances && translationEnabled { animateNextLine() }
  }
  private func animateNextLine() {
    animationTimer?.invalidate(); animationTimer = nil
    guard !UIAccessibility.isReduceMotionEnabled else { transitionStarted = -Double.infinity; showStill(); return }
    transitionStarted = CACurrentMediaTime()
    // Smooth frames only during a 360 ms line change; idle PiP stays at 2 fps.
    let animation = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      self.showStill()
      if CACurrentMediaTime() - self.transitionStarted >= 0.36 { timer.invalidate(); self.animationTimer = nil }
    }
    animationTimer = animation; RunLoop.main.add(animation, forMode: .common); showStill()
  }
  private func drawLyrics(in context: CGContext, bounds: CGRect) {
    let track = translationEnabled ? translationTrack : sourceTrack
    let progress = UIAccessibility.isReduceMotionEnabled ? 1 : CGFloat(min(1, (CACurrentMediaTime() - transitionStarted) / 0.36))
    LyricsPainter.draw(in: context, bounds: bounds, previous: track.previous?.text ?? "", current: translationEnabled ? translated : original, original: translationEnabled && showsOriginal ? original : "", progress: progress)
  }
  var onEvent: ((String, Error?) -> Void)?
  var onStatus: ((String) -> Void)?
  private var frame: Int64 = 0

  override init() {
    super.init()
    preview.isAccessibilityElement = true; preview.accessibilityTraits = .staticText; updateAccessibility()
    preview.backgroundColor = .black
    preview.layer.cornerRadius = 20
    preview.clipsToBounds = true
    preview.onLayout = { [weak self] in self?.layout() }
    preview.onDraw = { [weak self] context, bounds in
      // The sample-buffer layer supplies its own inline image / PiP placeholder.
      // Keep the idle drawing out of that layer's background to avoid double text.
      guard let self, self.layer == nil else { return }
      self.drawLyrics(in: context, bounds: bounds)
    }
  }
  // Opening Osu only draws native text. Register media after broadcast authorization.
  private func prepareMedia() {
    guard layer == nil else { return }
    let layer = AVSampleBufferDisplayLayer(); self.layer = layer; preview.setNeedsDisplay()
    layer.videoGravity = .resizeAspect; preview.layer.insertSublayer(layer, at: 0); layer.frame = preview.bounds
    var timebase: CMTimebase?
    CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
    if let timebase { layer.controlTimebase = timebase; CMTimebaseSetTime(timebase, time: .zero); CMTimebaseSetRate(timebase, rate: 1) }
    if AVPictureInPictureController.isPictureInPictureSupported() {
      pip = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: layer, playbackDelegate: self))
      pip?.delegate = self
      pip?.requiresLinearPlayback = true
      pip?.canStartPictureInPictureAutomaticallyFromInline = true
      readiness = pip?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] controller, _ in
        DispatchQueue.main.async {
          guard let self, self.pip === controller else { return }
          self.attemptStart()
        }
      }
    }
  }
  deinit { timer?.invalidate(); animationTimer?.invalidate() }
  func layout() {
    layer?.frame = preview.bounds; preview.setNeedsDisplay()
  }
  private func prime() {
    prepareMedia()
    guard timer == nil else { return }
    render()
    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.render(); self?.attemptStart() }
    self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    pip?.invalidatePlaybackState()
  }
  func start() {
    guard !active || stopping else { onStatus?("字幕小窗已开启"); return }
    wantsPicture = true
    guard !stopping else { return }
    prime()
    guard pip != nil else { onStatus?("此设备不支持画中画"); return }
    onStatus?("正在准备字幕小窗。如果已有视频小窗，请先将视频恢复到原 App 内播放。")
    attemptStart()
  }
  private func attemptStart() {
    guard wantsPicture, !starting, !stopping, let pip, !pip.isPictureInPictureActive, pip.isPictureInPicturePossible,
          Date().timeIntervalSince(lastStartAttempt) >= 1 else { return }
    // Another app's PiP can make start a no-op without changing `possible`.
    // Keep the explicit request pending until its delegate actually starts.
    lastStartAttempt = Date(); pip.startPictureInPicture()
  }
  func stop() {
    wantsPicture = false; timer?.invalidate(); timer = nil
    animationTimer?.invalidate(); animationTimer = nil; transitionStarted = -Double.infinity
    pip?.invalidatePlaybackState()
    if let timebase = layer?.controlTimebase { CMTimebaseSetRate(timebase, rate: 0) }
    layer?.flushAndRemoveImage(); preview.setNeedsDisplay()
    if active || starting { stopping = true; pip?.stopPictureInPicture() } else { releaseMedia() }
  }
  private func releaseMedia() {
    readiness?.invalidate(); readiness = nil
    pip?.delegate = nil; pip = nil
    layer?.removeFromSuperlayer(); layer = nil; stopping = false; starting = false; lastStartAttempt = .distantPast
  }
  var active: Bool { pip?.isPictureInPictureActive == true }
  var diagnostics: [String: Any] { ["possible": pip?.isPictureInPicturePossible == true, "supported": AVPictureInPictureController.isPictureInPictureSupported(), "frames": frame, "mediaCreated": layer != nil, "layerStatus": layer?.status.rawValue ?? 0, "layerError": layer?.error?.localizedDescription ?? ""] }
  var metrics: [String: Double] { ["pipPossible": pip?.isPictureInPicturePossible == true ? 1 : 0, "pipFrames": Double(frame), "pipStarting": starting ? 1 : 0, "pipLayerStatus": Double(layer?.status.rawValue ?? 0)] }

  private func render() {
    guard let layer else { return }
    let width = Int(LyricsPainter.size.width), height = Int(LyricsPainter.size.height)
    var pixel: CVPixelBuffer?
    let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
    guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixel) == kCVReturnSuccess, let pixel else { return }
    CVPixelBufferLockBaseAddress(pixel, [])
    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { CVPixelBufferUnlockBaseAddress(pixel, []); return }
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
    UIGraphicsPushContext(context)
    drawLyrics(in: context, bounds: CGRect(origin: .zero, size: LyricsPainter.size))
    UIGraphicsPopContext(); CVPixelBufferUnlockBaseAddress(pixel, [])
    var description: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &description)
    guard let description else { return }
    let now = layer.controlTimebase.map { CMTimebaseGetTime($0) } ?? CMTime(value: frame, timescale: 2)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: animationTimer == nil ? 2 : 30), presentationTimeStamp: now, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample)
    if layer.status == .failed { layer.flush() }
    if let sample, layer.isReadyForMoreMediaData {
      if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
      }
      layer.enqueue(sample); frame += 1
    }
  }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}
  func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange { CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity) }
  func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { timer == nil }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion: @escaping () -> Void) { completion() }
  func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    guard pip === pictureInPictureController else { return }; starting = true; onEvent?("starting", nil)
  }
  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    guard pip === pictureInPictureController else { return }; starting = false
    if stopping { pictureInPictureController.stopPictureInPicture(); return }
    onEvent?("started", nil); onStatus?("字幕小窗已开启")
  }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    guard pip === pictureInPictureController else { return }; starting = false
    if stopping { let restart = wantsPicture; releaseMedia(); if restart { start() }; return }
    // Transient failures (another video window active, session interrupted) are
    // retried by the render timer until the window becomes possible again.
    onEvent?("failed", error); onStatus?("字幕小窗暂时无法启动，收音继续；条件允许时自动恢复。")
  }
  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    guard pip === pictureInPictureController else { return }
    let programmatic = stopping; stopping = false; onEvent?("stopped", nil)
    if programmatic {
      timer?.invalidate(); timer = nil; releaseMedia(); preview.setNeedsDisplay()
      return
    }
    // The window was taken over (another app's video PiP) or dismissed. Keep
    // the media primed and re-acquire automatically; the render timer keeps
    // frames flowing so restored content is immediate.
    onStatus?("字幕小窗被其他视频小窗接管，收音继续；对方关闭后自动恢复。")
    preview.setNeedsDisplay(); attemptStart()
  }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
}
