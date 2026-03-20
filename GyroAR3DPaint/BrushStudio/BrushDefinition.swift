import SwiftUI
import simd

// MARK: - Brush Definition

struct BrushDefinition: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var category: BrushCategory
    
    // Geometry
    var geometry: GeometryParams
    
    // Stroke behavior
    var stroke: StrokeParams
    
    // Emission / particles
    var emission: EmissionParams
    
    // Color behavior
    var colorMode: ColorMode
    
    // Physics
    var physics: PhysicsParams
    
    // Base brush type to build upon
    var baseBrushType: String // Maps to existing BrushType
    
    static func == (lhs: BrushDefinition, rhs: BrushDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Parameter Groups

struct GeometryParams: Codable, Equatable {
    var baseSize: Float = 0.01          // Base particle/stroke size
    var sizeVariation: Float = 0.0      // Random size variation 0-1
    var sizeOverStroke: [Float] = [1.0] // Size multiplier curve along stroke
    var shape: ShapeType = .sphere
    var aspectRatio: Float = 1.0        // Width/height ratio for ribbons
    var segments: Int = 8               // Geometry detail level
}

enum ShapeType: String, Codable, CaseIterable {
    case sphere = "Sphere"
    case cube = "Cube"
    case cylinder = "Cylinder"
    case cone = "Cone"
    case ribbon = "Ribbon"
    case custom = "Custom"
}

struct StrokeParams: Codable, Equatable {
    var spacing: Float = 0.5            // Distance between points (0=continuous, 1=sparse)
    var jitter: Float = 0.0             // Random position offset
    var jitterScale: Float = 1.0        // Jitter amount multiplier
    var smoothing: Float = 0.5          // Stroke smoothing 0-1
    var pressureResponse: Float = 1.0   // How much size responds to pressure/speed
    var angleFollow: Float = 1.0        // How much brush rotates to follow stroke
    var minSpeed: Float = 0.0           // Minimum drawing speed threshold
    var maxSpeed: Float = 10.0          // Maximum speed for normalization
}

struct EmissionParams: Codable, Equatable {
    var rate: Float = 1.0               // Particles per unit distance
    var burstCount: Int = 1             // Particles per emission event
    var burstSpread: Float = 0.0        // Spread of burst particles
    var trailLength: Int = 0            // Number of trailing particles
    var trailFade: Float = 1.0          // Trail opacity falloff
    var lifetime: Float = 0.0           // Particle lifetime (0=permanent)
    var fadeIn: Float = 0.0             // Fade in duration
    var fadeOut: Float = 0.0            // Fade out duration
}

struct ColorMode: Codable, Equatable {
    var mode: ColorModeType = .solid
    var gradientStops: [GradientStop] = []
    var velocityColorMap: [GradientStop] = []
    var noiseScale: Float = 1.0
    var noiseSpeed: Float = 0.0
    var hueShiftOverStroke: Float = 0.0
    var saturationRange: ClosedRange<Float> = 0.8...1.0
    var brightnessRange: ClosedRange<Float> = 0.8...1.0

    // Live color modulation — added later, must decode with defaults for old presets
    var liveSource:      LiveColorSource = .off
    var liveHueA:        Float = 0.55
    var liveHueB:        Float = 0.0
    var liveSaturation:  Float = 1.0
    var liveBrightness:  Float = 1.0
    var liveThreshold:   Float = 0.1
    var liveRelease:     Float = 0.12

    // Custom decoder: vanhemmat tallennetut presetit eivät sisällä live-kenttiä
    // → puuttuvat kentät saavat oletusarvot eikä kaadu
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode             = try c.decodeIfPresent(ColorModeType.self,      forKey: .mode)             ?? .solid
        gradientStops    = try c.decodeIfPresent([GradientStop].self,     forKey: .gradientStops)    ?? []
        velocityColorMap = try c.decodeIfPresent([GradientStop].self,     forKey: .velocityColorMap) ?? []
        noiseScale       = try c.decodeIfPresent(Float.self,              forKey: .noiseScale)       ?? 1.0
        noiseSpeed       = try c.decodeIfPresent(Float.self,              forKey: .noiseSpeed)       ?? 0.0
        hueShiftOverStroke = try c.decodeIfPresent(Float.self,            forKey: .hueShiftOverStroke) ?? 0.0
        saturationRange  = try c.decodeIfPresent(ClosedRange<Float>.self, forKey: .saturationRange)  ?? 0.8...1.0
        brightnessRange  = try c.decodeIfPresent(ClosedRange<Float>.self, forKey: .brightnessRange)  ?? 0.8...1.0
        liveSource       = try c.decodeIfPresent(LiveColorSource.self,    forKey: .liveSource)       ?? .off
        liveHueA         = try c.decodeIfPresent(Float.self,              forKey: .liveHueA)         ?? 0.55
        liveHueB         = try c.decodeIfPresent(Float.self,              forKey: .liveHueB)         ?? 0.0
        liveSaturation   = try c.decodeIfPresent(Float.self,              forKey: .liveSaturation)   ?? 1.0
        liveBrightness   = try c.decodeIfPresent(Float.self,              forKey: .liveBrightness)   ?? 1.0
        liveThreshold    = try c.decodeIfPresent(Float.self,              forKey: .liveThreshold)    ?? 0.1
        liveRelease      = try c.decodeIfPresent(Float.self,              forKey: .liveRelease)      ?? 0.12
    }

    init() {}

    init(mode: ColorModeType = .solid,
         gradientStops: [GradientStop] = [],
         velocityColorMap: [GradientStop] = [],
         noiseScale: Float = 1.0,
         noiseSpeed: Float = 0.0,
         hueShiftOverStroke: Float = 0.0,
         saturationRange: ClosedRange<Float> = 0.8...1.0,
         brightnessRange: ClosedRange<Float> = 0.8...1.0,
         liveSource: LiveColorSource = .off,
         liveHueA: Float = 0.55,
         liveHueB: Float = 0.0,
         liveSaturation: Float = 1.0,
         liveBrightness: Float = 1.0,
         liveThreshold: Float = 0.1,
         liveRelease: Float = 0.12) {
        self.mode = mode
        self.gradientStops = gradientStops
        self.velocityColorMap = velocityColorMap
        self.noiseScale = noiseScale
        self.noiseSpeed = noiseSpeed
        self.hueShiftOverStroke = hueShiftOverStroke
        self.saturationRange = saturationRange
        self.brightnessRange = brightnessRange
        self.liveSource = liveSource
        self.liveHueA = liveHueA
        self.liveHueB = liveHueB
        self.liveSaturation = liveSaturation
        self.liveBrightness = liveBrightness
        self.liveThreshold = liveThreshold
        self.liveRelease = liveRelease
    }
}

enum LiveColorSource: String, Codable, CaseIterable {
    case off         = "Off"
    case rightStickX = "Xbox Right Stick X"
    case rightStickY = "Xbox Right Stick Y"
    case leftStickX  = "Xbox Left Stick X"
    case leftTrigger = "Xbox LT"
    case rightTrigger = "Xbox RT"
    case micPitch    = "Mic Pitch"
    case micAmplitude = "Mic Amplitude"
}

enum ColorModeType: String, Codable, CaseIterable {
    case solid = "Solid"
    case gradient = "Gradient"
    case velocity = "Velocity"
    case noise = "Noise"
    case rainbow = "Rainbow"
    case custom = "Custom"
}

struct GradientStop: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var position: Float     // 0-1 along stroke
    var hue: Float          // 0-1
    var saturation: Float   // 0-1
    var brightness: Float   // 0-1
    var alpha: Float = 1.0
    
    var color: Color {
        Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
    }
}

struct PhysicsParams: Codable, Equatable {
    var gravity: SIMD3<Float> = .zero   // Gravity vector
    var turbulence: Float = 0.0         // Random force amount
    var turbulenceScale: Float = 1.0    // Noise scale for turbulence
    var drag: Float = 0.0               // Air resistance
    var velocityInherit: Float = 0.0    // How much stroke velocity affects particles
    var bounce: Float = 0.0             // Collision bounce (future)
    var attract: Float = 0.0            // Attraction to stroke center
}

// MARK: - Brush Category

enum BrushCategory: String, Codable, CaseIterable {
    case basic = "Basic"
    case organic = "Organic"
    case geometric = "Geometric"
    case particle = "Particle"
    case texture = "Texture"
    case special = "Special"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .basic: return "circle.fill"
        case .organic: return "leaf.fill"
        case .geometric: return "triangle.fill"
        case .particle: return "sparkle"
        case .texture: return "square.grid.3x3.fill"
        case .special: return "star.fill"
        case .custom: return "paintbrush.fill"
        }
    }
}

// MARK: - Default Presets

extension BrushDefinition {
    
    static let defaultSmooth = BrushDefinition(
        name: "Smooth",
        category: .basic,
        geometry: GeometryParams(baseSize: 0.01, shape: .sphere),
        stroke: StrokeParams(spacing: 0.3, smoothing: 0.8),
        emission: EmissionParams(rate: 1.0),
        colorMode: ColorMode(mode: .solid),
        physics: PhysicsParams(),
        baseBrushType: "smooth"
    )
    
    static let defaultRibbon = BrushDefinition(
        name: "Ribbon",
        category: .basic,
        geometry: GeometryParams(baseSize: 0.015, shape: .ribbon, aspectRatio: 0.1),
        stroke: StrokeParams(spacing: 0.2, smoothing: 0.9, angleFollow: 1.0),
        emission: EmissionParams(rate: 1.0),
        colorMode: ColorMode(mode: .solid),
        physics: PhysicsParams(),
        baseBrushType: "ribbon"
    )
    
    static let defaultSparkle = BrushDefinition(
        name: "Sparkle",
        category: .particle,
        geometry: GeometryParams(baseSize: 0.005, sizeVariation: 0.5, shape: .sphere),
        stroke: StrokeParams(spacing: 0.1, jitter: 0.8, jitterScale: 2.0),
        emission: EmissionParams(rate: 3.0, burstCount: 3, burstSpread: 0.02),
        colorMode: ColorMode(mode: .rainbow, hueShiftOverStroke: 1.0),
        physics: PhysicsParams(turbulence: 0.3),
        baseBrushType: "sparkle"
    )
    
    static let defaultHelix = BrushDefinition(
        name: "Helix",
        category: .geometric,
        geometry: GeometryParams(baseSize: 0.008, shape: .sphere, segments: 12),
        stroke: StrokeParams(spacing: 0.15, smoothing: 0.7, angleFollow: 0.5),
        emission: EmissionParams(rate: 2.0),
        colorMode: ColorMode(mode: .gradient, gradientStops: [
            GradientStop(position: 0, hue: 0.6, saturation: 0.8, brightness: 1.0),
            GradientStop(position: 1, hue: 0.8, saturation: 0.8, brightness: 1.0)
        ]),
        physics: PhysicsParams(),
        baseBrushType: "helix"
    )
    
    static let defaultVine = BrushDefinition(
        name: "Vine",
        category: .organic,
        geometry: GeometryParams(baseSize: 0.006, sizeVariation: 0.3, shape: .cylinder),
        stroke: StrokeParams(spacing: 0.25, jitter: 0.2, smoothing: 0.6),
        emission: EmissionParams(rate: 1.5, trailLength: 2, trailFade: 0.7),
        colorMode: ColorMode(mode: .gradient, gradientStops: [
            GradientStop(position: 0, hue: 0.3, saturation: 0.7, brightness: 0.8),
            GradientStop(position: 1, hue: 0.35, saturation: 0.9, brightness: 0.5)
        ]),
        physics: PhysicsParams(gravity: SIMD3(0, -0.001, 0)),
        baseBrushType: "vine"
    )
    
    static let defaultNeon = BrushDefinition(
        name: "Neon",
        category: .special,
        geometry: GeometryParams(baseSize: 0.012, shape: .sphere),
        stroke: StrokeParams(spacing: 0.2, smoothing: 0.95),
        emission: EmissionParams(rate: 1.0, trailLength: 5, trailFade: 0.5),
        colorMode: ColorMode(
            mode: .solid,
            saturationRange: 1.0...1.0,
            brightnessRange: 1.0...1.0
        ),
        physics: PhysicsParams(),
        baseBrushType: "smooth"
    )
    
    static let allDefaults: [BrushDefinition] = [
        .defaultSmooth,
        .defaultRibbon,
        .defaultSparkle,
        .defaultHelix,
        .defaultVine,
        .defaultNeon
    ]
}

// MARK: - SIMD3 Codable Extension

extension SIMD3: Codable where Scalar: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Scalar.self)
        let y = try container.decode(Scalar.self)
        let z = try container.decode(Scalar.self)
        self.init(x, y, z)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}

// MARK: - ClosedRange Codable Extension

extension ClosedRange: Codable where Bound: Codable {
    enum CodingKeys: String, CodingKey {
        case lowerBound, upperBound
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lower = try container.decode(Bound.self, forKey: .lowerBound)
        let upper = try container.decode(Bound.self, forKey: .upperBound)
        self = lower...upper
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lowerBound, forKey: .lowerBound)
        try container.encode(upperBound, forKey: .upperBound)
    }
}
