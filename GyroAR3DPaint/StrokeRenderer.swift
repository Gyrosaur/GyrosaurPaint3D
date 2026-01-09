import RealityKit
import UIKit
import simd
import SwiftUI

class StrokeRenderer {
    private weak var arView: ARView?
    private var strokeAnchors: [UUID: AnchorEntity] = [:]
    private var selectedHighlight: AnchorEntity?
    
    // Cache performance level to avoid main actor issues
    private var cachedPerformanceLevel: PerformanceLevel = .medium
    
    func updatePerformanceLevel() {
        Task { @MainActor in
            self.cachedPerformanceLevel = PerformanceManager.shared.currentLevel
        }
    }
    
    private var performanceLevel: PerformanceLevel {
        return cachedPerformanceLevel
    }
    
    init(arView: ARView) {
        self.arView = arView
        NotificationCenter.default.addObserver(self, selector: #selector(handleClear), name: .strokesCleared, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUndo(_:)), name: .strokeUndone, object: nil)
        
        // Initial performance level sync
        updatePerformanceLevel()
    }
    
    @objc private func handleClear() {
        Task { @MainActor in
            for (_, anchor) in strokeAnchors { anchor.removeFromParent() }
            strokeAnchors.removeAll()
        }
    }
    
    @objc private func handleUndo(_ notification: Notification) {
        guard let id = notification.object as? UUID else { return }
        Task { @MainActor in
            strokeAnchors[id]?.removeFromParent()
            strokeAnchors.removeValue(forKey: id)
        }
    }
    
    func updateStroke(_ stroke: Stroke) {
        guard let arView = arView, stroke.points.count >= 2 else { return }
        let anchor = strokeAnchors[stroke.id] ?? createAnchor(for: stroke.id, in: arView)
        anchor.children.removeAll()
        let entity = buildEntity(for: stroke)
        anchor.addChild(entity)
    }
    
    func finalizeStroke(_ stroke: Stroke) {
        updateStroke(stroke)
    }
    
    func highlightStroke(_ stroke: Stroke) {
        guard let arView = arView else { return }
        selectedHighlight?.removeFromParent()
        let anchor = AnchorEntity(world: .zero)
        let skip = performanceLevel.pointSkip
        for (i, point) in stroke.points.enumerated() where i % skip == 0 {
            let sphere = ModelEntity(mesh: .generateSphere(radius: point.brushSize * 1.5), materials: [SimpleMaterial(color: .green.withAlphaComponent(0.3), isMetallic: false)])
            sphere.position = point.position
            anchor.addChild(sphere)
        }
        arView.scene.addAnchor(anchor)
        selectedHighlight = anchor
    }
    
    func clearHighlight() {
        selectedHighlight?.removeFromParent()
        selectedHighlight = nil
    }
    
    private func createAnchor(for id: UUID, in arView: ARView) -> AnchorEntity {
        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)
        strokeAnchors[id] = anchor
        return anchor
    }
    
    // Downsample points to reduce per-stroke complexity when gradients/per-point colors are active
        private func downsamplePoints(_ pts: [StrokePoint], maxCount: Int, minDistance: Float) -> [StrokePoint] {
            guard pts.count > maxCount else { return pts }
            var result: [StrokePoint] = []
            var lastKept = pts.first!
            result.append(lastKept)
            
            for p in pts.dropFirst() {
                if simd_distance(p.position, lastKept.position) >= minDistance {
                    result.append(p)
                    lastKept = p
                    if result.count >= maxCount { break }
                }
            }
            
            // Ensure the last point is present for continuity
            if let last = pts.last, result.last?.position != last.position {
                result.append(last)
            }
            
            return result
        }
      
    private func buildEntity(for stroke: Stroke) -> ModelEntity {
        switch stroke.brushType {
        case .smooth: return makeTube(stroke, seg: 12)
        case .ribbon: return makeRibbon(stroke)
        case .vine: return makeVine(stroke)
        case .tentacle: return makeTentacle(stroke)
        case .helix: return makeHelix(stroke)
        case .chain: return makeChain(stroke)
        case .zigzag: return makeZigzag(stroke)
        case .spiral: return makeSpiral(stroke)
        case .confetti: return makeConfetti(stroke)
        case .sparkle: return makeSparkle(stroke)
        case .stardust: return makeStardust(stroke)
        case .bubbles: return makeBubbles(stroke)
        case .fireflies: return makeFireflies(stroke)
        case .braid: return makeBraid(stroke)
        case .scales: return makeScales(stroke)
        case .waves: return makeWaves(stroke)
        case .pulse: return makePulse(stroke)
        case .aurora: return makeAurora(stroke)
        case .prism: return makePrism(stroke)
        // Uudet brushit
        case .torus: return makeTorus(stroke)
        case .morph: return makeMorph(stroke)
        case .blob: return makeBlob(stroke)
        case .coil: return makeCoil(stroke)
        case .membrane: return makeMembrane(stroke)
        case .lattice: return makeLattice(stroke)
        case .tendril: return makeTendril(stroke)
        case .voxel: return makeVoxel(stroke)
        }
    }
    
    // MARK: - Color helpers
    private func pointColor(_ p: StrokePoint, _ stroke: Stroke, hueShift: Float = 0, gradientPosition: Float = 0.5) -> UIColor {
        // Use per-point color if available, otherwise stroke color
        let baseColor: Color
        if let pointCol = p.color {
            baseColor = pointCol
        } else {
            baseColor = stroke.color
        }
        var col = UIColor(baseColor)
        
        // Apply gradient based on airPods value and position in stroke
        // gradientPosition: 0 = start of stroke, 1 = end of stroke
        let gradientVal = p.gradientValue
        if abs(gradientVal) > 0.05 {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            col.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            
            // Calculate brightness adjustment based on gradient direction and position
            // gradientVal < 0: light at start, dark at end
            // gradientVal > 0: dark at start, light at end
            let intensity = abs(CGFloat(gradientVal))
            let brightnessRange: CGFloat = 0.6 * intensity  // Max 60% brightness variation
            
            var brightnessAdjust: CGFloat
            if gradientVal < 0 {
                // Light -> Dark (vasen kallistus)
                brightnessAdjust = brightnessRange * (1 - CGFloat(gradientPosition) * 2)  // +range at 0, -range at 1
            } else {
                // Dark -> Light (oikea kallistus)
                brightnessAdjust = brightnessRange * (CGFloat(gradientPosition) * 2 - 1)  // -range at 0, +range at 1
            }
            
            b = max(0.1, min(1.0, b + brightnessAdjust))
            col = UIColor(hue: h, saturation: s, brightness: b, alpha: a)
        }
        
        if abs(hueShift) > 0.01 {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            col.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            h = (h + CGFloat(hueShift)).truncatingRemainder(dividingBy: 1.0)
            if h < 0 { h += 1 }
            col = UIColor(hue: h, saturation: s, brightness: b, alpha: a * CGFloat(p.opacity))
        } else {
            col = col.withAlphaComponent(CGFloat(p.opacity))
        }
        return col
    }
    
    private func randomHueShift() -> Float { Float.random(in: -0.15...0.15) }
    
    // MARK: - Mesh builders
    private func makeTube(_ stroke: Stroke, seg: Int) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        let level = performanceLevel
        let actualSeg = min(seg, level.tubeSegments)
        
        // Check if any point has its own color set or gradient
        let hasPerPointColors = pts.contains { $0.color != nil }
        let hasGradient = pts.contains { abs($0.gradientValue) > 0.05 }
        
        // Adjust max points based on performance level
        let maxPoints: Int
        let minDist: Float
        switch level {
        case .low: maxPoints = 150; minDist = 0.004
        case .medium: maxPoints = 300; minDist = 0.002
        case .high: maxPoints = 500; minDist = 0.001
        }
        
        if hasPerPointColors || hasGradient {
            let sampled = downsamplePoints(pts, maxCount: maxPoints, minDistance: minDist)
            // Per-point rendering for color variation
            for i in 0..<sampled.count {
                let p = sampled[i]
                let gradientPosition = sampled.count > 1 ? Float(i) / Float(sampled.count - 1) : 0.5
                let col = pointColor(p, stroke, gradientPosition: gradientPosition)
                let material = SimpleMaterial(color: col, isMetallic: false)
                
                let sphere = ModelEntity(mesh: .generateSphere(radius: p.brushSize), materials: [material])
                sphere.position = p.position
                parent.addChild(sphere)
                
                if i > 0 {
                    let prev = sampled[i - 1]
                    let dist = simd_distance(prev.position, p.position)
                    if dist > 0.001 {
                        let cyl = ModelEntity(mesh: .generateCylinder(height: dist, radius: p.brushSize * 0.8), materials: [material])
                        cyl.position = (prev.position + p.position) / 2
                        let dir = simd_normalize(p.position - prev.position)
                        cyl.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir)
                        parent.addChild(cyl)
                    }
                }
            }
            return parent
        } else {
            // Downsample for single color too
            let sampled = downsamplePoints(pts, maxCount: maxPoints, minDistance: minDist)
            // Original optimized mesh for single color
            var verts: [SIMD3<Float>] = [], inds: [UInt32] = []
            for i in 0..<sampled.count {
                let p = sampled[i], dir = direction(at: i, pts: sampled), basis = makeBasis(dir)
                for j in 0..<actualSeg {
                    let angle = Float(j) / Float(actualSeg) * .pi * 2
                    let norm = basis.0 * cos(angle) + basis.1 * sin(angle)
                    verts.append(p.position + norm * p.brushSize)
                }
                if i > 0 { for j in 0..<actualSeg { let n = (j + 1) % actualSeg; let b = UInt32((i - 1) * actualSeg); let t = UInt32(i * actualSeg)
                    inds += [b + UInt32(j), t + UInt32(j), b + UInt32(n), b + UInt32(n), t + UInt32(j), t + UInt32(n)] } }
            }
            return buildMesh(verts, inds, pointColor(sampled.first ?? pts[0], stroke))
        }
    }
    
    private func makeRibbon(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        let hasGradient = pts.contains { abs($0.gradientValue) > 0.05 }
        
        if hasGradient {
            let sampled = downsamplePoints(pts, maxCount: 400, minDistance: 0.0015)
            // Per-segment rendering with gradient
            for i in 1..<sampled.count {
                            let p = sampled[i], prev = sampled[i-1]
                            let dir = direction(at: i, pts: sampled)
                let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
                let gradientPosition = Float(i) / Float(sampled.count - 1)
                let col = pointColor(p, stroke, gradientPosition: gradientPosition)
                
                let dist = simd_distance(prev.position, p.position)
                if dist > 0.001 {
                    let ribbon = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(p.brushSize * 4, p.brushSize * 0.2, dist)), materials: [SimpleMaterial(color: col, isMetallic: false)])
                    ribbon.position = (prev.position + p.position) / 2
                    ribbon.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: dir)
                    parent.addChild(ribbon)
                }
            }
            return parent
        } else {
            var verts: [SIMD3<Float>] = [], inds: [UInt32] = []
            for i in 0..<pts.count {
                let p = pts[i], dir = direction(at: i, pts: pts)
                let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
                verts.append(p.position + side * p.brushSize * 2)
                verts.append(p.position - side * p.brushSize * 2)
                if i > 0 { let b = UInt32((i - 1) * 2); inds += [b, b + 2, b + 1, b + 1, b + 2, b + 3] }
            }
            return buildMesh(verts, inds, pointColor(pts[0], stroke))
        }
    }
    
    private func makeVine(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        // Main stem
        parent.addChild(makeTube(stroke, seg: 8))
        // Leaves at intervals
        for i in stride(from: 5, to: pts.count, by: 8) {
            let p = pts[i], dir = direction(at: i, pts: pts)
            let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
            let leafSize = p.brushSize * 3
            let col = pointColor(p, stroke, hueShift: randomHueShift())
            let leaf = ModelEntity(mesh: .generateSphere(radius: leafSize), materials: [SimpleMaterial(color: col, isMetallic: false)])
            leaf.scale = SIMD3<Float>(1, 0.3, 2)
            leaf.position = p.position + side * leafSize * Float(i % 2 == 0 ? 1 : -1)
            parent.addChild(leaf)
        }
        return parent
    }
    
    private func makeCoral(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        parent.addChild(makeTube(stroke, seg: 6))
        for i in stride(from: 3, to: pts.count, by: 5) {
            let p = pts[i]
            for _ in 0..<3 {
                let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize * 2
                let col = pointColor(p, stroke, hueShift: randomHueShift())
                let branch = ModelEntity(mesh: .generateSphere(radius: p.brushSize * 0.8), materials: [SimpleMaterial(color: col, isMetallic: false)])
                branch.position = p.position + offset
                parent.addChild(branch)
            }
        }
        return parent
    }
    
    private func makeTentacle(_ stroke: Stroke) -> ModelEntity {
        var verts: [SIMD3<Float>] = [], inds: [UInt32] = []
        let pts = stroke.points, seg = 8
        for i in 0..<pts.count {
            let p = pts[i], dir = direction(at: i, pts: pts), basis = makeBasis(dir)
            let taper = 1.0 - Float(i) / Float(pts.count) * 0.7
            for j in 0..<seg {
                let angle = Float(j) / Float(seg) * .pi * 2
                let wobble = sin(Float(i) * 0.5 + angle * 2) * 0.3
                let norm = basis.0 * cos(angle) + basis.1 * sin(angle)
                verts.append(p.position + norm * p.brushSize * taper * (1 + wobble))
            }
            if i > 0 { for j in 0..<seg { let n = (j + 1) % seg; let b = UInt32((i - 1) * seg); let t = UInt32(i * seg)
                inds += [b + UInt32(j), t + UInt32(j), b + UInt32(n), b + UInt32(n), t + UInt32(j), t + UInt32(n)] } }
        }
        return buildMesh(verts, inds, pointColor(pts[0], stroke))
    }
    
    private func makeRoot(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        parent.addChild(makeTube(stroke, seg: 6))
        let pts = stroke.points
        for i in stride(from: 4, to: pts.count, by: 6) {
            let p = pts[i]
            let rootLen = p.brushSize * 4
            let col = pointColor(p, stroke, hueShift: Float.random(in: -0.1...0.1))
            let root = ModelEntity(mesh: .generateCylinder(height: rootLen, radius: p.brushSize * 0.3), materials: [SimpleMaterial(color: col, isMetallic: false)])
            root.position = p.position + SIMD3<Float>(0, -rootLen / 2, 0)
            parent.addChild(root)
        }
        return parent
    }
    
    private func makeBranch(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        parent.addChild(makeTube(stroke, seg: 6))
        let pts = stroke.points
        for i in stride(from: 6, to: pts.count, by: 10) {
            let p = pts[i], dir = direction(at: i, pts: pts)
            let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
            let branchLen = p.brushSize * 5
            let col = pointColor(p, stroke, hueShift: randomHueShift())
            let branch = ModelEntity(mesh: .generateCylinder(height: branchLen, radius: p.brushSize * 0.4), materials: [SimpleMaterial(color: col, isMetallic: false)])
            branch.position = p.position + side * branchLen / 2 * Float(i % 2 == 0 ? 1 : -1)
            branch.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: side * Float(i % 2 == 0 ? 1 : -1))
            parent.addChild(branch)
        }
        return parent
    }
    
    private func makeHelix(_ stroke: Stroke) -> ModelEntity {
        var verts: [SIMD3<Float>] = [], inds: [UInt32] = []
        let pts = stroke.points, seg = 8
        for i in 0..<pts.count {
            let p = pts[i], dir = direction(at: i, pts: pts), basis = makeBasis(dir)
            let helixAngle = Float(i) * 0.5
            let helixOffset = (basis.0 * cos(helixAngle) + basis.1 * sin(helixAngle)) * p.brushSize * 2
            for j in 0..<seg {
                let angle = Float(j) / Float(seg) * .pi * 2
                let norm = basis.0 * cos(angle) + basis.1 * sin(angle)
                verts.append(p.position + helixOffset + norm * p.brushSize * 0.5)
            }
            if i > 0 { for j in 0..<seg { let n = (j + 1) % seg; let b = UInt32((i - 1) * seg); let t = UInt32(i * seg)
                inds += [b + UInt32(j), t + UInt32(j), b + UInt32(n), b + UInt32(n), t + UInt32(j), t + UInt32(n)] } }
        }
        return buildMesh(verts, inds, pointColor(pts[0], stroke))
    }
    
    private func makeDNA(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for i in 0..<pts.count {
            let p = pts[i], dir = direction(at: i, pts: pts), basis = makeBasis(dir)
            let angle = Float(i) * 0.4
            let offset1 = (basis.0 * cos(angle) + basis.1 * sin(angle)) * p.brushSize * 2
            let offset2 = (basis.0 * cos(angle + .pi) + basis.1 * sin(angle + .pi)) * p.brushSize * 2
            let col1 = pointColor(p, stroke, hueShift: 0.1)
            let col2 = pointColor(p, stroke, hueShift: -0.1)
            let s1 = ModelEntity(mesh: .generateSphere(radius: p.brushSize * 0.6), materials: [SimpleMaterial(color: col1, isMetallic: false)])
            let s2 = ModelEntity(mesh: .generateSphere(radius: p.brushSize * 0.6), materials: [SimpleMaterial(color: col2, isMetallic: false)])
            s1.position = p.position + offset1; s2.position = p.position + offset2
            parent.addChild(s1); parent.addChild(s2)
            if i % 4 == 0 {
                let bar = ModelEntity(mesh: .generateCylinder(height: p.brushSize * 4, radius: p.brushSize * 0.15), materials: [SimpleMaterial(color: .white, isMetallic: false)])
                bar.position = p.position
                bar.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(offset1 - offset2))
                parent.addChild(bar)
            }
        }
        return parent
    }
    
    private func makeChain(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for i in stride(from: 0, to: pts.count, by: 3) {
            let p = pts[i]
            let col = pointColor(p, stroke, hueShift: Float(i % 2) * 0.1)
            let link = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(p.brushSize * 2, p.brushSize, p.brushSize * 3), cornerRadius: p.brushSize * 0.3), materials: [SimpleMaterial(color: col, isMetallic: true)])
            link.position = p.position
            if i > 0 { link.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: direction(at: i, pts: pts)) }
            if i % 6 == 0 { link.orientation *= simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1)) }
            parent.addChild(link)
        }
        return parent
    }
    
    private func makeZigzag(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for i in 0..<pts.count - 1 {
            let p = pts[i], p2 = pts[i + 1]
            let dir = direction(at: i, pts: pts)
            let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
            let offset = side * p.brushSize * 2 * Float(i % 2 == 0 ? 1 : -1)
            let start = p.position + offset, end = p2.position - offset
            let dist = simd_distance(start, end)
            let col = pointColor(p, stroke)
            let seg = ModelEntity(mesh: .generateCylinder(height: dist, radius: p.brushSize * 0.5), materials: [SimpleMaterial(color: col, isMetallic: false)])
            seg.position = (start + end) / 2
            seg.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(end - start))
            parent.addChild(seg)
        }
        return parent
    }
    
    private func makeSpiral(_ stroke: Stroke) -> ModelEntity {
        var verts: [SIMD3<Float>] = [], inds: [UInt32] = []
        let pts = stroke.points, seg = 8
        for i in 0..<pts.count {
            let p = pts[i], dir = direction(at: i, pts: pts), basis = makeBasis(dir)
            let spiralR = p.brushSize * (1 + Float(i) * 0.1)
            let spiralAngle = Float(i) * 0.3
            let center = p.position + (basis.0 * cos(spiralAngle) + basis.1 * sin(spiralAngle)) * spiralR
            for j in 0..<seg {
                let angle = Float(j) / Float(seg) * .pi * 2
                let norm = basis.0 * cos(angle) + basis.1 * sin(angle)
                verts.append(center + norm * p.brushSize * 0.4)
            }
            if i > 0 { for j in 0..<seg { let n = (j + 1) % seg; let b = UInt32((i - 1) * seg); let t = UInt32(i * seg)
                inds += [b + UInt32(j), t + UInt32(j), b + UInt32(n), b + UInt32(n), t + UInt32(j), t + UInt32(n)] } }
        }
        return buildMesh(verts, inds, pointColor(pts[0], stroke))
    }
    
    private func makeSplatter(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        for p in stroke.points {
            for _ in 0..<3 {
                let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize * 2
                let col = pointColor(p, stroke, hueShift: randomHueShift())
                let drop = ModelEntity(mesh: .generateSphere(radius: p.brushSize * Float.random(in: 0.3...1.0)), materials: [SimpleMaterial(color: col, isMetallic: false)])
                drop.position = p.position + offset
                parent.addChild(drop)
            }
        }
        return parent
    }
    
    private func makeConfetti(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        for p in stroke.points {
            let col = pointColor(p, stroke, hueShift: Float.random(in: -0.5...0.5))
            let confetti = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(p.brushSize * 2, p.brushSize * 0.2, p.brushSize)), materials: [SimpleMaterial(color: col, isMetallic: false)])
            confetti.position = p.position + SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize
            confetti.orientation = simd_quatf(angle: Float.random(in: 0...(.pi * 2)), axis: SIMD3<Float>(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1)))
            parent.addChild(confetti)
        }
        return parent
    }
    
    private func makeSparkle(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        for (i, p) in stroke.points.enumerated() where i % 2 == 0 {
            let col = pointColor(p, stroke, hueShift: Float.random(in: -0.2...0.2))
            // 6-point star
            for axis in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)] {
                let spike = ModelEntity(mesh: .generateCylinder(height: p.brushSize * 3, radius: p.brushSize * 0.15), materials: [SimpleMaterial(color: col, isMetallic: true)])
                spike.position = p.position
                spike.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: axis)
                parent.addChild(spike)
            }
        }
        return parent
    }
    
    private func makeStardust(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        for p in stroke.points {
            for _ in 0..<2 {
                let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize * 1.5
                let size = p.brushSize * Float.random(in: 0.2...0.6)
                let col = pointColor(p, stroke, hueShift: Float.random(in: -0.3...0.3))
                let star = ModelEntity(mesh: .generateSphere(radius: size), materials: [SimpleMaterial(color: col, isMetallic: true)])
                star.position = p.position + offset
                parent.addChild(star)
            }
        }
        return parent
    }
    
    private func makeBubbles(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        for (i, p) in stroke.points.enumerated() where i % 3 == 0 {
            let col = pointColor(p, stroke, hueShift: randomHueShift())
            var mat = SimpleMaterial(); mat.color = .init(tint: col.withAlphaComponent(0.4)); mat.metallic = .float(0.8)
            let bubble = ModelEntity(mesh: .generateSphere(radius: p.brushSize * Float.random(in: 1...2)), materials: [mat])
            bubble.position = p.position + SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize
            parent.addChild(bubble)
        }
        return parent
    }
    
    private func makeFireflies(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        for (i, p) in stroke.points.enumerated() where i % 4 == 0 {
            let col = pointColor(p, stroke, hueShift: Float.random(in: -0.1...0.1))
            var mat = SimpleMaterial(); mat.color = .init(tint: col); mat.metallic = .float(1.0)
            let glow = ModelEntity(mesh: .generateSphere(radius: p.brushSize * 0.5), materials: [mat])
            glow.position = p.position + SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize * 2
            parent.addChild(glow)
        }
        return parent
    }
    
    private func makeRope(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        // Multiple twisted strands
        for strand in 0..<3 {
            for i in 0..<pts.count {
                let p = pts[i], dir = direction(at: i, pts: pts), basis = makeBasis(dir)
                let angle = Float(i) * 0.5 + Float(strand) * .pi * 2 / 3
                let offset = (basis.0 * cos(angle) + basis.1 * sin(angle)) * p.brushSize * 0.7
                let col = pointColor(p, stroke, hueShift: Float(strand) * 0.05)
                let seg = ModelEntity(mesh: .generateSphere(radius: p.brushSize * 0.4), materials: [SimpleMaterial(color: col, isMetallic: false)])
                seg.position = p.position + offset
                parent.addChild(seg)
            }
        }
        return parent
    }
    
    private func makeBraid(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for strand in 0..<3 {
            for i in 0..<pts.count {
                let p = pts[i], dir = direction(at: i, pts: pts), basis = makeBasis(dir)
                let phase = Float(strand) * .pi * 2 / 3
                let xOff = cos(Float(i) * 0.3 + phase) * p.brushSize
                let yOff = sin(Float(i) * 0.6 + phase) * p.brushSize * 0.5
                let offset = basis.0 * xOff + basis.1 * yOff
                let col = pointColor(p, stroke, hueShift: Float(strand) * 0.1 - 0.1)
                let seg = ModelEntity(mesh: .generateSphere(radius: p.brushSize * 0.5), materials: [SimpleMaterial(color: col, isMetallic: false)])
                seg.position = p.position + offset
                parent.addChild(seg)
            }
        }
        return parent
    }
    
    private func makeKnit(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for i in 0..<pts.count {
            let p = pts[i], dir = direction(at: i, pts: pts), basis = makeBasis(dir)
            let col = pointColor(p, stroke, hueShift: Float(i % 2) * 0.1)
            // Loop pattern
            let loopAngle = Float(i) * 0.8
            for j in 0..<6 {
                let a = Float(j) / 6 * .pi * 2 + loopAngle
                let offset = (basis.0 * cos(a) + basis.1 * sin(a)) * p.brushSize
                let knot = ModelEntity(mesh: .generateSphere(radius: p.brushSize * 0.25), materials: [SimpleMaterial(color: col, isMetallic: false)])
                knot.position = p.position + offset
                parent.addChild(knot)
            }
        }
        return parent
    }
    
    private func makeScales(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for (i, p) in pts.enumerated() {
            let dir = direction(at: i, pts: pts)
            let col = pointColor(p, stroke, hueShift: Float(i % 3) * 0.05)
            let scale = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(p.brushSize * 2, p.brushSize * 0.3, p.brushSize * 1.5), cornerRadius: p.brushSize * 0.2), materials: [SimpleMaterial(color: col, isMetallic: true)])
            scale.position = p.position
            scale.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: dir) * simd_quatf(angle: Float(i % 2) * 0.3 - 0.15, axis: SIMD3<Float>(1, 0, 0))
            parent.addChild(scale)
        }
        return parent
    }
    
    private func makeFeather(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        parent.addChild(makeTube(stroke, seg: 4))
        let pts = stroke.points
        for i in stride(from: 2, to: pts.count, by: 3) {
            let p = pts[i], dir = direction(at: i, pts: pts)
            let side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
            for s in [-1, 1] as [Float] {
                let col = pointColor(p, stroke, hueShift: Float.random(in: -0.05...0.05))
                let barb = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(p.brushSize * 3, p.brushSize * 0.1, p.brushSize * 0.3)), materials: [SimpleMaterial(color: col, isMetallic: false)])
                barb.position = p.position + side * p.brushSize * 1.5 * s
                barb.orientation = simd_quatf(angle: s * 0.3, axis: dir)
                parent.addChild(barb)
            }
        }
        return parent
    }
    
    private func makeWaves(_ stroke: Stroke) -> ModelEntity {
        var verts: [SIMD3<Float>] = [], inds: [UInt32] = []
        let pts = stroke.points, seg = 8
        for i in 0..<pts.count {
            let p = pts[i], dir = direction(at: i, pts: pts), basis = makeBasis(dir)
            let wave = sin(Float(i) * 0.5) * p.brushSize
            for j in 0..<seg {
                let angle = Float(j) / Float(seg) * .pi * 2
                let norm = basis.0 * cos(angle) + basis.1 * sin(angle)
                verts.append(p.position + basis.1 * wave + norm * p.brushSize * 0.6)
            }
            if i > 0 { for j in 0..<seg { let n = (j + 1) % seg; let b = UInt32((i - 1) * seg); let t = UInt32(i * seg)
                inds += [b + UInt32(j), t + UInt32(j), b + UInt32(n), b + UInt32(n), t + UInt32(j), t + UInt32(n)] } }
        }
        return buildMesh(verts, inds, pointColor(pts[0], stroke))
    }
    
    private func makePulse(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for (i, p) in pts.enumerated() {
            let pulseSize = p.brushSize * (1 + sin(Float(i) * 0.5) * 0.5)
            let col = pointColor(p, stroke, hueShift: sin(Float(i) * 0.3) * 0.1)
            let sphere = ModelEntity(mesh: .generateSphere(radius: pulseSize), materials: [SimpleMaterial(color: col, isMetallic: false)])
            sphere.position = p.position
            parent.addChild(sphere)
        }
        return parent
    }
    
    private func makeAurora(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for layer in 0..<3 {
            for (i, p) in pts.enumerated() {
                let dir = direction(at: i, pts: pts), basis = makeBasis(dir)
                let yOff = Float(layer) * p.brushSize * 0.8
                let wave = sin(Float(i) * 0.3 + Float(layer)) * p.brushSize
                let hue = Float(layer) * 0.15 + Float(i) * 0.01
                let col = pointColor(p, stroke, hueShift: hue)
                var mat = SimpleMaterial(); mat.color = .init(tint: col.withAlphaComponent(0.5))
                let ribbon = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(p.brushSize * 2, p.brushSize * 0.1, p.brushSize * 0.5)), materials: [mat])
                ribbon.position = p.position + basis.1 * (yOff + wave)
                parent.addChild(ribbon)
            }
        }
        return parent
    }
    
    private func makePrism(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for (i, p) in pts.enumerated() where i % 2 == 0 {
            let dir = direction(at: i, pts: pts)
            let col = pointColor(p, stroke, hueShift: Float(i % 6) * 0.1)
            let prism = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(p.brushSize, p.brushSize * 2, p.brushSize), cornerRadius: 0), materials: [SimpleMaterial(color: col, isMetallic: true)])
            prism.position = p.position
            prism.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir) * simd_quatf(angle: Float(i) * 0.2, axis: dir)
            parent.addChild(prism)
        }
        return parent
    }
    
    // Crystal - sharp crystalline shards
    // MARK: - New Innovative Brushes
    
    // Torus - donut/ring shape at each point
    private func makeTorus(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for (i, p) in pts.enumerated() where i % 3 == 0 {
            let dir = direction(at: i, pts: pts)
            let col = pointColor(p, stroke, hueShift: Float(i % 6) * 0.05)
            let majorRadius = p.brushSize * 1.5
            let minorRadius = p.brushSize * 0.3
            // Approximate torus with small spheres in ring
            for j in 0..<12 {
                let angle = Float(j) / 12 * Float.pi * 2
                let ringX = cos(angle) * majorRadius
                let ringZ = sin(angle) * majorRadius
                let sphere = ModelEntity(mesh: .generateSphere(radius: minorRadius), materials: [SimpleMaterial(color: col, isMetallic: true)])
                let basis = makeBasis(dir)
                sphere.position = p.position + basis.0 * ringX + basis.1 * ringZ
                parent.addChild(sphere)
            }
        }
        return parent
    }
    
    // Morph - polygon that changes sides (3-8) as you draw
    private func makeMorph(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for (i, p) in pts.enumerated() where i % 2 == 0 {
            let dir = direction(at: i, pts: pts)
            let basis = makeBasis(dir)
            let col = pointColor(p, stroke, hueShift: Float(i % 8) * 0.04)
            // Number of sides changes along stroke (3 to 8)
            let sides = 3 + (i / 5) % 6
            let radius = p.brushSize
            // Create polygon with varying sides
            for j in 0..<sides {
                let angle1 = Float(j) / Float(sides) * Float.pi * 2
                let angle2 = Float(j + 1) / Float(sides) * Float.pi * 2
                let p1 = basis.0 * cos(angle1) * radius + basis.1 * sin(angle1) * radius
                let p2 = basis.0 * cos(angle2) * radius + basis.1 * sin(angle2) * radius
                let edgeLen = simd_distance(p1, p2)
                let edgeMid = (p1 + p2) / 2
                let edgeDir = simd_normalize(p2 - p1)
                let edge = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(edgeLen, p.brushSize * 0.15, p.brushSize * 0.15), cornerRadius: 0), materials: [SimpleMaterial(color: col, isMetallic: false)])
                edge.position = p.position + edgeMid
                edge.orientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: edgeDir)
                parent.addChild(edge)
            }
        }
        return parent
    }
    
    // Blob - organic metaball-like shape
    private func makeBlob(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for (i, p) in pts.enumerated() {
            let col = pointColor(p, stroke, hueShift: Float.random(in: -0.08...0.08))
            // Central blob
            let blobSize = p.brushSize * Float.random(in: 0.7...1.3)
            let blob = ModelEntity(mesh: .generateSphere(radius: blobSize), materials: [SimpleMaterial(color: col, isMetallic: false)])
            blob.position = p.position
            // Squash/stretch randomly for organic feel
            blob.scale = SIMD3<Float>(Float.random(in: 0.6...1.4), Float.random(in: 0.6...1.4), Float.random(in: 0.6...1.4))
            parent.addChild(blob)
            // Add smaller satellite blobs
            if i % 3 == 0 {
                for _ in 0..<Int.random(in: 2...4) {
                    let offset = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * p.brushSize
                    let satellite = ModelEntity(mesh: .generateSphere(radius: p.brushSize * Float.random(in: 0.2...0.5)), materials: [SimpleMaterial(color: col, isMetallic: false)])
                    satellite.position = p.position + offset
                    parent.addChild(satellite)
                }
            }
        }
        return parent
    }
    
    // Coil - spring/helix that winds around the path
    private func makeCoil(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        let coilRadius = pts.first?.brushSize ?? 0.01
        var coilAngle: Float = 0
        for (i, p) in pts.enumerated() {
            let dir = direction(at: i, pts: pts)
            let basis = makeBasis(dir)
            let col = pointColor(p, stroke, hueShift: Float(i % 10) * 0.03)
            // Coil winds around path
            coilAngle += 0.5
            let x = cos(coilAngle) * coilRadius * 2
            let y = sin(coilAngle) * coilRadius * 2
            let coilPos = p.position + basis.0 * x + basis.1 * y
            let sphere = ModelEntity(mesh: .generateSphere(radius: p.brushSize * 0.4), materials: [SimpleMaterial(color: col, isMetallic: true)])
            sphere.position = coilPos
            parent.addChild(sphere)
            // Connect coil segments
            if i > 0 {
                let prevAngle = coilAngle - 0.5
                let prevP = pts[i-1]
                let prevBasis = makeBasis(direction(at: i-1, pts: pts))
                let prevX = cos(prevAngle) * coilRadius * 2
                let prevY = sin(prevAngle) * coilRadius * 2
                let prevCoilPos = prevP.position + prevBasis.0 * prevX + prevBasis.1 * prevY
                let dist = simd_distance(prevCoilPos, coilPos)
                if dist > 0.001 {
                    let wire = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(p.brushSize * 0.15, dist, p.brushSize * 0.15), cornerRadius: 0), materials: [SimpleMaterial(color: col, isMetallic: true)])
                    wire.position = (prevCoilPos + coilPos) / 2
                    wire.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(coilPos - prevCoilPos))
                    parent.addChild(wire)
                }
            }
        }
        return parent
    }
    
    // Membrane - thin bubble/film surface
    private func makeMembrane(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        for (i, p) in pts.enumerated() where i % 2 == 0 {
            let dir = direction(at: i, pts: pts)
            let basis = makeBasis(dir)
            let col = pointColor(p, stroke, hueShift: Float(i % 5) * 0.06)
            // Thin ellipsoid membrane
            let membrane = ModelEntity(mesh: .generateSphere(radius: p.brushSize), materials: [SimpleMaterial(color: col.withAlphaComponent(0.6), isMetallic: false)])
            membrane.position = p.position
            // Flatten into disc/membrane shape
            membrane.scale = SIMD3<Float>(2.0, 0.1, 2.0)
            membrane.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir)
            parent.addChild(membrane)
        }
        return parent
    }
    
    // Lattice - 3D grid structure that grows
    private func makeLattice(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        let gridSize = pts.first?.brushSize ?? 0.01
        for (i, p) in pts.enumerated() where i % 4 == 0 {
            let col = pointColor(p, stroke, hueShift: Float(i % 3) * 0.1)
            // Create 3x3x3 mini lattice at each point
            for x in -1...1 {
                for y in -1...1 {
                    for z in -1...1 {
                        // Nodes at corners
                        if abs(x) + abs(y) + abs(z) >= 2 {
                            let nodePos = p.position + SIMD3<Float>(Float(x), Float(y), Float(z)) * gridSize
                            let node = ModelEntity(mesh: .generateSphere(radius: gridSize * 0.15), materials: [SimpleMaterial(color: col, isMetallic: true)])
                            node.position = nodePos
                            parent.addChild(node)
                        }
                    }
                }
            }
            // Connecting struts
            let strutLen = gridSize * 2
            for axis in [SIMD3<Float>(1,0,0), SIMD3<Float>(0,1,0), SIMD3<Float>(0,0,1)] {
                let strut = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(gridSize * 0.05, strutLen, gridSize * 0.05), cornerRadius: 0), materials: [SimpleMaterial(color: col, isMetallic: true)])
                strut.position = p.position
                strut.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: axis)
                parent.addChild(strut)
            }
        }
        return parent
    }
    
    // Tendril - organic branching tendrils
    private func makeTendril(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        // Main tendril
        parent.addChild(makeTube(stroke, seg: 8))
        // Branching sub-tendrils
        for (i, p) in pts.enumerated() where i % 6 == 0 && i > 0 {
            let dir = direction(at: i, pts: pts)
            let basis = makeBasis(dir)
            let col = pointColor(p, stroke, hueShift: Float.random(in: -0.1...0.1))
            // 2-4 branches
            let numBranches = Int.random(in: 2...4)
            for b in 0..<numBranches {
                let branchAngle = Float(b) / Float(numBranches) * Float.pi * 2 + Float.random(in: -0.3...0.3)
                let branchDir = simd_normalize(basis.0 * cos(branchAngle) + basis.1 * sin(branchAngle) + dir * 0.5)
                // Branch with decreasing segments
                var branchPos = p.position
                var branchSize = p.brushSize * 0.6
                for seg in 0..<Int.random(in: 3...6) {
                    let segLen = branchSize * 2
                    let nextPos = branchPos + branchDir * segLen
                    let segment = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(branchSize * 0.3, segLen, branchSize * 0.3), cornerRadius: branchSize * 0.1), materials: [SimpleMaterial(color: col, isMetallic: false)])
                    segment.position = (branchPos + nextPos) / 2
                    segment.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: branchDir)
                    parent.addChild(segment)
                    branchPos = nextPos
                    branchSize *= 0.7
                }
            }
        }
        return parent
    }
    
    // Voxel - pixelated 3D cubes
    private func makeVoxel(_ stroke: Stroke) -> ModelEntity {
        let parent = ModelEntity()
        let pts = stroke.points
        let voxelSize = (pts.first?.brushSize ?? 0.01) * 0.8
        var placedVoxels = Set<String>()
        for p in pts {
            let col = pointColor(p, stroke, hueShift: Float.random(in: -0.05...0.05))
            // Snap to grid
            let gridX = round(p.position.x / voxelSize) * voxelSize
            let gridY = round(p.position.y / voxelSize) * voxelSize
            let gridZ = round(p.position.z / voxelSize) * voxelSize
            let key = "\(Int(gridX*1000))_\(Int(gridY*1000))_\(Int(gridZ*1000))"
            if !placedVoxels.contains(key) {
                placedVoxels.insert(key)
                let voxel = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(voxelSize * 0.95, voxelSize * 0.95, voxelSize * 0.95), cornerRadius: 0), materials: [SimpleMaterial(color: col, isMetallic: false)])
                voxel.position = SIMD3<Float>(gridX, gridY, gridZ)
                parent.addChild(voxel)
            }
        }
        return parent
    }
    
    // MARK: - Helpers
    private func direction(at i: Int, pts: [StrokePoint]) -> SIMD3<Float> {    private func direction(at i: Int, pts: [StrokePoint]) -> SIMD3<Float> {
        if pts.count < 2 { return SIMD3<Float>(0, 0, 1) }
        if i == 0 { return simd_normalize(pts[1].position - pts[0].position) }
        if i >= pts.count - 1 { return simd_normalize(pts[pts.count - 1].position - pts[pts.count - 2].position) }
        return simd_normalize(pts[i + 1].position - pts[i - 1].position)
    }
    
    private func makeBasis(_ dir: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let up = abs(dir.y) < 0.99 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let right = simd_normalize(simd_cross(up, dir))
        let realUp = simd_cross(dir, right)
        return (right, realUp)
    }
    
    private func buildMesh(_ verts: [SIMD3<Float>], _ inds: [UInt32], _ col: UIColor) -> ModelEntity {
        var desc = MeshDescriptor()
        desc.positions = MeshBuffer(verts)
        desc.primitives = .triangles(inds)
        do {
            let mesh = try MeshResource.generate(from: [desc])
            let mat = SimpleMaterial(color: col, isMetallic: false)
            return ModelEntity(mesh: mesh, materials: [mat])
        } catch {
            return ModelEntity()
        }
    }
}
