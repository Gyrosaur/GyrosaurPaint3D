import SwiftUI
import simd
import Combine
import UIKit
import Darwin

extension Notification.Name {
    static let strokesCleared = Notification.Name("strokesCleared")
    static let strokeUndone = Notification.Name("strokeUndone")
    static let strokeRedone = Notification.Name("strokeRedone")
}

// Sivellintyypit
enum BrushType: String, CaseIterable {
    // Perus
    case smooth = "Smooth"
    case ribbon = "Ribbon"
    // Orgaaniset
    case vine = "Vine"
    case tentacle = "Tentacle"
    // Geometriset
    case helix = "Helix"
    case chain = "Chain"
    case zigzag = "Zigzag"
    case spiral = "Spiral"
    // Partikkelit
    case confetti = "Confetti"
    case sparkle = "Sparkle"
    case stardust = "Stardust"
    case bubbles = "Bubbles"
    case fireflies = "Fireflies"
    // Tekstuurit
    case braid = "Braid"
    case scales = "Scales"
    // Erikoiset
    case waves = "Waves"
    case pulse = "Pulse"
    case aurora = "Aurora"
    case prism = "Prism"
    // Uudet
    case coil = "Coil"
    case membrane = "Membrane"
    case voxel = "Voxel"
    
    var icon: String {
        switch self {
        case .smooth: return "circle.fill"
        case .ribbon: return "wind"
        case .vine: return "leaf.fill"
        case .tentacle: return "tornado"
        case .helix: return "hurricane"
        case .chain: return "link"
        case .zigzag: return "bolt.horizontal.fill"
        case .spiral: return "circle.dotted"
        case .confetti: return "party.popper.fill"
        case .sparkle: return "sparkle"
        case .stardust: return "star.fill"
        case .bubbles: return "bubble.left.and.bubble.right.fill"
        case .fireflies: return "lightbulb.fill"
        case .braid: return "line.3.horizontal"
        case .scales: return "diamond.fill"
        case .waves: return "water.waves"
        case .pulse: return "waveform.path"
        case .aurora: return "rainbow"
        case .prism: return "triangle.fill"
        case .coil: return "hurricane"
        case .membrane: return "oval.fill"
        case .voxel: return "square.3.layers.3d"
        }
    }
}

struct StrokePoint {
    var position: SIMD3<Float>
    var brushSize: Float
    var timestamp: TimeInterval
    var opacity: Float = 1.0
    var color: Color? = nil  // Per-point color (nil = use stroke color)
    var gradientValue: Float = 0  // AirPods gradient: -1 = light->dark, 0 = uniform, 1 = dark->light
}

struct Stroke: Identifiable {
    let id = UUID()
    var color: Color  // Base color (fallback)
    var brushType: BrushType
    var points: [StrokePoint] = []
    var isSelected: Bool = false
    var brushPreset: BrushDefinition? = nil  // Studio preset (nil = use default rendering)
    
    mutating func addPoint(_ point: StrokePoint) {
        points.append(point)
    }
}

@MainActor
class DrawingEngine: ObservableObject {
    @Published var strokes: [Stroke] = []
    @Published var currentStroke: Stroke?
    @Published var isDrawing = false
    @Published var brushSize: Float = 0.01
    @Published var selectedBrushType: BrushType = .smooth
    @Published var hueShift: Float = 0
    @Published var opacity: Float = 1.0
    @Published var drawingDistanceOffset: Float = 0.0  // 0.0 = default (0.3m), 1.0 = +12m extra
    @Published var brushSizeMin: Float = 0.002
    @Published var brushSizeMax: Float = 0.05
    @Published var brushRideEnabled: Bool = false
    @Published var cpuUsage: Double = 0
    @Published var selectedColorIndex: Int = 0
    @Published var useImageColors = false
    @Published var imageColors: [Color] = []
    @Published var imageSelection = ImageSelectionState()
    @Published var tremoloActive: Bool = true // For tremolo modulation
    
    // Redo stack
    private var undoneStrokes: [Stroke] = []
    @Published var controllerColor: Color? = nil // Color from controller wheel
    @Published var brushSizeMultiplier: Float = 1.0 // LT: size boost
    @Published var sparkleAmount: Float = 0 // RT: sparkle/scatter
    @Published var airPodsGradientValue: Float = 0 // AirPods pään kallistus -1...1
    
    // MARK: - Brush Studio Integration
    @Published var activeBrushPreset: BrushDefinition = BrushDefinition.defaultSmooth
    @Published var useStudioPreset: Bool = false // Toggle between palette and studio
    
    // Computed parameters from active preset
    var presetJitter: Float { useStudioPreset ? activeBrushPreset.stroke.jitter : 0 }
    var presetSizeVariation: Float { useStudioPreset ? activeBrushPreset.geometry.sizeVariation : 0 }
    var presetSpacing: Float { useStudioPreset ? activeBrushPreset.stroke.spacing : 0.3 }
    var presetSmoothing: Float { useStudioPreset ? activeBrushPreset.stroke.smoothing : 0.5 }
    var presetGravity: SIMD3<Float> { useStudioPreset ? activeBrushPreset.physics.gravity : .zero }
    var presetTurbulence: Float { useStudioPreset ? activeBrushPreset.physics.turbulence : 0 }
    
    private var imageColorIndex: Int = 0
    private var cpuTimer: Timer?
    
    let availableColors: [Color] = [
        .white, .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink
    ]
    
    var currentColor: Color {
        // Controller color takes priority
        if let cc = controllerColor { return cc }
        if useImageColors && !imageColors.isEmpty {
            return imageColors[imageColorIndex % imageColors.count]
        }
        return availableColors[selectedColorIndex]
    }
    
    init() {
        cpuTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.cpuUsage = self?.getCPUUsage() ?? 0 }
        }
    }
    
    // MARK: - Brush Studio Methods
    
    func applyPreset(_ preset: BrushDefinition) {
        activeBrushPreset = preset
        useStudioPreset = true
        // Map base brush type if available
        if let baseType = BrushType(rawValue: preset.baseBrushType.capitalized) {
            selectedBrushType = baseType
        }
        // Apply base size from preset
        brushSize = preset.geometry.baseSize
    }
    
    func disableStudioPreset() {
        useStudioPreset = false
    }
    
    func toggleStudioPreset() {
        useStudioPreset.toggle()
    }
    
    // Set color from HSB (controller color wheel)
    func setColorFromHSB(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        controllerColor = Color(hue: hue, saturation: saturation, brightness: brightness)
        // Also update current stroke color if drawing
        if isDrawing, var stroke = currentStroke {
            stroke.color = controllerColor!
            currentStroke = stroke
        }
    }
    
    func clearControllerColor() {
        controllerColor = nil
    }
    
    // LB: Random color burst
    func randomizeColor() {
        let hue = CGFloat.random(in: 0...1)
        let sat = CGFloat.random(in: 0.7...1.0)
        controllerColor = Color(hue: hue, saturation: sat, brightness: 1.0)
    }
    
    // RB: Invert current color
    func invertColor() {
        let current = currentColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(current).getRed(&r, green: &g, blue: &b, alpha: &a)
        controllerColor = Color(red: 1-r, green: 1-g, blue: 1-b)
    }
    
    func startDrawing() {
        var stroke = Stroke(color: currentColor, brushType: selectedBrushType)
        // Attach studio preset if active
        if useStudioPreset {
            stroke.brushPreset = activeBrushPreset
        }
        currentStroke = stroke
        isDrawing = true
    }
    
    func addPoint(_ position: SIMD3<Float>) {
        guard isDrawing, tremoloActive else { return } // Tremolo can skip points
        
        // Calculate minimum spacing based on preset
        let minSpacing: Float = useStudioPreset ? (0.001 + presetSpacing * 0.005) : 0.002
        
        // Skip points that are too close to reduce CPU/GPU load when recording
        if let last = currentStroke?.points.last {
            if simd_distance(last.position, position) < minSpacing {
                return
            }
        }
        
        var finalPos = position
        
        // Apply preset jitter
        if presetJitter > 0.01 {
            let jitterAmount = presetJitter * brushSize * activeBrushPreset.stroke.jitterScale
            finalPos.x += Float.random(in: -jitterAmount...jitterAmount)
            finalPos.y += Float.random(in: -jitterAmount...jitterAmount)
            finalPos.z += Float.random(in: -jitterAmount...jitterAmount)
        }
        
        // Apply sparkle scatter if RT pressed (controller)
        if sparkleAmount > 0.1 {
            let scatter = sparkleAmount * brushSize * 3
            finalPos.x += Float.random(in: -scatter...scatter)
            finalPos.y += Float.random(in: -scatter...scatter)
            finalPos.z += Float.random(in: -scatter...scatter)
        }
        
        // Apply preset gravity (accumulates over stroke)
        if useStudioPreset && simd_length(presetGravity) > 0.0001 {
            let pointIndex = Float(currentStroke?.points.count ?? 0)
            finalPos += presetGravity * pointIndex
        }
        
        // Apply preset turbulence
        if presetTurbulence > 0.01 {
            let turbScale = activeBrushPreset.physics.turbulenceScale
            let turb = presetTurbulence * brushSize * turbScale
            finalPos.x += Float.random(in: -turb...turb)
            finalPos.y += Float.random(in: -turb...turb)
            finalPos.z += Float.random(in: -turb...turb)
        }
        
        // Haptic feedback based on brush size
        triggerHaptic(for: brushSize * brushSizeMultiplier)
        
        // Calculate final brush size with preset variation
        var finalBrushSize = brushSize * brushSizeMultiplier
        if presetSizeVariation > 0.01 {
            let variation = presetSizeVariation * finalBrushSize
            finalBrushSize += Float.random(in: -variation...variation)
            finalBrushSize = max(0.001, finalBrushSize) // Ensure positive
        }
        
        // Lock current color to this point - always set it
        let pointColor = currentColor
        let point = StrokePoint(
            position: finalPos,
            brushSize: finalBrushSize,
            timestamp: Date().timeIntervalSince1970,
            opacity: opacity,
            color: pointColor,  // Always store current color
            gradientValue: airPodsGradientValue  // Store AirPods gradient value
        )
        
        currentStroke?.addPoint(point)
        if useImageColors && !imageColors.isEmpty { imageColorIndex += 1 }
    }
    
    private var lastHapticTime: TimeInterval = 0
    
    private func triggerHaptic(for size: Float) {
        let now = Date().timeIntervalSince1970
        // Limit haptic rate to avoid overwhelming
        guard now - lastHapticTime > 0.05 else { return }
        lastHapticTime = now
        
        // Size ranges: small < 0.015, medium 0.015-0.03, large > 0.03
        let generator: UIImpactFeedbackGenerator
        if size < 0.015 {
            generator = UIImpactFeedbackGenerator(style: .light)
        } else if size < 0.03 {
            generator = UIImpactFeedbackGenerator(style: .medium)
        } else {
            generator = UIImpactFeedbackGenerator(style: .heavy)
        }
        generator.impactOccurred(intensity: min(1.0, CGFloat(size * 30)))
    }
    
    func stopDrawing() -> Stroke? {
        guard isDrawing, let stroke = currentStroke, stroke.points.count > 1 else {
            isDrawing = false; currentStroke = nil; return nil
        }
        strokes.append(stroke)
        let completed = stroke
        currentStroke = nil; isDrawing = false
        return completed
    }
    
    func undoLastStroke() {
        guard !strokes.isEmpty else { return }
        let removed = strokes.removeLast()
        undoneStrokes.append(removed)
        NotificationCenter.default.post(name: .strokeUndone, object: removed.id)
    }
    
    func redoLastStroke() {
        guard !undoneStrokes.isEmpty else { return }
        let restored = undoneStrokes.removeLast()
        strokes.append(restored)
        NotificationCenter.default.post(name: .strokeRedone, object: restored)
    }
    
    func clearAllStrokes() {
        strokes.removeAll()
        undoneStrokes.removeAll()
        NotificationCenter.default.post(name: .strokesCleared, object: nil)
    }
    
    func selectStroke(id: UUID) {
        for i in 0..<strokes.count {
            strokes[i].isSelected = (strokes[i].id == id)
        }
    }
    
    func deselectAll() {
        for i in 0..<strokes.count { strokes[i].isSelected = false }
    }
    
    func updateCurrentStrokeColor() {
        currentStroke?.color = currentColor
    }
    
    func updateCurrentStrokeBrushType() {
        currentStroke?.brushType = selectedBrushType
    }
    
    func setBrushSizeNormalized(_ value: Float) {
        brushSize = brushSizeMin + value * (brushSizeMax - brushSizeMin)
    }
    
    func loadImageColors() {
        imageColors = imageSelection.extractColorsInOrder(sampleCount: 256)
        imageColorIndex = 0
        if !imageColors.isEmpty { useImageColors = true }
    }
    
    private func getCPUUsage() -> Double {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = Double(cpuInfo.cpu_ticks.0)
        let system = Double(cpuInfo.cpu_ticks.1)
        let idle = Double(cpuInfo.cpu_ticks.2)
        let total = user + system + idle + Double(cpuInfo.cpu_ticks.3)
        return total > 0 ? ((user + system) / total) * 100 : 0
    }
}

class ImageSelectionState: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var selectionRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    
    func extractColorsInOrder(sampleCount: Int) -> [Color] {
        guard let image = selectedImage, let cgImage = image.cgImage else { return [] }
        let width = cgImage.width, height = cgImage.height
        let rectX = Int(selectionRect.origin.x * CGFloat(width))
        let rectY = Int(selectionRect.origin.y * CGFloat(height))
        let rectW = Int(selectionRect.width * CGFloat(width))
        let rectH = Int(selectionRect.height * CGFloat(height))
        guard rectW > 0, rectH > 0 else { return [] }
        guard let cropped = cgImage.cropping(to: CGRect(x: rectX, y: rectY, width: rectW, height: rectH)) else { return [] }
        let cw = cropped.width, ch = cropped.height
        var pixelData = [UInt8](repeating: 0, count: cw * ch * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixelData, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cw, height: ch))
        var colors: [Color] = []
        let step = max(1, (cw * ch) / sampleCount)
        for i in stride(from: 0, to: cw * ch, by: step) {
            let offset = i * 4
            if offset + 3 < pixelData.count {
                let r = Double(pixelData[offset]) / 255
                let g = Double(pixelData[offset + 1]) / 255
                let b = Double(pixelData[offset + 2]) / 255
                colors.append(Color(red: r, green: g, blue: b))
            }
        }
        return colors
    }
}
