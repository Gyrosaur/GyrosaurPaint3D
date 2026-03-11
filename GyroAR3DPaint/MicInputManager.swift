import Foundation
import AVFoundation
import Accelerate
import Combine

// MARK: - Input Source Enum
enum DrawingInputSource: String, CaseIterable {
    case gyro = "Gyro"
    case mic  = "Mic"
    case both = "Both"

    var icon: String {
        switch self {
        case .gyro: return "gyroscope"
        case .mic:  return "mic.fill"
        case .both: return "waveform.and.mic"
        }
    }
}

// MARK: - MicInputManager
@MainActor
class MicInputManager: ObservableObject {

    // Public state
    @Published var isRunning  = false
    @Published var amplitude: Float = 0.0   // 0–1 smoothed RMS → brush size
    @Published var gateOpen   = false        // true when above threshold
    @Published var pitchHue:  Float = 0.0   // 0–1 spectral centroid → hue shift

    // Tunable settings
    @Published var threshold:   Float = 0.04   // RMS gate threshold
    @Published var sensitivity: Float = 3.0    // amplitude scale before clamping

    private var audioEngine: AVAudioEngine?
    private var smoothedRMS:  Float = 0.0
    private var smoothedHue:  Float = 0.0

    // Asymmetric envelope for amplitude
    private let attackCoeff:  Float = 0.80
    private let releaseCoeff: Float = 0.93
    // Slow hue smoothing so colour shifts feel musical, not jittery
    private let hueSmooth:    Float = 0.94

    // FFT size must be power-of-2; 1024 gives decent freq resolution
    private let fftSize = 1024
    private var fftSetup: FFTSetup?
    private var window:   [Float] = []

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }

        // Prepare FFT
        let log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup  = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        window    = (0..<fftSize).map { i in
            // Hann window
            0.5 * (1.0 - cos(2.0 * .pi * Float(i) / Float(fftSize - 1)))
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch { print("[MicInputManager] Session error: \(error)"); return }

        let engine = AVAudioEngine()
        let input  = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize),
                         format: format) { [weak self] buf, _ in
            guard let self else { return }
            let rms      = Self.computeRMS(buffer: buf)
            let centroid = self.computeSpectralCentroid(buffer: buf,
                                                        sampleRate: Float(format.sampleRate))
            Task { @MainActor in self.process(rms: rms, centroid: centroid) }
        }

        do {
            try engine.start()
            audioEngine = engine
            isRunning   = true
        } catch { print("[MicInputManager] Engine error: \(error)") }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine  = nil
        if let s = fftSetup { vDSP_destroy_fftsetup(s); fftSetup = nil }
        isRunning    = false
        amplitude    = 0
        gateOpen     = false
        pitchHue     = 0
        smoothedRMS  = 0
        smoothedHue  = 0
    }

    // MARK: - Private

    private func process(rms: Float, centroid: Float) {
        // --- Amplitude envelope ---
        let coeff   = rms > smoothedRMS ? attackCoeff : releaseCoeff
        smoothedRMS = smoothedRMS * coeff + rms * (1.0 - coeff)
        amplitude   = min(1.0, smoothedRMS * sensitivity)
        gateOpen    = smoothedRMS >= threshold

        // --- Spectral centroid → hue (0–1) ---
        // Map 80 Hz–4 kHz log-scale onto 0–1
        // Below threshold we let hue drift back to 0
        if gateOpen && centroid > 0 {
            let logLo:  Float = log2(80)
            let logHi:  Float = log2(4000)
            let logC          = log2(max(80, min(4000, centroid)))
            let rawHue        = (logC - logLo) / (logHi - logLo)   // 0–1
            smoothedHue       = smoothedHue * hueSmooth + rawHue * (1.0 - hueSmooth)
        } else {
            smoothedHue = smoothedHue * 0.97  // slow drift to 0 when silent
        }
        pitchHue = smoothedHue
    }

    // Spectral centroid: weighted mean of frequency bins
    private func computeSpectralCentroid(buffer: AVAudioPCMBuffer, sampleRate: Float) -> Float {
        guard let fftSetup,
              let channelData = buffer.floatChannelData else { return 0 }

        let frames = min(fftSize, Int(buffer.frameLength))
        var samples = [Float](repeating: 0, count: fftSize)
        // Copy first channel, zero-pad if needed
        cblas_scopy(Int32(frames), channelData[0], 1, &samples, 1)

        // Apply Hann window
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))

        // Real FFT
        let halfN   = fftSize / 2
        var real    = [Float](repeating: 0, count: halfN)
        var imag    = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        real.withUnsafeMutableBufferPointer { rPtr in
            imag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!,
                                            imagp: iPtr.baseAddress!)
                samples.withUnsafeBytes { rawBuf in
                    let complexBuf = rawBuf.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complexBuf.baseAddress!, 2, &split,
                               1, vDSP_Length(halfN))
                }
                vDSP_fft_zrip(fftSetup, &split, 1,
                               vDSP_Length(log2(Float(fftSize))),
                               FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Weighted centroid
        let binWidth = sampleRate / Float(fftSize)
        var weightedSum: Float = 0
        var totalMag:    Float = 0
        for i in 0..<halfN {
            let freq = Float(i) * binWidth
            weightedSum += freq * magnitudes[i]
            totalMag    += magnitudes[i]
        }
        guard totalMag > 0 else { return 0 }
        return weightedSum / totalMag
    }

    private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let channels = Int(buffer.format.channelCount)
        let frames   = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for ch in 0..<channels {
            for i in 0..<frames { let s = data[ch][i]; sum += s * s }
        }
        return sqrt(sum / Float(channels * frames))
    }
}
