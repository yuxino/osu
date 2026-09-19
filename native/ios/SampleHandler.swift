import ReplayKit
import AVFoundation
import Network

final class SampleHandler: RPBroadcastSampleHandler {
  private let queue = DispatchQueue(label: "mimi.broadcast.audio")
  private var connection: NWConnection?
  private var converter: AVAudioConverter?
  private var sourceFormat: AVAudioFormat?
  private var ready = false
  private var pending = false
  private var stopped = false
  private var dropped = 0
  private var conversionFailures = 0
  private var frames = 0
  private var lastLog = Date.distantPast
  private let log = DiagnosticStore.shared
  private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

  override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
    queue.async {
      self.log.begin(source: "app_audio", target: "host")
      self.log.record("broadcast", "started")
      let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: 49371)!, using: .tcp)
      self.connection = c
      c.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          self.ready = true
          self.log.record("transport", "connected")
          self.send(["event": "started", "key": MimiWire.key])
          self.watchHost(c)
        case .failed(let error): self.log.record("transport", "failed", error: error); self.end("字幕接收器不可用：\(error.localizedDescription)")
        default: break
        }
      }
      c.start(queue: self.queue)
      self.queue.asyncAfter(deadline: .now() + 8) { [weak self] in
        guard let self, !self.ready, !self.stopped else { return }
        self.log.record("transport", "host_timeout"); self.end("请先在 osu 中开启字幕小窗，再开始广播。")
      }
    }
  }

  private func watchHost(_ c: NWConnection) {
    c.receive(minimumIncompleteLength: 1, maximumLength: 128) { [weak self] _, _, complete, error in
      guard let self, !self.stopped else { return }
      if complete || error != nil { self.log.record("transport", "host_closed", error: error); self.end("字幕会话已停止。") }
      else { self.watchHost(c) }
    }
  }

  override func broadcastPaused() { queue.async { self.log.record("broadcast", "paused"); self.send(["key": MimiWire.key, "event": "paused"]) } }
  override func broadcastResumed() { queue.async { self.log.record("broadcast", "resumed"); self.send(["key": MimiWire.key, "event": "resumed"]) } }
  override func broadcastFinished() { queue.async { self.log.record("broadcast", "finished"); self.stopped = true; self.ready = false; self.connection?.cancel(); self.connection = nil } }

  override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
    guard sampleBufferType == .audioApp else { return }
    // ReplayKit calls serially, but never queue retained audio behind network work.
    queue.sync {
      guard ready, !stopped else { return }
      guard !pending else { dropped += 1; return }
      guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
      let format = AVAudioFormat(cmAudioFormatDescription: description)
      guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))) else { return }
      pcm.frameLength = pcm.frameCapacity
      guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(pcm.frameLength), into: pcm.mutableAudioBufferList) == noErr else { return }
      if sourceFormat != format { sourceFormat = format; converter = AVAudioConverter(from: format, to: outputFormat) }
      guard let converter, let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(Double(pcm.frameLength) * 16000 / format.sampleRate) + 32) else { return }
      var supplied = false
      var error: NSError?
      converter.convert(to: output, error: &error) { _, status in
        if supplied { status.pointee = .noDataNow; return nil }
        supplied = true; status.pointee = .haveData; return pcm
      }
      guard error == nil, output.frameLength > 0, let samples = output.int16ChannelData?[0] else {
        conversionFailures += 1
        if conversionFailures == 1 { log.record("audio", "conversion_failed", error: error); send(["key": MimiWire.key, "event": "conversion_failed"]) }; return
      }
      let data = Data(bytes: samples, count: Int(output.frameLength) * 2)
      guard data.count <= 32768 else { return }
      frames += 1
      if Date().timeIntervalSince(lastLog) >= 5 { lastLog = Date(); log.record("audio", "counters", metrics: ["audioFrames": Double(frames), "dropped": Double(dropped), "conversionFailures": Double(conversionFailures)]) }
      send(["key": MimiWire.key, "audio": data.base64EncodedString(), "dropped": dropped, "conversionFailures": conversionFailures])
    }
  }

  private func send(_ object: [String: Any]) {
    guard !pending, ready, let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    pending = true
    connection?.send(content: data + Data([10]), completion: .contentProcessed { [weak self] error in
      guard let self else { return }; self.pending = false
      if let error { self.log.record("transport", "send_failed", error: error); self.end("音频传输中断：\(error.localizedDescription)") }
    })
  }
  private func end(_ message: String) {
    guard !stopped else { return }; log.record("broadcast", "ended"); stopped = true; ready = false; connection?.cancel()
    finishBroadcastWithError(NSError(domain: "MimiPrototype", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
  }
}
