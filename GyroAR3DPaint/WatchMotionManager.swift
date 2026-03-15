import SwiftUI
import WatchConnectivity
import Combine

// MARK: - Watch Motion Manager
// Vastaanottaa gyroskooppi- ja wrist-direction-dataa Apple Watchilta
// WatchKit app pitää lähettää dataa käyttäen WCSession sendMessage.
// Viesti-avaimet: "roll", "pitch", "yaw", "crownDelta" (kumulatiivinen pyörintä)

@MainActor
class WatchMotionManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isConnected = false
    @Published var isReachable = false

    // Gyro attitude (-1…1 normalised)
    @Published var roll:  Float = 0
    @Published var pitch: Float = 0
    @Published var yaw:   Float = 0

    // Crown / wrist-rotation derived color hue (0…1, wraps)
    @Published var colorHue: Float = 0
    private var crownAccumulator: Float = 0

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isConnected = state == .activated
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.isConnected = false }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in self.isConnected = false }
        WCSession.default.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handleMessage(message) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in self.handleMessage(message) }
        replyHandler(["ok": true])
    }

    private func handleMessage(_ msg: [String: Any]) {
        if let r = msg["roll"]  as? Double { roll  = Float(r) }
        if let p = msg["pitch"] as? Double { pitch = Float(p) }
        if let y = msg["yaw"]   as? Double { yaw   = Float(y) }

        // Crown delta: small signed float per tick; accumulate into hue wheel
        if let d = msg["crownDelta"] as? Double {
            crownAccumulator += Float(d) * 0.01   // sensitivity
            // Wrap 0…1
            crownAccumulator = crownAccumulator.truncatingRemainder(dividingBy: 1.0)
            if crownAccumulator < 0 { crownAccumulator += 1 }
            colorHue = crownAccumulator
        }
    }
}
