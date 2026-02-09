import SwiftUI
import RealityKit
import Combine

// MARK: - Brush Studio Mode (Standalone)

struct BrushStudioMode: View {
    @ObservedObject var presetManager: BrushPresetManager
    @EnvironmentObject var performanceManager: PerformanceManager
    @StateObject private var scriptEngine = BrushScriptEngine()
    
    var onExit: () -> Void
    
    @State private var selectedTab: StudioSection = .presets
    @State private var showingSaveDialog = false
    @State private var newPresetName = ""
    @State private var isCompiling = false
    @State private var compilationProgress: Float = 0
    @State private var showExamples = false
    @State private var showScriptEditor = false
    
    // Script editor
    @State private var scriptCode = """
// Brush Script - JavaScript
// GPT/Claude can generate this for you!

brush.name = "My Custom Brush";

// Geometry
brush.geometry.baseSize = 0.015;
brush.geometry.shape = "sphere";
brush.geometry.sizeVariation = 0.2;

// Stroke behavior  
brush.stroke.spacing = 0.3;
brush.stroke.jitter = 0.1;
brush.stroke.smoothing = 0.7;

// Color - try: solid, gradient, rainbow, velocity, noise
brush.color.mode = "rainbow";
brush.color.hueShift = 2.0;

// Physics
brush.physics.gravity = [0, -0.005, 0];
brush.physics.turbulence = 0.3;

// Particles
brush.emission.burstCount = 2;
brush.emission.trailLength = 3;
"""
    @State private var scriptError: String? = nil
    @State private var scriptSuccess: String? = nil
    
    enum StudioSection: String, CaseIterable {
        case presets = "Presets"
        case geometry = "Shape"
        case stroke = "Stroke"
        case color = "Color"
        case physics = "Physics"
        case emission = "Particles"
    }
    
    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            
            VStack(spacing: 0) {
                leftPanel
            }
            
            if isCompiling {
                compilationOverlay
            }
            
            if showExamples {
                examplesOverlay
            }
            
            if showScriptEditor {
                scriptEditorOverlay
            }
        }
        .alert("Save Preset", isPresented: $showingSaveDialog) {
            TextField("Name", text: $newPresetName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                presetManager.saveAsNewPreset(name: newPresetName)
            }
        }
    }
    
    // MARK: - Left Panel
    var leftPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onExit) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Exit")
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Text("Brush Studio")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showScriptEditor = true }) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(.orange)
                }
                
                Button(action: { showingSaveDialog = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color.white.opacity(0.05))
            
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(StudioSection.allCases, id: \.self) { section in
                        StudioTabButton(
                            title: section.rawValue,
                            icon: sectionIcon(section),
                            isSelected: selectedTab == section
                        ) {
                            selectedTab = section
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color.white.opacity(0.03))
            
            // Content
            ScrollView {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .presets:
                        PresetsPanel(presetManager: presetManager)
                    case .geometry:
                        GeometryPanel(geometry: $presetManager.currentPreset.geometry)
                    case .stroke:
                        StrokePanel(stroke: $presetManager.currentPreset.stroke)
                    case .color:
                        ColorPanel(colorMode: $presetManager.currentPreset.colorMode)
                    case .physics:
                        PhysicsPanel(physics: $presetManager.currentPreset.physics)
                    case .emission:
                        EmissionPanel(emission: $presetManager.currentPreset.emission)
                    }
                }
                .padding()
            }
            
            // Bottom controls
            HStack(spacing: 12) {
                Button(action: { presetManager.resetToDefaults() }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Text(presetManager.currentPreset.name)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Button(action: {
                    newPresetName = presetManager.currentPreset.name + " Custom"
                    showingSaveDialog = true
                }) {
                    Label("Save As", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
    
    // MARK: - Script Editor Panel (used in overlay)
    func runScript() {
        scriptError = nil
        scriptSuccess = nil
        
        let result = scriptEngine.execute(scriptCode)
        
        switch result {
        case .success(let brush):
            presetManager.currentPreset = brush
            scriptSuccess = "✓ Applied: \(brush.name)"
        case .failure(let error):
            scriptError = error.localizedDescription
        }
    }
    
    // MARK: - Script Editor Overlay
    var scriptEditorOverlay: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
                .onTapGesture { showScriptEditor = false }
            
            VStack(spacing: 0) {
                HStack {
                    Text("Script Editor")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { showExamples = true }) {
                        Label("Examples", systemImage: "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: runScript) {
                        Label("Run", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button(action: { showScriptEditor = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                
                TextEditor(text: $scriptCode)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.green)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                if let error = scriptError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .padding(.horizontal)
                } else if let success = scriptSuccess {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(success)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(8)
                    .padding(.horizontal)
                }
                
                Text("brush.geometry / brush.stroke / brush.color / brush.physics / brush.emission")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.bottom, 12)
            }
            .background(Color(white: 0.12))
            .cornerRadius(16)
            .padding(24)
        }
    }
    
    // MARK: - Examples Overlay
    var examplesOverlay: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
                .onTapGesture { showExamples = false }
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Example Scripts")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { showExamples = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                
                ExampleButton(title: "Rainbow Helix") {
                    scriptCode = Self.exampleRainbowHelix
                    showExamples = false
                }
                ExampleButton(title: "Pulsing") {
                    scriptCode = Self.examplePulsing
                    showExamples = false
                }
                ExampleButton(title: "Rain") {
                    scriptCode = Self.exampleRain
                    showExamples = false
                }
                ExampleButton(title: "Noise Scatter") {
                    scriptCode = Self.exampleNoise
                    showExamples = false
                }
            }
            .padding(20)
            .background(Color(white: 0.12))
            .cornerRadius(16)
            .padding(40)
        }
    }
    
    // MARK: - Compilation Overlay
    var compilationOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView(value: compilationProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                Text("Compiling...")
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Color(white: 0.15))
            .cornerRadius(16)
        }
    }
    
    func sectionIcon(_ section: StudioSection) -> String {
        switch section {
        case .presets: return "square.grid.2x2"
        case .geometry: return "cube"
        case .stroke: return "scribble"
        case .color: return "paintpalette"
        case .physics: return "atom"
        case .emission: return "sparkles"
        }
    }
    
    // MARK: - Example Scripts
    static let exampleRainbowHelix = """
brush.name = "Rainbow Helix";
brush.geometry.baseSize = 0.01;
brush.stroke.jitter = 0.15;
brush.color.mode = "rainbow";
brush.color.hueShift = 3.0;
brush.physics.gravity = [0, -0.005, 0];

brush.onPoint = function(ctx) {
    var angle = ctx.index * 0.3;
    return {
        offset: [Math.cos(angle) * 0.02, 0, Math.sin(angle) * 0.02]
    };
};
"""
    
    static let examplePulsing = """
brush.name = "Pulsing";
brush.geometry.baseSize = 0.015;
brush.color.mode = "solid";

brush.onPoint = function(ctx) {
    return {
        size: 0.01 + 0.01 * Math.sin(ctx.index * 0.5)
    };
};
"""
    
    static let exampleRain = """
brush.name = "Rain";
brush.geometry.baseSize = 0.005;
brush.geometry.sizeVariation = 0.3;
brush.physics.gravity = [0, -0.02, 0];
brush.physics.drag = 0.1;
brush.emission.burstCount = 5;
brush.emission.burstSpread = 0.03;
"""
    
    static let exampleNoise = """
brush.name = "Noise Scatter";
brush.geometry.baseSize = 0.008;
brush.color.mode = "noise";
brush.color.noiseScale = 5.0;

brush.onPoint = function(ctx) {
    var n = math.noise3d(ctx.position[0]*10, ctx.position[1]*10, ctx.position[2]*10);
    return { offset: [n*0.02, n*0.015, n*0.02] };
};
"""
}

// MARK: - Helper Views

struct StudioTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundColor(isSelected ? .white : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.3) : Color.clear)
            .cornerRadius(8)
        }
    }
}

struct ExampleButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
