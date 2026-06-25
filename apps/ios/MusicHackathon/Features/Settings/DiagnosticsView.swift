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
    .navigationTitle(L10n.tr("diagnostics.title"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: L10n.tr("diagnostics.searchPrompt"))
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        exportButton
        Menu {
          Button {
            Task {
              await diagnostics.refreshRecentEvents()
            }
          } label: {
            Label(L10n.tr("common.refresh"), systemImage: "arrow.clockwise")
          }

          Button(role: .destructive) {
            isShowingClearConfirmation = true
          } label: {
            Label(L10n.tr("diagnostics.clearLogs"), systemImage: "trash")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(L10n.tr("diagnostics.moreActions"))
      }
    }
    .confirmationDialog(
      L10n.tr("diagnostics.clearConfirmation.title"),
      isPresented: $isShowingClearConfirmation,
      titleVisibility: .visible
    ) {
      Button(L10n.tr("diagnostics.clearLogs"), role: .destructive) {
        Task {
          await diagnostics.clearLogs()
        }
      }
      Button(L10n.tr("common.cancel"), role: .cancel) {}
    } message: {
      Text(L10n.tr("diagnostics.clearConfirmation.message"))
    }
    .task {
      await diagnostics.refreshRecentEvents()
    }
  }

  private var statusSection: some View {
    Section(L10n.tr("diagnostics.status.section")) {
      LabeledContent(L10n.tr("diagnostics.status.recorded"), value: "\(diagnostics.recentEvents.count)")
      LabeledContent(L10n.tr("diagnostics.status.errorsAndWarnings"), value: "\(diagnostics.errorCount)")
      LabeledContent(L10n.tr("diagnostics.status.storage"), value: diagnostics.storageSummary.totalSizeText)
      LabeledContent(L10n.tr("diagnostics.status.lastEvent"), value: diagnostics.lastEventText)

      if diagnostics.isVerboseLoggingEnabled {
        if let expiresAt = diagnostics.verboseLoggingExpiresAt {
          LabeledContent(L10n.tr("diagnostics.status.verbose"), value: L10n.tr("diagnostics.verbose.until", expiresAt.formatted(.dateTime.hour().minute())))
        } else {
          LabeledContent(L10n.tr("diagnostics.status.verbose"), value: L10n.tr("common.enabled"))
        }

        Button {
          diagnostics.disableVerboseLogging()
        } label: {
          Label(L10n.tr("diagnostics.verbose.disable"), systemImage: "stop.circle")
        }
      } else {
        Button {
          diagnostics.enableVerboseLogging()
        } label: {
          Label(L10n.tr("diagnostics.verbose.enable15Minutes"), systemImage: "stethoscope")
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
    Section(L10n.tr("settings.privacy.section")) {
      Text(L10n.tr("diagnostics.privacy.description"))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var filtersSection: some View {
    Section(L10n.tr("diagnostics.filters.section")) {
      Picker(L10n.tr("diagnostics.filters.level"), selection: $selectedLevel) {
        Text(L10n.tr("common.all")).tag(Optional<DiagnosticLogLevel>.none)
        ForEach(DiagnosticLogLevel.allCases, id: \.self) { level in
          Label(level.title, systemImage: level.systemImage)
            .tag(Optional(level))
        }
      }

      Picker(L10n.tr("diagnostics.filters.chain"), selection: $selectedChain) {
        Text(L10n.tr("common.all")).tag(Optional<DiagnosticLogChain>.none)
        ForEach(DiagnosticLogChain.allCases, id: \.self) { chain in
          Label(chain.title, systemImage: chain.systemImage)
            .tag(Optional(chain))
        }
      }
    }
  }

  private var eventsSection: some View {
    Section(L10n.tr("diagnostics.logs.section")) {
      if filteredEvents.isEmpty {
        ContentUnavailableView(
          searchText.isEmpty ? L10n.tr("diagnostics.empty.title") : L10n.tr("diagnostics.empty.noMatchesTitle"),
          systemImage: searchText.isEmpty ? "doc.text.magnifyingglass" : "line.3.horizontal.decrease.circle",
          description: Text(searchText.isEmpty ? L10n.tr("diagnostics.empty.message") : L10n.tr("diagnostics.empty.noMatchesMessage"))
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
      .accessibilityLabel(L10n.tr("diagnostics.shareReport"))
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
      .accessibilityLabel(L10n.tr("diagnostics.exportReport"))
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
      Section(L10n.tr("diagnostics.detail.overview")) {
        LabeledContent(L10n.tr("diagnostics.detail.time"), value: event.timestamp.formatted(.dateTime.year().month().day().hour().minute().second()))
        LabeledContent(L10n.tr("diagnostics.detail.level"), value: event.level.title)
        LabeledContent(L10n.tr("diagnostics.detail.chain"), value: event.chain.title)
        LabeledContent(L10n.tr("diagnostics.detail.event"), value: event.event)
        if let correlationID = event.correlationID {
          LabeledContent(L10n.tr("diagnostics.detail.correlationID"), value: correlationID)
        }
      }

      Section(L10n.tr("diagnostics.detail.message")) {
        Text(event.message)
      }

      if !event.payload.isEmpty {
        Section(L10n.tr("diagnostics.detail.context")) {
          ForEach(event.payload.keys.sorted(), id: \.self) { key in
            LabeledContent(key, value: event.payload[key] ?? "")
          }
        }
      }

      if !relatedEvents.isEmpty {
        Section(L10n.tr("diagnostics.detail.relatedEvents")) {
          ForEach(relatedEvents) { relatedEvent in
            DiagnosticsLogRow(event: relatedEvent)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(L10n.tr("diagnostics.detail.title"))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    DiagnosticsView()
  }
  .environment(DiagnosticsStore.preview())
}
