import SwiftUI

struct MIDISettingsView: View {
    @ObservedObject var midiManager: MIDINetworkManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // Connection Status
                Section {
                    HStack {
                        Circle()
                            .fill(midiManager.isConnected ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        
                        Text(midiManager.statusMessage)
                            .font(.subheadline)
                        
                        Spacer()
                    }
                } header: {
                    Text("Connection Status")
                }
                
                // Network Settings
                Section {
                    HStack {
                        Text("Host IP")
                        Spacer()
                        TextField("192.168.1.100", text: $midiManager.targetHost)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("5004", value: $midiManager.targetPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Text("Network Settings")
                } footer: {
                    Text("Enter your Mac's IP address. Find it in System Preferences → Network. Default MIDI network port is 5004.")
                }
                
                // MIDI Channel
                Section {
                    Picker("MIDI Channel", selection: Binding(
                        get: { Int(midiManager.midiChannel) },
                        set: { midiManager.midiChannel = UInt8($0) }
                    )) {
                        ForEach(1...16, id: \.self) { channel in
                            Text("Channel \(channel)").tag(channel)
                        }
                    }
                } header: {
                    Text("MIDI Settings")
                }
                
                // Actions
                Section {
                    if midiManager.isConnected {
                        Button(role: .destructive) {
                            midiManager.disconnect()
                        } label: {
                            HStack {
                                Image(systemName: "network.slash")
                                Text("Disconnect")
                            }
                        }
                    } else {
                        Button {
                            midiManager.connectToNetwork()
                        } label: {
                            HStack {
                                Image(systemName: "network")
                                Text("Connect")
                            }
                        }
                    }
                    
                    Button {
                        testMIDI()
                    } label: {
                        HStack {
                            Image(systemName: "music.note")
                            Text("Test MIDI (Send C4)")
                        }
                    }
                    .disabled(!midiManager.isConnected)
                }
                
                // Instructions
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Setup Instructions:")
                            .font(.headline)
                        
                        Text("1. On Mac: Open 'Audio MIDI Setup' app")
                        Text("2. Window → Show MIDI Studio")
                        Text("3. Double-click 'Network' icon")
                        Text("4. Enable 'MIDI Network Setup'")
                        Text("5. Click '+' to add a new session")
                        Text("6. Your iPhone should appear in 'Directory'")
                        Text("7. Select it and click 'Connect'")
                        Text("8. In Logic Pro, create a new External MIDI track")
                        Text("9. Set input to 'Network' or 'GyroAR Virtual Out'")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("How to Connect")
                }
            }
            .navigationTitle("MIDI Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func testMIDI() {
        // Send a test note (Middle C, velocity 100)
        midiManager.sendNoteOn(note: 60, velocity: 100)
        
        // Send note off after 0.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            midiManager.sendNoteOff(note: 60)
        }
    }
}

#Preview {
    MIDISettingsView(midiManager: MIDINetworkManager.shared)
}
