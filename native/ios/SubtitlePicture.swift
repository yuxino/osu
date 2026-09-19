import UIKit
import AVKit

final class SubtitlePreviewView: UIView {
  var onLayout: (() -> Void)?
  override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
}

final class SubtitlePicture: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
  let preview = SubtitlePreviewView()
  let layer = AVSampleBufferDisplayLayer()
  private let still = UIView()
  private let stillOriginal = UILabel(), stillTranslated = UILabel()
  private var pip: AVPictureInPictureController?
  private var timer: Timer?
  private var wantsPicture = false
  private var stopping = false
  private var readiness: NSKeyValueObservation?
  var original = "播放一段你想听懂的内容" { didSet { updateAccessibility() } }
  var translated = "字幕会出现在这里" { didSet { updateAccessibility() } }
  private func updateAccessibility() {
    preview.accessibilityLabel = "字幕"; preview.accessibilityValue = original + "\n" + translated
    updateStillText()
  }
  func showStill() { if timer == nil { still.isHidden = false }; render() }
  var onEvent: ((String, Error?) -> Void)?
  var onStatus: ((String) -> Void)?
  var onClosed: (() -> Void)?
  private var frame: Int64 = 0

  override init() {
    super.init()
    preview.isAccessibilityElement = true; preview.accessibilityTraits = .staticText; updateAccessibility()
    preview.backgroundColor = .black
    preview.layer.cornerRadius = 20
    preview.clipsToBounds = true
    preview.onLayout = { [weak self] in self?.layout() }
    layer.videoGravity = .resizeAspect
    preview.layer.addSublayer(layer)
    // A native still remains readable when the timed video layer has no live frames.
    still.backgroundColor = .black; still.isUserInteractionEnabled = false; preview.addSubview(still)
    for label in [stillOriginal, stillTranslated] { label.numberOfLines = 0; label.lineBreakMode = .byWordWrapping; label.adjustsFontForContentSizeCategory = true; still.addSubview(label) }
    stillOriginal.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 15)); stillOriginal.textColor = UIColor(white: 0.68, alpha: 1)
    stillTranslated.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 22, weight: .semibold)); stillTranslated.textColor = .white
    var timebase: CMTimebase?
    CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
    if let timebase { layer.controlTimebase = timebase; CMTimebaseSetTime(timebase, time: .zero); CMTimebaseSetRate(timebase, rate: 1) }
    if AVPictureInPictureController.isPictureInPictureSupported() {
      pip = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: layer, playbackDelegate: self))
      pip?.delegate = self
      pip?.requiresLinearPlayback = true
      readiness = pip?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] controller, _ in
        DispatchQueue.main.async {
          guard let self, self.wantsPicture, !self.stopping, controller.isPictureInPicturePossible else { return }
          controller.startPictureInPicture()
        }
      }
    }
  }
  deinit { timer?.invalidate() }
  func layout() {
    layer.frame = preview.bounds; still.frame = preview.bounds
    let width = max(0, preview.bounds.width - 32), height = preview.bounds.height
    stillOriginal.frame = CGRect(x: 16, y: 16, width: width, height: height * 0.35)
    stillTranslated.frame = CGRect(x: 16, y: height * 0.45, width: width, height: height * 0.48)
    updateStillText()
  }
  private func updateStillText() {
    for (label, text) in [(stillOriginal, original), (stillTranslated, translated)] {
      guard label.bounds.width > 0, label.bounds.height > 0 else { continue }
      label.text = fittingTail(text, size: label.bounds.size, attributes: [.font: label.font!])
    }
  }
  // Keep the newest words together instead of truncating the final line mid-word.
  private func fittingTail(_ text: String, size: CGSize, attributes: [NSAttributedString.Key: Any]) -> String {
    var visible = String(text.suffix(400)), clipped = text.count > 400
    func removeLeadingWord() {
      if let split = visible.firstIndex(where: { $0.isWhitespace }), visible.distance(from: visible.startIndex, to: split) < 32 {
        visible = String(visible[visible.index(after: split)...]).trimmingCharacters(in: .whitespacesAndNewlines)
      } else { visible.removeFirst() }
    }
    if clipped, !visible.isEmpty { removeLeadingWord() }
    while !visible.isEmpty {
      let candidate = clipped ? "… " + visible : visible
      let measured = (candidate as NSString).boundingRect(with: CGSize(width: size.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
      if ceil(measured.height) <= floor(size.height) { return candidate }
      removeLeadingWord(); clipped = true
    }
    return ""
  }
  func prime() {
    still.isHidden = true
    guard timer == nil else { return }
    render()
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.render() }
  }
  func start() {
    wantsPicture = true
    prime()
    guard !stopping else { return }
    guard let pip else { onStatus?("此设备不支持画中画"); return }
    guard pip.isPictureInPicturePossible else { onStatus?("正在准备字幕小窗，就绪后会自动打开"); return }
    pip.startPictureInPicture()
  }
  func stop() { wantsPicture = false; timer?.invalidate(); timer = nil; stopping = stopping || active; pip?.stopPictureInPicture(); layer.flushAndRemoveImage(); still.isHidden = false }
  var active: Bool { pip?.isPictureInPictureActive == true }
  var diagnostics: [String: Any] { ["possible": pip?.isPictureInPicturePossible == true, "supported": AVPictureInPictureController.isPictureInPictureSupported(), "frames": frame, "layerStatus": layer.status.rawValue, "layerError": layer.error?.localizedDescription ?? ""] }

  private func render() {
    let width = 960, height = 576
    var pixel: CVPixelBuffer?
    let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
    guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixel) == kCVReturnSuccess, let pixel else { return }
    CVPixelBufferLockBaseAddress(pixel, [])
    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { CVPixelBufferUnlockBaseAddress(pixel, []); return }
    context.setFillColor(UIColor.black.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
    UIGraphicsPushContext(context)
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .left; paragraph.lineBreakMode = .byWordWrapping; paragraph.lineSpacing = 7
    func drawLatest(_ text: String, rect: CGRect, font: UIFont, color: UIColor) {
      let scaledFont = UIFontMetrics.default.scaledFont(for: font, maximumPointSize: font.pointSize * 1.6)
      let attributes: [NSAttributedString.Key: Any] = [.font: scaledFont, .foregroundColor: color, .paragraphStyle: paragraph]
      let visible = fittingTail(text, size: rect.size, attributes: attributes)
      (visible as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
    }
    drawLatest(original, rect: CGRect(x: 46, y: 44, width: 868, height: 175), font: .systemFont(ofSize: 40, weight: .regular), color: UIColor(white: 0.68, alpha: 1))
    drawLatest(translated, rect: CGRect(x: 46, y: 255, width: 868, height: 260), font: .systemFont(ofSize: 59, weight: .semibold), color: .white)
    UIGraphicsPopContext(); CVPixelBufferUnlockBaseAddress(pixel, [])
    var description: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &description)
    guard let description else { return }
    let now = layer.controlTimebase.map { CMTimebaseGetTime($0) } ?? CMTime(value: frame, timescale: 2)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 2), presentationTimeStamp: now, decodeTimeStamp: .invalid)
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
  func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { false }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion: @escaping () -> Void) { completion() }
  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { wantsPicture = false; onEvent?("started", nil); onStatus?("字幕小窗已开启") }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) { onEvent?("failed", error); onStatus?("小窗启动失败，错误代码已写入诊断。") }
  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    let programmatic = stopping; stopping = false; onEvent?("stopped", nil)
    if wantsPicture { start() } else if !programmatic { onClosed?() }
  }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(true) }
}
