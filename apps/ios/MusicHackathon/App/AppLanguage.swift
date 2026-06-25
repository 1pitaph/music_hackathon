import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case system
  case english = "en"
  case simplifiedChinese = "zh-Hans"
  case traditionalChinese = "zh-Hant"

  static let storageKey = "app.language"

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .system:
      L10n.tr("settings.language.system")
    case .english:
      L10n.tr("settings.language.english")
    case .simplifiedChinese:
      L10n.tr("settings.language.simplifiedChinese")
    case .traditionalChinese:
      L10n.tr("settings.language.traditionalChinese")
    }
  }

  var localeIdentifier: String? {
    switch self {
    case .system:
      nil
    case .english:
      "en"
    case .simplifiedChinese:
      "zh-Hans"
    case .traditionalChinese:
      "zh-Hant"
    }
  }

  var acceptLanguageHeader: String {
    switch self {
    case .system:
      return Locale.preferredLanguages.first ?? "en"
    case .english:
      return "en-US,en;q=0.9"
    case .simplifiedChinese:
      return "zh-Hans-CN,zh-CN;q=0.9,en;q=0.7"
    case .traditionalChinese:
      return "zh-Hant-TW,zh-TW;q=0.9,en;q=0.7"
    }
  }

  var speechLanguageIdentifier: String? {
    switch self {
    case .system:
      return Self.speechLanguageIdentifier(for: Locale.preferredLanguages.first)
    case .english:
      return "en-US"
    case .simplifiedChinese:
      return "zh-CN"
    case .traditionalChinese:
      return "zh-TW"
    }
  }

  static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
    guard
      let rawValue = defaults.string(forKey: storageKey),
      let language = AppLanguage(rawValue: rawValue)
    else {
      return .system
    }
    return language
  }

  static func store(_ language: AppLanguage, defaults: UserDefaults = .standard) {
    defaults.set(language.rawValue, forKey: storageKey)
    apply(language, defaults: defaults)
  }

  static func applyStoredPreference(defaults: UserDefaults = .standard) {
    apply(stored(in: defaults), defaults: defaults)
  }

  static func acceptLanguageHeader(defaults: UserDefaults = .standard) -> String {
    stored(in: defaults).acceptLanguageHeader
  }

  static func speechLanguageIdentifier(defaults: UserDefaults = .standard) -> String? {
    stored(in: defaults).speechLanguageIdentifier
  }

  static func apply(_ language: AppLanguage, defaults: UserDefaults = .standard) {
    if let localeIdentifier = language.localeIdentifier {
      defaults.set([localeIdentifier], forKey: "AppleLanguages")
    } else {
      defaults.removeObject(forKey: "AppleLanguages")
    }
    defaults.synchronize()
  }

  private static func speechLanguageIdentifier(for preferredLanguage: String?) -> String? {
    guard let preferredLanguage else { return nil }
    if preferredLanguage.localizedCaseInsensitiveContains("zh-Hant")
      || preferredLanguage.localizedCaseInsensitiveContains("zh_TW")
      || preferredLanguage.localizedCaseInsensitiveContains("zh-TW")
      || preferredLanguage.localizedCaseInsensitiveContains("zh-HK")
      || preferredLanguage.localizedCaseInsensitiveContains("zh_HK") {
      return "zh-TW"
    }
    if preferredLanguage.localizedCaseInsensitiveContains("zh") {
      return "zh-CN"
    }
    if preferredLanguage.localizedCaseInsensitiveContains("en") {
      return "en-US"
    }
    return nil
  }
}
