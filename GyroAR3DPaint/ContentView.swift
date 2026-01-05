import SwiftUI
import PhotosUI
import RealityKit
import ReplayKit
import Photos
import AVFoundation
import Combine

struct ContentView: View {
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
    
    @State private var showBrushPicker = false
    @State private var showBrushNotes = false
    @State private var notesForBrush: BrushType = .smooth
    @State private var showImagePicker = false
    @State private var showImageSelector = false
    @State private var showExport = false
    @State private var showDrawingModes = false
    @State private var showGallery = false
    @State private var showImageCrop = false
    @State private var showPaintImagePicker = false
    @State private var paintPhotoItem: PhotosPickerItem?
    @State private var tempPaintImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var drawingMode: DrawingMode = .freehand
    @State private var effectMode: EffectMode = .none
    @State private var showControllerIcon = false
    @State private var showCrosshair = true  // Tähtäin on/off
    @State private var arViewRef: ARView?
    
    @Binding var shouldExit: Bool
    
    init(shouldExit: Binding<Bool>) {
        self._shouldExit = shouldExit
    }
    
    var body: some View {
        mainZStack
            .photosPicker(isPresented: $showImagePicker, selection: $selectedPhotoItem, matching: .images)
            .photosPicker(isPresented: $showPaintImagePicker, selection: $paintPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, n in handleImagePick(n) }
            .onChange(of: paintPhotoItem) { _, n in handlePaintImagePick(n) }
            .onAppear { cameraSettings.backgroundMode = .white; startTremoloTimer(); setupControllerBindings(); setupAirPodsBinding() }
    }
    
    func setupControllerBindings() {
        // Use Combine to observe controller changes
        controllerManager.$dpadUp.sink { [self] p in if p { handleDpadUp() } }.store(in: &controllerCancellables)
        controllerManager.$dpadDown.sink { [self] p in if p { handleDpadDown() } }.store(in: &controllerCancellables)
        controllerManager.$dpadLeft.sink { [self] p in if p { handleDpadLeft() } }.store(in: &controllerCancellables)
        controllerManager.$dpadRight.sink { [self] p in if p { handleDpadRight() } }.store(in: &controllerCancellables)
        controllerManager.$leftStickX.sink { [self] _ in handleLeftStick() }.store(in: &controllerCancellables)
        controllerManager.$leftStickY.sink { [self] _ in handleLeftStick() }.store(in: &controllerCancellables)
        controllerManager.$rightStickX.sink { [self] v in 
            if !selectionManager.isSelectionMode {
                drawingEngine.opacity = max(0.1, min(1.0, (v + 1) / 2)) 
            }
        }.store(in: &controllerCancellables)
        controllerManager.$leftBumper.sink { [self] p in if p { drawingEngine.randomizeColor() } }.store(in: &controllerCancellables)
        controllerManager.$rightBumper.sink { [self] p in if p { drawingEngine.invertColor() } }.store(in: &controllerCancellables)
        controllerManager.$leftTrigger.sink { [self] v in drawingEngine.brushSizeMultiplier = 1.0 + v * 2.0 }.store(in: &controllerCancellables)
        controllerManager.$rightTrigger.sink { [self] v in drawingEngine.sparkleAmount = v }.store(in: &controllerCancellables)
        controllerManager.$buttonB.sink { [self] p in if p { drawingEngine.clearAllStrokes() } }.store(in: &controllerCancellables)
        controllerManager.$buttonX.sink { [self] p in if p { drawingEngine.undoLastStroke() } }.store(in: &controllerCancellables)
        controllerManager.$buttonA.sink { [self] p in if p { resetColorAndOpacity() } }.store(in: &controllerCancellables)
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
    
    func handleLeftStick() {
        if selectionManager.isSelectionMode {
            moveSelectedStrokes()
        } else {
            updateColorWheel()
        }
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
            arLayer
            
            // Crosshair (tähtäin)
            if showCrosshair && !selectionManager.isSelectionMode {
                CrosshairView(color: drawingEngine.currentColor)
            }
            
            // Selection mode indicator
            if selectionManager.isSelectionMode {
                SelectionModeOverlay(selectionManager: selectionManager, drawingEngine: drawingEngine)
            }
            
            // Hide UI when recording
            if !recordingManager.isRecording {
                topBarLayer
                indicatorsOverlay
                drawingInfoLayer
                effectLayer
            }
            recordingLayer
            if !recordingManager.isRecording {
                modalsLayer
            }
            toastLayer
            
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
            
            // Gallery
            if showGallery {
                GalleryView(
                    galleryManager: galleryManager,
                    onDismiss: { showGallery = false },
                    onSelect: { item in
                        showGallery = false
                    }
                )
            }
        }
        .statusBarHidden(recordingManager.isRecording)
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
        .ignoresSafeArea()
    }
    
    var recordingLayer: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                // Screenshot button
                Button(action: { takeScreenshotToGallery() }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                
                // Record button
                Button(action: {
                    if recordingManager.isRecording { recordingManager.stopRecording() }
                    else { recordingManager.startRecording() }
                }) {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.6)).frame(width: 70, height: 70)
                        if recordingManager.isRecording {
                            RoundedRectangle(cornerRadius: 4).fill(Color.red).frame(width: 24, height: 24)
                        } else {
                            Circle().fill(Color.red).frame(width: 30, height: 30)
                        }
                    }
                }
                .disabled(!recordingManager.canRecord)
                
                // Background mode button (cycle through modes)
                Button(action: { cycleBackgroundMode() }) {
                    ZStack {
                        Circle()
                            .fill(backgroundModeColor)
                            .frame(width: 44, height: 44)
                        if cameraSettings.backgroundMode == .ar {
                            Text("AR").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                        }
                    }
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                }
                
                // Gallery button
                Button(action: { showGallery = true }) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
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
            .padding(.bottom, 30)
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
        arView.snapshot(saveToHDR: false) { [self] image in
            guard let image = image else { return }
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
        VStack(spacing: 0) { compactTopBar; Spacer() }
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
            if showExport { exportModal }
            if showDrawingModes { drawingModesModal }
            if showImageSelector { imageSelectorModal }
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
        VStack(spacing: 6) {
            toolRow
            colorRow
        }
        .padding(.top, 50)
    }
    
    var toolRow: some View {
        HStack(spacing: 10) {
            // AirPods ja controller ikonit vasemmalla
            HStack(spacing: 6) {
                AirPodsStatusView(manager: airPodsManager)
                if controllerManager.isConnected {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            // Crosshair toggle
            SmallToolBtn(icon: "plus.circle", size: 30, hl: showCrosshair) { showCrosshair.toggle() }
            
            // Selector tool
            SmallToolBtn(icon: "hand.tap", size: 30, hl: selectionManager.isSelectionMode) { 
                selectionManager.toggleSelectionMode() 
            }
            
            SmallToolBtn(icon: drawingMode.icon, size: 30, hl: drawingMode != .freehand) { showDrawingModes.toggle() }
            SmallToolBtn(icon: drawingEngine.selectedBrushType.icon, size: 30) { showBrushPicker.toggle() }
            SmallToolBtn(icon: "square.and.arrow.up", size: 30) { showExport = true }
            SmallToolBtn(icon: "arrow.uturn.backward", size: 30) { drawingEngine.undoLastStroke() }
            SmallToolBtn(icon: "trash", size: 30) { drawingEngine.clearAllStrokes() }
        }
        .padding(.horizontal, 12)
    }
    
    var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Controller color indicator (if active)
                if drawingEngine.controllerColor != nil {
                    ZStack {
                        Circle()
                            .fill(drawingEngine.controllerColor!)
                            .frame(width: 28, height: 28)
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 28, height: 28)
                        Circle()
                            .stroke(Color.black, lineWidth: 1)
                            .frame(width: 32, height: 32)
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                // Paint from image button (rainbow circle)
                paintImageButton
                
                // Regular colors
                ForEach(drawingEngine.availableColors.indices, id: \.self) { i in
                    colorCircle(index: i)
                }
                if !drawingEngine.imageColors.isEmpty {
                    imageColorButton
                }
            }
            .padding(.horizontal, 12)
        }
    }
    
    var paintImageButton: some View {
        // Rainbow gradient circle for "paint from image"
        Button(action: { showPaintImagePicker = true }) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                            center: .center
                        )
                    )
                    .frame(width: 28, height: 28)
                if imagePaintSource.isActive {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    if imagePaintSource.sourceImage != nil {
                        tempPaintImage = imagePaintSource.sourceImage
                        showImageCrop = true
                    } else {
                        showPaintImagePicker = true
                    }
                }
        )
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
        return ZStack {
            Circle()
                .fill(drawingEngine.availableColors[index])
                .frame(width: 28, height: 28)
            if selected {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 28, height: 28)
                Circle()
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: 32, height: 32)
            }
        }
        .onTapGesture { 
            drawingEngine.selectedColorIndex = index
            drawingEngine.useImageColors = false
            drawingEngine.clearControllerColor()
        }
    }
    
    var imageColorButton: some View {
        let colors = Array(drawingEngine.imageColors.prefix(6))
        let selected = drawingEngine.useImageColors
        return ZStack {
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .frame(width: 44, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            if selected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 44, height: 28)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: 48, height: 32)
            }
        }
        .onTapGesture { 
            drawingEngine.useImageColors.toggle()
            if drawingEngine.useImageColors {
                drawingEngine.clearControllerColor()
            }
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
                onSelect: { showBrushPicker = false },
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
        drawingEngine.clearControllerColor()
        // Väri pysyy samana kuin ennen controller-säätöä (selectedColorIndex säilyy)
    }
}

// MARK: - Small Tool Button
struct SmallToolBtn: View {
    let icon: String
    var size: CGFloat = 32
    var hl: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.5)).foregroundColor(hl ? .yellow : .white)
                .frame(width: size, height: size).background(Color.black.opacity(0.5)).clipShape(Circle())
        }
    }
}

// MARK: - Compact Brush Picker Real
struct CompactBrushPickerReal: View {
    @ObservedObject var drawingEngine: DrawingEngine
    @ObservedObject var ratingManager: BrushRatingManager
    let onSelect: () -> Void; let onNotes: (BrushType) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            brushGrid
            Divider().background(Color.white.opacity(0.3))
            ratingRow
        }
        .padding(12).frame(width: 300)
        .background(Color.black.opacity(0.6))
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
    
    var brushGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 8) {
            ForEach(BrushType.allCases, id: \.self) { b in
                brushButton(b)
            }
        }
    }
    
    func brushButton(_ b: BrushType) -> some View {
        Button(action: { drawingEngine.selectedBrushType = b; onSelect() }) {
            VStack(spacing: 3) {
                Image(systemName: b.icon).font(.system(size: 24))
                    .foregroundColor(drawingEngine.selectedBrushType == b ? .yellow : .white)
                Text(b.rawValue).font(.system(size: 8)).foregroundColor(.gray).lineLimit(1)
                if let s = ratingManager.getAverageStars(for: b) {
                    Text("\(Int(s.rounded()))★").font(.system(size: 8, weight: .bold)).foregroundColor(.yellow)
                }
            }
            .frame(width: 54, height: 54)
            .background(drawingEngine.selectedBrushType == b ? Color.yellow.opacity(0.2) : Color.white.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    var ratingRow: some View {
        HStack {
            Image(systemName: drawingEngine.selectedBrushType.icon).font(.system(size: 16)).foregroundColor(.yellow)
            Text(drawingEngine.selectedBrushType.rawValue).font(.system(size: 12, weight: .medium)).foregroundColor(.white)
            Spacer()
            ForEach(1...5, id: \.self) { s in
                starButton(s)
            }
            Button(action: { onNotes(drawingEngine.selectedBrushType) }) {
                Image(systemName: "note.text").font(.system(size: 14)).foregroundColor(.cyan)
            }
        }.padding(.horizontal, 4)
    }
    
    func starButton(_ s: Int) -> some View {
        Button(action: { ratingManager.addRating(brushType: drawingEngine.selectedBrushType, stars: s, notes: "") }) {
            let avg = ratingManager.getAverageStars(for: drawingEngine.selectedBrushType)
            let filled = avg.map { s <= Int($0.rounded()) } ?? false
            Image(systemName: filled ? "star.fill" : "star").font(.system(size: 14)).foregroundColor(filled ? .yellow : .gray)
        }
    }
}

// MARK: - Effect Mode
enum EffectMode: String {
    case none = "", rainbow = "🌈", pulse = "💓", scatter = "✨", glow = "💡"
    var color: Color {
        switch self { case .none: return .clear; case .rainbow: return .red; case .pulse: return .pink; case .scatter: return .cyan; case .glow: return .yellow }
    }
}

// MARK: - Brush Notes View
struct BrushNotesView: View {
    let brushType: BrushType
    @ObservedObject var ratingManager: BrushRatingManager
    let onDismiss: () -> Void
    @State private var noteText = ""
    var body: some View {
        VStack(spacing: 10) {
            header
            textField
            saveBtn
        }
        .padding(12).frame(width: 240).background(Color(white: 0.12)).cornerRadius(12).foregroundColor(.white)
    }
    var header: some View {
        HStack {
            Image(systemName: brushType.icon).font(.system(size: 18))
            Text(brushType.rawValue).font(.system(size: 14, weight: .medium))
            Spacer()
            Button(action: onDismiss) { Image(systemName: "xmark.circle.fill").foregroundColor(.gray) }
        }
    }
    var textField: some View {
        TextField("Notes...", text: $noteText, axis: .vertical)
            .textFieldStyle(.plain).padding(8).background(Color.white.opacity(0.1)).cornerRadius(6)
    }
    var saveBtn: some View {
        Button("Save") {
            if !noteText.isEmpty { ratingManager.addRating(brushType: brushType, stars: 0, notes: noteText); noteText = "" }
        }
        .foregroundColor(.green).disabled(noteText.isEmpty)
    }
}

// MARK: - Image Selector View
struct ImageSelectorView: View {
    @ObservedObject var imageSelection: ImageSelectionState
    let onConfirm: () -> Void
    let onCancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Select Color Region").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                imageView
                buttons
            }.padding()
        }
    }
    var imageView: some View {
        Group {
            if let img = imageSelection.selectedImage {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: 250)
            }
        }
    }
    var buttons: some View {
        HStack(spacing: 30) {
            Button("Cancel") { onCancel() }.foregroundColor(.red)
            Button("Use") { onConfirm() }.foregroundColor(.green).fontWeight(.bold)
        }
    }
}

// MARK: - Camera Settings
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
        case .green: return UIColor(red: 0, green: 0.8, blue: 0, alpha: 1)
        }
    }
}

enum LensType: String, CaseIterable {
    case auto = "Auto"
    case wide = "Wide"
    case ultraWide = "Ultra"
    case telephoto = "Tele"
    
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .auto, .wide: return .builtInWideAngleCamera
        case .ultraWide: return .builtInUltraWideCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }
}

@MainActor
class CameraSettings: ObservableObject {
    @Published var backgroundMode: BackgroundMode = .ar
    @Published var lensType: LensType = .auto
    @Published var depthOfField: Float = 0 // 0 = off, 1 = max blur
    @Published var stabilizationEnabled = true
    @Published var exposure: Float = 0 // -2 to 2 EV
    
    var availableLenses: [LensType] {
        var lenses: [LensType] = [.auto, .wide]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera], mediaType: .video, position: .back)
        if !discovery.devices.isEmpty { lenses.append(.ultraWide) }
        let teleDiscovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTelephotoCamera], mediaType: .video, position: .back)
        if !teleDiscovery.devices.isEmpty { lenses.append(.telephoto) }
        return lenses
    }
}

// MARK: - Camera Controls Panel
struct CameraControlsPanel: View {
    @ObservedObject var settings: CameraSettings
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Camera").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
            
            Divider().background(Color.gray)
            
            // Background
            VStack(alignment: .leading, spacing: 6) {
                Text("Background").font(.system(size: 11)).foregroundColor(.gray)
                HStack(spacing: 8) {
                    ForEach(BackgroundMode.allCases, id: \.self) { mode in
                        Button(action: { settings.backgroundMode = mode }) {
                            Text(mode.rawValue).font(.system(size: 12, weight: .medium))
                                .foregroundColor(settings.backgroundMode == mode ? .black : .white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(settings.backgroundMode == mode ? Color.white : Color.white.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                }
            }
            
            Text("Tip: Use Green for chroma key editing")
                .font(.system(size: 9)).foregroundColor(.gray.opacity(0.7))
        }
        .padding(16)
        .background(Color.black.opacity(0.9))
        .cornerRadius(16)
        .frame(width: 280)
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
    
    func takeScreenshot(from arView: ARView) {
        arView.snapshot(saveToHDR: false) { [weak self] image in
            Task { @MainActor in
                guard let image = image else { self?.errorMessage = "Screenshot failed"; return }
                self?.saveToPhotos(image)
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
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: onScreenshot) {
                Image(systemName: "camera.fill").font(.system(size: 20)).foregroundColor(.white)
                    .frame(width: 50, height: 50).background(Color.black.opacity(0.6)).clipShape(Circle())
            }
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



// MARK: - Crosshair View
struct CrosshairView: View {
    let color: Color
    
    var body: some View {
        let darkColor = darken(color)
        
        ZStack {
            // Ulompi ympyrä
            Circle()
                .stroke(darkColor.opacity(0.6), lineWidth: 1)
                .frame(width: 20, height: 20)
            
            // Sisempi piste
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
}
