import SwiftUI
import PhotosUI
import RealityKit
import ReplayKit
import Photos
import AVFoundation
import Combine

struct ContentView: View {
    @EnvironmentObject var performanceManager: PerformanceManager
    @StateObject var drawingEngine = DrawingEngine()
    @StateObject var brushRatingManager = BrushRatingManager()
    @StateObject var controllerManager = GameControllerManager()
    @StateObject var selectionManager = StrokeSelectionManager()
    @StateObject var straightLineState = StraightLineState()
    @StateObject var recordingManager = RecordingManager()
    @StateObject var screenshotManager = ScreenshotManager()
    @StateObject var cameraSettings = CameraSettings()
    @StateObject var galleryManager = GalleryManager()
    @StateObject var imagePaintSource = ImagePaintSource()
    @StateObject var airPodsManager = AirPodsMotionManager()
    @StateObject var brushPresetManager = BrushPresetManager()
    @StateObject var midiManager = MIDINetworkManager.shared
    @StateObject var micManager = MicInputManager()
    
    @State private var showBrushPicker = false
    @State private var showBrushStudio = false
    @State private var showBrushNotes = false
    @State private var notesForBrush: BrushType = .smooth
    @State private var showImagePicker = false
    @State private var showImageSelector = false
    @State private var showExport = false
    @State private var showDrawingModes = false
    @State private var showGallery = false
    @State private var showImageCrop = false
    @State private var showPaintImagePicker = false
    @State private var showPerformanceSettings = false
    @State private var showMIDISettings = false
    @State private var paintPhotoItem: PhotosPickerItem?
    @State private var tempPaintImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var drawingMode: DrawingMode = .freehand
    @State private var effectMode: EffectMode = .none
    @State private var leftSliderMode: LeftSliderMode = .opacity
    
    enum LeftSliderMode {
        case opacity
        case distance
    }
    @State private var showControllerIcon = false
    @State private var showCrosshair = true  // Tähtäin on/off
    @State private var hideUI = false  // Piilota kaikki UI paitsa silmä-ikoni
    @State private var drawingLockActive = false  // Piirrinlukko
    @State private var showBrushSizeSettings = false
    @State private var drawingLockDragOffset: CGFloat = 0
    @State private var uiEditMode = false  // UI järjestely tila
    @State private var toolRowAtBottom = false  // Tool row sijainti
    @State private var colorRowAtBottom = false  // Color row sijainti
    @State private var arViewRef: ARView?
    @State private var screenshotFreezeTime: Double = 0.15  // Freeze duration in seconds
    @State private var showFreezeSlider = false
    @State private var isScreenshotFreezing = false
    @State private var showColorWheel = false
    @State private var colorWheelHue: CGFloat = 0
    @State private var colorWheelSaturation: CGFloat = 1
    private let cameraAspectRatio: CGFloat = 9.0 / 16.0
    private let minToolbarMargin: CGFloat = 120
    
    @Binding var shouldExit: Bool
    var onExitToMenu: (() -> Void)?
    
    init(shouldExit: Binding<Bool> = .constant(false), onExitToMenu: (() -> Void)? = nil) {
        self._shouldExit = shouldExit
        self.onExitToMenu = onExitToMenu
    }
    
    var body: some View {
        mainZStack
            .photosPicker(isPresented: $showImagePicker, selection: $selectedPhotoItem, matching: .images)
            .photosPicker(isPresented: $showPaintImagePicker, selection: $paintPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, n in handleImagePick(n) }
            .onChange(of: paintPhotoItem) { _, n in handlePaintImagePick(n) }
            .onAppear { startTremoloTimer(); setupControllerBindings(); setupAirPodsBinding(); setupMicBinding() }
    }
    
    func setupControllerBindings() {
        // Use Combine to observe controller changes
        controllerManager.$dpadUp.sink { [self] p in if p { handleDpadUp() } }.store(in: &controllerCancellables)
        controllerManager.$dpadDown.sink { [self] p in if p { handleDpadDown() } }.store(in: &controllerCancellables)
        controllerManager.$dpadLeft.sink { [self] p in if p { handleDpadLeft() } }.store(in: &controllerCancellables)
        controllerManager.$dpadRight.sink { [self] p in if p { handleDpadRight() } }.store(in: &controllerCancellables)
        
        // Left stick - color wheel control when open, otherwise brush size
        controllerManager.$leftStickX.sink { [self] _ in
            if showColorWheel {
                handleColorWheelStick()
            } else if selectionManager.isSelectionMode {
                handleLeftStick()
            }
            // X axis doesn't affect brush size
        }.store(in: &controllerCancellables)
        controllerManager.$leftStickY.sink { [self] _ in
            if showColorWheel {
                handleColorWheelStick()
            } else if selectionManager.isSelectionMode {
                handleLeftStick()
            } else {
                // Normal mode: left stick Y controls brush size
                drawingEngine.brushSize = controllerManager.controllerBrushSize
            }
        }.store(in: &controllerCancellables)
        
        // L3 button triggers brush size update (for extended range)
        controllerManager.$leftStickButton.sink { [self] _ in
            if !showColorWheel && !selectionManager.isSelectionMode {
                drawingEngine.brushSize = controllerManager.controllerBrushSize
            }
        }.store(in: &controllerCancellables)
        
        // Right stick X controls opacity
        controllerManager.$rightStickX.sink { [self] v in
            if !selectionManager.isSelectionMode {
                drawingEngine.opacity = max(0.1, min(1.0, (v + 1) / 2))
            }
        }.store(in: &controllerCancellables)
        
        // LT and RT control drawing on/off (isControllerDrawing is updated in GameControllerManager)
        // The actual drawing logic is handled in ARViewContainer based on isControllerDrawing
        
        controllerManager.$leftBumper.sink { [self] p in if p { drawingEngine.randomizeColor() } }.store(in: &controllerCancellables)
        controllerManager.$rightBumper.sink { [self] p in if p { drawingEngine.invertColor() } }.store(in: &controllerCancellables)
        controllerManager.$buttonB.sink { [self] p in if p { drawingEngine.clearAllStrokes() } }.store(in: &controllerCancellables)
        controllerManager.$buttonX.sink { [self] p in if p { drawingEngine.undoLastStroke() } }.store(in: &controllerCancellables)
        controllerManager.$buttonA.sink { [self] p in if p { resetColorAndOpacity() } }.store(in: &controllerCancellables)
        controllerManager.$buttonY.sink { [self] p in if p { cycleDrawingMode() } }.store(in: &controllerCancellables)
        controllerManager.$menuButton.sink { [self] p in if p { hideUI.toggle() } }.store(in: &controllerCancellables)
    }
    
    func handleDpadUp() {
        if selectionManager.isSelectionMode {
            cycleBrushForSelection(forward: true)
        } else {
            cycleBrush(forward: true)
        }
    }
    
    func handleDpadDown() {
        if selectionManager.isSelectionMode {
            cycleBrushForSelection(forward: false)
        } else {
            cycleBrush(forward: false)
        }
    }
    
    func handleDpadLeft() {
        if selectionManager.isSelectionMode {
            cycleColorForSelection(forward: false)
        } else {
            cycleColor(forward: false)
        }
    }
    
    func handleDpadRight() {
        if selectionManager.isSelectionMode {
            cycleColorForSelection(forward: true)
        } else {
            cycleColor(forward: true)
        }
    }
    
    func cycleDrawingMode(forward: Bool = true) {
            let modes = DrawingMode.allCases
            guard let idx = modes.firstIndex(of: drawingMode) else { return }
            let nextIndex = forward ? (idx + 1) % modes.count : (idx - 1 + modes.count) % modes.count
            drawingMode = modes[nextIndex]
        }
        
    func handleLeftStick() {
        if selectionManager.isSelectionMode {
            moveSelectedStrokes()
        }
        // Note: brush size control is now handled directly in setupControllerBindings
        // Color wheel is handled separately when showColorWheel is true
    }
    
    func cycleBrushForSelection(forward: Bool) {
        // TODO: Muuta valittujen piirtojen brushia
    }
    
    func cycleColorForSelection(forward: Bool) {
        guard selectionManager.hasSelection else { return }
        let c = drawingEngine.availableColors.count
        let newIndex = forward ? (drawingEngine.selectedColorIndex + 1) % c : (drawingEngine.selectedColorIndex - 1 + c) % c
        let newColor = drawingEngine.availableColors[newIndex]
        drawingEngine.selectedColorIndex = newIndex
        
        // Muuta valittujen strokejen väri
        for i in 0..<drawingEngine.strokes.count {
            if selectionManager.selectedStrokeIDs.contains(drawingEngine.strokes[i].id) {
                drawingEngine.strokes[i].color = newColor
                // Päivitä myös jokaisen pisteen väri
                for j in 0..<drawingEngine.strokes[i].points.count {
                    drawingEngine.strokes[i].points[j].color = newColor
                }
            }
        }
        // Päivitä renderöinti
        NotificationCenter.default.post(name: .strokesNeedUpdate, object: selectionManager.selectedStrokeIDs)
    }
    
    func moveSelectedStrokes() {
        guard selectionManager.hasSelection else { return }
        let x = controllerManager.leftStickX
        let y = controllerManager.leftStickY
        let rY = controllerManager.rightStickY  // Z-suunta (syvyys)
        
        let deadzone: Float = 0.15
        guard abs(x) > deadzone || abs(y) > deadzone || abs(rY) > deadzone else { return }
        
        let moveSpeed: Float = 0.002
        let movement = SIMD3<Float>(x * moveSpeed, y * moveSpeed, rY * moveSpeed)
        
        for i in 0..<drawingEngine.strokes.count {
            if selectionManager.selectedStrokeIDs.contains(drawingEngine.strokes[i].id) {
                for j in 0..<drawingEngine.strokes[i].points.count {
                    drawingEngine.strokes[i].points[j].position += movement
                }
            }
        }
        NotificationCenter.default.post(name: .strokesNeedUpdate, object: selectionManager.selectedStrokeIDs)
    }
    
    func setupAirPodsBinding() {
        // Sync AirPods gradient value to drawing engine
        airPodsManager.$colorGradientValue.sink { [self] value in
            drawingEngine.airPodsGradientValue = value
        }.store(in: &controllerCancellables)
    }

    func setupMicBinding() {
        // Forward mic gate and amplitude to drawingEngine
        micManager.$gateOpen.sink { [self] gate in
            drawingEngine.micGateActive = gate
        }.store(in: &controllerCancellables)

        micManager.$amplitude.sink { [self] amp in
            // Map amplitude to opacity (minimum 0.05 so there's always some ink)
            drawingEngine.micOpacity = max(0.05, min(1.0, amp))
        }.store(in: &controllerCancellables)

        // Start/stop mic engine when inputSource changes
        drawingEngine.$inputSource.sink { [self] source in
            switch source {
            case .mic, .both:
                micManager.start()
            case .gyro:
                micManager.stop()
                // Restore manual opacity when switching back
                drawingEngine.opacity = 1.0
            }
        }.store(in: &controllerCancellables)
    }
    
    @State private var controllerCancellables = Set<AnyCancellable>()
    
    // Tremolo timer for right stick Y modulation
    @State private var tremoloTimer: Timer?
    @State private var tremoloPhase: Bool = true
    
    func startTremoloTimer() {
        tremoloTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                let tremoloAmount = abs(controllerManager.rightStickY)
                if tremoloAmount > 0.1 && drawingEngine.isDrawing {
                    // Modulate drawing on/off based on tremolo
                    let speed = tremoloAmount * 20 // Higher = faster modulation
                    tremoloPhase.toggle()
                    drawingEngine.tremoloActive = tremoloPhase || tremoloAmount < 0.3
                }
            }
        }
    }
    
    // 360° color wheel from left stick
    func updateColorWheel() {
        let x = controllerManager.leftStickX
        let y = controllerManager.leftStickY
        let magnitude = sqrt(x*x + y*y)
        
        if magnitude > 0.2 { // Dead zone
            // Calculate angle (0-360°) -> hue (0-1)
            let angle = atan2(y, x)
            let hue = (angle + .pi) / (2 * .pi) // Convert -π...π to 0...1
            
            // Saturation from magnitude
            let saturation = min(1.0, magnitude)
            
            // Set color directly from HSB
            drawingEngine.setColorFromHSB(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: 1.0)
        }
    }
    
    var mainZStack: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Full screen AR view
            arLayer
                .ignoresSafeArea()
            
            cameraOverlayLayer
            
            // Toolbars
            VStack(spacing: 0) {
                // Top toolbar
                if !recordingManager.isRecording && !hideUI {
                    topMarginLayer
                }
                
                Spacer()
                
                // Bottom toolbar - show stop button when recording
                if recordingManager.isRecording {
                    // Minimal recording controls
                    HStack {
                        Spacer()
                        Button(action: { recordingManager.stopRecording() }) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 60, height: 60)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        Spacer()
                    }
                    .padding(.bottom, 40)
                } else if !hideUI {
                    bottomMarginLayer
                }
            }
            
            if !recordingManager.isRecording && !hideUI {
                modalsLayer
            }
            toastLayer
            
            // Eye icon and crosshair toggle - always visible
            eyeToggleButton
            
            // Image crop overlay
            if showImageCrop, let img = tempPaintImage {
                ImageCropView(
                    image: img,
                    cropRect: $imagePaintSource.cropRect,
                    onConfirm: {
                        imagePaintSource.setImage(img, cropRect: imagePaintSource.cropRect)
                        showImageCrop = false
                        tempPaintImage = nil
                    },
                    onCancel: {
                        showImageCrop = false
                        tempPaintImage = nil
                    }
                )
            }
            
            // Color wheel picker overlay
            if showColorWheel {
                colorWheelOverlay
                    .transition(.opacity)
            }
        }
        .statusBarHidden(recordingManager.isRecording || hideUI)
    }
    
    // Eye button only visible in hide mode - positioned where gallery button normally is
    var eyeToggleButton: some View {
        Group {
            if hideUI {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { hideUI.toggle() }) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(12)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
    }

    // Input source selector: cycles Gyro → Mic → Both
    var inputSourceButton: some View {
        Button(action: {
            let all = DrawingInputSource.allCases
            if let idx = all.firstIndex(of: drawingEngine.inputSource) {
                drawingEngine.inputSource = all[(idx + 1) % all.count]
            }
        }) {
            ZStack {
                Circle()
                    .fill(inputSourceGradient)
                    .frame(width: 32, height: 32)
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.25), Color.clear],
                                        center: .topLeading, startRadius: 0, endRadius: 20))
                    .frame(width: 30, height: 30)
                Image(systemName: drawingEngine.inputSource.icon)
                    .font(.system(size: 14))
                    .foregroundColor(inputSourceColor)
                // Mic activity pulse ring
                if (drawingEngine.inputSource == .mic || drawingEngine.inputSource == .both)
                    && micManager.gateOpen {
                    Circle()
                        .stroke(Color.green.opacity(0.8), lineWidth: 2)
                        .frame(width: 34, height: 34)
                }
            }
        }
    }

    private var inputSourceColor: Color {
        switch drawingEngine.inputSource {
        case .gyro: return .white
        case .mic:  return .green
        case .both: return .cyan
        }
    }

    private var inputSourceGradient: LinearGradient {
        let colors: [Color]
        switch drawingEngine.inputSource {
        case .gyro: colors = [Color.white.opacity(0.2), Color.gray.opacity(0.4), Color.black.opacity(0.5)]
        case .mic:  colors = [Color.green.opacity(0.3), Color.green.opacity(0.15), Color.black.opacity(0.5)]
        case .both: colors = [Color.cyan.opacity(0.3), Color.cyan.opacity(0.15), Color.black.opacity(0.5)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func cameraLayout(in size: CGSize) -> (cameraSize: CGSize, verticalMargin: CGFloat) {
        // Full screen - no margins
        return (size, 0)
    }
    
    var drawingLockHandle: some View {
        HStack {
            // Lock handle on left edge - swipe right to toggle
            ZStack {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 50, height: 120)
                
                // Lock indicator
                VStack(spacing: 4) {
                    Image(systemName: drawingLockActive ? "lock.fill" : "lock.open")
                        .font(.system(size: 20))
                        .foregroundColor(drawingLockActive ? .yellow : .white.opacity(0.6))
                    
                    Text(drawingLockActive ? "LOCKED" : "LOCK")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(drawingLockActive ? .yellow : .white.opacity(0.6))
                    
                    // Drag indicator
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .offset(x: drawingLockDragOffset)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Always drag right to toggle
                        drawingLockDragOffset = max(0, min(60, value.translation.width))
                    }
                    .onEnded { value in
                        // Toggle lock if dragged far enough right
                        if value.translation.width > 40 {
                            drawingLockActive.toggle()
                            if !drawingLockActive {
                                // Unlock - complete drawing
                                straightLineState.isDrawing = false
                                NotificationCenter.default.post(name: .drawingLockReleased, object: nil)
                            }
                        }
                        withAnimation(.spring(response: 0.3)) {
                            drawingLockDragOffset = 0
                        }
                    }
            )
            .offset(x: -10)
            
            Spacer()
        }
    }
    
    // Left edge slider - dual mode: opacity or drawing distance
    var leftEdgeOpacitySlider: some View {
        HStack {
            GeometryReader { geo in
                let sliderHeight: CGFloat = geo.size.height * 0.55
                let topOffset: CGFloat = 100
                
                let currentValue: Float = leftSliderMode == .opacity
                    ? drawingEngine.opacity
                    : drawingEngine.drawingDistanceOffset
                
                ZStack(alignment: .leading) {
                    // Touch area
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 70, height: sliderHeight)
                        .contentShape(Rectangle())
                        .position(x: 35, y: topOffset + sliderHeight / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let relativeY = (value.location.y - topOffset) / sliderHeight
                                    let newValue = Float(1.0 - max(0, min(1, relativeY)))
                                    if leftSliderMode == .opacity {
                                        drawingEngine.opacity = newValue
                                    } else {
                                        drawingEngine.drawingDistanceOffset = newValue
                                    }
                                }
                        )
                    
                    // Track background
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: leftSliderMode == .opacity
                                    ? [Color.white.opacity(0.15), Color.white.opacity(0.03)]
                                    : [Color.cyan.opacity(0.2), Color.cyan.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 10, height: sliderHeight)
                        .position(x: 12, y: topOffset + sliderHeight / 2)
                    
                    // Value indicator
                    Circle()
                        .fill(leftSliderMode == .opacity
                              ? Color.white.opacity(0.35)
                              : Color.cyan.opacity(0.5))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 2)
                        .position(
                            x: 12,
                            y: topOffset + sliderHeight * CGFloat(1.0 - currentValue)
                        )
                    
                    // Value label
                    Text(leftSliderMode == .opacity
                         ? "\(Int(currentValue * 100))"
                         : String(format: "%.0fm", 0.3 + currentValue * 500.0))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .position(
                            x: 42,
                            y: topOffset + sliderHeight * CGFloat(1.0 - currentValue)
                        )
                    
                    // Mode toggle button at bottom of slider
                    Button(action: {
                        leftSliderMode = leftSliderMode == .opacity ? .distance : .opacity
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 28, height: 28)
                            Image(systemName: leftSliderMode == .opacity
                                  ? "circle.lefthalf.filled"
                                  : "arrow.up.and.down.and.sparkles")
                                .font(.system(size: 13))
                                .foregroundColor(leftSliderMode == .opacity
                                                 ? .white.opacity(0.6)
                                                 : .cyan.opacity(0.8))
                        }
                    }
                    .position(x: 12, y: topOffset + sliderHeight + 25)
                    
                    // Brush size range button
                    Button(action: {
                        showBrushSizeSettings.toggle()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 28, height: 28)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .position(x: 12, y: topOffset + sliderHeight + 58)
                    .popover(isPresented: $showBrushSizeSettings) {
                        brushSizeSettingsPopover
                    }
                }
            }
            
            Spacer()
        }
    }
    
    var brushSizeSettingsPopover: some View {
        VStack(spacing: 16) {
            Text("BRUSH SIZE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 8) {
                HStack {
                    Text("Min")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text(String(format: "%.1fmm", drawingEngine.brushSizeMin * 1000))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
                Slider(value: $drawingEngine.brushSizeMin, in: 0.001...0.05, step: 0.001)
                    .tint(.cyan)
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Max")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text(String(format: "%.0fmm", drawingEngine.brushSizeMax * 1000))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
                Slider(value: $drawingEngine.brushSizeMax, in: 0.01...0.5, step: 0.005)
                    .tint(.cyan)
            }
            
            Button("Reset") {
                drawingEngine.brushSizeMin = 0.002
                drawingEngine.brushSizeMax = 0.05
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.cyan.opacity(0.8))
        }
        .padding(16)
        .frame(width: 220)
        .background(Color.black.opacity(0.9))
        .presentationCompactAdaptation(.popover)
    }
    
    var arLayer: some View {
        ARViewContainerWithRef(
            drawingEngine: drawingEngine,
            controllerManager: controllerManager,
            selectionManager: selectionManager,
            straightLineState: straightLineState,
            cameraSettings: cameraSettings,
            drawingMode: $drawingMode,
            arViewRef: $arViewRef
        )
    }
    
    var cameraOverlayLayer: some View {
        ZStack {
            // Screenshot freeze overlay
            if screenshotManager.isFreezing {
                Color.white.opacity(0.3)
                    .allowsHitTesting(false)
            }
            
            // Crosshair (tähtäin)
            if showCrosshair && !selectionManager.isSelectionMode && !hideUI {
                CrosshairView(color: drawingEngine.currentColor)
            }
            
            // Selection mode indicator
            if selectionManager.isSelectionMode && !hideUI {
                SelectionModeOverlay(selectionManager: selectionManager, drawingEngine: drawingEngine)
            }
            
            // Hide UI when recording or hideUI is true
            if !recordingManager.isRecording && !hideUI {
                indicatorsOverlay
                drawingInfoLayer
                effectLayer
            }
            
            // Left edge opacity slider - always available during drawing
            if !hideUI {
                leftEdgeOpacitySlider
            }
        }
    }
    
    var topMarginLayer: some View {
        VStack(spacing: 8) {
            if !recordingManager.isRecording && !hideUI {
                topBarLayer
            }
            
            if showFreezeSlider && !hideUI {
                freezeSliderView
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var bottomMarginLayer: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            
            if !hideUI {
                recordingStatusIcons
            }
            
            if !recordingManager.isRecording && !hideUI {
                bottomToolbarContent
            }
            
            if !hideUI {
                recordingControlsRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
    
    var recordingStatusIcons: some View {
        HStack {
            VStack(spacing: 6) {
                // Back to menu button
                if let exitAction = onExitToMenu {
                    Button(action: exitAction) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.gray.opacity(0.4), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 32, height: 32)
                            Circle()
                                .fill(RadialGradient(colors: [Color.white.opacity(0.25), Color.clear], center: .topLeading, startRadius: 0, endRadius: 20))
                                .frame(width: 30, height: 30)
                            Image(systemName: "house.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                
                // Performance indicator
                Button(action: { showPerformanceSettings = true }) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.gray.opacity(0.4), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(RadialGradient(colors: [Color.white.opacity(0.25), Color.clear], center: .topLeading, startRadius: 0, endRadius: 20))
                            .frame(width: 30, height: 30)
                        Image(systemName: performanceManager.currentLevel.icon)
                            .font(.system(size: 14))
                            .foregroundColor(performanceManager.currentLevel.color)
                    }
                }
                
                // Controller icon
                if controllerManager.isConnected {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.gray.opacity(0.4), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(RadialGradient(colors: [Color.white.opacity(0.25), Color.clear], center: .topLeading, startRadius: 0, endRadius: 20))
                            .frame(width: 30, height: 30)
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                }
                
                // AirPods icon
                AirPodsStatusView(manager: airPodsManager)

                // Input source selector (Gyro / Mic / Both)
                inputSourceButton
                
                // MIDI Status & Toggle
                Button(action: { showMIDISettings = true }) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.gray.opacity(0.4), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(RadialGradient(colors: [Color.white.opacity(0.25), Color.clear], center: .topLeading, startRadius: 0, endRadius: 20))
                            .frame(width: 30, height: 30)
                        Image(systemName: midiManager.isConnected ? "music.note.list" : "music.note")
                            .font(.system(size: 14))
                            .foregroundColor(midiManager.isConnected ? .green : .gray)
                    }
                }
                
                // MIDI Output ON/OFF Toggle
                if midiManager.isConnected {
                    Button(action: { midiManager.isMIDIEnabled.toggle() }) {
                        ZStack {
                            Circle()
                                .fill(midiManager.isMIDIEnabled ? Color.green.opacity(0.3) : Color.gray.opacity(0.2))
                                .frame(width: 32, height: 32)
                            Image(systemName: midiManager.isMIDIEnabled ? "waveform" : "waveform.slash")
                                .font(.system(size: 14))
                                .foregroundColor(midiManager.isMIDIEnabled ? .green : .gray)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.leading, 12)
    }
    
    var freezeSliderView: some View {
        VStack(spacing: 4) {
            Text("Screenshot Freeze: \(String(format: "%.2f", screenshotFreezeTime))s")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            Slider(value: $screenshotFreezeTime, in: 0.01...0.12, step: 0.005)
                .frame(width: 150)
                .accentColor(.cyan)
            Button("Hide") { showFreezeSlider = false }
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
    }
    
    var recordingControlsRow: some View {
        HStack(spacing: 16) {
            // Screenshot button - long press shows freeze slider
            Button(action: { takeScreenshotToGallery() }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.25), Color.gray.opacity(0.4), Color.black.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 50, height: 50)
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.3), Color.clear], center: .topLeading, startRadius: 0, endRadius: 30))
                        .frame(width: 48, height: 48)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    showFreezeSlider.toggle()
                }
            )
            
            // Record button
            Button(action: {
                if recordingManager.isRecording { recordingManager.stopRecording() }
                else { recordingManager.startRecording() }
            }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.gray.opacity(0.35), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 70, height: 70)
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.2), Color.clear], center: .topLeading, startRadius: 0, endRadius: 40))
                        .frame(width: 68, height: 68)
                    if recordingManager.isRecording {
                        RoundedRectangle(cornerRadius: 4).fill(Color.red).frame(width: 24, height: 24)
                    } else {
                        Circle().fill(Color.red).frame(width: 30, height: 30)
                    }
                }
            }
            .disabled(!recordingManager.canRecord)
            
            // Background mode button - with gray border for white mode
            Button(action: { cycleBackgroundMode() }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.gray.opacity(0.35), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                    Circle()
                        .fill(backgroundModeColor)
                        .frame(width: 40, height: 40)
                    Circle()
                        .stroke(Color.gray.opacity(0.6), lineWidth: 2)
                        .frame(width: 40, height: 40)
                    if cameraSettings.backgroundMode == .ar {
                        Text("AR").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    }
                }
            }
            
            // Eye button (hide UI)
            Button(action: { hideUI.toggle() }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.25), Color.gray.opacity(0.4), Color.black.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.3), Color.clear], center: .topLeading, startRadius: 0, endRadius: 25))
                        .frame(width: 42, height: 42)
                    Image(systemName: "eye.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
            }
            
            // Recording time
            if recordingManager.isRecording {
                Text(formatTime(recordingManager.recordingTime))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.6)).cornerRadius(6)
            }
        }
    }
    
    var backgroundModeColor: Color {
        switch cameraSettings.backgroundMode {
        case .ar: return Color.gray.opacity(0.5)
        case .black: return Color.black
        case .white: return Color.white
        case .green: return Color.green
        }
    }
    
    func cycleBackgroundMode() {
        let modes = BackgroundMode.allCases
        if let idx = modes.firstIndex(of: cameraSettings.backgroundMode) {
            cameraSettings.backgroundMode = modes[(idx + 1) % modes.count]
        }
    }
    
    func takeScreenshotToGallery() {
        guard let arView = arViewRef else { return }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Start freeze effect
        screenshotManager.isFreezing = true
        
        arView.snapshot(saveToHDR: false) { [self] image in
            guard let image = image else {
                Task { @MainActor in screenshotManager.isFreezing = false }
                return
            }
            // Save to internal gallery
            _ = galleryManager.saveImage(
                image,
                brushType: drawingEngine.selectedBrushType.rawValue,
                aspectRatio: "16:9"
            )
            // Also save to Photos
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized || status == .limited {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
            Task { @MainActor in
                // Keep freeze for configured duration
                try? await Task.sleep(nanoseconds: UInt64(screenshotFreezeTime * 1_000_000_000))
                screenshotManager.isFreezing = false
                
                screenshotManager.showSaveSuccess = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                screenshotManager.showSaveSuccess = false
            }
        }
    }
    
    func formatTime(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d.%d", Int(t) / 60, Int(t) % 60, Int((t.truncatingRemainder(dividingBy: 1)) * 10))
    }
    
    var toastLayer: some View {
        VStack {
            Spacer()
            if recordingManager.showSaveSuccess { SaveSuccessToast(message: "Video saved!") }
            if screenshotManager.showSaveSuccess { SaveSuccessToast(message: "Photo saved!") }
            Spacer().frame(height: 150)
        }
    }
    
    var topBarLayer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                if !toolRowAtBottom {
                    DraggableToolRow(
                        content: AnyView(toolRow),
                        isEditMode: uiEditMode,
                        isAtBottom: $toolRowAtBottom
                    )
                }
                if !colorRowAtBottom {
                    DraggableToolRow(
                        content: AnyView(colorRow),
                        isEditMode: uiEditMode,
                        isAtBottom: $colorRowAtBottom
                    )
                }
            }
            .padding(.top, 4)
            Spacer()
        }
    }
    
    var bottomToolbarContent: some View {
        VStack(spacing: 6) {
            if toolRowAtBottom {
                DraggableToolRow(
                    content: AnyView(toolRow),
                    isEditMode: uiEditMode,
                    isAtBottom: $toolRowAtBottom
                )
            }
            if colorRowAtBottom {
                DraggableToolRow(
                    content: AnyView(colorRow),
                    isEditMode: uiEditMode,
                    isAtBottom: $colorRowAtBottom
                )
            }
        }
    }
    
    var drawingInfoLayer: some View {
        Group {
            if drawingEngine.isDrawing || straightLineState.isDrawing {
                VStack { Spacer(); drawingInfoBar }
            }
        }
    }
    
    var selectionLayer: some View {
        EmptyView()
    }
    
    var effectLayer: some View {
        Group {
            if effectMode != .none { effectIndicator }
        }
    }
    
    var modalsLayer: some View {
        ZStack {
            if showBrushPicker { brushPickerModal }
            if showBrushNotes { brushNotesModal }
            if showBrushStudio { brushStudioModal }
            if showExport { exportModal }
            if showDrawingModes { drawingModesModal }
            if showImageSelector { imageSelectorModal }
            if showPerformanceSettings { performanceSettingsModal }
            if showMIDISettings { midiSettingsModal }
        }
    }
    
    var brushStudioModal: some View {
        BrushStudioView(
            presetManager: brushPresetManager,
            onApply: { preset in
                drawingEngine.applyPreset(preset)
                showBrushStudio = false
            },
            onDismiss: {
                showBrushStudio = false
            }
        )
    }
    
    var performanceSettingsModal: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { showPerformanceSettings = false }
            PerformanceSettingsPanel(performanceManager: performanceManager) {
                showPerformanceSettings = false
            }
        }
    }
    
    var midiSettingsModal: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { showMIDISettings = false }
            MIDISettingsView(midiManager: midiManager)
        }
    }
    
    func setupControllerObservers() {
        // Photo picker
        Task {
            for await _ in selectedPhotoItem.publisher.values {
                handleImagePick(selectedPhotoItem)
            }
        }
    }
}

// MARK: - Top Bar
extension ContentView {
    var compactTopBar: some View {
        VStack(spacing: 4) {
            toolRow
            colorRow
        }
        .padding(.top, 2)
    }
    
    var toolRow: some View {
        HStack(spacing: 8) {
            Spacer()
            
            // 1. Drawing mode
            SmallToolBtn(icon: drawingMode.icon, size: 32, hl: drawingMode != .freehand) { showDrawingModes.toggle() }
            
            // 2. Brush picker
            Button(action: { showBrushPicker.toggle() }) {
                SmallToolBtnView(icon: drawingEngine.selectedBrushType.icon, size: 32, hl: false)
            }
            
            // 3. Brush Studio - highlight when studio preset is active
            SmallToolBtn(icon: "slider.horizontal.3", size: 32, hl: drawingEngine.useStudioPreset) { showBrushStudio = true }
            
            // 4. Crosshair toggle
            SmallToolBtn(icon: showCrosshair ? "plus.circle.fill" : "plus.circle", size: 32, hl: showCrosshair) { showCrosshair.toggle() }
            
            // 5. Export
            SmallToolBtn(icon: "square.and.arrow.up", size: 32) { showExport = true }
            
            // 6. Undo
            SmallToolBtn(icon: "arrow.uturn.backward", size: 32) { drawingEngine.undoLastStroke() }
            
            // 7. Redo
            SmallToolBtn(icon: "arrow.uturn.forward", size: 32) { drawingEngine.redoLastStroke() }
            
            // 8. Clear
            SmallToolBtn(icon: "trash", size: 32) { drawingEngine.clearAllStrokes() }
            
            Spacer()
        }
        .padding(.horizontal, 8)
    }
    
    var colorRow: some View {
        let hasControllerColor = drawingEngine.controllerColor != nil
        let colorSpacing: CGFloat = hasControllerColor ? 4 : 6
        
        return HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: colorSpacing) {
                    // Controller color indicator - wheel icon with color center
                    if hasControllerColor {
                        ZStack {
                            // Rainbow ring
                            Circle()
                                .fill(
                                    AngularGradient(
                                        colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                                        center: .center
                                    )
                                )
                                .frame(width: 26, height: 26)
                            // Selected color center
                            Circle()
                                .fill(drawingEngine.controllerColor!)
                                .frame(width: 14, height: 14)
                            // 3D effect
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.white.opacity(0.4), Color.clear],
                                        center: .topLeading,
                                        startRadius: 0,
                                        endRadius: 10
                                    )
                                )
                                .frame(width: 14, height: 14)
                            // Selection ring
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 30, height: 30)
                        }
                    }
                    
                    // Color wheel button (rainbow circle)
                    colorWheelButton
                    
                    // Regular colors
                    ForEach(drawingEngine.availableColors.indices, id: \.self) { i in
                        colorCircle(index: i)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    var colorWheelButton: some View {
        Button(action: { showColorWheel.toggle() }) {
            ZStack {
                // Rainbow gradient
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        )
                    )
                    .frame(width: 28, height: 28)
                // 3D highlight
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.5), Color.clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 18
                        )
                    )
                    .frame(width: 26, height: 26)
                // Bottom shadow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.clear, Color.black.opacity(0.3)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 14
                        )
                    )
                    .frame(width: 28, height: 28)
                // Selection indicator
                if showColorWheel {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 30, height: 30)
                }
            }
        }
    }
    
    func handlePaintImagePick(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                tempPaintImage = image
                imagePaintSource.setImage(image)
            }
        }
    }
    
    func colorCircle(index: Int) -> some View {
        let selected = drawingEngine.selectedColorIndex == index && !drawingEngine.useImageColors && drawingEngine.controllerColor == nil
        let color = drawingEngine.availableColors[index]
        return ZStack {
            // Outer shadow for depth
            Circle()
                .fill(Color.black.opacity(0.4))
                .frame(width: 30, height: 30)
                .offset(x: 1, y: 2)
                .blur(radius: 2)
            
            // Base color
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
            
            // Inner gradient for sphere effect
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), Color.clear, color.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
            
            // Top-left specular highlight (glossy)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.7), Color.white.opacity(0.2), Color.clear],
                        center: UnitPoint(x: 0.3, y: 0.25),
                        startRadius: 0,
                        endRadius: 14
                    )
                )
                .frame(width: 26, height: 26)
            
            // Rim light at bottom
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.clear, Color.white.opacity(0.3), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .frame(width: 27, height: 27)
            
            if selected {
                Circle()
                    .stroke(Color.white, lineWidth: 2.5)
                    .frame(width: 32, height: 32)
                Circle()
                    .stroke(Color.black.opacity(0.4), lineWidth: 1)
                    .frame(width: 36, height: 36)
            }
        }
        .onTapGesture {
            drawingEngine.selectedColorIndex = index
            drawingEngine.useImageColors = false
            drawingEngine.clearControllerColor()
        }
    }
}

// MARK: - Indicators & Info
extension ContentView {
    var indicatorsOverlay: some View {
        EmptyView()
    }
    
    var cpuBadge: some View {
        EmptyView()
    }
    
    @ViewBuilder
    var controllerBadge: some View {
        if controllerManager.isConnected {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
                .padding(4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
        }
    }
    
    var drawingInfoBar: some View {
        HStack {
            if drawingEngine.isDrawing {
                Circle().fill(Color.red).frame(width: 6, height: 6)
            }
            if drawingMode == .straightLine {
                Text("LINE").font(.system(size: 8, weight: .bold)).foregroundColor(.yellow)
            }
            Spacer()
            infoValues
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black.opacity(0.6)).cornerRadius(8)
        .padding(.horizontal, 12).padding(.bottom, 30)
    }
    
    var infoValues: some View {
        HStack(spacing: 6) {
            Text("\(String(format: "%.1f", drawingEngine.brushSize * 100))cm").font(.system(size: 9, design: .monospaced))
            Circle().fill(drawingEngine.currentColor).frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
        }
    }
}

// MARK: - Draggable Tool Row
struct DraggableToolRow: View {
    let content: AnyView
    let isEditMode: Bool
    @Binding var isAtBottom: Bool
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    var body: some View {
        content
            .opacity(isEditMode ? 0.7 : 1.0)
            .overlay(
                Group {
                    if isEditMode {
                        // Edit mode overlay
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.cyan.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                            .padding(.horizontal, 8)
                    }
                }
            )
            .offset(y: dragOffset)
            .scaleEffect(isEditMode ? (isDragging ? 1.05 : 1.0) : 1.0)
            .animation(.spring(response: 0.3), value: isDragging)
            .rotationEffect(isEditMode && !isDragging ? .degrees(Double.random(in: -0.5...0.5)) : .zero)
            .animation(isEditMode ? .easeInOut(duration: 2).repeatForever(autoreverses: true) : .default, value: isEditMode)
            .gesture(
                isEditMode ?
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        isDragging = false
                        // If dragged more than 100 points, toggle position
                        if abs(value.translation.height) > 100 {
                            withAnimation(.spring(response: 0.4)) {
                                isAtBottom.toggle()
                            }
                        }
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = 0
                        }
                    }
                : nil
            )
    }
}

// MARK: - Selection & Effect
extension ContentView {
    var effectIndicator: some View {
        VStack {
            HStack {
                Spacer()
                Text(effectMode.rawValue).font(.system(size: 10, weight: .bold)).foregroundColor(.black)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(effectMode.color).cornerRadius(6)
            }
            .padding(.top, 90).padding(.trailing, 8)
            Spacer()
        }
    }
}

// MARK: - Modals
extension ContentView {
    var brushPickerModal: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea().onTapGesture { showBrushPicker = false }
            CompactBrushPickerReal(drawingEngine: drawingEngine, ratingManager: brushRatingManager,
                onSelect: { 
                    // Disable studio preset when selecting from palette
                    drawingEngine.disableStudioPreset()
                    showBrushPicker = false 
                },
                onNotes: { b in notesForBrush = b; showBrushNotes = true })
        }
    }
    
    var brushNotesModal: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { showBrushNotes = false }
            BrushNotesView(brushType: notesForBrush, ratingManager: brushRatingManager, onDismiss: { showBrushNotes = false })
        }
    }
    
    var exportModal: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            ExportView(strokes: drawingEngine.strokes, onDismiss: { showExport = false })
        }
    }
    
    var drawingModesModal: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { showDrawingModes = false }
            DrawingModePicker(selectedMode: $drawingMode, onDismiss: { showDrawingModes = false })
        }
    }
    
    var imageSelectorModal: some View {
        ImageSelectorView(imageSelection: drawingEngine.imageSelection,
            onConfirm: { drawingEngine.loadImageColors(); showImageSelector = false },
            onCancel: { drawingEngine.imageSelection.selectedImage = nil; showImageSelector = false })
    }
    
    // Color wheel popup overlay
    var colorWheelOverlay: some View {
        ZStack {
            // Background tap to dismiss
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showColorWheel = false }
            
            VStack {
                Spacer().frame(height: 140)
                
                HStack {
                    Spacer()
                    ColorWheelPickerView(
                        hue: $colorWheelHue,
                        saturation: $colorWheelSaturation,
                        onColorSelected: { color in
                            drawingEngine.controllerColor = color
                        }
                    )
                    .frame(width: 200, height: 220)
                    .padding(.trailing, 20)
                }
                
                Spacer()
            }
        }
    }
}

// MARK: - Color Wheel Picker View
struct ColorWheelPickerView: View {
    @Binding var hue: CGFloat
    @Binding var saturation: CGFloat
    var onColorSelected: (Color) -> Void
    
    var selectedColor: Color {
        Color(hue: hue, saturation: saturation, brightness: 1.0)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Color wheel
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.2), Color(white: 0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                VStack(spacing: 10) {
                    // Color wheel circle
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                    center: .center
                                )
                            )
                            .frame(width: 140, height: 140)
                        
                        // Saturation overlay (white center)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white, .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 70
                                )
                            )
                            .frame(width: 140, height: 140)
                        
                        // Selection indicator
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 20, height: 20)
                            .offset(
                                x: cos(hue * .pi * 2 - .pi / 2) * saturation * 60,
                                y: sin(hue * .pi * 2 - .pi / 2) * saturation * 60
                            )
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let center = CGPoint(x: 70, y: 70)
                                let dx = value.location.x - center.x
                                let dy = value.location.y - center.y
                                let angle = atan2(dy, dx)
                                hue = CGFloat((angle + .pi / 2) / (.pi * 2))
                                if hue < 0 { hue += 1 }
                                saturation = min(1, sqrt(dx*dx + dy*dy) / 70)
                                onColorSelected(selectedColor)
                            }
                    )
                    
                    // Selected color preview
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedColor)
                            .frame(width: 50, height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                        
                        Text("Selected")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Handlers
extension ContentView {
    func handleImagePick(_ item: PhotosPickerItem?) {
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
    
    func updateHue() {
        let x = controllerManager.leftStickX, y = controllerManager.leftStickY
        let mag = sqrt(x * x + y * y)
        if mag > 0.2 {
            let angle = atan2(y, x)
            let hue = (angle + Float.pi) / (2 * Float.pi)
            drawingEngine.hueShift = (hue - 0.5) * (mag > 0.8 ? 1.0 : 0.3)
            drawingEngine.updateCurrentStrokeColor()
        } else { drawingEngine.hueShift = 0 }
    }
    
    func cycleBrush(forward: Bool) {
        let b = BrushType.allCases
        guard let i = b.firstIndex(of: drawingEngine.selectedBrushType) else { return }
        drawingEngine.selectedBrushType = b[forward ? (i + 1) % b.count : (i - 1 + b.count) % b.count]
        drawingEngine.updateCurrentStrokeBrushType()
    }
    
    func cycleColor(forward: Bool) {
        let c = drawingEngine.availableColors.count, i = drawingEngine.selectedColorIndex
        drawingEngine.selectedColorIndex = forward ? (i + 1) % c : (i - 1 + c) % c
        drawingEngine.useImageColors = false
        drawingEngine.clearControllerColor()  // Tyhjennä controller-väri jotta palataan preset-väreihin
        drawingEngine.updateCurrentStrokeColor()
    }
    
    func handleLB(_ p: Bool) { if p { effectMode = .rainbow } else if effectMode == .rainbow { effectMode = .none } }
    func handleRB(_ p: Bool) { if p { effectMode = .pulse } else if effectMode == .pulse { effectMode = .none } }
    func handleLT(_ v: Float) { if v > 0.5 { effectMode = .scatter } else if effectMode == .scatter { effectMode = .none } }
    func handleRT(_ v: Float) { if v > 0.5 { effectMode = .glow } else if effectMode == .glow { effectMode = .none } }
    
    func resetColorAndOpacity() {
        drawingEngine.opacity = 1.0
        drawingEngine.hueShift = 0
        drawingEngine.clearControllerColor()
        drawingEngine.updateCurrentStrokeColor()
    }
    
    func handleColorWheelStick() {
        let x = controllerManager.leftStickX
        let y = controllerManager.leftStickY
        
        let magnitude = sqrt(x * x + y * y)
        guard magnitude > 0.1 else { return }
        
        let speed: CGFloat = magnitude > 0.9 ? 0.015 : 0.003
        
        colorWheelHue += CGFloat(x) * speed
        if colorWheelHue > 1 { colorWheelHue -= 1 }
        if colorWheelHue < 0 { colorWheelHue += 1 }
        
        colorWheelSaturation = max(0.1, min(1.0, colorWheelSaturation - CGFloat(y) * speed * 2))
        
        let color = Color(hue: colorWheelHue, saturation: colorWheelSaturation, brightness: 1.0)
        drawingEngine.controllerColor = color
    }
}

// MARK: - Recording Manager
@MainActor
class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var showSaveSuccess = false
    @Published var errorMessage: String?
    
    private var recorder = RPScreenRecorder.shared()
    private var timer: Timer?
    private var startTime: Date?
    
    var canRecord: Bool { recorder.isAvailable }
    
    func startRecording() {
        guard canRecord, !isRecording else { return }
        recorder.startRecording { [weak self] error in
            Task { @MainActor in
                if let error = error { self?.errorMessage = error.localizedDescription; return }
                self?.isRecording = true
                self?.startTime = Date()
                self?.startTimer()
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        recorder.stopRecording { [weak self] preview, error in
            Task { @MainActor in
                self?.isRecording = false
                self?.stopTimer()
                if let error = error { self?.errorMessage = error.localizedDescription; return }
                if let preview = preview {
                    preview.previewControllerDelegate = self
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.windows.first?.rootViewController {
                        root.present(preview, animated: true)
                    }
                }
            }
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let start = self?.startTime { self?.recordingTime = Date().timeIntervalSince(start) }
            }
        }
    }
    
    private func stopTimer() { timer?.invalidate(); timer = nil; recordingTime = 0 }
}

extension RecordingManager: RPPreviewViewControllerDelegate {
    nonisolated func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        Task { @MainActor in
            previewController.dismiss(animated: true)
            showSaveSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showSaveSuccess = false }
        }
    }
}

// MARK: - Screenshot Manager
@MainActor
class ScreenshotManager: ObservableObject {
    @Published var showSaveSuccess = false
    @Published var errorMessage: String?
    @Published var isFreezing = false
    
    func takeScreenshot(from arView: ARView, freezeDuration: Double = 0.15, onFreeze: (() -> Void)? = nil) {
        // Trigger haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Signal freeze start
        isFreezing = true
        onFreeze?()
        
        arView.snapshot(saveToHDR: false) { [weak self] image in
            Task { @MainActor in
                guard let image = image else {
                    self?.errorMessage = "Screenshot failed"
                    self?.isFreezing = false
                    return
                }
                self?.saveToPhotos(image)
                
                // Keep freeze for duration
                DispatchQueue.main.asyncAfter(deadline: .now() + freezeDuration) {
                    self?.isFreezing = false
                }
            }
        }
    }
    
    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            Task { @MainActor in
                guard status == .authorized || status == .limited else { self?.errorMessage = "Access denied"; return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                self?.showSaveSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showSaveSuccess = false }
            }
        }
    }
}

// MARK: - Recording Controls
struct RecordingControlsView: View {
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var screenshotManager: ScreenshotManager
    let onScreenshot: () -> Void
    @Binding var freezeTime: Double
    @Binding var showFreezeSlider: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Freeze time slider (väliaikainen)
            if showFreezeSlider {
                VStack(spacing: 4) {
                    Text("Freeze: \(String(format: "%.2f", freezeTime))s")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                    Slider(value: $freezeTime, in: 0.05...0.5, step: 0.01)
                        .frame(width: 120)
                        .accentColor(.cyan)
                }
                .padding(8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
            }
            
            HStack(spacing: 16) {
                // Screenshot button - long press shows slider
                Button(action: onScreenshot) {
                    Image(systemName: "camera.fill").font(.system(size: 20)).foregroundColor(.white)
                        .frame(width: 50, height: 50).background(Color.black.opacity(0.6)).clipShape(Circle())
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        showFreezeSlider.toggle()
                    }
                )
                
                Button(action: { recordingManager.isRecording ? recordingManager.stopRecording() : recordingManager.startRecording() }) {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.6)).frame(width: 70, height: 70)
                        if recordingManager.isRecording {
                            RoundedRectangle(cornerRadius: 4).fill(Color.red).frame(width: 24, height: 24)
                        } else {
                            Circle().fill(Color.red).frame(width: 30, height: 30)
                        }
                    }
                }.disabled(!recordingManager.canRecord)
                if recordingManager.isRecording {
                    Text(String(format: "%02d:%02d.%d", Int(recordingManager.recordingTime) / 60, Int(recordingManager.recordingTime) % 60, Int((recordingManager.recordingTime.truncatingRemainder(dividingBy: 1)) * 10)))
                        .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.red)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Color.black.opacity(0.6)).cornerRadius(6)
                }
            }
        }
    }
}

// MARK: - Toast
struct SaveSuccessToast: View {
    let message: String
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text(message).font(.system(size: 14, weight: .medium))
        }.foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.black.opacity(0.8)).cornerRadius(20)
    }
}



// MARK: - Crosshair View - simple circle with dot
struct CrosshairView: View {
    let color: Color
    let depthDistance: Float  // 0.3m default brush distance
    
    init(color: Color, depthDistance: Float = 0.3) {
        self.color = color
        self.depthDistance = depthDistance
    }
    
    var body: some View {
        let darkColor = darken(color)
        
        ZStack {
            // Outer circle
            Circle()
                .stroke(darkColor.opacity(0.6), lineWidth: 1)
                .frame(width: 20, height: 20)
            
            // Inner dot
            Circle()
                .fill(darkColor.opacity(0.8))
                .frame(width: 4, height: 4)
        }
    }
    
    func darken(_ color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: r * 0.4, green: g * 0.4, blue: b * 0.4)
    }
}

// MARK: - Selection Mode Overlay
struct SelectionModeOverlay: View {
    @ObservedObject var selectionManager: StrokeSelectionManager
    @ObservedObject var drawingEngine: DrawingEngine
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                // Selection mode indicator
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.yellow)
                    Text("SELECT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.yellow)
                }
                
                if selectionManager.hasSelection {
                    Text("\(selectionManager.selectedStrokeIDs.count) selected")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                    
                    Button(action: { selectionManager.clearSelection() }) {
                        Text("Clear")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(4)
                    }
                } else {
                    Text("Long press to select")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.7))
            .cornerRadius(10)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let strokesNeedUpdate = Notification.Name("strokesNeedUpdate")
    static let drawingLockReleased = Notification.Name("drawingLockReleased")
}

// MARK: - Small Tool Button with metallic gradient
struct SmallToolBtn: View {
    let icon: String
    var size: CGFloat = 32
    var hl: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            SmallToolBtnView(icon: icon, size: size, hl: hl)
        }
    }
}

// View-only version (no button)
struct SmallToolBtnView: View {
    let icon: String
    var size: CGFloat = 32
    var hl: Bool = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: hl ? [Color.yellow.opacity(0.95), Color.orange.opacity(0.8), Color.yellow.opacity(0.6)] 
                                  : [Color(white: 0.55), Color(white: 0.35), Color(white: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.4), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size - 2, height: size - 2)
            
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundColor(hl ? .black : .white)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
    }
}

// MARK: - Effect Mode
enum EffectMode: String {
    case none = "None"
    case rainbow = "Rainbow"
    case pulse = "Pulse"
    case scatter = "Scatter"
    case glow = "Glow"
    
    var color: Color {
        switch self {
        case .none: return .clear
        case .rainbow: return .purple
        case .pulse: return .cyan
        case .scatter: return .orange
        case .glow: return .yellow
        }
    }
}

// MARK: - Background Mode
enum BackgroundMode: String, CaseIterable {
    case ar = "AR"
    case black = "Black"
    case white = "White"
    case green = "Green"
    
    var color: UIColor? {
        switch self {
        case .ar: return nil
        case .black: return .black
        case .white: return .white
        case .green: return UIColor(red: 0, green: 1, blue: 0, alpha: 1)
        }
    }
}

// MARK: - Camera Settings
class CameraSettings: ObservableObject {
    @Published var backgroundMode: BackgroundMode = .ar
}

// MARK: - Compact Brush Picker Real
struct CompactBrushPickerReal: View {
    @ObservedObject var drawingEngine: DrawingEngine
    @ObservedObject var ratingManager: BrushRatingManager
    let onSelect: () -> Void
    let onNotes: (BrushType) -> Void
    
    let columns = [GridItem(.adaptive(minimum: 60))]
    
    func getRating(for brush: BrushType) -> Int {
        Int(ratingManager.getAverageStars(for: brush) ?? 0)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(BrushType.allCases, id: \.self) { brush in
                    BrushButton(
                        brush: brush,
                        isSelected: drawingEngine.selectedBrushType == brush,
                        rating: getRating(for: brush),
                        onTap: {
                            drawingEngine.selectedBrushType = brush
                            onSelect()
                        },
                        onLongPress: { onNotes(brush) }
                    )
                }
            }
            
            Divider().background(Color.white.opacity(0.3))
            
            HStack {
                Image(systemName: drawingEngine.selectedBrushType.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.yellow)
                Text(drawingEngine.selectedBrushType.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= getRating(for: drawingEngine.selectedBrushType) ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                        .font(.system(size: 16))
                        .onTapGesture {
                            ratingManager.addRating(brushType: drawingEngine.selectedBrushType, stars: star, notes: "")
                        }
                }
                Button(action: { onNotes(drawingEngine.selectedBrushType) }) {
                    Image(systemName: "note.text")
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .padding()
    }
}

struct BrushButton: View {
    let brush: BrushType
    let isSelected: Bool
    let rating: Int
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: brush.icon)
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .yellow : .white)
                Text(brush.rawValue)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                if rating > 0 {
                    HStack(spacing: 1) {
                        Text("\(rating)")
                            .font(.system(size: 8, weight: .bold))
                        Image(systemName: "star.fill")
                            .font(.system(size: 6))
                    }
                    .foregroundColor(.yellow)
                }
            }
            .frame(width: 60, height: 60)
            .background(isSelected ? Color.white.opacity(0.2) : Color.gray.opacity(0.3))
            .cornerRadius(8)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() }
        )
    }
}

// MARK: - Brush Notes View
struct BrushNotesView: View {
    let brushType: BrushType
    @ObservedObject var ratingManager: BrushRatingManager
    let onDismiss: () -> Void
    
    @State private var noteText: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: brushType.icon)
                    .font(.system(size: 24))
                    .foregroundColor(.yellow)
                Text(brushType.rawValue)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            
            TextEditor(text: $noteText)
                .frame(height: 120)
                .cornerRadius(8)
            
            Button("Save") {
                ratingManager.addRating(brushType: brushType, stars: 0, notes: noteText)
                onDismiss()
            }
            .foregroundColor(.cyan)
        }
        .padding()
        .background(Color.black.opacity(0.9))
        .cornerRadius(16)
        .padding()
        .onAppear {
            let ratings = ratingManager.getRatings(for: brushType)
            noteText = ratings.first?.notes ?? ""
        }
    }
}

// MARK: - Image Selector View
struct ImageSelectorView: View {
    @ObservedObject var imageSelection: ImageSelectionState
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            VStack {
                if let image = imageSelection.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                }
                
                HStack(spacing: 20) {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(.red)
                    Button("Use Colors") { onConfirm() }
                        .foregroundColor(.green)
                }
                .padding()
            }
        }
    }
}
