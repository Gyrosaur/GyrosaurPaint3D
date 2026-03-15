import SwiftUI
import ARKit
import Combine

// MARK: - Face Input Manager
// ARKit face tracking – suun, leuan ja kulmakarvojen data inputtina.
// Käyttää erillistä ARSession (ei häiritse kamera-ARia).

@MainActor
class FaceInputManager: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isRunning = false
    @Published var isTracking = false

    // Suun liikkeet (0…1)
    @Published var mouthOpen:   Float = 0  // mouthFunnel / jawOpen
    @Published var jawLeft:     Float = 0  // -1…1 (vasemmalle negatiivinen)
    @Published var mouthSmile:  Float = 0  // symmetrinen smile

    // Kulmakarva (0…1)
    @Published var browInnerUp: Float = 0

    // Silmät (0…1, 1 = kiinni)
    @Published var eyeBlinkL:   Float = 0
    @Published var eyeBlinkR:   Float = 0

    // Derived: mouthOpen kynnys piirtolukon triggerinä
    var isMouthGateOpen: Bool { mouthOpen > mouthGateThreshold }
    @Published var mouthGateThreshold: Float = 0.25

    private let session = ARSession()

    override init() {
        super.init()
        session.delegate = self
    }

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else {
            print("FaceInputManager: Face tracking not supported on this device")
            return
        }
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        session.pause()
        isRunning = false
        isTracking = false
        mouthOpen = 0; jawLeft = 0; mouthSmile = 0
        browInnerUp = 0; eyeBlinkL = 0; eyeBlinkR = 0
    }

    // MARK: ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let b = face.blendShapes
        Task { @MainActor in
            self.isTracking = face.isTracked

            func v(_ key: ARFaceAnchor.BlendShapeLocation) -> Float {
                Float(truncating: b[key] ?? 0)
            }

            // Jaw / mouth open: jawOpen is most reliable
            self.mouthOpen  = v(.jawOpen)
            // Jaw side-to-side: jawLeft positive = left, jawRight positive = right
            self.jawLeft    = v(.jawLeft) - v(.jawRight)   // -1…1
            // Smile: average both sides
            self.mouthSmile = (v(.mouthSmileLeft) + v(.mouthSmileRight)) / 2

            // Brows
            self.browInnerUp = (v(.browInnerUp))

            // Blinks
            self.eyeBlinkL = v(.eyeBlinkLeft)
            self.eyeBlinkR = v(.eyeBlinkRight)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in self.isRunning = false; self.isTracking = false }
    }
}

// MARK: - Face Input Status View

struct FaceInputStatusView: View {
    @ObservedObject var manager: FaceInputManager
    @State private var showDetails = false

    var body: some View {
        Button { showDetails.toggle() } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: manager.isTracking
                            ? [Color.purple.opacity(0.4), Color.pink.opacity(0.3), Color.black.opacity(0.5)]
                            : [Color.white.opacity(0.15), Color.gray.opacity(0.3), Color.black.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: manager.isTracking ? "face.smiling.inverse" : "face.smiling")
                    .font(.system(size: 14))
                    .foregroundColor(manager.isTracking ? .purple : .gray)

                // Mouth open mini-bar
                if manager.isTracking {
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.pink.opacity(0.8))
                            .frame(width: CGFloat(manager.mouthOpen) * 28, height: 3)
                            .frame(maxWidth: 28, alignment: .leading)
                    }
                    .frame(width: 32, height: 32)
                    .padding(.bottom, 2)
                }
            }
        }
        .popover(isPresented: $showDetails) {
            FaceInputDetailView(manager: manager)
        }
    }
}

struct FaceInputDetailView: View {
    @ObservedObject var manager: FaceInputManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "face.smiling.inverse").foregroundColor(.purple)
                Text(manager.isTracking ? "Face Tracked" : "No Face")
                    .font(.headline)
                Spacer()
                Button(manager.isRunning ? "Stop" : "Start") {
                    manager.isRunning ? manager.stop() : manager.start()
                }
                .buttonStyle(.bordered)
            }

            if manager.isTracking {
                Divider()
                Group {
                    FaceBarRow(label: "Mouth Open", value: manager.mouthOpen, color: .pink)
                    FaceBarRow(label: "Jaw L/R",    value: (manager.jawLeft + 1) / 2, color: .orange)
                    FaceBarRow(label: "Smile",      value: manager.mouthSmile,  color: .yellow)
                    FaceBarRow(label: "Brow Up",    value: manager.browInnerUp, color: .cyan)
                    FaceBarRow(label: "Blink L",    value: manager.eyeBlinkL,   color: .blue)
                    FaceBarRow(label: "Blink R",    value: manager.eyeBlinkR,   color: .blue)
                }

                Divider()
                HStack {
                    Text("Gate threshold").foregroundColor(.secondary)
                    Slider(value: $manager.mouthGateThreshold, in: 0.05...0.6)
                    Text(String(format: "%.2f", manager.mouthGateThreshold))
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding()
        .frame(width: 280)
    }
}

struct FaceBarRow: View {
    let label: String
    let value: Float
    let color: Color
    var body: some View {
        HStack(spacing: 8) {
            Text(label).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.7))
                        .frame(width: g.size.width * CGFloat(max(0, min(1, value))))
                }
            }
            .frame(height: 10)
            Text(String(format: "%.2f", value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
