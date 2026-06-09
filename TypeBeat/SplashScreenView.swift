import SwiftUI

/// Brief launch flourish over the same dark background as the artwork.
/// Pulses, glows, and rotates the infinity mark for ~1.4s, then dissolves
/// into the live UI. Mounted as an overlay so the engine warms up underneath
/// and there's no functional delay being hidden.
struct SplashScreenView: View {
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0.0
    @State private var rotation: Double = -8
    @State private var glow: Double = 0.0

    var body: some View {
        ZStack {
            // Background tone tuned to the artwork's deep-blue bleed so the
            // image edges visually melt into the screen.
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.20),
                    Color(red: 0.10, green: 0.13, blue: 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft chromatic glow that breathes behind the mark.
            RadialGradient(
                colors: [
                    Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.45 * glow),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 260
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            Image("splash")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation))
                .opacity(opacity)
                .shadow(color: .blue.opacity(0.5), radius: 32, x: 0, y: 8)
                .shadow(color: .purple.opacity(0.35), radius: 60, x: 0, y: 0)
                .accessibilityLabel("app.name".localized)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
                rotation = 0
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glow = 1.0
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
