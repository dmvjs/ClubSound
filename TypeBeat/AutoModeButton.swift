import SwiftUI

struct AutoModeButton: View {
    @Bindable var audioManager: AudioManager
    let buttonSize: CGFloat

    var body: some View {
        let isActive = audioManager.autoDJ.isEnabled

        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            audioManager.autoDJ.isEnabled.toggle()
        } label: {
            Text("auto".localized)
                .font(.system(size: buttonSize * 0.30, weight: .heavy))
                .textCase(.uppercase)
                .foregroundColor(isActive ? .black : .white.opacity(0.6))
                .frame(width: buttonSize, height: buttonSize)
                .circleControlBackground(isActive: isActive, activeColor: .purple)
                .shadow(color: isActive ? .purple.opacity(0.4) : .clear, radius: 7, x: 0, y: 4)
        }
        .accessibilityLabel("auto".localized)
        .accessibilityIdentifier("auto-mode-toggle")
    }
}
