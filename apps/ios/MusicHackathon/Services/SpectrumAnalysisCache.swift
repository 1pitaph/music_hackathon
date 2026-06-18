import CoreGraphics
import Foundation

actor SpectrumAnalysisCache {
  static let shared = SpectrumAnalysisCache()

  private var analyses: [SpectrumAnalysisCacheKey: AudioSpectrumAnalysis] = [:]
  private var localPreviewURLs: [URL: URL] = [:]

  func analysis(for audioURL: URL, bandCount: Int) async -> AudioSpectrumAnalysis {
    let key = SpectrumAnalysisCacheKey(audioURL: audioURL, bandCount: bandCount)
    if let analysis = analyses[key] {
      return analysis
    }

    do {
      let localURL = try await localAudioURL(for: audioURL)
      let analysis = await AudioSpectrumAnalyzer.analyze(audioURL: localURL, bandCount: bandCount)
      analyses[key] = analysis
      return analysis
    } catch {
      let empty = AudioSpectrumAnalysis.empty(bandCount: bandCount, frameRate: 30)
      analyses[key] = empty
      return empty
    }
  }

  private func localAudioURL(for audioURL: URL) async throws -> URL {
    guard !audioURL.isFileURL else {
      return audioURL
    }

    if let localURL = localPreviewURLs[audioURL] {
      return localURL
    }

    let directoryURL = try previewCacheDirectory()
    let targetURL = directoryURL.appendingPathComponent(Self.cacheFileName(for: audioURL))

    if FileManager.default.fileExists(atPath: targetURL.path) {
      localPreviewURLs[audioURL] = targetURL
      return targetURL
    }

    let (downloadedURL, response) = try await URLSession.shared.download(from: audioURL)
    if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
      throw SpectrumAnalysisCacheError.downloadFailed
    }

    if FileManager.default.fileExists(atPath: targetURL.path) {
      try FileManager.default.removeItem(at: targetURL)
    }

    try FileManager.default.moveItem(at: downloadedURL, to: targetURL)
    localPreviewURLs[audioURL] = targetURL
    return targetURL
  }

  private func previewCacheDirectory() throws -> URL {
    let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let directoryURL = cachesURL.appendingPathComponent("AudioSpectrumPreviews", isDirectory: true)

    if !FileManager.default.fileExists(atPath: directoryURL.path) {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    return directoryURL
  }

  private static func cacheFileName(for audioURL: URL) -> String {
    let extensionName = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
    return "\(String(format: "%016llx", stableHash(audioURL.absoluteString))).\(extensionName)"
  }

  private static func stableHash(_ value: String) -> UInt64 {
    value.utf8.reduce(UInt64(0xcbf29ce484222325)) { partialResult, byte in
      (partialResult ^ UInt64(byte)) &* 0x100000001b3
    }
  }
}

enum ProceduralSpectrumGenerator {
  static func bands(for track: Track, at seconds: TimeInterval, fallbackBars: [CGFloat]) -> [Float] {
    guard !fallbackBars.isEmpty else { return [] }

    let safeSeconds = seconds.isFinite ? max(0, seconds) : 0
    let seed = stableHash("\(track.title)|\(track.artist)|\(track.album)|\(track.mood)")
    let maxFallbackHeight = max(fallbackBars.max() ?? 1, 1)
    let tempo = 76 + Double(seed % 58)
    let beatPosition = safeSeconds * tempo / 60
    let moodBoost = energyBoost(for: track.mood)

    return fallbackBars.enumerated().map { index, height in
      let normalizedHeight = Double(height / maxFallbackHeight)
      let bandPosition = Double(index) / Double(max(fallbackBars.count - 1, 1))
      let seedOffset = unit(seed &+ UInt64(index) &* 0x9E3779B97F4A7C15)
      let phase = seedOffset * Double.pi * 2
      let lowWave = sin((safeSeconds * 1.15) + phase)
      let midWave = sin((safeSeconds * 2.75) + (phase * 1.7))
      let beatWave = max(0, sin((beatPosition * Double.pi * 2) - (bandPosition * 1.2)))
      let beatPulse = pow(beatWave, 4)
      let spectralTilt = 1 - (bandPosition * 0.34)
      let breathing = sin((safeSeconds * 0.32) + (phase * 0.37)) * 0.08

      let value = 0.16
        + (normalizedHeight * 0.38)
        + (lowWave * 0.11)
        + (midWave * 0.07)
        + (beatPulse * 0.26 * spectralTilt)
        + breathing
        + moodBoost

      return Float(min(max(value, 0.10), 1.0))
    }
  }

  private static func energyBoost(for mood: String) -> Double {
    let normalizedMood = mood.lowercased()

    if normalizedMood.contains("glow") || normalizedMood.contains("pop") {
      return 0.08
    }

    if normalizedMood.contains("cinematic") || normalizedMood.contains("night") {
      return 0.04
    }

    if normalizedMood.contains("acoustic") || normalizedMood.contains("quiet") {
      return -0.03
    }

    return 0
  }

  private static func stableHash(_ value: String) -> UInt64 {
    value.utf8.reduce(UInt64(0xcbf29ce484222325)) { partialResult, byte in
      (partialResult ^ UInt64(byte)) &* 0x100000001b3
    }
  }

  private static func unit(_ value: UInt64) -> Double {
    var z = value
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    z = z ^ (z >> 31)
    return Double(z >> 11) / Double(1 << 53)
  }
}

private struct SpectrumAnalysisCacheKey: Hashable {
  let audioURL: URL
  let bandCount: Int
}

private enum SpectrumAnalysisCacheError: Error {
  case downloadFailed
}
