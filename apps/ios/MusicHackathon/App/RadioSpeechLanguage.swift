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

  var defaultHostSpeakerID: String {
    switch self {
    case .chinese:
      "zh_female_shuangkuaisisi_moon_bigtts"
    case .english:
      "en_female_lauren_moon_bigtts"
    }
  }

  func resolvedHostSpeakerID(preferredSpeakerID: String?) -> String {
    guard
      let speakerID = preferredSpeakerID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !speakerID.isEmpty
    else {
      return defaultHostSpeakerID
    }

    return isKnownLanguageMismatch(speakerID: speakerID) ? defaultHostSpeakerID : speakerID
  }

  func isKnownLanguageMismatch(speakerID: String) -> Bool {
    let normalizedSpeakerID = speakerID.lowercased()
    switch self {
    case .chinese:
      return normalizedSpeakerID.hasPrefix("en_")
    case .english:
      return normalizedSpeakerID.hasPrefix("zh_")
    }
  }

  func matchesVoiceLanguage(_ language: String) -> Bool {
    let normalizedLanguage = language.lowercased()
    switch self {
    case .chinese:
      return normalizedLanguage.hasPrefix("zh")
    case .english:
      return normalizedLanguage.hasPrefix("en")
    }
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
