import CoreMotion
import SwiftUI
import Combine
import simd

@MainActor
class AirPodsMotionManager: ObservableObject {
    @Published var isConnected = false
    @Published var roll: Double = 0  // vasen-oikea kallistus (-1...1 normalisoitu)
    @Published var pitch: Double = 0
    @Published var yaw: Double = 0
    @Published var rawRoll: Double = 0  // raaka arvo radiaaneina
    @Published var rawPitch: Double = 0
    @Published var rawYaw: Double = 0
    
    // Värigradientti-arvo: -1 = vasen (vaalea->tumma), 0 = keski (tasainen), 1 = oikea (tumma->vaalea)
    @Published var colorGradientValue: Float = 0

    // Viimeisin raw rotation matrix — käytetään pään suunnan laskemiseen
    // Tästä saadaan "korvien välin" suunta world-spacessa
    @Published var headRotationMatrix: simd_float3x3 = matrix_identity_float3x3
    
    private let headphoneManager = CMHeadphoneMotionManager()
    private var motionQueue = OperationQueue()
    
    init() {
        motionQueue.name = "AirPodsMotionQueue"
        motionQueue.maxConcurrentOperationCount = 1
        startMonitoring()
    }
    
    func startMonitoring() {
        guard headphoneManager.isDeviceMotionAvailable else {
            print("AirPods motion not available")
            return
        }
        
        headphoneManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            
            Task { @MainActor in
                self.isConnected = true
                
                // Raaka arvot
                self.rawRoll = motion.attitude.roll
                self.rawPitch = motion.attitude.pitch
                self.rawYaw = motion.attitude.yaw
                
                // Normalisoidut arvot (-1...1)
                // Roll: vasen kallistus negatiivinen, oikea positiivinen
                // Tyypillinen vaihteluväli noin -0.5...0.5 rad normaalissa käytössä
                let normalizedRoll = max(-1, min(1, motion.attitude.roll / 0.5))
                self.roll = normalizedRoll
                self.pitch = max(-1, min(1, motion.attitude.pitch / 0.5))
                self.yaw = max(-1, min(1, motion.attitude.yaw / Double.pi))
                
                // ColorGradientValue suoraan rollista
                self.colorGradientValue = Float(normalizedRoll)

                // Tallenna rotation matrix pään suunnan laskemiseen
                let r = motion.attitude.rotationMatrix
                self.headRotationMatrix = simd_float3x3(
                    SIMD3<Float>(Float(r.m11), Float(r.m21), Float(r.m31)),
                    SIMD3<Float>(Float(r.m12), Float(r.m22), Float(r.m32)),
                    SIMD3<Float>(Float(r.m13), Float(r.m23), Float(r.m33))
                )
            }
        }
        
        // Tarkkaile yhteyden katkeamista
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisconnect),
            name: NSNotification.Name("CMHeadphoneMotionManagerDidDisconnect"),
            object: headphoneManager
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnect),
            name: NSNotification.Name("CMHeadphoneMotionManagerDidConnect"),
            object: headphoneManager
        )
    }
    
    func stopMonitoring() {
        headphoneManager.stopDeviceMotionUpdates()
        isConnected = false
    }
    
    @objc private func handleDisconnect() {
        Task { @MainActor in
            self.isConnected = false
            self.colorGradientValue = 0
        }
    }
    
    @objc private func handleConnect() {
        Task { @MainActor in
            self.isConnected = true
        }
    }
    
    deinit {
        headphoneManager.stopDeviceMotionUpdates()
    }
}

// MARK: - AirPods Status View
struct AirPodsStatusView: View {
    @ObservedObject var manager: AirPodsMotionManager
    @State private var showDetails = false
    
    var body: some View {
        Button(action: { showDetails.toggle() }) {
            HStack(spacing: 4) {
                // AirPods icon
                Image(systemName: manager.isConnected ? "airpodspro" : "airpodspro")
                    .font(.system(size: 12))
                    .foregroundColor(manager.isConnected ? .green : .gray)
                
                if manager.isConnected {
                    // Pieni gradientin visualisointi
                    GradientIndicator(value: manager.colorGradientValue)
                        .frame(width: 20, height: 8)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.5))
            .cornerRadius(6)
        }
        .popover(isPresented: $showDetails) {
            AirPodsDetailView(manager: manager)
        }
    }
}

// MARK: - Gradient Indicator
struct GradientIndicator: View {
    let value: Float // -1...1
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Tausta
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                
                // Keskiviiva
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 1)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                
                // Indikaattori
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 6, height: 6)
                    .position(
                        x: geo.size.width / 2 + CGFloat(value) * geo.size.width / 2,
                        y: geo.size.height / 2
                    )
            }
        }
    }
}

// MARK: - Detail View
struct AirPodsDetailView: View {
    @ObservedObject var manager: AirPodsMotionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "airpodspro")
                    .foregroundColor(manager.isConnected ? .green : .gray)
                Text(manager.isConnected ? "AirPods Connected" : "AirPods Disconnected")
                    .font(.headline)
            }
            
            if manager.isConnected {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Head Motion Data").font(.subheadline).foregroundColor(.secondary)
                    
                    DataRow(label: "Roll (L/R)", value: manager.roll, raw: manager.rawRoll)
                    DataRow(label: "Pitch (U/D)", value: manager.pitch, raw: manager.rawPitch)
                    DataRow(label: "Yaw", value: manager.yaw, raw: manager.rawYaw)
                    
                    Divider()
                    
                    HStack {
                        Text("Color Gradient")
                        Spacer()
                        Text(String(format: "%.2f", manager.colorGradientValue))
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // Iso gradientti-visualisointi
                    GradientPreview(value: manager.colorGradientValue)
                        .frame(height: 40)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .frame(width: 280)
    }
}

struct DataRow: View {
    let label: String
    let value: Double
    let raw: Double
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            VStack(alignment: .trailing) {
                Text(String(format: "%.2f", value))
                    .font(.system(.body, design: .monospaced))
                Text(String(format: "%.3f rad", raw))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Gradient Preview
struct GradientPreview: View {
    let value: Float
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Näytä millainen gradientti syntyy
                if value < -0.1 {
                    // Vasen: vaalea vasemmalla, tumma oikealla
                    LinearGradient(
                        colors: [.white, .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else if value > 0.1 {
                    // Oikea: tumma vasemmalla, vaalea oikealla
                    LinearGradient(
                        colors: [.black, .white],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    // Keski: tasainen
                    Color.gray
                }
                
                // Intensiteetin osoitin
                Text(gradientDescription)
                    .font(.caption)
                    .foregroundColor(abs(value) > 0.5 ? .white : .black)
            }
        }
    }
    
    var gradientDescription: String {
        if value < -0.7 { return "Light → Dark" }
        if value < -0.3 { return "Light → Mid" }
        if value > 0.7 { return "Dark → Light" }
        if value > 0.3 { return "Mid → Light" }
        return "Uniform"
    }
}
