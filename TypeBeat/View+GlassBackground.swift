import SwiftUI

extension View {
    /// Applies a Liquid Glass background within a rounded rectangle of the
    /// given radius. On iOS 26+ this uses the native `.glassEffect` material;
    /// older OSes fall back to a translucent gray fill that matches the
    /// inactive control-row buttons.
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.3))
            )
        }
    }

    /// Background for a circular toggle/control button. When `isActive`, fills
    /// with `activeColor`; otherwise renders Liquid Glass (iOS 26+) or the
    /// inactive-gray fallback.
    @ViewBuilder
    func circleControlBackground(isActive: Bool, activeColor: Color = .green) -> some View {
        if isActive {
            self.background(Circle().fill(activeColor))
        } else if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .circle)
        } else {
            self.background(Circle().fill(Color.gray.opacity(0.3)))
        }
    }
}
