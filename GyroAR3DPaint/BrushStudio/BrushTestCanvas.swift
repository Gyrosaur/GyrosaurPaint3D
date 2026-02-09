import SwiftUI
import RealityKit
import ARKit

// MARK: - Brush Test Canvas

struct BrushTestCanvas: View {
    let preset: BrushDefinition
    
    @StateObject private var testEngine = TestDrawingEngine()
    @State private var arView: ARView?
    
    var body: some View {
        ZStack {
            // AR View with white background
            TestARViewContainer(
                testEngine: testEngine,
                preset: preset,
                arViewRef: $arView
            )
            .background(Color.white)
            
            // Overlay controls
            VStack {
                Spacer()
                
                HStack {
                    // Clear button
                    Button(action: { testEngine.clear() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Drawing indicator
                    if testEngine.isDrawing {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Drawing")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
                    }
                }
                .padding(12)
            }
            
            // Touch area hint
            if testEngine.strokes.isEmpty {
                VStack {
                    Spacer()
                    Text("Touch and drag to test brush")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.bottom, 60)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Test Drawing Engine

@MainActor
class TestDrawingEngine: ObservableObject {
    @Published var strokes: [TestStroke] = []
    @Published var currentStroke: TestStroke?
    @Published var isDrawing = false
    
    struct TestStroke: Identifiable {
        let id = UUID()
        var points: [SIMD3<Float>] = []
        var color: UIColor = .white
        var brushSize: Float = 0.01
    }
    
    func startDrawing(at position: SIMD3<Float>, color: UIColor, size: Float) {
        var stroke = TestStroke()
        stroke.color = color
        stroke.brushSize = size
        stroke.points.append(position)
        currentStroke = stroke
        isDrawing = true
    }
    
    func addPoint(_ position: SIMD3<Float>) {
        guard isDrawing else { return }
        currentStroke?.points.append(position)
    }
    
    func endDrawing() {
        if let stroke = currentStroke, stroke.points.count > 1 {
            strokes.append(stroke)
        }
        currentStroke = nil
        isDrawing = false
    }
    
    func clear() {
        strokes.removeAll()
        currentStroke = nil
        isDrawing = false
    }
}

// MARK: - Test AR View Container

struct TestARViewContainer: UIViewRepresentable {
    @ObservedObject var testEngine: TestDrawingEngine
    let preset: BrushDefinition
    @Binding var arViewRef: ARView?
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure for non-AR mode (white background)
        arView.environment.background = .color(.white)
        arView.cameraMode = .nonAR
        
        // Setup camera position
        let cameraAnchor = AnchorEntity(world: [0, 0, 0.5])
        arView.scene.addAnchor(cameraAnchor)
        
        // Add lighting
        let lightAnchor = AnchorEntity(world: [0, 1, 0])
        let light = PointLight()
        light.light.intensity = 10000
        lightAnchor.addChild(light)
        arView.scene.addAnchor(lightAnchor)
        
        // Setup gesture recognizer
        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        arView.addGestureRecognizer(panGesture)
        
        context.coordinator.arView = arView
        
        // Create renderer on main actor
        Task { @MainActor in
            context.coordinator.renderer = TestStrokeRenderer(arView: arView)
        }
        
        DispatchQueue.main.async {
            self.arViewRef = arView
        }
        
        return arView
    }
    
    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.preset = preset
        context.coordinator.testEngine = testEngine
        
        // Update rendered strokes only if renderer is ready
        if context.coordinator.renderer != nil {
            Task { @MainActor in
                context.coordinator.updateStrokes()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(testEngine: testEngine, preset: preset)
    }
    
    class Coordinator: NSObject {
        var testEngine: TestDrawingEngine
        var preset: BrushDefinition
        var arView: ARView?
        var renderer: TestStrokeRenderer?
        
        init(testEngine: TestDrawingEngine, preset: BrushDefinition) {
            self.testEngine = testEngine
            self.preset = preset
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let arView = arView else { return }
            
            let location = gesture.location(in: arView)
            let position = screenToWorld(location, in: arView)
            
            Task { @MainActor in
                switch gesture.state {
                case .began:
                    let color = UIColor.systemBlue // Default test color
                    testEngine.startDrawing(at: position, color: color, size: preset.geometry.baseSize)
                    
                case .changed:
                    testEngine.addPoint(position)
                    updateStrokes()
                    
                case .ended, .cancelled:
                    testEngine.endDrawing()
                    updateStrokes()
                    
                default:
                    break
                }
            }
        }
        
        func screenToWorld(_ point: CGPoint, in arView: ARView) -> SIMD3<Float> {
            // Convert screen point to 3D position on a plane
            let normalizedX = Float(point.x / arView.bounds.width) * 2 - 1
            let normalizedY = -(Float(point.y / arView.bounds.height) * 2 - 1)
            
            // Position on a plane at z = 0
            return SIMD3<Float>(normalizedX * 0.3, normalizedY * 0.3, 0)
        }
        
        @MainActor
        func updateStrokes() {
            guard let renderer = renderer, renderer.arView != nil else { return }
            
            // Render completed strokes
            for stroke in testEngine.strokes {
                renderer.renderStroke(stroke, preset: preset)
            }
            
            // Render current stroke
            if let current = testEngine.currentStroke {
                renderer.renderStroke(current, preset: preset, isCurrent: true)
            }
        }
    }
}

// MARK: - Test Stroke Renderer

@MainActor
class TestStrokeRenderer {
    weak var arView: ARView?
    private var strokeAnchors: [UUID: AnchorEntity] = [:]
    private var currentAnchor: AnchorEntity?
    
    init(arView: ARView) {
        self.arView = arView
    }
    
    func renderStroke(_ stroke: TestDrawingEngine.TestStroke, preset: BrushDefinition, isCurrent: Bool = false) {
        guard let arView = arView, stroke.points.count >= 2 else { return }
        
        // Get or create anchor
        let anchor: AnchorEntity
        if isCurrent {
            if currentAnchor == nil {
                currentAnchor = AnchorEntity(world: .zero)
                arView.scene.addAnchor(currentAnchor!)
            }
            anchor = currentAnchor!
            anchor.children.removeAll()
        } else {
            if let existing = strokeAnchors[stroke.id] {
                anchor = existing
                anchor.children.removeAll()
            } else {
                anchor = AnchorEntity(world: .zero)
                arView.scene.addAnchor(anchor)
                strokeAnchors[stroke.id] = anchor
            }
        }
        
        // Render points based on preset
        let color = stroke.color
        let material = SimpleMaterial(color: color, isMetallic: false)
        
        for i in 0..<stroke.points.count {
            let p = stroke.points[i]
            
            // Apply size variation
            var size = stroke.brushSize
            if preset.geometry.sizeVariation > 0 {
                let variation = preset.geometry.sizeVariation * size
                size += Float.random(in: -variation...variation)
            }
            
            // Create sphere at point
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: max(0.002, size)),
                materials: [material]
            )
            sphere.position = p
            anchor.addChild(sphere)
            
            // Connect with cylinder
            if i > 0 {
                let prev = stroke.points[i - 1]
                let dist = simd_distance(prev, p)
                if dist > 0.001 {
                    let cyl = ModelEntity(
                        mesh: .generateCylinder(height: dist, radius: size * 0.8),
                        materials: [material]
                    )
                    cyl.position = (prev + p) / 2
                    let dir = simd_normalize(p - prev)
                    cyl.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir)
                    anchor.addChild(cyl)
                }
            }
        }
    }
    
    func clear() {
        for (_, anchor) in strokeAnchors {
            anchor.removeFromParent()
        }
        strokeAnchors.removeAll()
        currentAnchor?.removeFromParent()
        currentAnchor = nil
    }
}
