import Foundation
import UIKit
import Network

@MainActor final class FixtureRealtimeSocket: RealtimeSocket {
  var sentAudio = 0
  var sentFinish = 0
  private var messages: [Data] = []
  private var waiting: CheckedContinuation<Data, Error>?
  private(set) var closed = false
  var acknowledgeSetup = true, acknowledgeFinish = true
  var onClose: (() -> Void)?
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
  func confirmFinish() {
    guard !closed, sentFinish == 1 else { return }
    push(["type": "conversation.item.input_audio_transcription.completed", "item_id": "tail", "transcript": "最後の一文です。"])
    push(["type": "response.text.done", "response_id": "tail", "text": "这是最后一句。"])
    push(["type": "session.finished"])
  }
  func close() { guard !closed else { return }; closed = true; waiting?.resume(throwing: AlibabaProtocol.Failure.transport); waiting = nil; messages.removeAll(); onClose?() }
}

// Controlled service responses for manual UI checks and controller regressions.
// This file is only linked into the separate simulator harness, never the app.
@MainActor final class CloudUIFixture {
  private(set) var sockets: [FixtureRealtimeSocket] = []
  func controller(ready: Bool = false) -> MimiPrototypeController {
    UserDefaults.standard.set(true, forKey: "osu.automaticLanguageDefaultsV1")
    UserDefaults.standard.set("alibaba", forKey: "mimi.engine")
    UserDefaults.standard.set(ready ? "auto" : "ja", forKey: "mimi.alibaba.source")
    UserDefaults.standard.set("zh", forKey: "mimi.alibaba.target")
    writeState()
    return MimiPrototypeController(makeCloudClient: { [self] in
      let socket = FixtureRealtimeSocket()
      // First connection never becomes ready; later ones never confirm finish.
      socket.acknowledgeSetup = ready || !sockets.isEmpty; socket.acknowledgeFinish = ready
      sockets.append(socket)
      socket.onClose = { [weak self] in self?.writeState() }
      writeState()
      return AlibabaClient(factory: { _ in socket })
    }, readCloudCredential: { "fixture-only" })
  }
  private func writeState() {
    let rows = sockets.map { ["closed": $0.closed, "audio": $0.sentAudio, "finish": $0.sentFinish] as [String: Any] }
    let document: [String: Any] = ["scope": "UI lifecycle only; in-memory fake service, dummy credential, no provider network", "sockets": rows, "timestamp": ISO8601DateFormatter().string(from: Date())]
    let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cloud-ui-state.json")
    if let data = try? JSONSerialization.data(withJSONObject: document) { try? data.write(to: path, options: .atomic) }
  }
}

// Real controller + receiver, fake authenticated broadcast and cloud service.
// Waiting deliberately exceeds the 40-second failure observed on the phone.
@MainActor final class CaptureStartupFixture {
  private var connection: NWConnection?
  func run(controller: MimiPrototypeController, fixture: CloudUIFixture, completion: @escaping (Bool, String) -> Void) {
    Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 500_000_000)
        try press("开始听", in: controller.view)
        try await Task.sleep(nanoseconds: 45_000_000_000)
        guard fixture.sockets.isEmpty, let guide = controller.presentedViewController as? CapturePermissionController else { throw failure("permission_wait_created_cloud_or_lost_guide") }
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard fixture.sockets.isEmpty, controller.presentedViewController === guide else { throw failure("resume_changed_permission_session") }
        try press("暂不开启", in: guide.view)
        try await Task.sleep(nanoseconds: 700_000_000)
        guard fixture.sockets.isEmpty, controller.presentedViewController == nil else { throw failure("permission_cancel_did_not_stay_local") }
        try press("开始听", in: controller.view)
        try await Task.sleep(nanoseconds: 700_000_000)
        let connection = NWConnection(host: "127.0.0.1", port: 49371, using: .tcp); self.connection = connection
        connection.start(queue: DispatchQueue(label: "osu.capture.startup.fixture"))
        // The very first authenticated packet also carries PCM. It must survive
        // the cloud setup callback and keep the same receiver generation.
        try await send(["key": MimiWire.key, "event": "started", "audio": Data([0, 1, 2, 3]).base64EncodedString()], to: connection)
        try await Task.sleep(nanoseconds: 700_000_000)
        guard fixture.sockets.count == 1, fixture.sockets[0].sentAudio == 1 else { throw failure("first_authenticated_audio_lost") }
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await send(["key": MimiWire.key, "event": "heartbeat", "audio": Data([4, 5, 6, 7]).base64EncodedString()], to: connection)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard fixture.sockets.count == 1, fixture.sockets[0].sentAudio == 2 else { throw failure("cloud_ready_restarted_receiver") }
        try press("停止", in: controller.view)
        try await Task.sleep(nanoseconds: 700_000_000)
        guard fixture.sockets[0].closed, fixture.sockets[0].sentFinish == 1 else { throw failure("capture_stop_did_not_close_cloud") }
        connection.cancel(); self.connection = nil
        completion(true, "wait_45s_resume_cancel_then_authenticated_audio_resume_and_finish")
      } catch {
        connection?.cancel(); connection = nil
        completion(false, (error as NSError).domain)
      }
    }
  }
  private func press(_ title: String, in view: UIView) throws {
    func button(in view: UIView) -> UIButton? {
      if let button = view as? UIButton, button.configuration?.title == title, button.isEnabled { return button }
      return view.subviews.lazy.compactMap { button(in: $0) }.first
    }
    guard let target = button(in: view) else { throw failure("capture_action_unavailable") }
    target.sendActions(for: .touchUpInside)
  }
  private func send(_ object: [String: Any], to connection: NWConnection) async throws {
    let data = try JSONSerialization.data(withJSONObject: object) + Data([10])
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(content: data, completion: .contentProcessed { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      })
    }
  }
  private func failure(_ name: String) -> NSError { NSError(domain: name, code: 1) }
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
    client.onSource = { _, id, final in if final && id == "test1" { sources += 1 } }
    client.onTranslation = { _, id, final in if final && id == "response1" { translations += 1 } }
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
      client.onReady = { ready += 1 }; client.onSource = { _, _, _ in sources += 1 }; client.onFailure = { _ in failures += 1 }
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
