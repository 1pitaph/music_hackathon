import Foundation

enum RadioSpeechLanguage: String, CaseIterable, Identifiable {
  case chinese = "zh-CN"
  case english = "en-US"

  static let storageKey = "radio.speechLanguage"

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .chinese:
      L10n.tr("settings.speechLanguage.chinese")
    case .english:
      L10n.tr("settings.speechLanguage.english")
    }
  }

  var speechLanguageCode: String {
    rawValue
  }

  static func stored(in defaults: UserDefaults = .standard) -> RadioSpeechLanguage {
    guard
      let rawValue = defaults.string(forKey: storageKey),
      let language = RadioSpeechLanguage(rawValue: rawValue)
    else {
      return .chinese
    }
    return language
  }

  static func speechLanguageCode(defaults: UserDefaults = .standard) -> String {
    stored(in: defaults).speechLanguageCode
  }
}
