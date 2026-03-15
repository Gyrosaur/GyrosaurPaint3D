import SwiftUI
import ARKit
import RealityKit
import CoreMotion
import Combine

// MARK: - Draw direction source
enum StillDrawSource: String, CaseIterable {
    case phone      = "Phone Gyro"
    case airPods    = "AirPods"
    case watch      = "Apple Watch"
    case rightStick = "Xbox Right Stick"
    case playback   = "Recorded Clip"
    var icon: String {
        switch self {
        case .phone:      return "rotate.3d"
        case .airPods:    return "airpodspro"
        case .watch:      return "applewatch"
        case .rightStick: return "r.joystick.fill"
        case .playback:   return "play.circle.fill"
        }
    }
}

// MARK: - StillModeView
struct StillModeView: View {
    @StateObject var drawingEngine     = DrawingEngine()
    @StateObject var airPods           = AirPodsMotionManager()
    @StateObject var watchManager      = WatchMotionManager()
    @StateObject var faceManager       = FaceInputManager()
    @StateObject var recorder          = MotionRecorder()
    @StateObject var inputSettings     = InputSettingsManager()
    @StateObject var motionManager     = CMMotionManagerWrapper()
    @StateObject var controllerManager = GameControllerManager()
    @StateObject var sensorBridge      = StillSensorBridge()
    @StateObject var cameraSettings    = CameraSettings()

    var onExitToMenu: (() -> Void)?

    @State private var drawSource:       StillDrawSource = .phone
    @State private var showInputSettings = false
    @State private var showBrushPicker   = false
    @State private var showColorPicker   = false
    @State private var showSwipePanel    = false
    @State private var hideUI            = false
    @State private var arViewRef: ARView?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            StillARCanvas(
                drawingEngine:     drawingEngine,
                controllerManager: controllerManager,
                sensorBridge:      sensorBridge,
                airPods:           airPods,
                recorder:          recorder,
                faceManager:       faceManager,
                inputSettings:     inputSettings,
                cameraSettings:    cameraSettings,
                drawSource:        drawSource,
                arViewRef:         $arViewRef
            )
            .ignoresSafeArea()
            if !hideUI { uiOverlay }
            if hideUI {
                VStack { Spacer()
                    HStack { Spacer()
                        Button { hideUI = false } label: {
                            Image(systemName: "eye.slash.fill").font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.7)).padding(12)
                                .background(Color.black.opacity(0.3)).clipShape(Circle())
                        }
                        .padding(.trailing, 16).padding(.bottom, 30)
                    }
                }
            }
            // Swipe gesture detector oikeassa reunassa
            swipeEdgeDetector
            // Swipe-paneeli
            if showSwipePanel {
                HStack {
                    Spacer()
                    swipePanel.transition(.move(edge: .trailing))
                }
                .ignoresSafeArea()
            }
        }
        .onAppear  { startSensors() }
        .onDisappear { stopSensors() }
        .onChange(of: controllerManager.menuButton) { _, pressed in
            if pressed { withAnimation { hideUI.toggle() } }
        }
    }

    // MARK: - Sensors
    func startSensors() {
        motionManager.start(updateInterval: 1.0/60.0) { roll, pitch, yaw in
            Task { @MainActor in
                self.sensorBridge.phone = (Float(roll), Float(pitch), Float(yaw))
                if self.recorder.isRecording {
                    self.recorder.recordFrame(
                        phone: self.sensorBridge.phone, air: self.sensorBridge.airPods,
                        watch: self.sensorBridge.watch,
                        mouthOpen: self.faceManager.mouthOpen, jawLeft: self.faceManager.jawLeft,
                        browInner: self.faceManager.browInnerUp,
                        eyeBlinkL: self.faceManager.eyeBlinkL, eyeBlinkR: self.faceManager.eyeBlinkR,
                        colorHue: self.watchManager.colorHue)
                }
            }
        }
        airPods.$roll.sink { _ in
            Task { @MainActor in
                self.sensorBridge.airPods = (Float(self.airPods.roll), Float(self.airPods.pitch), Float(self.airPods.yaw))
                let n = Float((self.airPods.colorGradientValue + 1.0) / 2.0)
                self.inputSettings.applyGyro(value: n, isAirPods: true, to: self.drawingEngine)
            }
        }.store(in: &cancellables)
        watchManager.$roll.sink { _ in
            Task { @MainActor in
                self.sensorBridge.watch = (self.watchManager.roll, self.watchManager.pitch, self.watchManager.yaw)
                self.inputSettings.applyWatchCrownHue(self.watchManager.colorHue, to: self.drawingEngine)
            }
        }.store(in: &cancellables)
    }

    func stopSensors() {
        motionManager.stop(); faceManager.stop(); cancellables.removeAll()
    }

    // MARK: - UI Overlay
    var uiOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let exit = onExitToMenu {
                    Button(action: exit) { circleIcon("house.fill", color: .white) }
                }
                // Background cycle (käyttää olemassa olevaa BackgroundMode)
                Button { cameraSettings.backgroundMode = cameraSettings.backgroundMode.next() } label: {
                    circleIcon(cameraSettings.backgroundMode.icon, color: cameraSettings.backgroundMode.tintColor)
                }
                Spacer()
                AirPodsStatusView(manager: airPods)
                if controllerManager.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "gamecontroller.fill").font(.system(size: 11)).foregroundColor(.green)
                        Circle().fill(controllerManager.stillDrawGateActive ? Color.orange : Color.gray.opacity(0.3)).frame(width: 7, height: 7)
                        if controllerManager.stillDrawHoldMode {
                            Image(systemName: "hand.point.up.left.fill").font(.system(size: 9)).foregroundColor(.cyan)
                        }
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.black.opacity(0.4)).cornerRadius(10)
                }
                Button { withAnimation { hideUI = true } } label: { circleIcon("eye.slash", color: .white.opacity(0.6)) }
            }
            .padding(.horizontal, 14).padding(.top, 12)
            Spacer()
            HStack(spacing: 10) {
                // Brush type
                Button { showBrushPicker.toggle() } label: {
                    circleIcon(drawingEngine.selectedBrushType.icon, color: .cyan)
                }
                .popover(isPresented: $showBrushPicker) { brushPickerView }
                // Color / opacity / size
                Button { showColorPicker.toggle() } label: {
                    Circle().fill(drawingEngine.currentColor).frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                }
                .popover(isPresented: $showColorPicker) { colorPickerView }
                Spacer()
                // Input settings
                Button { showInputSettings.toggle() } label: { circleIcon("slider.horizontal.3", color: .white) }
                    .sheet(isPresented: $showInputSettings) {
                        StillInputSettingsView(manager: inputSettings, drawSource: $drawSource)
                    }
                Button { drawingEngine.undoLastStroke() } label: { circleIcon("arrow.uturn.backward", color: .white) }
                Button { drawingEngine.clearAllStrokes() } label: { circleIcon("trash", color: .red.opacity(0.7)) }
            }
            .padding(.horizontal, 14).padding(.bottom, 28)
        }
    }

    // MARK: - Swipe panel
    var swipeEdgeDetector: some View {
        HStack {
            Spacer()
            Rectangle().fill(Color.clear).frame(width: 20).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 20)
                    .onEnded { v in
                        if v.translation.width < -20 { withAnimation(.spring()) { showSwipePanel = true } }
                    })
        }
        .ignoresSafeArea()
        .allowsHitTesting(!showSwipePanel)
    }

    var swipePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button { withAnimation(.spring()) { showSwipePanel = false } } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 14).padding(.top, 16)
            panelSection("DRAW DIRECTION") {
                ForEach(StillDrawSource.allCases, id: \.self) { src in
                    panelRow(src.rawValue, icon: src.icon, active: drawSource == src, color: .cyan) {
                        drawSource = src
                    }
                }
            }
            panelSection("DRAW GATE") {
                panelRow("LT (hold)", icon: "l2.button.roundedtop.fill",
                         active: inputSettings.drawGateSource == .ltTrigger, color: .orange) {
                    inputSettings.drawGateSource = .ltTrigger
                }
                panelRow("RT (toggle/hold)", icon: "r2.button.roundedtop.fill",
                         active: inputSettings.drawGateSource == .rtTrigger, color: .orange) {
                    inputSettings.drawGateSource = .rtTrigger
                }
                panelRow("None (controller toggle)", icon: "minus",
                         active: inputSettings.drawGateSource == .none, color: .gray) {
                    inputSettings.drawGateSource = .none
                }
            }
            panelSection("BACKGROUND") {
                ForEach(BackgroundMode.allCases, id: \.self) { bg in
                    panelRow(bg.rawValue, icon: bg.icon,
                             active: cameraSettings.backgroundMode == bg, color: .purple) {
                        cameraSettings.backgroundMode = bg
                    }
                }
            }
            Spacer()
        }
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .cornerRadius(16, corners: [.topLeft, .bottomLeft])
        .shadow(radius: 20)
        .gesture(DragGesture().onEnded { v in
            if v.translation.width > 30 { withAnimation(.spring()) { showSwipePanel = false } }
        })
    }

    private func panelSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.gray).padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
            content()
        }
    }

    private func panelRow(_ label: String, icon: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).font(.system(size: 13))
                Text(label).font(.system(size: 13))
                Spacer()
                if active { Image(systemName: "checkmark").font(.system(size: 11)) }
            }
            .foregroundColor(active ? color : .white.opacity(0.8))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(active ? color.opacity(0.12) : Color.clear)
        }
    }

    // MARK: - Brush + Color pickers
    var brushPickerView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                ForEach(BrushType.allCases, id: \.self) { brush in
                    Button { drawingEngine.selectedBrushType = brush; showBrushPicker = false } label: {
                        VStack(spacing: 4) {
                            Image(systemName: brush.icon).font(.system(size: 20))
                            Text(brush.rawValue).font(.system(size: 9)).lineLimit(1)
                        }
                        .foregroundColor(drawingEngine.selectedBrushType == brush ? .cyan : .white)
                        .frame(width: 76, height: 56)
                        .background(drawingEngine.selectedBrushType == brush ? Color.cyan.opacity(0.2) : Color.white.opacity(0.07))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(drawingEngine.selectedBrushType == brush ? Color.cyan.opacity(0.5) : Color.clear))
                    }
                }
            }.padding(12)
        }
        .frame(width: 280, height: 320).background(Color(uiColor: .systemBackground).opacity(0.95))
    }

    var colorPickerView: some View {
        VStack(spacing: 10) {
            Text("Color").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.gray)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38))], spacing: 8) {
                ForEach(Array(drawingEngine.availableColors.enumerated()), id: \.offset) { i, color in
                    Button { drawingEngine.selectedColorIndex = i; showColorPicker = false } label: {
                        Circle().fill(color).frame(width: 36, height: 36)
                            .overlay(Circle().stroke(drawingEngine.selectedColorIndex == i ? Color.white : Color.clear, lineWidth: 2))
                    }
                }
            }.padding(.horizontal, 10)
            Divider()
            VStack(spacing: 4) {
                HStack { Text("Size").font(.caption).foregroundColor(.secondary); Spacer()
                    Text(String(format: "%.1fmm", drawingEngine.brushSize * 1000)).font(.system(size: 10, design: .monospaced)) }
                Slider(value: $drawingEngine.brushSize, in: drawingEngine.brushSizeMin...drawingEngine.brushSizeMax).tint(.cyan)
            }.padding(.horizontal, 12)
            VStack(spacing: 4) {
                HStack { Text("Opacity").font(.caption).foregroundColor(.secondary); Spacer()
                    Text("\(Int(drawingEngine.opacity*100))%").font(.system(size: 10, design: .monospaced)) }
                Slider(value: $drawingEngine.opacity, in: 0.05...1.0).tint(.cyan)
            }.padding(.horizontal, 12).padding(.bottom, 10)
        }
        .frame(width: 230).background(Color(uiColor: .systemBackground).opacity(0.95))
    }

    func circleIcon(_ name: String, color: Color) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color.white.opacity(0.15), Color.black.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 34, height: 34)
            Image(systemName: name).font(.system(size: 15)).foregroundColor(color)
        }
    }
}

// MARK: - BackgroundMode extension (lisätään tähän koska ContentView:ssä on perussisältö)
extension BackgroundMode {
    var icon: String {
        switch self {
        case .ar:    return "camera.fill"
        case .black: return "circle.fill"
        case .white: return "circle"
        case .green: return "camera.filters"
        }
    }
    var tintColor: Color {
        switch self {
        case .ar:    return .cyan
        case .black: return .white
        case .white: return .gray
        case .green: return .green
        }
    }
    func next() -> BackgroundMode {
        let all = BackgroundMode.allCases
        guard let i = all.firstIndex(of: self) else { return .ar }
        return all[(i + 1) % all.count]
    }
}

// MARK: - Corner radius helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
private struct RoundedCorner: Shape {
    var radius: CGFloat; var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

// MARK: - StillSensorBridge
@MainActor
class StillSensorBridge: ObservableObject {
    var phone:   (Float, Float, Float) = (0,0,0)
    var airPods: (Float, Float, Float) = (0,0,0)
    var watch:   (Float, Float, Float) = (0,0,0)
}

// MARK: - StillARCanvas
struct StillARCanvas: UIViewRepresentable {
    @ObservedObject var drawingEngine:     DrawingEngine
    @ObservedObject var controllerManager: GameControllerManager
    @ObservedObject var sensorBridge:      StillSensorBridge
    @ObservedObject var airPods:           AirPodsMotionManager
    @ObservedObject var recorder:          MotionRecorder
    @ObservedObject var faceManager:       FaceInputManager
    @ObservedObject var inputSettings:     InputSettingsManager
    @ObservedObject var cameraSettings:    CameraSettings
    var drawSource: StillDrawSource
    @Binding var arViewRef: ARView?

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        arView.session.run(config)
        arViewRef = arView
        context.coordinator.arView = arView
        context.coordinator.startDrawLoop()
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.drawSource    = drawSource
        context.coordinator.inputSettings = inputSettings
        context.coordinator.headRotationMatrix = airPods.headRotationMatrix
        // Tausta — käyttää olemassa olevaa BackgroundMode
        if let uiColor = cameraSettings.backgroundMode.color {
            arView.environment.background = .color(uiColor)
        } else {
            arView.environment.background = .cameraFeed()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: drawingEngine, bridge: sensorBridge,
                    controller: controllerManager, recorder: recorder,
                    face: faceManager, inputSettings: inputSettings)
    }

    // MARK: - Coordinator
    @MainActor
    class Coordinator: NSObject {
        weak var arView: ARView?
        let engine:     DrawingEngine
        let bridge:     StillSensorBridge
        let controller: GameControllerManager
        var recorder:   MotionRecorder
        let face:       FaceInputManager
        var inputSettings: InputSettingsManager
        var drawSource: StillDrawSource = .phone
        private var displayLink:    CADisplayLink?
        private var strokeRenderer: StrokeRenderer?
        private var strokeOrigin:   SIMD3<Float>? = nil
        private var wasGateOpen = false
        var headRotationMatrix: simd_float3x3 = matrix_identity_float3x3

        init(engine: DrawingEngine, bridge: StillSensorBridge, controller: GameControllerManager,
             recorder: MotionRecorder, face: FaceInputManager, inputSettings: InputSettingsManager) {
            self.engine = engine; self.bridge = bridge; self.controller = controller
            self.recorder = recorder; self.face = face; self.inputSettings = inputSettings
        }

        func startDrawLoop() {
            guard let arView = arView else { return }
            strokeRenderer = StrokeRenderer(arView: arView)
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            displayLink?.add(to: .main, forMode: .common)
        }

        @objc nonisolated func tick() {
            MainActor.assumeIsolated {
                guard let arView = arView, let frame = arView.session.currentFrame else { return }
                let cam = frame.camera.transform

                // Gate — alle kaikki lähteet
                let ctrlGate  = controller.isConnected && controller.stillDrawGateActive
                let inputGate = inputSettings.evaluateDrawGate(controller: controller)
                let faceGate  = face.isRunning && face.isMouthGateOpen
                let isGateOpen = ctrlGate || inputGate || faceGate || engine.micGateActive

                // Attitude
                let att: (roll: Float, pitch: Float, yaw: Float)
                switch drawSource {
                case .phone:      att = bridge.phone
                case .airPods:    att = bridge.airPods
                case .watch:      att = bridge.watch
                case .rightStick:
                    let x = abs(controller.rightStickX) > 0.1 ? controller.rightStickX : 0
                    let y = abs(controller.rightStickY) > 0.1 ? controller.rightStickY : 0
                    att = (x, y, 0)
                case .playback:
                    att = (recorder.liveFrame.phoneRoll, recorder.liveFrame.phonePitch, recorder.liveFrame.phoneYaw)
                }

                let fwd = SIMD3<Float>(-cam.columns.2.x, -cam.columns.2.y, -cam.columns.2.z)
                let rgt = SIMD3<Float>( cam.columns.0.x,  cam.columns.0.y,  cam.columns.0.z)
                let up  = SIMD3<Float>( cam.columns.1.x,  cam.columns.1.y,  cam.columns.1.z)
                let org = SIMD3<Float>( cam.columns.3.x,  cam.columns.3.y,  cam.columns.3.z)
                let t    = engine.drawingDistanceOffset
                let dist: Float = 0.3 + 0.5 * (log(1.0 + t * 9.0) / log(10.0))

                // Ankuroi aloituspaikka kun gate juuri aukeaa
                if isGateOpen && !wasGateOpen {
                    if drawSource == .airPods {
                        let hRaw = SIMD3<Float>(headRotationMatrix.columns.2.x,
                                               headRotationMatrix.columns.2.y,
                                               headRotationMatrix.columns.2.z)
                        let hf = simd_length(hRaw) > 0.01 ? simd_normalize(hRaw) : fwd
                        strokeOrigin = org + hf * dist
                    } else {
                        strokeOrigin = org + fwd * dist
                    }
                }
                wasGateOpen = isGateOpen

                let anchor  = strokeOrigin ?? (org + fwd * dist)
                let spread: Float = dist * 0.9
                let newPos  = anchor + rgt * (att.roll * spread) + up * (att.pitch * spread)

                if isGateOpen {
                    if !engine.isDrawing { engine.startDrawing() }
                    engine.addPoint(newPos)
                    if let cur = engine.currentStroke { strokeRenderer?.updateStroke(cur) }
                } else if engine.isDrawing {
                    strokeOrigin = nil
                    if let fin = engine.stopDrawing() { strokeRenderer?.finalizeStroke(fin) }
                }
                if recorder.isPlaying { recorder.applyToEngine(engine) }
                inputSettings.applyAll(to: engine, controller: controller)
            }
        }
    }
}

// MARK: - StillInputSettingsView
struct StillInputSettingsView: View {
    @ObservedObject var manager: InputSettingsManager
    @Binding var drawSource: StillDrawSource
    var body: some View {
        NavigationView {
            Form {
                // Draw direction — ensimmäisenä ja selkeästi
                Section(header: Text("Draw Direction")) {
                    Picker("Source", selection: $drawSource) {
                        ForEach(StillDrawSource.allCases, id: \.self) { src in
                            Label(src.rawValue, systemImage: src.icon).tag(src)
                        }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                // Draw gate
                Section(header: Text("Draw Gate")) {
                    GateSourceRow(selected: $manager.drawGateSource,
                                  usedElsewhere: manager.usedSources.subtracting([manager.drawGateSource]))
                    Text("LT = hold-only. RT = toggle (pitkä paina → hold-mode). None = controller still-toggle toimii.")
                        .font(.caption).foregroundColor(.secondary)
                }
                // Parameter mappings
                ForEach(manager.allMappings, id: \.label) { item in
                    Section(header: Label(item.label, systemImage: item.icon).foregroundColor(.purple)) {
                        MappingRow(mapping: item.binding,
                                   usedSources: manager.usedSources.subtracting([item.binding.wrappedValue.source]))
                    }
                }
            }
            .navigationTitle("Still Mode Settings").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}

// MARK: - Shared input UI (käytetään myös InputSettingsView:ssä)
struct GateSourceRow: View {
    @Binding var selected: InputChannel
    var usedElsewhere: Set<InputChannel>
    var body: some View {
        HStack {
            Image(systemName: "record.circle").frame(width: 22).foregroundColor(.orange)
            Picker("Gate", selection: $selected) {
                ForEach(InputChannel.allCases, id: \.self) { ch in
                    let used = usedElsewhere.contains(ch) && ch != .none
                    Label(ch.rawValue + (used ? " ⚬" : ""), systemImage: ch.icon).tag(ch)
                }
            }.pickerStyle(.menu)
        }
    }
}

struct MappingRow: View {
    @Binding var mapping: ParameterMapping
    var usedSources: Set<InputChannel>
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: mapping.source.icon).frame(width: 22).foregroundColor(.purple)
                Picker("Source", selection: $mapping.source) {
                    ForEach(InputChannel.allCases, id: \.self) { ch in
                        let used = usedSources.contains(ch) && ch != .none
                        Label(ch.rawValue + (used ? " ⚬" : ""), systemImage: ch.icon).tag(ch)
                    }
                }.pickerStyle(.menu)
                Spacer()
            }
            if mapping.source != .none {
                HStack {
                    Text("Scale").font(.caption).foregroundColor(.secondary)
                    Slider(value: $mapping.scale, in: -2...2).tint(.purple)
                    Text(String(format: "%.1f×", mapping.scale)).font(.system(size: 11, design: .monospaced)).frame(width: 36)
                }
            }
        }
    }
}

// MARK: - AR Camera Parameters View
struct ARCameraParamsView: View {
    @Binding var params: ARCameraParams
    var body: some View {
        NavigationView {
            List {
                Section("Exposure & Color") {
                    pSlider("Exposure (EV)", v: $params.exposureOffset, r: -4...4, f: "%+.1f EV")
                    pSlider("Brightness",    v: $params.brightness,     r: -0.5...0.5, f: "%+.2f")
                    pSlider("Contrast",      v: $params.contrast,       r: 0.5...2.0,  f: "%.2f")
                    pSlider("Saturation",    v: $params.saturation,     r: 0...2.0,    f: "%.2f")
                }
                Section("Film Effects") {
                    pSlider("Film Grain", v: $params.grainAmount,    r: 0...1, f: "%.2f")
                    pSlider("Vignette",   v: $params.vignetteAmount, r: 0...1, f: "%.2f")
                }
                Section("Options") {
                    Toggle("Auto White Balance", isOn: $params.autoWhiteBalance)
                    Toggle("Invert Colors",      isOn: $params.invertColors)
                }
                Section { Button("Reset All") { params = ARCameraParams() }.foregroundColor(.red) }
            }
            .navigationTitle("Camera Parameters").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
    private func pSlider(_ l: String, v: Binding<Float>, r: ClosedRange<Float>, f: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(l).font(.system(size: 13)); Spacer()
                Text(String(format: f, v.wrappedValue)).font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary) }
            Slider(value: v, in: r).tint(.cyan)
        }.padding(.vertical, 2)
    }
}

// MARK: - CoreMotion Wrapper
@MainActor
class CMMotionManagerWrapper: ObservableObject {
    private let cm = CMMotionManager()
    private let queue = OperationQueue()
    func start(updateInterval: TimeInterval, handler: @escaping (Double, Double, Double) -> Void) {
        guard cm.isDeviceMotionAvailable else { return }
        cm.deviceMotionUpdateInterval = updateInterval
        queue.maxConcurrentOperationCount = 1
        cm.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: queue) { motion, _ in
            guard let m = motion else { return }
            handler(m.attitude.roll, m.attitude.pitch, m.attitude.yaw)
        }
    }
    func stop() { cm.stopDeviceMotionUpdates() }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}
