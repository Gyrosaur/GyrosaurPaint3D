import SwiftUI

enum AppMode: String, CaseIterable {
    case realWorld   = "Real World AR"
    case stillMode   = "Still Mode"
    case brushStudio = "Brush Studio"

    var icon: String {
        switch self {
        case .realWorld:   return "camera.fill"
        case .stillMode:   return "applewatch.radiowaves.left.and.right"
        case .brushStudio: return "paintbrush.pointed.fill"
        }
    }

    var description: String {
        switch self {
        case .realWorld:   return "Paint in your real environment"
        case .stillMode:   return "Watch, AirPods & face control — no touch"
        case .brushStudio: return "Create and customize brushes"
        }
    }

    var accentColor: Color {
        switch self {
        case .realWorld:   return .cyan
        case .stillMode:   return .purple
        case .brushStudio: return .orange
        }
    }
}

struct ModeSelectionView: View {
    @Binding var selectedMode: AppMode?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                VStack(spacing: 8) {
                    Text("GyroAR3DPaint")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Choose your canvas")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.top, 60)

                Spacer()

                VStack(spacing: 20) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        ModeButton(mode: mode) {
                            withAnimation(.spring(response: 0.3)) { selectedMode = mode }
                        }
                    }
                }

                Spacer()

                Text("Move your body — paint in 3D space")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 40)
            }
        }
    }
}

struct ModeButton: View {
    let mode: AppMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: mode.icon)
                    .font(.system(size: 26))
                    .foregroundColor(mode.accentColor)
                    .frame(width: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                    Text(mode.description)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(mode.accentColor.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .foregroundColor(.white)
        .padding(.horizontal, 24)
    }
}

#Preview {
    ModeSelectionView(selectedMode: .constant(nil))
}
