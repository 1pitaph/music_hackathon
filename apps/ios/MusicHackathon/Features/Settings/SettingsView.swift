import MusicKit
import SwiftUI

struct SettingsView: View {
  @Environment(MusicAuthorizationService.self) private var musicAuthorization
  @Environment(RadioStationController.self) private var radioStation

  @AppStorage(RadioHostVoiceSettings.speakerIDKey) private var selectedHostSpeakerID = ""

  @State private var autoPlayNextStation = false
  @State private var backgroundPlay = false
  @State private var publicStation = false
  @State private var dataCollection = true

  var body: some View {
    List {
      appleMusicSection
      playbackSection
      backendStationSection
      speechVoiceSection
      dataSourceSection
      privacySection
      localMemorySection
      aboutSection
    }
    .listStyle(.insetGrouped)
    .task {
      await musicAuthorization.refreshAccessState()
      await radioStation.refreshMemoryStatus()
      await loadSpeechVoicesIfNeeded()
    }
  }

  private var appleMusicSection: some View {
    Section("Apple Music 授权") {
      LabeledContent("授权状态", value: musicAuthorization.statusText)
      LabeledContent("订阅状态", value: musicAuthorization.subscriptionText)

      Button {
        Task {
          await musicAuthorization.requestAccess()
        }
      } label: {
        Label(
          musicAuthorization.isRequestingAccess ? "请求中" : "连接 Apple Music",
          systemImage: "person.badge.key"
        )
      }
      .disabled(musicAuthorization.isRequestingAccess || musicAuthorization.status == .authorized)

      Button {
        Task {
          await musicAuthorization.refreshAccessState()
        }
      } label: {
        Label("刷新播放权限", systemImage: "arrow.triangle.2.circlepath")
      }
      .disabled(musicAuthorization.isRequestingAccess)

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

      Button {
        Task {
          await radioStation.refreshStation()
        }
      } label: {
        Label(
          radioStation.isLoadingStation ? "加载中" : "刷新后端电台",
          systemImage: "dot.radiowaves.left.and.right"
        )
      }
      .disabled(radioStation.isLoadingStation)

      if let message = radioStation.errorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
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

#Preview {
  let playbackController = PlaybackController()
  NavigationStack {
    SettingsView()
      .navigationTitle("Mine")
  }
  .environment(playbackController)
  .environment(RadioStationController(playbackController: playbackController))
  .environment(MusicAuthorizationService())
}
