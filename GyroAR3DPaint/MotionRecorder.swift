import SwiftUI
import Combine

// MARK: - Gyrosaur Motion Timeline (.gmt) format

/// One sampled frame of all available motion sources.
/// Values normalised: angles roughly -1…1 (radians / π), open/blink 0…1.
struct GyrosaurMotionFrame: Codable {
    var time: Double          // seconds from recording start
    // Phone
    var phoneRoll:  Float;  var phonePitch: Float;  var phoneYaw: Float
    // AirPods
    var airRoll:    Float;  var airPitch:  Float;   var airYaw:   Float
    // Watch
    var watchRoll:  Float;  var watchPitch: Float;  var watchYaw: Float
    // Face
    var mouthOpen:  Float   // 0…1
    var jawLeft:    Float   // -1…1
    var browInner:  Float   // 0…1
    var eyeBlinkL:  Float   // 0…1
    var eyeBlinkR:  Float   // 0…1
    // Derived
    var colorHue:   Float   // 0…1 hue active at record time
}

extension GyrosaurMotionFrame {
    static var zero: GyrosaurMotionFrame {
        .init(time: 0,
              phoneRoll: 0, phonePitch: 0, phoneYaw: 0,
              airRoll: 0,   airPitch: 0,   airYaw: 0,
              watchRoll: 0, watchPitch: 0, watchYaw: 0,
              mouthOpen: 0, jawLeft: 0,
              browInner: 0, eyeBlinkL: 0, eyeBlinkR: 0,
              colorHue: 0)
    }
}

/// Metadata + frames for one recorded clip.
struct GyrosaurMotionClip: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var duration: Double      // seconds
    var fps: Double
    var sourceFlags: [String] // ["phone","airpods","watch","face"]
    var createdAt: Date = Date()
    var frames: [GyrosaurMotionFrame]
}

// MARK: - Playback parameter mapping

enum MotionPlaybackTarget: String, CaseIterable, Codable {
    case none          = "None"
    case drawDirection = "Draw Direction"
    case brushSize     = "Brush Size"
    case opacity       = "Opacity"
    case hueShift      = "Hue Shift"
    case colorIndex    = "Color Index"
    case distance      = "Drawing Distance"
    case mouthGate     = "Mouth Gate"
}

enum MotionPlaybackAxis: String, CaseIterable, Codable {
    case phoneRoll  = "Phone Roll"
    case phonePitch = "Phone Pitch"
    case phoneYaw   = "Phone Yaw"
    case airRoll    = "AirPods Roll"
    case airPitch   = "AirPods Pitch"
    case watchRoll  = "Watch Roll"
    case watchPitch = "Watch Pitch"
    case mouthOpen  = "Mouth Open"
    case jawLeft    = "Jaw Left/Right"
    case colorHue   = "Color Hue"
}

struct MotionPlaybackMapping: Codable {
    var axis:   MotionPlaybackAxis   = .phoneRoll
    var target: MotionPlaybackTarget = .hueShift
    var scale:  Float                = 1.0
    var offset: Float                = 0.0
}

// MARK: - MotionRecorder

@MainActor
class MotionRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var recordingSeconds: Double = 0
    @Published var clips: [GyrosaurMotionClip] = []

    @Published var isPlaying = false
    @Published var playbackClipIndex: Int? = nil
    @Published var playbackProgress: Double = 0
    @Published var loopPlayback: Bool = true
    @Published var playbackMappings: [MotionPlaybackMapping] = [
        MotionPlaybackMapping(axis: .phoneRoll, target: .drawDirection),
        MotionPlaybackMapping(axis: .mouthOpen, target: .mouthGate)
    ]
    @Published var liveFrame: GyrosaurMotionFrame = .zero

    private var recordBuffer: [GyrosaurMotionFrame] = []
    private var recordStartTime: Double = 0
    private let sampleHz: Double = 60

    private var playTimer: Timer?
    private var playFrameIndex: Int = 0

    private var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GyrosaurTimeline", isDirectory: true)
    }

    init() {
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadClipsIndex()
    }

    // MARK: Recording

    func recordFrame(phone: (Float,Float,Float), air: (Float,Float,Float),
                     watch: (Float,Float,Float),
                     mouthOpen: Float, jawLeft: Float,
                     browInner: Float, eyeBlinkL: Float, eyeBlinkR: Float,
                     colorHue: Float) {
        guard isRecording else { return }
        let t = Date().timeIntervalSinceReferenceDate - recordStartTime
        let f = GyrosaurMotionFrame(
            time: t,
            phoneRoll: phone.0, phonePitch: phone.1, phoneYaw: phone.2,
            airRoll: air.0,     airPitch: air.1,     airYaw: air.2,
            watchRoll: watch.0, watchPitch: watch.1, watchYaw: watch.2,
            mouthOpen: mouthOpen, jawLeft: jawLeft,
            browInner: browInner, eyeBlinkL: eyeBlinkL, eyeBlinkR: eyeBlinkR,
            colorHue: colorHue)
        recordBuffer.append(f)
        recordingSeconds = t
    }

    func startRecording() {
        recordBuffer = []
        recordStartTime = Date().timeIntervalSinceReferenceDate
        recordingSeconds = 0
        isRecording = true
    }

    func stopRecording(name: String = "Clip") {
        isRecording = false
        guard !recordBuffer.isEmpty else { return }
        var flags = ["phone"]
        if recordBuffer.contains(where: { $0.airRoll != 0 }) { flags.append("airpods") }
        if recordBuffer.contains(where: { $0.watchRoll != 0 }) { flags.append("watch") }
        if recordBuffer.contains(where: { $0.mouthOpen != 0 }) { flags.append("face") }
        let clip = GyrosaurMotionClip(
            name: name, duration: recordBuffer.last?.time ?? 0,
            fps: sampleHz, sourceFlags: flags, frames: recordBuffer)
        clips.append(clip)
        saveClip(clip)
        recordBuffer = []
    }

    // MARK: Playback

    func startPlayback(clipIndex: Int) {
        guard clipIndex < clips.count else { return }
        playbackClipIndex = clipIndex
        playFrameIndex = 0
        isPlaying = true
        let frames = clips[clipIndex].frames
        playTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / sampleHz, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickPlayback(frames: frames) }
        }
    }

    func stopPlayback() {
        isPlaying = false
        playTimer?.invalidate(); playTimer = nil
        playbackProgress = 0; playFrameIndex = 0; liveFrame = .zero
    }

    private func tickPlayback(frames: [GyrosaurMotionFrame]) {
        guard isPlaying, !frames.isEmpty else { return }
        if playFrameIndex >= frames.count {
            if loopPlayback { playFrameIndex = 0 } else { stopPlayback(); return }
        }
        liveFrame = frames[playFrameIndex]
        playbackProgress = liveFrame.time / (frames.last?.time ?? 1)
        playFrameIndex += 1
    }

    func applyToEngine(_ engine: DrawingEngine) {
        for m in playbackMappings {
            let raw = axisValue(m.axis)
            let v = raw * m.scale + m.offset
            switch m.target {
            case .none: break
            case .drawDirection: break
            case .brushSize:
                engine.brushSize = engine.brushSizeMin + max(0,min(1,(v+1)/2)) * (engine.brushSizeMax - engine.brushSizeMin)
            case .opacity:  engine.opacity = max(0.05, min(1,(v+1)/2))
            case .hueShift: engine.hueShift = v * 0.5
            case .colorIndex:
                engine.selectedColorIndex = Int(max(0,min(1,(v+1)/2)) * Float(engine.availableColors.count - 1))
            case .distance: engine.drawingDistanceOffset = max(0, min(1,(v+1)/2))
            case .mouthGate: engine.micGateActive = v > 0.15
            }
        }
    }

    private func axisValue(_ axis: MotionPlaybackAxis) -> Float {
        switch axis {
        case .phoneRoll:  return liveFrame.phoneRoll
        case .phonePitch: return liveFrame.phonePitch
        case .phoneYaw:   return liveFrame.phoneYaw
        case .airRoll:    return liveFrame.airRoll
        case .airPitch:   return liveFrame.airPitch
        case .watchRoll:  return liveFrame.watchRoll
        case .watchPitch: return liveFrame.watchPitch
        case .mouthOpen:  return liveFrame.mouthOpen
        case .jawLeft:    return liveFrame.jawLeft
        case .colorHue:   return liveFrame.colorHue
        }
    }

    // MARK: Persistence

    private struct ClipMeta: Codable {
        var id: UUID; var name: String; var duration: Double
        var createdAt: Date; var sourceFlags: [String]
    }

    private func saveClip(_ clip: GyrosaurMotionClip) {
        let url = storageURL.appendingPathComponent("\(clip.id.uuidString).gmt")
        if let data = try? JSONEncoder().encode(clip) { try? data.write(to: url) }
        saveClipsIndex()
    }

    private func saveClipsIndex() {
        let metas = clips.map { ClipMeta(id: $0.id, name: $0.name, duration: $0.duration, createdAt: $0.createdAt, sourceFlags: $0.sourceFlags) }
        let url = storageURL.appendingPathComponent("index.json")
        if let data = try? JSONEncoder().encode(metas) { try? data.write(to: url) }
    }

    private func loadClipsIndex() {
        let url = storageURL.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url),
              let metas = try? JSONDecoder().decode([ClipMeta].self, from: data) else { return }
        clips = metas.compactMap { meta -> GyrosaurMotionClip? in
            let u = storageURL.appendingPathComponent("\(meta.id.uuidString).gmt")
            guard let d = try? Data(contentsOf: u) else { return nil }
            return try? JSONDecoder().decode(GyrosaurMotionClip.self, from: d)
        }
    }

    func deleteClip(at offsets: IndexSet) {
        for i in offsets {
            let u = storageURL.appendingPathComponent("\(clips[i].id.uuidString).gmt")
            try? FileManager.default.removeItem(at: u)
        }
        clips.remove(atOffsets: offsets)
        saveClipsIndex()
    }
}

// MARK: - MotionRecorderView

struct MotionRecorderView: View {
    @ObservedObject var recorder: MotionRecorder
    @State private var newClipName = ""
    @State private var showNamePrompt = false
    @State private var showMappingEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "record.circle").foregroundColor(.red)
                Text("Motion Timeline")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Button { showMappingEditor = true } label: {
                    Image(systemName: "slider.horizontal.3").foregroundColor(.cyan)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.07))

            Divider().background(Color.white.opacity(0.1))

            // Record row
            HStack(spacing: 12) {
                if recorder.isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                            .opacity(recorder.recordingSeconds.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.3)
                        Text(String(format: "%.1fs", recorder.recordingSeconds))
                            .font(.system(size: 12, design: .monospaced)).foregroundColor(.red)
                    }
                    Spacer()
                    Button { showNamePrompt = true } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.red.opacity(0.7)).cornerRadius(8)
                    }
                } else {
                    Button { recorder.startRecording() } label: {
                        Label("Record", systemImage: "record.circle.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.red.opacity(0.7)).cornerRadius(8)
                    }
                    Spacer()
                    Toggle("Loop", isOn: $recorder.loopPlayback)
                        .toggleStyle(.button).font(.system(size: 11)).tint(.cyan)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider().background(Color.white.opacity(0.1))

            // Clips list
            if recorder.clips.isEmpty {
                Text("No recordings yet")
                    .font(.system(size: 11)).foregroundColor(.gray).padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(recorder.clips.enumerated()), id: \.element.id) { idx, clip in
                            ClipRowView(
                                clip: clip,
                                isPlaying: recorder.isPlaying && recorder.playbackClipIndex == idx,
                                progress: (recorder.isPlaying && recorder.playbackClipIndex == idx) ? recorder.playbackProgress : nil,
                                onPlay: {
                                    if recorder.isPlaying && recorder.playbackClipIndex == idx {
                                        recorder.stopPlayback()
                                    } else { recorder.stopPlayback(); recorder.startPlayback(clipIndex: idx) }
                                },
                                onDelete: { recorder.deleteClip(at: IndexSet(integer: idx)) }
                            )
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))
        .sheet(isPresented: $showNamePrompt) {
            ClipNamePrompt(name: $newClipName) {
                recorder.stopRecording(name: newClipName.isEmpty ? "Clip \(recorder.clips.count + 1)" : newClipName)
                newClipName = ""; showNamePrompt = false
            }
        }
        .sheet(isPresented: $showMappingEditor) {
            PlaybackMappingEditor(mappings: $recorder.playbackMappings)
        }
    }
}

struct ClipRowView: View {
    let clip: GyrosaurMotionClip
    let isPlaying: Bool
    let progress: Double?
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundColor(isPlaying ? .orange : .cyan)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.07)).cornerRadius(7)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.name).font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                HStack(spacing: 6) {
                    Text(String(format: "%.1fs", clip.duration))
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                    ForEach(clip.sourceFlags, id: \.self) { flag in
                        Text(flag).font(.system(size: 8, weight: .bold))
                            .foregroundColor(.cyan.opacity(0.7))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.cyan.opacity(0.1)).cornerRadius(3)
                    }
                }
                if let p = progress { ProgressView(value: p).tint(.orange).frame(height: 2) }
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 11)).foregroundColor(.red.opacity(0.6))
            }
        }
        .padding(8)
        .background(isPlaying ? Color.orange.opacity(0.1) : Color.white.opacity(0.04))
        .cornerRadius(8)
    }
}

struct ClipNamePrompt: View {
    @Binding var name: String
    let onConfirm: () -> Void
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Name this recording").font(.headline)
                TextField("e.g. Head tilt right", text: $name).textFieldStyle(.roundedBorder).padding(.horizontal)
                Button("Save", action: onConfirm).buttonStyle(.borderedProminent)
            }
            .padding().navigationTitle("Save Clip").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

struct PlaybackMappingEditor: View {
    @Binding var mappings: [MotionPlaybackMapping]
    var body: some View {
        NavigationView {
            List {
                ForEach(mappings.indices, id: \.self) { i in
                    Section("Mapping \(i + 1)") {
                        Picker("Axis", selection: $mappings[i].axis) {
                            ForEach(MotionPlaybackAxis.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        Picker("Target", selection: $mappings[i].target) {
                            ForEach(MotionPlaybackTarget.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        HStack {
                            Text("Scale"); Spacer()
                            Slider(value: $mappings[i].scale, in: -3...3)
                            Text(String(format: "%.1f", mappings[i].scale))
                                .font(.system(.caption, design: .monospaced))
                        }
                        HStack {
                            Text("Offset"); Spacer()
                            Slider(value: $mappings[i].offset, in: -1...1)
                            Text(String(format: "%.2f", mappings[i].offset))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("Playback Mappings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("+ Add") { mappings.append(MotionPlaybackMapping()) }
                }
            }
        }
        .presentationDetents([.large])
    }
}
