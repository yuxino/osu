import Foundation
import Network
import AVFoundation

final class AudioReceiver {
  private let queue = DispatchQueue(label: "mimi.receiver")
  private var listener: NWListener?
  private var peer: NWConnection?
  private var bytes = Data()
  var onAudio: ((AVAudioPCMBuffer) -> Void)?
  var onStatus: ((String) -> Void)?
  private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
  private var authenticated = false
  func start() throws {
    try queue.sync {
    guard self.listener == nil else { return }
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 49371)
    let listener = try NWListener(using: parameters)
    self.listener = listener
    listener.stateUpdateHandler = { [weak self] state in
      if case .failed(let error) = state { self?.onStatus?("接收器失败：\(error.localizedDescription)") }
    }
    listener.newConnectionHandler = { [weak self] c in
      guard let self else { c.cancel(); return }
      guard self.peer == nil else { c.cancel(); return }
      self.peer = c; self.bytes.removeAll(keepingCapacity: true); self.authenticated = false
      c.start(queue: self.queue); self.read(c)
      self.queue.asyncAfter(deadline: .now() + 4) { [weak self, weak c] in
        guard let self, let c, self.peer === c, !self.authenticated else { return }
        self.close(c)
      }
    }
    listener.start(queue: queue)
    }
  }
  func stop() { queue.sync { self.listener?.cancel(); self.listener = nil; self.peer?.cancel(); self.peer = nil; self.bytes.removeAll(); self.authenticated = false } }
  private func close(_ c: NWConnection) { c.cancel(); if peer === c { peer = nil; bytes.removeAll(); authenticated = false } }
  private func read(_ c: NWConnection) {
    c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
      guard let self, self.peer === c else { return }
      if let data { self.bytes.append(data) }
      guard self.bytes.count <= 65536 else { self.close(c); self.onStatus?("音频帧超出限制"); return }
      while let end = self.bytes.firstIndex(of: 10) {
        let line = self.bytes.prefix(upTo: end); self.bytes.removeSubrange(...end)
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], object["key"] as? String == MimiWire.key else { self.close(c); return }
        self.authenticated = true
        if let event = object["event"] as? String { self.onStatus?("广播：\(event)") }
        guard let encoded = object["audio"] as? String else { continue }
        guard let raw = Data(base64Encoded: encoded), !raw.isEmpty, raw.count <= 32768, raw.count % 2 == 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: AVAudioFrameCount(raw.count / 2)), let dest = buffer.int16ChannelData?[0] else { self.close(c); return }
        buffer.frameLength = buffer.frameCapacity
        raw.copyBytes(to: UnsafeMutableRawBufferPointer(start: dest, count: raw.count))
        self.onAudio?(buffer)
      }
      if complete || error != nil { self.close(c); self.onStatus?("屏幕广播已结束") }
      else { self.read(c) }
    }
  }
}
