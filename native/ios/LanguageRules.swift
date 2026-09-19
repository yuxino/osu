import Foundation

enum PairReadiness: String {
  case checking, checkFailed, transcriptionOnly, installed, needsDownload, unsupported, requiresNewerOS
  var message: String {
    switch self {
    case .checkFailed: return "暂时无法检查翻译资源，请重新检查或选择仅显示原文。"
    case .checking: return "正在检查语言资源…"
    case .transcriptionOnly: return "只显示原文，不进行翻译。"
    case .installed: return "翻译语言包已下载，可在设备上处理。"
    case .needsDownload: return "支持此语言组合；请先准备并下载翻译语言包。"
    case .unsupported: return "系统不支持此翻译组合；请选择其他目标语言或仅显示原文。"
    case .requiresNewerOS: return "此版本的本地翻译需要 iOS 26；仍可选择仅显示原文。"
    }
  }
  var canStart: Bool { self == .installed || self == .transcriptionOnly }
}

struct LanguageSelection: Equatable {
  var source: String
  var target: String // Empty means explicit transcription only.
  var sourceLanguage: Locale.Language { Locale(identifier: source).language }
  var targetLanguage: Locale.Language? { target.isEmpty ? nil : Locale.Language(identifier: target) }
  var localSelection: LanguageSelection {
    guard let targetLanguage else { return self }
    return Self.identifier(sourceLanguage) == Self.identifier(targetLanguage) ? .init(source: source, target: "") : self
  }
  // Keep script information: zh-Hans and zh-Hant must not collapse to one entry.
  static func identifier(_ language: Locale.Language) -> String {
    if language.languageCode?.identifier == "zh", let script = language.script?.identifier { return "zh-\(script)" }
    return language.minimalIdentifier
  }
  static func display(_ identifier: String) -> String {
    Locale(identifier: "zh-Hans").localizedString(forIdentifier: identifier) ?? identifier
  }
}

enum SubtitleDefaults {
  // The new automatic default replaces the old demo's implicit English/Japanese hints once.
  // Subsequent deliberate selections, including Apple offline mode, remain untouched.
  static func migrate(_ defaults: UserDefaults) {
    guard !defaults.bool(forKey: "osu.automaticLanguageDefaultsV1") else { return }
    defaults.set("alibaba", forKey: "mimi.engine")
    defaults.set("auto", forKey: "mimi.alibaba.source")
    defaults.set("zh", forKey: "mimi.alibaba.target")
    defaults.set(true, forKey: "osu.automaticLanguageDefaultsV1")
  }
}
