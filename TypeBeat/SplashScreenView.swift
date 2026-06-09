import SwiftUI

/// Brand mark launch flourish, rendered as a stack of concentric vector
/// strokes so the silhouette is sharp at any size and the gradient screen
/// background bleeds through wherever the mark isn't.
///
/// The brand artwork is a chrome-shelled infinity with multiple distinct
/// rainbow rings nested inside it. Here that's reproduced by stacking five
/// strokes of the same lemniscate Path at decreasing line widths, so each
/// outer (wider) stroke shows through as a band on either side of the
/// inner (narrower) ones — like nested infinities of decreasing thickness.
///
/// Bands from outer to inner (visible band width ≈ (outer − inner) / 2):
///   • Chrome shell   (linear bevel gradient, widest)
///   • Ring 1         (angular rainbow, hue offset  0°)
///   • Ring 2         (angular rainbow, hue offset 72°)
///   • Ring 3         (angular rainbow, hue offset 144°)
///   • Core glint     (thin, .screen-blended, hue offset 216°)
///
/// Plus a soft halo behind everything for atmospheric glow, and a
/// staged entrance: anticipation → strike (flash + spring) → bloom →
/// continuous breathing hover.
struct SplashScreenView: View {
    @State private var glowOpacity: Double = 0
    @State private var flashOpacity: Double = 0
    @State private var markScale: CGFloat = 0.45
    @State private var markRotation: Double = -22
    @State private var markOpacity: Double = 0
    @State private var trimEnd: CGFloat = 0
    @State private var breathScale: CGFloat = 1.0
    @State private var glowRadius: CGFloat = 0
    @State private var particleProgress: Double = 0
    @State private var sweepPhase: Double = 0

    /// Saturated brand rainbow — matches the artwork's chrome+ring palette.
    private let rainbow: [Color] = [
        Color(red: 1.00, green: 0.30, blue: 0.30),   // red
        Color(red: 1.00, green: 0.55, blue: 0.10),   // orange
        Color(red: 1.00, green: 0.90, blue: 0.20),   // yellow
        Color(red: 0.30, green: 0.95, blue: 0.45),   // green
        Color(red: 0.20, green: 0.90, blue: 0.95),   // cyan
        Color(red: 0.35, green: 0.45, blue: 1.00),   // blue
        Color(red: 0.75, green: 0.35, blue: 1.00),   // purple
        Color(red: 1.00, green: 0.40, blue: 0.85),   // magenta
        Color(red: 1.00, green: 0.30, blue: 0.30)    // back to red
    ]

    /// Chrome bevel — alternating highlights and shadows down the cap.
    private var chromeGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(white: 1.00), location: 0.00),
                .init(color: Color(white: 0.80), location: 0.20),
                .init(color: Color(white: 0.55), location: 0.45),
                .init(color: Color(white: 0.85), location: 0.60),
                .init(color: Color(white: 0.45), location: 0.85),
                .init(color: Color(white: 0.95), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func ringGradient(angleOffset: Double, animatedAngle: Double) -> AngularGradient {
        AngularGradient(
            colors: rainbow,
            center: .center,
            startAngle: .degrees(animatedAngle + angleOffset),
            endAngle: .degrees(animatedAngle + angleOffset + 360)
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.04, blue: 0.13),
                    Color(red: 0.07, green: 0.10, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TimelineView(.animation) { context in
                // 6-second hue rotation around the rainbow palette.
                let cycle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 6) / 6
                let angle = cycle * 360

                ZStack {
                    // Diffuse halo — soft rainbow glow behind the mark
                    InfinityShape()
                        .stroke(
                            ringGradient(angleOffset: 0, animatedAngle: angle),
                            style: StrokeStyle(lineWidth: 90, lineCap: .round)
                        )
                        .blur(radius: 50)
                        .opacity(glowOpacity * 0.65)

                    // Chrome shell — the thick silver outer ring
                    InfinityShape()
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            chromeGradient,
                            style: StrokeStyle(lineWidth: 54, lineCap: .round, lineJoin: .round)
                        )

                    // Ring 1 — first rainbow band inside the chrome
                    InfinityShape()
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            ringGradient(angleOffset: 0, animatedAngle: angle),
                            style: StrokeStyle(lineWidth: 42, lineCap: .round, lineJoin: .round)
                        )

                    // Ring 2 — second rainbow band, hue-offset
                    InfinityShape()
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            ringGradient(angleOffset: 72, animatedAngle: angle),
                            style: StrokeStyle(lineWidth: 30, lineCap: .round, lineJoin: .round)
                        )

                    // Ring 3 — third rainbow band
                    InfinityShape()
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            ringGradient(angleOffset: 144, animatedAngle: angle),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
                        )

                    // Core glint — thin bright highlight riding the center
                    InfinityShape()
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            ringGradient(angleOffset: 216, animatedAngle: angle),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .blendMode(.screen)
                        .opacity(0.95)

                    // Light streak — a short bright segment that races
                    // around the lemniscate during bloom and onward.
                    let streakLen = 0.08
                    let streakStart = sweepPhase.truncatingRemainder(dividingBy: 1.0)
                    let streakEnd = streakStart + streakLen
                    Group {
                        if streakEnd <= 1.0 {
                            InfinityShape()
                                .trim(from: streakStart, to: streakEnd)
                                .stroke(
                                    Color.white,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                        } else {
                            // wraps around the end of the path
                            InfinityShape()
                                .trim(from: streakStart, to: 1.0)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            InfinityShape()
                                .trim(from: 0, to: streakEnd - 1.0)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        }
                    }
                    .blur(radius: 3)
                    .blendMode(.screen)
                    .opacity(markOpacity * 0.9)
                }
                .frame(width: 260, height: 230)
            }
            .scaleEffect(markScale * breathScale)
            .rotationEffect(.degrees(markRotation))
            .opacity(markOpacity)
            .shadow(color: .blue.opacity(0.5), radius: glowRadius, y: 10)
            .shadow(color: .purple.opacity(0.35), radius: glowRadius * 1.8)
            .accessibilityLabel("app.name".localized)

            // Particle burst — radiates outward from center on strike
            ParticleBurst(progress: particleProgress, colors: rainbow)
                .frame(width: 360, height: 360)
                .allowsHitTesting(false)
                .blendMode(.screen)

            // White punch-in flash on strike
            Color.white
                .opacity(flashOpacity)
                .blendMode(.screen)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear(perform: runSequence)
    }

    private func runSequence() {
        // Stage 1 — anticipation (0.00–0.30s): halo blooms out of black
        withAnimation(.easeOut(duration: 0.3)) {
            glowOpacity = 0.30
        }

        // Stage 2 — strike (0.30–0.40s): flash + spring in + draw on +
        // particle burst from center
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeIn(duration: 0.05)) {
                flashOpacity = 0.80
                markOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.05)) {
                flashOpacity = 0
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) {
                markScale = 1.0
                markRotation = 0
            }
            withAnimation(.easeOut(duration: 0.95).delay(0.05)) {
                trimEnd = 1.0
            }
            withAnimation(.easeOut(duration: 1.3).delay(0.05)) {
                particleProgress = 1.0
            }
            // Light streak: race around the path ~1.8s per loop, forever
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                sweepPhase = 1.0
            }
        }

        // Stage 3 — bloom (0.40–1.00s): halo and outer glow expand
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            withAnimation(.easeOut(duration: 0.7)) {
                glowOpacity = 1.0
                glowRadius = 36
            }
        }

        // Stage 4 — hover (1.00s+): continuous slow breathing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breathScale = 1.035
            }
        }
    }
}

/// Radial particle burst from the center. `progress` 0→1 drives expansion
/// and fade — particles start at the origin and fly outward, picking up
/// hue from the provided palette as they radiate.
private struct ParticleBurst: View {
    let progress: Double
    let colors: [Color]

    private let count = 18
    private let maxDistance: Double = 220

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let eased = 1 - pow(1 - progress, 2.4)  // easeOut curve

            for i in 0..<count {
                let angle = (Double(i) / Double(count)) * 2 * .pi
                let jitter = sin(Double(i) * 12.34) * 18  // deterministic offset
                let distance = (maxDistance + jitter) * eased

                let x = center.x + cos(angle) * distance
                let y = center.y + sin(angle) * distance

                let opacity = max(0, 1 - progress) * 0.9
                let radius = (1.0 - progress * 0.7) * 5
                let rect = CGRect(
                    x: x - radius,
                    y: y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                let color = colors[i % colors.count]
                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
            }
        }
    }
}

/// Bernoulli lemniscate — the mathematically clean infinity curve.
/// `sx` and `sy` independently scale the horizontal and vertical extents
/// so the shape can be squished/stretched away from its natural ~2.6:1
/// bounding aspect.
private struct InfinityShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let sx = rect.width * 0.46    // horizontal extent
        let sy = rect.height * 1.10   // vertical extent (stretched well past
                                      // the natural ratio for a less elongated,
                                      // more vertical infinity silhouette)

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
