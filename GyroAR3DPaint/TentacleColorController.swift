import SwiftUI
import Combine

// MARK: - TentacleColorController
// Ohjaa Tentacle-brushin per-point väriä reaaliajassa piirron aikana.
// Lähde: Xbox oikea tatti (X-akseli) tai mikrofoni (pitch/amplitudi)
// Interpoloi kahden käyttäjän valitseman värin välillä.

enum TentacleColorSource: String, CaseIterable {
    case off         = "Off"
    case rightStickX = "Xbox Right Stick X"
    case rightStickY = "Xbox Right Stick Y"
    case micPitch    = "Mic Pitch"
    case micAmplitude = "Mic Amplitude"
}

@MainActor
class TentacleColorController: ObservableObject {
    @Published var source:    TentacleColorSource = .off
    @Published var colorA:    Color = .cyan
    @Published var colorB:    Color = Color(hue: 0.85, saturation: 1, brightness: 1)
    // Kynnys alle jonka arvo = colorA (off-piste)
    @Published var threshold: Float = 0.15
    // Release-nopeus: kuinka nopeasti palataan A:han kynnyksen alle mennessä (0…1 per frame)
    @Published var releaseSpeed: Float = 0.12

    // Nykyinen interpolaatioarvo 0=A, 1=B — päivitetään per-tick
    private(set) var currentT: Float = 0.0
    // Smoothattu input-arvo
    private var smoothedInput: Float = 0.0

    // Päivitetään piirtoloopissa joka tick
    func update(controller: GameControllerManager?, micPitch: Float, micAmplitude: Float) {
        guard source != .off else { currentT = 0; return }

        let raw: Float
        switch source {
        case .off:           raw = 0
        case .rightStickX:   raw = (controller?.rightStickX ?? 0 + 1) / 2
        case .rightStickY:   raw = (controller?.rightStickY ?? 0 + 1) / 2
        case .micPitch:      raw = micPitch
        case .micAmplitude:  raw = micAmplitude
        }

        // Threshold: alle kynnyksen → target = 0 (colorA)
        let target: Float = raw > threshold ? (raw - threshold) / (1.0 - threshold) : 0.0

        // Jäykkä release jos kynnyksen alle, muuten seuraa nopeasti
        if target > smoothedInput {
            // Ylöspäin: seuraa suoraan (nopea respons)
            smoothedInput = target
        } else {
            // Alaspäin: release-nopeus (pehmeä palautus)
            smoothedInput = max(target, smoothedInput - releaseSpeed)
        }
        currentT = smoothedInput
    }

    // Laskee nykyisen värin interpolaatiosta
    var currentColor: Color {
        guard source != .off, currentT > 0.001 else { return colorA }
        return interpolate(colorA, colorB, t: CGFloat(currentT))
    }

    // Laskee värin per-point käyttäen tentacleHue-arvoa (tallennettu StrokePointiin)
    func color(for t: Float) -> Color {
        guard source != .off else { return colorA }
        return interpolate(colorA, colorB, t: CGFloat(t))
    }

    private func interpolate(_ a: Color, _ b: Color, t: CGFloat) -> Color {
        var h1: CGFloat = 0, s1: CGFloat = 0, v1: CGFloat = 0, a1: CGFloat = 0
        var h2: CGFloat = 0, s2: CGFloat = 0, v2: CGFloat = 0, a2: CGFloat = 0
        UIColor(a).getHue(&h1, saturation: &s1, brightness: &v1, alpha: &a1)
        UIColor(b).getHue(&h2, saturation: &s2, brightness: &v2, alpha: &a2)
        // Hue interpolaatio lyhintä reittiä
        var dh = h2 - h1
        if dh > 0.5 { dh -= 1 }
        if dh < -0.5 { dh += 1 }
        let h = (h1 + dh * t).truncatingRemainder(dividingBy: 1)
        return Color(hue: h < 0 ? h + 1 : h,
                     saturation: s1 + (s2 - s1) * t,
                     brightness: v1 + (v2 - v1) * t)
    }
}
