import SwiftUI
import UIKit

struct ArtworkImageView<Fallback: View>: View {
  @Environment(ArtworkAnalysisStore.self) private var analysisStore

  let resolution: ArtworkResolution
  let showsLoadingIndicator: Bool
  let fallback: () -> Fallback

  init(
    resolution: ArtworkResolution,
    showsLoadingIndicator: Bool = true,
    @ViewBuilder fallback: @escaping () -> Fallback
  ) {
    self.resolution = resolution
    self.showsLoadingIndicator = showsLoadingIndicator
    self.fallback = fallback
  }

  var body: some View {
    if !resolution.remoteURLs.isEmpty {
      RemoteArtworkView(
        urls: resolution.remoteURLs,
        showsLoadingIndicator: showsLoadingIndicator,
        onImageLoaded: { image, url in
          analysisStore.analyze(image: image, key: "remote:\(url.absoluteString)")
        }
      ) {
        fallback()
      }
    } else {
      fallback()
    }
  }
}

struct ProfileAvatarImageView<Fallback: View>: View {
  @Environment(ImageAssetStore.self) private var imageStore
  @Environment(ArtworkAnalysisStore.self) private var analysisStore

  let size: CGFloat
  let fallback: () -> Fallback

  init(size: CGFloat, @ViewBuilder fallback: @escaping () -> Fallback) {
    self.size = size
    self.fallback = fallback
  }

  var body: some View {
    if let source = imageStore.profileAvatarSource,
       let image = imageStore.image(for: source) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: source.id) {
          analysisStore.analyze(image: image, key: source.id)
        }
    } else {
      fallback()
    }
  }
}
