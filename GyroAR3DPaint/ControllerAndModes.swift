import GameController
import SwiftUI
import Combine
import simd

// MARK: - Xbox Controller Manager

@MainActor
class GameControllerManager: ObservableObject {
    @Published var isConnected = false
    @Published var controllerName: String = ""
    
    // Stick values (-1 to 1)
    @Published var leftStickX: Float = 0
    @Published var leftStickY: Float = 0
    @Published var rightStickX: Float = 0
    @Published var rightStickY: Float = 0
    
    // Triggers (0 to 1)
    @Published var leftTrigger: Float = 0
    @Published var rightTrigger: Float = 0
    
    // D-Pad
    @Published var dpadUp = false
    @Published var dpadDown = false
    @Published var dpadLeft = false
    @Published var dpadRight = false
    
    // Buttons
    @Published var buttonA = false
    @Published var buttonB = false
    @Published var buttonX = false
    @Published var buttonY = false
    @Published var leftBumper = false
    @Published var rightBumper = false
    @Published var menuButton = false  // Xbox menu button (three lines, right)
    @Published var leftStickButton = false  // L3 - stick pressed
    @Published var rightStickButton = false  // R3 - stick pressed
    @Published var optionsButton = false    // View/Options button (left of centre)

    // Still Mode draw gate
    // Käyttää MOLEMPIA LT ja RT — kumpi tahansa toimii
    // toggle-moodi: lyhyt paina = on/off
    // hold-moodi: pitkä paina = piirto kun pohjassa, irrotus = piirto loppuu
    @Published var stillDrawGateActive = false
    @Published var stillDrawHoldMode   = false
    // Seuraa triggerien rising/falling edge erikseen
    private var ltWasPressed = false
    private var rtWasPressed = false
    private var ltPressStart: Date? = nil
    private var rtPressStart: Date? = nil
    private let longPressDuration: TimeInterval = 0.6
    
    // Drawing control
    @Published var isControllerDrawing = false  // LT or RT pressed = draw
    
    // Brush size settings
    let baseBrushMin: Float = 0.002
    let baseBrushMax: Float = 0.052
    let extendedBrushMin: Float = 0.0002  // 0.1x base min
    let extendedBrushMax: Float = 0.104   // 2x base max

    // Sigmoid easing: pienet liikkeet hitaita, iso tatin paine kiihdyttää
    // k=4: maltillinen easing; suurempi k = jyrkempi porras
    static func easedStick(_ x: Float, k: Float = 4.0) -> Float {
        // Sigmoid: 1/(1+e^(-k*(x-0.5))) normalisoituna 0...1
        // Muunnetaan -1...1 → 0...1 → eased → takaisin -1...1
        guard abs(x) > 0.001 else { return 0 }
        let sign: Float = x > 0 ? 1 : -1
        let abs_x = abs(x)
        // Cubic-smoothstep: t³(t(6t-15)+10) — erittäin pehmeä
        let t = abs_x
        let eased = t * t * t * (t * (t * 6 - 15) + 10)
        return sign * eased
    }

    // Computed values for drawing
    var hueShift: Float {
        return GameControllerManager.easedStick(leftStickX) * 0.5
    }

    var saturationShift: Float {
        return (GameControllerManager.easedStick(leftStickY) + 1) / 2
    }

    var opacityValue: Float {
        return max(0.1, (GameControllerManager.easedStick(rightStickY) + 1) / 2)
    }

    var brushSizeModifier: Float {
        return 1 + GameControllerManager.easedStick(rightStickX) * 0.5
    }
    
    // Left stick Y controls brush size:
    // - Bottom (-1) = min size, Top (+1) = max size
    // - When L3 pressed (leftStickButton), range extends
    var controllerBrushSize: Float {
        // Eased stick: smoothstep-käyrä — pienet liikkeet maltillisia
        let raw = (leftStickY + 1) / 2  // 0…1
        let t = GameControllerManager.easedStick(raw * 2 - 1) * 0.5 + 0.5  // eased 0…1
        if leftStickButton {
            return extendedBrushMin + t * (extendedBrushMax - extendedBrushMin)
        } else {
            return baseBrushMin + t * (baseBrushMax - baseBrushMin)
        }
    }
    
    // Yhteinen logiikka molemmille triggereille
    private func handleTriggerGate(pressStart: inout Date?, wasPressed: inout Bool, isNowPressed: Bool) {
        if isNowPressed && !wasPressed {
            // Rising edge — paina alas
            pressStart = Date()
            if stillDrawHoldMode {
                stillDrawGateActive = true
            }
        } else if !isNowPressed && wasPressed {
            // Falling edge — irrotus
            let held = pressStart.map { Date().timeIntervalSince($0) } ?? 0
            pressStart = nil
            if held >= longPressDuration {
                // Pitkä painallus: siirry hold-moodiin, gate kiinni irrotuksessa
                stillDrawHoldMode   = true
                stillDrawGateActive = false
            } else {
                if stillDrawHoldMode {
                    // Hold-moodissa lyhyt painallus: poistu hold-moodista
                    stillDrawHoldMode   = false
                    stillDrawGateActive = false
                } else {
                    // Normaali toggle
                    stillDrawGateActive.toggle()
                }
            }
        }
        wasPressed = isNowPressed
    }

    private var controller: GCController?
    
    init() {
        setupControllerObservers()
        checkForExistingController()
    }
    
    private func setupControllerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected),
            name: .GCControllerDidConnect,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected),
            name: .GCControllerDidDisconnect,
            object: nil
        )
    }
    
    private func checkForExistingController() {
        if let controller = GCController.controllers().first {
            setupController(controller)
        }
    }
    
    @objc private func controllerConnected(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        setupController(controller)
    }
    
    @objc private func controllerDisconnected(_ notification: Notification) {
        Task { @MainActor in
            isConnected = false
            controllerName = ""
            controller = nil
        }
    }
    
    private func setupController(_ controller: GCController) {
        self.controller = controller
        
        Task { @MainActor in
            isConnected = true
            controllerName = controller.vendorName ?? "Controller"
        }
        
        // Extended gamepad (Xbox, PlayStation, etc.)
        if let gamepad = controller.extendedGamepad {
            setupExtendedGamepad(gamepad)
        }
    }
    
    private func setupExtendedGamepad(_ gamepad: GCExtendedGamepad) {
        // Left stick
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                self?.leftStickX = x
                self?.leftStickY = y
            }
        }
        
        // Right stick
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                self?.rightStickX = x
                self?.rightStickY = y
            }
        }
        
        // Triggers - now control drawing on/off
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, _ in
            Task { @MainActor in
                guard let self else { return }
                self.leftTrigger = value
                self.isControllerDrawing = value > 0.1 || self.rightTrigger > 0.1
                // LT = HOLD ONLY — piirto päällä kun pohjassa, ei toggle-logiikkaa
                let pressed = value > 0.3
                if pressed != self.ltWasPressed {
                    self.ltWasPressed = pressed
                    if pressed {
                        self.stillDrawGateActive = true
                    } else {
                        // Irrotus lopettaa aina piirron LT:llä
                        // Poistu myös hold-modesta jos se oli LT:n aktivoima
                        self.stillDrawGateActive = false
                    }
                }
            }
        }

        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
            Task { @MainActor in
                guard let self else { return }
                self.rightTrigger = value
                self.isControllerDrawing = self.leftTrigger > 0.1 || value > 0.1
                // Still Mode gate — rising/falling edge
                let pressed = value > 0.3
                self.handleTriggerGate(pressStart: &self.rtPressStart,
                                       wasPressed: &self.rtWasPressed,
                                       isNowPressed: pressed)
            }
        }
        
        // Left stick button (L3) - extend brush size range
        gamepad.leftThumbstickButton?.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.leftStickButton = pressed
            }
        }
        
        // Right stick button (R3)
        gamepad.rightThumbstickButton?.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.rightStickButton = pressed
            }
        }
        
        // D-Pad
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                self?.dpadUp = y > 0.5
                self?.dpadDown = y < -0.5
                self?.dpadLeft = x < -0.5
                self?.dpadRight = x > 0.5
            }
        }
        
        // Buttons
        gamepad.buttonA.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.buttonA = pressed
            }
        }
        
        gamepad.buttonB.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.buttonB = pressed
            }
        }
        
        gamepad.buttonX.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.buttonX = pressed
            }
        }
        
        gamepad.buttonY.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.buttonY = pressed
            }
        }
        
        gamepad.leftShoulder.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.leftBumper = pressed
            }
        }
        
        gamepad.rightShoulder.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.rightBumper = pressed
            }
        }
        
        // Menu button (Xbox button with three lines, right side)
        gamepad.buttonMenu.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.menuButton = pressed
            }
        }
        // Still Mode gate on RT-triggerillä
        gamepad.buttonOptions?.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.optionsButton = pressed
            }
        }
    }
}

// MARK: - Controller Status View

struct ControllerStatusView: View {
    @ObservedObject var controller: GameControllerManager
    
    var body: some View {
        if controller.isConnected {
            HStack(spacing: 4) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                
                // Show active controls
                if abs(controller.leftStickX) > 0.1 || abs(controller.leftStickY) > 0.1 {
                    Text("H:\(Int(controller.hueShift * 100))%")
                        .font(.system(size: 8, design: .monospaced))
                }
                
                if abs(controller.rightStickY) > 0.1 {
                    Text("O:\(Int(controller.opacityValue * 100))%")
                        .font(.system(size: 8, design: .monospaced))
                }
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.4))
            .cornerRadius(6)
        }
    }
}

// MARK: - Drawing Mode Enum

enum DrawingMode: String, CaseIterable {
    case freehand = "Freehand"
    case straightLine = "Straight Line"
    case arc = "Arc"
    case crescendo = "Crescendo"
    case diminuendo = "Diminuendo"
    
    var icon: String {
        switch self {
        case .freehand: return "scribble"
        case .straightLine: return "line.diagonal"
        case .arc: return "circle.bottomhalf.filled"
        case .crescendo: return "triangle.fill"
        case .diminuendo: return "triangle"
        }
    }
}

// MARK: - Drawing Mode Picker

struct DrawingModePicker: View {
    @Binding var selectedMode: DrawingMode
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Drawing Mode")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            ForEach(DrawingMode.allCases, id: \.self) { mode in
                Button(action: {
                    selectedMode = mode
                    onDismiss()
                }) {
                    HStack {
                        Image(systemName: mode.icon)
                            .frame(width: 24)
                        Text(mode.rawValue)
                        Spacer()
                        if selectedMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(10)
                    .background(selectedMode == mode ? Color.white.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .frame(width: 200)
        .background(Color(white: 0.15, opacity: 0.95))
        .cornerRadius(16)
    }
}

// MARK: - Stroke Selection Manager

@MainActor
class StrokeSelectionManager: ObservableObject {
    @Published var selectedStrokeIDs: Set<UUID> = []
    @Published var isSelectionMode = false  // Selector tool on/off
    @Published var longPressProgress: Float = 0
    @Published var isMultiSelecting = false  // Long press + drag
    
    private var longPressTimer: Timer?
    private var longPressStartTime: Date?
    private let longPressDuration: TimeInterval = 0.5
    private var longPressStartPosition: SIMD3<Float>?
    
    var hasSelection: Bool { !selectedStrokeIDs.isEmpty }
    
    func startLongPress(at position: SIMD3<Float>, strokes: [Stroke]) {
        guard isSelectionMode else { return }
        longPressStartTime = Date()
        longPressStartPosition = position
        longPressProgress = 0
        
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.longPressStartTime else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                self.longPressProgress = Float(min(1.0, elapsed / self.longPressDuration))
                
                if elapsed >= self.longPressDuration && !self.isMultiSelecting {
                    self.completeLongPress(at: position, strokes: strokes)
                }
            }
        }
    }
    
    func updateLongPress(at position: SIMD3<Float>, strokes: [Stroke]) {
        guard isSelectionMode, isMultiSelecting else { return }
        // Lisää kaikki stroket start -> current välillä
        selectStrokesInRange(from: longPressStartPosition ?? position, to: position, strokes: strokes)
    }
    
    func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressStartTime = nil
        longPressStartPosition = nil
        longPressProgress = 0
        isMultiSelecting = false
    }
    
    private func completeLongPress(at position: SIMD3<Float>, strokes: [Stroke]) {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressProgress = 0
        isMultiSelecting = true
        
        // Select stroke at position
        if let stroke = findClosestStroke(at: position, strokes: strokes) {
            selectedStrokeIDs.insert(stroke.id)
            NotificationCenter.default.post(name: .strokeSelected, object: stroke)
        }
    }
    
    func endLongPress() {
        isMultiSelecting = false
        longPressStartPosition = nil
    }
    
    private func selectStrokesInRange(from start: SIMD3<Float>, to end: SIMD3<Float>, strokes: [Stroke]) {
        let threshold: Float = 0.15
        for stroke in strokes {
            for point in stroke.points {
                // Check if point is near the line from start to end
                let dist = distanceToLineSegment(point: point.position, lineStart: start, lineEnd: end)
                if dist < threshold {
                    selectedStrokeIDs.insert(stroke.id)
                    break
                }
            }
        }
    }
    
    private func distanceToLineSegment(point: SIMD3<Float>, lineStart: SIMD3<Float>, lineEnd: SIMD3<Float>) -> Float {
        let line = lineEnd - lineStart
        let len2 = simd_length_squared(line)
        if len2 < 0.0001 { return simd_distance(point, lineStart) }
        
        let t = max(0, min(1, simd_dot(point - lineStart, line) / len2))
        let projection = lineStart + t * line
        return simd_distance(point, projection)
    }
    
    func selectStroke(at position: SIMD3<Float>, strokes: [Stroke]) -> Stroke? {
        return findClosestStroke(at: position, strokes: strokes)
    }
    
    private func findClosestStroke(at position: SIMD3<Float>, strokes: [Stroke]) -> Stroke? {
        var closestStroke: Stroke?
        var closestDistance: Float = .infinity
        let threshold: Float = 0.15
        
        for stroke in strokes {
            for point in stroke.points {
                let distance = simd_distance(position, point.position)
                if distance < threshold && distance < closestDistance {
                    closestDistance = distance
                    closestStroke = stroke
                }
            }
        }
        
        return closestStroke
    }
    
    func clearSelection() {
        selectedStrokeIDs.removeAll()
        NotificationCenter.default.post(name: .selectionCleared, object: nil)
    }
    
    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            clearSelection()
        }
    }
}

extension Notification.Name {
    static let strokeSelected = Notification.Name("strokeSelected")
    static let selectionCleared = Notification.Name("selectionCleared")
}

// MARK: - Straight Line Drawing State

class StraightLineState: ObservableObject {
    @Published var startPoint: SIMD3<Float>?
    @Published var endPoint: SIMD3<Float>?
    @Published var isDrawing = false
    
    func reset() {
        startPoint = nil
        endPoint = nil
        isDrawing = false
    }
    
    func generateLinePoints(brushSize: Float, color: Color, brushType: BrushType, opacity: Float = 1.0, gradientValue: Float = 0) -> [StrokePoint] {
        guard let start = startPoint, let end = endPoint else { return [] }
        
        let distance = simd_distance(start, end)
        let pointCount = max(2, Int(distance / 0.015)) // fewer points = lighter rendering
        var points: [StrokePoint] = []
        
        for i in 0..<pointCount {
            let t = Float(i) / Float(pointCount - 1)
            let position = start + (end - start) * t
            let point = StrokePoint(
                position: position,
                brushSize: brushSize,
                timestamp: Date().timeIntervalSince1970,
                opacity: opacity,
                color: color,
                gradientValue: gradientValue
            )
            points.append(point)
        }
        
        return points
    }
    
    // Arc: kaari joka kulkee start -> end mutta kaartuu ylöspäin
    func generateArcPoints(brushSize: Float, color: Color, brushType: BrushType, opacity: Float = 1.0, gradientValue: Float = 0) -> [StrokePoint] {
        guard let start = startPoint, let end = endPoint else { return [] }
        
        let distance = simd_distance(start, end)
        let pointCount = max(10, Int(distance / 0.005))
        var points: [StrokePoint] = []
        
        // Kaaren korkeus on 30% etäisyydestä
        let arcHeight = distance * 0.3
        
        // Laske suunta ja kohtisuora vektori
        let direction = simd_normalize(end - start)
        let up = SIMD3<Float>(0, 1, 0)
        var perpendicular = simd_cross(direction, up)
        if simd_length(perpendicular) < 0.01 {
            perpendicular = SIMD3<Float>(1, 0, 0)
        }
        perpendicular = simd_normalize(perpendicular)
        
        // Käytä y-akselia kaaren korkeudeksi
        let arcUp = SIMD3<Float>(0, 1, 0)
        
        for i in 0..<pointCount {
            let t = Float(i) / Float(pointCount - 1)
            // Lineaarinen positio
            let linearPos = start + (end - start) * t
            // Sini-kaari ylöspäin (0 alussa, max keskellä, 0 lopussa)
            let arcOffset = sin(t * .pi) * arcHeight
            let position = linearPos + arcUp * arcOffset
            
            let point = StrokePoint(
                position: position,
                brushSize: brushSize,
                timestamp: Date().timeIntervalSince1970,
                opacity: opacity,
                color: color,
                gradientValue: gradientValue
            )
            points.append(point)
        }
        
        return points
    }
    
    // Crescendo: ohut alussa, paksu lopussa (V-muoto)
    func generateCrescendoPoints(brushSize: Float, color: Color, brushType: BrushType, opacity: Float = 1.0, gradientValue: Float = 0) -> [StrokePoint] {
        guard let start = startPoint, let end = endPoint else { return [] }
        
        let distance = simd_distance(start, end)
        let pointCount = max(2, Int(distance / 0.005))
        var points: [StrokePoint] = []
        
        // Isompi max koko
        let minSize = brushSize * 0.02
        let maxSize = brushSize * 1.5
        
        for i in 0..<pointCount {
            let t = Float(i) / Float(pointCount - 1)
            let position = start + (end - start) * t
            // Koko kasvaa lineaarisesti
            let size = minSize + (maxSize - minSize) * t
            
            let point = StrokePoint(
                position: position,
                brushSize: size,
                timestamp: Date().timeIntervalSince1970,
                opacity: opacity,
                color: color,
                gradientValue: gradientValue
            )
            points.append(point)
        }
        
        return points
    }
    
    // Diminuendo: paksu alussa, ohut lopussa
    func generateDiminuendoPoints(brushSize: Float, color: Color, brushType: BrushType, opacity: Float = 1.0, gradientValue: Float = 0) -> [StrokePoint] {
        guard let start = startPoint, let end = endPoint else { return [] }
        
        let distance = simd_distance(start, end)
        let pointCount = max(2, Int(distance / 0.005))
        var points: [StrokePoint] = []
        
        // Isompi max koko
        let maxSize = brushSize * 1.5
        let minSize = brushSize * 0.02
        
        for i in 0..<pointCount {
            let t = Float(i) / Float(pointCount - 1)
            let position = start + (end - start) * t
            // Koko pienenee lineaarisesti
            let size = maxSize - (maxSize - minSize) * t
            
            let point = StrokePoint(
                position: position,
                brushSize: size,
                timestamp: Date().timeIntervalSince1970,
                opacity: opacity,
                color: color,
                gradientValue: gradientValue
            )
            points.append(point)
        }
        
        return points
    }
}
