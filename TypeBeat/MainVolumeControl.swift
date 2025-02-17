//
//  MainVolumeControl.swift
//  ClubSound
//
//  Created by Kirk Elliott on 12/6/24.
//


import SwiftUI

struct MainVolumeControl: View {
    @Binding var mainVolume: Float
    @ObservedObject var audioManager: AudioManager
    @State private var progress: Double = 0
    
    var body: some View {
        HStack(spacing: 4) {
            // BPM Circle with progress ring
            ZStack {
                // Background track (iOS system gray)
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 2)
                    .frame(width: 39, height: 39)
                
                // Progress ring (iOS blue)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color.accentColor, lineWidth: 2)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 39, height: 39)
                    .animation(.linear(duration: 1/30), value: progress)
                
                // Center circle
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 35, height: 35)
                    .overlay(
                        Text("\(Int(audioManager.bpm))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    )
            }
            .padding(5)
            .onAppear {
                startProgressUpdates()
            }

            Text("main.volume".localized)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)
                .accessibilityIdentifier("Main Volume")
            Spacer()

            Slider(value: $mainVolume, in: 0...1)
                .accentColor(.accentColor)
                .frame(width: 150)
                .onChange(of: mainVolume) { newValue, _ in
                    audioManager.setMasterVolume(newValue)
                }
                .padding(8)
                .accessibilityIdentifier("Main Volume Slider")
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6).opacity(0.4))
        )
        .padding(.vertical, -2)
    }
    
    private func startProgressUpdates() {
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { _ in
            if audioManager.isPlaying {
                progress = audioManager.loopProgress()
            } else {
                progress = 0
            }
        }
    }
}
