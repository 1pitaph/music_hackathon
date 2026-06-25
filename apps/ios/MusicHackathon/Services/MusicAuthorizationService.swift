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
      "需要先在 Apple Music 中确认最新隐私政策或服务条款。"
    case .permissionDenied:
      "Apple Music 无法读取当前账号的订阅状态，请检查媒体与 Apple Music 权限。"
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
      "Airset 的 Apple Music 权限已关闭。"
    case .authorizationRestricted:
      "此设备的 Apple Music 访问受限制。"
    case .authorizationRequired:
      "需要连接 Apple Music 才能播放这首歌。"
    case .subscriptionRequired:
      "需要有效的 Apple Music 订阅才能播放完整歌曲。"
    case .catalogPlaybackUnavailable:
      "当前账号或地区暂不支持 Apple Music 目录播放。"
    case .privacyAcknowledgementRequired:
      "请先打开 Apple Music 并确认最新隐私政策或服务条款。"
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

  @ObservationIgnored private var subscriptionUpdatesTask: Task<Void, Never>?

  init() {
    startObservingSubscriptionUpdates()
  }

  deinit {
    subscriptionUpdatesTask?.cancel()
  }

  func refresh() {
    status = MusicAuthorization.currentStatus
  }

  func refreshAccessState() async {
    refresh()
    await refreshSubscription()
  }

  func requestAccess() async {
    guard !isRequestingAccess else { return }

    isRequestingAccess = true
    status = await MusicAuthorization.request()
    isRequestingAccess = false
    await refreshSubscription()
  }

  func refreshSubscription() async {
    guard status == .authorized else {
      subscription = nil
      subscriptionIssue = nil
      return
    }

    isRefreshingSubscription = true
    lastErrorMessage = nil
    subscriptionIssue = nil

    do {
      subscription = try await MusicSubscription.current
    } catch {
      subscription = nil
      let issue = AppleMusicSubscriptionIssue(error: error)
      subscriptionIssue = issue
      lastErrorMessage = issue.message
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
      throw AppleMusicAccessError.authorizationDenied
    case .restricted:
      throw AppleMusicAccessError.authorizationRestricted
    case .notDetermined:
      throw AppleMusicAccessError.authorizationRequired
    @unknown default:
      throw AppleMusicAccessError.authorizationRequired
    }

    if let subscriptionIssue {
      switch subscriptionIssue {
      case .privacyAcknowledgementRequired:
        throw AppleMusicAccessError.privacyAcknowledgementRequired
      case .permissionDenied:
        throw AppleMusicAccessError.authorizationDenied
      case .unknown(let message):
        throw AppleMusicAccessError.subscriptionCheckFailed(message)
      }
    }

    guard let subscription else {
      throw AppleMusicAccessError.catalogPlaybackUnavailable
    }

    guard subscription.canPlayCatalogContent else {
      if subscription.canBecomeSubscriber {
        throw AppleMusicAccessError.subscriptionRequired
      }
      throw AppleMusicAccessError.catalogPlaybackUnavailable
    }

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
      "已授权"
    case .denied:
      "已拒绝"
    case .notDetermined:
      "未决定"
    case .restricted:
      "受限制"
    @unknown default:
      "未知"
    }
  }

  var subscriptionText: String {
    switch readiness {
    case .notDetermined, .requestingAuthorization:
      "需要授权"
    case .denied:
      "系统权限已关闭"
    case .restricted:
      "设备限制"
    case .checkingSubscription:
      "正在检查"
    case .subscriptionStatusUnknown:
      "等待刷新"
    case .ready:
      "可播放完整歌曲"
    case .needsSubscription:
      "需要 Apple Music 订阅"
    case .catalogPlaybackUnavailable:
      "目录播放不可用"
    case .privacyAcknowledgementRequired:
      "需要确认隐私政策"
    case .subscriptionCheckFailed:
      "检查失败"
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
        }
      }
    }
  }
}
