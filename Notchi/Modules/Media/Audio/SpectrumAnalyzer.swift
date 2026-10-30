import Accelerate

/// Turns raw audio into a few smoothed band levels (0…1) for the visualizer.
///
/// 1024-point FFT with 50% overlap and a Hann window. Bands are spaced logarithmically from 60 Hz
/// to 12 kHz, like hearing. Each band is normalized in dB and then auto-gained against its own
/// recent peak, so the bars dance at any volume. Not thread-safe: one instance per audio queue.
final class SpectrumAnalyzer {
    let bandCount: Int

    private let fftSize = 1024
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let bandBins: [Range<Int>]
    /// Samples between published frames (about 30 per second).
    private let emitInterval: Int

    private var pending: [Float] = []
    private var samplesSinceEmit = 0
    private var peaks: [Float]
    private var smoothed: [Float]

    // Scratch buffers, reused so the audio thread never allocates.
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]

    init(sampleRate: Double, bandCount: Int = 4, updatesPerSecond: Double = 30) {
        self.bandCount = bandCount
        fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        emitInterval = max(Int(sampleRate / updatesPerSecond), 1)

        let binWidth = sampleRate / Double(fftSize)
        let low = 60.0, high = min(12_000, sampleRate / 2)
        bandBins = (0..<bandCount).map { band in
            let start = low * pow(high / low, Double(band) / Double(bandCount))
            let end = low * pow(high / low, Double(band + 1) / Double(bandCount))
            let first = max(Int(start / binWidth), 1)
            return first..<max(Int(end / binWidth), first + 1)
        }

        peaks = Array(repeating: 0.3, count: bandCount)
        smoothed = Array(repeating: 0, count: bandCount)
        windowed = Array(repeating: 0, count: fftSize)
        real = Array(repeating: 0, count: fftSize / 2)
        imaginary = Array(repeating: 0, count: fftSize / 2)
        magnitudes = Array(repeating: 0, count: fftSize / 2)
        pending.reserveCapacity(fftSize * 2)
    }

    /// Feeds mono samples. Returns new levels when it's time to publish, otherwise nil.
    func process(_ samples: UnsafeBufferPointer<Float>) -> [Float]? {
        pending.append(contentsOf: samples)
        samplesSinceEmit += samples.count
        var result: [Float]?
        while pending.count >= fftSize {
            let levels = analyzeFrame()
            pending.removeFirst(fftSize / 2)
            if samplesSinceEmit >= emitInterval {
                samplesSinceEmit = 0
                result = levels
            }
        }
        return result
    }

    private func analyzeFrame() -> [Float] {
        pending.withUnsafeBufferPointer { frame in
            vDSP.multiply(UnsafeBufferPointer(rebasing: frame[0..<fftSize]), window, result: &windowed)
        }
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &magnitudes)
            }
        }

        let scale = 1 / Float(fftSize * fftSize)
        for band in 0..<bandCount {
            let bins = bandBins[band].clamped(to: 0..<magnitudes.count)
            var energy: Float = 0
            for bin in bins { energy += magnitudes[bin] }
            energy = energy / Float(max(bins.count, 1)) * scale

            // dB → 0…1 between a noise floor and a loud ceiling.
            let decibels = 10 * log10(energy + 1e-12)
            let level = min(max((decibels + 75) / 60, 0), 1)

            // Auto-gain: compare against this band's slowly decaying recent peak.
            peaks[band] = max(level, peaks[band] * 0.995, 0.3)
            let target = level < 0.05 ? 0 : min(level / peaks[band], 1)

            // Fast attack, slower release, so bars snap up and fall gracefully.
            let rate: Float = target > smoothed[band] ? 0.6 : 0.25
            smoothed[band] += (target - smoothed[band]) * rate
        }
        return smoothed
    }
}
