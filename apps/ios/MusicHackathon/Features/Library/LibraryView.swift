import SwiftUI

struct LibraryView: View {
  @Environment(MusicAuthorizationService.self) private var musicAuthorization
  @Environment(AppleMusicLibraryStore.self) private var appleMusicLibrary

  var body: some View {
    List {
      Section(L10n.tr("archive.tab.playlists")) {
        if appleMusicLibrary.playlists.isEmpty {
          libraryStateRow
        } else {
          ForEach(appleMusicLibrary.playlists) { playlist in
            NavigationLink {
              PlaylistDetailView(playlist: playlist)
            } label: {
              HStack(spacing: 12) {
                PlaylistArtworkThumbnail(playlist: playlist, size: 42)

                VStack(alignment: .leading, spacing: 3) {
                  Text(playlist.name)
                  Text(playlist.curatorName ?? L10n.count("count.songs", playlist.tracks.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }

      Section("Apple Music") {
        HStack {
          Label(L10n.tr("library.access"), systemImage: "person.badge.key")
          Spacer()
          Text(musicAuthorization.statusText)
            .foregroundStyle(.secondary)
        }

        Button {
          Task {
            await musicAuthorization.requestAccess()
            await appleMusicLibrary.refresh(authorizationStatus: musicAuthorization.status)
          }
        } label: {
          Label(
            musicAuthorization.isRequestingAccess ? L10n.tr("appleMusic.requesting") : L10n.tr("appleMusic.requestAccess"),
            systemImage: "music.note.house"
          )
        }
        .disabled(musicAuthorization.isRequestingAccess || musicAuthorization.status == .authorized)

        Button {
          Task {
            await refreshLibrary()
          }
        } label: {
          Label(appleMusicLibrary.state.isLoading ? L10n.tr("playback.loading") : L10n.tr("library.refreshPlaylists"), systemImage: "arrow.clockwise")
        }
        .disabled(appleMusicLibrary.state.isLoading)

        if let errorMessage = appleMusicLibrary.lastErrorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .listStyle(.insetGrouped)
    .task {
      await musicAuthorization.refreshAccessState()
      await appleMusicLibrary.loadIfNeeded(authorizationStatus: musicAuthorization.status)
    }
  }

  @ViewBuilder
  private var libraryStateRow: some View {
    switch appleMusicLibrary.state {
    case .idle, .loading:
      ProgressView(L10n.tr("library.loadingAppleMusic"))
    case .needsAuthorization:
      Label(L10n.tr("library.connectAppleMusic"), systemImage: "person.badge.key")
    case .empty:
      Label(L10n.tr("archive.empty.playlists"), systemImage: "music.note.list")
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
    case .loaded:
      Label(L10n.tr("library.emptyPlayablePlaylists"), systemImage: "music.note.list")
    }
  }

  private func refreshLibrary() async {
    await musicAuthorization.refreshAccessState()
    await appleMusicLibrary.refresh(authorizationStatus: musicAuthorization.status)
  }
}

private struct PlaylistDetailView: View {
  let playlist: AppleMusicPlaylistSnapshot

  var body: some View {
    List {
      Section {
        HStack(spacing: 14) {
          PlaylistArtworkThumbnail(playlist: playlist, size: 72)

          VStack(alignment: .leading, spacing: 5) {
            Text(playlist.name)
              .font(.headline)
            Text(playlist.curatorName ?? L10n.tr("archive.appleMusicLibrary"))
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Text(L10n.count("count.songs", playlist.tracks.count))
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 8)
      }

      Section(L10n.tr("archive.tab.songs")) {
        if playlist.tracks.isEmpty {
          ContentUnavailableView(
            L10n.tr("library.noSongsLoaded"),
            systemImage: "music.note",
            description: Text(L10n.tr("library.refreshToLoadTracks"))
          )
        } else {
          ForEach(playlist.tracks) { track in
            HStack(spacing: 12) {
              TrackArtworkThumbnail(track: track, size: 40)

              VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                Text("\(track.artist) • \(track.album)")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          }
        }
      }
    }
  }
}

private struct PlaylistArtworkThumbnail: View {
  let playlist: AppleMusicPlaylistSnapshot
  let size: CGFloat

  var body: some View {
    ArtworkImageView(resolution: artworkResolution) {
      Color.clear
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityHidden(true)
  }

  private var artworkResolution: ArtworkResolution {
    ArtworkResolution(remoteURLs: playlist.artworkCandidateURLs)
  }
}

private struct TrackArtworkThumbnail: View {
  let track: Track
  let size: CGFloat

  var body: some View {
    ArtworkImageView(resolution: artworkResolution) {
      Color.clear
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .accessibilityHidden(true)
  }

  private var artworkResolution: ArtworkResolution {
    ArtworkResolution(remoteURLs: [track.artworkURL])
  }
}

#Preview {
  NavigationStack {
    LibraryView()
      .navigationTitle(L10n.tr("library.title"))
  }
  .environment(MusicAuthorizationService())
  .environment(AppleMusicLibraryStore())
  .environment(ImageAssetStore())
  .environment(ArtworkAnalysisStore())
}
