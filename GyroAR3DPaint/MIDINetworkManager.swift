import Foundation
import CoreMIDI
import CoreMotion

@MainActor
class MIDINetworkManager: ObservableObject {
    static let shared = MIDINetworkManager()
    
    @Published var isConnected = false
    @Published var isMIDIEnabled = false
    @Published var statusMessage = "Disconnected"
    @Published var targetHost = "192.168.1.100" // Default Logic Pro Mac IP
    @Published var targetPort: UInt16 = 5004 // Default MIDI network port
    
    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var virtualSource: MIDIEndpointRef = 0
    private var networkSession: MIDINetworkSession?
    
    // MIDI channel (1-16)
    var midiChannel: UInt8 = 1
    
    init() {
        setupMIDI()
    }
    
    private func setupMIDI() {
        var client = MIDIClientRef()
        let status = MIDIClientCreate("GyroAR3DPaint MIDI" as CFString, nil, nil, &client)
        
        if status == noErr {
            midiClient = client
            
            // Create output port
            var port = MIDIPortRef()
            MIDIOutputPortCreate(client, "GyroAR Output" as CFString, &port)
            outputPort = port
            
            // Create virtual source
            var source = MIDIEndpointRef()
            MIDISourceCreate(client, "GyroAR Virtual Out" as CFString, &source)
            virtualSource = source
            
            print("✅ MIDI Client created successfully")
        } else {
            print("❌ Failed to create MIDI client: \(status)")
        }
    }
    
    func connectToNetwork() {
        // Use built-in MIDI Network Session
        networkSession = MIDINetworkSession.default()
        networkSession?.isEnabled = true
        networkSession?.connectionPolicy = .anyone
        
        // Create a network host
        let host = MIDINetworkHost(name: "Logic Pro", address: targetHost, port: Int(targetPort))
        let connection = MIDINetworkConnection(host: host)
        
        if let session = networkSession {
            // Remove old connections
            for existingConnection in session.connections() {
                session.removeConnection(existingConnection)
            }
            
            // Add new connection
            if session.addConnection(connection) {
                isConnected = true
                statusMessage = "Connected to \(targetHost):\(targetPort)"
                print("✅ MIDI Network connected to \(targetHost):\(targetPort)")
            } else {
                isConnected = false
                statusMessage = "Failed to connect"
                print("❌ Failed to add MIDI network connection")
            }
        }
    }
    
    func disconnect() {
        if let session = networkSession {
            for connection in session.connections() {
                session.removeConnection(connection)
            }
            session.isEnabled = false
        }
        isConnected = false
        statusMessage = "Disconnected"
        print("🔌 MIDI Network disconnected")
    }
    
    // MARK: - Send MIDI Messages
    
    /// Send Control Change message
    /// - Parameters:
    ///   - controller: CC number (0-127)
    ///   - value: CC value (0-127)
    func sendCC(controller: UInt8, value: UInt8) {
        guard isMIDIEnabled, isConnected else { return }
        
        let channel = midiChannel - 1 // MIDI channels are 0-15 internally
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = 3
        packet.data.0 = 0xB0 | channel // Control Change + channel
        packet.data.1 = controller
        packet.data.2 = value
        
        sendPacket(packet)
    }
    
    /// Send Pitch Bend message
    /// - Parameter value: 14-bit value (0-16383, center = 8192)
    func sendPitchBend(value: UInt16) {
        guard isMIDIEnabled, isConnected else { return }
        
        let channel = midiChannel - 1
        let lsb = UInt8(value & 0x7F)
        let msb = UInt8((value >> 7) & 0x7F)
        
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = 3
        packet.data.0 = 0xE0 | channel // Pitch Bend + channel
        packet.data.1 = lsb
        packet.data.2 = msb
        
        sendPacket(packet)
    }
    
    /// Send Note On message
    func sendNoteOn(note: UInt8, velocity: UInt8) {
        guard isMIDIEnabled, isConnected else { return }
        
        let channel = midiChannel - 1
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = 3
        packet.data.0 = 0x90 | channel // Note On + channel
        packet.data.1 = note
        packet.data.2 = velocity
        
        sendPacket(packet)
    }
    
    /// Send Note Off message
    func sendNoteOff(note: UInt8) {
        guard isMIDIEnabled, isConnected else { return }
        
        let channel = midiChannel - 1
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = 3
        packet.data.0 = 0x80 | channel // Note Off + channel
        packet.data.1 = note
        packet.data.2 = 0
        
        sendPacket(packet)
    }
    
    private func sendPacket(_ packet: MIDIPacket) {
        var packetList = MIDIPacketList()
        packetList.numPackets = 1
        packetList.packet = packet
        
        // Send to network session destination endpoints
        let destinationCount = MIDIGetNumberOfDestinations()
        for i in 0..<destinationCount {
            let endpoint = MIDIGetDestination(i)
            MIDISend(outputPort, endpoint, &packetList)
        }
        
        // Also send to virtual source (for local testing)
        MIDIReceived(virtualSource, &packetList)
    }
    
    // MARK: - Motion Data Converters
    
    /// Convert gyro rotation rate to MIDI CC (0-127)
    /// - Parameter rotationRate: Radians per second (-π to π typically)
    /// - Returns: MIDI value 0-127
    func gyroToMIDI(_ rotationRate: Double) -> UInt8 {
        // Clamp to reasonable range (-3 to 3 rad/s)
        let clamped = max(-3.0, min(3.0, rotationRate))
        // Map to 0-127
        let normalized = (clamped + 3.0) / 6.0
        return UInt8(normalized * 127.0)
    }
    
    /// Convert acceleration to MIDI CC (0-127)
    /// - Parameter acceleration: G-force (-2 to 2 typically)
    /// - Returns: MIDI value 0-127
    func accelerationToMIDI(_ acceleration: Double) -> UInt8 {
        // Clamp to ±2G
        let clamped = max(-2.0, min(2.0, acceleration))
        // Map to 0-127
        let normalized = (clamped + 2.0) / 4.0
        return UInt8(normalized * 127.0)
    }
    
    /// Convert rotation to pitch bend (0-16383, center 8192)
    func rotationToPitchBend(_ rotation: Double) -> UInt16 {
        // Clamp to ±π
        let clamped = max(-Double.pi, min(Double.pi, rotation))
        // Map to 0-16383
        let normalized = (clamped + Double.pi) / (2.0 * Double.pi)
        return UInt16(normalized * 16383.0)
    }
}

// MARK: - MIDI CC Mappings (Standard)

enum MIDIControlChange: UInt8 {
    case modWheel = 1
    case breathController = 2
    case footController = 4
    case volume = 7
    case balance = 8
    case pan = 10
    case expression = 11
    case cutoff = 74      // Filter cutoff (standard)
    case resonance = 71   // Filter resonance (standard)
    case attack = 73
    case release = 72
    case reverb = 91
    case delay = 94
}
