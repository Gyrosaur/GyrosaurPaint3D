import SwiftUI

struct InputSettingsView: View {
    @ObservedObject var manager: InputSettingsManager
    @ObservedObject var drawingEngine: DrawingEngine
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Draw Gate")) {
                    GateSourceRow(selected: $manager.drawGateSource,
                                  usedElsewhere: manager.usedSources.subtracting([manager.drawGateSource]))
                }
                ForEach(manager.allMappings, id: \.label) { item in
                    Section(header: Label(item.label, systemImage: item.icon).foregroundColor(.cyan)) {
                        MappingRow(mapping: item.binding,
                                   usedSources: manager.usedSources.subtracting([item.binding.wrappedValue.source]))
                    }
                }
                Section(header: Text("Camera Colors")) {
                    HStack {
                        Image(systemName: "camera.aperture").frame(width: 24).foregroundColor(.orange)
                        Text("Palette Mode")
                        Spacer()
                        Picker("", selection: $drawingEngine.cameraColorMode) {
                            ForEach(CameraColorMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle("Input Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { onDismiss?() } }
            }
        }
        .frame(maxWidth: 400)
    }
}

// MARK: - Tentacle Color Settings View
struct TentacleColorSettingsView: View {
    @ObservedObject var tc: TentacleColorController
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Source")) {
                    Picker("Color Source", selection: $tc.source) {
                        ForEach(TentacleColorSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.inline).labelsHidden()
                }
                if tc.source != .off {
                    Section(header: Text("Colors")) {
                        HStack {
                            Text("Color A (low)")
                            Spacer()
                            ColorPicker("", selection: $tc.colorA).labelsHidden()
                        }
                        HStack {
                            Text("Color B (high)")
                            Spacer()
                            ColorPicker("", selection: $tc.colorB).labelsHidden()
                        }
                        // Live preview
                        HStack(spacing: 0) {
                            ForEach(0..<20) { i in
                                let t = Float(i) / 19.0
                                Rectangle().fill(tc.color(for: t)).frame(height: 20)
                            }
                        }.cornerRadius(6).padding(.vertical, 4)
                    }
                    Section(header: Text("Dynamics")) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text("Threshold").font(.caption).foregroundColor(.secondary)
                                Spacer(); Text(String(format: "%.0f%%", tc.threshold * 100)).font(.system(size: 11, design: .monospaced)) }
                            Slider(value: $tc.threshold, in: 0...0.8).tint(.orange)
                            Text("Alle tämän: värillä A").font(.caption2).foregroundColor(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text("Release Speed").font(.caption).foregroundColor(.secondary)
                                Spacer(); Text(String(format: "%.0f%%/f", tc.releaseSpeed * 100)).font(.system(size: 11, design: .monospaced)) }
                            Slider(value: $tc.releaseSpeed, in: 0.01...0.5).tint(.cyan)
                            Text("Kuinka nopeasti palaa A:han").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Section(header: Text("Live Preview")) {
                        HStack {
                            Text("Current T")
                            Spacer()
                            Text(String(format: "%.2f", tc.currentT)).font(.system(size: 12, design: .monospaced))
                            Circle().fill(tc.currentColor).frame(width: 20, height: 20)
                        }
                    }
                }
            }
            .navigationTitle("Tentacle Color").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
