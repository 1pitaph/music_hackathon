import XCTest
@testable import MusicHackathon

final class DiagnosticsLogWriterTests: XCTestCase {
  func testWriteLoadAndClearEvents() async throws {
    let directoryURL = temporaryDirectoryURL()
    let writer = DiagnosticsLogWriter(
      directoryURL: directoryURL,
      maxActiveFileBytes: 512,
      maxRotatedFiles: 2
    )
    let event = DiagnosticLogEvent(
      level: .error,
      chain: .playbackAppleMusic,
      event: "attempt_failed",
      message: "Playback failed.",
      sessionID: "session-1",
      correlationID: "attempt-1",
      payload: ["failed_phase": "play"]
    )

    try await writer.write(event)

    let loadedEvents = try await writer.loadRecentEvents()
    XCTAssertEqual(loadedEvents.count, 1)
    XCTAssertEqual(loadedEvents.first?.event, "attempt_failed")
    XCTAssertEqual(loadedEvents.first?.payload["failed_phase"], "play")

    let summary = try await writer.storageSummary()
    XCTAssertEqual(summary.fileCount, 1)
    XCTAssertGreaterThan(summary.totalBytes, 0)

    try await writer.clear()

    let clearedEvents = try await writer.loadRecentEvents()
    XCTAssertTrue(clearedEvents.isEmpty)
  }

  func testExportReportWritesRedactedDiagnosticPackage() async throws {
    let directoryURL = temporaryDirectoryURL()
    let writer = DiagnosticsLogWriter(directoryURL: directoryURL)
    let event = DiagnosticLogEvent(
      level: .notice,
      chain: .musicSubscription,
      event: "catalog_playback_ready",
      message: "Apple Music catalog playback is ready.",
      sessionID: "session-1",
      payload: ["can_play_catalog_content": "true"]
    )
    try await writer.write(event)

    let events = try await writer.loadRecentEvents()
    let exportURL = try await writer.exportReport(
      events: events,
      context: DiagnosticsAppContext(
        appVersion: "1.0",
        buildNumber: "1",
        bundleIdentifier: "com.test.music",
        osVersion: "26.0",
        deviceModel: "iPhone",
        localeIdentifier: "en_US",
        timeZoneIdentifier: "UTC",
        generatedAt: Date(timeIntervalSince1970: 0)
      ),
      storageSummary: try await writer.storageSummary()
    )

    let data = try Data(contentsOf: exportURL)
    let report = try JSONDecoder.iso8601.decode(DiagnosticsIssueReport.self, from: data)

    XCTAssertEqual(report.events.count, 1)
    XCTAssertEqual(report.events.first?.event, "catalog_playback_ready")
    XCTAssertFalse(report.privacyNotes.isEmpty)
  }

  private func temporaryDirectoryURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "DiagnosticsLogWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }
}

private extension JSONDecoder {
  static var iso8601: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
