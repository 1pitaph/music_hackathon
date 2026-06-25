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

  func testImageStoreSavesCoverAndSurvivesReload() async throws {
    let directoryURL = try temporaryDirectory()
    let store = ImageAssetStore(directoryURL: directoryURL)

    let source = try await store.savePickedImage(
      data: testImageData(size: CGSize(width: 16, height: 28), color: .blue),
      purpose: .stationCover,
      key: "station-1"
    )

    XCTAssertEqual(store.coverSource(for: "station-1"), source)
    XCTAssertNotNil(store.image(for: source))

    let reloadedStore = ImageAssetStore(directoryURL: directoryURL)
    XCTAssertEqual(reloadedStore.coverSource(for: "station-1"), source)

    reloadedStore.clearCover(for: "station-1")
    XCTAssertNil(reloadedStore.coverSource(for: "station-1"))
  }

  func testCorruptMetadataFallsBackToEmptyState() throws {
    let directoryURL = try temporaryDirectory()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: directoryURL.appendingPathComponent("metadata.json"))

    let store = ImageAssetStore(directoryURL: directoryURL)

    XCTAssertNil(store.profileAvatarSource)
    XCTAssertNil(store.coverSource(for: "station-1"))
  }

  func testBundledCoverCatalogSelectionIsStable() {
    let first = BundledCoverCatalog.fallbackSource(forID: "station-1", title: "Night Set", genre: "Jazz")
    let second = BundledCoverCatalog.fallbackSource(forID: "station-1", title: "Night Set", genre: "Jazz")

    XCTAssertEqual(first, second)
    XCTAssertEqual(BundledCoverCatalog.covers.count, 10)
  }

  func testArtworkAnalysisChoosesReadableForeground() {
    let darkResult = ArtworkAnalysisStore.analyze(image: testImage(size: CGSize(width: 8, height: 8), color: .black))
    let lightResult = ArtworkAnalysisStore.analyze(image: testImage(size: CGSize(width: 8, height: 8), color: .white))

    XCTAssertTrue(darkResult.isDark)
    XCTAssertEqual(darkResult.recommendedForegroundHex, "#FFFFFF")
    XCTAssertFalse(lightResult.isDark)
    XCTAssertEqual(lightResult.recommendedForegroundHex, "#121212")
  }

  func testArtworkPriorityHonorsOverrideRemoteBundledFallbackOrder() {
    let override = ArtworkSource.userFile(fileName: "cover.jpg")
    let bundled = ArtworkSource.bundledCover(id: "midnight-blue-note")
    let remote = URL(string: "https://example.com/cover.jpg")!

    XCTAssertEqual(
      ArtworkPriorityResolver.preferredSource(
        overrideSource: override,
        remoteURLs: [remote],
        bundledFallback: bundled
      ),
      .override(override)
    )
    XCTAssertEqual(
      ArtworkPriorityResolver.preferredSource(
        overrideSource: nil,
        remoteURLs: [remote],
        bundledFallback: bundled
      ),
      .remote(remote)
    )
    XCTAssertEqual(
      ArtworkPriorityResolver.preferredSource(
        overrideSource: nil,
        remoteURLs: [],
        bundledFallback: bundled
      ),
      .bundled(bundled)
    )
    XCTAssertEqual(
      ArtworkPriorityResolver.preferredSource(
        overrideSource: nil,
        remoteURLs: [],
        bundledFallback: nil
      ),
      .generatedFallback
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
