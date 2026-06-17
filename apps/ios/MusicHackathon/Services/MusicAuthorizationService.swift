import MusicKit
import Observation

@MainActor
@Observable
final class MusicAuthorizationService {
  var status: MusicAuthorization.Status = MusicAuthorization.currentStatus
  var isRequestingAccess = false

  func refresh() {
    status = MusicAuthorization.currentStatus
  }

  func requestAccess() async {
    guard !isRequestingAccess else { return }

    isRequestingAccess = true
    status = await MusicAuthorization.request()
    isRequestingAccess = false
  }
}
