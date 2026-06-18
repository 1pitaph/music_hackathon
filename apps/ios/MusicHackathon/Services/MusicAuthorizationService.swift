import MusicKit
import Observation

@MainActor
@Observable
final class MusicAuthorizationService {
  var status: MusicAuthorization.Status = MusicAuthorization.currentStatus
  var subscription: MusicSubscription?
  var isRequestingAccess = false
  var isRefreshingSubscription = false
  var lastErrorMessage: String?

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
      return
    }

    isRefreshingSubscription = true
    lastErrorMessage = nil

    do {
      subscription = try await MusicSubscription.current
    } catch {
      subscription = nil
      lastErrorMessage = error.localizedDescription
    }

    isRefreshingSubscription = false
  }

  var canPlayCatalogContent: Bool {
    subscription?.canPlayCatalogContent == true
  }

  var canBecomeSubscriber: Bool {
    subscription?.canBecomeSubscriber == true
  }

  var statusText: String {
    switch status {
    case .authorized:
      "Authorized"
    case .denied:
      "Denied"
    case .notDetermined:
      "Not Determined"
    case .restricted:
      "Restricted"
    @unknown default:
      "Unknown"
    }
  }

  var subscriptionText: String {
    guard status == .authorized else { return "Authorize first" }

    if isRefreshingSubscription {
      return "Checking"
    }

    if canPlayCatalogContent {
      return "Catalog playback ready"
    }

    if canBecomeSubscriber {
      return "Subscription available"
    }

    return "Catalog playback unavailable"
  }
}
