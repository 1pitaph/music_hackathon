import XCTest
import UIKit
@testable import MusicHackathon

@MainActor
final class ArtworkImageSystemTests: XCTestCase {
  func testImageStoreSavesReloadsAndDeletesProfileAvatar() async throws {
    let directoryURL = try temporaryDirectory()
    let store = ImageAssetStore(directoryURL: directoryURL)

    let source = try await store.savePickedImage(
      data: testImageData(size: CGSize(width: 24, height: 12), color: .red),
      purpose: .profileAvatar
    )

    XCTAssertEqual(store.profileAvatarSource, source)
    guard let imageURL = store.imageURL(for: source) else {
      XCTFail("Expected image URL")
      return
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))

    let reloadedStore = ImageAssetStore(directoryURL: directoryURL)
    XCTAssertEqual(reloadedStore.profileAvatarSource, source)
    XCTAssertNotNil(reloadedStore.image(for: source))

    reloadedStore.clearProfileAvatar()
    XCTAssertNil(reloadedStore.profileAvatarSource)
    XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
  }

  func testCorruptMetadataFallsBackToEmptyState() throws {
    let directoryURL = try temporaryDirectory()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: directoryURL.appendingPathComponent("metadata.json"))

    let store = ImageAssetStore(directoryURL: directoryURL)

    XCTAssertNil(store.profileAvatarSource)
  }

  func testLegacyBundledCoverMetadataIsIgnoredAndScrubbedOnSave() async throws {
    struct LegacyMetadata: Codable {
      var profileAvatarSource: ArtworkSource?
      var coverSources: [String: ArtworkSource]
    }

    let directoryURL = try temporaryDirectory()
    let metadataURL = directoryURL.appendingPathComponent("metadata.json")
    let profileSource = ArtworkSource.userFile(fileName: "profile-avatar.jpg")
    let legacyMetadata = LegacyMetadata(
      profileAvatarSource: profileSource,
      coverSources: ["station-1": .bundledCover(id: "midnight-blue-note")]
    )
    try JSONEncoder().encode(legacyMetadata).write(to: metadataURL)

    let store = ImageAssetStore(directoryURL: directoryURL)

    XCTAssertEqual(store.profileAvatarSource, profileSource)
    XCTAssertNil(store.imageURL(for: .bundledCover(id: "midnight-blue-note")))

    try await store.savePickedImage(
      data: testImageData(size: CGSize(width: 24, height: 24), color: .green),
      purpose: .profileAvatar
    )
    let savedMetadata = try String(contentsOf: metadataURL, encoding: .utf8)

    XCTAssertFalse(savedMetadata.contains("coverSources"))
    XCTAssertFalse(savedMetadata.contains("bundledCover"))
  }

  func testArtworkAnalysisChoosesReadableForeground() {
    let darkResult = ArtworkAnalysisStore.analyze(image: testImage(size: CGSize(width: 8, height: 8), color: .black))
    let lightResult = ArtworkAnalysisStore.analyze(image: testImage(size: CGSize(width: 8, height: 8), color: .white))

    XCTAssertTrue(darkResult.isDark)
    XCTAssertEqual(darkResult.recommendedForegroundHex, "#FFFFFF")
    XCTAssertFalse(lightResult.isDark)
    XCTAssertEqual(lightResult.recommendedForegroundHex, "#121212")
  }

  func testArtworkPriorityOnlyUsesFetchableRemoteArtwork() {
    let remote = URL(string: "https://example.com/cover.jpg")!
    let template = URL(string: "https://example.com/{w}x{h}bb.{f}")!

    XCTAssertEqual(
      ArtworkPriorityResolver.preferredSource(
        remoteURLs: [remote]
      ),
      .remote(remote)
    )
    XCTAssertEqual(
      ArtworkPriorityResolver.preferredSource(
        remoteURLs: [template, nil]
      ),
      .none
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ArtworkImageSystemTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func testImageData(size: CGSize, color: UIColor) -> Data {
    testImage(size: size, color: color).pngData()!
  }

  private func testImage(size: CGSize, color: UIColor) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { context in
      color.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
  }
}
