import XCTest
@testable import MusicHackathon

final class LocalizationResourceTests: XCTestCase {
  func testRepresentativeLocalizableKeysResolveForEverySupportedLocale() throws {
    let expectations: [(locale: String, radio: String, language: String)] = [
      ("en", "Radio", "Traditional Chinese"),
      ("zh-Hans", "电台", "繁体中文"),
      ("zh-Hant", "電臺", "繁體中文")
    ]

    for expectation in expectations {
      let bundle = try localizedBundle(for: expectation.locale)

      XCTAssertEqual(localized("tab.radio", in: bundle), expectation.radio)
      XCTAssertEqual(localized("settings.language.traditionalChinese", in: bundle), expectation.language)
      XCTAssertNotEqual(localized("settings.speechLanguage.preference", in: bundle), "settings.speechLanguage.preference")
      XCTAssertNotEqual(localized("settings.speechLanguage.footer", in: bundle), "settings.speechLanguage.footer")
      XCTAssertNotEqual(localized("appleMusic.alert.denied.title", in: bundle), "appleMusic.alert.denied.title")
      XCTAssertNotEqual(localized("diagnostics.title", in: bundle), "diagnostics.title")
      XCTAssertNotEqual(localized("discover.feed.cached", in: bundle), "discover.feed.cached")
      XCTAssertNotEqual(localized("discover.feed.paginationFailed", in: bundle), "discover.feed.paginationFailed")
      XCTAssertNotEqual(localized("discover.publish.copyLink", in: bundle), "discover.publish.copyLink")
      XCTAssertNotEqual(localized("discover.publish.uploadNotice", in: bundle), "discover.publish.uploadNotice")
      XCTAssertNotEqual(localized("discover.publish.success.unlisted", in: bundle), "discover.publish.success.unlisted")
    }
  }

  func testInfoPlistKeysResolveForEverySupportedLocale() throws {
    for locale in ["en", "zh-Hans", "zh-Hant"] {
      let bundle = try localizedBundle(for: locale)

      XCTAssertEqual(localized("CFBundleDisplayName", table: "InfoPlist", in: bundle), "Airset")
      XCTAssertNotEqual(
        localized("NSAppleMusicUsageDescription", table: "InfoPlist", in: bundle),
        "NSAppleMusicUsageDescription"
      )
      XCTAssertNotEqual(
        localized("NSMediaLibraryUsageDescription", table: "InfoPlist", in: bundle),
        "NSMediaLibraryUsageDescription"
      )
      XCTAssertNotEqual(
        localized("NSMicrophoneUsageDescription", table: "InfoPlist", in: bundle),
        "NSMicrophoneUsageDescription"
      )
    }
  }

  func testEnglishPluralFormatting() throws {
    let bundle = try localizedBundle(for: "en")

    XCTAssertEqual(localizedCount("count.songs", 1, in: bundle), "1 song")
    XCTAssertEqual(localizedCount("count.songs", 2, in: bundle), "2 songs")
    XCTAssertEqual(localizedCount("archive.relative.dayAgo", 1, in: bundle), "1 day ago")
    XCTAssertEqual(localizedCount("archive.relative.dayAgo", 3, in: bundle), "3 days ago")
  }

  func testChineseCountAndRelativeDateFormatting() throws {
    let simplifiedBundle = try localizedBundle(for: "zh-Hans")
    let traditionalBundle = try localizedBundle(for: "zh-Hant")

    XCTAssertEqual(localizedCount("count.songs", 1, in: simplifiedBundle), "1 首歌")
    XCTAssertEqual(localizedCount("count.playlists", 3, in: simplifiedBundle), "3 个歌单")
    XCTAssertEqual(localizedCount("archive.relative.monthAgo", 2, in: simplifiedBundle), "2 个月前")

    XCTAssertEqual(localizedCount("count.songs", 1, in: traditionalBundle), "1 首歌")
    XCTAssertEqual(localizedCount("count.playlists", 3, in: traditionalBundle), "3 個歌單")
    XCTAssertEqual(localizedCount("archive.relative.monthAgo", 2, in: traditionalBundle), "2 個月前")
  }

  private func localizedBundle(for locale: String) throws -> Bundle {
    let path = try XCTUnwrap(L10n.bundle.path(forResource: locale, ofType: "lproj"))
    return try XCTUnwrap(Bundle(path: path))
  }

  private func localized(_ key: String, table: String? = nil, in bundle: Bundle) -> String {
    bundle.localizedString(forKey: key, value: key, table: table)
  }

  private func localizedCount(_ key: String, _ value: Int, in bundle: Bundle) -> String {
    let localeIdentifier = bundle.bundleURL.deletingPathExtension().lastPathComponent
    let format = pluralFormat(for: key, value: value, localeIdentifier: localeIdentifier, in: bundle)
    return String(format: format, locale: Locale(identifier: localeIdentifier), value)
  }

  private func pluralFormat(
    for key: String,
    value: Int,
    localeIdentifier: String,
    in bundle: Bundle
  ) -> String {
    guard
      let url = bundle.url(forResource: "Localizable", withExtension: "stringsdict"),
      let data = try? Data(contentsOf: url),
      let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let entry = root[key] as? [String: Any],
      let valueRules = entry["value"] as? [String: Any]
    else {
      XCTFail("Missing stringsdict entry for \(key)")
      return key
    }

    if localeIdentifier == "en", value == 1, let oneFormat = valueRules["one"] as? String {
      return oneFormat
    }

    if let otherFormat = valueRules["other"] as? String {
      return otherFormat
    }

    XCTFail("Missing fallback plural format for \(key)")
    return key
  }
}
