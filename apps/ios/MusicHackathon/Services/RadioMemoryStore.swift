import Foundation

protocol RadioMemoryStoring {
  func buildContext() async throws -> RadioMemoryContext
  func record(_ event: RadioMemoryEvent) async throws
  func compressionRequest() async throws -> RadioMemoryCompressionRequest?
  func applyCompression(_ proposal: RadioCompressedMemory) async throws
  func clear() async throws
  func snapshot() async throws -> RadioMemorySnapshot
}

struct RadioMemoryContext: Codable, Equatable {
  var tasteSummary: String = ""
  var avoidSummary: String = ""
  var likedArtistsTop: [String] = []
  var skippedMoodsTop: [String] = []
  var recentlyPlayedTrackKeys: [String] = []
  var recentEvents: [RadioMemoryEvent] = []
  var pinnedNotes: [String] = []
}

struct RadioMemoryEvent: Codable, Equatable, Identifiable {
  let id: UUID
  var type: String
  var trackKey: String?
  var title: String?
  var artist: String?
  var mood: String?
  var at: String

  init(
    id: UUID = UUID(),
    type: String,
    track: Track? = nil,
    at: Date = Date()
  ) {
    self.id = id
    self.type = type
    trackKey = track?.radioIdentity
    title = track?.title
    artist = track?.artist
    mood = track?.mood
    self.at = Self.timestampFormatter.string(from: at)
  }

  private static let timestampFormatter = ISO8601DateFormatter()
}

struct RadioMemoryCompressionRequest: Codable, Equatable {
  var existingSummary: RadioMemoryContext
  var newEvents: [RadioMemoryEvent]
  var pinnedNotes: [String]
  var maxOutputTokens: Int
}

struct RadioCompressedMemory: Codable, Equatable {
  var tasteSummary: String
  var avoidSummary: String
  var likedArtistsTop: [String]
  var skippedMoodsTop: [String]
  var pinnedNotes: [String]
}

struct RadioMemorySnapshot: Equatable {
  var eventCount: Int
  var uncompressedEventCount: Int
  var tasteSummary: String
  var avoidSummary: String
  var markdownPreview: String
}

actor RadioMemoryStore: RadioMemoryStoring {
  private let directoryURL: URL
  private let jsonURL: URL
  private let markdownURL: URL
  private let compressionEventThreshold: Int
  private let maxRecentEvents = 120
  private let maxContextEvents = 24

  init(
    directoryURL: URL? = nil,
    compressionEventThreshold: Int = 20
  ) {
    let resolvedDirectory = directoryURL ?? Self.defaultDirectoryURL()
    self.directoryURL = resolvedDirectory
    jsonURL = resolvedDirectory.appending(path: "memory.json")
    markdownURL = resolvedDirectory.appending(path: "memory.md")
    self.compressionEventThreshold = compressionEventThreshold
  }

  func buildContext() async throws -> RadioMemoryContext {
    let memory = try loadMemory()
    return RadioMemoryContext(
      tasteSummary: memory.summary.taste,
      avoidSummary: memory.summary.avoid,
      likedArtistsTop: rankedValues(memory.counters.likedArtists, limit: 12),
      skippedMoodsTop: rankedValues(memory.counters.skippedMoods, limit: 12),
      recentlyPlayedTrackKeys: Array(memory.recentlyPlayedTrackKeys.prefix(60)),
      recentEvents: Array(memory.recentEvents.suffix(maxContextEvents)),
      pinnedNotes: memory.pinnedNotes
    )
  }

  func record(_ event: RadioMemoryEvent) async throws {
    var memory = try loadMemory()
    memory.recentEvents.append(event)
    memory.recentEvents = Array(memory.recentEvents.suffix(maxRecentEvents))
    memory.uncompressedEventCount += 1

    if let trackKey = event.trackKey, ["play", "complete", "skip", "like", "dislike"].contains(event.type) {
      memory.recentlyPlayedTrackKeys.removeAll { $0 == trackKey }
      memory.recentlyPlayedTrackKeys.insert(trackKey, at: 0)
      memory.recentlyPlayedTrackKeys = Array(memory.recentlyPlayedTrackKeys.prefix(80))
    }

    switch event.type {
    case "like", "complete", "replay":
      increment(event.artist, in: &memory.counters.likedArtists)
    case "skip", "dislike":
      increment(event.mood, in: &memory.counters.skippedMoods)
    default:
      break
    }

    try save(memory)
  }

  func compressionRequest() async throws -> RadioMemoryCompressionRequest? {
    let memory = try loadMemory()
    guard memory.uncompressedEventCount >= compressionEventThreshold else {
      return nil
    }

    return RadioMemoryCompressionRequest(
      existingSummary: try await buildContext(),
      newEvents: Array(memory.recentEvents.suffix(memory.uncompressedEventCount)),
      pinnedNotes: memory.pinnedNotes,
      maxOutputTokens: 500
    )
  }

  func applyCompression(_ proposal: RadioCompressedMemory) async throws {
    var memory = try loadMemory()
    memory.summary = RadioStoredMemory.Summary(
      taste: proposal.tasteSummary,
      avoid: proposal.avoidSummary,
      updatedAt: RadioMemoryEvent.timestampNow()
    )
    memory.pinnedNotes = Array(orderedUnique(memory.pinnedNotes + proposal.pinnedNotes).prefix(20))
    memory.counters.likedArtists = rankedDictionary(proposal.likedArtistsTop, existing: memory.counters.likedArtists)
    memory.counters.skippedMoods = rankedDictionary(proposal.skippedMoodsTop, existing: memory.counters.skippedMoods)
    memory.uncompressedEventCount = 0
    try save(memory)
  }

  func clear() async throws {
    try save(RadioStoredMemory())
  }

  func snapshot() async throws -> RadioMemorySnapshot {
    let memory = try loadMemory()
    return RadioMemorySnapshot(
      eventCount: memory.recentEvents.count,
      uncompressedEventCount: memory.uncompressedEventCount,
      tasteSummary: memory.summary.taste,
      avoidSummary: memory.summary.avoid,
      markdownPreview: renderMarkdown(memory)
    )
  }

  private func loadMemory() throws -> RadioStoredMemory {
    try ensureDirectory()
    guard FileManager.default.fileExists(atPath: jsonURL.path) else {
      let memory = RadioStoredMemory()
      try save(memory)
      return memory
    }

    let data = try Data(contentsOf: jsonURL)
    return try JSONDecoder().decode(RadioStoredMemory.self, from: data)
  }

  private func save(_ memory: RadioStoredMemory) throws {
    try ensureDirectory()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(memory)
    try data.write(to: jsonURL, options: [.atomic, .completeFileProtection])

    let markdownData = Data(renderMarkdown(memory).utf8)
    try markdownData.write(to: markdownURL, options: [.atomic, .completeFileProtection])
  }

  private func ensureDirectory() throws {
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  private func renderMarkdown(_ memory: RadioStoredMemory) -> String {
    var lines: [String] = [
      "# Airset Memory",
      "",
      "This local file is generated from memory.json. Airset sends only a small relevant summary to the backend.",
      "",
      "## Taste Summary",
      memory.summary.taste.isEmpty ? "- No stable taste summary yet." : "- \(memory.summary.taste)",
      "",
      "## Avoid",
      memory.summary.avoid.isEmpty ? "- No avoid summary yet." : "- \(memory.summary.avoid)",
      "",
      "## Top Liked Artists",
    ]

    lines.append(contentsOf: markdownList(rankedValues(memory.counters.likedArtists, limit: 8)))
    lines.append("")
    lines.append("## Recently Skipped Moods")
    lines.append(contentsOf: markdownList(rankedValues(memory.counters.skippedMoods, limit: 8)))
    lines.append("")
    lines.append("## Pinned Notes")
    lines.append(contentsOf: markdownList(memory.pinnedNotes))
    lines.append("")
    lines.append("## Recent Events")
    lines.append(contentsOf: memory.recentEvents.suffix(20).map { event in
      let title = event.title ?? event.trackKey ?? "unknown track"
      let artist = event.artist.map { " by \($0)" } ?? ""
      return "- \(event.at) \(event.type): \(title)\(artist)"
    })

    return lines.joined(separator: "\n") + "\n"
  }

  private func markdownList(_ values: [String]) -> [String] {
    values.isEmpty ? ["- None yet."] : values.map { "- \($0)" }
  }

  private func increment(_ value: String?, in dictionary: inout [String: Int]) {
    guard let value, !value.isEmpty else { return }
    dictionary[value, default: 0] += 1
  }

  private func rankedValues(_ dictionary: [String: Int], limit: Int) -> [String] {
    dictionary
      .sorted { lhs, rhs in
        if lhs.value == rhs.value {
          return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
        return lhs.value > rhs.value
      }
      .prefix(limit)
      .map(\.key)
  }

  private func rankedDictionary(_ values: [String], existing: [String: Int]) -> [String: Int] {
    var result = existing
    for (index, value) in values.enumerated() where !value.isEmpty {
      result[value] = max(result[value, default: 0], max(1, values.count - index))
    }
    return result
  }

  private func orderedUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for value in values where !value.isEmpty && !seen.contains(value) {
      seen.insert(value)
      ordered.append(value)
    }
    return ordered
  }

  private static func defaultDirectoryURL() -> URL {
    let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return baseURL.appending(path: "AirsetRadioMemory", directoryHint: .isDirectory)
  }
}

private struct RadioStoredMemory: Codable, Equatable {
  struct Summary: Codable, Equatable {
    var taste: String = ""
    var avoid: String = ""
    var updatedAt: String = ""
  }

  struct Counters: Codable, Equatable {
    var likedArtists: [String: Int] = [:]
    var skippedMoods: [String: Int] = [:]
  }

  var version = 1
  var summary = Summary()
  var counters = Counters()
  var recentlyPlayedTrackKeys: [String] = []
  var recentEvents: [RadioMemoryEvent] = []
  var pinnedNotes: [String] = []
  var uncompressedEventCount = 0
}

private extension RadioMemoryEvent {
  static func timestampNow() -> String {
    ISO8601DateFormatter().string(from: Date())
  }
}
