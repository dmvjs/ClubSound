//
//  WakeLockControlViewModifier.swift
//  ClubSound
//
//  Created by Kirk Elliott on 12/3/24.
//

import SwiftUI
// Custom Modifier for Apple-Like Design
struct WakeLockControlViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            .shadow(radius: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.tertiaryLabel), lineWidth: 1)
            )
    }
}

extension View {
    func wakeLockControlStyle() -> some View {
        self.modifier(WakeLockControlViewModifier())
    }
}
