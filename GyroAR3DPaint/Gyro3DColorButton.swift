import SwiftUI
import SceneKit
import CoreMotion

// MARK: - 3D Color Button with Gyroscope Response
struct Gyro3DColorButton: View {
    let color: Color
    let isSelected: Bool
    let size: CGFloat
    let action: () -> Void
    
    @StateObject private var motionManager = ButtonMotionManager()
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // SceneKit 3D sphere
                SceneKitSphereView(
                    color: UIColor(color),
                    pitch: motionManager.pitch,
                    roll: motionManager.roll,
                    size: size
                )
                .frame(width: size, height: size)
                
                // Selection ring
                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2.5)
                        .frame(width: size + 4, height: size + 4)
                    Circle()
                        .stroke(Color.black.opacity(0.4), lineWidth: 1)
                        .frame(width: size + 8, height: size + 8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear { motionManager.startUpdates() }
        .onDisappear { motionManager.stopUpdates() }
    }
}

// MARK: - Shared Motion Manager (singleton for all buttons)
@MainActor
class ButtonMotionManager: ObservableObject {
    static let shared = ButtonMotionManager()
    
    @Published var pitch: Float = 0
    @Published var roll: Float = 0
    
    private var motionManager: CMMotionManager?
    private var updateTimer: Timer?
    private var refCount = 0
    
    func startUpdates() {
        refCount += 1
        guard refCount == 1 else { return }
        
        motionManager = CMMotionManager()
        guard let mm = motionManager, mm.isDeviceMotionAvailable else { return }
        
        mm.deviceMotionUpdateInterval = 1.0 / 30.0
        mm.startDeviceMotionUpdates()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let motion = mm.deviceMotion else { return }
                let smoothing: Float = 0.15
                self?.pitch += smoothing * (Float(motion.attitude.pitch) - (self?.pitch ?? 0))
                self?.roll += smoothing * (Float(motion.attitude.roll) - (self?.roll ?? 0))
            }
        }
    }
    
    func stopUpdates() {
        refCount -= 1
        guard refCount == 0 else { return }
        
        updateTimer?.invalidate()
        updateTimer = nil
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
    }
}

// MARK: - SceneKit Sphere View
struct SceneKitSphereView: UIViewRepresentable {
    let color: UIColor
    let pitch: Float
    let roll: Float
    let size: CGFloat
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling2X
        scnView.isUserInteractionEnabled = false
        scnView.preferredFramesPerSecond = 30
        
        let scene = SCNScene()
        scnView.scene = scene
        
        // Sphere
        let sphere = SCNSphere(radius: 0.5)
        sphere.segmentCount = 32
        
        // Shiny material
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.specular.contents = UIColor.white
        material.shininess = 0.85
        material.reflective.contents = UIColor.white.withAlphaComponent(0.1)
        material.fresnelExponent = 1.8
        material.lightingModel = .blinn
        sphere.materials = [material]
        
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.name = "sphere"
        scene.rootNode.addChildNode(sphereNode)
        
        // Main light
        let light = SCNLight()
        light.type = .directional
        light.intensity = 1200
        light.color = UIColor.white
        
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.name = "mainLight"
        lightNode.position = SCNVector3(0.5, 1, 1)
        lightNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(lightNode)
        
        // Ambient
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 250
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        
        // Camera
        let camera = SCNCamera()
        camera.fieldOfView = 45
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 2)
        scene.rootNode.addChildNode(cameraNode)
        
        return scnView
    }
    
    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let scene = scnView.scene,
              let lightNode = scene.rootNode.childNode(withName: "mainLight", recursively: false) else { return }
        
        // Light follows gyroscope
        let d: Float = 1.5
        let x = sin(roll) * d
        let y = cos(pitch) * d * 0.5 + 0.5
        let z = cos(roll) * d
        
        lightNode.position = SCNVector3(x, y, z)
        lightNode.look(at: SCNVector3(0, 0, 0))
        
        // Update color
        if let sphereNode = scene.rootNode.childNode(withName: "sphere", recursively: false),
           let geometry = sphereNode.geometry as? SCNSphere,
           let material = geometry.materials.first {
            material.diffuse.contents = color
        }
    }
}
