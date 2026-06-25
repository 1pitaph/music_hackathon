import XCTest
@testable import MusicHackathon

final class AppLanguageTests: XCTestCase {
  func testStoredLanguageDefaultsToSystem() {
    withIsolatedDefaults { defaults, suiteName in
      XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
      XCTAssertNil(persistedAppleLanguages(in: suiteName))
    }
  }

  func testStorePersistsLanguageAndAppliesAppleLanguagesOverride() {
    withIsolatedDefaults { defaults, suiteName in
      AppLanguage.store(.simplifiedChinese, defaults: defaults)

      XCTAssertEqual(AppLanguage.stored(in: defaults), .simplifiedChinese)
      XCTAssertEqual(defaults.string(forKey: AppLanguage.storageKey), "zh-Hans")
      XCTAssertEqual(persistedAppleLanguages(in: suiteName), ["zh-Hans"])
    }
  }

  func testSystemLanguageRemovesAppleLanguagesOverrideButRemainsPersisted() {
    withIsolatedDefaults { defaults, suiteName in
      AppLanguage.store(.traditionalChinese, defaults: defaults)
      AppLanguage.store(.system, defaults: defaults)

      XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
      XCTAssertEqual(defaults.string(forKey: AppLanguage.storageKey), "system")
      XCTAssertNil(persistedAppleLanguages(in: suiteName))
    }
  }

  func testApplyStoredPreferenceUsesPersistedLanguage() {
    withIsolatedDefaults { defaults, suiteName in
      defaults.set("en", forKey: AppLanguage.storageKey)

      AppLanguage.applyStoredPreference(defaults: defaults)

      XCTAssertEqual(persistedAppleLanguages(in: suiteName), ["en"])
    }
  }

  func testInvalidStoredLanguageFallsBackToSystem() {
    withIsolatedDefaults { defaults, suiteName in
      defaults.set("not-a-language", forKey: AppLanguage.storageKey)

      AppLanguage.applyStoredPreference(defaults: defaults)

      XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
      XCTAssertNil(persistedAppleLanguages(in: suiteName))
    }
  }

  func testBackendLanguageHintsMatchExplicitChoices() {
    withIsolatedDefaults { defaults, _ in
      AppLanguage.store(.english, defaults: defaults)
      XCTAssertEqual(AppLanguage.acceptLanguageHeader(defaults: defaults), "en-US,en;q=0.9")
      XCTAssertEqual(AppLanguage.speechLanguageIdentifier(defaults: defaults), "en-US")

      AppLanguage.store(.simplifiedChinese, defaults: defaults)
      XCTAssertEqual(AppLanguage.acceptLanguageHeader(defaults: defaults), "zh-Hans-CN,zh-CN;q=0.9,en;q=0.7")
      XCTAssertEqual(AppLanguage.speechLanguageIdentifier(defaults: defaults), "zh-CN")

      AppLanguage.store(.traditionalChinese, defaults: defaults)
      XCTAssertEqual(AppLanguage.acceptLanguageHeader(defaults: defaults), "zh-Hant-TW,zh-TW;q=0.9,en;q=0.7")
      XCTAssertEqual(AppLanguage.speechLanguageIdentifier(defaults: defaults), "zh-TW")
    }
  }

  func testRadioSpeechLanguageDefaultsToChineseAndReadsStoredValue() {
    withIsolatedDefaults { defaults, _ in
      XCTAssertEqual(RadioSpeechLanguage.stored(in: defaults), .chinese)
      XCTAssertEqual(RadioSpeechLanguage.speechLanguageCode(defaults: defaults), "zh-CN")

      defaults.set(RadioSpeechLanguage.english.rawValue, forKey: RadioSpeechLanguage.storageKey)

      XCTAssertEqual(RadioSpeechLanguage.stored(in: defaults), .english)
      XCTAssertEqual(RadioSpeechLanguage.speechLanguageCode(defaults: defaults), "en-US")
    }
  }

  func testRadioSpeechLanguageFallsBackToChineseForInvalidStoredValue() {
    withIsolatedDefaults { defaults, _ in
      defaults.set("fr-FR", forKey: RadioSpeechLanguage.storageKey)

      XCTAssertEqual(RadioSpeechLanguage.stored(in: defaults), .chinese)
      XCTAssertEqual(RadioSpeechLanguage.speechLanguageCode(defaults: defaults), "zh-CN")
    }
  }

  private func withIsolatedDefaults(_ body: (UserDefaults, String) -> Void) {
    let suiteName = "AppLanguageTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    body(defaults, suiteName)
  }

  private func persistedAppleLanguages(in suiteName: String) -> [String]? {
    UserDefaults.standard.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String]
  }
}
