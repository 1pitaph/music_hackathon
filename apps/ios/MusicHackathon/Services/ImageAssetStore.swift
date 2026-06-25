import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ImageAssetStore {
  private(set) var profileAvatarSource: ArtworkSource?
  private(set) var revision = 0

  private let fileManager: FileManager
  private let directoryURL: URL
  private let imagesDirectoryURL: URL
  private let metadataURL: URL
  private var metadata: ImageAssetMetadata

  init(
    directoryURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    let rootURL = directoryURL ?? Self.defaultDirectoryURL()
    self.directoryURL = rootURL
    imagesDirectoryURL = rootURL.appendingPathComponent("Images", isDirectory: true)
    metadataURL = rootURL.appendingPathComponent("metadata.json")
    metadata = Self.loadMetadata(from: metadataURL)
    profileAvatarSource = metadata.profileAvatarSource
  }

  func imageURL(for source: ArtworkSource) -> URL? {
    switch source {
    case let .userFile(fileName):
      return imagesDirectoryURL.appendingPathComponent(fileName)
    case .bundledCover:
      return nil
    }
  }

  func image(for source: ArtworkSource) -> UIImage? {
    guard let url = imageURL(for: source),
          let data = try? Data(contentsOf: url) else {
      return nil
    }
    return UIImage(data: data)
  }

  @discardableResult
  func savePickedImage(
    data: Data,
    purpose: ImageAssetPurpose,
    key: String? = nil
  ) async throws -> ArtworkSource {
    let jpegData = try Self.squareJPEGData(from: data)
    try ensureDirectories()

    let fileName = fileName(for: purpose, key: key)
    let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)
    try jpegData.write(to: fileURL, options: [.atomic, .completeFileProtection])

    let source = ArtworkSource.userFile(fileName: fileName)
    switch purpose {
    case .profileAvatar:
      removeUserFileIfNeeded(metadata.profileAvatarSource, excluding: source)
      metadata.profileAvatarSource = source
      profileAvatarSource = source
    }

    try saveMetadata()
    revision += 1
    return source
  }

  func clearProfileAvatar() {
    removeUserFileIfNeeded(metadata.profileAvatarSource, excluding: nil)
    metadata.profileAvatarSource = nil
    profileAvatarSource = nil
    try? saveMetadata()
    revision += 1
  }

  func clearAllCustomImages() {
    try? fileManager.removeItem(at: directoryURL)
    metadata = ImageAssetMetadata()
    profileAvatarSource = nil
    revision += 1
  }

  private func fileName(for purpose: ImageAssetPurpose, key: String?) -> String {
    switch purpose {
    case .profileAvatar:
      return "profile-avatar.jpg"
    }
  }

  private func removeUserFileIfNeeded(_ source: ArtworkSource?, excluding replacement: ArtworkSource?) {
    guard case let .userFile(fileName)? = source else { return }
    if source == replacement { return }
    try? fileManager.removeItem(at: imagesDirectoryURL.appendingPathComponent(fileName))
  }

  private func ensureDirectories() throws {
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
  }

  private func saveMetadata() throws {
    try ensureDirectories()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(metadata)
    try data.write(to: metadataURL, options: [.atomic, .completeFileProtection])
  }

  private static func loadMetadata(from metadataURL: URL) -> ImageAssetMetadata {
    guard let data = try? Data(contentsOf: metadataURL),
          let metadata = try? JSONDecoder().decode(ImageAssetMetadata.self, from: data) else {
      return ImageAssetMetadata()
    }
    return metadata
  }

  private static func defaultDirectoryURL() -> URL {
    let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return applicationSupportURL.appendingPathComponent("AirsetImages", isDirectory: true)
  }

  static func squareJPEGData(from data: Data, maxSide: CGFloat = 1024, compressionQuality: CGFloat = 0.86) throws -> Data {
    guard let image = UIImage(data: data),
          let cgImage = image.cgImage else {
      throw ImageAssetStoreError.invalidImage
    }

    let inputWidth = CGFloat(cgImage.width)
    let inputHeight = CGFloat(cgImage.height)
    let side = min(inputWidth, inputHeight)
    let cropRect = CGRect(
      x: (inputWidth - side) / 2,
      y: (inputHeight - side) / 2,
      width: side,
      height: side
    )

    guard let croppedImage = cgImage.cropping(to: cropRect) else {
      throw ImageAssetStoreError.invalidImage
    }

    let outputSide = min(side, maxSide)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)
    let renderedImage = renderer.image { _ in
      UIImage(cgImage: croppedImage).draw(in: CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
    }

    guard let jpegData = renderedImage.jpegData(compressionQuality: compressionQuality) else {
      throw ImageAssetStoreError.invalidImage
    }
    return jpegData
  }
}

private struct ImageAssetMetadata: Codable {
  var profileAvatarSource: ArtworkSource?

  init(profileAvatarSource: ArtworkSource? = nil) {
    self.profileAvatarSource = profileAvatarSource
  }

  private enum CodingKeys: String, CodingKey {
    case profileAvatarSource
    case coverSources
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    profileAvatarSource = try container.decodeIfPresent(ArtworkSource.self, forKey: .profileAvatarSource)
    _ = try container.decodeIfPresent([String: ArtworkSource].self, forKey: .coverSources)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(profileAvatarSource, forKey: .profileAvatarSource)
  }
}

enum ImageAssetStoreError: Error {
  case invalidImage
}
