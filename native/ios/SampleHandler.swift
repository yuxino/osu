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
  private var backlog = PCMBacklog()
  private var events: [String] = []
  private var pump: DispatchSourceTimer?
  private var lastHeartbeat = Date.distantPast
  private var heartbeatDue = false
  private var stopped = false
  private var configurationBytes = Data()
  private var islandRequested = false
  private var island: BroadcastIslandSession?
  private let islandDelivery = PCMDeliveryBuffer()
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
      c.stateUpdateHandler = { [weak self, weak c] state in
        guard let self, let c, self.connection === c, !self.stopped else { return }
        switch state {
        case .ready:
          self.ready = true
          self.log.record("transport", "connected")
          self.sendEvent("started")
          self.startPump()
          self.watchHost(c)
        case .waiting(let error):
          self.log.record("transport", "waiting", error: error)
          // The host may just be returning from the system picker or lock screen.
          // Retry the local connection within the existing eight-second deadline.
          self.queue.asyncAfter(deadline: .now() + 0.5) { [weak self, weak c] in
            guard let self, let c, self.connection === c, !self.stopped, case .waiting = c.state else { return }
            c.restart()
          }
        case .failed(let error): self.log.record("transport", "failed", error: error); self.end("字幕接收器不可用：\(error.localizedDescription)")
        default: break
        }
      }
      c.start(queue: self.queue)
      self.queue.asyncAfter(deadline: .now() + 8) { [weak self] in
        guard let self, !self.ready, !self.stopped else { return }
        self.log.record("transport", "host_timeout"); self.end("收音未能接通，已停止。请回到 Osu 重新开始。")
      }
    }
  }

  private func watchHost(_ c: NWConnection) {
    c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
      guard let self, !self.stopped else { return }
      if let data, !data.isEmpty {
        self.configurationBytes.append(data)
        guard self.configurationBytes.count <= 8192, !self.islandRequested else { self.end("字幕配置无效，请重新开始。"); return }
        if let newline = self.configurationBytes.firstIndex(of: 10) {
          do {
            let configuration = try IslandConfiguration.decode(Data(self.configurationBytes.prefix(upTo: newline)), key: MimiWire.key)
            self.configurationBytes.removeAll(); self.islandRequested = true
            self.pump?.cancel(); self.pump = nil; self.backlog.clear(); self.events.removeAll()
            Task { @MainActor [weak self] in
              guard let self else { return }
              do {
                let session = try BroadcastIslandSession(configuration: configuration)
                session.onFailure = { [weak self] in self?.queue.async { [weak self] in self?.end("灵动岛字幕已结束，请回到 Osu 检查实时活动权限、网络和阿里云配置。") } }
                self.queue.async {
                  guard !self.stopped else { Task { @MainActor in session.stop() }; return }
                  self.island = session
                  let delivery = self.islandDelivery
                  Task { @MainActor in while let data = delivery.next() { session.append(data) } }
                }
              } catch { self.queue.async { self.end("无法连接灵动岛字幕，请回到 Osu 重新开始。") } }
            }
          } catch { self.end("字幕配置无效，请重新开始。"); return }
        }
      }
      if complete || error != nil { self.log.record("transport", "host_closed", error: error); self.end("字幕会话已停止。") }
      else { self.watchHost(c) }
    }
  }

  override func broadcastPaused() { queue.async { self.log.record("broadcast", "paused"); self.sendEvent("paused"); if let session = self.island { Task { @MainActor in session.pause(true) } } } }
  override func broadcastResumed() { queue.async { self.log.record("broadcast", "resumed"); self.sendEvent("resumed"); if let session = self.island { Task { @MainActor in session.pause(false) } } } }
  override func broadcastFinished() { queue.async { self.log.record("broadcast", "finished"); self.stopIsland(); self.stopped = true; self.ready = false; self.pump?.cancel(); self.pump = nil; self.backlog.clear(); self.connection?.cancel(); self.connection = nil } }

  private func startPump() {
    let timer = DispatchSource.makeTimerSource(queue: queue); pump = timer
    timer.schedule(deadline: .now(), repeating: .milliseconds(100))
    timer.setEventHandler { [weak self] in
      guard let self, !self.stopped else { return }
      if Date().timeIntervalSince(self.lastHeartbeat) >= 1 { self.lastHeartbeat = Date(); self.heartbeatDue = true }
      self.drain(flush: true)
    }
    timer.resume()
  }

  override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
    guard sampleBufferType == .audioApp else { return }
    // Convert promptly, then retain only a bounded amount of compact PCM.
    queue.sync {
      guard ready, !stopped else { return }
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
        if conversionFailures == 1 { log.record("audio", "conversion_failed", error: error); sendEvent("conversion_failed") }; return
      }
      let data = Data(bytes: samples, count: Int(output.frameLength) * 2)
      if islandRequested {
        switch islandDelivery.append(data) {
        case .buffered, .closed: break
        case .overflow: end("字幕处理跟不上播放速度，请重新开始。")
        case .schedule:
          let delivery = islandDelivery
          // The queue owns the session reference; the client runs on MainActor.
          guard let session = island else { return }
          Task { @MainActor in while let data = delivery.next() { session.append(data) } }
        }
        return
      }
      do { try backlog.append(data) }
      catch { log.record("audio", "buffer_overflow"); end("音频处理跟不上播放速度，已停止收音。请回到 Osu 重新开始。"); return }
      frames += 1
      if Date().timeIntervalSince(lastLog) >= 5 { lastLog = Date(); log.record("audio", "counters", metrics: ["audioFrames": Double(frames), "dropped": Double(dropped), "conversionFailures": Double(conversionFailures)]) }
      drain()
    }
  }

  private func sendEvent(_ event: String) {
    guard !stopped, !islandRequested else { return }
    guard events.count < 16 else { end("收音状态传输中断，请重新开始。"); return }
    events.append(event); drain()
  }
  private func drain(flush: Bool = false) {
    guard !islandRequested, !pending, ready, !stopped, let connection else { return }
    var object: [String: Any] = ["key": MimiWire.key, "dropped": dropped, "conversionFailures": conversionFailures]
    if !events.isEmpty { object["event"] = events.removeFirst() }
    else if heartbeatDue { object["event"] = "heartbeat"; heartbeatDue = false }
    else if backlog.count >= 3200 || (flush && backlog.count > 0), let audio = backlog.take() { object["audio"] = audio.base64EncodedString() }
    else { return }
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { end("收音数据处理失败，请重新开始。"); return }
    pending = true
    connection.send(content: data + Data([10]), completion: .contentProcessed { [weak self, weak connection] error in
      guard let self, let connection, self.connection === connection, !self.stopped else { return }; self.pending = false
      if let error { self.log.record("transport", "send_failed", error: error); self.end("音频传输中断：\(error.localizedDescription)") }
      else { self.drain() }
    })
  }
  private func stopIsland() {
    islandDelivery.cancel()
    if let session = island { island = nil; Task { @MainActor in session.stop() } }
  }
  private func end(_ message: String) {
    guard !stopped else { return }; log.record("broadcast", "ended"); stopIsland(); stopped = true; ready = false; pump?.cancel(); pump = nil; backlog.clear(); connection?.cancel()
    finishBroadcastWithError(NSError(domain: "MimiPrototype", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
  }
}
