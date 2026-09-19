import Foundation

// Injectable only in source-level tests; production always constructs the fixed TLS endpoint.
@MainActor protocol RealtimeSocket: AnyObject {
  func send(_ text: String) async throws
  func receive() async throws -> Data
  func ping() async throws
  func close()
}
@MainActor private final class DashScopeSocket: RealtimeSocket {
  private let session: URLSession
  private let task: URLSessionWebSocketTask
  init(key: String) {
    let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 15; config.urlCache = nil; config.httpCookieStorage = nil
    session = URLSession(configuration: config)
    var request = URLRequest(url: AlibabaProtocol.endpoint)
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    task = session.webSocketTask(with: request); task.maximumMessageSize = 131072; task.resume()
  }
  func send(_ text: String) async throws { try await task.send(.string(text)) }
  func receive() async throws -> Data {
    switch try await task.receive() {
    case .string(let text): return Data(text.utf8)
    case .data(let data): return data
    @unknown default: throw AlibabaProtocol.Failure.invalidEvent
    }
  }
  func ping() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      task.sendPing { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
    }
  }
  func close() { task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
}

@MainActor final class AlibabaClient {
  var onReady: (() -> Void)?
  var onSource: ((String, Bool) -> Void)?
  var onTranslation: ((String, Bool) -> Void)?
  var onFailure: ((AlibabaProtocol.Failure) -> Void)?
  var onMetric: ((Int) -> Void)?
  private var socket: RealtimeSocket?
  private let factory: (String) -> RealtimeSocket
  private var receiveWork: Task<Void, Never>?, sendWork: Task<Void, Never>?, healthWork: Task<Void, Never>?
  private var generation = 0
  private var ready = false, active = false, sending = false
  private var queue = BoundedAudioQueue()
  private var setupAt = Date(), sendAt: Date?, pingAt: Date?, lastPing = Date()
  private var sourceGate = CloudPreviewGate(), translationGate = CloudPreviewGate()
  init(factory: ((String) -> RealtimeSocket)? = nil) { self.factory = factory ?? { DashScopeSocket(key: $0) } }
  func start(key: String, source: String, target: String) throws {
    stop()
    guard !key.isEmpty else { throw AlibabaProtocol.Failure.authentication }
    let setup = try AlibabaProtocol.setup(source: source, target: target)
    active = true; generation += 1; let epoch = generation; setupAt = Date(); lastPing = Date()
    sourceGate = CloudPreviewGate(); translationGate = CloudPreviewGate()
    let socket = factory(key); self.socket = socket
    receiveWork = Task { [weak self] in
      do {
        try await socket.send(setup)
        while !Task.isCancelled {
          let data = try await socket.receive()
          guard let self, self.active, self.generation == epoch else { return }
          switch try AlibabaProtocol.decode(data) {
          case .ready: if !self.ready { self.ready = true; self.onReady?(); self.flush() }
          case .source(let text, let id, let final): if self.ready && self.sourceGate.accept(id: id, final: final) && !text.isEmpty { self.onSource?(text, final) }
          case .translation(let text, let id, let final): if self.ready && self.translationGate.accept(id: id, final: final) && !text.isEmpty { self.onTranslation?(text, final) }
          case .failure(let failure): self.fail(failure); return
          case .finished: self.fail(.transport); return
          case .ignored: break
          }
        }
      } catch { guard let self, self.generation == epoch, self.active else { return }; self.fail((error as? AlibabaProtocol.Failure) ?? .transport) }
    }
    healthWork = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard let self, self.active, self.generation == epoch, !Task.isCancelled else { return }
        let now = Date()
        if (!self.ready && now.timeIntervalSince(self.setupAt) > 15) || self.sendAt.map({ now.timeIntervalSince($0) > 5 }) == true || self.pingAt.map({ now.timeIntervalSince($0) > 5 }) == true { self.fail(.timeout); return }
        if self.ready && self.pingAt == nil && now.timeIntervalSince(self.lastPing) >= 10 {
          self.pingAt = now; self.lastPing = now
          Task { [weak self] in
            do { try await socket.ping(); guard let self, self.generation == epoch else { return }; self.pingAt = nil }
            catch { guard let self, self.generation == epoch, self.active else { return }; self.fail(.transport) }
          }
        }
      }
    }
  }
  func append(_ data: Data) {
    guard active else { return }
    do { try queue.append(data); flush() } catch { fail(.overload) }
  }
  private func flush() {
    guard ready && active && !sending, let socket else { return }
    sending = true; let epoch = generation
    sendWork = Task { [weak self] in
      guard let self else { return }
      while self.active && self.generation == epoch, let data = self.queue.next() {
        self.sendAt = Date()
        do { try await socket.send(AlibabaProtocol.audio(data)) }
        catch { if self.generation == epoch && self.active { self.fail(.transport) }; return }
        guard self.generation == epoch && self.active else { return }
        self.sendAt = nil; self.onMetric?(data.count)
      }
      if self.generation == epoch { self.sending = false }
    }
  }
  func stop() {
    generation += 1; active = false; ready = false; sending = false
    receiveWork?.cancel(); sendWork?.cancel(); healthWork?.cancel(); receiveWork = nil; sendWork = nil; healthWork = nil
    socket?.close(); socket = nil; queue.clear(); sendAt = nil; pingAt = nil
  }
  private func fail(_ failure: AlibabaProtocol.Failure) { guard active else { return }; stop(); onFailure?(failure) }
}
