import Foundation

@MainActor final class FixtureRealtimeSocket: RealtimeSocket {
  var sentAudio = 0
  private var messages: [Data] = []
  private var waiting: CheckedContinuation<Data, Error>?
  private var closed = false
  func send(_ text: String) async throws {
    guard !closed else { throw AlibabaProtocol.Failure.transport }
    let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    if object["type"] as? String == "session.update" { push(["type": "session.updated"]) }
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
    client.onReady = { ready = true }
    client.onSource = { _, final in if final { sources += 1 } }
    client.onFailure = { _ in completion(false, "fixture_client_failed") }
    client.onTranslation = { [weak self] _, final in
      guard let self, final, !self.done else { return }; translations += 1
      client.stop(); client.append(Data([0, 0]))
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 200_000_000)
        self.done = true; self.client = nil
        completion(ready && sources == 1 && translations == 1 && socket.sentAudio == 1, "keychain_roundtrip_and_fake_cloud_readiness_delivery_stop")
      }
    }
    do { try client.start(key: "fixture-only", source: "ja", target: "zh"); client.append(Data([0, 1, 2, 3])) }
    catch { completion(false, "fixture_start_failed") }
  }
}
