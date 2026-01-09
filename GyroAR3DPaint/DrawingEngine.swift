import SwiftUI
import simd
import Combine
import UIKit
import Darwin

extension Notification.Name {
    static let strokesCleared = Notification.Name("strokesCleared")
    static let strokeUndone = Notification.Name("strokeUndone")
}

// 31 sivellintä - kaikki 3D ja moniväriset
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
    // Uudet epäsäännölliset muodot
    case torus = "Torus"          // Rinkeli/donitsi-muoto
    case morph = "Morph"          // Muuttuva monikulmio (3-8 kulmaa)
    case blob = "Blob"            // Orgaaninen möykky (metaball)
    case coil = "Coil"            // Kierteinen jousi
    case membrane = "Membrane"    // Ohut kalvo/kupla
    case lattice = "Lattice"      // 3D ristikkorakenne
    case tendril = "Tendril"      // Haarautuva lonkero
    case voxel = "Voxel"          // Pikselimäinen 3D-kuutio
    
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
        // Uudet epäsäännölliset
        case .torus: return "circle.dashed"
        case .morph: return "seal.fill"
        case .blob: return "drop.fill"
        case .coil: return "hurricane"
        case .membrane: return "oval.fill"
        case .lattice: return "cube.transparent"
        case .tendril: return "arrow.triangle.branch"
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
    @Published var cpuUsage: Double = 0
    @Published var selectedColorIndex: Int = 0
    @Published var useImageColors = false
    @Published var imageColors: [Color] = []
    @Published var imageSelection = ImageSelectionState()
    @Published var tremoloActive: Bool = true // For tremolo modulation
    @Published var controllerColor: Color? = nil // Color from controller wheel
    @Published var brushSizeMultiplier: Float = 1.0 // LT: size boost
    @Published var sparkleAmount: Float = 0 // RT: sparkle/scatter
    @Published var airPodsGradientValue: Float = 0 // AirPods pään kallistus -1...1
    
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
        currentStroke = Stroke(color: currentColor, brushType: selectedBrushType)
        isDrawing = true
    }
    
    func addPoint(_ position: SIMD3<Float>) {
        guard isDrawing, tremoloActive else { return } // Tremolo can skip points
        // Skip points that are too close to reduce CPU/GPU load when recording
                if let last = currentStroke?.points.last {
                    let minSpacing: Float = 0.002 // 2 mm
                    if simd_distance(last.position, position) < minSpacing {
                        return
                    }
                }
                
        
        // Apply sparkle scatter if RT pressed
        var finalPos = position
        if sparkleAmount > 0.1 {
            let scatter = sparkleAmount * brushSize * 3
            finalPos.x += Float.random(in: -scatter...scatter)
            finalPos.y += Float.random(in: -scatter...scatter)
            finalPos.z += Float.random(in: -scatter...scatter)
        }
        
        // Lock current color to this point - always set it
        let pointColor = currentColor
        let point = StrokePoint(
            position: finalPos,
            brushSize: brushSize * brushSizeMultiplier, // LT affects size
            timestamp: Date().timeIntervalSince1970,
            opacity: opacity,
            color: pointColor,  // Always store current color
            gradientValue: airPodsGradientValue  // Store AirPods gradient value
        )
        
        currentStroke?.addPoint(point)
        if useImageColors && !imageColors.isEmpty { imageColorIndex += 1 }
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
        NotificationCenter.default.post(name: .strokeUndone, object: removed.id)
    }
    
    func clearAllStrokes() {
        strokes.removeAll()
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
        brushSize = 0.002 + value * 0.05
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
