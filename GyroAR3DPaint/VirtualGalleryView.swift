import SwiftUI
import RealityKit
import ARKit
import PhotosUI
import CoreMotion

struct VirtualGalleryView: View {
    @StateObject private var drawingEngine = DrawingEngine()
    @StateObject private var brushRatingManager = BrushRatingManager()
    @StateObject private var controllerManager = GameControllerManager()
    @StateObject private var straightLineState = StraightLineState()
    @StateObject private var whiteRoomState = WhiteRoomState()
    
    @State private var showBrushPicker = false
    @State private var showBrushNotes = false
    @State private var notesForBrush: BrushType = .smooth
    @State private var showImagePicker = false
    @State private var showImageSelector = false
    @State private var showExport = false
    @State private var showDrawingModes = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var drawingMode: DrawingMode = .freehand
    
    @Binding var shouldExit: Bool
    
    var body: some View {
        ZStack {
            WhiteRoomARView(
                drawingEngine: drawingEngine,
                controllerManager: controllerManager,
                straightLineState: straightLineState,
                whiteRoomState: whiteRoomState,
                drawingMode: $drawingMode
            )
            .ignoresSafeArea()
            
            // Bottom joysticks
            VStack {
                Spacer()
                HStack(spacing: 60) {
                    MoveJoystick(state: whiteRoomState)
                    DepthJoystick(state: whiteRoomState)
                }
                .padding(.bottom, 30)
            }
            
            // Top UI
            VStack(spacing: 0) {
                compactTopBar
                Spacer()
            }
            
            // Left indicators
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        cpuIndicator
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 50).padding(.leading, 8)
            
            // Drawing info
            if drawingEngine.isDrawing {
                VStack { Spacer(); drawingInfoBar.padding(.bottom, 140) }
            }
            
            // Modals
            if showBrushPicker { brushPickerOverlay }
            if showBrushNotes { brushNotesOverlay }
            if showExport {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    ExportView(strokes: drawingEngine.strokes, onDismiss: { showExport = false })
                }
            }
            if showDrawingModes {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { showDrawingModes = false }
                    DrawingModePicker(selectedMode: $drawingMode, onDismiss: { showDrawingModes = false })
                }
            }
            if showImageSelector {
                ImageSelectorView(
                    imageSelection: drawingEngine.imageSelection,
                    onConfirm: { drawingEngine.loadImageColors(); showImageSelector = false },
                    onCancel: { drawingEngine.imageSelection.selectedImage = nil; showImageSelector = false }
                )
            }
        }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    await MainActor.run {
                        drawingEngine.imageSelection.selectedImage = img
                        drawingEngine.imageSelection.selectionRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                        showImageSelector = true
                    }
                }
            }
        }
        // Xbox controller
        .onChange(of: controllerManager.leftStickX) { _, _ in handleXboxMove() }
        .onChange(of: controllerManager.leftStickY) { _, _ in handleXboxMove() }
        .onChange(of: controllerManager.rightStickY) { _, v in
            if whiteRoomState.xboxEnabled { whiteRoomState.brushDistance = max(0.2, min(1.5, whiteRoomState.brushDistance - v * 0.02)) }
        }
        .onChange(of: controllerManager.dpadUp) { _, p in if p { cycleBrush(forward: true) } }
        .onChange(of: controllerManager.dpadDown) { _, p in if p { cycleBrush(forward: false) } }
        .onChange(of: controllerManager.dpadLeft) { _, p in if p { cycleColor(forward: false) } }
        .onChange(of: controllerManager.dpadRight) { _, p in if p { cycleColor(forward: true) } }
    }
    
    func handleXboxMove() {
        guard whiteRoomState.xboxEnabled else { return }
        let x = controllerManager.leftStickX, y = controllerManager.leftStickY
        whiteRoomState.offset.x += x * 0.02
        whiteRoomState.offset.z -= y * 0.02
    }
    
    func cycleBrush(forward: Bool) {
        let b = BrushType.allCases
        guard let i = b.firstIndex(of: drawingEngine.selectedBrushType) else { return }
        drawingEngine.selectedBrushType = b[forward ? (i + 1) % b.count : (i - 1 + b.count) % b.count]
    }
    
    func cycleColor(forward: Bool) {
        let c = drawingEngine.availableColors.count, i = drawingEngine.selectedColorIndex
        drawingEngine.selectedColorIndex = forward ? (i + 1) % c : (i - 1 + c) % c
        drawingEngine.useImageColors = false
    }
    
    var compactTopBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                SmallBtn(icon: "chevron.left") { shouldExit = true }
                Spacer()
                // Xbox toggle in toolbar
                if controllerManager.isConnected {
                    Button(action: { whiteRoomState.xboxEnabled.toggle() }) {
                        Image(systemName: "gamecontroller.fill").font(.system(size: 14))
                            .foregroundColor(whiteRoomState.xboxEnabled ? .green : .gray)
                            .frame(width: 32, height: 32).background(Color.black.opacity(0.5)).clipShape(Circle())
                    }
                }
                SmallBtn(icon: drawingMode.icon) { showDrawingModes.toggle() }
                SmallBtn(icon: drawingEngine.selectedBrushType.icon) { showBrushPicker.toggle() }
                SmallBtn(icon: "photo") { showImagePicker = true }
                SmallBtn(icon: "square.and.arrow.up") { showExport = true }
                SmallBtn(icon: "arrow.uturn.backward") { drawingEngine.undoLastStroke() }
                SmallBtn(icon: "trash") { drawingEngine.clearAllStrokes() }
            }
            .padding(.horizontal, 12)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(drawingEngine.availableColors.indices, id: \.self) { i in
                        Circle().fill(drawingEngine.availableColors[i]).frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.white, lineWidth: drawingEngine.selectedColorIndex == i ? 2 : 0))
                            .onTapGesture { drawingEngine.selectedColorIndex = i; drawingEngine.useImageColors = false }
                    }
                }.padding(.horizontal, 12)
            }
        }
        .padding(.top, 50)
    }
    
    var cpuIndicator: some View {
        let u = drawingEngine.cpuUsage
        return Text("\(Int(u))%")
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(u < 50 ? .green : .yellow)
            .padding(4).background(Color.black.opacity(0.5)).cornerRadius(4)
    }
    
    var drawingInfoBar: some View {
        HStack {
            Circle().fill(Color.red).frame(width: 6, height: 6)
            Text("REC").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
            Spacer()
            Text("D:\(String(format: "%.0f", whiteRoomState.brushDistance * 100))cm").font(.system(size: 9)).foregroundColor(.cyan)
            Circle().fill(drawingEngine.currentColor).frame(width: 12, height: 12)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black.opacity(0.6)).cornerRadius(8)
        .padding(.horizontal, 20)
    }
    
    var brushPickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea().onTapGesture { showBrushPicker = false }
            CompactBrushPicker(drawingEngine: drawingEngine, ratingManager: brushRatingManager,
                onSelect: { showBrushPicker = false },
                onNotes: { b in notesForBrush = b; showBrushNotes = true })
        }
    }
    
    var brushNotesOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { showBrushNotes = false }
            BrushNotesView(brushType: notesForBrush, ratingManager: brushRatingManager, onDismiss: { showBrushNotes = false })
        }
    }
}

// MARK: - White Room State
class WhiteRoomState: ObservableObject {
    @Published var offset: SIMD3<Float> = .zero
    @Published var brushDistance: Float = 0.5
    @Published var xboxEnabled = false
}

// MARK: - Move Joystick
struct MoveJoystick: View {
    @ObservedObject var state: WhiteRoomState
    @State private var dragOffset: CGSize = .zero
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Color.white.opacity(0.1)).frame(width: 80, height: 80)
                Circle().fill(Color.white.opacity(0.3)).frame(width: 40, height: 40)
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                let max: CGFloat = 30
                                let dx = Swift.max(-max, Swift.min(max, v.translation.width))
                                let dy = Swift.max(-max, Swift.min(max, v.translation.height))
                                dragOffset = CGSize(width: dx, height: dy)
                                startTimer(dx: Float(dx / max), dy: Float(dy / max))
                            }
                            .onEnded { _ in
                                dragOffset = .zero
                                stopTimer()
                            }
                    )
            }
            Text("MOVE").font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.6))
        }
    }
    
    func startTimer(dx: Float, dy: Float) {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            state.offset.x += dx * 0.02
            state.offset.z += dy * 0.02
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Depth Joystick
struct DepthJoystick: View {
    @ObservedObject var state: WhiteRoomState
    @State private var dragOffset: CGSize = .zero
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Color.white.opacity(0.1)).frame(width: 80, height: 80)
                Circle().fill(Color.white.opacity(0.3)).frame(width: 40, height: 40)
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                let max: CGFloat = 30
                                let dy = Swift.max(-max, Swift.min(max, v.translation.height))
                                dragOffset = CGSize(width: 0, height: dy)
                                startTimer(dy: Float(-dy / max))
                            }
                            .onEnded { _ in
                                dragOffset = .zero
                                stopTimer()
                            }
                    )
            }
            Text("DEPTH").font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.6))
        }
    }
    
    func startTimer(dy: Float) {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            state.brushDistance = Swift.max(0.2, Swift.min(2.0, state.brushDistance + dy * 0.01))
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Small Button
struct SmallBtn: View {
    let icon: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(.white)
                .frame(width: 32, height: 32).background(Color.black.opacity(0.5)).clipShape(Circle())
        }
    }
}

// MARK: - Compact Brush Picker
struct CompactBrushPicker: View {
    @ObservedObject var drawingEngine: DrawingEngine
    @ObservedObject var ratingManager: BrushRatingManager
    let onSelect: () -> Void; let onNotes: (BrushType) -> Void
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 6) {
                ForEach(BrushType.allCases, id: \.self) { b in
                    Button(action: { drawingEngine.selectedBrushType = b; onSelect() }) {
                        VStack(spacing: 2) {
                            Image(systemName: b.icon).font(.system(size: 16))
                                .foregroundColor(drawingEngine.selectedBrushType == b ? .yellow : .white)
                            if let s = ratingManager.getAverageStars(for: b) {
                                Text("\(Int(s.rounded()))★").font(.system(size: 6)).foregroundColor(.yellow)
                            }
                        }
                        .frame(width: 40, height: 36)
                        .background(drawingEngine.selectedBrushType == b ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .frame(width: 280, height: 220)
        .padding(10)
        .background(Color.black.opacity(0.85)).cornerRadius(12)
    }
}

// MARK: - White Room AR View
struct WhiteRoomARView: UIViewRepresentable {
    @ObservedObject var drawingEngine: DrawingEngine
    @ObservedObject var controllerManager: GameControllerManager
    @ObservedObject var straightLineState: StraightLineState
    @ObservedObject var whiteRoomState: WhiteRoomState
    @Binding var drawingMode: DrawingMode
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.init(white: 0.95, alpha: 1))
        
        let roomAnchor = AnchorEntity(world: .zero)
        let floor = ModelEntity(mesh: .generatePlane(width: 10, depth: 10), materials: [SimpleMaterial(color: .init(white: 0.9, alpha: 1), isMetallic: false)])
        floor.position.y = -1
        roomAnchor.addChild(floor)
        arView.scene.addAnchor(roomAnchor)
        
        context.coordinator.arView = arView
        context.coordinator.drawingEngine = drawingEngine
        context.coordinator.whiteRoomState = whiteRoomState
        context.coordinator.roomAnchor = roomAnchor
        context.coordinator.startFrameUpdates()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.drawingMode = drawingMode
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    @MainActor
    class Coordinator: NSObject {
        weak var arView: ARView?
        var drawingEngine: DrawingEngine?
        var whiteRoomState: WhiteRoomState?
        var roomAnchor: AnchorEntity?
        var drawingMode: DrawingMode = .freehand
        
        private var displayLink: CADisplayLink?
        private var strokeRenderer: StrokeRenderer?
        private var motionManager: CMMotionManager?
        private var currentRotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        
        func startFrameUpdates() {
            guard let arView = arView else { return }
            strokeRenderer = StrokeRenderer(arView: arView)
            
            motionManager = CMMotionManager()
            if motionManager?.isDeviceMotionAvailable == true {
                motionManager?.deviceMotionUpdateInterval = 1.0 / 60.0
                motionManager?.startDeviceMotionUpdates(using: .xArbitraryZVertical)
            }
            
            displayLink = CADisplayLink(target: self, selector: #selector(frameUpdate))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            displayLink?.add(to: .main, forMode: .common)
            
            setupTouchHandling()
        }
        
        @objc func frameUpdate() {
            guard let drawingEngine = drawingEngine, let state = whiteRoomState else { return }
            
            if let motion = motionManager?.deviceMotion {
                let q = motion.attitude.quaternion
                currentRotation = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
            }
            
            let brushPosition = getBrushPosition(state: state)
            
            if drawingMode == .freehand && drawingEngine.isDrawing {
                drawingEngine.addPoint(brushPosition)
                if let stroke = drawingEngine.currentStroke {
                    strokeRenderer?.updateStroke(stroke)
                }
            }
        }
        
        func getBrushPosition(state: WhiteRoomState) -> SIMD3<Float> {
            let forward = currentRotation.act(SIMD3<Float>(0, 0, -1))
            return state.offset + forward * state.brushDistance
        }
        
        func setupTouchHandling() {
            guard let arView = arView else { return }
            let touchView = WhiteRoomTouchView(frame: arView.bounds)
            touchView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            touchView.coordinator = self
            arView.addSubview(touchView)
        }
        
        func handleTouchBegan(at location: CGPoint, in view: UIView) {
            guard let drawingEngine = drawingEngine else { return }
            updateBrushSize(at: location, in: view)
            if drawingMode == .freehand { drawingEngine.startDrawing() }
        }
        
        func handleTouchMoved(at location: CGPoint, in view: UIView) {
            updateBrushSize(at: location, in: view)
        }
        
        func handleTouchEnded() {
            guard let drawingEngine = drawingEngine else { return }
            if drawingMode == .freehand {
                if let stroke = drawingEngine.stopDrawing() {
                    strokeRenderer?.finalizeStroke(stroke)
                }
            }
        }
        
        func updateBrushSize(at location: CGPoint, in view: UIView) {
            guard let drawingEngine = drawingEngine else { return }
            let norm = max(0, min(1, 1.1 - (location.y / view.bounds.height * 1.1)))
            drawingEngine.setBrushSizeNormalized(Float(norm))
        }
        
        deinit {
            displayLink?.invalidate()
            motionManager?.stopDeviceMotionUpdates()
        }
    }
}

class WhiteRoomTouchView: UIView {
    weak var coordinator: WhiteRoomARView.Coordinator?
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError() }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        coordinator?.handleTouchBegan(at: t.location(in: self), in: self)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        coordinator?.handleTouchMoved(at: t.location(in: self), in: self)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { coordinator?.handleTouchEnded() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { coordinator?.handleTouchEnded() }
}
