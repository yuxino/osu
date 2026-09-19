import Foundation

@MainActor final class FixtureRealtimeSocket: RealtimeSocket {
  var sentAudio = 0
  var sentFinish = 0
  private var messages: [Data] = []
  private var waiting: CheckedContinuation<Data, Error>?
  private(set) var closed = false
  var acknowledgeSetup = true, acknowledgeFinish = true
  func send(_ text: String) async throws {
    guard !closed else { throw AlibabaProtocol.Failure.transport }
    let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    if object["type"] as? String == "session.update" && acknowledgeSetup { push(["type": "session.updated"]) }
    if object["type"] as? String == "session.finish" { sentFinish += 1; if acknowledgeFinish { push(["type": "session.finished"]) } }
    if object["type"] as? String == "input_audio_buffer.append" {
      sentAudio += 1
      push(["type": "conversation.item.input_audio_transcription.completed", "item_id": "test1", "transcript": "こんにちは"])
      push(["type": "response.text.done", "response_id": "response1", "text": "你好"])
    }
  }
  private func push(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object)
    if let waiting { self.waiting = nil; waiting.resume(returning: data) } else { messages.append(data) }
  }
  func receive() async throws -> Data {
    if closed { throw AlibabaProtocol.Failure.transport }
    if !messages.isEmpty { return messages.removeFirst() }
    return try await withCheckedThrowingContinuation { waiting = $0 }
  }
  func ping() async throws { if closed { throw AlibabaProtocol.Failure.transport } }
  func close() { closed = true; waiting?.resume(throwing: AlibabaProtocol.Failure.transport); waiting = nil; messages.removeAll() }
}

@MainActor final class CloudFixture {
  private var client: AlibabaClient?
  private var done = false
  func run(completion: @escaping (Bool, String) -> Void) {
    let service = "com.yuxino.osu.tests." + UUID().uuidString
    do {
      defer { try? CloudCredentialStore.remove(service: service) }
      guard try !CloudCredentialStore.isPresent(service: service) else { completion(false, "keychain_initial_state"); return }
      try CloudCredentialStore.save("fixture-only-first", service: service)
      try CloudCredentialStore.save("fixture-only-updated", service: service)
      guard try CloudCredentialStore.read(service: service) == "fixture-only-updated" else { completion(false, "keychain_roundtrip"); return }
      try CloudCredentialStore.remove(service: service)
      guard try !CloudCredentialStore.isPresent(service: service) else { completion(false, "keychain_remove"); return }
    } catch { completion(false, "keychain_test_failed"); return }
    let socket = FixtureRealtimeSocket(); let client = AlibabaClient(factory: { _ in socket }); self.client = client
    var ready = false, sources = 0, translations = 0
    client.onSource = { _, final in if final { sources += 1 } }
    client.onTranslation = { _, final in if final { translations += 1 } }
    client.onFailure = { _ in completion(false, "fixture_client_failed") }
    client.onReady = { [weak self, weak client] in
      guard let self, let client else { return }; ready = true
      // Finish before flush starts: pre-ready queued audio must precede session.finish.
      client.finish { confirmed in
        client.append(Data([0, 0]))
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 200_000_000)
          self.done = true; self.client = nil
          completion(confirmed && ready && sources == 1 && translations == 1 && socket.sentAudio == 1 && socket.sentFinish == 1, "keychain_and_cloud_readiness_final_drain_stop")
        }
      }
      client.append(Data([0, 0]))
    }
    do { try client.start(key: "fixture-only", source: "ja", target: "zh"); client.append(Data([0, 1, 2, 3])) }
    catch { completion(false, "fixture_start_failed") }
  }
}

@MainActor final class CloudLifecycleFixture {
  private var retained: AlibabaClient?
  func run(completion: @escaping (Bool, String) -> Void) {
    Task { @MainActor in
      // Immediate stop and restart must invalidate the old socket's completion.
      let old = FixtureRealtimeSocket(), fresh = FixtureRealtimeSocket()
      var factories = 0, ready = 0, sources = 0, failures = 0
      let client = AlibabaClient(factory: { _ in factories += 1; return factories == 1 ? old : fresh })
      retained = client
      client.onReady = { ready += 1 }; client.onSource = { _, _ in sources += 1 }; client.onFailure = { _ in failures += 1 }
      do {
        try client.start(key: "fixture-only", source: "ja", target: "zh"); client.stop()
        try client.start(key: "fixture-only", source: "ja", target: "zh")
      } catch { completion(false, "restart_setup"); return }
      try? await Task.sleep(nanoseconds: 100_000_000)
      client.append(Data([0, 1])); try? await Task.sleep(nanoseconds: 100_000_000)
      client.stop(); client.append(Data([0, 1]))
      guard ready == 1 && sources == 1 && failures == 0 && old.sentAudio == 0 && fresh.sentAudio == 1 else { completion(false, "restart_generation"); return }

      // A stalled setup may buffer at most two seconds, then closes once.
      let blocked = FixtureRealtimeSocket(); blocked.acknowledgeSetup = false
      let overloaded = AlibabaClient(factory: { _ in blocked }); retained = overloaded
      var overloads = 0
      overloaded.onFailure = { if $0 == .overload { overloads += 1 } }
      try? overloaded.start(key: "fixture-only", source: "ja", target: "zh")
      overloaded.append(Data(repeating: 0, count: 32768)); overloaded.append(Data(repeating: 0, count: 32768))
      try? await Task.sleep(nanoseconds: 100_000_000)
      guard overloads == 1 && blocked.sentAudio == 0 else { completion(false, "bounded_backpressure"); return }

      // A server that never confirms finish cannot leave an invisible session open.
      let silent = FixtureRealtimeSocket(); silent.acknowledgeFinish = false
      let finishing = AlibabaClient(factory: { _ in silent }); retained = finishing
      var finishResult: Bool?
      finishing.onReady = { [weak finishing] in finishing?.finish { finishResult = $0 } }
      try? finishing.start(key: "fixture-only", source: "ja", target: "zh")
      let deadline = Date().addingTimeInterval(10)
      while finishResult == nil && Date() < deadline { try? await Task.sleep(nanoseconds: 100_000_000) }
      guard finishResult == false && silent.closed && silent.sentFinish == 1 else { finishing.stop(); completion(false, "finish_timeout"); return }
      retained = nil; completion(true, "cancel_restart_backpressure_and_bounded_finish_timeout")
    }
  }
}
