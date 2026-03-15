// MARK: - Apple Watch Extension for GyrosaurPaint3D
// Lisää tämä Watch App -targetiin (WatchKit Extension tai watchOS App).
//
// VAATIMUKSET:
// 1. Xcodessa: File → New → Target → watchOS → Watch App (tai Watch App for iOS App)
// 2. Lisää WatchConnectivity.framework molempiin targeteihin
// 3. Kopioi tämä tiedosto Watch-targetiin
// 4. iPhone-puoli (WatchMotionManager.swift) on jo valmis vastaanottamaan
//
// TOIMINTA:
// - Lähettää gyro-asennon (roll/pitch/yaw) iPhonelle 30 Hz
// - Lähettää crown-deltan (digitaalinen kruunu) portaattomaksi väriselauksi
// - Käyttöliittymä: iso vihreä nappi käynnistää/pysäyttää lähetyksen

import SwiftUI
import WatchKit
import CoreMotion
import WatchConnectivity

@main
struct GyrosaurWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}

struct WatchContentView: View {
    @StateObject var sender = WatchSender()

    var body: some View {
        VStack(spacing: 12) {
            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(sender.isPhoneReachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(sender.isPhoneReachable ? "Phone OK" : "No Phone")
                    .font(.system(size: 12))
                    .foregroundColor(sender.isPhoneReachable ? .green : .red)
            }

            // Big toggle button
            Button {
                sender.isStreaming ? sender.stop() : sender.start()
            } label: {
                ZStack {
                    Circle()
                        .fill(sender.isStreaming ? Color.orange : Color.green)
                        .frame(width: 70, height: 70)
                    Image(systemName: sender.isStreaming ? "stop.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            // Gyro readout
            if sender.isStreaming {
                VStack(spacing: 3) {
                    GyroRow(label: "R", value: sender.roll)
                    GyroRow(label: "P", value: sender.pitch)
                    GyroRow(label: "Y", value: sender.yaw)
                }
            }

            // Crown colour preview
            Circle()
                .fill(Color(hue: Double(sender.crownHue), saturation: 0.9, brightness: 1.0))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
        .padding()
        // Digital Crown controls hue
        .focusable()
        .digitalCrownRotation($sender.crownValue,
                               from: 0, through: 1,
                               by: 0.005,
                               sensitivity: .medium,
                               isContinuous: true,
                               isHapticFeedbackEnabled: true)
        .onChange(of: sender.crownValue) { _, newValue in
            sender.crownHue = Float(newValue.truncatingRemainder(dividingBy: 1.0))
            if sender.crownHue < 0 { sender.crownHue += 1 }
            sender.sendCrownDelta()
        }
    }
}

struct GyroRow: View {
    let label: String
    let value: Float
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 14)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2).fill(Color.cyan.opacity(0.7))
                        .frame(width: g.size.width * CGFloat((value + 1) / 2))
                }
            }
            .frame(height: 6)
            Text(String(format: "%.2f", value))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36)
        }
    }
}

// MARK: - WatchSender

@MainActor
class WatchSender: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isStreaming = false
    @Published var isPhoneReachable = false
    @Published var roll:  Float = 0
    @Published var pitch: Float = 0
    @Published var yaw:   Float = 0
    @Published var crownValue: Double = 0
    @Published var crownHue:   Float  = 0

    private let motion = CMMotionManager()
    private let queue  = OperationQueue()
    private var lastCrownSent: Float = -99

    override init() {
        super.init()
        queue.maxConcurrentOperationCount = 1
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        isStreaming = true
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] m, _ in
            guard let self, let m else { return }
            let r = Float(max(-1, min(1, m.attitude.roll  / .pi)))
            let p = Float(max(-1, min(1, m.attitude.pitch / .pi)))
            let y = Float(max(-1, min(1, m.attitude.yaw   / .pi)))
            Task { @MainActor in
                self.roll = r; self.pitch = p; self.yaw = y
                self.sendMotion(r: r, p: p, y: y)
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        isStreaming = false
    }

    private func sendMotion(r: Float, p: Float, y: Float) {
        guard WCSession.default.isReachable else { return }
        let msg: [String: Any] = ["roll": Double(r), "pitch": Double(p), "yaw": Double(y)]
        WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: nil)
    }

    func sendCrownDelta() {
        guard WCSession.default.isReachable else { return }
        let delta = crownHue - lastCrownSent
        lastCrownSent = crownHue
        let msg: [String: Any] = ["crownDelta": Double(delta), "crownHue": Double(crownHue)]
        WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: nil)
    }

    // MARK: WCSessionDelegate (watchOS)
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.isPhoneReachable = session.isReachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isPhoneReachable = session.isReachable }
    }

    // watchOS ei vaadi näitä mutta protokollavaatimus on sama
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
