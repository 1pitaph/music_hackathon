import Foundation
import MusicKit
import Observation

enum AppleMusicAccessReadiness: Equatable {
  case notDetermined
  case requestingAuthorization
  case denied
  case restricted
  case checkingSubscription
  case subscriptionStatusUnknown
  case ready
  case needsSubscription
  case catalogPlaybackUnavailable
  case privacyAcknowledgementRequired
  case subscriptionCheckFailed(String)
}

enum AppleMusicSubscriptionIssue: Equatable {
  case privacyAcknowledgementRequired
  case permissionDenied
  case unknown(String)

  init(error: Error) {
    if let subscriptionError = error as? MusicSubscription.Error {
      switch subscriptionError {
      case .privacyAcknowledgementRequired:
        self = .privacyAcknowledgementRequired
      case .permissionDenied:
        self = .permissionDenied
      case .unknown:
        self = .unknown(subscriptionError.localizedDescription)
      @unknown default:
        self = .unknown(subscriptionError.localizedDescription)
      }
      return
    }

    let description = error.localizedDescription
    if description.localizedCaseInsensitiveContains("privacy")
      && description.localizedCaseInsensitiveContains("acknowledg") {
      self = .privacyAcknowledgementRequired
    } else {
      self = .unknown(description)
    }
  }

  var message: String {
    switch self {
    case .privacyAcknowledgementRequired:
      L10n.tr("appleMusic.error.privacyAcknowledgementRequired")
    case .permissionDenied:
      L10n.tr("appleMusic.error.subscriptionPermissionDenied")
    case .unknown(let message):
      message
    }
  }
}

enum AppleMusicAccessError: LocalizedError {
  case authorizationDenied
  case authorizationRestricted
  case authorizationRequired
  case subscriptionRequired
  case catalogPlaybackUnavailable
  case privacyAcknowledgementRequired
  case subscriptionCheckFailed(String)

  var errorDescription: String? {
    switch self {
    case .authorizationDenied:
      L10n.tr("appleMusic.error.authorizationDenied")
    case .authorizationRestricted:
      L10n.tr("appleMusic.error.authorizationRestricted")
    case .authorizationRequired:
      L10n.tr("appleMusic.error.authorizationRequired")
    case .subscriptionRequired:
      L10n.tr("appleMusic.error.subscriptionRequired")
    case .catalogPlaybackUnavailable:
      L10n.tr("appleMusic.error.catalogPlaybackUnavailable")
    case .privacyAcknowledgementRequired:
      L10n.tr("appleMusic.error.openMusicForPrivacy")
    case .subscriptionCheckFailed(let message):
      message
    }
  }
}

@MainActor
@Observable
final class MusicAuthorizationService {
  var status: MusicAuthorization.Status = MusicAuthorization.currentStatus
  var subscription: MusicSubscription?
  var subscriptionIssue: AppleMusicSubscriptionIssue?
  var isRequestingAccess = false
  var isRefreshingSubscription = false
  var lastErrorMessage: String?

  @ObservationIgnored private let diagnostics: DiagnosticsStore?
  @ObservationIgnored private var subscriptionUpdatesTask: Task<Void, Never>?

  init(diagnostics: DiagnosticsStore? = nil) {
    self.diagnostics = diagnostics
    startObservingSubscriptionUpdates()
  }

  deinit {
    subscriptionUpdatesTask?.cancel()
  }

  func refresh() {
    status = MusicAuthorization.currentStatus
    diagnostics?.record(
      .info,
      chain: .musicAuthorization,
      event: "status_refresh",
      message: L10n.tr("diagnostic.message.musicAuthorizationStatusRefreshed"),
      payload: ["authorization_status": statusDiagnosticValue]
    )
  }

  func refreshAccessState() async {
    refresh()
    await refreshSubscription()
  }

  func requestAccess() async {
    guard !isRequestingAccess else { return }

    isRequestingAccess = true
    diagnostics?.record(
      .notice,
      chain: .musicAuthorization,
      event: "request_start",
      message: L10n.tr("diagnostic.message.musicAuthorizationRequestStarted")
    )
    status = await MusicAuthorization.request()
    isRequestingAccess = false
    diagnostics?.record(
      status == .authorized ? .notice : .warning,
      chain: .musicAuthorization,
      event: "request_result",
      message: L10n.tr("diagnostic.message.musicAuthorizationRequestFinished"),
      payload: ["authorization_status": statusDiagnosticValue]
    )
    await refreshSubscription()
  }

  func refreshSubscription() async {
    guard status == .authorized else {
      subscription = nil
      subscriptionIssue = nil
      diagnostics?.record(
        .info,
        chain: .musicSubscription,
        event: "subscription_refresh_skipped",
        message: L10n.tr("diagnostic.message.musicSubscriptionSkipUnauthorized"),
        payload: ["authorization_status": statusDiagnosticValue]
      )
      return
    }

    isRefreshingSubscription = true
    lastErrorMessage = nil
    subscriptionIssue = nil
    diagnostics?.record(
      .info,
      chain: .musicSubscription,
      event: "subscription_refresh_start",
      message: L10n.tr("diagnostic.message.musicSubscriptionRefreshStarted")
    )

    do {
      subscription = try await MusicSubscription.current
      diagnostics?.record(
        subscription?.canPlayCatalogContent == true ? .notice : .warning,
        chain: .musicSubscription,
        event: "subscription_refresh_success",
        message: L10n.tr("diagnostic.message.musicSubscriptionRefreshSucceeded"),
        payload: subscriptionDiagnosticPayload
      )
    } catch {
      subscription = nil
      let issue = AppleMusicSubscriptionIssue(error: error)
      subscriptionIssue = issue
      lastErrorMessage = issue.message
      diagnostics?.record(
        .error,
        chain: .musicSubscription,
        event: "subscription_refresh_failed",
        message: L10n.tr("diagnostic.message.musicSubscriptionRefreshFailed"),
        payload: DiagnosticsPayload.merge(
          ["subscription_issue": issue.diagnosticValue],
          DiagnosticsPayload.error(error)
        )
      )
    }

    isRefreshingSubscription = false
  }

  @discardableResult
  func ensureCatalogPlaybackReady() async throws -> MusicSubscription {
    refresh()

    if status == .notDetermined {
      await requestAccess()
    } else if status == .authorized {
      await refreshSubscription()
    }

    switch status {
    case .authorized:
      break
    case .denied:
      recordAccessFailure("authorization_denied")
      throw AppleMusicAccessError.authorizationDenied
    case .restricted:
      recordAccessFailure("authorization_restricted")
      throw AppleMusicAccessError.authorizationRestricted
    case .notDetermined:
      recordAccessFailure("authorization_required")
      throw AppleMusicAccessError.authorizationRequired
    @unknown default:
      recordAccessFailure("authorization_unknown")
      throw AppleMusicAccessError.authorizationRequired
    }

    if let subscriptionIssue {
      switch subscriptionIssue {
      case .privacyAcknowledgementRequired:
        recordAccessFailure("privacy_acknowledgement_required")
        throw AppleMusicAccessError.privacyAcknowledgementRequired
      case .permissionDenied:
        recordAccessFailure("subscription_permission_denied")
        throw AppleMusicAccessError.authorizationDenied
      case .unknown(let message):
        recordAccessFailure("subscription_check_failed", extra: ["message_hash": DiagnosticsRedactor.hash(message)])
        throw AppleMusicAccessError.subscriptionCheckFailed(message)
      }
    }

    guard let subscription else {
      recordAccessFailure("subscription_missing")
      throw AppleMusicAccessError.catalogPlaybackUnavailable
    }

    guard subscription.canPlayCatalogContent else {
      if subscription.canBecomeSubscriber {
        recordAccessFailure("subscription_required")
        throw AppleMusicAccessError.subscriptionRequired
      }
      recordAccessFailure("catalog_playback_unavailable")
      throw AppleMusicAccessError.catalogPlaybackUnavailable
    }

    diagnostics?.record(
      .notice,
      chain: .musicSubscription,
      event: "catalog_playback_ready",
      message: L10n.tr("diagnostic.message.catalogPlaybackReady"),
      payload: subscriptionDiagnosticPayload
    )
    return subscription
  }

  var canPlayCatalogContent: Bool {
    subscription?.canPlayCatalogContent == true
  }

  var canBecomeSubscriber: Bool {
    subscription?.canBecomeSubscriber == true
  }

  var readiness: AppleMusicAccessReadiness {
    if isRequestingAccess {
      return .requestingAuthorization
    }

    switch status {
    case .notDetermined:
      return .notDetermined
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    case .authorized:
      break
    @unknown default:
      return .subscriptionStatusUnknown
    }

    if isRefreshingSubscription {
      return .checkingSubscription
    }

    if let subscriptionIssue {
      switch subscriptionIssue {
      case .privacyAcknowledgementRequired:
        return .privacyAcknowledgementRequired
      case .permissionDenied:
        return .denied
      case .unknown(let message):
        return .subscriptionCheckFailed(message)
      }
    }

    guard let subscription else {
      return .subscriptionStatusUnknown
    }

    if subscription.canPlayCatalogContent {
      return .ready
    }

    if subscription.canBecomeSubscriber {
      return .needsSubscription
    }

    return .catalogPlaybackUnavailable
  }

  var statusText: String {
    switch status {
    case .authorized:
      L10n.tr("appleMusic.status.authorized")
    case .denied:
      L10n.tr("appleMusic.status.denied")
    case .notDetermined:
      L10n.tr("appleMusic.status.notDetermined")
    case .restricted:
      L10n.tr("appleMusic.status.restricted")
    @unknown default:
      L10n.tr("common.unknown")
    }
  }

  var subscriptionText: String {
    switch readiness {
    case .notDetermined, .requestingAuthorization:
      L10n.tr("appleMusic.subscription.needsAuthorization")
    case .denied:
      L10n.tr("appleMusic.subscription.permissionOff")
    case .restricted:
      L10n.tr("appleMusic.subscription.restricted")
    case .checkingSubscription:
      L10n.tr("appleMusic.subscription.checking")
    case .subscriptionStatusUnknown:
      L10n.tr("appleMusic.subscription.waitingRefresh")
    case .ready:
      L10n.tr("appleMusic.subscription.ready")
    case .needsSubscription:
      L10n.tr("appleMusic.subscription.needsSubscription")
    case .catalogPlaybackUnavailable:
      L10n.tr("appleMusic.subscription.catalogUnavailable")
    case .privacyAcknowledgementRequired:
      L10n.tr("appleMusic.subscription.needsPrivacyAcknowledgement")
    case .subscriptionCheckFailed:
      L10n.tr("appleMusic.subscription.checkFailed")
    }
  }

  private func startObservingSubscriptionUpdates() {
    guard subscriptionUpdatesTask == nil else { return }

    subscriptionUpdatesTask = Task { [weak self] in
      for await subscription in MusicSubscription.subscriptionUpdates {
        await MainActor.run {
          self?.subscription = subscription
          self?.subscriptionIssue = nil
          self?.lastErrorMessage = nil
          self?.diagnostics?.record(
            subscription.canPlayCatalogContent ? .notice : .warning,
            chain: .musicSubscription,
            event: "subscription_update",
            message: L10n.tr("diagnostic.message.musicSubscriptionUpdated"),
            payload: [
              "can_play_catalog_content": DiagnosticsPayload.bool(subscription.canPlayCatalogContent),
              "can_become_subscriber": DiagnosticsPayload.bool(subscription.canBecomeSubscriber),
              "has_cloud_library_enabled": DiagnosticsPayload.bool(subscription.hasCloudLibraryEnabled)
            ]
          )
        }
      }
    }
  }

  private var statusDiagnosticValue: String {
    switch status {
    case .authorized:
      "authorized"
    case .denied:
      "denied"
    case .notDetermined:
      "not_determined"
    case .restricted:
      "restricted"
    @unknown default:
      "unknown"
    }
  }

  private var subscriptionDiagnosticPayload: [String: String] {
    guard let subscription else {
      return [
        "has_subscription_snapshot": "false",
        "readiness": readiness.diagnosticValue
      ]
    }

    return [
      "has_subscription_snapshot": "true",
      "readiness": readiness.diagnosticValue,
      "can_play_catalog_content": DiagnosticsPayload.bool(subscription.canPlayCatalogContent),
      "can_become_subscriber": DiagnosticsPayload.bool(subscription.canBecomeSubscriber),
      "has_cloud_library_enabled": DiagnosticsPayload.bool(subscription.hasCloudLibraryEnabled)
    ]
  }

  private func recordAccessFailure(_ reason: String, extra: [String: String] = [:]) {
    diagnostics?.record(
      .warning,
      chain: .musicSubscription,
      event: "catalog_playback_not_ready",
      message: L10n.tr("diagnostic.message.catalogPlaybackNotReady"),
      payload: DiagnosticsPayload.merge(
        [
          "reason": reason,
          "authorization_status": statusDiagnosticValue,
          "readiness": readiness.diagnosticValue
        ],
        subscriptionDiagnosticPayload,
        extra
      )
    )
  }
}

private extension AppleMusicSubscriptionIssue {
  var diagnosticValue: String {
    switch self {
    case .privacyAcknowledgementRequired:
      "privacy_acknowledgement_required"
    case .permissionDenied:
      "permission_denied"
    case .unknown:
      "unknown"
    }
  }
}

private extension AppleMusicAccessReadiness {
  var diagnosticValue: String {
    switch self {
    case .notDetermined:
      "not_determined"
    case .requestingAuthorization:
      "requesting_authorization"
    case .denied:
      "denied"
    case .restricted:
      "restricted"
    case .checkingSubscription:
      "checking_subscription"
    case .subscriptionStatusUnknown:
      "subscription_status_unknown"
    case .ready:
      "ready"
    case .needsSubscription:
      "needs_subscription"
    case .catalogPlaybackUnavailable:
      "catalog_playback_unavailable"
    case .privacyAcknowledgementRequired:
      "privacy_acknowledgement_required"
    case .subscriptionCheckFailed:
      "subscription_check_failed"
    }
  }
}
