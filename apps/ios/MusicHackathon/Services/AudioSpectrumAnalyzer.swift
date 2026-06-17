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

    let clampedSeconds = max(0, seconds)

    guard clampedSeconds > frames[0].timestamp else {
      return frames[0].bands
    }

    guard clampedSeconds < frames[frames.count - 1].timestamp else {
      return frames[frames.count - 1].bands
    }

    var lowerIndex = 0
    var upperIndex = frames.count - 1

    while lowerIndex + 1 < upperIndex {
      let midpoint = (lowerIndex + upperIndex) / 2

      if frames[midpoint].timestamp <= clampedSeconds {
        lowerIndex = midpoint
      } else {
        upperIndex = midpoint
      }
    }

    let lowerFrame = frames[lowerIndex]
    let upperFrame = frames[upperIndex]
    let frameDuration = max(upperFrame.timestamp - lowerFrame.timestamp, .leastNonzeroMagnitude)
    let fraction = Float((clampedSeconds - lowerFrame.timestamp) / frameDuration)

    return zip(lowerFrame.bands, upperFrame.bands).map { lower, upper in
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
    let hopSize = max(1, fftSize / 4)
    let analysisFrameRate = samples.sampleRate / Double(hopSize)
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

    return AudioSpectrumAnalysis(frames: frames, frameRate: analysisFrameRate, bandCount: bandCount)
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
      return (left * 0.25) + (value * 0.5) + (right * 0.25)
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
    let minimumDecibels: Float = -42

    guard bandPeaks.contains(where: { $0 > 0 }), globalEnergyPeak > 0 else {
      return rawFrames.map { frame in
        AudioSpectrumFrame(
          timestamp: frame.timestamp,
          bands: Array(repeating: 0.12, count: frame.bands.count)
        )
      }
    }

    let normalizedFrames = rawFrames.enumerated().map { frameIndex, frame in
      let energyScale = pow(normalizedDecibels(
        value: frameEnergies[frameIndex],
        peak: globalEnergyPeak,
        minimumDecibels: minimumDecibels
      ), 1.1)
      let normalized = frame.bands.enumerated().map { bandIndex, band in
        let bandPeak = max(bandPeaks[bandIndex], .leastNonzeroMagnitude)
        let bandScale = pow(
          normalizedDecibels(value: band, peak: bandPeak, minimumDecibels: minimumDecibels),
          1.35
        )
        let weightedBand = bandScale * (0.12 + (0.76 * energyScale))
        return max(0.02, min(1, weightedBand))
      }

      return AudioSpectrumFrame(
        timestamp: frame.timestamp,
        bands: smoothedBands(normalized)
      )
    }

    return temporallySmoothedFrames(normalizedFrames)
  }

  private static func normalizedDecibels(
    value: Float,
    peak: Float,
    minimumDecibels: Float
  ) -> Float {
    let ratio = max(value / max(peak, .leastNonzeroMagnitude), 0.000_1)
    let decibels = max(minimumDecibels, 20 * log10(ratio))
    return min(max((decibels - minimumDecibels) / abs(minimumDecibels), 0), 1)
  }

  private static func temporallySmoothedFrames(_ frames: [AudioSpectrumFrame]) -> [AudioSpectrumFrame] {
    guard var previousFrame = frames.first else {
      return []
    }

    var smoothedFrames = [previousFrame]
    smoothedFrames.reserveCapacity(frames.count)

    for frame in frames.dropFirst() {
      let delta = max(frame.timestamp - previousFrame.timestamp, 1.0 / 120.0)
      let attackAlpha = smoothingAlpha(delta: delta, timeConstant: 0.018)
      let releaseAlpha = smoothingAlpha(delta: delta, timeConstant: 0.11)
      let bands = zip(previousFrame.bands, frame.bands).map { previous, target in
        let alpha = target > previous ? attackAlpha : releaseAlpha
        return previous + ((target - previous) * alpha)
      }
      let nextFrame = AudioSpectrumFrame(timestamp: frame.timestamp, bands: bands)
      smoothedFrames.append(nextFrame)
      previousFrame = nextFrame
    }

    return smoothedFrames
  }

  private static func smoothingAlpha(delta: TimeInterval, timeConstant: TimeInterval) -> Float {
    1 - exp(-Float(delta / max(timeConstant, .leastNonzeroMagnitude)))
  }
}
