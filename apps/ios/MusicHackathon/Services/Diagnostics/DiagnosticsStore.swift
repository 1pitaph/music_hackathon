import Foundation
import Observation
import UIKit

actor DiagnosticsLogWriter {
  private let directoryURL: URL
  private let activeDirectoryURL: URL
  private let rotatedDirectoryURL: URL
  private let activeURL: URL
  private let maxActiveFileBytes: Int64
  private let maxRotatedFiles: Int
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    directoryURL: URL? = nil,
    maxActiveFileBytes: Int64 = 1_048_576,
    maxRotatedFiles: Int = 8
  ) {
    let resolvedDirectory = directoryURL ?? Self.defaultDirectoryURL()
    self.directoryURL = resolvedDirectory
    activeDirectoryURL = resolvedDirectory.appending(path: "active", directoryHint: .isDirectory)
    rotatedDirectoryURL = resolvedDirectory.appending(path: "rotated", directoryHint: .isDirectory)
    activeURL = activeDirectoryURL.appending(path: "events.jsonl")
    self.maxActiveFileBytes = maxActiveFileBytes
    self.maxRotatedFiles = maxRotatedFiles
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func write(_ event: DiagnosticLogEvent) throws {
    try ensureDirectories()
    let data = try encoder.encode(event)
    let lineData = data + Data([0x0A])
    try rotateIfNeeded(extraBytes: Int64(lineData.count))
    try append(lineData)
    try cleanupRotatedFiles()
  }

  func loadRecentEvents(limit: Int = 300) throws -> [DiagnosticLogEvent] {
    try ensureDirectories()
    let urls = try eventFileURLs()
    var events: [DiagnosticLogEvent] = []

    for url in urls {
      let data = try Data(contentsOf: url)
      guard let text = String(data: data, encoding: .utf8) else { continue }
      for line in text.split(separator: "\n") {
        guard let lineData = String(line).data(using: .utf8) else { continue }
        if let event = try? decoder.decode(DiagnosticLogEvent.self, from: lineData) {
          events.append(event)
        }
      }
    }

    return Array(
      events
        .sorted { $0.timestamp > $1.timestamp }
        .prefix(limit)
    )
  }

  func clear() throws {
    if FileManager.default.fileExists(atPath: directoryURL.path) {
      try FileManager.default.removeItem(at: directoryURL)
    }
    try ensureDirectories()
  }

  func storageSummary() throws -> DiagnosticsStorageSummary {
    try ensureDirectories()
    let urls = try eventFileURLs()
    let totalBytes = try urls.reduce(Int64(0)) { partialResult, url in
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      return partialResult + ((attributes[.size] as? NSNumber)?.int64Value ?? 0)
    }
    return DiagnosticsStorageSummary(fileCount: urls.count, totalBytes: totalBytes)
  }

  func exportReport(
    events: [DiagnosticLogEvent],
    context: DiagnosticsAppContext,
    storageSummary: DiagnosticsStorageSummary
  ) throws -> URL {
    let exportDirectoryURL = FileManager.default.temporaryDirectory
      .appending(path: "AirsetDiagnosticsExports", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: exportDirectoryURL,
      withIntermediateDirectories: true
    )

    let timestamp = Self.fileTimestampFormatter.string(from: Date())
    let exportURL = exportDirectoryURL.appending(path: "airset-diagnostics-\(timestamp).json")
    let report = DiagnosticsIssueReport(
      context: context,
      privacyNotes: [
        "Track, Apple Music, playlist, speech, and URL identifiers are hashed or reduced to non-secret metadata.",
        "Authorization tokens, account identifiers, full private URLs, audio files, and artwork are not included.",
        L10n.tr("diagnostics.report.privacy.radioMemoryRawEventsExcluded")
      ],
      storageSummary: DiagnosticsStorageSummaryPayload(
        fileCount: storageSummary.fileCount,
        totalBytes: storageSummary.totalBytes
      ),
      events: events
    )

    let reportEncoder = JSONEncoder()
    reportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    reportEncoder.dateEncodingStrategy = .iso8601
    let data = try reportEncoder.encode(report)
    try data.write(to: exportURL, options: [.atomic, .completeFileProtection])
    return exportURL
  }

  private func eventFileURLs() throws -> [URL] {
    let rotatedURLs = (try? FileManager.default.contentsOfDirectory(
      at: rotatedDirectoryURL,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    let allURLs = rotatedURLs + (FileManager.default.fileExists(atPath: activeURL.path) ? [activeURL] : [])
    return allURLs.sorted { lhs, rhs in
      modificationDate(for: lhs) < modificationDate(for: rhs)
    }
  }

  private func ensureDirectories() throws {
    try FileManager.default.createDirectory(
      at: activeDirectoryURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: rotatedDirectoryURL,
      withIntermediateDirectories: true
    )
  }

  private func rotateIfNeeded(extraBytes: Int64) throws {
    guard FileManager.default.fileExists(atPath: activeURL.path) else { return }
    let attributes = try FileManager.default.attributesOfItem(atPath: activeURL.path)
    let currentBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard currentBytes + extraBytes > maxActiveFileBytes else { return }

    let rotatedURL = rotatedDirectoryURL
      .appending(path: "events-\(Self.fileTimestampFormatter.string(from: Date())).jsonl")
    try FileManager.default.moveItem(at: activeURL, to: rotatedURL)
  }

  private func append(_ data: Data) throws {
    if !FileManager.default.fileExists(atPath: activeURL.path) {
      FileManager.default.createFile(atPath: activeURL.path, contents: nil)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: activeURL.path
      )
    }

    let handle = try FileHandle(forWritingTo: activeURL)
    defer {
      try? handle.close()
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
  }

  private func cleanupRotatedFiles() throws {
    let rotatedURLs = ((try? FileManager.default.contentsOfDirectory(
      at: rotatedDirectoryURL,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? [])
      .sorted { modificationDate(for: $0) > modificationDate(for: $1) }

    for url in rotatedURLs.dropFirst(maxRotatedFiles) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func modificationDate(for url: URL) -> Date {
    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
    return values?.contentModificationDate ?? .distantPast
  }

  private static func defaultDirectoryURL() -> URL {
    let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return baseURL.appending(path: "AirsetDiagnostics", directoryHint: .isDirectory)
  }

  private static let fileTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
    return formatter
  }()
}

@MainActor
@Observable
final class DiagnosticsStore {
  var recentEvents: [DiagnosticLogEvent] = []
  var storageSummary = DiagnosticsStorageSummary()
  var isVerboseLoggingEnabled = false
  var verboseLoggingExpiresAt: Date?
  var lastExportURL: URL?
  var lastErrorMessage: String?

  @ObservationIgnored private let writer: DiagnosticsLogWriter
  @ObservationIgnored private var verboseExpirationTask: Task<Void, Never>?
  @ObservationIgnored private let maxInMemoryEvents = 300

  let sessionID: String

  init(
    writer: DiagnosticsLogWriter = DiagnosticsLogWriter(),
    sessionID: String = UUID().uuidString,
    loadsExistingEvents: Bool = true
  ) {
    self.writer = writer
    self.sessionID = sessionID

    if loadsExistingEvents {
      Task {
        await refreshRecentEvents()
      }
    }
  }

  var errorCount: Int {
    recentEvents.filter { $0.level.priority >= DiagnosticLogLevel.warning.priority }.count
  }

  var lastEventText: String {
    guard let event = recentEvents.first else { return L10n.tr("diagnostics.noLogs") }
    return event.timestamp.formatted(.dateTime.hour().minute().second())
  }

  func record(
    _ level: DiagnosticLogLevel,
    chain: DiagnosticLogChain,
    event: String,
    message: String,
    correlationID: String? = nil,
    retention: String = "diagnostic_info",
    privacy: String = "private_redacted",
    payload: [String: String] = [:]
  ) {
    expireVerboseLoggingIfNeeded()
    let logEvent = DiagnosticLogEvent(
      level: level,
      chain: chain,
      event: event,
      message: message,
      sessionID: sessionID,
      correlationID: correlationID,
      retention: retention,
      privacy: privacy,
      payload: payload
    )

    AppLog.log(logEvent)

    guard shouldPersist(level) else { return }
    recentEvents.insert(logEvent, at: 0)
    recentEvents = Array(recentEvents.prefix(maxInMemoryEvents))

    Task {
      do {
        try await writer.write(logEvent)
        await refreshStorageSummary()
      } catch {
        await MainActor.run {
          self.lastErrorMessage = error.localizedDescription
        }
      }
    }
  }

  func enableVerboseLogging(for duration: TimeInterval = 15 * 60) {
    isVerboseLoggingEnabled = true
    verboseLoggingExpiresAt = Date().addingTimeInterval(duration)
    verboseExpirationTask?.cancel()
    verboseExpirationTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(duration))
      await MainActor.run {
        guard let self else { return }
        self.isVerboseLoggingEnabled = false
        self.verboseLoggingExpiresAt = nil
        self.record(
          .notice,
          chain: .diagnosticsExport,
          event: "verbose_logging_expired",
          message: L10n.tr("diagnostic.message.verboseLoggingExpired")
        )
      }
    }

    record(
      .notice,
      chain: .diagnosticsExport,
      event: "verbose_logging_enabled",
      message: L10n.tr("diagnostic.message.verboseLoggingEnabled"),
      payload: ["duration_seconds": String(Int(duration))]
    )
  }

  func disableVerboseLogging() {
    verboseExpirationTask?.cancel()
    verboseExpirationTask = nil
    isVerboseLoggingEnabled = false
    verboseLoggingExpiresAt = nil
    record(
      .notice,
      chain: .diagnosticsExport,
      event: "verbose_logging_disabled",
      message: L10n.tr("diagnostic.message.verboseLoggingDisabled")
    )
  }

  func refreshRecentEvents() async {
    do {
      let loadedEvents = try await writer.loadRecentEvents(limit: maxInMemoryEvents)
      let summary = try await writer.storageSummary()
      recentEvents = loadedEvents
      storageSummary = summary
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = error.localizedDescription
    }
  }

  func refreshStorageSummary() async {
    do {
      storageSummary = try await writer.storageSummary()
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = error.localizedDescription
    }
  }

  func clearLogs() async {
    do {
      try await writer.clear()
      recentEvents = []
      storageSummary = DiagnosticsStorageSummary()
      lastExportURL = nil
      lastErrorMessage = nil
      record(
        .notice,
        chain: .diagnosticsExport,
        event: "logs_cleared",
        message: L10n.tr("diagnostic.message.diagnosticsLogsCleared")
      )
    } catch {
      lastErrorMessage = error.localizedDescription
    }
  }

  func exportIssueReport() async -> URL? {
    do {
      let events = try await writer.loadRecentEvents(limit: maxInMemoryEvents)
      let summary = try await writer.storageSummary()
      let exportURL = try await writer.exportReport(
        events: events,
        context: Self.appContext(),
        storageSummary: summary
      )
      lastExportURL = exportURL
      storageSummary = summary
      record(
        .notice,
        chain: .diagnosticsExport,
        event: "issue_report_exported",
        message: L10n.tr("diagnostic.message.diagnosticsReportGenerated"),
        payload: [
          "event_count": String(events.count),
          "file_size_bytes": String((try? exportURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        ]
      )
      return exportURL
    } catch {
      lastErrorMessage = error.localizedDescription
      record(
        .error,
        chain: .diagnosticsExport,
        event: "issue_report_export_failed",
        message: L10n.tr("diagnostic.message.diagnosticsReportFailed"),
        payload: DiagnosticsPayload.error(error)
      )
      return nil
    }
  }

  private func shouldPersist(_ level: DiagnosticLogLevel) -> Bool {
    level != .debug || isVerboseLoggingEnabled
  }

  private func expireVerboseLoggingIfNeeded() {
    guard
      isVerboseLoggingEnabled,
      let verboseLoggingExpiresAt,
      verboseLoggingExpiresAt <= Date()
    else { return }

    isVerboseLoggingEnabled = false
    self.verboseLoggingExpiresAt = nil
    verboseExpirationTask?.cancel()
    verboseExpirationTask = nil
  }

  private static func appContext() -> DiagnosticsAppContext {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
    let build = info["CFBundleVersion"] as? String ?? "unknown"
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"

    return DiagnosticsAppContext(
      appVersion: version,
      buildNumber: build,
      bundleIdentifier: bundleIdentifier,
      osVersion: UIDevice.current.systemVersion,
      deviceModel: UIDevice.current.model,
      localeIdentifier: Locale.current.identifier,
      timeZoneIdentifier: TimeZone.current.identifier,
      generatedAt: Date()
    )
  }
}

extension DiagnosticsStore {
  static func preview() -> DiagnosticsStore {
    let writer = DiagnosticsLogWriter(
      directoryURL: FileManager.default.temporaryDirectory
        .appending(path: "AirsetDiagnosticsPreview-\(UUID().uuidString)", directoryHint: .isDirectory),
      maxActiveFileBytes: 32_768,
      maxRotatedFiles: 1
    )
    let store = DiagnosticsStore(writer: writer, loadsExistingEvents: false)
    store.record(
      .warning,
      chain: .playbackAppleMusic,
      event: "fallback_preview",
      message: L10n.tr("playback.error.fallbackPreview"),
      correlationID: "preview-attempt-123456",
      payload: ["failed_phase": "prepare_to_play"]
    )
    store.record(
      .notice,
      chain: .musicAuthorization,
      event: "subscription_ready",
      message: L10n.tr("diagnostic.message.catalogPlaybackReady"),
      payload: ["can_play_catalog_content": "true"]
    )
    return store
  }
}
