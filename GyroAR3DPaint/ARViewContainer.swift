import SwiftUI
import RealityKit
import ARKit
import Combine
import AVFoundation

private func makeARConfiguration(environmentTexturingEnabled: Bool) -> ARWorldTrackingConfiguration {
    let config = ARWorldTrackingConfiguration()
    config.planeDetection = []
    config.environmentTexturing = environmentTexturingEnabled ? .automatic : .none
    return config
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var drawingEngine: DrawingEngine
    @ObservedObject var controllerManager: GameControllerManager
    @ObservedObject var selectionManager: StrokeSelectionManager
    @ObservedObject var straightLineState: StraightLineState
    @Binding var drawingMode: DrawingMode
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let settings = PerformanceManager.shared.graphicsSettings
        let config = makeARConfiguration(environmentTexturingEnabled: settings.environmentTexturingEnabled)
        arView.session.run(config)
        
        context.coordinator.arView = arView
        context.coordinator.drawingEngine = drawingEngine
        context.coordinator.controllerManager = controllerManager
        context.coordinator.selectionManager = selectionManager
        context.coordinator.straightLineState = straightLineState
        context.coordinator.startFrameUpdates()
        context.coordinator.applyGraphicsSettings(to: arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.drawingMode = drawingMode
        context.coordinator.applyGraphicsSettings(to: uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    @MainActor
    class Coordinator: NSObject {
        weak var arView: ARView?
        var drawingEngine: DrawingEngine?
        var controllerManager: GameControllerManager?
        var selectionManager: StrokeSelectionManager?
        var straightLineState: StraightLineState?
        var drawingMode: DrawingMode = .freehand
        
        private var displayLink: CADisplayLink?
        private var strokeRenderer: StrokeRenderer?
        private var linePreviewEntity: ModelEntity?
        private var linePreviewAnchor: AnchorEntity?
        private var lastGraphicsSettings: PerformanceManager.GraphicsSettings?
        
        func startFrameUpdates() {
            guard let arView = arView else { return }
            
            strokeRenderer = StrokeRenderer(arView: arView)
            
            // Line preview anchor
            linePreviewAnchor = AnchorEntity(world: .zero)
            arView.scene.addAnchor(linePreviewAnchor!)
            
            displayLink = CADisplayLink(target: self, selector: #selector(frameUpdate))
            // Use performance level for frame rate
            let level = PerformanceManager.shared.currentLevel
            let targetFPS = Float(level.targetFrameRate)
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: targetFPS * 0.5, maximum: targetFPS, preferred: targetFPS)
            displayLink?.add(to: .main, forMode: .common)
            
            // Listen for selection
            NotificationCenter.default.addObserver(self, selector: #selector(handleStrokeSelected(_:)), name: .strokeSelected, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleSelectionCleared), name: .selectionCleared, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleStrokesNeedUpdate(_:)), name: .strokesNeedUpdate, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleDrawingLockReleased), name: .drawingLockReleased, object: nil)
            
            setupTouchHandling()
        }
        
        @objc func handleDrawingLockReleased() {
            // Complete the locked drawing
            handleTouchEnded()
        }
        
        @objc func handleStrokeSelected(_ notification: Notification) {
            guard let stroke = notification.object as? Stroke else { return }
            strokeRenderer?.highlightStroke(stroke)
        }
        
        @objc func handleSelectionCleared() {
            strokeRenderer?.clearHighlight()
        }
        
        @objc func handleStrokesNeedUpdate(_ notification: Notification) {
            guard let strokeIDs = notification.object as? Set<UUID>,
                  let drawingEngine = drawingEngine else { return }
            
            // Re-render updated strokes
            for stroke in drawingEngine.strokes {
                if strokeIDs.contains(stroke.id) {
                    strokeRenderer?.updateStroke(stroke)
                }
            }
        }
        
        @objc func frameUpdate() {
            guard let arView = arView,
                  let drawingEngine = drawingEngine,
                  let frame = arView.session.currentFrame else { return }
            
            let brushPosition = getBrushPosition(from: frame)
            
            // Handle controller drawing (LT/RT triggers)
            handleControllerDrawing(at: brushPosition)
            
            // Handle different drawing modes
            switch drawingMode {
            case .freehand:
                if drawingEngine.isDrawing {
                    drawingEngine.addPoint(brushPosition)
                    
                    if let currentStroke = drawingEngine.currentStroke {
                        strokeRenderer?.updateStroke(currentStroke)
                    }
                }
                
            case .straightLine, .arc, .crescendo, .diminuendo:
                if let lineState = straightLineState, lineState.isDrawing {
                    lineState.endPoint = brushPosition
                    updateLinePreview()
                }
            }
        }
        
        // Track controller drawing state for edge detection
        private var wasControllerDrawing = false
        
        private func handleControllerDrawing(at position: SIMD3<Float>) {
            guard let controllerManager = controllerManager,
                  let drawingEngine = drawingEngine,
                  controllerManager.isConnected else { return }
            
            let isDrawingNow = controllerManager.isControllerDrawing
            
            // Rising edge: started drawing
            if isDrawingNow && !wasControllerDrawing {
                // Don't interfere with selection mode
                if selectionManager?.isSelectionMode != true {
                    switch drawingMode {
                    case .freehand:
                        drawingEngine.startDrawing()
                    case .straightLine, .arc, .crescendo, .diminuendo:
                        straightLineState?.startPoint = position
                        straightLineState?.endPoint = position
                        straightLineState?.isDrawing = true
                    }
                }
            }
            
            // Falling edge: stopped drawing
            if !isDrawingNow && wasControllerDrawing {
                if selectionManager?.isSelectionMode != true {
                    handleTouchEnded()
                }
            }
            
            wasControllerDrawing = isDrawingNow
        }
        
        private func updateLinePreview() {
            guard let lineState = straightLineState,
                  let start = lineState.startPoint,
                  let end = lineState.endPoint,
                  let drawingEngine = drawingEngine else { return }
            
            // Remove old preview
            linePreviewAnchor?.children.removeAll()
            linePreviewEntity?.removeFromParent()
            linePreviewEntity = nil
            
            let distance = simd_distance(start, end)
            if distance > 0.01 {
                var material = UnlitMaterial()
                material.color = .init(tint: UIColor(drawingEngine.currentColor).withAlphaComponent(0.5))
                
                if drawingMode == .arc {
                    // Arc preview - näytä kaari pisteinä
                    let arcHeight = distance * 0.3
                    let arcUp = SIMD3<Float>(0, 1, 0)
                    let pointCount = min(40, max(10, Int(distance / 0.05)))
                    
                    let parentEntity = ModelEntity()
                    
                    for i in 0..<pointCount {
                        let t = Float(i) / Float(pointCount - 1)
                        let linearPos = start + (end - start) * t
                        let arcOffset = sin(t * .pi) * arcHeight
                        let position = linearPos + arcUp * arcOffset
                        
                        let sphere = ModelEntity(
                            mesh: .generateSphere(radius: drawingEngine.brushSize * 0.3),
                            materials: [material]
                        )
                        sphere.position = position
                        parentEntity.addChild(sphere)
                    }
                    
                    linePreviewAnchor?.addChild(parentEntity)
                    linePreviewEntity = parentEntity
                } else {
                    // Straight line preview
                    let direction = simd_normalize(end - start)
                    let midpoint = (start + end) / 2
                    
                    let mesh = MeshResource.generateCylinder(height: distance, radius: drawingEngine.brushSize * 0.5)
                    let entity = ModelEntity(mesh: mesh, materials: [material])
                    
                    let up = SIMD3<Float>(0, 1, 0)
                    let rotation = simd_quatf(from: up, to: direction)
                    entity.orientation = rotation
                    entity.position = midpoint
                    
                    linePreviewAnchor?.addChild(entity)
                    linePreviewEntity = entity
                }
            }
        }
        
        func setupTouchHandling() {
            guard let arView = arView else { return }
            
            let touchView = DrawingTouchView(frame: arView.bounds)
            touchView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            touchView.coordinator = self
            arView.addSubview(touchView)
        }

        func applyGraphicsSettings(to arView: ARView) {
            let settings = PerformanceManager.shared.graphicsSettings
            var renderOptions: ARView.RenderOptions = []
            if !settings.hdrEnabled {
                renderOptions.insert(.disableHDR)
            }
            if !settings.cameraGrainEnabled {
                renderOptions.insert(.disableCameraGrain)
            }
            if arView.renderOptions != renderOptions {
                arView.renderOptions = renderOptions
            }

            if lastGraphicsSettings?.environmentTexturingEnabled != settings.environmentTexturingEnabled {
                let config = makeARConfiguration(environmentTexturingEnabled: settings.environmentTexturingEnabled)
                arView.session.run(config)
            }
            lastGraphicsSettings = settings
        }
        
        func handleTouchBegan(at location: CGPoint, in view: UIView) {
            guard let drawingEngine = drawingEngine,
                  let arView = arView,
                  let frame = arView.session.currentFrame else { return }
            
            // Check if selection mode is active
            if selectionManager?.isSelectionMode == true {
                let brushPosition = getBrushPosition(from: frame)
                selectionManager?.startLongPress(at: brushPosition, strokes: drawingEngine.strokes)
                return
            }
            
            updateBrushSize(at: location, in: view)
            
            let brushPosition = getBrushPosition(from: frame)
            
            switch drawingMode {
            case .freehand:
                drawingEngine.startDrawing()
                
            case .straightLine, .arc, .crescendo, .diminuendo:
                straightLineState?.startPoint = brushPosition
                straightLineState?.endPoint = brushPosition
                straightLineState?.isDrawing = true
            }
        }
        
        func handleTouchMoved(at location: CGPoint, in view: UIView) {
            guard let arView = arView,
                  let frame = arView.session.currentFrame else { return }
            
            // Handle selection mode multi-select
            if selectionManager?.isSelectionMode == true && selectionManager?.isMultiSelecting == true {
                let brushPosition = getBrushPosition(from: frame)
                selectionManager?.updateLongPress(at: brushPosition, strokes: drawingEngine?.strokes ?? [])
                return
            }
            
            updateBrushSize(at: location, in: view)
        }
        
        func handleTouchEnded() {
            guard let drawingEngine = drawingEngine else { return }
            
            // Handle selection mode
            if selectionManager?.isSelectionMode == true {
                selectionManager?.endLongPress()
                selectionManager?.cancelLongPress()
                return
            }
            
            switch drawingMode {
            case .freehand:
                if let completedStroke = drawingEngine.stopDrawing() {
                    strokeRenderer?.finalizeStroke(completedStroke)
                }
                
            case .crescendo:
                // Line-based crescendo
                if let lineState = straightLineState,
                   lineState.startPoint != nil,
                   lineState.endPoint != nil {
                    
                    let points = lineState.generateCrescendoPoints(
                        brushSize: drawingEngine.brushSize,
                        color: drawingEngine.currentColor,
                        brushType: drawingEngine.selectedBrushType,
                        opacity: drawingEngine.opacity,
                        gradientValue: drawingEngine.airPodsGradientValue
                    )
                    
                    if !points.isEmpty {
                        var stroke = Stroke(color: drawingEngine.currentColor, brushType: drawingEngine.selectedBrushType)
                        for point in points { stroke.addPoint(point) }
                        drawingEngine.strokes.append(stroke)
                        strokeRenderer?.finalizeStroke(stroke)
                    }
                    
                    linePreviewAnchor?.children.removeAll()
                    linePreviewEntity?.removeFromParent()
                    linePreviewEntity = nil
                    lineState.reset()
                }
                
            case .diminuendo:
                // Line-based diminuendo
                if let lineState = straightLineState,
                   lineState.startPoint != nil,
                   lineState.endPoint != nil {
                    
                    let points = lineState.generateDiminuendoPoints(
                        brushSize: drawingEngine.brushSize,
                        color: drawingEngine.currentColor,
                        brushType: drawingEngine.selectedBrushType,
                        opacity: drawingEngine.opacity,
                        gradientValue: drawingEngine.airPodsGradientValue
                    )
                    
                    if !points.isEmpty {
                        var stroke = Stroke(color: drawingEngine.currentColor, brushType: drawingEngine.selectedBrushType)
                        for point in points { stroke.addPoint(point) }
                        drawingEngine.strokes.append(stroke)
                        strokeRenderer?.finalizeStroke(stroke)
                    }
                    
                    linePreviewAnchor?.children.removeAll()
                    linePreviewEntity?.removeFromParent()
                    linePreviewEntity = nil
                    lineState.reset()
                }
                
            case .straightLine:
                if let lineState = straightLineState,
                   lineState.startPoint != nil,
                   lineState.endPoint != nil {
                    
                    let points = lineState.generateLinePoints(
                        brushSize: drawingEngine.brushSize,
                        color: drawingEngine.currentColor,
                        brushType: drawingEngine.selectedBrushType,
                        opacity: drawingEngine.opacity,
                        gradientValue: drawingEngine.airPodsGradientValue
                    )
                    
                    if !points.isEmpty {
                        var stroke = Stroke(color: drawingEngine.currentColor, brushType: drawingEngine.selectedBrushType)
                        for point in points { stroke.addPoint(point) }
                        drawingEngine.strokes.append(stroke)
                        strokeRenderer?.finalizeStroke(stroke)
                    }
                    
                    linePreviewEntity?.removeFromParent()
                    linePreviewEntity = nil
                    lineState.reset()
                }
                
            case .arc:
                if let lineState = straightLineState,
                   lineState.startPoint != nil,
                   lineState.endPoint != nil {
                    
                    let points = lineState.generateArcPoints(
                        brushSize: drawingEngine.brushSize,
                        color: drawingEngine.currentColor,
                        brushType: drawingEngine.selectedBrushType,
                        opacity: drawingEngine.opacity,
                        gradientValue: drawingEngine.airPodsGradientValue
                    )
                    
                    if !points.isEmpty {
                        var stroke = Stroke(color: drawingEngine.currentColor, brushType: drawingEngine.selectedBrushType)
                        for point in points { stroke.addPoint(point) }
                        drawingEngine.strokes.append(stroke)
                        strokeRenderer?.finalizeStroke(stroke)
                    }
                    
                    linePreviewEntity?.removeFromParent()
                    linePreviewEntity = nil
                    lineState.reset()
                }
            }
        }
        
        private func getBrushPosition(from frame: ARFrame) -> SIMD3<Float> {
            let cameraTransform = frame.camera.transform
            let baseDistance: Float = 0.3
            // Logarithmic curve: slow start, accelerates toward max
            // At offset 0 → 0 extra, at offset 1 → 2.0m extra
            let t = drawingEngine?.drawingDistanceOffset ?? 0.0
            let extraDistance: Float = 2.0 * (log(1.0 + t * 9.0) / log(10.0))
            let brushDistance = baseDistance + extraDistance
            let forward = SIMD3<Float>(
                -cameraTransform.columns.2.x,
                -cameraTransform.columns.2.y,
                -cameraTransform.columns.2.z
            )
            return SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            ) + forward * brushDistance
        }
        
        private func updateBrushSize(at location: CGPoint, in view: UIView) {
            guard let drawingEngine = drawingEngine else { return }
            
            let screenHeight = view.bounds.height
            let normalizedY = location.y / screenHeight
            let sizeNormalized = 1.1 - (normalizedY * 1.1)
            let clampedSize = max(0, min(1, sizeNormalized))
            drawingEngine.setBrushSizeNormalized(Float(clampedSize))
        }
        
        deinit {
            displayLink?.invalidate()
        }
    }
}

class DrawingTouchView: UIView {
    weak var coordinator: ARViewContainer.Coordinator?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        coordinator?.handleTouchBegan(at: touch.location(in: self), in: self)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        coordinator?.handleTouchMoved(at: touch.location(in: self), in: self)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.handleTouchEnded()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.handleTouchEnded()
    }
}

// MARK: - ARView Container with Reference
struct ARViewContainerWithRef: UIViewRepresentable {
    @ObservedObject var drawingEngine: DrawingEngine
    @ObservedObject var controllerManager: GameControllerManager
    @ObservedObject var selectionManager: StrokeSelectionManager
    @ObservedObject var straightLineState: StraightLineState
    @ObservedObject var cameraSettings: CameraSettings
    @Binding var drawingMode: DrawingMode
    @Binding var arViewRef: ARView?
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let settings = PerformanceManager.shared.graphicsSettings
        let config = makeARConfiguration(environmentTexturingEnabled: settings.environmentTexturingEnabled)
        arView.session.run(config)
        
        context.coordinator.arView = arView
        context.coordinator.drawingEngine = drawingEngine
        context.coordinator.controllerManager = controllerManager
        context.coordinator.selectionManager = selectionManager
        context.coordinator.straightLineState = straightLineState
        context.coordinator.startFrameUpdates()
        context.coordinator.applyGraphicsSettings(to: arView)
        
        DispatchQueue.main.async { self.arViewRef = arView }
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.drawingMode = drawingMode
        context.coordinator.applyGraphicsSettings(to: uiView)
        
        // Background
        if let bgColor = cameraSettings.backgroundMode.color {
            uiView.environment.background = .color(bgColor)
        } else {
            uiView.environment.background = .cameraFeed()
        }
    }
    
    func makeCoordinator() -> ARViewContainer.Coordinator { ARViewContainer.Coordinator() }
}
