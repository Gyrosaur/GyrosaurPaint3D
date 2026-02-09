import SwiftUI
import Photos

@main
struct GyroAR3DPaintApp: App {
    @StateObject private var performanceManager = PerformanceManager.shared
    @StateObject private var brushPresetManager = BrushPresetManager()
    @State private var selectedMode: AppMode? = nil
    @State private var showOnboarding = false
    
    init() {
        // Request photo library access at launch
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if !performanceManager.hasSelectedLevel {
                    PerformanceSelectionView(performanceManager: performanceManager) {
                        showOnboarding = false
                    }
                } else if selectedMode == nil {
                    ModeSelectionView(selectedMode: $selectedMode)
                } else if selectedMode == .brushStudio {
                    // Brush Studio mode
                    BrushStudioMode(
                        presetManager: brushPresetManager,
                        onExit: { selectedMode = nil }
                    )
                    .environmentObject(performanceManager)
                } else {
                    // AR Drawing mode (Real World)
                    ContentView(onExitToMenu: { selectedMode = nil })
                        .environmentObject(performanceManager)
                }
            }
        }
    }
}
