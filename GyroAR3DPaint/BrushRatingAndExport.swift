import SwiftUI
import Foundation
import RealityKit
import SceneKit

// MARK: - Brush Rating Data

struct BrushRating: Codable, Identifiable {
    let id: UUID
    let brushType: String
    let stars: Int
    let notes: String
    let timestamp: Date
    
    init(brushType: String, stars: Int, notes: String) {
        self.id = UUID()
        self.brushType = brushType
        self.stars = stars
        self.notes = notes
        self.timestamp = Date()
    }
}

struct BrushRatingsData: Codable {
    var ratings: [BrushRating] = []
}

// MARK: - Brush Rating Manager

@MainActor
class BrushRatingManager: ObservableObject {
    @Published var ratingsData = BrushRatingsData()
    
    private let saveKey = "BrushRatings"
    
    init() {
        loadRatings()
    }
    
    func addRating(brushType: BrushType, stars: Int, notes: String) {
        let rating = BrushRating(brushType: brushType.rawValue, stars: stars, notes: notes)
        ratingsData.ratings.append(rating)
        saveRatings()
    }
    
    func getRatings(for brushType: BrushType) -> [BrushRating] {
        return ratingsData.ratings
            .filter { $0.brushType == brushType.rawValue }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    func getAverageStars(for brushType: BrushType) -> Double? {
        let ratings = getRatings(for: brushType)
        guard !ratings.isEmpty else { return nil }
        let total = ratings.reduce(0) { $0 + $1.stars }
        return Double(total) / Double(ratings.count)
    }
    
    func getTotalRatingCount(for brushType: BrushType) -> Int {
        return getRatings(for: brushType).count
    }
    
    private func saveRatings() {
        if let encoded = try? JSONEncoder().encode(ratingsData) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadRatings() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode(BrushRatingsData.self, from: data) {
            ratingsData = decoded
        }
    }
}

// MARK: - Brush Rating View

struct BrushRatingView: View {
    let brushType: BrushType
    @ObservedObject var ratingManager: BrushRatingManager
    @State private var currentStars: Int = 0
    @State private var currentNotes: String = ""
    @State private var showNotes: Bool = false
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: brushType.icon)
                    .font(.system(size: 24))
                Text(brushType.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            if let avg = ratingManager.getAverageStars(for: brushType) {
                HStack {
                    Text("Avg: \(String(format: "%.1f", avg))★")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                    Text("(\(ratingManager.getTotalRatingCount(for: brushType)) ratings)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            
            HStack(spacing: 8) {
                Text("Rate:")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                ForEach(1...5, id: \.self) { star in
                    Button(action: { currentStars = star }) {
                        Image(systemName: star <= currentStars ? "star.fill" : "star")
                            .font(.system(size: 20))
                            .foregroundColor(star <= currentStars ? .yellow : .gray)
                    }
                }
            }
            
            Button(action: { withAnimation { showNotes.toggle() } }) {
                HStack {
                    Image(systemName: "note.text")
                    Text(showNotes ? "Hide Notes" : "Add Notes")
                        .font(.system(size: 12))
                }
                .foregroundColor(.blue)
            }
            
            if showNotes {
                TextField("Notes, wishes, ideas...", text: $currentNotes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .lineLimit(3...6)
                    .font(.system(size: 12))
            }
            
            if currentStars > 0 {
                Button(action: submitRating) {
                    Text("Save Rating")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.yellow)
                        .cornerRadius(8)
                }
            }
            
            let previousRatings = ratingManager.getRatings(for: brushType).prefix(3)
            if !previousRatings.isEmpty {
                Divider().background(Color.white.opacity(0.2))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Previous Ratings")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                    
                    ForEach(Array(previousRatings)) { rating in
                        HStack {
                            Text(String(repeating: "★", count: rating.stars))
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            if !rating.notes.isEmpty {
                                Text(rating.notes.prefix(30) + (rating.notes.count > 30 ? "..." : ""))
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Spacer()
                            Text(rating.timestamp.formatted(.dateTime.month().day()))
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(white: 0.12, opacity: 0.98))
        .cornerRadius(16)
        .foregroundColor(.white)
    }
    
    private func submitRating() {
        ratingManager.addRating(brushType: brushType, stars: currentStars, notes: currentNotes)
        currentStars = 0
        currentNotes = ""
        showNotes = false
    }
}

// MARK: - Export Manager

class ExportManager {
    
    // Export as USDZ with proper tube mesh geometry (matches in-app rendering)
    static func exportAsUSDZ(strokes: [Stroke], quality: ExportQuality = .high, onProgress: @escaping (Float) -> Void, completion: @escaping (URL?) -> Void) {
        Task {
            let scene = SCNScene()
            let totalStrokes = strokes.count
            let segments = quality == .high ? 12 : (quality == .medium ? 8 : 6)
            
            for (strokeIndex, stroke) in strokes.enumerated() {
                guard stroke.points.count >= 2 else { continue }
                
                let strokeNode = SCNNode()
                strokeNode.name = "stroke_\(stroke.brushType.rawValue)_\(strokeIndex)"
                
                // Build mesh based on brush type - matching StrokeRenderer logic
                let meshNode = buildBrushMesh(for: stroke, segments: segments, quality: quality)
                strokeNode.addChildNode(meshNode)
                
                scene.rootNode.addChildNode(strokeNode)
                let progress = Float(strokeIndex + 1) / Float(totalStrokes) * 0.8
                await MainActor.run { onProgress(progress) }
            }
            
            // Add lights
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.intensity = 800
            scene.rootNode.addChildNode(ambientLight)
            
            let directionalLight = SCNNode()
            directionalLight.light = SCNLight()
            directionalLight.light?.type = .directional
            directionalLight.light?.intensity = 400
            directionalLight.position = SCNVector3(5, 10, 5)
            directionalLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(directionalLight)
            
            await MainActor.run { onProgress(0.85) }
            
            let filename = "GyroArt_\(Int(Date().timeIntervalSince1970)).usdz"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            
            // Run file write on background thread with progress simulation
            let writeSuccess = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    // Simulate progress during write
                    let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        Task { @MainActor in
                            // Progress between 0.85 and 0.98
                            let current = Float.random(in: 0.86...0.97)
                            onProgress(current)
                        }
                    }
                    RunLoop.current.add(timer, forMode: .common)
                    
                    let success = scene.write(to: tempURL, options: nil, delegate: nil, progressHandler: nil)
                    
                    timer.invalidate()
                    continuation.resume(returning: success)
                }
            }
            
            await MainActor.run {
                onProgress(1.0)
                completion(writeSuccess ? tempURL : nil)
            }
        }
    }
    
    // MARK: - Brush-specific mesh builders (matching StrokeRenderer)
    
    private static func buildBrushMesh(for stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        switch stroke.brushType {
        // Perus
        case .smooth: return makeTubeExport(stroke, segments: segments, quality: quality)
        case .ribbon: return makeRibbonExport(stroke, quality: quality)
        // Orgaaniset
        case .vine: return makeVineExport(stroke, segments: segments, quality: quality)
        case .tentacle: return makeTentacleExport(stroke, segments: segments, quality: quality)
        // Geometriset
        case .helix: return makeHelixExport(stroke, segments: segments, quality: quality)
        case .chain: return makeChainExport(stroke, quality: quality)
        case .zigzag: return makeZigzagExport(stroke, quality: quality)
        case .spiral: return makeSpiralExport(stroke, segments: segments, quality: quality)
        // Partikkelit
        case .confetti: return makeConfettiExport(stroke, quality: quality)
        case .sparkle: return makeSparkleExport(stroke, quality: quality)
        case .stardust: return makeStardustExport(stroke, quality: quality)
        case .bubbles: return makeBubblesExport(stroke, quality: quality)
        case .fireflies: return makeFirefliesExport(stroke, quality: quality)
        // Tekstuurit
        case .braid: return makeBraidExport(stroke, segments: segments, quality: quality)
        case .scales: return makeScalesExport(stroke, quality: quality)
        // Erikoiset
        case .waves: return makeWavesExport(stroke, segments: segments, quality: quality)
        case .pulse: return makePulseExport(stroke, quality: quality)
        case .aurora: return makeAuroraExport(stroke, quality: quality)
        case .prism: return makePrismExport(stroke, quality: quality)
        // Uudet
        case .coil: return makeTubeExport(stroke, segments: segments, quality: quality)
        case .membrane: return makeTubeExport(stroke, segments: segments, quality: quality)
        case .voxel: return makeTubeExport(stroke, segments: segments, quality: quality)
        }
    }
    
    // Tube/Smooth brush
    private static func makeTubeExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        guard sampled.count >= 2 else { return parent }
        
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let tubeNode = createContinuousTube(points: sampled, color: color, segments: segments)
        parent.addChildNode(tubeNode)
        return parent
    }
    
    // Ribbon brush - flat strips
    private static func makeRibbonExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        for i in 1..<sampled.count {
            let p = sampled[i]
            let prev = sampled[i-1]
            let gradPos = Float(i) / Float(sampled.count - 1)
            let color = getPointColor(p, stroke: stroke, gradientPosition: gradPos)
            
            let dist = simd_distance(prev.position, p.position)
            if dist > 0.001 {
                let box = SCNBox(width: CGFloat(p.brushSize * 4), height: CGFloat(p.brushSize * 0.2), length: CGFloat(dist), chamferRadius: 0)
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.lightingModel = .physicallyBased
                box.materials = [mat]
                
                let node = SCNNode(geometry: box)
                node.position = SCNVector3((prev.position.x + p.position.x) / 2,
                                           (prev.position.y + p.position.y) / 2,
                                           (prev.position.z + p.position.z) / 2)
                let dir = simd_normalize(p.position - prev.position)
                node.look(at: SCNVector3(p.position.x, p.position.y, p.position.z))
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Bubbles brush - large translucent spheres
    private static func makeBubblesExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = max(3, quality.pointSkip)
        
        for i in stride(from: 0, to: pts.count, by: skip) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let color = getPointColor(p, stroke: stroke, gradientPosition: gradPos)
            
            // Random size variation like StrokeRenderer
            let radius = p.brushSize * Float.random(in: 1.0...2.0)
            let sphere = SCNSphere(radius: CGFloat(radius))
            sphere.segmentCount = 16
            
            let mat = SCNMaterial()
            mat.diffuse.contents = color.withAlphaComponent(0.6)
            mat.lightingModel = .physicallyBased
            mat.metalness.contents = 0.8
            mat.roughness.contents = 0.1
            mat.transparency = 0.6
            sphere.materials = [mat]
            
            let node = SCNNode(geometry: sphere)
            // Random offset like StrokeRenderer
            let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize
            node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
            parent.addChildNode(node)
        }
        return parent
    }
    
    // Splatter brush - random droplets
    private static func makeSplatterExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        
        for p in pts {
            let gradPos = Float(pts.firstIndex(where: { $0.position == p.position }) ?? 0) / Float(max(1, pts.count - 1))
            
            for _ in 0..<3 {
                let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize * 2
                let hueShift = Float.random(in: -0.15...0.15)
                let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: hueShift)
                
                let radius = p.brushSize * Float.random(in: 0.3...1.0)
                let sphere = SCNSphere(radius: CGFloat(radius))
                sphere.segmentCount = 12
                
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.lightingModel = .physicallyBased
                sphere.materials = [mat]
                
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Confetti brush - flat colored squares
    private static func makeConfettiExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        
        for (i, p) in pts.enumerated() {
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let hueShift = Float.random(in: -0.5...0.5)
            let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: hueShift)
            
            let box = SCNBox(width: CGFloat(p.brushSize * 2), height: CGFloat(p.brushSize * 0.2), length: CGFloat(p.brushSize), chamferRadius: 0)
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.lightingModel = .physicallyBased
            box.materials = [mat]
            
            let node = SCNNode(geometry: box)
            let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize
            node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
            node.eulerAngles = SCNVector3(Float.random(in: 0...Float.pi*2), Float.random(in: 0...Float.pi*2), Float.random(in: 0...Float.pi*2))
            parent.addChildNode(node)
        }
        return parent
    }
    
    // Sparkle brush - 6-point stars
    private static func makeSparkleExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = max(2, quality.pointSkip)
        
        for i in stride(from: 0, to: pts.count, by: skip) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let color = getPointColor(p, stroke: stroke, gradientPosition: gradPos)
            
            for axis in [SCNVector3(1,0,0), SCNVector3(0,1,0), SCNVector3(0,0,1)] {
                let spike = SCNCylinder(radius: CGFloat(p.brushSize * 0.15), height: CGFloat(p.brushSize * 3))
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.lightingModel = .physicallyBased
                mat.metalness.contents = 1.0
                spike.materials = [mat]
                
                let node = SCNNode(geometry: spike)
                node.position = SCNVector3(p.position.x, p.position.y, p.position.z)
                // Set rotation based on axis
                if axis.x == 1 {
                    node.eulerAngles = SCNVector3(0, 0, Float.pi/2)
                } else if axis.z == 1 {
                    node.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
                }
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Stardust brush - small metallic spheres
    private static func makeStardustExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        
        for (i, p) in pts.enumerated() {
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            
            for _ in 0..<2 {
                let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize * 1.5
                let size = p.brushSize * Float.random(in: 0.2...0.6)
                let hueShift = Float.random(in: -0.3...0.3)
                let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: hueShift)
                
                let sphere = SCNSphere(radius: CGFloat(size))
                sphere.segmentCount = 10
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.lightingModel = .physicallyBased
                mat.metalness.contents = 1.0
                sphere.materials = [mat]
                
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Chain brush - linked boxes
    private static func makeChainExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        
        for i in stride(from: 0, to: pts.count, by: 3) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let hueShift = Float(i % 2) * 0.1
            let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: hueShift)
            
            let box = SCNBox(width: CGFloat(p.brushSize * 2), height: CGFloat(p.brushSize), length: CGFloat(p.brushSize * 3), chamferRadius: CGFloat(p.brushSize * 0.3))
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.lightingModel = .physicallyBased
            mat.metalness.contents = 1.0
            box.materials = [mat]
            
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(p.position.x, p.position.y, p.position.z)
            if i > 0 {
                let dir = direction(at: i, pts: pts)
                node.look(at: SCNVector3(p.position.x + dir.x, p.position.y + dir.y, p.position.z + dir.z))
            }
            if i % 6 == 0 {
                node.eulerAngles.z += Float.pi / 2
            }
            parent.addChildNode(node)
        }
        return parent
    }
    
    // DNA brush - double helix
    private static func makeDNAExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        
        for (i, p) in pts.enumerated() {
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let dir = direction(at: i, pts: pts)
            let basis = makeBasis(dir)
            let angle = Float(i) * 0.4
            
            let offset1 = (basis.0 * cos(angle) + basis.1 * sin(angle)) * p.brushSize * 2
            let offset2 = (basis.0 * cos(angle + .pi) + basis.1 * sin(angle + .pi)) * p.brushSize * 2
            
            let col1 = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: 0.1)
            let col2 = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: -0.1)
            
            let s1 = SCNSphere(radius: CGFloat(p.brushSize * 0.6))
            let s2 = SCNSphere(radius: CGFloat(p.brushSize * 0.6))
            s1.segmentCount = 10
            s2.segmentCount = 10
            
            let mat1 = SCNMaterial()
            mat1.diffuse.contents = col1
            mat1.lightingModel = .physicallyBased
            s1.materials = [mat1]
            
            let mat2 = SCNMaterial()
            mat2.diffuse.contents = col2
            mat2.lightingModel = .physicallyBased
            s2.materials = [mat2]
            
            let n1 = SCNNode(geometry: s1)
            let n2 = SCNNode(geometry: s2)
            n1.position = SCNVector3(p.position.x + offset1.x, p.position.y + offset1.y, p.position.z + offset1.z)
            n2.position = SCNVector3(p.position.x + offset2.x, p.position.y + offset2.y, p.position.z + offset2.z)
            parent.addChildNode(n1)
            parent.addChildNode(n2)
            
            // Connecting bar every 4 points
            if i % 4 == 0 {
                let bar = SCNCylinder(radius: CGFloat(p.brushSize * 0.15), height: CGFloat(p.brushSize * 4))
                let barMat = SCNMaterial()
                barMat.diffuse.contents = UIColor.white
                barMat.lightingModel = .physicallyBased
                bar.materials = [barMat]
                
                let barNode = SCNNode(geometry: bar)
                barNode.position = SCNVector3(p.position.x, p.position.y, p.position.z)
                let barDir = simd_normalize(offset1 - offset2)
                barNode.look(at: SCNVector3(p.position.x + barDir.x, p.position.y + barDir.y, p.position.z + barDir.z))
                barNode.eulerAngles.x += Float.pi / 2
                parent.addChildNode(barNode)
            }
        }
        return parent
    }
    
    // Helix brush
    private static func makeHelixExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        var helixPoints: [StrokePoint] = []
        for (i, p) in sampled.enumerated() {
            let dir = direction(at: i, pts: sampled)
            let basis = makeBasis(dir)
            let helixAngle = Float(i) * 0.5
            let helixOffset = (basis.0 * cos(helixAngle) + basis.1 * sin(helixAngle)) * p.brushSize * 2
            var newPoint = p
            newPoint.position = p.position + helixOffset
            newPoint.brushSize = p.brushSize * 0.5
            helixPoints.append(newPoint)
        }
        
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let tubeNode = createContinuousTube(points: helixPoints, color: color, segments: segments)
        parent.addChildNode(tubeNode)
        return parent
    }
    
    // Vine brush - tube with leaves
    private static func makeVineExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        // Main stem
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let stemNode = createContinuousTube(points: sampled, color: color, segments: segments)
        parent.addChildNode(stemNode)
        
        // Leaves
        for i in stride(from: 5, to: pts.count, by: 8) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let dir = direction(at: i, pts: pts)
            let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
            let leafSize = p.brushSize * 3
            let hueShift = Float.random(in: -0.15...0.15)
            let leafColor = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: hueShift)
            
            let leaf = SCNSphere(radius: CGFloat(leafSize))
            leaf.segmentCount = 12
            let mat = SCNMaterial()
            mat.diffuse.contents = leafColor
            mat.lightingModel = .physicallyBased
            leaf.materials = [mat]
            
            let leafNode = SCNNode(geometry: leaf)
            leafNode.scale = SCNVector3(1, 0.3, 2)
            let offset = side * leafSize * Float(i % 2 == 0 ? 1 : -1)
            leafNode.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
            parent.addChildNode(leafNode)
        }
        return parent
    }
    
    // Coral brush - tube with branches
    private static func makeCoralExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        // Main stem
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let stemNode = createContinuousTube(points: sampled, color: color, segments: 6)
        parent.addChildNode(stemNode)
        
        // Branches
        for i in stride(from: 3, to: pts.count, by: 5) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            
            for _ in 0..<3 {
                let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize * 2
                let hueShift = Float.random(in: -0.15...0.15)
                let branchColor = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: hueShift)
                
                let branch = SCNSphere(radius: CGFloat(p.brushSize * 0.8))
                branch.segmentCount = 10
                let mat = SCNMaterial()
                mat.diffuse.contents = branchColor
                mat.lightingModel = .physicallyBased
                branch.materials = [mat]
                
                let node = SCNNode(geometry: branch)
                node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Tentacle brush - tapered wobbling tube
    private static func makeTentacleExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        guard sampled.count >= 2 else { return parent }
        
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        let seg = 8
        
        for i in 0..<sampled.count {
            let p = sampled[i]
            let dir = direction(at: i, pts: sampled)
            let basis = makeBasis(dir)
            let taper = 1.0 - Float(i) / Float(sampled.count) * 0.7
            
            for j in 0..<seg {
                let angle = Float(j) / Float(seg) * .pi * 2
                let wobble = sin(Float(i) * 0.5 + angle * 2) * 0.3
                let normal = basis.0 * cos(angle) + basis.1 * sin(angle)
                let pos = p.position + normal * p.brushSize * taper * (1 + wobble)
                vertices.append(SCNVector3(pos.x, pos.y, pos.z))
                normals.append(SCNVector3(normal.x, normal.y, normal.z))
            }
            
            if i > 0 {
                for j in 0..<Int32(seg) {
                    let n = (j + 1) % Int32(seg)
                    let b = Int32(i - 1) * Int32(seg)
                    let t = Int32(i) * Int32(seg)
                    indices += [b + j, t + j, b + n, b + n, t + j, t + n]
                }
            }
        }
        
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .physicallyBased
        geometry.materials = [mat]
        
        parent.addChildNode(SCNNode(geometry: geometry))
        return parent
    }
    
    // Root brush - tube with downward roots
    private static func makeRootExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let stemNode = createContinuousTube(points: sampled, color: color, segments: 6)
        parent.addChildNode(stemNode)
        
        for i in stride(from: 4, to: pts.count, by: 6) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let rootLen = p.brushSize * 4
            let rootColor = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: Float.random(in: -0.1...0.1))
            
            let root = SCNCylinder(radius: CGFloat(p.brushSize * 0.3), height: CGFloat(rootLen))
            let mat = SCNMaterial()
            mat.diffuse.contents = rootColor
            mat.lightingModel = .physicallyBased
            root.materials = [mat]
            
            let node = SCNNode(geometry: root)
            node.position = SCNVector3(p.position.x, p.position.y - rootLen/2, p.position.z)
            parent.addChildNode(node)
        }
        return parent
    }
    
    // Branch brush - tube with side branches
    private static func makeBranchExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let stemNode = createContinuousTube(points: sampled, color: color, segments: 6)
        parent.addChildNode(stemNode)
        
        for i in stride(from: 6, to: pts.count, by: 10) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let dir = direction(at: i, pts: pts)
            let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
            let branchLen = p.brushSize * 5
            let branchColor = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: Float.random(in: -0.15...0.15))
            
            let branch = SCNCylinder(radius: CGFloat(p.brushSize * 0.4), height: CGFloat(branchLen))
            let mat = SCNMaterial()
            mat.diffuse.contents = branchColor
            mat.lightingModel = .physicallyBased
            branch.materials = [mat]
            
            let node = SCNNode(geometry: branch)
            let sideDir = side * Float(i % 2 == 0 ? 1 : -1)
            node.position = SCNVector3(p.position.x + sideDir.x * branchLen/2, p.position.y + sideDir.y * branchLen/2, p.position.z + sideDir.z * branchLen/2)
            node.look(at: SCNVector3(p.position.x + sideDir.x, p.position.y + sideDir.y, p.position.z + sideDir.z))
            node.eulerAngles.x += Float.pi / 2
            parent.addChildNode(node)
        }
        return parent
    }
    
    // Zigzag brush
    private static func makeZigzagExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        
        for i in 0..<pts.count - 1 {
            let p = pts[i]
            let p2 = pts[i + 1]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let dir = direction(at: i, pts: pts)
            let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
            let offset = side * p.brushSize * 2 * Float(i % 2 == 0 ? 1 : -1)
            let start = p.position + offset
            let end = p2.position - offset
            let dist = simd_distance(start, end)
            
            let color = getPointColor(p, stroke: stroke, gradientPosition: gradPos)
            let seg = SCNCylinder(radius: CGFloat(p.brushSize * 0.5), height: CGFloat(dist))
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.lightingModel = .physicallyBased
            seg.materials = [mat]
            
            let node = SCNNode(geometry: seg)
            node.position = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
            let segDir = simd_normalize(end - start)
            node.look(at: SCNVector3(end.x, end.y, end.z))
            node.eulerAngles.x += Float.pi / 2
            parent.addChildNode(node)
        }
        return parent
    }
    
    // Spiral brush
    private static func makeSpiralExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        var spiralPoints: [StrokePoint] = []
        for (i, p) in sampled.enumerated() {
            let dir = direction(at: i, pts: sampled)
            let basis = makeBasis(dir)
            let spiralR = p.brushSize * (1 + Float(i) * 0.1)
            let spiralAngle = Float(i) * 0.3
            let center = p.position + (basis.0 * cos(spiralAngle) + basis.1 * sin(spiralAngle)) * spiralR
            var newPoint = p
            newPoint.position = center
            newPoint.brushSize = p.brushSize * 0.4
            spiralPoints.append(newPoint)
        }
        
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let tubeNode = createContinuousTube(points: spiralPoints, color: color, segments: segments)
        parent.addChildNode(tubeNode)
        return parent
    }
    
    // Fireflies brush
    private static func makeFirefliesExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = max(4, quality.pointSkip)
        
        for i in stride(from: 0, to: pts.count, by: skip) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let hueShift = Float.random(in: -0.1...0.1)
            let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: hueShift)
            
            let glow = SCNSphere(radius: CGFloat(p.brushSize * 0.5))
            glow.segmentCount = 10
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.emission.contents = color
            mat.lightingModel = .physicallyBased
            mat.metalness.contents = 1.0
            glow.materials = [mat]
            
            let node = SCNNode(geometry: glow)
            let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize * 2
            node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
            parent.addChildNode(node)
        }
        return parent
    }
    
    // Rope brush - twisted strands
    private static func makeRopeExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        
        for strand in 0..<3 {
            for i in stride(from: 0, to: pts.count, by: skip) {
                let p = pts[i]
                let gradPos = Float(i) / Float(max(1, pts.count - 1))
                let dir = direction(at: i, pts: pts)
                let basis = makeBasis(dir)
                let angle = Float(i) * 0.5 + Float(strand) * .pi * 2 / 3
                let offset = (basis.0 * cos(angle) + basis.1 * sin(angle)) * p.brushSize * 0.7
                let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: Float(strand) * 0.05)
                
                let seg = SCNSphere(radius: CGFloat(p.brushSize * 0.4))
                seg.segmentCount = 8
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.lightingModel = .physicallyBased
                seg.materials = [mat]
                
                let node = SCNNode(geometry: seg)
                node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Braid brush
    private static func makeBraidExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        
        for strand in 0..<3 {
            for i in stride(from: 0, to: pts.count, by: skip) {
                let p = pts[i]
                let gradPos = Float(i) / Float(max(1, pts.count - 1))
                let dir = direction(at: i, pts: pts)
                let basis = makeBasis(dir)
                let phase = Float(strand) * .pi * 2 / 3
                let xOff = cos(Float(i) * 0.3 + phase) * p.brushSize
                let yOff = sin(Float(i) * 0.6 + phase) * p.brushSize * 0.5
                let offset = basis.0 * xOff + basis.1 * yOff
                let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: Float(strand) * 0.1 - 0.1)
                
                let seg = SCNSphere(radius: CGFloat(p.brushSize * 0.5))
                seg.segmentCount = 8
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.lightingModel = .physicallyBased
                seg.materials = [mat]
                
                let node = SCNNode(geometry: seg)
                node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Knit brush
    private static func makeKnitExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        
        for i in stride(from: 0, to: pts.count, by: skip) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let dir = direction(at: i, pts: pts)
            let basis = makeBasis(dir)
            let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: Float(i % 2) * 0.1)
            
            let loopAngle = Float(i) * 0.8
            for j in 0..<6 {
                let a = Float(j) / 6 * .pi * 2 + loopAngle
                let offset = (basis.0 * cos(a) + basis.1 * sin(a)) * p.brushSize
                
                let knot = SCNSphere(radius: CGFloat(p.brushSize * 0.25))
                knot.segmentCount = 8
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.lightingModel = .physicallyBased
                knot.materials = [mat]
                
                let node = SCNNode(geometry: knot)
                node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Scales brush
    private static func makeScalesExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        
        for i in stride(from: 0, to: pts.count, by: skip) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let dir = direction(at: i, pts: pts)
            let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: Float(i % 3) * 0.05)
            
            let scale = SCNBox(width: CGFloat(p.brushSize * 2), height: CGFloat(p.brushSize * 0.3), length: CGFloat(p.brushSize * 1.5), chamferRadius: CGFloat(p.brushSize * 0.2))
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.lightingModel = .physicallyBased
            mat.metalness.contents = 1.0
            scale.materials = [mat]
            
            let node = SCNNode(geometry: scale)
            node.position = SCNVector3(p.position.x, p.position.y, p.position.z)
            node.look(at: SCNVector3(p.position.x + dir.x, p.position.y + dir.y, p.position.z + dir.z))
            node.eulerAngles.x += Float(i % 2) * 0.3 - 0.15
            parent.addChildNode(node)
        }
        return parent
    }
    
    // Feather brush
    private static func makeFeatherExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let stemNode = createContinuousTube(points: sampled, color: color, segments: 4)
        parent.addChildNode(stemNode)
        
        for i in stride(from: 2, to: pts.count, by: 3) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let dir = direction(at: i, pts: pts)
            let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
            
            for s: Float in [-1, 1] {
                let barbColor = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: Float.random(in: -0.05...0.05))
                let barb = SCNBox(width: CGFloat(p.brushSize * 3), height: CGFloat(p.brushSize * 0.1), length: CGFloat(p.brushSize * 0.3), chamferRadius: 0)
                let mat = SCNMaterial()
                mat.diffuse.contents = barbColor
                mat.lightingModel = .physicallyBased
                barb.materials = [mat]
                
                let node = SCNNode(geometry: barb)
                node.position = SCNVector3(p.position.x + side.x * p.brushSize * 1.5 * s, p.position.y + side.y * p.brushSize * 1.5 * s, p.position.z + side.z * p.brushSize * 1.5 * s)
                node.eulerAngles.z = s * 0.3
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Waves brush
    private static func makeWavesExport(_ stroke: Stroke, segments: Int, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        var wavePoints: [StrokePoint] = []
        for (i, p) in sampled.enumerated() {
            let dir = direction(at: i, pts: sampled)
            let basis = makeBasis(dir)
            let wave = sin(Float(i) * 0.5) * p.brushSize
            var newPoint = p
            newPoint.position = p.position + basis.1 * wave
            newPoint.brushSize = p.brushSize * 0.6
            wavePoints.append(newPoint)
        }
        
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let tubeNode = createContinuousTube(points: wavePoints, color: color, segments: segments)
        parent.addChildNode(tubeNode)
        return parent
    }
    
    // Pulse brush
    private static func makePulseExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        
        for i in stride(from: 0, to: pts.count, by: skip) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let pulseSize = p.brushSize * (1 + sin(Float(i) * 0.5) * 0.5)
            let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: sin(Float(i) * 0.3) * 0.1)
            
            let sphere = SCNSphere(radius: CGFloat(pulseSize))
            sphere.segmentCount = 12
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.lightingModel = .physicallyBased
            sphere.materials = [mat]
            
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(p.position.x, p.position.y, p.position.z)
            parent.addChildNode(node)
        }
        return parent
    }
    
    // Aurora brush
    private static func makeAuroraExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        
        for layer in 0..<3 {
            for i in stride(from: 0, to: pts.count, by: skip) {
                let p = pts[i]
                let gradPos = Float(i) / Float(max(1, pts.count - 1))
                let dir = direction(at: i, pts: pts)
                let basis = makeBasis(dir)
                let yOff = Float(layer) * p.brushSize * 0.8
                let wave = sin(Float(i) * 0.3 + Float(layer)) * p.brushSize
                let hue = Float(layer) * 0.15 + Float(i) * 0.01
                let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: hue)
                
                let ribbon = SCNBox(width: CGFloat(p.brushSize * 2), height: CGFloat(p.brushSize * 0.1), length: CGFloat(p.brushSize * 0.5), chamferRadius: 0)
                let mat = SCNMaterial()
                mat.diffuse.contents = color.withAlphaComponent(0.5)
                mat.lightingModel = .physicallyBased
                mat.transparency = 0.5
                ribbon.materials = [mat]
                
                let node = SCNNode(geometry: ribbon)
                let offset = basis.1 * (yOff + wave)
                node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Prism brush
    private static func makePrismExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = max(2, quality.pointSkip)
        
        for i in stride(from: 0, to: pts.count, by: skip) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let dir = direction(at: i, pts: pts)
            let color = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: Float(i % 6) * 0.1)
            
            let prism = SCNBox(width: CGFloat(p.brushSize), height: CGFloat(p.brushSize * 2), length: CGFloat(p.brushSize), chamferRadius: 0)
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.lightingModel = .physicallyBased
            mat.metalness.contents = 1.0
            prism.materials = [mat]
            
            let node = SCNNode(geometry: prism)
            node.position = SCNVector3(p.position.x, p.position.y, p.position.z)
            node.look(at: SCNVector3(p.position.x + dir.x, p.position.y + dir.y, p.position.z + dir.z))
            node.eulerAngles.z += Float(i) * 0.2
            parent.addChildNode(node)
        }
        return parent
    }
    
    // Galaxy brush
    private static func makeGalaxyExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = quality.pointSkip
        let sampled = stride(from: 0, to: pts.count, by: skip).map { pts[$0] }
        
        // Core tube
        let color = getPointColor(sampled[0], stroke: stroke, gradientPosition: 0)
        let coreNode = createContinuousTube(points: sampled, color: color, segments: 6)
        parent.addChildNode(coreNode)
        
        // Stars around
        for (i, p) in pts.enumerated() {
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let dir = direction(at: i, pts: pts)
            let basis = makeBasis(dir)
            
            for _ in 0..<2 {
                let angle = Float.random(in: 0...(.pi * 2))
                let dist = Float.random(in: 1...3) * p.brushSize
                let offset = (basis.0 * cos(angle) + basis.1 * sin(angle)) * dist
                let starColor = getPointColorWithHueShift(p, stroke: stroke, gradientPosition: gradPos, hueShift: Float.random(in: -0.3...0.3))
                
                let star = SCNSphere(radius: CGFloat(p.brushSize * Float.random(in: 0.1...0.3)))
                star.segmentCount = 8
                let mat = SCNMaterial()
                mat.diffuse.contents = starColor
                mat.emission.contents = starColor
                mat.lightingModel = .physicallyBased
                mat.metalness.contents = 1.0
                star.materials = [mat]
                
                let node = SCNNode(geometry: star)
                node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
                parent.addChildNode(node)
            }
        }
        return parent
    }
    
    // Fog brush - many tiny translucent particles
    private static func makeFogExport(_ stroke: Stroke, quality: ExportQuality) -> SCNNode {
        let parent = SCNNode()
        let pts = stroke.points
        let skip = max(2, quality.pointSkip)
        
        for i in stride(from: 0, to: pts.count, by: skip) {
            let p = pts[i]
            let gradPos = Float(i) / Float(max(1, pts.count - 1))
            let color = getPointColor(p, stroke: stroke, gradientPosition: gradPos)
            let cloudRadius = p.brushSize * 3
            
            // Many tiny particles
            let particleCount = quality == .high ? 8 : (quality == .medium ? 5 : 3)
            for _ in 0..<particleCount {
                let theta = Float.random(in: 0...Float.pi * 2)
                let phi = Float.random(in: 0...Float.pi)
                let r = Float.random(in: 0.3...1.0) * cloudRadius
                
                let offset = SIMD3<Float>(
                    r * sin(phi) * cos(theta),
                    r * sin(phi) * sin(theta),
                    r * cos(phi)
                )
                
                let particleSize = Float.random(in: 0.002...0.008)
                
                let sphere = SCNSphere(radius: CGFloat(particleSize))
                sphere.segmentCount = 6
                let mat = SCNMaterial()
                mat.diffuse.contents = color.withAlphaComponent(CGFloat(Float.random(in: 0.05...0.15)))
                mat.lightingModel = .physicallyBased
                mat.transparency = CGFloat(Float.random(in: 0.05...0.15))
                sphere.materials = [mat]
                
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(p.position.x + offset.x, p.position.y + offset.y, p.position.z + offset.z)
                parent.addChildNode(node)
            }
            
            // Larger cloud puffs
            if i % 2 == 0 {
                let puffSize = cloudRadius * Float.random(in: 0.3...0.6)
                let puff = SCNSphere(radius: CGFloat(puffSize))
                puff.segmentCount = 8
                let puffMat = SCNMaterial()
                puffMat.diffuse.contents = color.withAlphaComponent(0.03)
                puffMat.lightingModel = .physicallyBased
                puffMat.transparency = 0.03
                puff.materials = [puffMat]
                
                let puffOffset = SIMD3<Float>(
                    Float.random(in: -1...1),
                    Float.random(in: -1...1),
                    Float.random(in: -1...1)
                ) * cloudRadius * 0.5
                
                let puffNode = SCNNode(geometry: puff)
                puffNode.position = SCNVector3(p.position.x + puffOffset.x, p.position.y + puffOffset.y, p.position.z + puffOffset.z)
                parent.addChildNode(puffNode)
            }
        }
        return parent
    }

    // Helper with hue shift
    private static func getPointColorWithHueShift(_ point: StrokePoint, stroke: Stroke, gradientPosition: Float, hueShift: Float) -> UIColor {
        let baseColor = getPointColor(point, stroke: stroke, gradientPosition: gradientPosition)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        baseColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        h += CGFloat(hueShift)
        if h < 0 { h += 1 }
        if h > 1 { h -= 1 }
        return UIColor(hue: h, saturation: s, brightness: b, alpha: a)
    }

    // Create continuous tube for single-color strokes
    private static func createContinuousTube(points: [StrokePoint], color: UIColor, segments: Int) -> SCNNode {
        guard points.count >= 2 else { return SCNNode() }
        
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        
        for i in 0..<points.count {
            let p = points[i]
            let dir = direction(at: i, pts: points)
            let basis = makeBasis(dir)
            
            for j in 0...segments {
                let angle = Float(j) / Float(segments) * .pi * 2
                let normal = basis.0 * cos(angle) + basis.1 * sin(angle)
                let pos = p.position + normal * p.brushSize
                vertices.append(SCNVector3(pos.x, pos.y, pos.z))
                normals.append(SCNVector3(normal.x, normal.y, normal.z))
            }
            
            if i > 0 {
                let ringSize = Int32(segments + 1)
                let base = Int32(i - 1) * ringSize
                let top = Int32(i) * ringSize
                for j in 0..<Int32(segments) {
                    indices += [base + j, top + j, base + j + 1, base + j + 1, top + j, top + j + 1]
                }
            }
        }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0.1
        material.roughness.contents = 0.5
        geometry.materials = [material]
        
        let node = SCNNode(geometry: geometry)
        
        // Add end caps
        let capMaterial = SCNMaterial()
        capMaterial.diffuse.contents = color
        capMaterial.lightingModel = .physicallyBased
        
        if let first = points.first {
            let startCap = SCNSphere(radius: CGFloat(first.brushSize))
            startCap.segmentCount = segments
            startCap.materials = [capMaterial]
            let startNode = SCNNode(geometry: startCap)
            startNode.position = SCNVector3(first.position.x, first.position.y, first.position.z)
            node.addChildNode(startNode)
        }
        
        if let last = points.last {
            let endCap = SCNSphere(radius: CGFloat(last.brushSize))
            endCap.segmentCount = segments
            endCap.materials = [capMaterial]
            let endNode = SCNNode(geometry: endCap)
            endNode.position = SCNVector3(last.position.x, last.position.y, last.position.z)
            node.addChildNode(endNode)
        }
        
        return node
    }
    
    // Helper: get direction at point index
    private static func direction(at i: Int, pts: [StrokePoint]) -> SIMD3<Float> {
        if pts.count < 2 { return SIMD3<Float>(0, 0, 1) }
        if i == 0 { return simd_normalize(pts[1].position - pts[0].position) }
        if i >= pts.count - 1 { return simd_normalize(pts[pts.count - 1].position - pts[pts.count - 2].position) }
        return simd_normalize(pts[i + 1].position - pts[i - 1].position)
    }
    
    // Helper: create orthonormal basis
    private static func makeBasis(_ dir: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let up = abs(dir.y) < 0.99 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let right = simd_normalize(simd_cross(up, dir))
        let realUp = simd_cross(dir, right)
        return (right, realUp)
    }
    
    // Helper: get point color with gradient support
    private static func getPointColor(_ point: StrokePoint, stroke: Stroke, gradientPosition: Float) -> UIColor {
        var baseColor: UIColor
        if let pc = point.color {
            // Convert SwiftUI Color to UIColor properly
            baseColor = UIColor(pc).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        } else {
            // Convert stroke.color (SwiftUI Color) to UIColor
            baseColor = UIColor(stroke.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        }
        
        // Ensure we have valid RGB values
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        baseColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Apply point opacity
        baseColor = UIColor(red: r, green: g, blue: b, alpha: CGFloat(point.opacity))
        
        // Apply gradient
        if abs(point.gradientValue) > 0.05 {
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
            baseColor.getHue(&h, saturation: &s, brightness: &br, alpha: &al)
            
            let intensity = abs(CGFloat(point.gradientValue))
            let brightnessRange: CGFloat = 0.5 * intensity
            var brightnessAdjust: CGFloat
            if point.gradientValue < 0 {
                brightnessAdjust = brightnessRange * (1 - CGFloat(gradientPosition) * 2)
            } else {
                brightnessAdjust = brightnessRange * (CGFloat(gradientPosition) * 2 - 1)
            }
            br = max(0.1, min(1.0, br + brightnessAdjust))
            return UIColor(hue: h, saturation: s, brightness: br, alpha: al)
        }
        
        return baseColor
    }
    
    // Export as JSON (preserves all data)
    static func exportAsJSON(strokes: [Stroke], completion: @escaping (URL?) -> Void) {
        let exportData = StrokeExportData(strokes: strokes)
        
        guard let jsonData = try? JSONEncoder().encode(exportData) else {
            completion(nil)
            return
        }
        
        let filename = "GyroArt_\(Date().formatted(.dateTime.year().month().day().hour().minute())).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try jsonData.write(to: tempURL)
            completion(tempURL)
        } catch {
            completion(nil)
        }
    }
    
    // Export as OBJ (3D mesh)
    static func exportAsOBJ(strokes: [Stroke], completion: @escaping (URL?) -> Void) {
        var objContent = "# GyroAR3DPaint Export\n"
        var vertexOffset = 1
        
        for stroke in strokes {
            objContent += "# Stroke: \(stroke.brushType.rawValue)\n"
            objContent += "o stroke_\(stroke.id.uuidString.prefix(8))\n"
            
            for point in stroke.points {
                objContent += "v \(point.position.x) \(point.position.y) \(point.position.z)\n"
            }
            
            if stroke.points.count > 1 {
                objContent += "l"
                for i in 0..<stroke.points.count {
                    objContent += " \(vertexOffset + i)"
                }
                objContent += "\n"
            }
            
            vertexOffset += stroke.points.count
        }
        
        let filename = "GyroArt_\(Date().formatted(.dateTime.year().month().day().hour().minute())).obj"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try objContent.write(to: tempURL, atomically: true, encoding: .utf8)
            completion(tempURL)
        } catch {
            completion(nil)
        }
    }
}

// MARK: - Export Data Structures

struct StrokeExportData: Codable {
    var version: String = "1.0"
    let exportDate: Date
    let strokes: [StrokeExport]
    
    init(strokes: [Stroke]) {
        self.exportDate = Date()
        self.strokes = strokes.map { StrokeExport(from: $0) }
    }
}

struct StrokeExport: Codable {
    let id: String
    let brushType: String
    let points: [PointExport]
    let createdAt: Date
}

struct PointExport: Codable {
    let x: Float
    let y: Float
    let z: Float
    let brushSize: Float
    let colorHex: String
    let timestamp: TimeInterval
}

extension StrokeExport {
    init(from stroke: Stroke) {
        self.id = stroke.id.uuidString
        self.brushType = stroke.brushType.rawValue
        self.createdAt = Date(timeIntervalSince1970: stroke.points.first?.timestamp ?? Date().timeIntervalSince1970)
        self.points = stroke.points.map { point in
            PointExport(
                x: point.position.x,
                y: point.position.y,
                z: point.position.z,
                brushSize: point.brushSize,
                colorHex: UIColor(stroke.color).toHex(),
                timestamp: point.timestamp
            )
        }
    }
}

extension UIColor {
    func toHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Export View

enum ExportQuality: String, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    
    var pointSkip: Int {
        switch self {
        case .high: return 1
        case .medium: return 2
        case .low: return 4
        }
    }
}

struct ExportView: View {
    let strokes: [Stroke]
    @State private var isExporting = false
    @State private var exportProgress: Float = 0
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var selectedQuality: ExportQuality = .high
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Export Artwork")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("\(strokes.count) strokes")
                .font(.caption)
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Quality").font(.system(size: 11)).foregroundColor(.gray)
                HStack(spacing: 6) {
                    ForEach(ExportQuality.allCases, id: \.self) { q in
                        Button(action: { selectedQuality = q }) {
                            Text(q.rawValue).font(.system(size: 11, weight: .medium))
                                .foregroundColor(selectedQuality == q ? .black : .white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(selectedQuality == q ? Color.white : Color.white.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            if isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: exportProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                    Text("\(Int(exportProgress * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.cyan)
                }
            } else {
                VStack(spacing: 10) {
                    ExportButton(title: "USDZ (3D)", icon: "cube.fill") {
                        exportUSDZ()
                    }
                    
                    ExportButton(title: "JSON", icon: "doc.text") {
                        exportJSON()
                    }
                    
                    ExportButton(title: "OBJ", icon: "cube") {
                        exportOBJ()
                    }
                }
            }
            
            Button("Cancel") { onDismiss() }
                .foregroundColor(.red)
                .disabled(isExporting)
        }
        .padding(20)
        .frame(width: 220)
        .background(Color(white: 0.15, opacity: 0.95))
        .cornerRadius(16)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }
    
    private func exportUSDZ() {
        isExporting = true
        exportProgress = 0
        ExportManager.exportAsUSDZ(strokes: strokes, quality: selectedQuality, onProgress: { p in
            exportProgress = p
        }) { url in
            isExporting = false
            if let url = url {
                exportURL = url
                showShareSheet = true
            }
        }
    }
    
    private func exportJSON() {
        ExportManager.exportAsJSON(strokes: strokes) { url in
            if let url = url {
                exportURL = url
                showShareSheet = true
            }
        }
    }
    
    private func exportOBJ() {
        ExportManager.exportAsOBJ(strokes: strokes) { url in
            if let url = url {
                exportURL = url
                showShareSheet = true
            }
        }
    }
}

struct ExportButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Image(systemName: "square.and.arrow.up")
            }
            .foregroundColor(.white)
            .padding(12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
