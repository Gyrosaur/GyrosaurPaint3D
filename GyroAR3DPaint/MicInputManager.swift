import Foundation
import AVFoundation
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
    @Published var amplitude: Float = 0.0   // 0–1, smoothed RMS
    @Published var gateOpen   = false        // true when above threshold

    // Tunable settings
    @Published var threshold:    Float = 0.04   // RMS gate threshold
    @Published var sensitivity:  Float = 3.0    // scale before clamping

    private var audioEngine: AVAudioEngine?
    private var smoothed: Float = 0.0

    // Asymmetric smoothing
    private let attackCoeff:  Float = 0.80   // fast attack
    private let releaseCoeff: Float = 0.93   // slow release (sustain tail)

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[MicInputManager] Session setup error: \(error)")
            return
        }

        let engine = AVAudioEngine()
        let input  = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buf, _ in
            guard let self else { return }
            let rms = Self.computeRMS(buffer: buf)
            Task { @MainActor in self.processAmplitude(rms) }
        }

        do {
            try engine.start()
            audioEngine = engine
            isRunning   = true
        } catch {
            print("[MicInputManager] Engine start error: \(error)")
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRunning   = false
        amplitude   = 0
        gateOpen    = false
        smoothed    = 0
    }

    // MARK: - Private

    private func processAmplitude(_ raw: Float) {
        let coeff = raw > smoothed ? attackCoeff : releaseCoeff
        smoothed  = smoothed * coeff + raw * (1.0 - coeff)

        amplitude = min(1.0, smoothed * sensitivity)
        gateOpen  = smoothed >= threshold
    }

    private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let channels = Int(buffer.format.channelCount)
        let frames   = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        for ch in 0..<channels {
            for i in 0..<frames {
                let s = data[ch][i]; sum += s * s
            }
        }
        return sqrt(sum / Float(channels * frames))
    }
}
