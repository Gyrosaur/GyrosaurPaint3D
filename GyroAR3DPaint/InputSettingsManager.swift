import SwiftUI
import Combine

// MARK: - Input Parameter (what an input controls)
enum InputParameter: String, CaseIterable {
    case none          = "None"
    case brushSize     = "Brush Size"
    case opacity       = "Opacity"
    case hueShift      = "Hue Shift"
    case distance      = "Drawing Distance"
    case colorIndex    = "Camera Palette Index"
}

// MARK: - Input Sources (the four controllable inputs)
enum InputChannel: String, CaseIterable {
    case phoneGyro   = "Phone Gyro"
    case airPodsGyro = "AirPods Gyro"
    case mic         = "Microphone"
    case leftSlider  = "Left Slider"

    var icon: String {
        switch self {
        case .phoneGyro:   return "rotate.3d"
        case .airPodsGyro: return "airpodspro"
        case .mic:         return "mic.fill"
        case .leftSlider:  return "slider.vertical.3"
        }
    }
}

// MARK: - InputSettingsManager
class InputSettingsManager: ObservableObject {
    // One mapping per input channel
    @Published var phoneGyroParam:   InputParameter = .none
    @Published var airPodsGyroParam: InputParameter = .hueShift
    @Published var micParam:         InputParameter = .brushSize
    @Published var leftSliderParam:  InputParameter = .opacity

    func param(for channel: InputChannel) -> Binding<InputParameter> {
        switch channel {
        case .phoneGyro:   return Binding(get: { self.phoneGyroParam },   set: { self.phoneGyroParam   = $0 })
        case .airPodsGyro: return Binding(get: { self.airPodsGyroParam }, set: { self.airPodsGyroParam = $0 })
        case .mic:         return Binding(get: { self.micParam },         set: { self.micParam         = $0 })
        case .leftSlider:  return Binding(get: { self.leftSliderParam },  set: { self.leftSliderParam  = $0 })
        }
    }

    /// Apply a normalised value (0–1) from a channel to the drawing engine.
    func apply(channel: InputChannel, value: Float, to engine: DrawingEngine) {
        let param: InputParameter
        switch channel {
        case .phoneGyro:   param = phoneGyroParam
        case .airPodsGyro: param = airPodsGyroParam
        case .mic:         param = micParam
        case .leftSlider:  param = leftSliderParam
        }
        guard param != .none else { return }
        write(param: param, value: value, to: engine)
    }

    private func write(param: InputParameter, value: Float, to engine: DrawingEngine) {
        switch param {
        case .none: break
        case .brushSize:
            engine.brushSize = engine.brushSizeMin
                + value * (engine.brushSizeMax - engine.brushSizeMin)
        case .opacity:
            engine.opacity = max(0.05, value)
        case .hueShift:
            engine.hueShift = (value - 0.5) * 0.6
        case .distance:
            engine.drawingDistanceOffset = value
        case .colorIndex:
            engine.cameraColorDrivenIndex = value
        }
    }
}
