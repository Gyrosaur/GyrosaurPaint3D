import Foundation
import JavaScriptCore
import simd

// MARK: - Brush Script Engine

/// JavaScriptCore-based brush scripting engine
/// Allows full JavaScript for brush creation - like Blender's Python
///
/// # USAGE:
/// ```javascript
/// // Set brush properties
/// brush.geometry.baseSize = 0.02;
/// brush.geometry.shape = "sphere";
/// brush.stroke.jitter = 0.5;
/// brush.color.mode = "rainbow";
/// brush.physics.gravity = [0, -0.01, 0];
///
/// // Per-point callback for dynamic effects
/// brush.onPoint = function(ctx) {
///     return {
///         size: 0.01 + Math.sin(ctx.index * 0.2) * 0.005
///     };
/// };
/// ```

@MainActor
class BrushScriptEngine: ObservableObject {
    
    private var context: JSContext!
    @Published var lastError: String?
    @Published var isExecuting = false
    
    // The brush being modified
    @Published var currentBrush: BrushDefinition = .defaultSmooth
    
    // Per-point callback (if defined in script)
    private var onPointCallback: JSValue?
    
    init() {
        setupContext()
    }
    
    // MARK: - Context Setup
    
    private func setupContext() {
        context = JSContext()
        
        // Error handler
        context.exceptionHandler = { [weak self] _, exception in
            Task { @MainActor in
                self?.lastError = exception?.toString() ?? "Unknown error"
            }
        }
        
        // Console.log
        let consoleLog: @convention(block) (String) -> Void = { message in
            print("[BrushScript] \(message)")
        }
        context.setObject(consoleLog, forKeyedSubscript: "print" as NSString)
        
        // Setup brush API
        setupBrushAPI()
        
        // Setup math helpers
        setupMathHelpers()
        
        // Setup color helpers
        setupColorHelpers()
        
        // Setup vector helpers
        setupVectorHelpers()
        
        // Setup presets
        setupPresets()
    }
    
    // MARK: - Brush API
    
    private func setupBrushAPI() {
        // Create nested brush object structure
        let setupScript = """
        var brush = {
            name: "Custom Brush",
            
            geometry: {
                baseSize: 0.01,
                sizeVariation: 0.0,
                shape: "sphere",
                aspectRatio: 1.0,
                segments: 8
            },
            
            stroke: {
                spacing: 0.3,
                jitter: 0.0,
                jitterScale: 1.0,
                smoothing: 0.5,
                pressureResponse: 1.0,
                angleFollow: 0.0
            },
            
            color: {
                mode: "solid",
                hueShift: 1.0,
                noiseScale: 1.0,
                noiseSpeed: 1.0,
                gradient: []
            },
            
            physics: {
                gravity: [0, 0, 0],
                turbulence: 0.0,
                turbulenceScale: 1.0,
                drag: 0.0,
                velocityInherit: 0.0,
                attract: 0.0
            },
            
            emission: {
                rate: 1.0,
                burstCount: 1,
                burstSpread: 0.0,
                trailLength: 0,
                trailFade: 0.5,
                lifetime: 0,
                fadeIn: 0.0,
                fadeOut: 0.0
            },
            
            // Per-point callback
            onPoint: null
        };
        """
        context.evaluateScript(setupScript)
    }
    
    // MARK: - Math Helpers
    
    private func setupMathHelpers() {
        let mathScript = """
        var math = {
            sin: Math.sin,
            cos: Math.cos,
            tan: Math.tan,
            abs: Math.abs,
            sqrt: Math.sqrt,
            pow: Math.pow,
            min: Math.min,
            max: Math.max,
            floor: Math.floor,
            ceil: Math.ceil,
            round: Math.round,
            random: Math.random,
            PI: Math.PI,
            
            // Extra helpers
            lerp: function(a, b, t) { return a + (b - a) * t; },
            clamp: function(x, min, max) { return Math.min(Math.max(x, min), max); },
            map: function(x, inMin, inMax, outMin, outMax) {
                return (x - inMin) / (inMax - inMin) * (outMax - outMin) + outMin;
            },
            smoothstep: function(edge0, edge1, x) {
                var t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1);
                return t * t * (3 - 2 * t);
            },
            noise: function(x) {
                // Simple pseudo-noise
                return Math.sin(x * 12.9898) * 43758.5453 % 1;
            },
            noise2d: function(x, y) {
                return Math.sin(x * 12.9898 + y * 78.233) * 43758.5453 % 1;
            },
            noise3d: function(x, y, z) {
                return Math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453 % 1;
            }
        };
        """
        context.evaluateScript(mathScript)
    }
    
    // MARK: - Color Helpers
    
    private func setupColorHelpers() {
        let colorScript = """
        var color = {
            // HSL to object
            hsl: function(h, s, l) {
                return { h: h, s: s, l: l, a: 1.0 };
            },
            hsla: function(h, s, l, a) {
                return { h: h, s: s, l: l, a: a };
            },
            
            // RGB (0-1 range)
            rgb: function(r, g, b) {
                return { r: r, g: g, b: b, a: 1.0 };
            },
            rgba: function(r, g, b, a) {
                return { r: r, g: g, b: b, a: a };
            },
            
            // Gradient stop helper
            stop: function(position, h, s, b, a) {
                return { pos: position, h: h || 0, s: s || 1, b: b || 1, a: a || 1 };
            },
            
            // Interpolate colors
            mix: function(c1, c2, t) {
                if (c1.h !== undefined) {
                    return {
                        h: math.lerp(c1.h, c2.h, t),
                        s: math.lerp(c1.s, c2.s, t),
                        l: math.lerp(c1.l, c2.l, t),
                        a: math.lerp(c1.a || 1, c2.a || 1, t)
                    };
                }
                return {
                    r: math.lerp(c1.r, c2.r, t),
                    g: math.lerp(c1.g, c2.g, t),
                    b: math.lerp(c1.b, c2.b, t),
                    a: math.lerp(c1.a || 1, c2.a || 1, t)
                };
            }
        };
        """
        context.evaluateScript(colorScript)
    }
    
    // MARK: - Vector Helpers
    
    private func setupVectorHelpers() {
        let vecScript = """
        function vec3(x, y, z) {
            return [x || 0, y || 0, z || 0];
        }
        
        var vec = {
            add: function(a, b) { return [a[0]+b[0], a[1]+b[1], a[2]+b[2]]; },
            sub: function(a, b) { return [a[0]-b[0], a[1]-b[1], a[2]-b[2]]; },
            mul: function(a, s) { return [a[0]*s, a[1]*s, a[2]*s]; },
            div: function(a, s) { return [a[0]/s, a[1]/s, a[2]/s]; },
            dot: function(a, b) { return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]; },
            cross: function(a, b) {
                return [
                    a[1]*b[2] - a[2]*b[1],
                    a[2]*b[0] - a[0]*b[2],
                    a[0]*b[1] - a[1]*b[0]
                ];
            },
            length: function(a) { return Math.sqrt(a[0]*a[0] + a[1]*a[1] + a[2]*a[2]); },
            normalize: function(a) {
                var len = vec.length(a);
                return len > 0 ? vec.div(a, len) : [0,0,0];
            },
            lerp: function(a, b, t) {
                return [
                    math.lerp(a[0], b[0], t),
                    math.lerp(a[1], b[1], t),
                    math.lerp(a[2], b[2], t)
                ];
            },
            distance: function(a, b) {
                return vec.length(vec.sub(a, b));
            }
        };
        """
        context.evaluateScript(vecScript)
    }
    
    // MARK: - Presets
    
    private func setupPresets() {
        let presetsScript = """
        var presets = {
            smooth: function() {
                brush.geometry.baseSize = 0.01;
                brush.geometry.shape = "sphere";
                brush.stroke.smoothing = 0.8;
                brush.color.mode = "solid";
            },
            sparkle: function() {
                brush.geometry.baseSize = 0.008;
                brush.geometry.sizeVariation = 0.5;
                brush.emission.burstCount = 3;
                brush.emission.burstSpread = 0.02;
                brush.color.mode = "rainbow";
                brush.color.hueShift = 2.0;
            },
            ribbon: function() {
                brush.geometry.baseSize = 0.015;
                brush.geometry.shape = "ribbon";
                brush.geometry.aspectRatio = 5.0;
                brush.stroke.smoothing = 0.9;
            },
            helix: function() {
                brush.geometry.baseSize = 0.008;
                brush.stroke.jitter = 0.3;
                brush.physics.turbulence = 0.4;
            },
            neon: function() {
                brush.geometry.baseSize = 0.006;
                brush.color.mode = "solid";
                brush.emission.trailLength = 5;
                brush.emission.trailFade = 0.8;
            },
            rain: function() {
                brush.geometry.baseSize = 0.005;
                brush.physics.gravity = [0, -0.02, 0];
                brush.physics.drag = 0.1;
                brush.emission.burstCount = 5;
            }
        };
        
        // Load preset helper
        function loadPreset(name) {
            if (presets[name]) {
                presets[name]();
            }
        }
        """
        context.evaluateScript(presetsScript)
    }
    
    // MARK: - Script Execution
    
    func execute(_ script: String) -> Result<BrushDefinition, ScriptError> {
        lastError = nil
        isExecuting = true
        defer { isExecuting = false }
        
        // Reset brush to defaults before running script
        setupBrushAPI()
        
        // Execute user script
        context.evaluateScript(script)
        
        // Check for errors
        if let error = lastError {
            return .failure(.executionError(error))
        }
        
        // Extract brush values from JS context
        guard let brushObj = context.objectForKeyedSubscript("brush") else {
            return .failure(.executionError("brush object not found"))
        }
        
        do {
            let brush = try extractBrush(from: brushObj)
            currentBrush = brush
            
            // Store onPoint callback if defined
            if let onPoint = brushObj.objectForKeyedSubscript("onPoint"), !onPoint.isUndefined && !onPoint.isNull {
                onPointCallback = onPoint
            } else {
                onPointCallback = nil
            }
            
            return .success(brush)
        } catch {
            return .failure(.extractionError(error.localizedDescription))
        }
    }
    
    // MARK: - Extract Brush from JS
    
    private func extractBrush(from jsObj: JSValue) throws -> BrushDefinition {
        var brush = BrushDefinition.defaultSmooth
        
        // Name
        if let name = jsObj.objectForKeyedSubscript("name")?.toString(), name != "undefined" {
            brush.name = name
        }
        
        // Geometry
        if let geo = jsObj.objectForKeyedSubscript("geometry") {
            brush.geometry.baseSize = geo.objectForKeyedSubscript("baseSize")?.toFloat() ?? 0.01
            brush.geometry.sizeVariation = geo.objectForKeyedSubscript("sizeVariation")?.toFloat() ?? 0
            brush.geometry.aspectRatio = geo.objectForKeyedSubscript("aspectRatio")?.toFloat() ?? 1
            brush.geometry.segments = Int(geo.objectForKeyedSubscript("segments")?.toInt32() ?? 8)
            
            if let shapeStr = geo.objectForKeyedSubscript("shape")?.toString() {
                brush.geometry.shape = ShapeType(rawValue: shapeStr) ?? .sphere
            }
        }
        
        // Stroke
        if let stroke = jsObj.objectForKeyedSubscript("stroke") {
            brush.stroke.spacing = stroke.objectForKeyedSubscript("spacing")?.toFloat() ?? 0.3
            brush.stroke.jitter = stroke.objectForKeyedSubscript("jitter")?.toFloat() ?? 0
            brush.stroke.jitterScale = stroke.objectForKeyedSubscript("jitterScale")?.toFloat() ?? 1
            brush.stroke.smoothing = stroke.objectForKeyedSubscript("smoothing")?.toFloat() ?? 0.5
            brush.stroke.pressureResponse = stroke.objectForKeyedSubscript("pressureResponse")?.toFloat() ?? 1
            brush.stroke.angleFollow = stroke.objectForKeyedSubscript("angleFollow")?.toFloat() ?? 0
        }
        
        // Color
        if let col = jsObj.objectForKeyedSubscript("color") {
            if let modeStr = col.objectForKeyedSubscript("mode")?.toString() {
                brush.colorMode.mode = ColorModeType(rawValue: modeStr) ?? .solid
            }
            brush.colorMode.hueShiftOverStroke = col.objectForKeyedSubscript("hueShift")?.toFloat() ?? 1
            brush.colorMode.noiseScale = col.objectForKeyedSubscript("noiseScale")?.toFloat() ?? 1
            brush.colorMode.noiseSpeed = col.objectForKeyedSubscript("noiseSpeed")?.toFloat() ?? 1
            
            // Gradient stops
            if let gradArr = col.objectForKeyedSubscript("gradient"), gradArr.isArray {
                var stops: [GradientStop] = []
                let length = gradArr.objectForKeyedSubscript("length")?.toInt32() ?? 0
                for i in 0..<length {
                    if let stop = gradArr.objectAtIndexedSubscript(Int(i)) {
                        let gs = GradientStop(
                            position: stop.objectForKeyedSubscript("pos")?.toFloat() ?? 0,
                            hue: stop.objectForKeyedSubscript("h")?.toFloat() ?? 0,
                            saturation: stop.objectForKeyedSubscript("s")?.toFloat() ?? 1,
                            brightness: stop.objectForKeyedSubscript("b")?.toFloat() ?? 1,
                            alpha: stop.objectForKeyedSubscript("a")?.toFloat() ?? 1
                        )
                        stops.append(gs)
                    }
                }
                if !stops.isEmpty {
                    brush.colorMode.gradientStops = stops
                }
            }
        }
        
        // Physics
        if let phys = jsObj.objectForKeyedSubscript("physics") {
            if let gravArr = phys.objectForKeyedSubscript("gravity"), gravArr.isArray {
                let gx = gravArr.objectAtIndexedSubscript(0)?.toFloat() ?? 0
                let gy = gravArr.objectAtIndexedSubscript(1)?.toFloat() ?? 0
                let gz = gravArr.objectAtIndexedSubscript(2)?.toFloat() ?? 0
                brush.physics.gravity = SIMD3<Float>(gx, gy, gz)
            }
            brush.physics.turbulence = phys.objectForKeyedSubscript("turbulence")?.toFloat() ?? 0
            brush.physics.turbulenceScale = phys.objectForKeyedSubscript("turbulenceScale")?.toFloat() ?? 1
            brush.physics.drag = phys.objectForKeyedSubscript("drag")?.toFloat() ?? 0
            brush.physics.velocityInherit = phys.objectForKeyedSubscript("velocityInherit")?.toFloat() ?? 0
            brush.physics.attract = phys.objectForKeyedSubscript("attract")?.toFloat() ?? 0
        }
        
        // Emission
        if let emit = jsObj.objectForKeyedSubscript("emission") {
            brush.emission.rate = emit.objectForKeyedSubscript("rate")?.toFloat() ?? 1
            brush.emission.burstCount = Int(emit.objectForKeyedSubscript("burstCount")?.toInt32() ?? 1)
            brush.emission.burstSpread = emit.objectForKeyedSubscript("burstSpread")?.toFloat() ?? 0
            brush.emission.trailLength = Int(emit.objectForKeyedSubscript("trailLength")?.toInt32() ?? 0)
            brush.emission.trailFade = emit.objectForKeyedSubscript("trailFade")?.toFloat() ?? 0.5
            brush.emission.lifetime = emit.objectForKeyedSubscript("lifetime")?.toFloat() ?? 0
            brush.emission.fadeIn = emit.objectForKeyedSubscript("fadeIn")?.toFloat() ?? 0
            brush.emission.fadeOut = emit.objectForKeyedSubscript("fadeOut")?.toFloat() ?? 0
        }
        
        return brush
    }
    
    // MARK: - Per-Point Evaluation
    
    /// Call from renderer for per-point dynamic effects
    func evaluatePoint(index: Int, position: SIMD3<Float>, velocity: SIMD3<Float>, time: Float) -> PointModification? {
        guard let callback = onPointCallback, callback.isObject else { return nil }
        
        // Create context object
        let ctxScript = """
        var __ctx = {
            index: \(index),
            position: [\(position.x), \(position.y), \(position.z)],
            velocity: [\(velocity.x), \(velocity.y), \(velocity.z)],
            time: \(time)
        };
        """
        context.evaluateScript(ctxScript)
        
        // Call the callback
        guard let ctx = context.objectForKeyedSubscript("__ctx") else { return nil }
        let result = callback.call(withArguments: [ctx])
        
        guard let res = result, !res.isUndefined && !res.isNull else { return nil }
        
        // Extract modifications
        var mod = PointModification()
        
        if let size = res.objectForKeyedSubscript("size"), !size.isUndefined {
            mod.size = size.toFloat()
        }
        if let hue = res.objectForKeyedSubscript("hue"), !hue.isUndefined {
            mod.hue = hue.toFloat()
        }
        if let sat = res.objectForKeyedSubscript("saturation"), !sat.isUndefined {
            mod.saturation = sat.toFloat()
        }
        if let bright = res.objectForKeyedSubscript("brightness"), !bright.isUndefined {
            mod.brightness = bright.toFloat()
        }
        if let alpha = res.objectForKeyedSubscript("alpha"), !alpha.isUndefined {
            mod.alpha = alpha.toFloat()
        }
        if let offset = res.objectForKeyedSubscript("offset"), offset.isArray {
            let ox = offset.objectAtIndexedSubscript(0)?.toFloat() ?? 0
            let oy = offset.objectAtIndexedSubscript(1)?.toFloat() ?? 0
            let oz = offset.objectAtIndexedSubscript(2)?.toFloat() ?? 0
            mod.offset = SIMD3<Float>(ox, oy, oz)
        }
        
        return mod
    }
    
    // MARK: - Types
    
    enum ScriptError: Error, LocalizedError {
        case executionError(String)
        case extractionError(String)
        
        var errorDescription: String? {
            switch self {
            case .executionError(let msg): return "Script error: \(msg)"
            case .extractionError(let msg): return "Extraction error: \(msg)"
            }
        }
    }
    
    struct PointModification {
        var size: Float?
        var hue: Float?
        var saturation: Float?
        var brightness: Float?
        var alpha: Float?
        var offset: SIMD3<Float>?
    }
}

// MARK: - JSValue Extensions

extension JSValue {
    func toFloat() -> Float {
        return Float(self.toDouble())
    }
}
