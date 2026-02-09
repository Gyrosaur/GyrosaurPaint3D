import SwiftUI

// MARK: - Presets Panel

struct PresetsPanel: View {
    @ObservedObject var presetManager: BrushPresetManager
    @State private var selectedCategory: BrushCategory = .basic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BrushCategory.allCases, id: \.self) { category in
                        CategoryChipButton(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }
            
            // Presets grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(presetManager.presets(for: selectedCategory)) { preset in
                    PresetCardButton(
                        preset: preset,
                        isSelected: presetManager.currentPreset.id == preset.id
                    ) {
                        presetManager.selectPreset(preset)
                    }
                }
            }
            
            // User presets section
            if !presetManager.userPresets.isEmpty {
                Divider().background(Color.white.opacity(0.2))
                
                Text("Custom Brushes")
                    .font(.headline)
                    .foregroundColor(.white)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(presetManager.userPresets) { preset in
                        PresetCardButton(
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
}

struct CategoryChipButton: View {
    let category: BrushCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 12))
                Text(category.rawValue)
                    .font(.system(size: 12))
            }
            .foregroundColor(isSelected ? .white : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color.white.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

struct PresetCardButton: View {
    let preset: BrushDefinition
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Preview icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))
                        .frame(height: 50)
                    
                    Image(systemName: preset.category.icon)
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Text(preset.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(8)
            .background(isSelected ? Color.blue.opacity(0.3) : Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Geometry Panel

struct GeometryPanel: View {
    @Binding var geometry: GeometryParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelHeader(title: "Shape", icon: "cube.fill")
            
            // Shape picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Shape Type")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Picker("Shape", selection: $geometry.shape) {
                    ForEach(ShapeType.allCases, id: \.self) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            StudioSlider(
                title: "Base Size",
                value: $geometry.baseSize,
                range: 0.002...0.05,
                format: "%.3f m"
            )
            
            StudioSlider(
                title: "Size Variation",
                value: $geometry.sizeVariation,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            StudioSlider(
                title: "Aspect Ratio",
                value: $geometry.aspectRatio,
                range: 0.1...10,
                format: "%.1f"
            )
            
            StudioStepper(
                title: "Segments",
                value: $geometry.segments,
                range: 3...32
            )
        }
    }
}

// MARK: - Stroke Panel

struct StrokePanel: View {
    @Binding var stroke: StrokeParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelHeader(title: "Stroke Behavior", icon: "scribble")
            
            StudioSlider(
                title: "Spacing",
                value: $stroke.spacing,
                range: 0.05...2,
                format: "%.2f"
            )
            
            StudioSlider(
                title: "Smoothing",
                value: $stroke.smoothing,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            PanelHeader(title: "Jitter", icon: "waveform.path.ecg")
            
            StudioSlider(
                title: "Jitter Amount",
                value: $stroke.jitter,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            StudioSlider(
                title: "Jitter Scale",
                value: $stroke.jitterScale,
                range: 0.1...5,
                format: "%.1f×"
            )
            
            PanelHeader(title: "Response", icon: "hand.draw.fill")
            
            StudioSlider(
                title: "Pressure Response",
                value: $stroke.pressureResponse,
                range: 0...2,
                format: "%.1f×"
            )
            
            StudioSlider(
                title: "Angle Follow",
                value: $stroke.angleFollow,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
        }
    }
}
import SwiftUI

// MARK: - Color Panel

struct ColorPanel: View {
    @Binding var colorMode: ColorMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelHeader(title: "Color Mode", icon: "paintpalette.fill")
            
            // Mode picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Mode")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Picker("Mode", selection: $colorMode.mode) {
                    ForEach(ColorModeType.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Mode-specific controls
            switch colorMode.mode {
            case .solid:
                Text("Uses the selected drawing color")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
                
            case .gradient:
                GradientEditorPanel(stops: $colorMode.gradientStops)
                
            case .rainbow:
                StudioSlider(
                    title: "Hue Cycles",
                    value: $colorMode.hueShiftOverStroke,
                    range: 0...5,
                    format: "%.1f cycles"
                )
                
                Text("Colors cycle through the rainbow along the stroke")
                    .font(.caption)
                    .foregroundColor(.gray)
                
            case .velocity:
                Text("Color changes based on drawing speed")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 4)
                
                Text("Slow = Blue → Fast = Red")
                    .font(.caption2)
                    .foregroundColor(.blue)
                
            case .noise:
                StudioSlider(
                    title: "Noise Scale",
                    value: $colorMode.noiseScale,
                    range: 0.1...10,
                    format: "%.1f"
                )
                
                StudioSlider(
                    title: "Noise Speed",
                    value: $colorMode.noiseSpeed,
                    range: 0...5,
                    format: "%.1f"
                )
                
            case .custom:
                Text("Custom scripted color mode (future)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Gradient Editor

struct GradientEditorPanel: View {
    @Binding var stops: [GradientStop]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gradient Stops")
                .font(.subheadline)
                .foregroundColor(.white)
            
            // Gradient preview
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        stops: stops.sorted { $0.position < $1.position }.map { stop in
                            Gradient.Stop(color: stop.color, location: CGFloat(stop.position))
                        },
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 30)
            
            // Stop list
            ForEach($stops) { $stop in
                HStack(spacing: 12) {
                    // Color preview
                    Circle()
                        .fill(stop.color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    
                    VStack(spacing: 4) {
                        // Hue slider
                        HStack {
                            Text("H")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .frame(width: 12)
                            Slider(value: $stop.hue, in: 0...1)
                                .tint(Color(hue: Double(stop.hue), saturation: 1, brightness: 1))
                        }
                        
                        // Position slider
                        HStack {
                            Text("P")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .frame(width: 12)
                            Slider(value: $stop.position, in: 0...1)
                                .tint(.white.opacity(0.5))
                        }
                    }
                    
                    // Delete button
                    if stops.count > 2 {
                        Button {
                            stops.removeAll { $0.id == stop.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red.opacity(0.7))
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            
            // Add stop button
            Button {
                let newStop = GradientStop(
                    position: 0.5,
                    hue: Float.random(in: 0...1),
                    saturation: 1.0,
                    brightness: 1.0
                )
                stops.append(newStop)
            } label: {
                Label("Add Color Stop", systemImage: "plus.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Physics Panel

struct PhysicsPanel: View {
    @Binding var physics: PhysicsParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelHeader(title: "Gravity", icon: "arrow.down.circle.fill")
            
            StudioSlider(
                title: "Gravity Y",
                value: Binding(
                    get: { physics.gravity.y },
                    set: { physics.gravity.y = $0 }
                ),
                range: -0.02...0.02,
                format: "%.4f"
            )
            
            PanelHeader(title: "Turbulence", icon: "wind")
            
            StudioSlider(
                title: "Amount",
                value: $physics.turbulence,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            StudioSlider(
                title: "Scale",
                value: $physics.turbulenceScale,
                range: 0.1...10,
                format: "%.1f"
            )
            
            PanelHeader(title: "Forces", icon: "atom")
            
            StudioSlider(
                title: "Drag",
                value: $physics.drag,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            StudioSlider(
                title: "Velocity Inherit",
                value: $physics.velocityInherit,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            StudioSlider(
                title: "Attraction",
                value: $physics.attract,
                range: -1...1,
                format: "%.2f"
            )
        }
    }
}

// MARK: - Emission Panel

struct EmissionPanel: View {
    @Binding var emission: EmissionParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelHeader(title: "Emission Rate", icon: "sparkles")
            
            StudioSlider(
                title: "Rate",
                value: $emission.rate,
                range: 0.1...10,
                format: "%.1f/unit"
            )
            
            StudioStepper(
                title: "Burst Count",
                value: $emission.burstCount,
                range: 1...20
            )
            
            StudioSlider(
                title: "Burst Spread",
                value: $emission.burstSpread,
                range: 0...0.1,
                format: "%.3f m"
            )
            
            PanelHeader(title: "Trail", icon: "wind")
            
            StudioStepper(
                title: "Trail Length",
                value: $emission.trailLength,
                range: 0...20
            )
            
            StudioSlider(
                title: "Trail Fade",
                value: $emission.trailFade,
                range: 0...1,
                format: "%.0f%%",
                multiplier: 100
            )
            
            PanelHeader(title: "Lifetime", icon: "timer")
            
            StudioSlider(
                title: "Lifetime",
                value: $emission.lifetime,
                range: 0...10,
                format: emission.lifetime == 0 ? "Permanent" : "%.1f s"
            )
            
            StudioSlider(
                title: "Fade In",
                value: $emission.fadeIn,
                range: 0...2,
                format: "%.2f s"
            )
            
            StudioSlider(
                title: "Fade Out",
                value: $emission.fadeOut,
                range: 0...2,
                format: "%.2f s"
            )
        }
    }
}


// MARK: - Shared UI Components

struct PanelHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(.top, 8)
    }
}

struct StudioSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String
    var multiplier: Float = 1
    
    var formattedValue: String {
        if format == "Permanent" && value == 0 {
            return "Permanent"
        }
        return String(format: format, value * multiplier)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(formattedValue)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .monospacedDigit()
            }
            
            Slider(value: $value, in: range)
                .tint(.blue)
        }
    }
}

struct StudioStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    if value > range.lowerBound { value -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(value > range.lowerBound ? .blue : .gray)
                }
                
                Text("\(value)")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 30)
                
                Button {
                    if value < range.upperBound { value += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(value < range.upperBound ? .blue : .gray)
                }
            }
        }
    }
}
