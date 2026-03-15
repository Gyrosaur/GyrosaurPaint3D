import SwiftUI
import Combine

// MARK: - Controllable parameters
enum InputParameter: String, CaseIterable {
    case none       = "None"
    case brushSize  = "Brush Size"
    case opacity    = "Opacity"
    case hueShift   = "Hue Shift"
    case distance   = "Drawing Distance"
    case colorIndex = "Camera Palette Index"
}

// MARK: - Input sources
enum InputChannel: String, CaseIterable {
    case none        = "None"
    case phoneGyro   = "Phone Gyro"
    case airPodsGyro = "AirPods"
    case mic         = "Microphone"
    case leftSlider  = "Left Slider"
    case ltTrigger   = "Xbox LT"
    case rtTrigger   = "Xbox RT"
    case rightStickX = "Xbox Right Stick X"
    case rightStickY = "Xbox Right Stick Y"
    case leftStickX  = "Xbox Left Stick X"
    case leftStickY  = "Xbox Left Stick Y"

    var icon: String {
        switch self {
        case .none:        return "minus"
        case .phoneGyro:   return "rotate.3d"
        case .airPodsGyro: return "airpodspro"
        case .mic:         return "mic.fill"
        case .leftSlider:  return "slider.vertical.3"
        case .ltTrigger:   return "l2.button.roundedtop.fill"
        case .rtTrigger:   return "r2.button.roundedtop.fill"
        case .rightStickX: return "r.joystick.fill"
        case .rightStickY: return "r.joystick.fill"
        case .leftStickX:  return "l.joystick.fill"
        case .leftStickY:  return "l.joystick.fill"
        }
    }
}

// MARK: - AR Camera Parameters
struct ARCameraParams {
    var exposureOffset: Float = 0
    var autoWhiteBalance: Bool = true
    var contrast:       Float = 1.0
    var brightness:     Float = 0.0
    var saturation:     Float = 1.0
    var grainAmount:    Float = 0.0
    var vignetteAmount: Float = 0.0
    var invertColors:   Bool  = false
}

// MARK: - Parameter → Source mapping
struct ParameterMapping {
    var source: InputChannel = .none
    var scale:  Float        = 1.0
}

@MainActor
class InputSettingsManager: ObservableObject {
    // Toiminnot → lähteet (kaikki oletuksena None)
    @Published var brushSizeSource  = ParameterMapping(source: .none)
    @Published var opacitySource    = ParameterMapping(source: .leftSlider)
    @Published var hueShiftSource   = ParameterMapping(source: .none)
    @Published var distanceSource   = ParameterMapping(source: .none)
    @Published var colorIndexSource = ParameterMapping(source: .none)

    // Draw gate — mitä lähde avaa piirron
    @Published var drawGateSource: InputChannel = .none

    // AR Camera Parameters
    @Published var cameraParams = ARCameraParams()

    // Kaikki lähteet jotka ovat jo käytössä jossain mappingissa
    var usedSources: Set<InputChannel> {
        var used: Set<InputChannel> = []
        for m in [brushSizeSource, opacitySource, hueShiftSource, distanceSource, colorIndexSource] {
            if m.source != .none { used.insert(m.source) }
        }
        if drawGateSource != .none { used.insert(drawGateSource) }
        return used
    }

    // Kaikki toiminnot listana UI:ta varten
    var allMappings: [(label: String, icon: String, binding: Binding<ParameterMapping>)] {
        [
            ("Brush Size",  "circle.fill",               binding(\.brushSizeSource)),
            ("Opacity",     "circle.lefthalf.filled",     binding(\.opacitySource)),
            ("Hue Shift",   "paintpalette.fill",          binding(\.hueShiftSource)),
            ("Distance",    "arrow.up.and.down.and.sparkles", binding(\.distanceSource)),
            ("Color Index", "camera.aperture",            binding(\.colorIndexSource)),
        ]
    }

    func binding(_ kp: ReferenceWritableKeyPath<InputSettingsManager, ParameterMapping>) -> Binding<ParameterMapping> {
        Binding(get: { self[keyPath: kp] }, set: { self[keyPath: kp] = $0 })
    }

    // MARK: - Apply per frame
    func applyAll(to engine: DrawingEngine, controller: GameControllerManager?) {
        applyMapping(brushSizeSource, controller: controller) { v in
            engine.brushSize = engine.brushSizeMin + v * (engine.brushSizeMax - engine.brushSizeMin)
        }
        applyMapping(opacitySource, controller: controller) { v in
            engine.opacity = max(0.05, min(1.0, v))
        }
        applyMapping(hueShiftSource, controller: controller) { v in
            engine.hueShift = (v - 0.5) * 0.6
        }
        applyMapping(distanceSource, controller: controller) { v in
            engine.drawingDistanceOffset = max(0, min(1, v))
        }
        applyMapping(colorIndexSource, controller: controller) { v in
            engine.cameraColorDrivenIndex = v
        }
    }

    // Draw gate evalutaatio — palauttaa true jos gate-lähde on aktiivinen
    func evaluateDrawGate(controller: GameControllerManager?) -> Bool {
        switch drawGateSource {
        case .none:        return false
        case .ltTrigger:   return (controller?.leftTrigger  ?? 0) > 0.3
        case .rtTrigger:   return (controller?.rightTrigger ?? 0) > 0.3
        case .mic:         return false  // mic gate on erillinen
        case .phoneGyro, .airPodsGyro, .leftSlider,
             .rightStickX, .rightStickY, .leftStickX, .leftStickY:
            return false  // analogiset lähteet eivät toimi gate-lähteenä suoraan
        }
    }

    private func applyMapping(_ m: ParameterMapping, controller: GameControllerManager?,
                               write: (Float) -> Void) {
        guard m.source != .none, let v = rawValue(for: m.source, controller: controller) else { return }
        write(max(0, min(1, v * m.scale)))
    }

    private func rawValue(for source: InputChannel, controller: GameControllerManager?) -> Float? {
        switch source {
        case .none:        return nil
        case .phoneGyro:   return nil  // käsitellään applyGyro:ssa
        case .airPodsGyro: return nil  // käsitellään applyGyro:ssa
        case .mic:         return nil  // käsitellään erikseen
        case .leftSlider:  return nil  // slider lukee suoraan
        case .ltTrigger:   return controller?.leftTrigger
        case .rtTrigger:   return controller?.rightTrigger
        case .rightStickX: return controller.map { ($0.rightStickX + 1) / 2 }
        case .rightStickY: return controller.map { ($0.rightStickY + 1) / 2 }
        case .leftStickX:  return controller.map { ($0.leftStickX  + 1) / 2 }
        case .leftStickY:  return controller.map { ($0.leftStickY  + 1) / 2 }
        }
    }

    // Gyro-arvojen reititys (AirPods / Phone — kutsutaan sensoriCB:sta)
    func applyGyro(value: Float, isAirPods: Bool, to engine: DrawingEngine) {
        let src: InputChannel = isAirPods ? .airPodsGyro : .phoneGyro
        if hueShiftSource.source == src {
            engine.hueShift = (value - 0.5) * 0.6 * hueShiftSource.scale
        }
        if brushSizeSource.source == src {
            engine.brushSize = engine.brushSizeMin + value * (engine.brushSizeMax - engine.brushSizeMin)
        }
        if opacitySource.source == src {
            engine.opacity = max(0.05, min(1.0, value * opacitySource.scale))
        }
    }

    func applyWatchCrownHue(_ hue: Float, to engine: DrawingEngine) {
        engine.setColorFromHSB(hue: CGFloat(hue), saturation: 0.9, brightness: 1.0)
    }
}
