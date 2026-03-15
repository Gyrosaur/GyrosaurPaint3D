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
