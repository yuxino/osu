import UIKit
import AVKit

final class SubtitlePicture: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
  let preview = UIView()
  let layer = AVSampleBufferDisplayLayer()
  private var pip: AVPictureInPictureController?
  private var timer: Timer?
  private var wantsPicture = false
  private var stopping = false
  private var readiness: NSKeyValueObservation?
  var original = "等待其他 App 的声音"
  var translated = "Mimi · 本地字幕实验"
  var onEvent: ((String, Error?) -> Void)?
  var onStatus: ((String) -> Void)?
  var onClosed: (() -> Void)?
  private var frame: Int64 = 0

  override init() {
    super.init()
    preview.backgroundColor = .black
    preview.layer.cornerRadius = 16
    preview.clipsToBounds = true
    layer.videoGravity = .resizeAspect
    preview.layer.addSublayer(layer)
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
  func layout() { layer.frame = preview.bounds }
  func prime() {
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
  func stop() { wantsPicture = false; timer?.invalidate(); timer = nil; stopping = stopping || active; pip?.stopPictureInPicture(); layer.flushAndRemoveImage() }
  var active: Bool { pip?.isPictureInPictureActive == true }
  var diagnostics: [String: Any] { ["possible": pip?.isPictureInPicturePossible == true, "supported": AVPictureInPictureController.isPictureInPictureSupported(), "frames": frame, "layerStatus": layer.status.rawValue, "layerError": layer.error?.localizedDescription ?? ""] }

  private func render() {
    let width = 960, height = 420
    var pixel: CVPixelBuffer?
    let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
    guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixel) == kCVReturnSuccess, let pixel else { return }
    CVPixelBufferLockBaseAddress(pixel, [])
    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { CVPixelBufferUnlockBaseAddress(pixel, []); return }
    context.setFillColor(UIColor.black.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
    UIGraphicsPushContext(context)
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .left; paragraph.lineBreakMode = .byTruncatingHead
    (String(original.suffix(240)) as NSString).draw(in: CGRect(x: 36, y: 35, width: 888, height: 140), withAttributes: [.font: UIFont.systemFont(ofSize: 37, weight: .medium), .foregroundColor: UIColor(white: 0.72, alpha: 1), .paragraphStyle: paragraph])
    (String(translated.suffix(160)) as NSString).draw(in: CGRect(x: 36, y: 185, width: 888, height: 190), withAttributes: [.font: UIFont.systemFont(ofSize: 48, weight: .semibold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
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
