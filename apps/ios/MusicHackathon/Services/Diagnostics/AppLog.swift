import Foundation
import OSLog

enum AppLog {
  static let subsystem = Bundle.main.bundleIdentifier ?? "com.1pitaph.music"

  static func log(_ event: DiagnosticLogEvent) {
    let logger = Logger(subsystem: subsystem, category: event.chain.rawValue)
    let message = "[\(event.event)] \(event.message)"
    let correlationID = event.correlationID ?? "none"

    switch event.level {
    case .debug:
      logger.debug("\(message, privacy: .public) correlation=\(correlationID, privacy: .public)")
    case .info:
      logger.info("\(message, privacy: .public) correlation=\(correlationID, privacy: .public)")
    case .notice:
      logger.notice("\(message, privacy: .public) correlation=\(correlationID, privacy: .public)")
    case .warning, .error:
      logger.error("\(message, privacy: .public) correlation=\(correlationID, privacy: .public)")
    case .fault:
      logger.fault("\(message, privacy: .public) correlation=\(correlationID, privacy: .public)")
    }
  }
}
