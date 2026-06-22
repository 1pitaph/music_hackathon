import Foundation

struct RadioStateStore {
  static let defaultKey = "airset.radio.memory.v1"

  private let userDefaults: UserDefaults
  private let key: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(userDefaults: UserDefaults = .standard, key: String = Self.defaultKey) {
    self.userDefaults = userDefaults
    self.key = key
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func loadMemory() -> RadioMemory {
    guard let data = userDefaults.data(forKey: key) else {
      return RadioMemory()
    }

    do {
      return try decoder.decode(RadioMemory.self, from: data)
    } catch {
      return RadioMemory()
    }
  }

  func saveMemory(_ memory: RadioMemory) {
    guard let data = try? encoder.encode(memory) else { return }
    userDefaults.set(data, forKey: key)
  }
}
