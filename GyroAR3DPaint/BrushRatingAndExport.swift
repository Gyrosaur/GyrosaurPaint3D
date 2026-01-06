import SwiftUI
import Foundation
import RealityKit

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
            // Header
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
            
            // Stats
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
            
            // Star rating
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
            
            // Notes toggle
            Button(action: { withAnimation { showNotes.toggle() } }) {
                HStack {
                    Image(systemName: "note.text")
                    Text(showNotes ? "Hide Notes" : "Add Notes")
                        .font(.system(size: 12))
                }
                .foregroundColor(.blue)
            }
            
            // Notes field
            if showNotes {
                TextField("Notes, wishes, ideas...", text: $currentNotes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .lineLimit(3...6)
                    .font(.system(size: 12))
            }
            
            // Submit button
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
            
            // Previous ratings
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

import SceneKit

class ExportManager {
    
    // Export as USDZ using SceneKit (standard format, works in Blender)
    static func exportAsUSDZ(strokes: [Stroke], quality: ExportQuality = .high, onProgress: @escaping (Float) -> Void, completion: @escaping (URL?) -> Void) {
        Task {
            let scene = SCNScene()
            let totalStrokes = strokes.count
            let skip = quality.pointSkip
            
            // Material cache to avoid creating duplicates
            var materialCache: [String: SCNMaterial] = [:]
            
            func getMaterial(for color: UIColor) -> SCNMaterial {
                var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                let key = "\(Int(r*255))_\(Int(g*255))_\(Int(b*255))_\(Int(a*100))"
                
                if let cached = materialCache[key] {
                    return cached
                }
                
                let material = SCNMaterial()
                material.diffuse.contents = color
                material.lightingModel = .physicallyBased
                material.metalness.contents = 0.1
                material.roughness.contents = 0.6
                // Lisää emission jotta värit näkyvät paremmin
                material.emission.contents = color.withAlphaComponent(0.15)
                materialCache[key] = material
                return material
            }
            
            for (strokeIndex, stroke) in strokes.enumerated() {
                guard stroke.points.count >= 2 else { continue }
                
                let strokeNode = SCNNode()
                strokeNode.name = "stroke_\(stroke.brushType.rawValue)_\(strokeIndex)"
                
                // Stroke-level color (fallback)
                let strokeColor = UIColor(stroke.color)
                
                for i in stride(from: 0, to: stroke.points.count, by: skip) {
                    let p = stroke.points[i]
                    
                    // Get point-specific color or use stroke color
                    let pointColor: UIColor
                    if let pc = p.color {
                        pointColor = UIColor(pc).withAlphaComponent(CGFloat(p.opacity))
                    } else {
                        pointColor = strokeColor.withAlphaComponent(CGFloat(p.opacity))
                    }
                    
                    // Apply gradient if present
                    let finalColor: UIColor
                    if abs(p.gradientValue) > 0.05 {
                        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                        pointColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                        let gradientPosition = Float(i) / Float(max(1, stroke.points.count - 1))
                        let intensity = abs(CGFloat(p.gradientValue))
                        let brightnessRange: CGFloat = 0.5 * intensity
                        var brightnessAdjust: CGFloat
                        if p.gradientValue < 0 {
                            brightnessAdjust = brightnessRange * (1 - CGFloat(gradientPosition) * 2)
                        } else {
                            brightnessAdjust = brightnessRange * (CGFloat(gradientPosition) * 2 - 1)
                        }
                        b = max(0.1, min(1.0, b + brightnessAdjust))
                        finalColor = UIColor(hue: h, saturation: s, brightness: b, alpha: a)
                    } else {
                        finalColor = pointColor
                    }
                    
                    let material = getMaterial(for: finalColor)
                    
                    let sphere = SCNSphere(radius: CGFloat(p.brushSize))
                    sphere.segmentCount = quality == .high ? 16 : (quality == .medium ? 12 : 8)
                    sphere.materials = [material]
                    let sphereNode = SCNNode(geometry: sphere)
                    sphereNode.position = SCNVector3(p.position.x, p.position.y, p.position.z)
                    strokeNode.addChildNode(sphereNode)
                    
                    if i > 0 {
                        let prevIdx = max(0, i - skip)
                        let prev = stroke.points[prevIdx]
                        let dist = simd_distance(prev.position, p.position)
                        if dist > 0.001 {
                            let cyl = SCNCylinder(radius: CGFloat(p.brushSize * 0.8), height: CGFloat(dist))
                            cyl.radialSegmentCount = quality == .high ? 12 : (quality == .medium ? 8 : 6)
                            cyl.materials = [material]
                            let cylNode = SCNNode(geometry: cyl)
                            cylNode.position = SCNVector3(
                                (prev.position.x + p.position.x) / 2,
                                (prev.position.y + p.position.y) / 2,
                                (prev.position.z + p.position.z) / 2
                            )
                            // Orient cylinder
                            let dir = simd_normalize(p.position - prev.position)
                            cylNode.look(at: SCNVector3(p.position.x, p.position.y, p.position.z))
                            cylNode.eulerAngles.x += .pi / 2
                            strokeNode.addChildNode(cylNode)
                        }
                    }
                }
                
                scene.rootNode.addChildNode(strokeNode)
                let progress = Float(strokeIndex + 1) / Float(totalStrokes) * 0.8
                await MainActor.run { onProgress(progress) }
            }
            
            // Add ambient light for better color visibility
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.intensity = 500
            ambientLight.light?.color = UIColor.white
            scene.rootNode.addChildNode(ambientLight)
            
            await MainActor.run { onProgress(0.9) }
            
            let filename = "GyroArt_\(Int(Date().timeIntervalSince1970)).usdz"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            
            // Use SceneKit's write method for standard USDZ
            let success = scene.write(to: tempURL, options: nil, delegate: nil, progressHandler: nil)
            
            await MainActor.run {
                onProgress(1.0)
                completion(success ? tempURL : nil)
            }
        }
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
            
            // Export points as vertices
            for point in stroke.points {
                objContent += "v \(point.position.x) \(point.position.y) \(point.position.z)\n"
            }
            
            // Create line from vertices
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
            
            // Quality selector
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
