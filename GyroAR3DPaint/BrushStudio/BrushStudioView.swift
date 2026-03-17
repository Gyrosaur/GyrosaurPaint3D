import SwiftUI

struct BrushStudioView: View {
    @ObservedObject var presetManager: BrushPresetManager
    @Environment(\.dismiss) var dismiss
    
    // Callbacks for integration
    var onApply: ((BrushDefinition) -> Void)?
    var onDismiss: (() -> Void)?
    
    @State private var selectedTab: StudioTab = .presets
    @State private var showingSaveDialog = false
    @State private var newPresetName = ""
    @State private var editingPreset: BrushDefinition?
    
    enum StudioTab: String, CaseIterable {
        case presets = "Presets"
        case geometry = "Geometry"
        case stroke = "Stroke"
        case emission = "Emission"
        case color = "Color"
        case physics = "Physics"
    }
    
    // Convenience initializer without callbacks
    init(presetManager: BrushPresetManager) {
        self.presetManager = presetManager
        self.onApply = nil
        self.onDismiss = nil
    }
    
    // Full initializer with callbacks
    init(presetManager: BrushPresetManager, onApply: ((BrushDefinition) -> Void)?, onDismiss: (() -> Void)?) {
        self.presetManager = presetManager
        self.onApply = onApply
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(StudioTab.allCases, id: \.self) { tab in
                            TabButton(title: tab.rawValue, isSelected: selectedTab == tab) {
                                selectedTab = tab
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                
                Divider()
                
                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .presets:
                            PresetsTab(presetManager: presetManager)
                        case .geometry:
                            GeometryTab(geometry: $presetManager.currentPreset.geometry)
                        case .stroke:
                            StrokeTab(stroke: $presetManager.currentPreset.stroke)
                        case .emission:
                            EmissionTab(emission: $presetManager.currentPreset.emission)
                        case .color:
                            ColorTab(colorMode: $presetManager.currentPreset.colorMode)
                        case .physics:
                            PhysicsTab(physics: $presetManager.currentPreset.physics)
                        }
                    }
                    .padding()
                }
                
                // Preview & Actions
                VStack(spacing: 12) {
                    BrushPreviewView(preset: presetManager.currentPreset)
                        .frame(height: 80)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(12)
                    
                    HStack(spacing: 12) {
                        Button("Reset") {
                            presetManager.resetToDefaults()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Save As...") {
                            newPresetName = presetManager.currentPreset.name + " Custom"
                            showingSaveDialog = true
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Apply") {
                            if let onApply = onApply {
                                onApply(presetManager.currentPreset)
                            } else {
                                dismiss()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
            }
            .navigationTitle("Brush Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if let onDismiss = onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    }
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
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .gray)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.clear)
                .cornerRadius(20)
        }
    }
}

// MARK: - Presets Tab

struct PresetsTab: View {
    @ObservedObject var presetManager: BrushPresetManager
    @State private var selectedCategory: BrushCategory = .basic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Category picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BrushCategory.allCases, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }
            
            // Preset grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(presetManager.presets(for: selectedCategory)) { preset in
                    PresetCard(
                        preset: preset,
                        isSelected: presetManager.currentPreset.id == preset.id
                    ) {
                        presetManager.selectPreset(preset)
                    }
                }
            }
        }
    }
}

struct CategoryChip: View {
    let category: BrushCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 12))
                Text(category.rawValue)
                    .font(.system(size: 13))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .cornerRadius(16)
        }
    }
}

struct PresetCard: View {
    let preset: BrushDefinition
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Mini preview
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.6))
                    .frame(height: 60)
                    .overlay(
                        Image(systemName: preset.category.icon)
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.5))
                    )
                
                Text(preset.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(8)
            .background(isSelected ? Color.blue.opacity(0.2) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Geometry Tab

struct GeometryTab: View {
    @Binding var geometry: GeometryParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Shape", icon: "cube.fill")
            
            Picker("Shape", selection: $geometry.shape) {
                ForEach(ShapeType.allCases, id: \.self) { shape in
                    Text(shape.rawValue).tag(shape)
                }
            }
            .pickerStyle(.segmented)
            
            ParameterSlider(
                title: "Base Size",
                value: $geometry.baseSize,
                range: 0.002...0.05,
                format: "%.3f m"
            )
            
            ParameterSlider(
                title: "Size Variation",
                value: $geometry.sizeVariation,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            ParameterSlider(
                title: "Aspect Ratio",
                value: $geometry.aspectRatio,
                range: 0.1...10,
                format: "%.1f"
            )
            
            Stepper("Segments: \(geometry.segments)", value: $geometry.segments, in: 3...32)
        }
    }
}

// MARK: - Stroke Tab

struct StrokeTab: View {
    @Binding var stroke: StrokeParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Stroke Behavior", icon: "scribble")
            
            ParameterSlider(
                title: "Spacing",
                value: $stroke.spacing,
                range: 0.05...2,
                format: "%.2f"
            )
            
            ParameterSlider(
                title: "Smoothing",
                value: $stroke.smoothing,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            SectionHeader(title: "Jitter", icon: "waveform.path.ecg")
            
            ParameterSlider(
                title: "Jitter Amount",
                value: $stroke.jitter,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            ParameterSlider(
                title: "Jitter Scale",
                value: $stroke.jitterScale,
                range: 0.1...5,
                format: "%.1f×"
            )
            
            SectionHeader(title: "Response", icon: "hand.draw.fill")
            
            ParameterSlider(
                title: "Pressure Response",
                value: $stroke.pressureResponse,
                range: 0...2,
                format: "%.1f×"
            )
            
            ParameterSlider(
                title: "Angle Follow",
                value: $stroke.angleFollow,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
        }
    }
}

// MARK: - Emission Tab

struct EmissionTab: View {
    @Binding var emission: EmissionParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Emission Rate", icon: "sparkles")
            
            ParameterSlider(
                title: "Rate",
                value: $emission.rate,
                range: 0.1...10,
                format: "%.1f/unit"
            )
            
            Stepper("Burst Count: \(emission.burstCount)", value: $emission.burstCount, in: 1...20)
            
            ParameterSlider(
                title: "Burst Spread",
                value: $emission.burstSpread,
                range: 0...0.1,
                format: "%.3f m"
            )
            
            SectionHeader(title: "Trail", icon: "wind")
            
            Stepper("Trail Length: \(emission.trailLength)", value: $emission.trailLength, in: 0...20)
            
            ParameterSlider(
                title: "Trail Fade",
                value: $emission.trailFade,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            SectionHeader(title: "Lifetime", icon: "timer")
            
            ParameterSlider(
                title: "Lifetime",
                value: $emission.lifetime,
                range: 0...10,
                format: emission.lifetime == 0 ? "Permanent" : "%.1f s"
            )
            
            ParameterSlider(
                title: "Fade In",
                value: $emission.fadeIn,
                range: 0...2,
                format: "%.2f s"
            )
            
            ParameterSlider(
                title: "Fade Out",
                value: $emission.fadeOut,
                range: 0...2,
                format: "%.2f s"
            )
        }
    }
}

// MARK: - Color Tab

struct ColorTab: View {
    @Binding var colorMode: ColorMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Color Mode", icon: "paintpalette.fill")
            
            Picker("Mode", selection: $colorMode.mode) {
                ForEach(ColorModeType.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            switch colorMode.mode {
            case .gradient:
                GradientEditor(stops: $colorMode.gradientStops)
            case .rainbow:
                ParameterSlider(
                    title: "Hue Shift",
                    value: $colorMode.hueShiftOverStroke,
                    range: 0...3,
                    format: "%.1f cycles"
                )
            case .noise:
                ParameterSlider(
                    title: "Noise Scale",
                    value: $colorMode.noiseScale,
                    range: 0.1...10,
                    format: "%.1f"
                )
                ParameterSlider(
                    title: "Noise Speed",
                    value: $colorMode.noiseSpeed,
                    range: 0...5,
                    format: "%.1f"
                )
            default:
                EmptyView()
            }

            // MARK: - Live Color Modulation
            Divider().background(Color.white.opacity(0.15)).padding(.vertical, 4)
            SectionHeader(title: "Live Color (Input)", icon: "waveform.path.ecg")
            Text("Ohjaa väriä A→B piirron aikana. Käytä Tentacle-presetillä.")
                .font(.caption).foregroundColor(.secondary)

            Picker("Source", selection: $colorMode.liveSource) {
                ForEach(LiveColorSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)

            if colorMode.liveSource != .off {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Color A").font(.caption).foregroundColor(.secondary)
                        ColorPicker("", selection: Binding(
                            get: { Color(hue: Double(colorMode.liveHueA), saturation: Double(colorMode.liveSaturation), brightness: Double(colorMode.liveBrightness)) },
                            set: { c in
                                var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
                                UIColor(c).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
                                colorMode.liveHueA = Float(h)
                                colorMode.liveSaturation = Float(s)
                                colorMode.liveBrightness = Float(v)
                            }
                        )).labelsHidden().frame(width: 44, height: 44)
                    }
                    VStack(spacing: 4) {
                        Text("Color B").font(.caption).foregroundColor(.secondary)
                        ColorPicker("", selection: Binding(
                            get: { Color(hue: Double(colorMode.liveHueB), saturation: Double(colorMode.liveSaturation), brightness: Double(colorMode.liveBrightness)) },
                            set: { c in
                                var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
                                UIColor(c).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
                                colorMode.liveHueB = Float(h)
                            }
                        )).labelsHidden().frame(width: 44, height: 44)
                    }
                    // Gradient preview A→B
                    VStack(spacing: 2) {
                        Text("Preview").font(.caption).foregroundColor(.secondary)
                        LinearGradient(
                            colors: liveGradientColors(mode: colorMode),
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(height: 28).cornerRadius(4)
                    }
                }
                ParameterSlider(title: "Threshold", value: $colorMode.liveThreshold, range: 0...0.8, format: "%.2f")
                ParameterSlider(title: "Release Speed", value: $colorMode.liveRelease, range: 0.01...0.4, format: "%.3f/frame")
            }
        }
    }
}

private func liveGradientColors(mode: ColorMode) -> [Color] {
    let steps = 8
    return (0..<steps).map { i in
        let t = Double(i) / Double(steps - 1)
        let hA = Double(mode.liveHueA)
        let hB = Double(mode.liveHueB)
        var dh = hB - hA
        if dh > 0.5 { dh -= 1 }
        if dh < -0.5 { dh += 1 }
        let h = (hA + dh * t).truncatingRemainder(dividingBy: 1)
        return Color(hue: h < 0 ? h + 1 : h,
                     saturation: Double(mode.liveSaturation),
                     brightness: Double(mode.liveBrightness))
    }
}

struct GradientEditor: View {
    @Binding var stops: [GradientStop]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gradient Stops")
                .font(.headline)
            
            ForEach($stops) { $stop in
                HStack {
                    Circle()
                        .fill(stop.color)
                        .frame(width: 30, height: 30)
                    
                    VStack {
                        Slider(value: $stop.hue, in: 0...1)
                        Slider(value: $stop.position, in: 0...1)
                    }
                    
                    Button {
                        stops.removeAll { $0.id == stop.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            
            Button {
                stops.append(GradientStop(
                    position: 1.0,
                    hue: Float.random(in: 0...1),
                    saturation: 1.0,
                    brightness: 1.0
                ))
            } label: {
                Label("Add Stop", systemImage: "plus.circle.fill")
            }
        }
    }
}

// MARK: - Physics Tab

struct PhysicsTab: View {
    @Binding var physics: PhysicsParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Gravity", icon: "arrow.down.circle.fill")
            
            ParameterSlider(
                title: "Gravity Y",
                value: Binding(
                    get: { physics.gravity.y },
                    set: { physics.gravity.y = $0 }
                ),
                range: -0.01...0.01,
                format: "%.4f"
            )
            
            SectionHeader(title: "Turbulence", icon: "wind")
            
            ParameterSlider(
                title: "Amount",
                value: $physics.turbulence,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            ParameterSlider(
                title: "Scale",
                value: $physics.turbulenceScale,
                range: 0.1...10,
                format: "%.1f"
            )
            
            SectionHeader(title: "Forces", icon: "atom")
            
            ParameterSlider(
                title: "Drag",
                value: $physics.drag,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            ParameterSlider(
                title: "Velocity Inherit",
                value: $physics.velocityInherit,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            ParameterSlider(
                title: "Attraction",
                value: $physics.attract,
                range: -1...1,
                format: "%.2f"
            )
        }
    }
}

// MARK: - Shared Components

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.headline)
        }
        .padding(.top, 8)
    }
}

struct ParameterSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String
    var multiplier: Float = 1
    
    var formattedValue: String {
        if format.contains("%@") || format == "Permanent" && value == 0 {
            return format
        }
        return String(format: format, value * multiplier)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(formattedValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Preview

struct BrushPreviewView: View {
    let preset: BrushDefinition
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                // Draw preview stroke
                let path = Path { p in
                    let y = size.height / 2
                    p.move(to: CGPoint(x: 20, y: y))
                    
                    for i in 0..<100 {
                        let x = 20 + (size.width - 40) * CGFloat(i) / 100
                        let wave = sin(CGFloat(i) * 0.1) * 10 * CGFloat(preset.stroke.jitter)
                        p.addLine(to: CGPoint(x: x, y: y + wave))
                    }
                }
                
                context.stroke(
                    path,
                    with: .color(.white),
                    lineWidth: CGFloat(preset.geometry.baseSize * 1000)
                )
            }
        }
    }
}

#Preview {
    BrushStudioView(presetManager: BrushPresetManager())
}
