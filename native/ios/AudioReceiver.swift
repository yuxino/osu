import Foundation
import Network

final class AudioReceiver {
  private let queue = DispatchQueue(label: "mimi.receiver")
  private var listener: NWListener?
  private var peer: NWConnection?
  private var decoder = AudioPacketDecoder(key: MimiWire.key)
  var onAudio: ((Data) -> Void)?
  var onEvent: ((String, Error?, [String: Double]) -> Void)?
  private var authenticated = false
  private var lastStatistics = Date.distantPast
  func start() throws {
    try queue.sync {
      guard self.listener == nil else { return }
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 49371)
      let listener = try NWListener(using: parameters); self.listener = listener
      listener.stateUpdateHandler = { [weak self, weak listener] state in
        guard let self, let listener, self.listener === listener else { return }
        switch state {
        case .ready: self.onEvent?("ready", nil, [:])
        case .failed(let error): self.onEvent?("listener_failed", error, [:])
        default: break
        }
      }
      listener.newConnectionHandler = { [weak self, weak listener] c in
        guard let self, let listener, self.listener === listener else { c.cancel(); return }
        guard self.peer == nil else { c.cancel(); return }
        self.peer = c; self.decoder = AudioPacketDecoder(key: MimiWire.key); self.authenticated = false; self.lastStatistics = .distantPast
        self.onEvent?("connecting", nil, [:])
        c.start(queue: self.queue); self.read(c)
        self.queue.asyncAfter(deadline: .now() + 4) { [weak self, weak c] in
          guard let self, let c, self.peer === c, !self.authenticated else { return }
          self.onEvent?("authentication_timeout", nil, [:]); self.close(c)
        }
      }
      listener.start(queue: queue)
    }
  }
  func stop() { queue.sync { self.listener?.cancel(); self.listener = nil; self.peer?.cancel(); self.peer = nil; self.decoder = AudioPacketDecoder(key: MimiWire.key); self.authenticated = false } }
  private func close(_ c: NWConnection) { c.cancel(); if peer === c { peer = nil; decoder = AudioPacketDecoder(key: MimiWire.key); authenticated = false } }
  private func read(_ c: NWConnection) {
    c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
      guard let self, self.peer === c else { return }
      do {
        for packet in try self.decoder.append(data ?? Data()) {
          if !self.authenticated { self.authenticated = true; self.onEvent?("connected", nil, [:]) }
          if let event = packet.event { self.onEvent?(event, nil, [:]) }
          if Date().timeIntervalSince(self.lastStatistics) >= 5 {
            self.lastStatistics = Date(); self.onEvent?("extension_counters", nil, ["dropped": packet.dropped, "conversionFailures": packet.conversionFailures])
          }
          if let raw = packet.audio { self.onAudio?(raw) }
        }
      } catch { let authenticated = self.authenticated; self.onEvent?("invalid_packet", nil, [:]); self.close(c); if authenticated { self.onEvent?("failed", nil, [:]) }; return }
      if complete || error != nil { let authenticated = self.authenticated; self.close(c); if authenticated { self.onEvent?(error == nil ? "ended" : "failed", error, [:]) } }
      else { self.read(c) }
    }
  }
}
