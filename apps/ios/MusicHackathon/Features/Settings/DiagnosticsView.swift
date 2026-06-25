import SwiftUI

struct DiagnosticsView: View {
  @Environment(DiagnosticsStore.self) private var diagnostics

  @State private var searchText = ""
  @State private var selectedLevel: DiagnosticLogLevel?
  @State private var selectedChain: DiagnosticLogChain?
  @State private var isExporting = false
  @State private var isShowingClearConfirmation = false

  private var filteredEvents: [DiagnosticLogEvent] {
    diagnostics.recentEvents.filter { event in
      if let selectedLevel, event.level != selectedLevel {
        return false
      }

      if let selectedChain, event.chain != selectedChain {
        return false
      }

      guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return true
      }

      let query = searchText.lowercased()
      return event.message.lowercased().contains(query)
        || event.event.lowercased().contains(query)
        || event.chain.title.lowercased().contains(query)
        || event.payload.contains { key, value in
          key.lowercased().contains(query) || value.lowercased().contains(query)
        }
    }
  }

  var body: some View {
    List {
      statusSection
      privacySection
      filtersSection
      eventsSection
    }
    .listStyle(.insetGrouped)
    .navigationTitle("日志与诊断")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "搜索日志、链路或字段")
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        exportButton
        Menu {
          Button {
            Task {
              await diagnostics.refreshRecentEvents()
            }
          } label: {
            Label("刷新", systemImage: "arrow.clockwise")
          }

          Button(role: .destructive) {
            isShowingClearConfirmation = true
          } label: {
            Label("清空日志", systemImage: "trash")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("更多诊断操作")
      }
    }
    .confirmationDialog(
      "清空本地诊断日志？",
      isPresented: $isShowingClearConfirmation,
      titleVisibility: .visible
    ) {
      Button("清空日志", role: .destructive) {
        Task {
          await diagnostics.clearLogs()
        }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("这只会清空诊断日志，不会删除本地声音档案或 Apple Music 资料库。")
    }
    .task {
      await diagnostics.refreshRecentEvents()
    }
  }

  private var statusSection: some View {
    Section("状态") {
      LabeledContent("已记录", value: "\(diagnostics.recentEvents.count)")
      LabeledContent("错误与警告", value: "\(diagnostics.errorCount)")
      LabeledContent("占用空间", value: diagnostics.storageSummary.totalSizeText)
      LabeledContent("最近事件", value: diagnostics.lastEventText)

      if diagnostics.isVerboseLoggingEnabled {
        if let expiresAt = diagnostics.verboseLoggingExpiresAt {
          LabeledContent("详细诊断", value: "到 \(expiresAt.formatted(.dateTime.hour().minute()))")
        } else {
          LabeledContent("详细诊断", value: "已开启")
        }

        Button {
          diagnostics.disableVerboseLogging()
        } label: {
          Label("关闭详细诊断", systemImage: "stop.circle")
        }
      } else {
        Button {
          diagnostics.enableVerboseLogging()
        } label: {
          Label("开启详细诊断 15 分钟", systemImage: "stethoscope")
        }
      }

      if let message = diagnostics.lastErrorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var privacySection: some View {
    Section("隐私") {
      Text("诊断日志用于排查播放、授权、后端电台和本地档案问题。导出报告不包含 Apple Music token、完整私人 URL、音频文件、封面图片或完整资料库历史。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var filtersSection: some View {
    Section("筛选") {
      Picker("级别", selection: $selectedLevel) {
        Text("全部").tag(Optional<DiagnosticLogLevel>.none)
        ForEach(DiagnosticLogLevel.allCases, id: \.self) { level in
          Label(level.title, systemImage: level.systemImage)
            .tag(Optional(level))
        }
      }

      Picker("链路", selection: $selectedChain) {
        Text("全部").tag(Optional<DiagnosticLogChain>.none)
        ForEach(DiagnosticLogChain.allCases, id: \.self) { chain in
          Label(chain.title, systemImage: chain.systemImage)
            .tag(Optional(chain))
        }
      }
    }
  }

  private var eventsSection: some View {
    Section("日志") {
      if filteredEvents.isEmpty {
        ContentUnavailableView(
          searchText.isEmpty ? "暂无诊断日志" : "没有匹配的日志",
          systemImage: searchText.isEmpty ? "doc.text.magnifyingglass" : "line.3.horizontal.decrease.circle",
          description: Text(searchText.isEmpty ? "播放、授权或电台操作发生后会在这里显示。" : "调整搜索词或筛选条件后再试。")
        )
      } else {
        ForEach(filteredEvents) { event in
          NavigationLink {
            DiagnosticsLogDetailView(event: event, relatedEvents: relatedEvents(for: event))
          } label: {
            DiagnosticsLogRow(event: event)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var exportButton: some View {
    if let exportURL = diagnostics.lastExportURL, !isExporting {
      ShareLink(item: exportURL) {
        Image(systemName: "square.and.arrow.up")
      }
      .accessibilityLabel("分享诊断报告")
    } else {
      Button {
        Task {
          isExporting = true
          _ = await diagnostics.exportIssueReport()
          isExporting = false
        }
      } label: {
        if isExporting {
          ProgressView()
        } else {
          Image(systemName: "square.and.arrow.up")
        }
      }
      .accessibilityLabel("导出诊断报告")
      .disabled(isExporting)
    }
  }

  private func relatedEvents(for event: DiagnosticLogEvent) -> [DiagnosticLogEvent] {
    guard let correlationID = event.correlationID else { return [] }
    return diagnostics.recentEvents.filter { relatedEvent in
      relatedEvent.id != event.id && relatedEvent.correlationID == correlationID
    }
  }
}

private struct DiagnosticsLogRow: View {
  let event: DiagnosticLogEvent

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: event.level.systemImage)
        .foregroundStyle(levelTint)
        .frame(width: 22, height: 22)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(event.chain.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }

        Text(event.message)
          .font(.subheadline)
          .lineLimit(2)

        HStack(spacing: 8) {
          Text(event.event)
          if let suffix = event.correlationSuffix {
            Text("#\(suffix)")
          }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 4)
  }

  private var levelTint: Color {
    switch event.level {
    case .debug, .info:
      .secondary
    case .notice:
      .green
    case .warning:
      .orange
    case .error, .fault:
      .red
    }
  }
}

private struct DiagnosticsLogDetailView: View {
  let event: DiagnosticLogEvent
  let relatedEvents: [DiagnosticLogEvent]

  var body: some View {
    List {
      Section("概览") {
        LabeledContent("时间", value: event.timestamp.formatted(.dateTime.year().month().day().hour().minute().second()))
        LabeledContent("级别", value: event.level.title)
        LabeledContent("链路", value: event.chain.title)
        LabeledContent("事件", value: event.event)
        if let correlationID = event.correlationID {
          LabeledContent("关联 ID", value: correlationID)
        }
      }

      Section("消息") {
        Text(event.message)
      }

      if !event.payload.isEmpty {
        Section("上下文") {
          ForEach(event.payload.keys.sorted(), id: \.self) { key in
            LabeledContent(key, value: event.payload[key] ?? "")
          }
        }
      }

      if !relatedEvents.isEmpty {
        Section("同一链路事件") {
          ForEach(relatedEvents) { relatedEvent in
            DiagnosticsLogRow(event: relatedEvent)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("日志详情")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    DiagnosticsView()
  }
  .environment(DiagnosticsStore.preview())
}
