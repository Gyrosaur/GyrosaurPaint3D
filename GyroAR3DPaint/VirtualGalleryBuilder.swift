import SwiftUI
import RealityKit
import simd

// MARK: - White Room Builder

class WhiteRoomBuilder {
    
    // Create a simple white room (10m x 5m x 10m)
    static func buildRoom() -> Entity {
        let roomRoot = Entity()
        
        let width: Float = 10
        let height: Float = 5
        let depth: Float = 10
        
        // Materials
        var floorMaterial = PhysicallyBasedMaterial()
        floorMaterial.baseColor = .init(tint: UIColor(white: 0.85, alpha: 1))
        floorMaterial.roughness = 0.6
        floorMaterial.metallic = 0.0
        
        var wallMaterial = PhysicallyBasedMaterial()
        wallMaterial.baseColor = .init(tint: UIColor(white: 0.95, alpha: 1))
        wallMaterial.roughness = 0.9
        wallMaterial.metallic = 0.0
        
        var ceilingMaterial = PhysicallyBasedMaterial()
        ceilingMaterial.baseColor = .init(tint: UIColor(white: 1.0, alpha: 1))
        ceilingMaterial.roughness = 0.95
        ceilingMaterial.metallic = 0.0
        
        // Floor
        let floor = ModelEntity(
            mesh: MeshResource.generatePlane(width: width, depth: depth),
            materials: [floorMaterial]
        )
        floor.position = SIMD3<Float>(0, -height/2, 0)
        roomRoot.addChild(floor)
        
        // Ceiling
        let ceiling = ModelEntity(
            mesh: MeshResource.generatePlane(width: width, depth: depth),
            materials: [ceilingMaterial]
        )
        ceiling.position = SIMD3<Float>(0, height/2, 0)
        ceiling.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        roomRoot.addChild(ceiling)
        
        // Walls
        // North wall (far)
        let northWall = ModelEntity(
            mesh: MeshResource.generatePlane(width: width, depth: height),
            materials: [wallMaterial]
        )
        northWall.position = SIMD3<Float>(0, 0, -depth/2)
        northWall.orientation = simd_quatf(angle: .pi/2, axis: SIMD3<Float>(1, 0, 0))
        roomRoot.addChild(northWall)
        
        // South wall (near)
        let southWall = ModelEntity(
            mesh: MeshResource.generatePlane(width: width, depth: height),
            materials: [wallMaterial]
        )
        southWall.position = SIMD3<Float>(0, 0, depth/2)
        southWall.orientation = simd_quatf(angle: -.pi/2, axis: SIMD3<Float>(1, 0, 0))
        roomRoot.addChild(southWall)
        
        // East wall
        let eastWall = ModelEntity(
            mesh: MeshResource.generatePlane(width: depth, depth: height),
            materials: [wallMaterial]
        )
        eastWall.position = SIMD3<Float>(width/2, 0, 0)
        eastWall.orientation = simd_quatf(angle: .pi/2, axis: SIMD3<Float>(1, 0, 0)) * simd_quatf(angle: -.pi/2, axis: SIMD3<Float>(0, 0, 1))
        roomRoot.addChild(eastWall)
        
        // West wall
        let westWall = ModelEntity(
            mesh: MeshResource.generatePlane(width: depth, depth: height),
            materials: [wallMaterial]
        )
        westWall.position = SIMD3<Float>(-width/2, 0, 0)
        westWall.orientation = simd_quatf(angle: .pi/2, axis: SIMD3<Float>(1, 0, 0)) * simd_quatf(angle: .pi/2, axis: SIMD3<Float>(0, 0, 1))
        roomRoot.addChild(westWall)
        
        // Add grid lines on floor for spatial reference
        addFloorGrid(to: roomRoot, width: width, height: height, depth: depth)
        
        return roomRoot
    }
    
    static func addFloorGrid(to parent: Entity, width: Float, height: Float, depth: Float) {
        var lineMaterial = UnlitMaterial()
        lineMaterial.color = .init(tint: UIColor(white: 0.7, alpha: 0.5))
        
        let gridSpacing: Float = 1.0 // 1 meter grid
        let lineThickness: Float = 0.005
        
        // X lines
        let xCount = Int(width / gridSpacing) + 1
        for i in 0..<xCount {
            let x = -width/2 + Float(i) * gridSpacing
            let line = ModelEntity(
                mesh: MeshResource.generateBox(width: lineThickness, height: 0.001, depth: depth),
                materials: [lineMaterial]
            )
            line.position = SIMD3<Float>(x, -height/2 + 0.001, 0)
            parent.addChild(line)
        }
        
        // Z lines
        let zCount = Int(depth / gridSpacing) + 1
        for i in 0..<zCount {
            let z = -depth/2 + Float(i) * gridSpacing
            let line = ModelEntity(
                mesh: MeshResource.generateBox(width: width, height: 0.001, depth: lineThickness),
                materials: [lineMaterial]
            )
            line.position = SIMD3<Float>(0, -height/2 + 0.001, z)
            parent.addChild(line)
        }
    }
}
