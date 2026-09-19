import UIKit
import Network

// A paced, authored PCM stream through the production receiver, client,
// controller and lyrics preview. Provider replies are in memory. This cannot
// establish ReplayKit, PiP, network latency, battery or physical-device behavior.
@MainActor final class StreamEnduranceFixture {
  private let picture = SubtitlePicture()
  private let socket = FixtureRealtimeSocket()
  private var pickerRequests = 0
  private var connection: NWConnection?
  private var captureClosed = false
  private var checkpoints: [[String: Any]] = []
  private var began = 0.0, sent = 0, maxLateness = 0.0

  func controller() -> MimiPrototypeController {
    UserDefaults.standard.set(true, forKey: "osu.automaticLanguageDefaultsV1")
    UserDefaults.standard.set("alibaba", forKey: "mimi.engine")
    UserDefaults.standard.set("auto", forKey: "mimi.alibaba.source")
    UserDefaults.standard.set("zh", forKey: "mimi.alibaba.target")
    socket.streamingLyrics = true; socket.acknowledgeFinish = false
    return MimiPrototypeController(makeCloudClient: { [socket] in AlibabaClient(factory: { _ in socket }) }, readCloudCredential: { "fixture-only" }, requestBroadcast: { [self] in pickerRequests += 1; return true }, picture: picture)
  }

  func run(controller: MimiPrototypeController, duration: Int, completion: @escaping (Bool, String) -> Void) {
    Task { @MainActor in
      do {
        try await wait { UIApplication.shared.applicationState == .active }
        try press("开始听", in: controller.view)
        try await wait { self.pickerRequests == 1 }
        let stream = NWConnection(host: "127.0.0.1", port: 49371, using: .tcp); connection = stream
        stream.start(queue: DispatchQueue(label: "osu.stream.fixture"))
        try await wait { if case .ready = stream.state { return true }; return false }
        stream.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, ended, error in
          Task { @MainActor in if ended || error != nil { self?.captureClosed = true } }
        }
        var pcm = Data()
        for sample in 0..<1600 {
          var value = Int16(sin(Double(sample) * 2 * .pi * 440 / 16000) * 8000).littleEndian
          withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        let packet = try JSONSerialization.data(withJSONObject: ["key": MimiWire.key, "event": "heartbeat", "audio": pcm.base64EncodedString()]) + Data([10])
        began = ProcessInfo.processInfo.systemUptime
        let expected = duration * 10
        for index in 0..<expected {
          let deadline = began + Double(index) / 10
          let remaining = deadline - ProcessInfo.processInfo.systemUptime
          if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
          maxLateness = max(maxLateness, ProcessInfo.processInfo.systemUptime - deadline)
          guard !socket.closed, UIApplication.shared.applicationState == .active else { throw failure("stream_stopped_or_backgrounded") }
          try await send(packet, to: stream); sent += 1
          if sent % 600 == 0 { try checkpoint() }
        }
        try await wait { self.socket.sentAudio == expected }
        try press("停止", in: controller.view)
        try await wait { self.socket.sentFinish == 1 }
        socket.confirmFinish()
        try await wait { self.socket.closed && self.captureClosed && self.snapshot()["captureState"] as? String == "stopped" }
        let state = snapshot(), metrics = state["metrics"] as? [String: Double] ?? [:]
        guard socket.sentBytes == expected * 3200,
              metrics["audioFrames"] == Double(expected),
              abs((metrics["audioSeconds"] ?? 0) - Double(duration)) < 0.001,
              metrics["recognitionUpdates"] == Double(duration + 1),
              metrics["translationUpdates"] == Double(duration + 1),
              metrics["sourceFinals"] == Double(duration / 3 + 1),
              metrics["translationFinals"] == Double(duration / 3 + 1),
              picture.translated == "这是最后一句。",
              state["running"] as? Bool == false,
              state["pip"] as? Bool == false,
              picture.diagnostics["mediaCreated"] as? Bool == false
        else { throw failure("stream_counts_or_final_cleanup_mismatch") }
        try checkpoint()
        try write(passed: true, result: "paced_stream_and_final_tail_confirmed")
        connection?.cancel(); connection = nil
        completion(true, "paced_\(duration)s_stream_and_final_tail_confirmed")
      } catch {
        connection?.cancel(); connection = nil; socket.close()
        try? write(passed: false, result: (error as NSError).domain)
        completion(false, (error as NSError).domain)
      }
    }
  }
  private func checkpoint() throws {
    checkpoints.append(["elapsed": ProcessInfo.processInfo.systemUptime - began, "sentChunks": sent, "providerChunks": socket.sentAudio, "snapshot": snapshot()])
    try write(passed: nil, result: "running")
  }
  private func write(passed: Bool?, result: String) throws {
    var document: [String: Any] = ["result": result, "sentChunks": sent, "providerChunks": socket.sentAudio, "providerBytes": socket.sentBytes, "finishRequests": socket.sentFinish, "socketClosed": socket.closed, "captureClosed": captureClosed, "elapsed": ProcessInfo.processInfo.systemUptime - began, "maxSendLatenessMS": maxLateness * 1000, "checkpoints": checkpoints, "finalSnapshot": snapshot(), "timestamp": ISO8601DateFormatter().string(from: Date()), "scope": "Paced synthetic PCM and in-memory provider; production foreground controller/receiver/client/lyrics. No real capture, PiP, cloud, battery or phone performance evidence."]
    if let passed { document["passed"] = passed }
    let url = DiagnosticStore.shared.directory.deletingLastPathComponent().appendingPathComponent("stream-endurance.json")
    try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
  }
  private func snapshot() -> [String: Any] {
    let path = DiagnosticStore.shared.directory.deletingLastPathComponent().appendingPathComponent("probe-status.json")
    guard let data = try? Data(contentsOf: path), let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return state
  }
  private func wait(until condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(5)
    while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
    guard condition() else { throw failure("stream_state_timeout") }
  }
  private func press(_ title: String, in view: UIView) throws {
    func button(_ view: UIView) -> UIButton? {
      if let b = view as? UIButton, b.configuration?.title == title, b.isEnabled { return b }
      return view.subviews.lazy.compactMap { button($0) }.first
    }
    guard let target = button(view) else { throw failure("stream_action_unavailable") }
    target.sendActions(for: .touchUpInside)
  }
  private func send(_ data: Data, to connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(content: data, completion: .contentProcessed { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      })
    }
  }
  private func failure(_ name: String) -> NSError { NSError(domain: name, code: 1) }
}
