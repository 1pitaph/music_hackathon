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

  @State private var autoPlayNextStation = false
  @State private var backgroundPlay = false
  @State private var publicStation = false
  @State private var dataCollection = true
  @State private var activeAppleMusicAlert: AppleMusicAlert?
  @State private var isShowingMusicSubscriptionOffer = false
  @State private var didPresentInitialAppleMusicIssue = false

  var body: some View {
    List {
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

  private var appleMusicSection: some View {
    Section("Apple Music 授权") {
      LabeledContent("授权状态", value: musicAuthorization.statusText)
      LabeledContent("订阅状态", value: musicAuthorization.subscriptionText)
      if let subscription = musicAuthorization.subscription {
        LabeledContent("同步资料库", value: subscription.hasCloudLibraryEnabled ? "已开启" : "未开启")
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
        Label("刷新播放权限", systemImage: "arrow.triangle.2.circlepath")
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
    Section("播放") {
      Toggle("自动播放下一个电台", isOn: $autoPlayNextStation)
      Toggle("后台播放", isOn: $backgroundPlay)
      LabeledContent("音质", value: "自动")
    }
  }

  private var backendStationSection: some View {
    Section("后端电台") {
      LabeledContent("当前电台", value: radioStation.stationTitle)
      LabeledContent("队列歌曲", value: "\(radioStation.stationTracks.count)")
      LabeledContent("电台状态", value: backendStationStatusText)

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
    Section("诊断") {
      NavigationLink {
        DiagnosticsView()
      } label: {
        HStack(spacing: 12) {
          Label("日志与诊断", systemImage: "stethoscope")
            .frame(maxWidth: .infinity, alignment: .leading)

          VStack(alignment: .trailing, spacing: 2) {
            Text("\(diagnostics.errorCount) 个问题")
              .font(.caption)
              .foregroundStyle(diagnostics.errorCount > 0 ? .orange : .secondary)
            Text(diagnostics.lastEventText)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
      }

      Text("保存播放、Apple Music、后端电台和本地档案链路的短期诊断日志，可筛选、清空或导出。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var backendStationStatusText: String {
    if radioStation.isLoadingStation {
      return "正在加载"
    }

    if radioStation.isExtendingStation {
      return "正在丰富下一段"
    }

    return "待命"
  }

  private var backendStationRefreshTitle: String {
    if radioStation.isLoadingStation {
      return "加载中"
    }

    if radioStation.isExtendingStation {
      return "正在丰富下一段"
    }

    return "刷新后端电台"
  }

  private var speechVoiceSection: some View {
    Section("主持人声音") {
      LabeledContent("当前声音", value: selectedHostVoiceName)

      if let catalog = radioStation.speechVoiceCatalog, !catalog.voices.isEmpty {
        Picker("声音", selection: $selectedHostSpeakerID) {
          ForEach(catalog.voices) { voice in
            Text(voice.name).tag(voice.id)
          }

          if !selectedHostSpeakerID.isEmpty,
             catalog.voice(for: selectedHostSpeakerID) == nil {
            Text(selectedHostSpeakerID).tag(selectedHostSpeakerID)
          }
        }

        if let voice = selectedSpeechVoice {
          LabeledContent("风格", value: voice.style.isEmpty ? "默认" : voice.style)
          LabeledContent("模型", value: voice.model)
        }
      } else if radioStation.isLoadingSpeechVoices {
        ProgressView("加载可用声音")
      }

      Button {
        Task {
          await loadSpeechVoices()
        }
      } label: {
        Label(
          radioStation.isLoadingSpeechVoices ? "刷新中" : "刷新可用声音",
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
    Section("数据来源") {
      LabeledContent("本 App 播放记录", value: "\(radioStation.memoryEventCount) 条")
      LabeledContent("导入播放列表", value: "3 个")
      LabeledContent("手动补充", value: "12 条")

      Text("MVP 只使用本 App 内播放事件、用户主动导入和手动补充，不读取完整 Apple Music 历史。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var privacySection: some View {
    Section("隐私") {
      Toggle("公开我的电台", isOn: $publicStation)
      Toggle("数据收集", isOn: $dataCollection)

      Text("声音档案默认私密。关闭数据收集后，新播放事件不会用于生成个人档案摘要。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var localMemorySection: some View {
    Section("本地声音档案") {
      LabeledContent("最近事件", value: "\(radioStation.memoryEventCount)")

      Text(radioStation.memorySummaryText)
        .font(.footnote)
        .foregroundStyle(.secondary)

      Button(role: .destructive) {
        Task {
          await radioStation.clearMemory()
        }
      } label: {
        Label("清空本地档案", systemImage: "trash")
      }
    }
  }

  private var artworkSection: some View {
    Section("图片与封面") {
      Button(role: .destructive) {
        imageAssetStore.clearAllCustomImages()
      } label: {
        Label("清除本地头像", systemImage: "trash")
      }

      Text("只会删除本机保存的用户头像；歌曲、歌单和电台封面始终使用 Apple Music artwork。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var aboutSection: some View {
    Section("关于") {
      LabeledContent("版本", value: "Music Archive v1.0.0")
      LabeledContent("隐私政策", value: "准备中")
      LabeledContent("用户协议", value: "准备中")
    }
  }

  private var selectedSpeechVoice: RadioSpeechVoice? {
    guard let catalog = radioStation.speechVoiceCatalog else { return nil }
    if let voice = catalog.voice(for: selectedHostSpeakerID) {
      return voice
    }
    return catalog.voice(for: catalog.defaultSpeaker)
  }

  private var selectedHostVoiceName: String {
    if let voice = selectedSpeechVoice {
      return voice.name
    }
    if !selectedHostSpeakerID.isEmpty {
      return selectedHostSpeakerID
    }
    return "后端默认"
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
      "需要连接 Apple Music"
    case .requestingAuthorization:
      "正在请求授权"
    case .denied:
      "Apple Music 权限已关闭"
    case .restricted:
      "Apple Music 访问受限制"
    case .checkingSubscription:
      "正在检查播放资格"
    case .subscriptionStatusUnknown:
      "需要刷新播放资格"
    case .ready:
      "Apple Music 已就绪"
    case .needsSubscription:
      "需要 Apple Music 订阅"
    case .catalogPlaybackUnavailable:
      "目录播放暂不可用"
    case .privacyAcknowledgementRequired:
      "需要确认 Apple Music 隐私政策"
    case .subscriptionCheckFailed:
      "订阅状态检查失败"
    }
  }

  private var appleMusicReadinessMessage: String {
    switch musicAuthorization.readiness {
    case .notDetermined:
      "连接后，Airset 可以播放完整歌曲，并读取你授权的歌单和歌曲。"
    case .requestingAuthorization:
      "请在系统弹窗中允许 Airset 访问媒体与 Apple Music。"
    case .denied:
      "请到系统设置中允许 Airset 访问媒体与 Apple Music。"
    case .restricted:
      "此设备可能被屏幕使用时间、家长控制或管理配置限制，Airset 无法直接解除。"
    case .checkingSubscription:
      "Airset 正在确认当前 Apple Music 账号是否可以播放完整目录歌曲。"
    case .subscriptionStatusUnknown:
      "授权已完成，但还需要刷新一次 Apple Music 播放资格。"
    case .ready:
      "可以播放 Apple Music 目录中的完整歌曲；若某首歌受地区或内容限制，仍会切换到试听。"
    case .needsSubscription:
      "完整歌曲需要有效 Apple Music 订阅；没有订阅时仍可播放可用的试听片段。"
    case .catalogPlaybackUnavailable:
      "当前账号、地区、内容限制或 Music app 状态暂不允许目录播放；请先在 Apple Music 中确认账号状态。"
    case .privacyAcknowledgementRequired:
      "请打开 Apple Music app，登录媒体账号并接受最新隐私政策、服务条款或 What's New，再回到 Airset 重试。"
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
      return "处理中"
    }

    return switch musicAuthorization.readiness {
    case .notDetermined:
      "连接 Apple Music"
    case .requestingAuthorization, .checkingSubscription:
      "处理中"
    case .denied:
      "打开系统设置"
    case .restricted:
      "查看限制说明"
    case .subscriptionStatusUnknown, .ready, .subscriptionCheckFailed:
      "刷新播放权限"
    case .needsSubscription:
      "查看 Apple Music 订阅"
    case .catalogPlaybackUnavailable, .privacyAcknowledgementRequired:
      "打开 Apple Music"
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
        title: Text("连接 Apple Music"),
        message: Text("Airset 会请求媒体与 Apple Music 权限，用于播放完整歌曲、读取你授权的歌单和歌曲。"),
        primaryButton: .default(Text("继续")) {
          Task {
            await requestAppleMusicAccess()
          }
        },
        secondaryButton: .cancel(Text("稍后"))
      )
    case .denied:
      return Alert(
        title: Text("需要 Apple Music 权限"),
        message: Text("请在系统设置中允许 Airset 访问媒体与 Apple Music，然后回到这里刷新播放权限。"),
        primaryButton: .default(Text("打开设置")) {
          openAppSettings()
        },
        secondaryButton: .cancel(Text("取消"))
      )
    case .restricted:
      return Alert(
        title: Text("Apple Music 访问受限制"),
        message: Text("此设备的媒体访问可能被屏幕使用时间、家长控制或管理配置限制。请检查系统限制后再重试。"),
        dismissButton: .default(Text("知道了"))
      )
    case .privacyAcknowledgementRequired:
      return Alert(
        title: Text("需要确认 Apple Music 隐私政策"),
        message: Text("请打开 Apple Music app，登录媒体账号并接受最新隐私政策、服务条款或 What's New。完成后回到 Airset 点“刷新播放权限”。"),
        primaryButton: .default(Text("打开 Apple Music")) {
          openAppleMusicApp()
        },
        secondaryButton: .cancel(Text("稍后"))
      )
    case .subscriptionRequired:
      return Alert(
        title: Text("需要 Apple Music 订阅"),
        message: Text("播放完整目录歌曲需要有效 Apple Music 订阅；没有订阅时，Airset 会尽量播放可用试听片段。"),
        primaryButton: .default(Text("查看订阅方案")) {
          isShowingMusicSubscriptionOffer = true
        },
        secondaryButton: .cancel(Text("稍后"))
      )
    case .catalogPlaybackUnavailable:
      return Alert(
        title: Text("目录播放暂不可用"),
        message: Text("请确认 Apple Music app 已安装、媒体账号已登录、订阅和地区可用，并且没有屏幕使用时间内容限制。"),
        primaryButton: .default(Text("打开 Apple Music")) {
          openAppleMusicApp()
        },
        secondaryButton: .default(Text("重试")) {
          Task {
            await refreshAppleMusicAccess(presentsFollowUp: false)
          }
        }
      )
    case .subscriptionCheckFailed(let message):
      return Alert(
        title: Text("检查播放权限失败"),
        message: Text(message),
        primaryButton: .default(Text("重试")) {
          Task {
            await refreshAppleMusicAccess(presentsFollowUp: true)
          }
        },
        secondaryButton: .cancel(Text("取消"))
      )
    case .subscriptionOfferFailed(let message):
      return Alert(
        title: Text("无法显示订阅方案"),
        message: Text(message),
        dismissButton: .default(Text("知道了"))
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

  private func syncSelectedHostSpeaker() {
    guard let catalog = radioStation.speechVoiceCatalog, !catalog.voices.isEmpty else { return }
    if selectedHostSpeakerID.isEmpty {
      selectedHostSpeakerID = catalog.defaultSpeaker
    } else if catalog.voice(for: selectedHostSpeakerID) == nil {
      selectedHostSpeakerID = catalog.defaultSpeaker
    }
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
      .navigationTitle("Mine")
  }
  .environment(playbackController)
  .environment(RadioStationController(playbackController: playbackController))
  .environment(MusicAuthorizationService())
  .environment(AppleMusicLibraryStore())
  .environment(DiagnosticsStore.preview())
  .environment(ImageAssetStore())
  .environment(ArtworkAnalysisStore())
}
