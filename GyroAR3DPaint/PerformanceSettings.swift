import SwiftUI
import UIKit

// MARK: - Performance Level
enum PerformanceLevel: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    var description: String {
        switch self {
        case .low: return "Best for older devices\niPhone 11 and earlier"
        case .medium: return "Balanced performance\niPhone 12-14"
        case .high: return "Maximum quality\niPhone 15 Pro and newer"
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "tortoise.fill"
        case .medium: return "hare.fill"
        case .high: return "bolt.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    // Frame rate target
    var targetFrameRate: Int {
        switch self {
        case .low: return 30
        case .medium: return 60
        case .high: return 120
        }
    }
    
    // Mesh segments for tube brushes
    var tubeSegments: Int {
        switch self {
        case .low: return 4
        case .medium: return 8
        case .high: return 12
        }
    }
    
    // Points to skip in rendering (1 = none, 2 = every other)
    var pointSkip: Int {
        switch self {
        case .low: return 3
        case .medium: return 2
        case .high: return 1
        }
    }
    
    // Max particles for particle brushes
    var maxParticles: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }
    
    // Enable complex brushes
    var enableComplexBrushes: Bool {
        switch self {
        case .low: return false
        case .medium: return true
        case .high: return true
        }
    }
    
    // Shadow/lighting quality
    var enableAdvancedLighting: Bool {
        switch self {
        case .low: return false
        case .medium: return false
        case .high: return true
        }
    }
}

// MARK: - Performance Manager
@MainActor
class PerformanceManager: ObservableObject {
    static let shared = PerformanceManager()
    
    @Published var currentLevel: PerformanceLevel {
        didSet {
            UserDefaults.standard.set(currentLevel.rawValue, forKey: "performanceLevel")
        }
    }
    
    @Published var hasSelectedLevel: Bool {
        didSet {
            UserDefaults.standard.set(hasSelectedLevel, forKey: "hasSelectedPerformanceLevel")
        }
    }
    
    @Published var autoDetectedLevel: PerformanceLevel
    
    init() {
        // Detect device capability first
        let detected = PerformanceManager.detectDeviceLevel()
        self.autoDetectedLevel = detected
        
        // Load saved preference or use auto-detected
        if let saved = UserDefaults.standard.string(forKey: "performanceLevel"),
           let level = PerformanceLevel(rawValue: saved) {
            self.currentLevel = level
        } else {
            self.currentLevel = detected
        }
        
        self.hasSelectedLevel = UserDefaults.standard.bool(forKey: "hasSelectedPerformanceLevel")
    }
    
    static func detectDeviceLevel() -> PerformanceLevel {
        // Get device model identifier
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        
        // iPhone identifiers mapping
        // iPhone 15 Pro/Pro Max = iPhone16,1 / iPhone16,2
        // iPhone 15/Plus = iPhone15,4 / iPhone15,5
        // iPhone 14 Pro/Pro Max = iPhone15,2 / iPhone15,3
        // iPhone 14/Plus = iPhone14,7 / iPhone14,8
        // iPhone 13 Pro/Pro Max = iPhone14,2 / iPhone14,3
        // iPhone 13/Mini = iPhone14,4 / iPhone14,5
        // iPhone 12 series = iPhone13,x
        // iPhone 11 series = iPhone12,x
        // etc.
        
        // Check for Pro models with ProMotion (120Hz)
        let proMotionDevices = [
            "iPhone14,2", "iPhone14,3",  // 13 Pro
            "iPhone15,2", "iPhone15,3",  // 14 Pro
            "iPhone16,1", "iPhone16,2",  // 15 Pro
            "iPhone17,1", "iPhone17,2",  // 16 Pro (future)
        ]
        
        if proMotionDevices.contains(identifier) {
            return .high
        }
        
        // Medium tier - iPhone 12-15 non-Pro
        let mediumDevices = [
            "iPhone13,1", "iPhone13,2", "iPhone13,3", "iPhone13,4",  // 12 series
            "iPhone14,4", "iPhone14,5", "iPhone14,7", "iPhone14,8",  // 13/14 non-Pro
            "iPhone15,4", "iPhone15,5",  // 15 non-Pro
        ]
        
        if mediumDevices.contains(identifier) {
            return .medium
        }
        
        // Also check by processor capability
        let processorCount = ProcessInfo.processInfo.processorCount
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        
        // 6+ cores and 6GB+ RAM = high capable
        if processorCount >= 6 && physicalMemory >= 6_000_000_000 {
            return .high
        }
        
        // 4+ cores and 4GB+ RAM = medium
        if processorCount >= 4 && physicalMemory >= 4_000_000_000 {
            return .medium
        }
        
        return .low
    }
    
    func resetToDefault() {
        currentLevel = autoDetectedLevel
    }
}

// MARK: - Performance Selection View (Onboarding)
struct PerformanceSelectionView: View {
    @ObservedObject var performanceManager: PerformanceManager
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Gyro AR Paint")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Select Performance Mode")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .padding(.top, 40)
                
                // Recommended badge
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Recommended for your device: \(performanceManager.autoDetectedLevel.rawValue)")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)
                
                // Performance options
                VStack(spacing: 16) {
                    ForEach(PerformanceLevel.allCases, id: \.self) { level in
                        PerformanceLevelCard(
                            level: level,
                            isSelected: performanceManager.currentLevel == level,
                            isRecommended: level == performanceManager.autoDetectedLevel
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                performanceManager.currentLevel = level
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Continue button
                Button(action: {
                    performanceManager.hasSelectedLevel = true
                    onComplete()
                }) {
                    HStack {
                        Text("Start Painting")
                            .font(.system(size: 18, weight: .semibold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .green],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Performance Level Card
struct PerformanceLevelCard: View {
    let level: PerformanceLevel
    let isSelected: Bool
    let isRecommended: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(level.color.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: level.icon)
                        .font(.system(size: 22))
                        .foregroundColor(level.color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(level.rawValue)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if isRecommended {
                            Text("Recommended")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(level.description)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isSelected ? 0.15 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? level.color : Color.clear, lineWidth: 2)
                    )
            )
        }
    }
}

// MARK: - Settings Panel (In-app)
struct PerformanceSettingsPanel: View {
    @ObservedObject var performanceManager: PerformanceManager
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Performance")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                }
            }
            
            Divider().background(Color.gray)
            
            // Current FPS indicator
            HStack {
                Text("Target FPS")
                    .foregroundColor(.gray)
                Spacer()
                Text("\(performanceManager.currentLevel.targetFrameRate)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            
            // Level selection
            VStack(spacing: 10) {
                ForEach(PerformanceLevel.allCases, id: \.self) { level in
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            performanceManager.currentLevel = level
                        }
                    }) {
                        HStack {
                            Image(systemName: level.icon)
                                .foregroundColor(level.color)
                                .frame(width: 24)
                            
                            Text(level.rawValue)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            if performanceManager.currentLevel == level {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            performanceManager.currentLevel == level ?
                            Color.white.opacity(0.1) : Color.clear
                        )
                        .cornerRadius(8)
                    }
                }
            }
            
            // Reset button
            Button(action: {
                performanceManager.resetToDefault()
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Recommended")
                }
                .font(.system(size: 13))
                .foregroundColor(.cyan)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(Color.black.opacity(0.95))
        .cornerRadius(20)
        .frame(width: 300)
    }
}
