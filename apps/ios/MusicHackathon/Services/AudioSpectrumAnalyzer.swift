import Accelerate
import AVFoundation
import Foundation

struct AudioSpectrumAnalysis: Equatable, Sendable {
  let frames: [AudioSpectrumFrame]
  let frameRate: Double
  let bandCount: Int

  static func empty(bandCount: Int, frameRate: Double) -> AudioSpectrumAnalysis {
    AudioSpectrumAnalysis(frames: [], frameRate: frameRate, bandCount: bandCount)
  }

  func bands(at seconds: TimeInterval) -> [Float] {
    guard !frames.isEmpty else {
      return Array(repeating: 0.18, count: bandCount)
    }

    let exactFrame = max(0, seconds) * frameRate
    let lowerIndex = min(Int(exactFrame.rounded(.down)), frames.count - 1)
    let upperIndex = min(lowerIndex + 1, frames.count - 1)
    let fraction = Float(exactFrame - Double(lowerIndex))

    guard lowerIndex != upperIndex else {
      return frames[lowerIndex].bands
    }

    return zip(frames[lowerIndex].bands, frames[upperIndex].bands).map { lower, upper in
      lower + ((upper - lower) * fraction)
    }
  }
}

struct AudioSpectrumFrame: Equatable, Sendable {
  let timestamp: TimeInterval
  let bands: [Float]
}

enum AudioSpectrumAnalyzer {
  static func analyze(
    audioURL: URL,
    bandCount: Int = 40,
    frameRate: Double = 30
  ) async -> AudioSpectrumAnalysis {
    await Task.detached(priority: .userInitiated) {
      do {
        return try makeAnalysis(audioURL: audioURL, bandCount: bandCount, frameRate: frameRate)
      } catch {
        return .empty(bandCount: bandCount, frameRate: frameRate)
      }
    }.value
  }

  private static func makeAnalysis(
    audioURL: URL,
    bandCount: Int,
    frameRate: Double
  ) throws -> AudioSpectrumAnalysis {
    let samples = try mixedMonoSamples(from: audioURL)
    guard !samples.values.isEmpty, bandCount > 0, frameRate > 0 else {
      return .empty(bandCount: bandCount, frameRate: frameRate)
    }

    let fftSize = 2048
    let hopSize = max(1, Int(samples.sampleRate / frameRate))
    let binRanges = logarithmicBinRanges(
      bandCount: bandCount,
      fftSize: fftSize,
      sampleRate: samples.sampleRate
    )
    let frames = spectrumFrames(
      samples: samples.values,
      sampleRate: samples.sampleRate,
      fftSize: fftSize,
      hopSize: hopSize,
      binRanges: binRanges
    )

    return AudioSpectrumAnalysis(frames: frames, frameRate: frameRate, bandCount: bandCount)
  }

  private static func mixedMonoSamples(from audioURL: URL) throws -> (values: [Float], sampleRate: Double) {
    let file = try AVAudioFile(forReading: audioURL)
    let format = file.processingFormat
    let frameCapacity = AVAudioFrameCount(file.length)

    guard
      frameCapacity > 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)
    else {
      return ([], format.sampleRate)
    }

    try file.read(into: buffer)

    guard let channelData = buffer.floatChannelData else {
      return ([], format.sampleRate)
    }

    let frameLength = Int(buffer.frameLength)
    let channelCount = max(1, Int(format.channelCount))
    var mono = Array(repeating: Float.zero, count: frameLength)

    for frame in 0..<frameLength {
      var sample = Float.zero

      for channel in 0..<channelCount {
        sample += channelData[channel][frame]
      }

      mono[frame] = sample / Float(channelCount)
    }

    return (mono, format.sampleRate)
  }

  private static func spectrumFrames(
    samples: [Float],
    sampleRate: Double,
    fftSize: Int,
    hopSize: Int,
    binRanges: [Range<Int>]
  ) -> [AudioSpectrumFrame] {
    guard
      !samples.isEmpty,
      let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))
    else {
      return []
    }

    defer {
      vDSP_destroy_fftsetup(fftSetup)
    }

    var window = Array(repeating: Float.zero, count: fftSize)
    vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

    let halfSize = fftSize / 2
    let lastStart = max(0, samples.count - fftSize)
    var rawFrames: [(timestamp: TimeInterval, bands: [Float])] = []
    rawFrames.reserveCapacity(max(1, samples.count / hopSize))

    var start = 0
    while start <= lastStart {
      let bands = spectrumBands(
        samples: samples,
        start: start,
        fftSize: fftSize,
        fftSetup: fftSetup,
        window: window,
        halfSize: halfSize,
        binRanges: binRanges
      )
      rawFrames.append((timestamp: Double(start) / sampleRate, bands: bands))
      start += hopSize
    }

    if rawFrames.isEmpty {
      let bands = spectrumBands(
        samples: samples,
        start: 0,
        fftSize: fftSize,
        fftSetup: fftSetup,
        window: window,
        halfSize: halfSize,
        binRanges: binRanges
      )
      rawFrames.append((timestamp: 0, bands: bands))
    }

    return normalizedFrames(rawFrames)
  }

  private static func spectrumBands(
    samples: [Float],
    start: Int,
    fftSize: Int,
    fftSetup: FFTSetup,
    window: [Float],
    halfSize: Int,
    binRanges: [Range<Int>]
  ) -> [Float] {
    var frame = Array(repeating: Float.zero, count: fftSize)
    let copyCount = min(fftSize, max(0, samples.count - start))

    if copyCount > 0 {
      frame.replaceSubrange(0..<copyCount, with: samples[start..<(start + copyCount)])
    }

    vDSP.multiply(frame, window, result: &frame)

    var real = Array(repeating: Float.zero, count: halfSize)
    var imaginary = Array(repeating: Float.zero, count: halfSize)
    var magnitudes = Array(repeating: Float.zero, count: halfSize)

    frame.withUnsafeBufferPointer { framePointer in
      real.withUnsafeMutableBufferPointer { realPointer in
        imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
          guard
            let frameBase = framePointer.baseAddress,
            let realBase = realPointer.baseAddress,
            let imaginaryBase = imaginaryPointer.baseAddress
          else {
            return
          }

          var splitComplex = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)
          frameBase.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPointer in
            vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(halfSize))
          }
          vDSP_fft_zrip(
            fftSetup,
            &splitComplex,
            1,
            vDSP_Length(log2(Float(fftSize))),
            FFTDirection(FFT_FORWARD)
          )
          vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
        }
      }
    }

    return binRanges.map { range -> Float in
      guard !range.isEmpty else { return 0 }
      let total = range.reduce(Float.zero) { partial, index in
        partial + magnitudes[min(max(index, 0), magnitudes.count - 1)]
      }
      return sqrt(total / Float(range.count))
    }
  }

  private static func logarithmicBinRanges(
    bandCount: Int,
    fftSize: Int,
    sampleRate: Double
  ) -> [Range<Int>] {
    let nyquist = sampleRate / 2
    let minFrequency = 50.0
    let maxFrequency = min(14_000, nyquist)
    let minLog = log10(minFrequency)
    let maxLog = log10(maxFrequency)

    return (0..<bandCount).map { index in
      let lowerT = Double(index) / Double(bandCount)
      let upperT = Double(index + 1) / Double(bandCount)
      let lowerFrequency = pow(10, minLog + (maxLog - minLog) * lowerT)
      let upperFrequency = pow(10, minLog + (maxLog - minLog) * upperT)
      let lowerBin = max(1, Int((lowerFrequency / sampleRate) * Double(fftSize)))
      let upperBin = max(lowerBin + 1, Int((upperFrequency / sampleRate) * Double(fftSize)))
      return lowerBin..<min(fftSize / 2, upperBin)
    }
  }

  private static func smoothedBands(_ bands: [Float]) -> [Float] {
    guard bands.count > 2 else {
      return bands
    }

    return bands.enumerated().map { index, value in
      let left = bands[max(0, index - 1)]
      let right = bands[min(bands.count - 1, index + 1)]
      return (left * 0.2) + (value * 0.6) + (right * 0.2)
    }
  }

  private static func normalizedFrames(
    _ rawFrames: [(timestamp: TimeInterval, bands: [Float])]
  ) -> [AudioSpectrumFrame] {
    guard let firstFrame = rawFrames.first else {
      return []
    }

    var bandPeaks = Array(repeating: Float.zero, count: firstFrame.bands.count)
    var frameEnergies = Array(repeating: Float.zero, count: rawFrames.count)

    for (frameIndex, frame) in rawFrames.enumerated() {
      var frameEnergy = Float.zero

      for (bandIndex, band) in frame.bands.enumerated() {
        bandPeaks[bandIndex] = max(bandPeaks[bandIndex], band)
        frameEnergy += band
      }

      frameEnergies[frameIndex] = frameEnergy / Float(max(1, frame.bands.count))
    }

    let globalEnergyPeak = frameEnergies.max() ?? 0

    guard bandPeaks.contains(where: { $0 > 0 }), globalEnergyPeak > 0 else {
      return rawFrames.map { frame in
        AudioSpectrumFrame(
          timestamp: frame.timestamp,
          bands: Array(repeating: 0.12, count: frame.bands.count)
        )
      }
    }

    return rawFrames.enumerated().map { frameIndex, frame in
      let energyScale = pow(min(1, frameEnergies[frameIndex] / globalEnergyPeak), 0.35)
      let normalized = frame.bands.enumerated().map { bandIndex, band in
        let bandPeak = max(bandPeaks[bandIndex], .leastNonzeroMagnitude)
        let bandScale = pow(min(1, band / bandPeak), 0.58)
        let weightedBand = bandScale * (0.34 + (0.66 * energyScale))
        return max(0.05, min(1, weightedBand))
      }

      return AudioSpectrumFrame(
        timestamp: frame.timestamp,
        bands: smoothedBands(normalized)
      )
    }
  }
}
