import Foundation
import SwiftUI
import simd

// MARK: - Brush DSL Parser

/// Parses text commands into BrushDefinition modifications
/// 
/// # SYNTAX REFERENCE
///
/// ## Basic Commands (property value):
/// ```
/// size 0.02          # Base brush size in meters (0.002 - 0.05)
/// variation 0.5      # Size variation 0-1 (0 = uniform, 1 = max random)
/// shape sphere       # Shape: sphere, cube, cylinder, cone, ribbon
/// segments 12        # Geometry detail (3-32)
/// aspect 2.0         # Width/height ratio for ribbons
/// ```
///
/// ## Stroke Commands:
/// ```
/// spacing 0.3        # Point spacing (0.05 = dense, 2.0 = sparse)
/// jitter 0.5         # Random position offset 0-1
/// jitterscale 2.0    # Jitter multiplier
/// smoothing 0.8      # Stroke smoothing 0-1
/// pressure 1.5       # Pressure/speed response multiplier
/// anglefollow 1.0    # How much brush rotates with stroke 0-1
/// ```
///
/// ## Color Commands:
/// ```
/// color solid        # Use selected color
/// color gradient     # Gradient along stroke
/// color rainbow      # Hue cycles along stroke
/// color velocity     # Color based on speed
/// color noise        # Perlin noise coloring
/// hueshift 2.0       # Rainbow cycles (for rainbow mode)
/// noisescale 3.0     # Noise frequency (for noise mode)
/// ```
///
/// ## Physics Commands:
/// ```
/// gravity -0.01      # Y gravity (negative = down)
/// gravityx 0.005     # X gravity
/// gravityz 0.005     # Z gravity
/// turbulence 0.5     # Random force amount 0-1
/// turbscale 2.0      # Turbulence noise scale
/// drag 0.3           # Air resistance 0-1
/// attract 0.5        # Attraction to stroke center (-1 to 1)
/// ```
///
/// ## Emission/Particle Commands:
/// ```
/// rate 2.0           # Particles per unit distance
/// burst 3            # Particles per emission
/// spread 0.02        # Burst spread distance
/// trail 5            # Trailing particle count
/// trailfade 0.7      # Trail opacity falloff 0-1
/// lifetime 3.0       # Particle lifetime seconds (0 = permanent)
/// fadein 0.1         # Fade in duration
/// fadeout 0.5        # Fade out duration
/// ```
///
/// ## Preset Commands:
/// ```
/// preset smooth      # Load smooth preset
/// preset sparkle     # Load sparkle preset
/// preset ribbon      # Load ribbon preset
/// preset helix       # Load helix preset
/// preset vine        # Load vine preset
/// preset neon        # Load neon preset
/// reset              # Reset to defaults
/// ```
///
/// ## Compound Commands (multiple on one line):
/// ```
/// size 0.02 jitter 0.5 color rainbow gravity -0.01
/// ```
///
/// ## Math Expressions:
/// ```
/// size +0.005        # Add to current value
/// size -0.005        # Subtract from current
/// size *2            # Multiply current
/// size /2            # Divide current
/// jitter random      # Random value in valid range
/// ```

class BrushDSLParser {
    
    enum ParseError: Error, LocalizedError {
        case unknownCommand(String)
        case invalidValue(command: String, value: String)
        case missingValue(command: String)
        
        var errorDescription: String? {
            switch self {
            case .unknownCommand(let cmd):
                return "Unknown command: '\(cmd)'"
            case .invalidValue(let cmd, let val):
                return "Invalid value '\(val)' for '\(cmd)'"
            case .missingValue(let cmd):
                return "Missing value for '\(cmd)'"
            }
        }
    }
    
    struct ParseResult {
        var preset: BrushDefinition
        var errors: [ParseError]
        var appliedCommands: [String]
    }
    
    // MARK: - Main Parse Function
    
    static func parse(_ input: String, into preset: BrushDefinition) -> ParseResult {
        var result = preset
        var errors: [ParseError] = []
        var applied: [String] = []
        
        // Tokenize: split by whitespace, handle quoted strings later if needed
        let tokens = tokenize(input)
        var i = 0
        
        while i < tokens.count {
            let command = tokens[i].lowercased()
            
            // Commands without values
            if command == "reset" {
                result = BrushDefinition.defaultSmooth
                applied.append("reset")
                i += 1
                continue
            }
            
            // Commands that need a value
            guard i + 1 < tokens.count else {
                errors.append(.missingValue(command: command))
                i += 1
                continue
            }
            
            let value = tokens[i + 1]
            
            do {
                try applyCommand(command, value: value, to: &result)
                applied.append("\(command) \(value)")
            } catch let error as ParseError {
                errors.append(error)
            } catch {
                errors.append(.invalidValue(command: command, value: value))
            }
            
            i += 2
        }
        
        return ParseResult(preset: result, errors: errors, appliedCommands: applied)
    }
    
    // MARK: - Tokenizer
    
    private static func tokenize(_ input: String) -> [String] {
        // Split by whitespace, preserving order
        input.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Command Application
    
    private static func applyCommand(_ command: String, value: String, to preset: inout BrushDefinition) throws {
        
        switch command {
            
        // === GEOMETRY ===
        case "size", "basesize":
            preset.geometry.baseSize = try parseFloat(value, range: 0.002...0.1)
            
        case "variation", "sizevariation", "sizevar":
            preset.geometry.sizeVariation = try parseFloat(value, range: 0...1)
            
        case "shape":
            preset.geometry.shape = try parseShape(value)
            
        case "segments", "seg":
            preset.geometry.segments = try parseInt(value, range: 3...32)
            
        case "aspect", "aspectratio":
            preset.geometry.aspectRatio = try parseFloat(value, range: 0.1...10)
            
        // === STROKE ===
        case "spacing", "space":
            preset.stroke.spacing = try parseFloat(value, range: 0.05...2)
            
        case "jitter", "jit":
            preset.stroke.jitter = try parseFloat(value, range: 0...1)
            
        case "jitterscale", "jitscale":
            preset.stroke.jitterScale = try parseFloat(value, range: 0.1...10)
            
        case "smoothing", "smooth":
            preset.stroke.smoothing = try parseFloat(value, range: 0...1)
            
        case "pressure", "pressureresponse":
            preset.stroke.pressureResponse = try parseFloat(value, range: 0...3)
            
        case "anglefollow", "angle":
            preset.stroke.angleFollow = try parseFloat(value, range: 0...1)
            
        // === COLOR ===
        case "color", "colormode":
            preset.colorMode.mode = try parseColorMode(value)
            
        case "hueshift", "hue":
            preset.colorMode.hueShiftOverStroke = try parseFloat(value, range: 0...10)
            
        case "noisescale":
            preset.colorMode.noiseScale = try parseFloat(value, range: 0.1...20)
            
        case "noisespeed":
            preset.colorMode.noiseSpeed = try parseFloat(value, range: 0...10)
            
        // === PHYSICS ===
        case "gravity", "grav", "gravityy":
            preset.physics.gravity.y = try parseFloat(value, range: -0.05...0.05)
            
        case "gravityx", "gravx":
            preset.physics.gravity.x = try parseFloat(value, range: -0.05...0.05)
            
        case "gravityz", "gravz":
            preset.physics.gravity.z = try parseFloat(value, range: -0.05...0.05)
            
        case "turbulence", "turb":
            preset.physics.turbulence = try parseFloat(value, range: 0...1)
            
        case "turbscale", "turbulencescale":
            preset.physics.turbulenceScale = try parseFloat(value, range: 0.1...20)
            
        case "drag":
            preset.physics.drag = try parseFloat(value, range: 0...1)
            
        case "attract", "attraction":
            preset.physics.attract = try parseFloat(value, range: -1...1)
            
        case "velocityinherit", "velinherit":
            preset.physics.velocityInherit = try parseFloat(value, range: 0...1)
            
        // === EMISSION ===
        case "rate", "emissionrate":
            preset.emission.rate = try parseFloat(value, range: 0.1...20)
            
        case "burst", "burstcount":
            preset.emission.burstCount = try parseInt(value, range: 1...50)
            
        case "spread", "burstspread":
            preset.emission.burstSpread = try parseFloat(value, range: 0...0.2)
            
        case "trail", "traillength":
            preset.emission.trailLength = try parseInt(value, range: 0...30)
            
        case "trailfade":
            preset.emission.trailFade = try parseFloat(value, range: 0...1)
            
        case "lifetime", "life":
            preset.emission.lifetime = try parseFloat(value, range: 0...30)
            
        case "fadein":
            preset.emission.fadeIn = try parseFloat(value, range: 0...5)
            
        case "fadeout":
            preset.emission.fadeOut = try parseFloat(value, range: 0...5)
            
        // === PRESETS ===
        case "preset", "load":
            preset = try loadPreset(value)
            
        default:
            throw ParseError.unknownCommand(command)
        }
    }
    
    // MARK: - Value Parsers
    
    private static func parseFloat(_ value: String, range: ClosedRange<Float>) throws -> Float {
        // Handle "random"
        if value.lowercased() == "random" || value.lowercased() == "rand" {
            return Float.random(in: range)
        }
        
        // Handle math expressions
        if value.hasPrefix("+") || value.hasPrefix("-") || value.hasPrefix("*") || value.hasPrefix("/") {
            // Would need current value context - skip for now, treat as number
        }
        
        guard let num = Float(value) else {
            throw ParseError.invalidValue(command: "float", value: value)
        }
        
        return min(max(num, range.lowerBound), range.upperBound)
    }
    
    private static func parseInt(_ value: String, range: ClosedRange<Int>) throws -> Int {
        if value.lowercased() == "random" || value.lowercased() == "rand" {
            return Int.random(in: range)
        }
        
        guard let num = Int(value) else {
            throw ParseError.invalidValue(command: "int", value: value)
        }
        
        return min(max(num, range.lowerBound), range.upperBound)
    }
    
    private static func parseShape(_ value: String) throws -> ShapeType {
        switch value.lowercased() {
        case "sphere", "ball", "round": return .sphere
        case "cube", "box", "square": return .cube
        case "cylinder", "cyl", "tube": return .cylinder
        case "cone", "point": return .cone
        case "ribbon", "flat", "strip": return .ribbon
        case "custom": return .custom
        default:
            throw ParseError.invalidValue(command: "shape", value: value)
        }
    }
    
    private static func parseColorMode(_ value: String) throws -> ColorModeType {
        switch value.lowercased() {
        case "solid", "flat", "single": return .solid
        case "gradient", "grad", "blend": return .gradient
        case "rainbow", "spectrum", "hue": return .rainbow
        case "velocity", "speed", "vel": return .velocity
        case "noise", "perlin", "random": return .noise
        case "custom": return .custom
        default:
            throw ParseError.invalidValue(command: "color", value: value)
        }
    }
    
    private static func loadPreset(_ value: String) throws -> BrushDefinition {
        switch value.lowercased() {
        case "smooth", "default": return .defaultSmooth
        case "ribbon", "flat": return .defaultRibbon
        case "sparkle", "spark", "glitter": return .defaultSparkle
        case "helix", "spiral", "dna": return .defaultHelix
        case "vine", "organic", "plant": return .defaultVine
        case "neon", "glow", "light": return .defaultNeon
        default:
            throw ParseError.invalidValue(command: "preset", value: value)
        }
    }
}

// MARK: - Help Text Generator

extension BrushDSLParser {
    
    static let helpText = """
    BRUSH DSL COMMANDS
    ══════════════════
    
    GEOMETRY:
      size 0.02         Base size (0.002-0.1)
      variation 0.5     Size randomness (0-1)
      shape sphere      sphere/cube/cylinder/cone/ribbon
      segments 12       Detail level (3-32)
      aspect 2.0        Width/height ratio
    
    STROKE:
      spacing 0.3       Point density (0.05-2)
      jitter 0.5        Position randomness (0-1)
      smoothing 0.8     Smooth strokes (0-1)
      pressure 1.5      Speed response
      anglefollow 1.0   Rotation follow (0-1)
    
    COLOR:
      color solid       solid/gradient/rainbow/velocity/noise
      hueshift 2.0      Rainbow cycles
      noisescale 3.0    Noise frequency
    
    PHYSICS:
      gravity -0.01     Y gravity (down = negative)
      turbulence 0.5    Random forces (0-1)
      drag 0.3          Air resistance (0-1)
      attract 0.5       Pull to center (-1 to 1)
    
    PARTICLES:
      rate 2.0          Emission rate
      burst 3           Particles per point
      trail 5           Trail length
      lifetime 3.0      Seconds (0 = forever)
    
    PRESETS:
      preset sparkle    Load preset
      reset             Reset to default
    
    TIPS:
      • Combine: size 0.02 jitter 0.5 color rainbow
      • Use 'random' for any value: jitter random
    """
}
