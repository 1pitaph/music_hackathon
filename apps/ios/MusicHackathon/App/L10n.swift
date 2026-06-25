import Foundation
import SwiftUI

final class AppBundleMarker: NSObject {}

enum L10n {
  static var bundle: Bundle {
    Bundle(for: AppBundleMarker.self)
  }

  static func tr(_ key: String, _ arguments: CVarArg...) -> String {
    let format = currentLocalizedBundle.localizedString(forKey: key, value: key, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: Locale.current, arguments: arguments)
  }

  static func count(_ key: String, _ value: Int) -> String {
    if let format = pluralFormat(for: key, value: value) {
      return String(format: format, locale: currentLocale, value)
    }

    let format = bundle.localizedString(forKey: key, value: key, table: nil)
    return String.localizedStringWithFormat(format, value)
  }

  static func text(_ key: String) -> Text {
    Text(tr(key))
  }

  private static let currentLocalizationIdentifier = bundle.preferredLocalizations.first ?? "en"

  private static var currentLocale: Locale {
    Locale(identifier: currentLocalizationIdentifier)
  }

  private static let currentLocalizedBundle: Bundle = {
    guard
      let path = bundle.path(forResource: currentLocalizationIdentifier, ofType: "lproj"),
      let localizedBundle = Bundle(path: path)
    else {
      return bundle
    }
    return localizedBundle
  }()

  private static func pluralFormat(for key: String, value: Int) -> String? {
    guard
      let url = currentLocalizedBundle.url(forResource: "Localizable", withExtension: "stringsdict"),
      let data = try? Data(contentsOf: url),
      let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let entry = root[key] as? [String: Any],
      let valueRules = entry["value"] as? [String: Any]
    else {
      return nil
    }

    let language = currentLocale.language.languageCode?.identifier
    if language == "en", value == 1, let oneFormat = valueRules["one"] as? String {
      return oneFormat
    }
    return valueRules["other"] as? String
  }
}
