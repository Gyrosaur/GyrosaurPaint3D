import SwiftUI
import AVKit
import AVFoundation

// MARK: - Video Editor View
struct VideoEditorView: View {
    let videoURL: URL
    let onSave: (URL) -> Void
    let onCancel: () -> Void
    
    @State private var player: AVPlayer?
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 1
    @State private var videoDuration: Double = 1
    
    // Transform states
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Angle = .zero
    @State private var offset: CGSize = .zero
    @State private var selectedAspectRatio: AspectRatioOption = .original
    
    // Gesture states
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureRotation: Angle = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerBar
                
                // Video preview with transforms
                videoPreviewArea
                
                // Edit tools
                editToolsBar
                
                // Trim slider
                trimSlider
                
                // Bottom buttons
                bottomButtons
            }
        }
        .onAppear {
            setupPlayer()
        }
    }
    
    var headerBar: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .foregroundColor(.white)
            
            Spacer()
            
            Text("Edit Video")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            Button("Save") { saveVideo() }
                .foregroundColor(.cyan)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
    
    var videoPreviewArea: some View {
        GeometryReader { geo in
            ZStack {
                // Aspect ratio frame
                let frameSize = calculateFrameSize(in: geo.size)
                
                // Video player
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(width: frameSize.width, height: frameSize.height)
                        .scaleEffect(scale * gestureScale)
                        .rotationEffect(rotation + gestureRotation)
                        .offset(x: offset.width + gestureOffset.width,
                                y: offset.height + gestureOffset.height)
                        .clipShape(Rectangle())
                        .gesture(combinedGesture)
                }
                
                // Aspect ratio overlay
                Rectangle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: frameSize.width, height: frameSize.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 400)
    }
    
    var combinedGesture: some Gesture {
        SimultaneousGesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .updating($gestureScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        scale *= value
                    },
                RotationGesture()
                    .updating($gestureRotation) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        rotation += value
                    }
            ),
            DragGesture()
                .updating($gestureOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                }
        )
    }
    
    var editToolsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                // Aspect ratio buttons
                ForEach(AspectRatioOption.allCases, id: \.self) { ratio in
                    Button(action: { selectedAspectRatio = ratio }) {
                        VStack(spacing: 4) {
                            ratio.icon
                                .font(.system(size: 20))
                            Text(ratio.label)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(selectedAspectRatio == ratio ? .cyan : .white.opacity(0.7))
                        .frame(width: 50, height: 50)
                        .background(selectedAspectRatio == ratio ? Color.cyan.opacity(0.2) : Color.clear)
                        .cornerRadius(8)
                    }
                }
                
                Divider().frame(height: 40).background(Color.gray)
                
                // Reset button
                Button(action: resetTransforms) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 20))
                        Text("Reset")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.orange)
                    .frame(width: 50, height: 50)
                }
                
                // Rotate 90°
                Button(action: { rotation += .degrees(90) }) {
                    VStack(spacing: 4) {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 20))
                        Text("90°")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 50, height: 50)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 60)
        .background(Color.black.opacity(0.5))
    }
    
    var trimSlider: some View {
        VStack(spacing: 8) {
            Text("Trim")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
            // Dual thumb slider
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 40)
                    
                    // Selected range
                    Rectangle()
                        .fill(Color.cyan.opacity(0.5))
                        .frame(width: CGFloat(trimEnd - trimStart) * geo.size.width, height: 40)
                        .offset(x: CGFloat(trimStart) * geo.size.width)
                    
                    // Start handle
                    trimHandle(position: $trimStart, maxWidth: geo.size.width)
                        .offset(x: CGFloat(trimStart) * geo.size.width - 10)
                    
                    // End handle
                    trimHandle(position: $trimEnd, maxWidth: geo.size.width)
                        .offset(x: CGFloat(trimEnd) * geo.size.width - 10)
                }
            }
            .frame(height: 40)
            .cornerRadius(6)
            
            // Time labels
            HStack {
                Text(formatTime(trimStart * videoDuration))
                Spacer()
                Text(formatTime((trimEnd - trimStart) * videoDuration))
                    .foregroundColor(.cyan)
                Spacer()
                Text(formatTime(trimEnd * videoDuration))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.gray)
        }
        .padding()
    }
    
    func trimHandle(position: Binding<Double>, maxWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 20, height: 50)
            .cornerRadius(4)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newPos = Double(value.location.x / maxWidth)
                        position.wrappedValue = min(1, max(0, newPos))
                    }
            )
    }
    
    var bottomButtons: some View {
        HStack(spacing: 20) {
            Button(action: { player?.seek(to: .zero); player?.play() }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.3))
                    .clipShape(Circle())
            }
        }
        .padding()
    }
    
    // MARK: - Helper Functions
    
    func setupPlayer() {
        player = AVPlayer(url: videoURL)
        
        // Get duration
        let asset = AVAsset(url: videoURL)
        Task {
            if let duration = try? await asset.load(.duration) {
                await MainActor.run {
                    videoDuration = CMTimeGetSeconds(duration)
                }
            }
        }
    }
    
    func calculateFrameSize(in containerSize: CGSize) -> CGSize {
        let ratio = selectedAspectRatio.ratio
        let containerRatio = containerSize.width / containerSize.height
        
        if ratio > containerRatio {
            // Width limited
            return CGSize(width: containerSize.width * 0.9, height: containerSize.width * 0.9 / ratio)
        } else {
            // Height limited
            return CGSize(width: containerSize.height * 0.9 * ratio, height: containerSize.height * 0.9)
        }
    }
    
    func resetTransforms() {
        withAnimation(.spring(response: 0.3)) {
            scale = 1.0
            rotation = .zero
            offset = .zero
        }
    }
    
    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, frac)
    }
    
    func saveVideo() {
        // For now, just save original - full export with transforms would need AVFoundation export
        onSave(videoURL)
    }
}

// MARK: - Aspect Ratio Options
enum AspectRatioOption: CaseIterable {
    case original
    case ratio16x9
    case ratio9x16
    case ratio4x3
    case ratio3x4
    case ratio1x1
    
    var label: String {
        switch self {
        case .original: return "Original"
        case .ratio16x9: return "16:9"
        case .ratio9x16: return "9:16"
        case .ratio4x3: return "4:3"
        case .ratio3x4: return "3:4"
        case .ratio1x1: return "1:1"
        }
    }
    
    var icon: Image {
        switch self {
        case .original: return Image(systemName: "rectangle")
        case .ratio16x9: return Image(systemName: "rectangle.fill")
        case .ratio9x16: return Image(systemName: "rectangle.portrait.fill")
        case .ratio4x3: return Image(systemName: "rectangle.fill")
        case .ratio3x4: return Image(systemName: "rectangle.portrait.fill")
        case .ratio1x1: return Image(systemName: "square.fill")
        }
    }
    
    var ratio: CGFloat {
        switch self {
        case .original: return 16/9  // Default to 16:9
        case .ratio16x9: return 16/9
        case .ratio9x16: return 9/16
        case .ratio4x3: return 4/3
        case .ratio3x4: return 3/4
        case .ratio1x1: return 1
        }
    }
}
