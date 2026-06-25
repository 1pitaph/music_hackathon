import CryptoKit
import Foundation

enum DiagnosticLogLevel: String, CaseIterable, Codable, Hashable {
  case debug
  case info
  case notice
  case warning
  case error
  case fault

  var title: String {
    switch self {
    case .debug:
      "调试"
    case .info:
      "信息"
    case .notice:
      "关键"
    case .warning:
      "警告"
    case .error:
      "错误"
    case .fault:
      "故障"
    }
  }

  var systemImage: String {
    switch self {
    case .debug:
      "curlybraces"
    case .info:
      "info.circle"
    case .notice:
      "checkmark.seal"
    case .warning:
      "exclamationmark.triangle.fill"
    case .error:
      "exclamationmark.octagon.fill"
    case .fault:
      "xmark.octagon.fill"
    }
  }

  var priority: Int {
    switch self {
    case .debug:
      0
    case .info:
      1
    case .notice:
      2
    case .warning:
      3
    case .error:
      4
    case .fault:
      5
    }
  }
}

enum DiagnosticLogChain: String, CaseIterable, Codable, Hashable {
  case appLifecycle = "app.lifecycle"
  case uiState = "ui.state"
  case musicAuthorization = "music.authorization"
  case musicSubscription = "music.subscription"
  case musicCatalog = "music.catalog"
  case playbackAppleMusic = "playback.appleMusic"
  case playbackPreview = "playback.preview"
  case playbackSpeech = "playback.speech"
  case audioSession = "audio.session"
  case radioBackend = "radio.backend"
  case radioStation = "radio.station"
  case radioMemory = "radio.memory"
  case libraryAppleMusic = "library.appleMusic"
  case diagnosticsExport = "diagnostics.export"
  case network = "network"
  case cache = "cache"

  var title: String {
    switch self {
    case .appLifecycle:
      "App 生命周期"
    case .uiState:
      "界面状态"
    case .musicAuthorization:
      "Apple Music 授权"
    case .musicSubscription:
      "Apple Music 订阅"
    case .musicCatalog:
      "Apple Music 目录"
    case .playbackAppleMusic:
      "完整歌曲播放"
    case .playbackPreview:
      "试听播放"
    case .playbackSpeech:
      "主持人语音"
    case .audioSession:
      "音频会话"
    case .radioBackend:
      "后端电台"
    case .radioStation:
      "电台队列"
    case .radioMemory:
      "本地声音档案"
    case .libraryAppleMusic:
      "Apple Music 资料库"
    case .diagnosticsExport:
      "诊断导出"
    case .network:
      "网络请求"
    case .cache:
      "缓存"
    }
  }

  var systemImage: String {
    switch self {
    case .appLifecycle:
      "app.badge"
    case .uiState:
      "rectangle.stack"
    case .musicAuthorization, .musicSubscription:
      "person.badge.key"
    case .musicCatalog, .libraryAppleMusic:
      "music.note.list"
    case .playbackAppleMusic:
      "play.circle"
    case .playbackPreview:
      "waveform"
    case .playbackSpeech:
      "quote.bubble"
    case .audioSession:
      "speaker.wave.2"
    case .radioBackend, .radioStation:
      "dot.radiowaves.left.and.right"
    case .radioMemory:
      "brain"
    case .diagnosticsExport:
      "square.and.arrow.up"
    case .network:
      "network"
    case .cache:
      "externaldrive"
    }
  }
}

struct DiagnosticLogEvent: Codable, Hashable, Identifiable {
  var schema = 1
  let id: UUID
  let timestamp: Date
  let level: DiagnosticLogLevel
  let chain: DiagnosticLogChain
  let event: String
  let message: String
  let sessionID: String
  let correlationID: String?
  let retention: String
  let privacy: String
  let payload: [String: String]

  init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    level: DiagnosticLogLevel,
    chain: DiagnosticLogChain,
    event: String,
    message: String,
    sessionID: String,
    correlationID: String? = nil,
    retention: String = "diagnostic_info",
    privacy: String = "private_redacted",
    payload: [String: String] = [:]
  ) {
    self.id = id
    self.timestamp = timestamp
    self.level = level
    self.chain = chain
    self.event = event
    self.message = message
    self.sessionID = sessionID
    self.correlationID = correlationID
    self.retention = retention
    self.privacy = privacy
    self.payload = payload
  }

  var correlationSuffix: String? {
    guard let correlationID else { return nil }
    return String(correlationID.suffix(6))
  }
}

struct DiagnosticsStorageSummary: Equatable {
  var fileCount: Int = 0
  var totalBytes: Int64 = 0

  var totalSizeText: String {
    ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
  }
}

struct DiagnosticsAppContext: Codable, Hashable {
  let appVersion: String
  let buildNumber: String
  let bundleIdentifier: String
  let osVersion: String
  let deviceModel: String
  let localeIdentifier: String
  let timeZoneIdentifier: String
  let generatedAt: Date
}

struct DiagnosticsIssueReport: Codable {
  var schema = 1
  let context: DiagnosticsAppContext
  let privacyNotes: [String]
  let storageSummary: DiagnosticsStorageSummaryPayload
  let events: [DiagnosticLogEvent]
}

struct DiagnosticsStorageSummaryPayload: Codable {
  let fileCount: Int
  let totalBytes: Int64
}

enum DiagnosticsPayload {
  static func bool(_ value: Bool) -> String {
    value ? "true" : "false"
  }

  static func durationMilliseconds(_ seconds: TimeInterval) -> String {
    String(Int((seconds * 1000).rounded()))
  }

  static func track(_ track: Track) -> [String: String] {
    var payload: [String: String] = [
      "track_key_hash": DiagnosticsRedactor.hash(track.radioIdentity),
      "has_apple_music_id": bool(track.normalizedAppleMusicID != nil),
      "has_preview_url": bool(track.previewURL != nil),
      "duration_seconds": String(Int(track.duration.rounded()))
    ]

    if let appleMusicID = track.normalizedAppleMusicID {
      payload["apple_music_id_hash"] = DiagnosticsRedactor.hash(appleMusicID)
    }

    if let host = track.previewURL?.host {
      payload["preview_host"] = host
    }

    if let source = track.source {
      payload["source"] = source
    }

    if let sourceLane = track.sourceLane {
      payload["source_lane"] = sourceLane
    }

    return payload
  }

  static func url(_ url: URL?) -> [String: String] {
    guard let url else { return [:] }
    return [
      "url_host": url.host ?? "unknown",
      "url_path_extension": url.pathExtension,
      "url_hash": DiagnosticsRedactor.hash(url.absoluteString)
    ]
  }

  static func error(_ error: Error) -> [String: String] {
    let nsError = error as NSError
    var payload: [String: String] = [
      "error_domain": nsError.domain,
      "error_code": String(nsError.code),
      "error_description": nsError.localizedDescription
    ]

    if let failureReason = nsError.localizedFailureReason {
      payload["error_failure_reason"] = failureReason
    }

    if let recoverySuggestion = nsError.localizedRecoverySuggestion {
      payload["error_recovery_suggestion"] = recoverySuggestion
    }

    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      payload["underlying_error_domain"] = underlying.domain
      payload["underlying_error_code"] = String(underlying.code)
      payload["underlying_error_description"] = underlying.localizedDescription
    }

    return payload
  }

  static func merge(_ payloads: [String: String]...) -> [String: String] {
    payloads.reduce(into: [:]) { result, payload in
      result.merge(payload) { _, newValue in newValue }
    }
  }
}

enum DiagnosticsRedactor {
  private static let saltKey = "diagnostics.hashSalt"

  static func hash(_ value: String) -> String {
    let saltedValue = "\(salt)::\(value)"
    let digest = SHA256.hash(data: Data(saltedValue.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static var salt: String {
    if let existing = UserDefaults.standard.string(forKey: saltKey), !existing.isEmpty {
      return existing
    }

    let newSalt = UUID().uuidString
    UserDefaults.standard.set(newSalt, forKey: saltKey)
    return newSalt
  }
}
