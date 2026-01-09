import SwiftUI
import Photos

@main
struct GyroAR3DPaintApp: App {
    @StateObject private var performanceManager = PerformanceManager.shared
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
                } else {
                    ContentView(shouldExit: .constant(false))
                        .environmentObject(performanceManager)
                }
            }
        }
    }
}
