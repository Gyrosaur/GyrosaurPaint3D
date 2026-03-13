import SwiftUI

struct InputSettingsView: View {
    @ObservedObject var manager: InputSettingsManager
    @ObservedObject var drawingEngine: DrawingEngine
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Choose what each input controls. Each input can drive one parameter at a time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach(InputChannel.allCases, id: \.self) { channel in
                    Section {
                        HStack {
                            Image(systemName: channel.icon)
                                .frame(width: 24)
                                .foregroundColor(.cyan)
                            Picker(channel.rawValue, selection: manager.param(for: channel)) {
                                ForEach(InputParameter.allCases, id: \.self) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                        }
                    } header: {
                        Text(channel.rawValue)
                    }
                }

                Section {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 24)
                            .foregroundColor(.orange)
                        Text("Camera Palette Mode")
                        Spacer()
                        Picker("", selection: $drawingEngine.cameraColorMode) {
                            ForEach(CameraColorMode.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Camera Colors")
                }
            }
            .navigationTitle("Input Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss?() }
                }
            }
        }
        .frame(maxWidth: 400)
        .background(Color.black.opacity(0.95))
    }
}
