import Foundation

// Live, authenticated transport evidence only. A saved diagnostic snapshot is never input.
struct CaptureReadiness {
  enum State: String {
    case idle, preparing, needsBroadcast, connecting, waitingForAudio, silent, receiving, paused, lost, stopped
    var message: String {
      switch self {
      case .idle: return "自动识别声音的语言，准备好了就开始。"
      case .preparing: return "正在准备收音…"
      case .needsBroadcast: return "尚未允许收音。点下方系统按钮，选择 Osu Audio，再点「开始广播」。"
      case .connecting: return "正在连接 Osu Audio…"
      case .waitingForAudio: return "广播已连接，等待声音。请切回网页或 App 播放内容。"
      case .silent: return "广播已开启，收到的音频暂时是静音。若视频正在发声，内容可能限制收音。"
      case .receiving: return "正在收音，字幕会持续更新。"
      case .paused: return "系统广播已暂停，恢复后会继续收音。"
      case .lost: return "与系统广播的连接已中断，请重新开始。"
      case .stopped: return "广播已停止。准备好了就再开始。"
      }
    }
  }
  private var started = false, ready = false, connecting = false, paused = false, ended = false
  private(set) var connected = false
  private var lastPacket: TimeInterval?, lastAudio: TimeInterval?, lastSound: TimeInterval?
  mutating func start() { self = Self(); started = true }
  mutating func receiverReady() { ready = true }
  mutating func connectionStarted() { connecting = true }
  mutating func connectionReady(at time: TimeInterval) { connected = true; connecting = false; lastPacket = time }
  mutating func heartbeat(at time: TimeInterval) { guard connected else { return }; lastPacket = time }
  mutating func setPaused(_ value: Bool, at time: TimeInterval) { paused = value; heartbeat(at: time) }
  mutating func audio(peak: Double, at time: TimeInterval) {
    guard connected else { return }
    lastAudio = time; lastPacket = time
    if peak > 0.001 { lastSound = time }
  }
  mutating func stop() { started = false; connected = false; ended = true }
  func state(at time: TimeInterval) -> State {
    guard started else { return ended ? .stopped : .idle }
    guard connected else { return connecting ? .connecting : (ready ? .needsBroadcast : .preparing) }
    guard let lastPacket, time - lastPacket <= 6 else { return .lost }
    if paused { return .paused }
    guard let lastAudio, time - lastAudio <= 5 else { return .waitingForAudio }
    if let lastSound, time - lastSound <= 4 { return .receiving }
    return .silent
  }
}
