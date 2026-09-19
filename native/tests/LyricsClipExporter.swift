import UIKit
import AVFoundation

/// A deterministic clip of the production painter; fixed authored text only.
@MainActor enum LyricsClipExporter {
  static func write(to url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let width = Int(LyricsPainter.size.width), height = Int(LyricsPainter.size.height)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? failure() }
    writer.startSession(atSourceTime: .zero)
    let lines = [
      ("窓の外は、少しずつ明るくなってきた。", "窗外，正一点一点亮起来。"),
      ("今日は、いつもと違う道を歩いてみよう。", "今天，走一条不一样的路吧。"),
      ("知らない言葉も、少しずつ分かるようになる。", "陌生的话语，也会慢慢听懂。")
    ]
    for frame in 0..<270 {
      let deadline = Date().addingTimeInterval(10)
      while !input.isReadyForMoreMediaData {
        guard writer.status == .writing, Date() < deadline else { writer.cancelWriting(); throw writer.error ?? failure() }
        try await Task.sleep(nanoseconds: 10_000_000)
      }
      try autoreleasepool {
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw failure() }
        CVPixelBufferLockBaseAddress(buffer, []); defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { throw failure() }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context); defer { UIGraphicsPopContext() }
        let index = frame / 90, progress: CGFloat = index == 0 ? 1 : min(1, CGFloat(frame % 90) / 10.8)
        LyricsPainter.draw(in: context, bounds: CGRect(origin: .zero, size: LyricsPainter.size), previous: index == 0 ? "" : lines[index - 1].1, current: lines[index].1, original: "", progress: progress)
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error ?? failure() }
      }
    }
    input.markAsFinished(); await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? failure() }
  }
  private static func failure() -> Error { NSError(domain: "OsuLyricsClip", code: 1) }
}
