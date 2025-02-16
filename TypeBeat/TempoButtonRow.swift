import SwiftUI

struct TempoButtonRow: View {
    @ObservedObject var audioManager: AudioManager
    @StateObject private var wakeLockManager = WakeLockManager()
    @Environment(\.dismiss) private var dismiss
    @State private var showingLanguageSelection = false
    @State private var breatheScale: CGFloat = 1.0
    
    // Adjusted constants for better layout
    private let maxButtonSize: CGFloat = 56
    private let minButtonSpacing: CGFloat = 4
    private let horizontalPadding: CGFloat = 8
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - (horizontalPadding * 2)
            let totalButtons = 9
            let totalSpacing = minButtonSpacing * CGFloat(totalButtons - 1)
            let buttonSize = min(maxButtonSize, (availableWidth - totalSpacing) / CGFloat(totalButtons))
            
            HStack(spacing: minButtonSpacing) {
                ControlButtonGroup(
                    audioManager: audioManager,
                    wakeLockManager: wakeLockManager,
                    showingLanguageSelection: $showingLanguageSelection,
                    breatheScale: $breatheScale,
                    buttonSize: buttonSize
                )
                
                TempoButtonGroup(
                    audioManager: audioManager,
                    buttonSize: buttonSize
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
        .frame(height: maxButtonSize)
        .sheet(isPresented: $showingLanguageSelection) {
            LanguageSelectionView()
        }
    }
}

// Create separate files for these components:
// TempoButtonRow+ControlButtonGroup.swift
// TempoButtonRow+TempoButtonGroup.swift
