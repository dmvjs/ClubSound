import SwiftUI

/// Brand mark launch flourish — staged: anticipation → strike → bloom → hover.
///
/// The infinity is rendered as a vector lemniscate (math-clean, sharp at any
/// size) with four stacked strokes:
///   1. Diffuse halo glow (wide blurred angular-gradient stroke)
///   2. Chrome outer shell (linear gradient white→gray→white for 3D bevel)
///   3. Rainbow inner band (continuously rotating angular gradient)
///   4. Bright glint core (thin stroke offset in phase, .screen-blended)
///
/// Sequence:
///   0.00s – 0.30s  anticipation: faint halo blooms from black
///   0.30s – 0.40s  strike: white flash + mark snaps in with overshoot
///                  spring + slight rotation correction; stroke trim 0→1
///   0.40s – 1.00s  bloom: halo fades to full, glow shadows expand
///   1.00s – ∞     hover: continuous chromatic shimmer + slow breathing scale
struct SplashScreenView: View {
    @State private var glowOpacity: Double = 0
    @State private var flashOpacity: Double = 0
    @State private var markScale: CGFloat = 0.4
    @State private var markRotation: Double = -25
    @State private var markOpacity: Double = 0
    @State private var trimEnd: CGFloat = 0
    @State private var breathScale: CGFloat = 1.0
    @State private var glowRadius: CGFloat = 0

    private let rainbow: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.15),
                    Color(red: 0.08, green: 0.11, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // The mark itself, scaled and shimmering
            TimelineView(.animation) { context in
                let cycle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 6) / 6
                let angle = cycle * 360

                ZStack {
                    // 1. Halo — diffuse rainbow glow behind the mark
                    InfinityShape()
                        .stroke(
                            AngularGradient(
                                colors: rainbow,
                                center: .center,
                                startAngle: .degrees(angle),
                                endAngle: .degrees(angle + 360)
                            ),
                            style: StrokeStyle(lineWidth: 70, lineCap: .round)
                        )
                        .blur(radius: 42)
                        .opacity(glowOpacity * 0.7)

                    // 2. Chrome outer shell
                    InfinityShape()
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white,
                                    .white.opacity(0.6),
                                    .gray.opacity(0.55),
                                    .white.opacity(0.9)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 32, lineCap: .round, lineJoin: .round)
                        )

                    // 3. Rainbow inner band
                    InfinityShape()
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            AngularGradient(
                                colors: rainbow,
                                center: .center,
                                startAngle: .degrees(angle),
                                endAngle: .degrees(angle + 360)
                            ),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round)
                        )

                    // 4. Bright glint core
                    InfinityShape()
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            AngularGradient(
                                colors: rainbow,
                                center: .center,
                                startAngle: .degrees(angle + 90),
                                endAngle: .degrees(angle + 450)
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .blendMode(.screen)
                        .opacity(0.9)
                }
                .frame(width: 300, height: 150)
            }
            .scaleEffect(markScale * breathScale)
            .rotationEffect(.degrees(markRotation))
            .opacity(markOpacity)
            .shadow(color: .blue.opacity(0.55), radius: glowRadius)
            .shadow(color: .purple.opacity(0.35), radius: glowRadius * 1.6)
            .accessibilityLabel("app.name".localized)

            // White flash that punches in on strike
            Color.white
                .opacity(flashOpacity)
                .blendMode(.screen)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear(perform: runSequence)
    }

    private func runSequence() {
        // Stage 1 — anticipation (0.00–0.30s): glow blooms from black
        withAnimation(.easeOut(duration: 0.3)) {
            glowOpacity = 0.25
        }

        // Stage 2 — strike (0.30–0.40s): white flash, mark snaps in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeIn(duration: 0.05)) {
                flashOpacity = 0.75
                markOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.05)) {
                flashOpacity = 0
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                markScale = 1.0
                markRotation = 0
            }
            withAnimation(.easeOut(duration: 0.85).delay(0.05)) {
                trimEnd = 1.0
            }
        }

        // Stage 3 — bloom (0.40–1.00s): halo + glow expand
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            withAnimation(.easeOut(duration: 0.6)) {
                glowOpacity = 1.0
                glowRadius = 28
            }
        }

        // Stage 4 — hover (1.00s+): continuous breathing scale
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathScale = 1.04
            }
        }
    }
}

/// Bernoulli lemniscate — the mathematically clean infinity curve.
/// Aspect ratio is 2:1 (wider than tall); frame the view accordingly.
private struct InfinityShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let sx = rect.width * 0.48
        let sy = rect.height * 0.48

        let steps = 240
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let denom = 1 + sin(t) * sin(t)
            let x = cx + sx * cos(t) / denom
            let y = cy + sy * cos(t) * sin(t) / denom
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

#Preview {
    SplashScreenView()
}
