import UIKit
import Network
import AVFoundation

@main
final class SimulatorHarness: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private let receiver = AudioReceiver()
  private var client: NWConnection?
  private var completed = false
  private let queue = DispatchQueue(label: "mimi.simulator.tests")
  func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    let w = UIWindow(frame: UIScreen.main.bounds); w.rootViewController = MimiPrototypeController(); w.makeKeyAndVisible(); window = w
    if ProcessInfo.processInfo.arguments.contains("--verify-transport") { verifyTransport() }
    return true
  }
  private func verifyTransport() {
    receiver.onEvent = { [weak self] event, _, _ in
      guard let self else { return }
      if event == "ready" { self.connect() }
      if event == "listener_failed" { self.finish(false, "listener_failed") }
    }
    receiver.onAudio = { [weak self] buffer in
      guard let self else { return }
      let valid = buffer.frameLength == 2 && buffer.int16ChannelData?[0][0] == 256 && buffer.int16ChannelData?[0][1] == 770
      self.finish(valid, valid ? "loopback_pcm_passed" : "pcm_mismatch")
    }
    do { try receiver.start() } catch { finish(false, "start_failed") }
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.finish(false, "timeout") }
  }
  private func connect() {
    let c = NWConnection(host: "127.0.0.1", port: 49371, using: .tcp); client = c
    c.stateUpdateHandler = { state in
      if case .ready = state {
        let data = try! JSONSerialization.data(withJSONObject: ["key": MimiWire.key, "audio": Data([0, 1, 2, 3]).base64EncodedString()]) + Data([10])
        c.send(content: data.prefix(7), completion: .contentProcessed { _ in c.send(content: data.dropFirst(7), completion: .contentProcessed { _ in }) })
      }
    }
    c.start(queue: queue)
  }
  private func finish(_ passed: Bool, _ result: String) {
    DispatchQueue.main.async { [self] in
      guard !completed else { return }; completed = true
      receiver.stop(); client?.cancel()
      let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("simulator-test.json")
      let data = try! JSONSerialization.data(withJSONObject: ["passed": passed, "result": result, "timestamp": ISO8601DateFormatter().string(from: Date()), "scope": "Production loopback receiver and native controller; no ReplayKit or speech/translation acceptance"])
      try! data.write(to: url, options: .atomic)
    }
  }
}
