import Foundation
import SwiftUI
import UIKit

enum ArtworkURLCandidates {
  static func normalized(_ url: URL?) -> URL? {
    guard let url else { return nil }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      return nil
    }
    guard let host = url.host, !host.isEmpty else { return nil }

    let absoluteString = url.absoluteString
    let decodedString = absoluteString.removingPercentEncoding ?? absoluteString
    let normalizedString = decodedString.lowercased()
    let unresolvedTokens = ["{w}", "{h}", "{f}"]
    guard !unresolvedTokens.contains(where: normalizedString.contains) else {
      return nil
    }

    return url
  }

  static func unique(from urls: [URL?]) -> [URL] {
    var seen = Set<String>()
    var result: [URL] = []

    for url in urls {
      guard let normalizedURL = normalized(url) else { continue }
      let key = normalizedURL.absoluteString
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(normalizedURL)
    }

    return result
  }
}

private enum RemoteArtworkImageCache {
  static let shared = NSCache<NSURL, UIImage>()
}

struct RemoteArtworkView<Fallback: View>: View {
  private let candidateURLs: [URL]
  private let loadingTimeout: TimeInterval
  private let showsLoadingIndicator: Bool
  private let onImageLoaded: ((UIImage, URL) -> Void)?
  private let fallback: () -> Fallback

  @State private var image: UIImage?
  @State private var isLoading = false

  init(
    urls: [URL?],
    loadingTimeout: TimeInterval = 1.2,
    showsLoadingIndicator: Bool = true,
    onImageLoaded: ((UIImage, URL) -> Void)? = nil,
    @ViewBuilder fallback: @escaping () -> Fallback
  ) {
    self.candidateURLs = ArtworkURLCandidates.unique(from: urls)
    self.loadingTimeout = loadingTimeout
    self.showsLoadingIndicator = showsLoadingIndicator
    self.onImageLoaded = onImageLoaded
    self.fallback = fallback
  }

  init(
    urls: [URL],
    loadingTimeout: TimeInterval = 1.2,
    showsLoadingIndicator: Bool = true,
    onImageLoaded: ((UIImage, URL) -> Void)? = nil,
    @ViewBuilder fallback: @escaping () -> Fallback
  ) {
    self.candidateURLs = ArtworkURLCandidates.unique(from: urls.map(Optional.some))
    self.loadingTimeout = loadingTimeout
    self.showsLoadingIndicator = showsLoadingIndicator
    self.onImageLoaded = onImageLoaded
    self.fallback = fallback
  }

  var body: some View {
    ZStack {
      fallback()

      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .transition(.opacity)
      }

      if isLoading && image == nil && showsLoadingIndicator {
        ProgressView()
          .controlSize(.small)
          .transition(.opacity)
      }
    }
    .task(id: loadKey) {
      await loadImage()
    }
  }

  private var loadKey: String {
    candidateURLs.map(\.absoluteString).joined(separator: "|")
  }

  @MainActor
  private func loadImage() async {
    image = nil
    guard !candidateURLs.isEmpty else {
      isLoading = false
      return
    }

    isLoading = showsLoadingIndicator
    defer {
      if !Task.isCancelled {
        isLoading = false
      }
    }

    for url in candidateURLs {
      if let cachedImage = RemoteArtworkImageCache.shared.object(forKey: url as NSURL) {
        image = cachedImage
        onImageLoaded?(cachedImage, url)
        return
      }

      do {
        let data = try await Self.imageData(from: url, timeout: loadingTimeout)
        guard !Task.isCancelled else { return }
        guard let loadedImage = UIImage(data: data) else { continue }
        RemoteArtworkImageCache.shared.setObject(loadedImage, forKey: url as NSURL)
        image = loadedImage
        onImageLoaded?(loadedImage, url)
        return
      } catch is CancellationError {
        return
      } catch {
        continue
      }
    }
  }

  private static func imageData(from url: URL, timeout: TimeInterval) async throws -> Data {
    try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask {
        var request = URLRequest(url: url)
        request.timeoutInterval = max(timeout, 0.1)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
          guard 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
          }
        }

        return data
      }

      group.addTask {
        let nanoseconds = UInt64(max(timeout, 0.1) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
        throw URLError(.timedOut)
      }

      do {
        guard let data = try await group.next() else {
          throw URLError(.unknown)
        }
        group.cancelAll()
        return data
      } catch {
        group.cancelAll()
        throw error
      }
    }
  }
}
