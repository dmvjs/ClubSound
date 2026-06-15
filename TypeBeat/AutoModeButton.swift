import SwiftUI

/// Genius-AI-styled AutoDJ toggle: iridescent angular-gradient pill with
/// the AUTO label on the left and a black-thumb switch on the right.
/// Tapping flips `AutoDJ.isEnabled` — it does NOT start playback; the user
/// still has to press play. AutoDJ then adopts whatever's playing as its
/// initial pair. Disabled (desaturated + dimmed) when samples are queued
/// and auto is off, so it can't fight a manual selection.
struct AutoModeButton: View {
    @Bindable var audioManager: AudioManager
    private let height: CGFloat = 34

    var body: some View {
        let isActive = audioManager.autoDJ.isEnabled
        let isEnabled = audioManager.activeSamples.isEmpty || isActive

        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            audioManager.autoDJ.isEnabled.toggle()
        }) {
            HStack(spacing: 10) {
                Text("auto".localized)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundColor(.black)
                    .shadow(color: .white.opacity(0.45), radius: 1.5, x: 0, y: 0)
                    .lineLimit(1)

                switchControl(isActive: isActive)
            }
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(iridescentPill(isEnabled: isEnabled))
            .overlay(rimHighlight)
            .shadow(color: Color.purple.opacity(isActive ? 0.55 : 0.30), radius: isActive ? 12 : 6, x: 0, y: 4)
            .shadow(color: Color.pink.opacity(isActive ? 0.40 : 0.18), radius: isActive ? 16 : 8, x: 0, y: 6)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.35)
        .saturation(isEnabled ? 1.0 : 0.45)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
        .animation(.easeInOut, value: isEnabled)
        .accessibilityLabel("auto".localized)
        .accessibilityIdentifier("auto-mode-toggle")
    }

    // MARK: - Sub-views

    private func switchControl(isActive: Bool) -> some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.22))
                .overlay(Capsule().stroke(Color.white.opacity(0.30), lineWidth: 0.5))
                .frame(width: 34, height: 18)
            Circle()
                .fill(Color.black)
                .frame(width: 14, height: 14)
                .offset(x: isActive ? 8 : -8)
        }
    }

    /// Single slow rotation regardless of state — shimmer is ambient
    /// texture, not a state signal. Active vs inactive shows up in the
    /// thumb position, saturation, and chromatic glow intensity.
    @ViewBuilder
    private func iridescentPill(isEnabled: Bool) -> some View {
        TimelineView(.animation(paused: !isEnabled)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(t * 8)
            Capsule()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(red: 0.98, green: 0.45, blue: 0.85),  // pink
                            Color(red: 0.55, green: 0.40, blue: 0.95),  // purple
                            Color(red: 0.35, green: 0.75, blue: 0.98),  // cyan
                            Color(red: 0.99, green: 0.78, blue: 0.40),  // amber
                            Color(red: 0.98, green: 0.45, blue: 0.85),  // pink (loop)
                        ],
                        center: .center,
                        startAngle: angle,
                        endAngle: angle + .degrees(360)
                    )
                )
        }
    }

    private var rimHighlight: some View {
        Capsule()
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.45), .white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}
