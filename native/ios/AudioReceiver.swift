import Foundation
import Network

final class AudioReceiver {
  private let queue = DispatchQueue(label: "mimi.receiver")
  private var listener: NWListener?
  private var peer: NWConnection?
  private var decoder = AudioPacketDecoder(key: MimiWire.key)
  var onAudio: ((Data) -> Void)?
  // Callbacks fire on the receiver queue; hop queues before calling back in.
  var onEvent: ((String, Error?, [String: Double]) -> Void)?
  private var configuration: Data?
  var islandConfiguration: Data? {
    get { queue.sync { configuration } }
    set { queue.sync { configuration = newValue } }
  }
  private var authenticated = false
  private var lastStatistics = Date.distantPast
  private var rebindAttempts = 0
  private var bindEpoch = 0
  private var bindSettled = false
  func start() throws {
    try queue.sync { try bind() }
  }
  // A resume refresh can rebind while the kernel is still releasing the
  // previous port. The conflict surfaces as .failed on device, and as either
  // .waiting or no callback at all elsewhere, where a listener would hang
  // forever without recovering. Every bind is therefore watchdogged: if it
  // neither readies nor fails in time, it is retried a bounded number of times
  // while no broadcast is attached. Genuine bind failures still surface as
  // listener_failed.
  private func bind() throws {
    guard self.listener == nil else { return }
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 49371)
    let listener = try NWListener(using: parameters); self.listener = listener
    bindSettled = false
    let epoch = bindEpoch
    listener.stateUpdateHandler = { [weak self, weak listener] state in
      guard let self, let listener, self.listener === listener else { return }
      switch state {
      case .ready:
        self.bindSettled = true; self.rebindAttempts = 0; self.onEvent?("ready", nil, [:])
      case .failed(let error):
        self.bindSettled = true
        // The device reports a taken port as EADDRINUSE; the simulator as
        // EINVAL. Both are safe to retry with fixed parameters while no
        // broadcast is attached.
        if self.peer == nil, self.rebindAttempts < 3,
           case .posix(let code) = error, code == .EADDRINUSE || code == .EINVAL {
          self.scheduleRebind()
        } else { self.onEvent?("listener_failed", error, [:]) }
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
    queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      guard let self, self.bindEpoch == epoch else { return }
      self.settleOrRetry()
    }
  }
  // On the receiver queue. A bind that neither readies nor failed in time gets
  // one more chance; exhausting the budget surfaces listener_failed instead of
  // leaving the session hanging without a receiver.
  private func settleOrRetry() {
    guard !bindSettled, peer == nil, listener != nil else { return }
    guard rebindAttempts < 3 else {
      bindSettled = true; listener?.cancel(); listener = nil
      onEvent?("listener_failed", NWError.posix(.ETIMEDOUT), [:])
      return
    }
    rebindAttempts += 1
    listener?.cancel(); listener = nil
    do { try bind() } catch { onEvent?("listener_failed", error, [:]) }
  }
  private func scheduleRebind() {
    rebindAttempts += 1
    listener?.cancel(); listener = nil
    let epoch = bindEpoch
    queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      guard let self, self.bindEpoch == epoch, self.peer == nil else { return }
      do { try self.bind() } catch { self.onEvent?("listener_failed", error, [:]) }
    }
  }
  // iOS may reclaim a suspended app's listener without a failure callback.
  // An attaching peer is preserved when the system picker returns to the app.
  @discardableResult func refreshUnconnectedListener() throws -> Bool {
    let restart = queue.sync {
      guard self.peer == nil else { return false }
      self.bindEpoch += 1
      self.listener?.cancel(); self.listener = nil
      return true
    }
    if restart { try start() }
    return restart
  }
  func stop() { queue.sync { self.bindEpoch += 1; self.rebindAttempts = 0; self.listener?.cancel(); self.listener = nil; self.peer?.cancel(); self.peer = nil; self.decoder = AudioPacketDecoder(key: MimiWire.key); self.authenticated = false } }
  private func close(_ c: NWConnection) { c.cancel(); if peer === c { peer = nil; decoder = AudioPacketDecoder(key: MimiWire.key); authenticated = false } }
  private func read(_ c: NWConnection) {
    c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
      guard let self, self.peer === c else { return }
      do {
        for packet in try self.decoder.append(data ?? Data()) {
          if !self.authenticated { self.authenticated = true; if let configuration = self.configuration { self.configuration = nil; c.send(content: configuration + Data([10]), completion: .contentProcessed { _ in }) }; self.onEvent?("connected", nil, [:]) }
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
