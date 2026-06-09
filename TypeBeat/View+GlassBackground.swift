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
}
