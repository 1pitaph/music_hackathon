import MusicKit
import SwiftUI
import UIKit

struct SettingsView: View {
  @Environment(MusicAuthorizationService.self) private var musicAuthorization
  @Environment(AppleMusicLibraryStore.self) private var appleMusicLibrary
  @Environment(RadioStationController.self) private var radioStation
  @Environment(DiagnosticsStore.self) private var diagnostics
  @Environment(ImageAssetStore.self) private var imageAssetStore
  @Environment(\.openURL) private var openURL

  @AppStorage(RadioHostVoiceSettings.speakerIDKey) private var selectedHostSpeakerID = ""
  @AppStorage(AppLanguage.storageKey) private var selectedLanguageRawValue = AppLanguage.system.rawValue
  @AppStorage(RadioSpeechLanguage.storageKey) private var selectedSpeechLanguageRawValue = RadioSpeechLanguage.chinese.rawValue

  @State private var autoPlayNextStation = false
  @State private var backgroundPlay = false
  @State private var publicStation = false
  @State private var dataCollection = true
  @State private var activeAppleMusicAlert: AppleMusicAlert?
  @State private var isShowingLanguageRestartAlert = false
  @State private var isShowingMusicSubscriptionOffer = false
  @State private var didPresentInitialAppleMusicIssue = false

  var body: some View {
    List {
      languageSection
      appleMusicSection
      playbackSection
      backendStationSection
      diagnosticsSection
      speechVoiceSection
      dataSourceSection
      privacySection
      artworkSection
      localMemorySection
      aboutSection
    }
    .listStyle(.insetGrouped)
    .alert(item: $activeAppleMusicAlert, content: appleMusicAlert)
    .alert(L10n.tr("settings.language.restartTitle"), isPresented: $isShowingLanguageRestartAlert) {
      Button(L10n.tr("common.ok"), role: .cancel) {}
    } message: {
      Text(L10n.tr("settings.language.restartMessage"))
    }
    .musicSubscriptionOffer(
      isPresented: $isShowingMusicSubscriptionOffer,
      options: musicSubscriptionOfferOptions
    ) { error in
      if let error {
        activeAppleMusicAlert = .subscriptionOfferFailed(error.localizedDescription)
      }
    }
    .onChange(of: isShowingMusicSubscriptionOffer) { _, isPresented in
      guard !isPresented else { return }
      Task {
        await refreshAppleMusicAccess(presentsFollowUp: false)
      }
    }
    .task {
      await refreshAppleMusicAccess(presentsFollowUp: true)
      await radioStation.refreshMemoryStatus()
      await loadSpeechVoicesIfNeeded()
    }
  }

  private var languageSection: some View {
    Section {
      Picker(L10n.tr("settings.language.preference"), selection: appLanguageBinding) {
        ForEach(AppLanguage.allCases) { language in
          Text(language.localizedTitle).tag(language.rawValue)
        }
      }

      Text(L10n.tr("settings.language.footer"))
        .font(.footnote)
        .foregroundStyle(.secondary)
    } header: {
      Text(L10n.tr("settings.language.section"))
    }
  }

  private var appLanguageBinding: Binding<String> {
    Binding {
      selectedLanguageRawValue
    } set: { newValue in
      let language = AppLanguage(rawValue: newValue) ?? .system
      selectedLanguageRawValue = language.rawValue
      AppLanguage.store(language)
      isShowingLanguageRestartAlert = true
    }
  }

  private var appleMusicSection: some View {
    Section(L10n.tr("settings.appleMusic.section")) {
      LabeledContent(L10n.tr("settings.appleMusic.authorizationStatus"), value: musicAuthorization.statusText)
      LabeledContent(L10n.tr("settings.appleMusic.subscriptionStatus"), value: musicAuthorization.subscriptionText)
      if let subscription = musicAuthorization.subscription {
        LabeledContent(L10n.tr("settings.appleMusic.cloudLibrary"), value: subscription.hasCloudLibraryEnabled ? L10n.tr("common.on") : L10n.tr("common.off"))
      }

      VStack(alignment: .leading, spacing: 8) {
        Label(appleMusicReadinessTitle, systemImage: appleMusicReadinessIcon)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(appleMusicReadinessTint)

        Text(appleMusicReadinessMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 4)

      Button {
        handleAppleMusicPrimaryAction()
      } label: {
        Label(appleMusicPrimaryActionTitle, systemImage: appleMusicPrimaryActionIcon)
      }
      .disabled(isAppleMusicActionBusy)

      Button {
        Task {
          await refreshAppleMusicAccess(presentsFollowUp: true)
        }
      } label: {
        Label(L10n.tr("appleMusic.refreshPlaybackAccess"), systemImage: "arrow.triangle.2.circlepath")
      }
      .disabled(isAppleMusicActionBusy)

      if let message = musicAuthorization.lastErrorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var playbackSection: some View {
    Section(L10n.tr("settings.playback.section")) {
      Toggle(L10n.tr("settings.playback.autoPlayNextStation"), isOn: $autoPlayNextStation)
      Toggle(L10n.tr("settings.playback.backgroundPlay"), isOn: $backgroundPlay)
      LabeledContent(L10n.tr("settings.playback.audioQuality"), value: L10n.tr("common.automatic"))
    }
  }

  private var backendStationSection: some View {
    Section(L10n.tr("settings.backend.section")) {
      LabeledContent(L10n.tr("settings.backend.currentStation"), value: radioStation.stationTitle)
      LabeledContent(L10n.tr("settings.backend.queueSongs"), value: "\(radioStation.stationTracks.count)")
      LabeledContent(L10n.tr("settings.backend.stationStatus"), value: backendStationStatusText)

      Button {
        Task {
          await radioStation.refreshStation()
        }
      } label: {
        Label(
          backendStationRefreshTitle,
          systemImage: "dot.radiowaves.left.and.right"
        )
      }
      .disabled(radioStation.isLoadingStation || radioStation.isExtendingStation)

      if let message = radioStation.errorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if let message = radioStation.extensionErrorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var diagnosticsSection: some View {
    Section(L10n.tr("settings.diagnostics.section")) {
      NavigationLink {
        DiagnosticsView()
      } label: {
        HStack(spacing: 12) {
          Label(L10n.tr("diagnostics.title"), systemImage: "stethoscope")
            .frame(maxWidth: .infinity, alignment: .leading)

          VStack(alignment: .trailing, spacing: 2) {
            Text(L10n.count("count.issues", diagnostics.errorCount))
              .font(.caption)
              .foregroundStyle(diagnostics.errorCount > 0 ? .orange : .secondary)
            Text(diagnostics.lastEventText)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
      }

      Text(L10n.tr("settings.diagnostics.description"))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var backendStationStatusText: String {
    if radioStation.isLoadingStation {
      return L10n.tr("playback.loading")
    }

    if radioStation.isExtendingStation {
      return L10n.tr("radio.extendingNextSegment")
    }

    return L10n.tr("common.standby")
  }

  private var backendStationRefreshTitle: String {
    if radioStation.isLoadingStation {
      return L10n.tr("playback.loading")
    }

    if radioStation.isExtendingStation {
      return L10n.tr("radio.extendingNextSegment")
    }

    return L10n.tr("settings.backend.refresh")
  }

  private var speechVoiceSection: some View {
    Section(L10n.tr("settings.speechVoice.section")) {
      Picker(L10n.tr("settings.speechLanguage.preference"), selection: speechLanguageBinding) {
        ForEach(RadioSpeechLanguage.allCases) { language in
          Text(language.localizedTitle).tag(language.rawValue)
        }
      }

      Text(L10n.tr("settings.speechLanguage.footer"))
        .font(.footnote)
        .foregroundStyle(.secondary)

      LabeledContent(L10n.tr("settings.speechVoice.currentVoice"), value: selectedHostVoiceName)

      if let catalog = radioStation.speechVoiceCatalog, !catalog.voices.isEmpty {
        Picker(L10n.tr("settings.speechVoice.voice"), selection: $selectedHostSpeakerID) {
          ForEach(catalog.voices) { voice in
            Text(voice.name).tag(voice.id)
          }

          if !selectedHostSpeakerID.isEmpty,
             catalog.voice(for: selectedHostSpeakerID) == nil {
            Text(selectedHostSpeakerID).tag(selectedHostSpeakerID)
          }
        }

        if let voice = selectedSpeechVoice {
          LabeledContent(L10n.tr("settings.speechVoice.style"), value: voice.style.isEmpty ? L10n.tr("common.default") : voice.style)
          LabeledContent(L10n.tr("settings.speechVoice.model"), value: voice.model)
        }
      } else if radioStation.isLoadingSpeechVoices {
        ProgressView(L10n.tr("settings.speechVoice.loading"))
      }

      Button {
        Task {
          await loadSpeechVoices()
        }
      } label: {
        Label(
          radioStation.isLoadingSpeechVoices ? L10n.tr("common.refreshing") : L10n.tr("settings.speechVoice.refresh"),
          systemImage: "arrow.triangle.2.circlepath"
        )
      }
      .disabled(radioStation.isLoadingSpeechVoices)

      if let message = radioStation.speechVoicesErrorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var dataSourceSection: some View {
    Section(L10n.tr("settings.dataSource.section")) {
      LabeledContent(L10n.tr("settings.dataSource.appPlaybackHistory"), value: L10n.count("count.entries", radioStation.memoryEventCount))
      LabeledContent(L10n.tr("settings.dataSource.importedPlaylists"), value: L10n.count("count.playlists", 3))
      LabeledContent(L10n.tr("settings.dataSource.manualEntries"), value: L10n.count("count.entries", 12))

      Text(L10n.tr("settings.dataSource.description"))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var privacySection: some View {
    Section(L10n.tr("settings.privacy.section")) {
      Toggle(L10n.tr("settings.privacy.publicStation"), isOn: $publicStation)
      Toggle(L10n.tr("settings.privacy.dataCollection"), isOn: $dataCollection)

      Text(L10n.tr("settings.privacy.description"))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var localMemorySection: some View {
    Section(L10n.tr("settings.localMemory.section")) {
      LabeledContent(L10n.tr("settings.localMemory.recentEvents"), value: "\(radioStation.memoryEventCount)")

      Text(radioStation.memorySummaryText)
        .font(.footnote)
        .foregroundStyle(.secondary)

      Button(role: .destructive) {
        Task {
          await radioStation.clearMemory()
        }
      } label: {
        Label(L10n.tr("settings.localMemory.clear"), systemImage: "trash")
      }
    }
  }

  private var artworkSection: some View {
    Section(L10n.tr("settings.artwork.section")) {
      Button(role: .destructive) {
        imageAssetStore.clearAllCustomImages()
      } label: {
        Label(L10n.tr("settings.artwork.clearLocalAvatar"), systemImage: "trash")
      }

      Text(L10n.tr("settings.artwork.description"))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var aboutSection: some View {
    Section(L10n.tr("settings.about.section")) {
      LabeledContent(L10n.tr("settings.about.version"), value: "Music Archive v1.0.0")
      LabeledContent(L10n.tr("settings.about.privacyPolicy"), value: L10n.tr("common.comingSoon"))
      LabeledContent(L10n.tr("settings.about.terms"), value: L10n.tr("common.comingSoon"))
    }
  }

  private var selectedSpeechVoice: RadioSpeechVoice? {
    guard let catalog = radioStation.speechVoiceCatalog else { return nil }
    if let voice = catalog.voice(for: selectedHostSpeakerID) {
      return voice
    }
    guard selectedHostSpeakerID.isEmpty else { return nil }
    return catalog.voice(for: defaultHostSpeakerID(for: selectedSpeechLanguage, in: catalog))
      ?? catalog.voice(for: catalog.defaultSpeaker)
  }

  private var speechLanguageBinding: Binding<String> {
    Binding {
      selectedSpeechLanguageRawValue
    } set: { newValue in
      let language = RadioSpeechLanguage(rawValue: newValue) ?? .chinese
      selectedSpeechLanguageRawValue = language.rawValue
      syncSelectedHostSpeaker(for: language)
    }
  }

  private var selectedSpeechLanguage: RadioSpeechLanguage {
    RadioSpeechLanguage(rawValue: selectedSpeechLanguageRawValue) ?? .chinese
  }

  private var selectedHostVoiceName: String {
    if let voice = selectedSpeechVoice {
      return voice.name
    }
    if !selectedHostSpeakerID.isEmpty {
      return selectedHostSpeakerID
    }
    return L10n.tr("settings.speechVoice.backendDefault")
  }

  private var isAppleMusicActionBusy: Bool {
    musicAuthorization.isRequestingAccess || musicAuthorization.isRefreshingSubscription
  }

  private var musicSubscriptionOfferOptions: MusicSubscriptionOffer.Options {
    MusicSubscriptionOffer.Options(messageIdentifier: .playMusic)
  }

  private var appleMusicReadinessTitle: String {
    return switch musicAuthorization.readiness {
    case .notDetermined:
      L10n.tr("appleMusic.readiness.notDetermined.title")
    case .requestingAuthorization:
      L10n.tr("appleMusic.readiness.requestingAuthorization.title")
    case .denied:
      L10n.tr("appleMusic.readiness.denied.title")
    case .restricted:
      L10n.tr("appleMusic.readiness.restricted.title")
    case .checkingSubscription:
      L10n.tr("appleMusic.readiness.checkingSubscription.title")
    case .subscriptionStatusUnknown:
      L10n.tr("appleMusic.readiness.subscriptionStatusUnknown.title")
    case .ready:
      L10n.tr("appleMusic.readiness.ready.title")
    case .needsSubscription:
      L10n.tr("appleMusic.readiness.needsSubscription.title")
    case .catalogPlaybackUnavailable:
      L10n.tr("appleMusic.readiness.catalogPlaybackUnavailable.title")
    case .privacyAcknowledgementRequired:
      L10n.tr("appleMusic.readiness.privacyAcknowledgementRequired.title")
    case .subscriptionCheckFailed:
      L10n.tr("appleMusic.readiness.subscriptionCheckFailed.title")
    }
  }

  private var appleMusicReadinessMessage: String {
    switch musicAuthorization.readiness {
    case .notDetermined:
      L10n.tr("appleMusic.readiness.notDetermined.message")
    case .requestingAuthorization:
      L10n.tr("appleMusic.readiness.requestingAuthorization.message")
    case .denied:
      L10n.tr("appleMusic.readiness.denied.message")
    case .restricted:
      L10n.tr("appleMusic.readiness.restricted.message")
    case .checkingSubscription:
      L10n.tr("appleMusic.readiness.checkingSubscription.message")
    case .subscriptionStatusUnknown:
      L10n.tr("appleMusic.readiness.subscriptionStatusUnknown.message")
    case .ready:
      L10n.tr("appleMusic.readiness.ready.message")
    case .needsSubscription:
      L10n.tr("appleMusic.readiness.needsSubscription.message")
    case .catalogPlaybackUnavailable:
      L10n.tr("appleMusic.readiness.catalogPlaybackUnavailable.message")
    case .privacyAcknowledgementRequired:
      L10n.tr("appleMusic.readiness.privacyAcknowledgementRequired.message")
    case .subscriptionCheckFailed(let message):
      message
    }
  }

  private var appleMusicReadinessIcon: String {
    switch musicAuthorization.readiness {
    case .ready:
      "checkmark.seal.fill"
    case .checkingSubscription, .requestingAuthorization:
      "hourglass"
    case .denied, .restricted, .catalogPlaybackUnavailable, .privacyAcknowledgementRequired, .subscriptionCheckFailed:
      "exclamationmark.triangle.fill"
    case .needsSubscription:
      "music.note"
    case .notDetermined, .subscriptionStatusUnknown:
      "person.badge.key"
    }
  }

  private var appleMusicReadinessTint: Color {
    switch musicAuthorization.readiness {
    case .ready:
      .green
    case .needsSubscription, .notDetermined, .subscriptionStatusUnknown:
      .cyan
    case .checkingSubscription, .requestingAuthorization:
      .secondary
    case .denied, .restricted, .catalogPlaybackUnavailable, .privacyAcknowledgementRequired, .subscriptionCheckFailed:
      .orange
    }
  }

  private var appleMusicPrimaryActionTitle: String {
    if isAppleMusicActionBusy {
      return L10n.tr("common.processing")
    }

    return switch musicAuthorization.readiness {
    case .notDetermined:
      L10n.tr("appleMusic.connect.title")
    case .requestingAuthorization, .checkingSubscription:
      L10n.tr("common.processing")
    case .denied:
      L10n.tr("common.openSystemSettings")
    case .restricted:
      L10n.tr("appleMusic.viewRestrictions")
    case .subscriptionStatusUnknown, .ready, .subscriptionCheckFailed:
      L10n.tr("appleMusic.refreshPlaybackAccess")
    case .needsSubscription:
      L10n.tr("appleMusic.viewSubscription")
    case .catalogPlaybackUnavailable, .privacyAcknowledgementRequired:
      L10n.tr("appleMusic.openApp")
    }
  }

  private var appleMusicPrimaryActionIcon: String {
    switch musicAuthorization.readiness {
    case .denied:
      "gearshape"
    case .needsSubscription:
      "music.note"
    case .catalogPlaybackUnavailable, .privacyAcknowledgementRequired:
      "music.quarternote.3"
    case .restricted, .subscriptionCheckFailed:
      "exclamationmark.circle"
    case .subscriptionStatusUnknown, .ready, .checkingSubscription:
      "arrow.triangle.2.circlepath"
    case .notDetermined, .requestingAuthorization:
      "person.badge.key"
    }
  }

  private func handleAppleMusicPrimaryAction() {
    switch musicAuthorization.readiness {
    case .notDetermined:
      activeAppleMusicAlert = .connectIntro
    case .denied:
      activeAppleMusicAlert = .denied
    case .restricted:
      activeAppleMusicAlert = .restricted
    case .needsSubscription:
      activeAppleMusicAlert = .subscriptionRequired
    case .catalogPlaybackUnavailable:
      activeAppleMusicAlert = .catalogPlaybackUnavailable
    case .privacyAcknowledgementRequired:
      activeAppleMusicAlert = .privacyAcknowledgementRequired
    case .requestingAuthorization, .checkingSubscription:
      break
    case .subscriptionStatusUnknown, .ready, .subscriptionCheckFailed:
      Task {
        await refreshAppleMusicAccess(presentsFollowUp: true)
      }
    }
  }

  private func refreshAppleMusicAccess(presentsFollowUp: Bool) async {
    await musicAuthorization.refreshAccessState()
    await appleMusicLibrary.refresh(authorizationStatus: musicAuthorization.status)

    if presentsFollowUp {
      presentAppleMusicFollowUp(force: false)
    }
  }

  private func requestAppleMusicAccess() async {
    await musicAuthorization.requestAccess()
    await appleMusicLibrary.refresh(authorizationStatus: musicAuthorization.status)
    presentAppleMusicFollowUp(force: true)
  }

  private func presentAppleMusicFollowUp(force: Bool) {
    guard force || !didPresentInitialAppleMusicIssue else { return }

    let nextAlert: AppleMusicAlert?
    switch musicAuthorization.readiness {
    case .denied:
      nextAlert = .denied
    case .restricted:
      nextAlert = .restricted
    case .needsSubscription:
      nextAlert = .subscriptionRequired
    case .catalogPlaybackUnavailable:
      nextAlert = .catalogPlaybackUnavailable
    case .privacyAcknowledgementRequired:
      nextAlert = .privacyAcknowledgementRequired
    case .subscriptionCheckFailed(let message):
      nextAlert = .subscriptionCheckFailed(message)
    case .notDetermined, .requestingAuthorization, .checkingSubscription, .subscriptionStatusUnknown, .ready:
      nextAlert = nil
    }

    if let nextAlert {
      activeAppleMusicAlert = nextAlert
      didPresentInitialAppleMusicIssue = true
    }
  }

  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    openURL(url)
  }

  private func openAppleMusicApp() {
    guard let url = URL(string: "music://") else { return }
    openURL(url)
  }

  private func appleMusicAlert(_ alert: AppleMusicAlert) -> Alert {
    switch alert {
    case .connectIntro:
      return Alert(
        title: Text(L10n.tr("appleMusic.connect.title")),
        message: Text(L10n.tr("appleMusic.alert.connect.message")),
        primaryButton: .default(Text(L10n.tr("common.continue"))) {
          Task {
            await requestAppleMusicAccess()
          }
        },
        secondaryButton: .cancel(Text(L10n.tr("common.later")))
      )
    case .denied:
      return Alert(
        title: Text(L10n.tr("appleMusic.alert.denied.title")),
        message: Text(L10n.tr("appleMusic.alert.denied.message")),
        primaryButton: .default(Text(L10n.tr("common.openSettings"))) {
          openAppSettings()
        },
        secondaryButton: .cancel(Text(L10n.tr("common.cancel")))
      )
    case .restricted:
      return Alert(
        title: Text(L10n.tr("appleMusic.readiness.restricted.title")),
        message: Text(L10n.tr("appleMusic.alert.restricted.message")),
        dismissButton: .default(Text(L10n.tr("common.ok")))
      )
    case .privacyAcknowledgementRequired:
      return Alert(
        title: Text(L10n.tr("appleMusic.readiness.privacyAcknowledgementRequired.title")),
        message: Text(L10n.tr("appleMusic.alert.privacyAcknowledgementRequired.message")),
        primaryButton: .default(Text(L10n.tr("appleMusic.openApp"))) {
          openAppleMusicApp()
        },
        secondaryButton: .cancel(Text(L10n.tr("common.later")))
      )
    case .subscriptionRequired:
      return Alert(
        title: Text(L10n.tr("appleMusic.readiness.needsSubscription.title")),
        message: Text(L10n.tr("appleMusic.alert.subscriptionRequired.message")),
        primaryButton: .default(Text(L10n.tr("appleMusic.viewSubscriptionPlans"))) {
          isShowingMusicSubscriptionOffer = true
        },
        secondaryButton: .cancel(Text(L10n.tr("common.later")))
      )
    case .catalogPlaybackUnavailable:
      return Alert(
        title: Text(L10n.tr("appleMusic.readiness.catalogPlaybackUnavailable.title")),
        message: Text(L10n.tr("appleMusic.alert.catalogPlaybackUnavailable.message")),
        primaryButton: .default(Text(L10n.tr("appleMusic.openApp"))) {
          openAppleMusicApp()
        },
        secondaryButton: .default(Text(L10n.tr("common.retry"))) {
          Task {
            await refreshAppleMusicAccess(presentsFollowUp: false)
          }
        }
      )
    case .subscriptionCheckFailed(let message):
      return Alert(
        title: Text(L10n.tr("appleMusic.alert.subscriptionCheckFailed.title")),
        message: Text(message),
        primaryButton: .default(Text(L10n.tr("common.retry"))) {
          Task {
            await refreshAppleMusicAccess(presentsFollowUp: true)
          }
        },
        secondaryButton: .cancel(Text(L10n.tr("common.cancel")))
      )
    case .subscriptionOfferFailed(let message):
      return Alert(
        title: Text(L10n.tr("appleMusic.alert.subscriptionOfferFailed.title")),
        message: Text(message),
        dismissButton: .default(Text(L10n.tr("common.ok")))
      )
    }
  }

  private func loadSpeechVoicesIfNeeded() async {
    guard radioStation.speechVoiceCatalog == nil else { return }
    await loadSpeechVoices()
  }

  private func loadSpeechVoices() async {
    await radioStation.refreshSpeechVoices()
    syncSelectedHostSpeaker()
  }

  private func syncSelectedHostSpeaker(for language: RadioSpeechLanguage? = nil) {
    let language = language ?? selectedSpeechLanguage
    guard let catalog = radioStation.speechVoiceCatalog, !catalog.voices.isEmpty else {
      selectedHostSpeakerID = language.resolvedHostSpeakerID(preferredSpeakerID: selectedHostSpeakerID)
      return
    }

    let defaultSpeakerID = defaultHostSpeakerID(for: language, in: catalog)
    if selectedHostSpeakerID.isEmpty || language.isKnownLanguageMismatch(speakerID: selectedHostSpeakerID) {
      selectedHostSpeakerID = defaultSpeakerID
    } else if catalog.voice(for: selectedHostSpeakerID) == nil {
      selectedHostSpeakerID = defaultSpeakerID
    }
  }

  private func defaultHostSpeakerID(
    for language: RadioSpeechLanguage,
    in catalog: RadioSpeechVoiceCatalog
  ) -> String {
    if let voice = catalog.voice(for: language.defaultHostSpeakerID),
       language.matchesVoiceLanguage(voice.language) {
      return voice.id
    }

    if let defaultVoice = catalog.voice(for: catalog.defaultSpeaker),
       language.matchesVoiceLanguage(defaultVoice.language) {
      return defaultVoice.id
    }

    if !language.isKnownLanguageMismatch(speakerID: catalog.defaultSpeaker) {
      return catalog.defaultSpeaker
    }

    return language.defaultHostSpeakerID
  }
}

private enum AppleMusicAlert: Identifiable {
  case connectIntro
  case denied
  case restricted
  case privacyAcknowledgementRequired
  case subscriptionRequired
  case catalogPlaybackUnavailable
  case subscriptionCheckFailed(String)
  case subscriptionOfferFailed(String)

  var id: String {
    switch self {
    case .connectIntro:
      "connectIntro"
    case .denied:
      "denied"
    case .restricted:
      "restricted"
    case .privacyAcknowledgementRequired:
      "privacyAcknowledgementRequired"
    case .subscriptionRequired:
      "subscriptionRequired"
    case .catalogPlaybackUnavailable:
      "catalogPlaybackUnavailable"
    case .subscriptionCheckFailed(let message):
      "subscriptionCheckFailed-\(message)"
    case .subscriptionOfferFailed(let message):
      "subscriptionOfferFailed-\(message)"
    }
  }
}

#Preview {
  let playbackController = PlaybackController()
  NavigationStack {
    SettingsView()
      .navigationTitle(L10n.tr("tab.mine"))
  }
  .environment(playbackController)
  .environment(RadioStationController(playbackController: playbackController))
  .environment(MusicAuthorizationService())
  .environment(AppleMusicLibraryStore())
  .environment(DiagnosticsStore.preview())
  .environment(ImageAssetStore())
  .environment(ArtworkAnalysisStore())
}
